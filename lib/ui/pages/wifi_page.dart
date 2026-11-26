import 'package:flutter/material.dart';

import '../../api/router_api.dart';
import '../../models/models.dart';
import '../theme.dart';
import '../widgets/glass.dart';

/// WiFi 页：无线状态与关联客户端。
class WifiPage extends StatefulWidget {
  const WifiPage({super.key});

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
              trailing: IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 22),
                onPressed: _load,
                tooltip: '刷新',
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
