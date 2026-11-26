import 'package:flutter/material.dart';

import '../../api/router_api.dart';
import '../../models/models.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/glass.dart';

/// 设备页：DHCP 租约、固定 IP 与拉黑。
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final _api = RouterApi.instance;
  final _searchController = TextEditingController();

  List<DhcpLease> _all = [];
  String _query = '';
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.getDhcpLeases();
      list.sort(_compare);
      if (!mounted) return;
      setState(() {
        _all = list;
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

  int _compare(DhcpLease a, DhcpLease b) {
    int lastOctet(String ip) {
      final parts = ip.split('.');
      if (parts.length != 4) return 9999;
      return int.tryParse(parts[3]) ?? 9999;
    }

    final r = lastOctet(a.ip).compareTo(lastOctet(b.ip));
    return r != 0 ? r : a.mac.compareTo(b.mac);
  }

  List<DhcpLease> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all
        .where((e) =>
            e.hostname.toLowerCase().contains(q) ||
            e.ip.toLowerCase().contains(q) ||
            e.mac.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: PageHeader(
              title: '设备',
              subtitle: _loading ? '正在读取租约…' : '共 ${_all.length} 台设备',
              trailing: IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 22),
                onPressed: _busy ? null : _load,
                tooltip: '刷新',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: '搜索主机名 / IP / MAC',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AppTheme.primary,
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _all.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
        ],
      );
    }

    if (_all.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 40, 20, 130),
        children: [
          GlassCard(
            child: EmptyView(
              icon: Icons.devices_other_rounded,
              text: _error ?? '暂无设备租约',
              action: FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重新读取'),
              ),
            ),
          ),
        ],
      );
    }

    final devices = _filtered;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 130),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: BadgeChip(
              '刷新失败：$_error',
              color: const Color(0xFFD64545),
              icon: Icons.error_outline_rounded,
            ),
          ),
        for (final lease in devices) ...[
          _DeviceCard(
            lease: lease,
            enabled: !_busy,
            onFix: () => _fixIp(lease),
            onUnfix: () => _unfix(lease),
            onBlock: () => _block(lease),
            onUnblock: () => _unblock(lease),
          ),
          const SizedBox(height: 12),
        ],
        if (devices.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: EmptyView(
              icon: Icons.search_off_rounded,
              text: '没有匹配的设备',
            ),
          ),
      ],
    );
  }

  Future<void> _fixIp(DhcpLease lease) async {
    final ip = await showTextInputDialog(
      context,
      title: '固定 IP',
      message: '为 ${lease.displayHostname}（${lease.mac}）设置静态租约，'
          '设备重新获取地址后会固定使用该 IP。',
      hintText: '例如 192.168.1.100',
      initialValue: lease.staticIp ?? lease.ip,
      keyboardType: TextInputType.text,
      validator: (v) {
        if (v.isEmpty) return '请输入 IP 地址';
        final ok = RegExp(
                r'^((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$')
            .hasMatch(v);
        return ok ? null : 'IP 格式不正确';
      },
    );
    if (ip == null || !mounted) return;

    await _run(() => _api.setStaticLease(lease, ip), '已固定为 $ip');
  }

  Future<void> _unfix(DhcpLease lease) async {
    final ok = await showConfirmDialog(
      context,
      title: '取消固定 IP',
      message: '将删除 ${lease.displayHostname} 的静态租约，之后由 DHCP 动态分配地址。',
      confirmText: '取消固定',
    );
    if (!ok || !mounted) return;
    await _run(() => _api.removeStaticLease(lease.staticSid), '已取消固定 IP');
  }

  Future<void> _block(DhcpLease lease) async {
    final ok = await showConfirmDialog(
      context,
      title: '拉黑设备',
      message: '将添加防火墙规则丢弃 ${lease.displayHostname}（${lease.mac}）'
          '的全部流量，该设备将无法访问网络。',
      confirmText: '拉黑',
      danger: true,
    );
    if (!ok || !mounted) return;
    await _run(() => _api.blockDevice(lease.mac), '已拉黑 ${lease.displayHostname}');
  }

  Future<void> _unblock(DhcpLease lease) async {
    final ok = await showConfirmDialog(
      context,
      title: '解除拉黑',
      message: '将删除该设备的防火墙拦截规则，恢复其网络访问。',
      confirmText: '解除',
    );
    if (!ok || !mounted) return;
    await _run(
        () => _api.unblockDevice(lease.blockSid), '已解除 ${lease.displayHostname} 的拉黑');
  }

  Future<void> _run(Future<void> Function() action, String successText) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      showToast(context, successText);
      await _load();
    } catch (e) {
      if (!mounted) return;
      showToast(context, '操作失败：${e is ApiException ? e.message : e}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.lease,
    required this.enabled,
    required this.onFix,
    required this.onUnfix,
    required this.onBlock,
    required this.onUnblock,
  });

  final DhcpLease lease;
  final bool enabled;
  final VoidCallback onFix;
  final VoidCallback onUnfix;
  final VoidCallback onBlock;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final name = lease.displayHostname;
    final initial = name == '(未知)' ? '?' : name.substring(0, 1).toUpperCase();

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  gradient: LinearGradient(
                    colors: lease.blocked
                        ? [const Color(0xFFE06666), const Color(0xFFC74343)]
                        : [
                            AppTheme.primary.withValues(alpha: 0.95),
                            AppTheme.secondary.withValues(alpha: 0.85),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      lease.mac,
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
                    lease.ip.isEmpty ? '—' : lease.ip,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    lease.expires <= 0 ? '永久' : '剩余 ${lease.expiresDisplay}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (lease.staticSid != null || lease.blocked) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (lease.staticSid != null)
                  BadgeChip(
                    '固定 IP：${lease.staticIp ?? lease.ip}',
                    color: AppTheme.primary,
                    icon: Icons.push_pin_rounded,
                  ),
                if (lease.blocked)
                  const BadgeChip(
                    '已拉黑',
                    color: Color(0xFFD64545),
                    icon: Icons.block_rounded,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: enabled
                      ? (lease.staticSid != null ? onUnfix : onFix)
                      : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    side: BorderSide(
                      color: AppTheme.primary.withValues(alpha: 0.45),
                    ),
                    foregroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: Icon(
                    lease.staticSid != null
                        ? Icons.push_pin_outlined
                        : Icons.push_pin_rounded,
                    size: 16,
                  ),
                  label: Text(
                    lease.staticSid != null ? '取消固定' : '固定 IP',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: enabled ? (lease.blocked ? onUnblock : onBlock) : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    side: BorderSide(
                      color: lease.blocked
                          ? const Color(0xFF27C281).withValues(alpha: 0.5)
                          : const Color(0xFFD64545).withValues(alpha: 0.45),
                    ),
                    foregroundColor: lease.blocked
                        ? const Color(0xFF27C281)
                        : const Color(0xFFD64545),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: Icon(
                    lease.blocked ? Icons.lock_open_rounded : Icons.block_rounded,
                    size: 16,
                  ),
                  label: Text(
                    lease.blocked ? '解除拉黑' : '拉黑',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
