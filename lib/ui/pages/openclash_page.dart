import 'package:flutter/material.dart';

import '../../api/router_api.dart';
import '../../models/models.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/glass.dart';

/// OpenClash 页：运行状态与订阅管理。
class OpenClashPage extends StatefulWidget {
  const OpenClashPage({super.key});

  @override
  State<OpenClashPage> createState() => _OpenClashPageState();
}

class _OpenClashPageState extends State<OpenClashPage> {
  final _api = RouterApi.instance;

  OpenClashConfig? _config;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _updating = false;

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
      final config = await _api.getOpenClash();
      if (!mounted) return;
      setState(() {
        _config = config;
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

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'OpenClash',
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: '刷新',
        ),
      ],
      child: RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            if (_loading && _config == null)
              const GlassCard(
                child: SizedBox(
                  height: 160,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              )
            else if (_config == null)
              GlassCard(
                child: EmptyView(
                  icon: Icons.shield_outlined,
                  text: _error ?? '未检测到 OpenClash',
                  action: FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('重新检测'),
                  ),
                ),
              )
            else
              ..._buildContent(_config!),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildContent(OpenClashConfig config) {
    return [
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusDot(active: config.running, size: 10),
                const SizedBox(width: 8),
                Text(
                  config.running ? '运行中' : '已停止',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: config.running
                        ? const Color(0xFF27C281)
                        : AppTheme.textSecondary(context),
                  ),
                ),
                const Spacer(),
                BadgeChip(config.proxyModeDisplay, color: AppTheme.secondary),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            InfoRow('当前配置', config.currentConfigName ?? '—'),
            InfoRow('运行模式', config.operationMode ?? '—'),
            InfoRow('混合端口', config.mixedPort ?? '—'),
            InfoRow('控制面板端口', config.cnPort ?? '—'),
            InfoRow('订阅数量', '${config.subscribes.length}'),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                backgroundColor: AppTheme.secondary,
              ),
              onPressed: _updating ? null : _updateSubscriptions,
              icon: _updating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_download_rounded, size: 18),
              label: Text(_updating ? '正在更新…' : '更新订阅'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                foregroundColor: AppTheme.primary,
                side: BorderSide(
                  color: AppTheme.primary.withValues(alpha: 0.5),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: _busy ? null : () => _showSubscribeDialog(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('添加订阅'),
            ),
          ),
        ],
      ),
      const SectionTitle('订阅列表'),
      if (config.subscribes.isEmpty)
        GlassCard(
          child: EmptyView(
            icon: Icons.playlist_add_rounded,
            text: '还没有订阅，点击上方「添加订阅」填入机场订阅地址',
            action: FilledButton.icon(
              onPressed: () => _showSubscribeDialog(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('添加订阅'),
            ),
          ),
        )
      else
        for (final sub in config.subscribes) ...[
          _SubscribeCard(
            subscribe: sub,
            enabled: !_busy,
            onEdit: () => _showSubscribeDialog(sub),
            onDelete: () => _delete(sub),
            onToggle: (value) => _toggle(sub, value),
          ),
          const SizedBox(height: 10),
        ],
    ];
  }

  Future<void> _showSubscribeDialog([OpenClashSubscribe? existing]) async {
    final result = await showDialog<_SubscribeResult>(
      context: context,
      builder: (_) => _SubscribeDialog(
        existing: existing,
        all: _config?.subscribes ?? const <OpenClashSubscribe>[],
      ),
    );

    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      if (existing == null) {
        await _api.addOpenClashSubscribe(
            result.name, result.address, result.enabled);
      } else {
        await _api.updateOpenClashSubscribe(
          existing.sid,
          name: result.name,
          address: result.address,
          enabled: result.enabled,
        );
      }
      if (!mounted) return;
      showToast(context, existing == null ? '订阅已添加' : '订阅已保存');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showToast(context, '保存失败：${e is ApiException ? e.message : e}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(OpenClashSubscribe sub, bool value) async {
    setState(() => _busy = true);
    try {
      await _api.updateOpenClashSubscribe(sub.sid, enabled: value);
      if (!mounted) return;
      setState(() {
        sub.enabled = value;
      });
    } catch (e) {
      if (!mounted) return;
      showToast(context, '操作失败：${e is ApiException ? e.message : e}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(OpenClashSubscribe sub) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除订阅',
      message: '确定删除订阅「${sub.name ?? '未命名'}」吗？此操作不可恢复。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.deleteOpenClashSubscribe(sub.sid);
      if (!mounted) return;
      showToast(context, '订阅已删除');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showToast(context, '删除失败：${e is ApiException ? e.message : e}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateSubscriptions() async {
    setState(() => _updating = true);
    try {
      final message = await _api.updateOpenClashSubscriptions();
      if (!mounted) return;
      showToast(context, message);
    } catch (e) {
      if (!mounted) return;
      showToast(context, '更新失败：${e is ApiException ? e.message : e}');
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }
}

class _SubscribeCard extends StatelessWidget {
  const _SubscribeCard({
    required this.subscribe,
    required this.enabled,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final OpenClashSubscribe subscribe;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final name = subscribe.name ?? '未命名订阅';
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppTheme.secondary.withValues(alpha: 0.14),
                ),
                child: const Icon(Icons.link_rounded,
                    size: 18, color: AppTheme.secondary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (subscribe.isCurrent) ...[
                          const SizedBox(width: 6),
                          const BadgeChip(
                            '当前使用',
                            color: Color(0xFF27C281),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subscribe.address ?? '未填写地址',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.78,
                child: Switch.adaptive(
                  value: subscribe.enabled,
                  activeTrackColor: AppTheme.primary,
                  onChanged: enabled ? onToggle : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              BadgeChip(
                subscribe.enabled ? '已启用' : '已停用',
                color: subscribe.enabled
                    ? const Color(0xFF27C281)
                    : const Color(0xFF9AA3B2),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: enabled ? onEdit : null,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('编辑', style: TextStyle(fontSize: 12.5)),
              ),
              TextButton.icon(
                onPressed: enabled ? onDelete : null,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFD64545),
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('删除', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubscribeResult {
  const _SubscribeResult(this.name, this.address, this.enabled);

  final String name;
  final String address;
  final bool enabled;
}

/// 订阅编辑弹窗：控制器由弹窗自身持有并在 dispose 时释放，避免关闭动画期间访问已释放对象。
class _SubscribeDialog extends StatefulWidget {
  const _SubscribeDialog({required this.existing, required this.all});

  final OpenClashSubscribe? existing;
  final List<OpenClashSubscribe> all;

  @override
  State<_SubscribeDialog> createState() => _SubscribeDialogState();
}

class _SubscribeDialogState extends State<_SubscribeDialog> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _addrCtrl =
      TextEditingController(text: widget.existing?.address ?? '');
  late bool _enabled = widget.existing?.enabled ?? true;
  String? _nameError;
  String? _addrError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    final address = _addrCtrl.text.trim();
    final duplicate = widget.all.any((s) =>
        s.sid != widget.existing?.sid &&
        (s.name ?? '').toLowerCase() == name.toLowerCase());

    setState(() {
      _nameError = null;
      _addrError = null;
      if (name.isEmpty) {
        _nameError = '请输入名称';
      } else if (name.contains('/')) {
        _nameError = '名称不能包含斜杠';
      } else if (duplicate) {
        _nameError = '名称已存在';
      }
      if (address.isEmpty) {
        _addrError = '请输入订阅地址';
      } else if (!address.startsWith('http://') &&
          !address.startsWith('https://')) {
        _addrError = '地址需以 http:// 或 https:// 开头';
      }
    });
    if (_nameError != null || _addrError != null) return;
    Navigator.pop(context, _SubscribeResult(name, address, _enabled));
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDark(context);
    return AlertDialog(
      backgroundColor: dark ? const Color(0xFF161E30) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        widget.existing == null ? '添加订阅' : '编辑订阅',
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: '名称',
                hintText: '例如 我的机场',
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addrCtrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: '订阅地址',
                hintText: 'https://example.com/sub?token=...',
                errorText: _addrError,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Expanded(
                  child: Text('启用该订阅', style: TextStyle(fontSize: 13.5)),
                ),
                Switch.adaptive(
                  value: _enabled,
                  activeTrackColor: AppTheme.primary,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
              ],
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
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}
