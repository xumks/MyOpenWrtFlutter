import 'package:flutter/material.dart';

import '../../api/router_api.dart';
import '../../models/models.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/glass.dart';

/// WiFi 页：无线状态与关联客户端。
class WifiPage extends StatefulWidget {
  const WifiPage({super.key, this.active = true});

  /// 当前是否为可见标签页；从其他标签返回时自动刷新。
  final bool active;

  @override
  State<WifiPage> createState() => _WifiPageState();
}

class _WifiPageState extends State<WifiPage> {
  final _api = RouterApi.instance;

  List<WifiInfo> _list = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant WifiPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.getWifiInfo();
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  int get _clientCount =>
      _list.fold(0, (sum, w) => sum + w.clients.length);

  /// 读取无线配置，选择后弹出名称/密码编辑框。
  Future<void> _openWifiSettings() async {
    if (!_api.hasSession) {
      showToast(context, '请先在「设置」中连接路由器');
      return;
    }
    showToast(context, '正在读取无线配置…');

    List<WirelessConfig> configs;
    try {
      configs = await _api.getWirelessConfigs();
    } catch (e) {
      if (!mounted) return;
      showToast(context, '读取无线配置失败：${e is ApiException ? e.message : e}');
      return;
    }
    if (!mounted) return;
    if (configs.isEmpty) {
      showToast(context, '未找到可编辑的无线配置（需为 AP 模式）');
      return;
    }

    final selected = await _showChooser(configs);
    if (selected == null || !mounted) return;
    await _editConfig(selected);
  }

  Future<WirelessConfig?> _showChooser(List<WirelessConfig> configs) {
    final dark = AppTheme.isDark(context);
    return showModalBottomSheet<WirelessConfig>(
      context: context,
      backgroundColor: dark ? const Color(0xFF161E30) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 14),
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textSecondary(ctx).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 22),
                child: Text(
                  '无线设置',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Text(
                  '选择一个无线网络修改名称或密码',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary(ctx),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              for (final cfg in configs)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 22),
                  title: Text(
                    cfg.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    cfg.subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary(ctx),
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppTheme.textSecondary(ctx)
                        .withValues(alpha: 0.7),
                  ),
                  onTap: () => Navigator.pop(ctx, cfg),
                ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editConfig(WirelessConfig cfg) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _WifiEditDialog(config: cfg),
    );
    if (result == null || !mounted) return;

