import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';

class GlassNavItem {
  const GlassNavItem(this.icon, this.activeIcon, this.label);

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// 仿 iPhone 的毛玻璃悬浮底部导航栏。
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.index,
    required this.onChanged,
  });

  final int index;
  final ValueChanged<int> onChanged;

  static const items = <GlassNavItem>[
    GlassNavItem(Icons.dashboard_outlined, Icons.dashboard_rounded, '概览'),
    GlassNavItem(Icons.lan_outlined, Icons.lan_rounded, '网络'),
    GlassNavItem(Icons.devices_outlined, Icons.devices_rounded, '设备'),
    GlassNavItem(Icons.wifi_outlined, Icons.wifi_rounded, 'WiFi'),
    GlassNavItem(Icons.settings_outlined, Icons.settings_rounded, '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDark(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset > 0 ? bottomInset + 4 : 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            height: 66,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: dark
                  ? const Color(0xFF111A2C).withValues(alpha: 0.62)
                  : Colors.white.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.14)
                    : Colors.white.withValues(alpha: 0.85),
              ),
              boxShadow: [
                BoxShadow(
                  color: dark
                      ? Colors.black.withValues(alpha: 0.45)
                      : const Color(0xFF35538F).withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              children: List.generate(items.length, (i) {
                final item = items[i];
                final selected = i == index;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(i),
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        padding: EdgeInsets.symmetric(
                          horizontal: selected ? 13 : 8,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.primary
                                  .withValues(alpha: dark ? 0.24 : 0.14)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              selected ? item.activeIcon : item.icon,
                              size: 21,
                              color: selected
                                  ? AppTheme.primary
                                  : scheme.onSurfaceVariant.withValues(alpha: 0.85),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 10,
                                height: 1.1,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected
                                    ? AppTheme.primary
                                    : scheme.onSurfaceVariant
                                        .withValues(alpha: 0.80),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
