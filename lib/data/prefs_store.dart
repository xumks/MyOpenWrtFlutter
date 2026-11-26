import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// 使用 SharedPreferences 持久化连接配置与会话。
class PrefsStore {
  const PrefsStore._();

  static const _kHost = 'host';
  static const _kPort = 'port';
  static const _kUsername = 'username';
  static const _kPassword = 'password';
  static const _kUseHttps = 'use_https';
  static const _kSession = 'session_id';

  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static bool get hasConfig => _prefs.containsKey(_kHost);

  static RouterConnection loadConfig() {
    if (!hasConfig) return const RouterConnection();
    return RouterConnection(
      host: _prefs.getString(_kHost) ?? '192.168.1.1',
      port: _prefs.getInt(_kPort) ?? 80,
      username: _prefs.getString(_kUsername) ?? 'root',
      password: _prefs.getString(_kPassword) ?? '',
      useHttps: _prefs.getBool(_kUseHttps) ?? false,
    );
  }

  static Future<void> saveConfig(RouterConnection config) async {
    await _prefs.setString(_kHost, config.host);
    await _prefs.setInt(_kPort, config.port);
    await _prefs.setString(_kUsername, config.username);
    await _prefs.setString(_kPassword, config.password);
    await _prefs.setBool(_kUseHttps, config.useHttps);
  }

  static String? get sessionId => _prefs.getString(_kSession);

  static Future<void> saveSession(String sessionId) async {
    await _prefs.setString(_kSession, sessionId);
  }

  static Future<void> clearSession() async {
    await _prefs.remove(_kSession);
  }
}