    final (ssid, key) = result;
    showToast(context, '正在保存无线配置…');
    try {
      await _api.updateWirelessConfig(cfg.sid, ssid, key);
      if (!mounted) return;
      showToast(context, '已保存，无线配置正在生效');
      _load();
    } catch (e) {
      if (!mounted) return;
      showToast(context, '保存失败：${e is ApiException ? e.message : e}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 130),
          children: [
            PageHeader(
              title: 'WiFi',
              subtitle: _list.isEmpty
                  ? '无线网络状态'
                  : '${_list.length} 个射频 · $_clientCount 台设备已连接',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.tune_rounded, size: 22),
                    onPressed: _openWifiSettings,
                    tooltip: '修改 WiFi 名称/密码',
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 22),
                    onPressed: _load,
                    tooltip: '刷新',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_loading && _list.isEmpty)
              const GlassCard(
                child: SizedBox(
                  height: 160,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              )
            else if (_list.isEmpty)
              GlassCard(
                child: EmptyView(
                  icon: Icons.wifi_off_rounded,
                  text: _error ?? '未读取到无线信息（路由器可能未启用 WiFi 或固件不支持）',
                  action: FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('重试'),
                  ),
                ),
              )
            else ...[
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: BadgeChip(
                    '刷新失败：$_error',
                    color: const Color(0xFFD64545),
                    icon: Icons.error_outline_rounded,
                  ),
                ),
              for (final wifi in _list) ...[
                _WifiCard(info: wifi),
                const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _WifiCard extends StatelessWidget {
  const _WifiCard({required this.info});

  final WifiInfo info;

  @override
  Widget build(BuildContext context) {
    final icon = _signalIcon(info.signal);
    final signalColor = _signalColor(info.signal);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.accent.withValues(alpha: 0.92),
                      AppTheme.primary.withValues(alpha: 0.72),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(icon, color: Colors.white, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.ssid.isEmpty || info.ssid == '—' ? '(未广播)' : info.ssid,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${info.ifname} · ${info.mode}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    info.signalDisplay,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: signalColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '信道 ${info.channel}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              BadgeChip(
                info.up ? '已启用' : '未启用',
                color: info.up
                    ? const Color(0xFF27C281)
                    : const Color(0xFF9AA3B2),
              ),
              BadgeChip(info.encryption, color: AppTheme.secondary),
              BadgeChip('${info.clients.length} 台设备',
                  color: AppTheme.primary),
            ],
          ),
          if (info.clients.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 6),
            for (final client in info.clients)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(Icons.smartphone_rounded,
                        size: 15,
                        color: AppTheme.textSecondary(context)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        client.hostname.isEmpty
                            ? client.mac
                            : '${client.hostname}  ${client.mac}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text(
                      client.signal == 0 ? '—' : '${client.signal} dBm',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _signalColor(client.signal),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  IconData _signalIcon(int signal) {
    if (!info.up) return Icons.wifi_off_rounded;
    if (signal >= -55) return Icons.signal_wifi_4_bar_rounded;
    if (signal >= -70) return Icons.network_wifi_3_bar_rounded;
    if (signal >= -80) return Icons.network_wifi_2_bar_rounded;
    return Icons.network_wifi_1_bar_rounded;
  }

  Color _signalColor(int signal) {
    if (signal == 0) return const Color(0xFF9AA3B2);
    if (signal >= -60) return const Color(0xFF27C281);
    if (signal >= -75) return const Color(0xFFE0A100);
    return const Color(0xFFD64545);
  }
}

/// WiFi 名称 / 密码编辑对话框，保存后返回 (ssid, key)。
class _WifiEditDialog extends StatefulWidget {
  const _WifiEditDialog({required this.config});

  final WirelessConfig config;

  @override
  State<_WifiEditDialog> createState() => _WifiEditDialogState();
}

class _WifiEditDialogState extends State<_WifiEditDialog> {
  late final TextEditingController _ssidCtrl =
      TextEditingController(text: widget.config.ssid);
  final _keyCtrl = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _ssidCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final ssid = _ssidCtrl.text.trim();
    final key = _keyCtrl.text;
    if (ssid.isEmpty) {
      setState(() => _error = '请输入 WiFi 名称');
      return;
    }
    if (ssid.length > 32) {
      setState(() => _error = 'WiFi 名称不能超过 32 个字符');
      return;
    }
    final keyValid = key.isEmpty ||
        (key.length >= 8 && key.length <= 63) ||
        (key.length == 64 && RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(key));
    if (!keyValid) {
      setState(() => _error = '密码需为 8-63 位字符，或 64 位十六进制');
      return;
    }
    Navigator.pop(context, (ssid, key));
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDark(context);
    final encryption = widget.config.encryption.isEmpty
        ? 'none'
        : widget.config.encryption;
    return AlertDialog(
      backgroundColor: dark ? const Color(0xFF161E30) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'WiFi 名称 / 密码',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ssidCtrl,
              autofocus: true,
              maxLength: 32,
              decoration: const InputDecoration(
                labelText: 'WiFi 名称 (SSID)',
                hintText: '输入新的 WiFi 名称',
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _keyCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'WiFi 密码',
                hintText: '留空表示保持原密码',
                helperText: '8-63 位字符，或 64 位十六进制',
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
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFFD64545),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '当前加密方式：$encryption\n'
              '保存后无线会重新加载，已连接设备可能短暂断开。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.55,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存并应用'),
        ),
      ],
    );
  }
}
