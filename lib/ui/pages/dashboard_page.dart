import 'package:flutter/material.dart';

import '../../api/router_api.dart';
import '../../models/models.dart';
import '../theme.dart';
import '../../util/format.dart';
import '../widgets/dialogs.dart';
import '../widgets/glass.dart';

/// 概览页：系统状态、负载、内存与快捷操作。
class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.onOpenSettings,
    required this.onOpenServices,
    required this.onOpenOpenClash,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onOpenServices;
  final VoidCallback onOpenOpenClash;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _api = RouterApi.instance;

  SystemInfo? _info;
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
      final info = await _api.getSystemInfo();
      if (!mounted) return;
      setState(() {
        _info = info;
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
              title: '概览',
              subtitle: _api.hasSession
                  ? _api.config.displayName
                  : '尚未连接路由器，请先在设置中配置',
              trailing: _CircleIconButton(
                icon: Icons.refresh_rounded,
                onTap: _load,
              ),
            ),
            const SizedBox(height: 18),
            if (_loading && _info == null)
              const _LoadingCard()
            else if (_info == null)
              _ErrorCard(
                message: _error ?? '暂无数据',
                onRetry: _load,
                onSettings: widget.onOpenSettings,
              )
            else
              ..._buildContent(_info!),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildContent(SystemInfo info) {
    final memoryPercent = info.memoryTotal <= 0
        ? 0.0
        : (info.memoryUsed / info.memoryTotal).clamp(0.0, 1.0);
    final swapUsed = info.swapTotal - info.swapFree;

    return [
      _HeroCard(info: info),
      if (_error != null) ...[
        const SizedBox(height: 12),
        BadgeChip(
          '刷新失败：$_error',
          color: const Color(0xFFD64545),
          icon: Icons.error_outline_rounded,
        ),
      ],
      const SectionTitle('运行状态'),
      Row(
        children: [
          Expanded(
            child: StatTile(
              icon: Icons.speed_rounded,
              label: '负载 1 分钟',
              value: Fmt.load(info.load1),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StatTile(
              icon: Icons.timeline_rounded,
              label: '负载 5 分钟',
              value: Fmt.load(info.load5),
              color: AppTheme.secondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StatTile(
              icon: Icons.show_chart_rounded,
              label: '负载 15 分钟',
              value: Fmt.load(info.load15),
              color: AppTheme.accent,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '内存占用',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  Fmt.memory(info.memoryTotal, info.memoryUsed),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: memoryPercent,
                minHeight: 8,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation(
                  memoryPercent > 0.85
                      ? const Color(0xFFD64545)
                      : AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Divider(),
            InfoRow('Swap', Fmt.memory(info.swapTotal, swapUsed)),
          ],
        ),
      ),
      const SectionTitle('系统信息'),
      GlassCard(
        child: Column(
          children: [
            InfoRow('设备型号', info.model),
            InfoRow('固件版本', info.firmwareDisplay),
            InfoRow('内核版本', info.kernel),
            InfoRow('主机名', info.hostname),
            InfoRow('运行时长', Fmt.uptime(info.uptime)),
          ],
        ),
      ),
      const SectionTitle('快捷操作'),
      ActionTile(
        icon: Icons.tune_rounded,
        label: '服务与插件管理',
        sublabel: '启停 / 重启 / 开机自启',
        color: AppTheme.primary,
        onTap: widget.onOpenServices,
      ),
      const SizedBox(height: 10),
      ActionTile(
        icon: Icons.shield_moon_rounded,
        label: 'OpenClash 订阅',
        sublabel: '管理订阅地址与更新配置',
        color: AppTheme.secondary,
        onTap: widget.onOpenOpenClash,
      ),
      const SizedBox(height: 10),
      ActionTile(
        icon: Icons.restart_alt_rounded,
        label: '重启路由器',
        sublabel: '网络会中断约 1-2 分钟',
        color: const Color(0xFFD64545),
        onTap: _reboot,
      ),
      const SizedBox(height: 10),
      ActionTile(
        icon: Icons.settings_rounded,
        label: '连接设置',
        sublabel: '修改路由器地址与登录账号',
        color: const Color(0xFF5B6B85),
        onTap: widget.onOpenSettings,
      ),
    ];
  }

  Future<void> _reboot() async {
    final ok = await showConfirmDialog(
      context,
      title: '重启路由器',
      message: '确定要重启路由器吗？重启期间网络将中断约 1-2 分钟。',
      confirmText: '重启',
      danger: true,
    );
    if (!ok || !mounted) return;
    showToast(context, '正在重启路由器…');
    try {
      await _api.reboot();
      if (!mounted) return;
      showToast(context, '重启命令已发送，请等待路由器重新上线');
      setState(() {
        _info = null;
        _error = '路由器正在重启，稍后下拉刷新';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      showToast(context, '重启失败：${e is ApiException ? e.message : e}');
    }
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.info});

  final SystemInfo info;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [Color(0xFF4B7DFF), Color(0xFF7B5CFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4B7DFF).withValues(alpha: 0.32),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.router_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.hostname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      info.model,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF7CFFB2),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      '在线',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.18),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _heroItem('固件', info.release),
              _heroItem('内核', info.kernel),
              _heroItem('运行时长', Fmt.uptime(info.uptime)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroItem(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.70),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.glassFill(context),
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.glassBorder(context)),
      ),
      child: IconButton(
        icon: Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurface),
        onPressed: onTap,
        tooltip: '刷新',
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const GlassCard(
      child: SizedBox(
        height: 180,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              SizedBox(height: 14),
              Text('正在连接路由器…', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.onRetry,
    required this.onSettings,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        children: [
          const SizedBox(height: 8),
          const Icon(Icons.cloud_off_rounded, size: 40, color: Color(0xFF9AA3B2)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重试'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onSettings,
                  icon: const Icon(Icons.settings_rounded, size: 18),
                  label: const Text('去设置'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
