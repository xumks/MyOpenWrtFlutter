import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/prefs_store.dart';
import '../models/models.dart';

/// 接口调用失败异常。
class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// OpenWrt ubus over HTTP（JSON-RPC 2.0）客户端。
///
/// 与 Android 版行为保持一致：
///  - POST /ubus，先 session.login 换取 session id；
///  - 会话失效（错误码 6）自动重新登录并重试一次；
///  - 写入 UCI 时通过 file.exec 逐个传参调用 /sbin/uci，避免 shell 转义问题。
class RouterApi {
  RouterApi._();

  static final RouterApi instance = RouterApi._();

  static const _emptySession = '00000000000000000000000000000000';
  static const _errAccessDenied = 6;

  static final _macPattern = RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');
  static final _ipv4Pattern = RegExp(
    r'^((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$',
  );

  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..badCertificateCallback = (cert, host, port) => true;

  RouterConnection _config = const RouterConnection();
  String? _sessionId;
  int _callId = 1;

  RouterConnection get config => _config;

  bool get hasSession => _sessionId != null && _sessionId!.isNotEmpty;

  /// 读取已保存的连接配置与会话（需要在 PrefsStore.init 之后调用）。
  void initFromSaved() {
    _config = PrefsStore.loadConfig();
    _sessionId = PrefsStore.sessionId;
  }

  Future<void> setConfig(RouterConnection config) async {
    _config = config;
    _sessionId = null;
    await PrefsStore.saveConfig(config);
    await PrefsStore.clearSession();
  }

  Future<void> logout() async {
    _sessionId = null;
    await PrefsStore.clearSession();
  }

  // ============================ 底层调用 ============================

  Future<Map<String, dynamic>> _post(
    Map<String, dynamic> body, {
    bool long = false,
  }) async {
    final timeout = Duration(seconds: long ? 60 : 20);
    final request = await _client.postUrl(Uri.parse('${_config.baseUrl}/ubus'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close().timeout(timeout);
    final text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw ApiException('HTTP ${response.statusCode}（请确认地址/端口正确）');
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('响应格式错误: $text');
    }
    return decoded;
  }

  Future<Map<String, dynamic>?> call(
    String object,
    String method, {
    Map<String, dynamic>? params,
    bool long = false,
    bool retried = false,
  }) async {
    await _ensureSession();
    final body = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': _callId++,
      'method': 'call',
      'params': [
        _sessionId,
        object,
        method,
        params ?? <String, dynamic>{},
      ],
    };

    final json = await _post(body, long: long);
    if (json.containsKey('error')) {
      final err = json['error'];
      final message = err is Map ? (err['message'] ?? '未知错误') : err;
      throw ApiException('ubus 错误: $message');
    }

    final result = json['result'];
    if (result is! List || result.isEmpty) {
      throw ApiException('响应缺少 result 字段');
    }

    final first = result[0];
    if (first is int) {
      if (first == _errAccessDenied) {
        if (retried) throw ApiException('ubus 权限不足（错误码 6）');
        _sessionId = null;
        await PrefsStore.clearSession();
        await login();
        return call(object, method,
            params: params, long: long, retried: true);
      }
      if (first != 0) {
        final detail = result.length > 1 ? '${result[1]}' : '';
        throw ApiException('ubus 返回错误码 $first${detail.isEmpty ? '' : ': $detail'}');
      }
      if (result.length > 1 && result[1] is Map) {
        return Map<String, dynamic>.from(result[1] as Map);
      }
      return <String, dynamic>{};
    }

    if (result.length > 1 && result[1] is Map) {
      return Map<String, dynamic>.from(result[1] as Map);
    }
    return null;
  }

  Future<void> _ensureSession() async {
    if (!hasSession) await login();
  }

  /// 登录并保存 session id。
  Future<String> login() async {
    final body = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': _callId++,
      'method': 'call',
      'params': [
        _emptySession,
        'session',
        'login',
        {
          'username': _config.username.isEmpty ? 'root' : _config.username,
          'password': _config.password,
          'timeout': 3600,
        },
      ],
    };

    final json = await _post(body);
    if (json.containsKey('error')) {
      final err = json['error'];
      final message = err is Map ? (err['message'] ?? '未知错误') : err;
      throw ApiException('登录失败: $message');
    }

