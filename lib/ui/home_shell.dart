import 'package:flutter/material.dart';

import 'pages/dashboard_page.dart';
import 'pages/devices_page.dart';
import 'pages/network_page.dart';
import 'pages/openclash_page.dart';
import 'pages/services_page.dart';
import 'pages/settings_page.dart';
import 'pages/wifi_page.dart';
import 'theme.dart';
import 'widgets/glass_nav_bar.dart';

/// 应用主框架：内容区 + 毛玻璃底部导航。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  void _openServices() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ServicesPage()),
    );
  }

  void _openOpenClash() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OpenClashPage()),
    );
  }

  Widget _buildPage() {
    switch (_index) {
      case 0:
        return DashboardPage(
          onOpenSettings: () => _select(4),
          onOpenServices: _openServices,
          onOpenOpenClash: _openOpenClash,
        );
      case 1:
        return const NetworkPage();
      case 2:
        return const DevicesPage();
      case 3:
        return const WifiPage();
      default:
        return const SettingsPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: AuroraBackground()),
          Positioned.fill(
            child: KeyedSubtree(key: ValueKey(_index), child: _buildPage()),
          ),
        ],
      ),
      bottomNavigationBar: GlassNavBar(index: _index, onChanged: _select),
    );
  }
}
