import 'package:flutter/material.dart';

import '../../api/router_api.dart';
import '../../models/models.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/glass.dart';

/// 服务与插件管理页。
class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key});

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  final _api = RouterApi.instance;
  final _searchController = TextEditingController();

  List<ServiceInfo> _all = [];
  String _query = '';
  String _filter = 'all';
  String? _error;
  String? _busyName;
  bool _loading = true;

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
      final list = await _api.getServices();
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

  List<ServiceInfo> get _filtered {
    final q = _query.trim().toLowerCase();
    return _all.where((s) {
      if (q.isNotEmpty && !s.name.toLowerCase().contains(q)) return false;
      switch (_filter) {
        case 'running':
          return s.running;
        case 'enabled':
          return s.enabled;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: '服务与插件',
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: '刷新',
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: '搜索服务名称，如 openclash',
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
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _filterChip('all', '全部'),
                const SizedBox(width: 8),
                _filterChip('running', '运行中'),
                const SizedBox(width: 8),
                _filterChip('enabled', '开机自启'),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AppTheme.primary,
              child: _buildList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => setState(() => _filter = value),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? Colors.white : Theme.of(context).colorScheme.onSurface,
      ),
      selectedColor: AppTheme.primary,
      backgroundColor: AppTheme.glassFill(context),
      side: BorderSide(color: AppTheme.glassBorder(context)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _buildList() {
    if (_loading && _all.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
        ],
      );
    }

    final list = _filtered;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: BadgeChip(
              '加载失败：$_error',
              color: const Color(0xFFD64545),
              icon: Icons.error_outline_rounded,
            ),
          ),
        if (list.isEmpty)
          GlassCard(
            child: EmptyView(
              icon: Icons.extension_off_rounded,
              text: _all.isEmpty ? (_error ?? '没有可管理的服务') : '没有匹配的服务',
              action: FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重新加载'),
              ),
            ),
          ),
        for (final service in list) ...[
          _ServiceCard(
            service: service,
            busy: _busyName == service.name,
            onAction: (action) => _action(service, action),
            onToggleEnabled: (value) =>
                _action(service, value ? 'enable' : 'disable'),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Future<void> _action(ServiceInfo service, String action) async {
    if (action == 'stop') {
      final ok = await showConfirmDialog(
        context,
        title: '停止服务',
        message: '停止 ${service.name} 后，依赖它的功能将不可用，确定继续吗？',
        confirmText: '停止',
        danger: true,
      );
      if (!ok || !mounted) return;
    }

    setState(() => _busyName = service.name);
    try {
      await _api.serviceAction(service.name, action);
      if (!mounted) return;
      showToast(context, '${service.name}：$action 执行成功');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showToast(context, '操作失败：${e is ApiException ? e.message : e}');
    } finally {
      if (mounted) setState(() => _busyName = null);
    }
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.service,
    required this.busy,
    required this.onAction,
    required this.onToggleEnabled,
  });

  final ServiceInfo service;
  final bool busy;
  final ValueChanged<String> onAction;
  final ValueChanged<bool> onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    final subtitle = <String>[
      service.runningText,
      'PID ${service.pidDisplay}',
      service.startOrderDisplay,
      if (service.instanceCount > 1) '${service.instanceCount} 实例',
    ].join(' · ');

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 13, 10, 8),
      radius: 20,
      child: Column(
        children: [
          Row(
            children: [
              StatusDot(active: service.running),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (!service.hasInit)
                const BadgeChip('仅运行实例',
                    color: Color(0xFF9AA3B2)),
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz_rounded, size: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  onSelected: onAction,
                  itemBuilder: (ctx) => [
                    _menuItem('start', Icons.play_arrow_rounded, '启动', !service.running),
                    _menuItem('stop', Icons.stop_rounded, '停止', service.running),
                    _menuItem('restart', Icons.restart_alt_rounded, '重启', true),
                  ],
                ),
            ],
          ),
          if (service.hasInit)
            Row(
              children: [
                const SizedBox(width: 1),
                Text(
                  '开机自启',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
                const Spacer(),
                Text(
                  service.enabledText,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: service.enabled
                        ? const Color(0xFF27C281)
                        : AppTheme.textSecondary(context),
                  ),
                ),
                Transform.scale(
                  scale: 0.78,
                  child: Switch.adaptive(
                    value: service.enabled,
                    activeTrackColor: AppTheme.primary,
                    onChanged: busy ? null : onToggleEnabled,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
      String value, IconData icon, String label, bool enabled) {
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
