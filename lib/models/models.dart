/// 路由器连接配置。
class RouterConnection {
  final String host;
  final int port;
  final String username;
  final String password;
  final bool useHttps;

  const RouterConnection({
    this.host = '192.168.1.1',
    this.port = 80,
    this.username = 'root',
    this.password = '',
    this.useHttps = false,
  });

  String get baseUrl => '${useHttps ? 'https' : 'http'}://$host:$port';

  String get displayName => '${username.isEmpty ? 'root' : username}@$host';
}

/// 系统信息（ubus system info + system board）。
class SystemInfo {
  String model = '—';
  String boardName = '—';
  String release = '—';
  String revision = '—';
  String kernel = '—';
  String hostname = 'OpenWrt';
  int uptime = 0;
  double load1 = 0;
  double load5 = 0;
  double load15 = 0;
  int memoryTotal = 0;
  int memoryFree = 0;
  int memoryShared = 0;
  int memoryBuffered = 0;
  int memoryAvailable = 0;
  int swapTotal = 0;
  int swapFree = 0;

  int get memoryUsed => memoryTotal - memoryAvailable;

  String get firmwareDisplay =>
      revision.isEmpty || revision == '—' ? release : '$release ($revision)';
}

/// 网络接口（ubus network.interface dump）。
class NetworkInterfaceInfo {
  String name = '—';
  String device = '—';
  bool up = false;
  String ipv4Addr = '—';
  String ipv4Mask = '—';
  String ipv6Addr = '—';
  String mac = '—';
  int rxBytes = 0;
  int txBytes = 0;
  int rxPackets = 0;
  int txPackets = 0;
  String proto = '—';

  /// 实时速率，由页面采样计算。
  String rxRate = '—';
  String txRate = '—';
}

/// DHCP 租约（已连接设备）。
class DhcpLease {
  String ip = '';
  String mac = '';
  String hostname = '';
  int expires = 0; // 剩余秒数，0 表示永久
  String? staticSid;
  String? staticIp;
  bool blocked = false;
  String? blockSid;

  String get displayHostname {
    final h = hostname.trim();
    if (h.isEmpty || h == '*') return '(未知)';
    return h;
  }

  String get expiresDisplay {
    if (expires <= 0) return '永久';
    final h = expires ~/ 3600;
    final m = (expires % 3600) ~/ 60;
    if (h > 0) return '$h小时$m分';
    return '$m分钟';
  }
}

class WifiClient {
  String mac = '';
  String hostname = '';
  int signal = 0;
  String connectedTime = '';
}

/// WiFi 设备信息（ubus iwinfo 或 iwinfo 命令）。
class WifiInfo {
  String ifname = '';
  String ssid = '—';
  String encryption = '—';
  bool up = false;
  String channel = '—';
  int signal = 0;
  String mode = '—';
  String country = '—';
  List<WifiClient> clients = [];

  String get signalDisplay => signal == 0 ? '—' : '$signal dBm';
}

/// /etc/config/wireless 中的一个 wifi-iface（AP）配置。
class WirelessConfig {
  String sid = '';
  String ssid = '';
  String key = '';
  String encryption = 'none';
  String device = '—';
  bool disabled = false;

  String get title => ssid.trim().isEmpty ? '(未设置名称)' : ssid;

  String get subtitle {
    final buffer = StringBuffer(device.isEmpty ? '—' : device);
    buffer.write(' · ');
    buffer.write(encryption.isEmpty ? 'none' : encryption);
    if (disabled) buffer.write(' · 已禁用');
    return buffer.toString();
  }
}

/// 服务 / 插件信息（合并 ubus service list 与 rc list）。
class ServiceInfo {
  String name = '';
  bool running = false;
  bool hasInit = false;
  bool enabled = false;
  int pid = 0;
  String command = '';
  int startOrder = 0;
  int instanceCount = 0;

  String get pidDisplay => pid > 0 ? '$pid' : '—';
  String get startOrderDisplay => hasInit ? 'S$startOrder' : '—';
  String get runningText => running ? '运行中' : '已停止';
  String get enabledText => hasInit ? (enabled ? '自启:开' : '自启:关') : '—';
}

/// OpenClash 订阅。
class OpenClashSubscribe {
  String sid = '';
  String? name;
  String? address;
  bool enabled = true;
  String? subUa;
  String? subConvert;
  bool isCurrent = false;
}

/// OpenClash 全局配置 + 订阅列表。
class OpenClashConfig {
  bool enable = false;
  String? proxyMode;
  String? operationMode;
  String? configPath;
  String? httpPort;
  String? socksPort;
  String? mixedPort;
  String? proxyPort;
  String? dnsPort;
  String? cnPort;
  String? coreType;
  String? dashboardType;
  bool running = false;
  List<OpenClashSubscribe> subscribes = [];

  String? get currentConfigName {
    final path = configPath;
    if (path == null || path.isEmpty) return null;
    final slash = path.lastIndexOf('/');
    var base = slash >= 0 ? path.substring(slash + 1) : path;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    return base;
  }

  String get proxyModeDisplay {
    switch (proxyMode) {
      case 'rule':
        return '规则模式';
      case 'global':
        return '全局模式';
      case 'direct':
        return '直连模式';
      default:
        return proxyMode ?? '—';
    }
  }
}
