import 'package:flutter/material.dart';

import 'api/router_api.dart';
import 'data/prefs_store.dart';
import 'ui/home_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PrefsStore.init();
  RouterApi.instance.initFromSaved();
  runApp(const OpenWrtApp());
}

class OpenWrtApp extends StatelessWidget {
  const OpenWrtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenWrt 管理',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const HomeShell(),
    );
  }
}
