import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionTokenStore {
  static const channel = MethodChannel('geosustain/session');
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_android) return prefs.getString('token');
    final legacy = prefs.getString('token');
    if (legacy != null) {
      await channel.invokeMethod<void>('write', legacy);
      await prefs.remove('token');
    }
    return channel.invokeMethod<String>('read');
  }

  Future<void> write(String token) async {
    final prefs = await SharedPreferences.getInstance();
    if (_android) {
      await channel.invokeMethod<void>('write', token);
      await prefs.remove('token');
    } else {
      await prefs.setString('token', token);
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    if (_android) await channel.invokeMethod<void>('delete');
    await prefs.remove('token');
  }
}