    final result = json['result'];
    if (result is! List || result.isEmpty) {
      throw ApiException('登录响应格式错误');
    }

    String? sid;
    final first = result[0];
    if (first is String) {
      sid = first;
    } else if (first is int) {
      if (first == _errAccessDenied) {
        throw ApiException('用户名或密码错误');
      }
      if (first == 0 && result.length > 1 && result[1] is Map) {
        sid = (result[1] as Map)['ubus_rpc_session']?.toString();
      }
      if (sid == null || sid.isEmpty) {
        throw ApiException('登录失败，错误码 $first');
      }
    }
    if (sid == null || sid.isEmpty) {
      throw ApiException('登录响应缺少 session 信息');
    }

    _sessionId = sid;
    await PrefsStore.saveSession(sid);
    return sid;
  }

  /// 简单连通性测试（TCP 连接）。
  Future<bool> ping() async {
    try {
      final socket = await Socket.connect(
        _config.host,
        _config.port,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ============================ 系统信息 ============================

  Future<SystemInfo> getSystemInfo() async {
    final info = SystemInfo();
    final sys = await call('system', 'info') ?? <String, dynamic>{};

    info.uptime = _asInt(sys['uptime']);
    final load = sys['load'];
    if (load is List && load.length >= 3) {
      info.load1 = _asDouble(load[0]) / 65535.0;
      info.load5 = _asDouble(load[1]) / 65535.0;
      info.load15 = _asDouble(load[2]) / 65535.0;
    }

    final mem = sys['memory'];
    if (mem is Map) {
      info.memoryTotal = _asInt(mem['total']);
      info.memoryFree = _asInt(mem['free']);
      info.memoryShared = _asInt(mem['shared']);
      info.memoryBuffered = _asInt(mem['buffered']);
      info.memoryAvailable = mem['available'] != null
          ? _asInt(mem['available'])
          : info.memoryFree + info.memoryBuffered;
    }

    final swap = sys['swap'];
    if (swap is Map) {
      info.swapTotal = _asInt(swap['total']);
      info.swapFree = _asInt(swap['free']);
    }

    try {
      final board = await call('system', 'board') ?? <String, dynamic>{};
      info.model = (board['model'] ?? '—').toString();
      info.boardName = (board['board_name'] ?? '—').toString();
      info.hostname = (board['hostname'] ?? 'OpenWrt').toString();
      info.kernel = (board['kernel'] ?? '—').toString();
      final release = board['release'];
      if (release is Map) {
        info.release = (release['version'] ?? '—').toString();
        info.revision = (release['revision'] ?? '—').toString();
      }
    } catch (_) {
      // board 为可选信息
    }
    return info;
  }

  /// 重启路由器。
  Future<void> reboot() async {
    await call('system', 'reboot');
    await logout();
  }

  // ============================ 网络接口 ============================

  Future<List<NetworkInterfaceInfo>> getNetworkInterfaces() async {
    final list = <NetworkInterfaceInfo>[];
    final data = await call('network.interface', 'dump') ?? <String, dynamic>{};
    final interfaces = data['interface'];
    if (interfaces is List) {
      for (final raw in interfaces) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final ni = NetworkInterfaceInfo();
        ni.name = (item['interface'] ?? item['name'] ?? '?').toString();
        ni.proto = (item['proto'] ?? '—').toString();
        ni.device = (item['device'] ?? '—').toString();
        ni.up = item['up'] == true;
        ni.mac = (item['mac'] ?? '—').toString();

        final v4 = item['ipv4-address'];
        if (v4 is List && v4.isNotEmpty && v4.first is Map) {
          final a = v4.first as Map;
          ni.ipv4Addr = (a['address'] ?? '—').toString();
          ni.ipv4Mask = (a['mask'] ?? '—').toString();
        }
        final v6 = item['ipv6-address'];
        if (v6 is List && v6.isNotEmpty && v6.first is Map) {
          ni.ipv6Addr = ((v6.first as Map)['address'] ?? '—').toString();
        }
        final stats = item['stats'];
        if (stats is Map) {
          ni.rxBytes = _asInt(stats['rx_bytes']);
          ni.txBytes = _asInt(stats['tx_bytes']);
          ni.rxPackets = _asInt(stats['rx_packets']);
          ni.txPackets = _asInt(stats['tx_packets']);
        }
        list.add(ni);
      }
    }

    // 用 /proc/net/dev 补全流量统计
    try {
      final dev = await call('file', 'read', params: {'path': '/proc/net/dev'});
      final parsed = _parseProcNetDev((dev?['data'] ?? '').toString());
      for (final ni in list) {
        final st = parsed[ni.device] ?? parsed[ni.name];
        if (st != null) {
          ni.rxBytes = st[0];
          ni.txBytes = st[1];
        }
      }
    } catch (_) {}
    return list;
  }

  Map<String, List<int>> _parseProcNetDev(String content) {
    final map = <String, List<int>>{};
    final lines = content.split('\n');
    for (var i = 2; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final name = line.substring(0, colon).trim();
      final tokens = line.substring(colon + 1).trim().split(RegExp(r'\s+'));
      if (tokens.length < 9) continue;
      final rx = int.tryParse(tokens[0]);
      final tx = int.tryParse(tokens[8]);
      if (rx != null && tx != null) map[name] = [rx, tx];
    }
    return map;
  }

  Future<void> restartInterface(String iface) async {
    await call('network.interface.$iface', 'restart', params: {'interface': iface});
  }

  // ============================ 设备 / 租约 ============================

  Future<List<DhcpLease>> getDhcpLeases() async {
    final list = <DhcpLease>[];
    final byMac = <String, DhcpLease>{};

    final data = await call('file', 'read', params: {'path': '/tmp/dhcp.leases'});
    final content = (data?['data'] ?? '').toString();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    for (var line in content.split('\n')) {
      line = line.trim();
      if (line.isEmpty) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 4) continue;
      final lease = DhcpLease();
      final expiry = int.tryParse(parts[0]) ?? 0;
      lease.expires =
          expiry <= 0 ? 0 : (expiry - now).clamp(0, 1 << 62).toInt();
      lease.mac = parts[1];
      lease.ip = parts[2];
      lease.hostname = parts[3];
      list.add(lease);
      byMac[lease.mac.toLowerCase()] = lease;
    }

    // 静态租约（/etc/config/dhcp host 段）
    try {
      final hosts = await readUciConfig('dhcp');
      for (final entry in hosts.entries) {
        final sec = entry.value;
        if (sec['.type'] != 'host') continue;
        final mac = (sec['mac'] ?? '').trim();
        if (mac.isEmpty) continue;
        final ip = (sec['ip'] ?? '').trim();
        final key = mac.toLowerCase();
        var lease = byMac[key];
        if (lease == null) {
          lease = DhcpLease()
            ..mac = mac
            ..ip = ip
            ..hostname = sec['name'] ?? ''
            ..expires = 0;
          list.add(lease);
          byMac[key] = lease;
        }
        lease.staticSid = entry.key;
        lease.staticIp = ip;
        if (lease.ip.isEmpty) lease.ip = ip;
      }
    } catch (_) {}

    // 防火墙拉黑规则
    try {
      final rules = await readUciConfig('firewall');
      for (final entry in rules.entries) {
        final sec = entry.value;
        if (sec['.type'] != 'rule') continue;
        final target = (sec['target'] ?? '').toUpperCase();
        if (target != 'DROP' && target != 'REJECT') continue;
        final macs = sec['src_mac'];
        if (macs == null) continue;
        for (final m in macs.trim().split(RegExp(r'\s+'))) {
          if (m.isEmpty) continue;
          final key = m.toLowerCase();
          var lease = byMac[key];
          if (lease == null) {
            lease = DhcpLease()
              ..mac = m
              ..expires = 0;
            list.add(lease);
            byMac[key] = lease;
          }
          lease.blocked = true;
          lease.blockSid = entry.key;
        }
      }
    } catch (_) {}
    return list;
  }

  Future<void> setStaticLease(DhcpLease lease, String ip) async {
    if (!_macPattern.hasMatch(lease.mac)) {
      throw ApiException('设备 MAC 地址无效');
    }
    final fixedIp = ip.trim();
    if (!_ipv4Pattern.hasMatch(fixedIp)) {
      throw ApiException('IP 地址格式不正确');
    }
    var name = lease.hostname.trim();
    if (name.isEmpty || name == '*') {
      name = 'device_${lease.mac.replaceAll(':', '')}';
    }

    var sid = lease.staticSid;
    final sections = await readUciConfig('dhcp');
    for (final entry in sections.entries) {
      if (entry.value['.type'] != 'host') continue;
      if (sid != null && sid == entry.key) continue;
      if (fixedIp == entry.value['ip']) {
        final usedMac = entry.value['mac'];
        throw ApiException(
            'IP $fixedIp 已被${usedMac == null ? '其他设备' : '设备 $usedMac'}固定');
      }
    }

    if (sid == null || sid.isEmpty) {
      sid = (await _execUci(['add', 'dhcp', 'host'])).trim();
      if (sid.isEmpty) throw ApiException('创建静态租约失败');
    }
    await _execUci(['set', 'dhcp.$sid.mac=${lease.mac}']);
    await _execUci(['set', 'dhcp.$sid.ip=$fixedIp']);
    await _execUci(['set', 'dhcp.$sid.name=$name']);
    await _execUci(['commit', 'dhcp']);

    // 清除该 MAC 的旧动态租约，使其立即按固定地址重新获取
    await execShell(
      'grep -iv " ${lease.mac.toLowerCase()} " /tmp/dhcp.leases > /tmp/dhcp.leases.tmp 2>/dev/null && '
      'mv /tmp/dhcp.leases.tmp /tmp/dhcp.leases',
    );
    await execInit('dnsmasq', 'restart');
  }

  Future<void> removeStaticLease(String? sid) async {
    if (sid == null || sid.isEmpty) throw ApiException('未找到静态租约配置');
    await _execUci(['delete', 'dhcp.$sid']);
    await _execUci(['commit', 'dhcp']);
    await execInit('dnsmasq', 'restart');
  }

  Future<void> blockDevice(String mac) async {
    if (!_macPattern.hasMatch(mac)) throw ApiException('设备 MAC 地址无效');
    final sid = (await _execUci(['add', 'firewall', 'rule'])).trim();
    if (sid.isEmpty) throw ApiException('创建防火墙规则失败');
    await _execUci(['set', 'firewall.$sid.name=Block-$mac']);
    await _execUci(['set', 'firewall.$sid.src=lan']);
    await _execUci(['set', 'firewall.$sid.src_mac=$mac']);
    await _execUci(['set', 'firewall.$sid.dest=*']);
    await _execUci(['set', 'firewall.$sid.proto=all']);
    await _execUci(['set', 'firewall.$sid.target=DROP']);
    await _execUci(['set', 'firewall.$sid.enabled=1']);
    await _execUci(['commit', 'firewall']);
    await execInit('firewall', 'reload');
  }

  Future<void> unblockDevice(String? sid) async {
    if (sid == null || sid.isEmpty) throw ApiException('未找到拉黑规则');
    await _execUci(['delete', 'firewall.$sid']);
    await _execUci(['commit', 'firewall']);
    await execInit('firewall', 'reload');
  }

  // ============================ WiFi ============================

  Future<List<WifiInfo>> getWifiInfo() async {
    final list = <WifiInfo>[];
    var got = false;
    try {
      final devices = await call('iwinfo', 'devices');
      if (devices != null) {
        for (final key in devices.keys) {
          got = true;
          final wifi = WifiInfo()..ifname = key;
          try {
            final info =
                await call('iwinfo', 'info', params: {'device': key}) ??
                    <String, dynamic>{};
            wifi.ssid = (info['ssid'] ?? '—').toString();
            wifi.mode = (info['mode'] ?? '—').toString();
            wifi.channel = (info['channel'] ?? '—').toString();
            wifi.country = (info['country'] ?? '—').toString();
            wifi.up = _asInt(info['channel']) != 0 || wifi.ssid != '—';
            final enc = info['encryption'];
            if (enc is Map) {
              wifi.encryption =
                  (enc['encryption'] ?? enc['description'] ?? '—').toString();
            }
            wifi.signal = _asInt(info['signal']);
          } catch (_) {}
          try {
            final assoc = await call('iwinfo', 'assoclist',
                params: {'device': key});
            final results = assoc?['results'];
            if (results is Map) {
              results.forEach((mac, value) {
                if (value is! Map) return;
                wifi.clients.add(WifiClient()
                  ..mac = mac.toString()
                  ..signal = _asInt(value['signal'])
                  ..connectedTime = (value['connected_time'] ?? '—').toString()
                  ..hostname = (value['hostname'] ?? '').toString());
              });
            }
          } catch (_) {}
          list.add(wifi);
        }
      }
    } catch (_) {}

    if (!got) return _parseWifiViaExec();
    return list;
  }

  Future<List<WifiInfo>> _parseWifiViaExec() async {
    final list = <WifiInfo>[];
    try {
      final text = await _execIwinfo(const []);
      final blocks = text.split(RegExp(r'\n\s*\n'));
      final header = RegExp(r'^(\S+)\s+ESSID:\s*"?([^"]*)"?');
      final channel = RegExp(r'Channel:\s*(\d+)');
      final signal = RegExp(r'Signal:\s*(-?\d+)\s*dBm');
      final enc = RegExp(r'Encryption:\s*(.+)$', multiLine: true);
      final mode = RegExp(r'Mode:\s*(\w+)');

      for (var block in blocks) {
        block = block.trim();
        if (block.isEmpty) continue;
        final mh = header.firstMatch(block);
        if (mh == null) continue;
        final w = WifiInfo()
          ..ifname = mh.group(1) ?? ''
          ..ssid = mh.group(2) ?? '';
        final mc = channel.firstMatch(block);
        if (mc != null) w.channel = mc.group(1)!;
        final ms = signal.firstMatch(block);
        if (ms != null) w.signal = int.tryParse(ms.group(1)!) ?? 0;
        final me = enc.firstMatch(block);
        if (me != null) w.encryption = me.group(1)!.trim();
        final mm = mode.firstMatch(block);
        if (mm != null) w.mode = mm.group(1)!;
        w.up = w.channel != '—' || w.ssid.isNotEmpty;
        list.add(w);
      }

      for (final w in list) {
        try {
          final assoc = await _execIwinfo([w.ifname, 'assoclist']);
          final mac = RegExp(
              r'^([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})\s+(-?\d+)\s*dBm',
              multiLine: true);
          for (final m in mac.allMatches(assoc)) {
            w.clients.add(WifiClient()
              ..mac = m.group(1) ?? ''
              ..signal = int.tryParse(m.group(2) ?? '') ?? 0);
          }
        } catch (_) {}
      }
    } catch (_) {}
    return list;
  }

  Future<String> _execIwinfo(List<String> args) async {
    final data = await call('file', 'exec', params: {
      'command': '/usr/bin/iwinfo',
      'params': args,
    });
    return (data?['stdout'] ?? '').toString();
  }

  // ============================ 服务 ============================

  Future<List<ServiceInfo>> getServices() async {
    final services = await call('service', 'list') ?? <String, dynamic>{};
    final rc = await call('rc', 'list') ?? <String, dynamic>{};

    final names = <String>{};
    names.addAll(rc.keys);
    names.addAll(services.keys);

    final list = <ServiceInfo>[];
    for (final name in names) {
      final s = ServiceInfo()..name = name;

      final r = rc[name];
      if (r is Map) {
        s.hasInit = true;
        s.enabled = r['enabled'] == true;
        s.startOrder = _asInt(r['start']);
        s.running = r['running'] == true;
      }

      final svc = services[name];
      if (svc is Map) {
        final instances = svc['instances'];
        if (instances is Map) {
          var anyRunning = false;
          for (final inst in instances.values) {
            s.instanceCount++;
            if (inst is! Map) continue;
            if (inst['running'] == true) anyRunning = true;
            if (s.pid == 0) s.pid = _asInt(inst['pid']);
            if (s.command.isEmpty) {
              final cmd = inst['command'];
              if (cmd is List) {
                s.command = cmd.map((e) => '$e').join(' ');
              }
            }
          }
          if (s.instanceCount > 0) s.running = anyRunning;
        }
      }
      list.add(s);
    }
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Future<String> serviceAction(String name, String action) async {
    return execInit(name, action);
  }

  Future<String> execInit(String name, String action) async {
    final data = await call(
      'file',
      'exec',
      long: true,
      params: {
        'command': '/etc/init.d/$name',
        'params': [action],
      },
    );
    final code = _asInt(data?['code'], fallback: -1);
    final stdout = (data?['stdout'] ?? '').toString();
    final stderr = (data?['stderr'] ?? '').toString();
    if (code != 0) {
      final msg = stderr.trim().isNotEmpty ? stderr : stdout;
      throw ApiException(
          '执行失败 (code=$code)${msg.trim().isEmpty ? '' : ': ${msg.trim()}'}');
    }
    return stdout;
  }

  // ============================ OpenClash ============================

  Future<OpenClashConfig> getOpenClash() async {
    final sections = await readUciConfig('openclash');
    if (sections.isEmpty) {
      throw ApiException('未检测到 OpenClash（未找到 /etc/config/openclash）');
    }

    final oc = OpenClashConfig();
    Map<String, String>? global;
    Map<String, String>? fallback;
    for (final entry in sections.entries) {
      final sec = entry.value;
      final type = sec['.type'];
      if (type == 'config_subscribe') {
        oc.subscribes.add(OpenClashSubscribe()
          ..sid = entry.key
          ..name = _emptyToNull(sec['name'])
          ..address = _firstNonEmpty([sec['address'], sec['url']])
          ..enabled = !sec.containsKey('enabled') || _truthy(sec['enabled'])
          ..subUa = _emptyToNull(sec['sub_ua'])
          ..subConvert = _emptyToNull(sec['sub_convert']));
      } else if (type == 'openclash' && global == null) {
        global = sec;
      } else {
        fallback ??= sec;
      }
    }
    final g = global ?? fallback;
    if (g == null) throw ApiException('OpenClash 配置为空');

    oc.enable = _truthy(g['enable']);
    oc.proxyMode = g['proxy_mode'];
    oc.operationMode = _firstNonEmpty([g['en_mode'], g['operation_mode']]);
    oc.configPath = g['config_path'];
    oc.httpPort = g['http_port'];
    oc.socksPort = g['socks_port'];
    oc.mixedPort = g['mixed_port'];
    oc.proxyPort = _firstNonEmpty([g['proxy_port'], g['redir_port'], g['tproxy_port']]);
    oc.dnsPort = g['dns_port'];
    oc.cnPort = g['cn_port'];
    oc.coreType = g['core_type'];
    oc.dashboardType = g['dashboard_type'];

    final current = oc.currentConfigName;
    for (final s in oc.subscribes) {
      s.isCurrent = current != null &&
          s.name != null &&
          current.toLowerCase() == s.name!.toLowerCase();
    }

    try {
      final rc = await call('rc', 'list');
      final entry = rc?['openclash'];
      if (entry is Map) oc.running = entry['running'] == true;
    } catch (_) {}
    return oc;
  }

  Future<void> addOpenClashSubscribe(
      String name, String address, bool enabled) async {
    final sid = (await _execUci(['add', 'openclash', 'config_subscribe'])).trim();
    if (sid.isEmpty) throw ApiException('创建订阅配置失败');
    await _execUci(['set', 'openclash.$sid.name=$name']);
    await _execUci(['set', 'openclash.$sid.address=$address']);
    await _execUci(['set', 'openclash.$sid.enabled=${enabled ? '1' : '0'}']);
    await _execUci(['commit', 'openclash']);
  }

  Future<void> updateOpenClashSubscribe(
    String sid, {
    String? name,
    String? address,
    required bool enabled,
  }) async {
    if (name != null) await _execUci(['set', 'openclash.$sid.name=$name']);
    if (address != null) {
      await _execUci(['set', 'openclash.$sid.address=$address']);
    }
    await _execUci(['set', 'openclash.$sid.enabled=${enabled ? '1' : '0'}']);
    await _execUci(['commit', 'openclash']);
  }

  Future<void> deleteOpenClashSubscribe(String sid) async {
    await _execUci(['delete', 'openclash.$sid']);
    await _execUci(['commit', 'openclash']);
  }

  /// 调用 openclash.sh 后台更新订阅（等价 LuCI 的「更新配置」）。
  Future<String> updateOpenClashSubscriptions() async {
    const script = '/usr/share/openclash/openclash.sh';
    final data = await call(
      'file',
      'exec',
      long: true,
      params: {
        'command': '/bin/sh',
        'params': [
          '-c',
          'if [ -x $script ]; then $script >/tmp/openclash_app_update.log 2>&1 & echo __STARTED__; else echo __MISSING__; fi',
        ],
      },
    );
    final out = (data?['stdout'] ?? '').toString();
    if (out.contains('__MISSING__')) {
      throw ApiException('未找到 $script，请确认 OpenClash 已正确安装');
    }
    return '已开始更新订阅，OpenClash 会自动重启生效';
  }

  // ============================ UCI 辅助 ============================

  /// 读取 UCI 配置：sectionId -> {选项: 值}（含 .type）。
  Future<Map<String, Map<String, String>>> readUciConfig(
      String configName) async {
    final result = <String, Map<String, String>>{};
    try {
      final data = await call('uci', 'get', params: {'config': configName});
      final values = data?['values'];
      if (values is Map && values.isNotEmpty) {
        final keys = values.keys.map((e) => '$e').toList()
          ..sort((a, b) {
            final va = values[a];
            final vb = values[b];
            final ia = va is Map ? _asInt(va['.index']) : 0;
            final ib = vb is Map ? _asInt(vb['.index']) : 0;
            return ia.compareTo(ib);
          });
        for (final key in keys) {
          final sec = values[key];
          if (sec is! Map) continue;
          final map = <String, String>{};
          sec.forEach((k, v) {
            if (v == null) return;
            map['$k'] = '$v';
          });
          result[key] = map;
        }
        if (result.isNotEmpty) return result;
      }
    } catch (_) {}

    // 回退：部分固件没有 ubus uci 对象
    final out = await execShell('uci show $configName 2>/dev/null');
    final prefix = '$configName.';
    for (final raw in out.split('\n')) {
      final line = raw.trim();
      if (!line.startsWith(prefix)) continue;
      final rest = line.substring(prefix.length);
      final eq = rest.indexOf('=');
      if (eq <= 0) continue;
      final path = rest.substring(0, eq);
      final value = _unquoteUci(rest.substring(eq + 1));
      final dot = path.indexOf('.');
      final secRef = dot < 0 ? path : path.substring(0, dot);
      final opt = dot < 0 ? '.type' : path.substring(dot + 1);
      result.putIfAbsent(secRef, () => <String, String>{})[opt] = value;
    }
    return result;
  }

  Future<String> execShell(String cmd) async {
    final data = await call('file', 'exec', params: {
      'command': '/bin/sh',
      'params': ['-c', cmd],
    });
    return (data?['stdout'] ?? '').toString();
  }

  /// 执行 uci 命令（参数逐个传递，避免 shell 引号问题）。
  Future<String> _execUci(List<String> args) async {
    final data = await call(
      'file',
      'exec',
      long: true,
      params: {
        'command': '/sbin/uci',
        'params': args,
      },
    );
    final code = _asInt(data?['code'], fallback: -1);
    final stdout = (data?['stdout'] ?? '').toString();
    if (code != 0) {
      final err = (data?['stderr'] ?? '').toString().trim();
      throw ApiException(
          'UCI 操作失败${err.isEmpty ? '' : '：$err'}');
    }
    return stdout;
  }

  // ============================ 工具函数 ============================

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  static bool _truthy(String? v) {
    if (v == null) return false;
    final s = v.trim().toLowerCase();
    return s == '1' || s == 'true' || s == 'on' || s == 'yes' || s == 'enabled';
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final v in values) {
      if (v != null && v.trim().isNotEmpty) return v;
    }
    return null;
  }

  static String? _emptyToNull(String? v) =>
      (v == null || v.isEmpty) ? null : v;

  static String _unquoteUci(String v) {
    var s = v.trim();
    if (s.length >= 2 && s.startsWith("'") && s.endsWith("'")) {
      s = s.substring(1, s.length - 1).replaceAll(r"'\''", "'");
    }
    return s;
  }
}
