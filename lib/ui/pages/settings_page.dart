import 'package:flutter/material.dart';

import '../../api/router_api.dart';
import '../../models/models.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/glass.dart';

/// 设置页：路由器连接配置与关于信息。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _api = RouterApi.instance;

  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;

  bool _useHttps = false;
  bool _obscure = true;
  bool _busy = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    final config = _api.config;
    _hostCtrl = TextEditingController(text: config.host);
    _portCtrl = TextEditingController(text: '${config.port}');
    _userCtrl = TextEditingController(text: config.username);
    _passCtrl = TextEditingController(text: config.password);
    _useHttps = config.useHttps;
    _status = _api.hasSession
        ? '已连接：${config.displayName}'
        : '已保存配置，尚未连接';
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  RouterConnection? _readConfig() {
    final host = _hostCtrl.text.trim();
    if (host.isEmpty) {
      showToast(context, '请输入路由器地址');
      return null;
    }
    var port = int.tryParse(_portCtrl.text.trim()) ?? (_useHttps ? 443 : 80);
    if (port <= 0 || port > 65535) port = _useHttps ? 443 : 80;
    final user = _userCtrl.text.trim();
    return RouterConnection(
      host: host,
      port: port,
      username: user.isEmpty ? 'root' : user,
      password: _passCtrl.text,
      useHttps: _useHttps,
    );
  }

  Future<void> _saveAndConnect() async {
    final config = _readConfig();
    if (config == null) return;

    setState(() {
      _busy = true;
      _status = '正在连接并登录…';
    });
    try {
      await _api.setConfig(config);
      await _api.login();
      if (!mounted) return;
      setState(() => _status = '已连接：${config.displayName}');
      showToast(context, '连接成功');
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : e.toString();
      setState(() => _status = '连接失败：$message');
      showToast(context, '连接失败：$message');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testConnection() async {
    final config = _readConfig();
    if (config == null) return;

    setState(() {
      _busy = true;
      _status = '正在测试连通性…';
    });
    try {
      await _api.setConfig(config);
      final reachable = await _api.ping();
      if (!mounted) return;
      if (!reachable) {
        setState(() => _status = '路由器不可达，请检查地址与网络');
        return;
      }
      setState(() => _status = '路由器可达，正在验证登录…');
      await _api.login();
      if (!mounted) return;
      setState(() => _status = '测试通过：登录成功 ✓');
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : e.toString();
      setState(() => _status = '测试失败：$message');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    await _api.logout();
    if (!mounted) return;
    setState(() => _status = '已断开登录');
    showToast(context, '已断开登录');
  }

  @override
  Widget build(BuildContext context) {
    final connected = _api.hasSession;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 130),
        children: [
          PageHeader(
            title: '设置',
            subtitle: '通过 ubus over HTTP 管理路由器',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: (connected
                        ? const Color(0xFF27C281)
                        : const Color(0xFF9AA3B2))
                    .withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusDot(active: connected, size: 7),
                  const SizedBox(width: 6),
                  Text(
                    connected ? '已连接' : '未连接',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: connected
                          ? const Color(0xFF27C281)
                          : AppTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle('路由器连接'),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _hostCtrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: '路由器地址',
                    hintText: '192.168.1.1',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _portCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '端口',
                          hintText: '80',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.isDark(context)
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.white.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.isDark(context)
                                ? Colors.white.withValues(alpha: 0.10)
                                : Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text('HTTPS',
                                  style: TextStyle(fontSize: 13.5)),
                            ),
                            Switch.adaptive(
                              value: _useHttps,
                              activeTrackColor: AppTheme.primary,
                              onChanged: (v) => setState(() {
                                _useHttps = v;
                                final port =
                                    int.tryParse(_portCtrl.text.trim()) ?? 0;
                                if (port == 0 ||
                                    port == 80 ||
                                    port == 443) {
                                  _portCtrl.text = v ? '443' : '80';
                                }
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _userCtrl,
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    hintText: 'root',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: '密码',
                    hintText: '路由器登录密码',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 19,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    StatusDot(active: connected, size: 8),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _status,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(minHeight: 2.5),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: _busy ? null : _saveAndConnect,
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text('保存并连接'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    foregroundColor: AppTheme.primary,
                    side: BorderSide(
                      color: AppTheme.primary.withValues(alpha: 0.5),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: _busy ? null : _testConnection,
                  icon: const Icon(Icons.bolt_rounded, size: 18),
                  label: const Text('测试连接'),
                ),
              ),
            ],
          ),
          if (connected)
            Center(
              child: TextButton(
                onPressed: _busy ? null : _logout,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFD64545),
                ),
                child: const Text('断开登录'),
              ),
            ),
          const SectionTitle('关于'),
          GlassCard(
            child: Column(
              children: [
                InfoRow('应用名称', 'OpenWrt 管理'),
                InfoRow('版本', '1.0.0'),
                InfoRow('通信协议', 'ubus / JSON-RPC 2.0'),
                InfoRow('最低系统', 'Android 6.0 (API 23)'),
                const SizedBox(height: 8),
                Text(
                  '本应用通过路由器开放的 ubus HTTP 接口工作，'
                  '连接信息仅保存在本机，不会上传到任何服务器。'
                  '为兼容自签名证书，HTTPS 模式不校验证书，'
                  '建议仅在可信局域网内使用。',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.6,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
