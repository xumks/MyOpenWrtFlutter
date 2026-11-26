import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/router_api.dart';
import '../../models/models.dart';
import '../theme.dart';
import '../../util/format.dart';
import '../widgets/dialogs.dart';
import '../widgets/glass.dart';

/// 网络接口页：状态、地址、流量与实时速率。
class NetworkPage extends StatefulWidget {
  const NetworkPage({super.key});

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  final _api = RouterApi.instance;

  List<NetworkInterfaceInfo> _list = [];
  final Map<String, ({int rx, int tx, int ms})> _prev = {};
  String? _error;
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await _api.getNetworkInterfaces();
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final ni in list) {
        final prev = _prev[ni.name];
        if (prev != null && now > prev.ms) {
          ni.rxRate = Fmt.rate(ni.rxBytes - prev.rx, now - prev.ms);
          ni.txRate = Fmt.rate(ni.txBytes - prev.tx, now - prev.ms);
        } else {
          ni.rxRate = '0 B/s';
          ni.txRate = '0 B/s';
        }
        _prev[ni.name] = (rx: ni.rxBytes, tx: ni.txBytes, ms: now);
      }
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        color: AppTheme.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 130),
          children: [
            PageHeader(
              title: '网络',
              subtitle: _list.isEmpty ? '接口状态与流量统计' : '共 ${_list.length} 个网络接口',
              trailing: IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 22),
                onPressed: _refresh,
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
                  icon: Icons.lan_outlined,
                  text: _error ?? '没有读取到网络接口',
                  action: FilledButton.icon(
                    onPressed: _refresh,
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
              for (final ni in _list) ...[
                _InterfaceCard(
                  info: ni,
                  onTap: () => _showDetail(ni),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showDetail(NetworkInterfaceInfo ni) async {
    final dark = AppTheme.isDark(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: dark ? const Color(0xFF161E30) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                Row(
                  children: [
                    StatusDot(active: ni.up, size: 10),
                    const SizedBox(width: 8),
                    Text(
                      ni.name.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    BadgeChip(ni.up ? 'UP' : 'DOWN',
                        color: ni.up
                            ? const Color(0xFF27C281)
                            : const Color(0xFF9AA3B2)),
                  ],
                ),
                const SizedBox(height: 14),
                InfoRow('物理设备', ni.device),
                InfoRow('协议', ni.proto),
                InfoRow('IPv4', ni.ipv4Addr),
                InfoRow('掩码', ni.ipv4Mask),
                InfoRow('IPv6', ni.ipv6Addr),
                InfoRow('MAC', ni.mac),
                InfoRow('接收数据包', '${ni.rxPackets}'),
                InfoRow('发送数据包', '${ni.txPackets}'),
                InfoRow('累计接收', Fmt.bytes(ni.rxBytes)),
                InfoRow('累计发送', Fmt.bytes(ni.txBytes)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _restart(ni.name);
                    },
                    icon: const Icon(Icons.restart_alt_rounded, size: 19),
                    label: Text('重启接口 ${ni.name}'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _restart(String name) async {
    final ok = await showConfirmDialog(
      context,
      title: '重启接口',
      message: '确定要重启接口 $name 吗？该接口的临时连接会短暂中断。',
      confirmText: '重启',
    );
    if (!ok || !mounted) return;
    showToast(context, '正在重启接口 $name…');
    try {
      await _api.restartInterface(name);
      if (!mounted) return;
      showToast(context, '接口 $name 已重启');
      _refresh();
    } catch (e) {
      if (!mounted) return;
      showToast(context, '重启失败：${e is ApiException ? e.message : e}');
    }
  }
}

class _InterfaceCard extends StatelessWidget {
  const _InterfaceCard({required this.info, required this.onTap});

  final NetworkInterfaceInfo info;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusDot(active: info.up),
              const SizedBox(width: 8),
              Text(
                info.name.toUpperCase(),
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 8),
              BadgeChip(
                info.protocolText,
                color: AppTheme.secondary,
              ),
              const Spacer(),
              Text(
                info.up ? '在线' : '离线',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: info.up
                      ? const Color(0xFF27C281)
                      : AppTheme.textSecondary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            info.device,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TrafficInfo(
                  icon: Icons.south_rounded,
                  label: '接收',
                  color: const Color(0xFF27C281),
                  total: Fmt.bytes(info.rxBytes),
                  rate: info.rxRate,
                ),
              ),
              Container(
                width: 1,
                height: 30,
                color: Theme.of(context)
                    .dividerColor
                    .withValues(alpha: 0.6),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: _TrafficInfo(
                    icon: Icons.north_rounded,
                    label: '发送',
                    color: AppTheme.primary,
                    total: Fmt.bytes(info.txBytes),
                    rate: info.txRate,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            info.ipv4Addr == '—' ? '未分配 IPv4 地址' : 'IPv4  ${info.ipv4Addr}',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficInfo extends StatelessWidget {
  const _TrafficInfo({
    required this.icon,
    required this.label,
    required this.color,
    required this.total,
    required this.rate,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String total;
  final String rate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary(context),
              ),
            ),
            const Spacer(),
            Text(
              rate,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            total,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

extension on NetworkInterfaceInfo {
  String get protocolText {
    switch (proto) {
      case 'dhcp':
        return 'DHCP';
      case 'static':
        return '静态';
      case 'pppoe':
        return 'PPPoE';
      default:
        return proto.toUpperCase();
    }
  }
}
