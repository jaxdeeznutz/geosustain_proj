import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class FirebaseRuntime {
  static Map<String, dynamic> _bundled = {};
  static String _value(String key, String supplied) =>
      supplied.isNotEmpty ? supplied : '${_bundled[key] ?? ''}';
  static String get apiKey => _value(
    'FIREBASE_API_KEY',
    const String.fromEnvironment('FIREBASE_API_KEY'),
  );
  static String get projectId => _value(
    'FIREBASE_PROJECT_ID',
    const String.fromEnvironment('FIREBASE_PROJECT_ID'),
  );
  static String get senderId => _value(
    'FIREBASE_SENDER_ID',
    const String.fromEnvironment('FIREBASE_SENDER_ID'),
  );
  static String get webAppId =>
      const String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static String get androidAppId => _value(
    'FIREBASE_ANDROID_APP_ID',
    const String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
  );
  static String get googleWebClientId => _value(
    'GOOGLE_WEB_CLIENT_ID',
    const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
  );
  static Future<void> loadBundledConfig() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final data = jsonDecode(
        await rootBundle.loadString('deployment/firebase-android.public.json'),
      );
      if (data is Map<String, dynamic>) _bundled = data;
    } catch (_) {
      _bundled = {};
    }
  }

  static bool get configured =>
      apiKey.isNotEmpty &&
      projectId.isNotEmpty &&
      senderId.isNotEmpty &&
      (kIsWeb
          ? webAppId.isNotEmpty
          : defaultTargetPlatform == TargetPlatform.android &&
                androidAppId.isNotEmpty);
  static FirebaseOptions get options => FirebaseOptions(
    apiKey: apiKey,
    appId: kIsWeb ? webAppId : androidAppId,
    messagingSenderId: senderId,
    projectId: projectId,
    authDomain:
        _value(
          'FIREBASE_AUTH_DOMAIN',
          const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
        ).isNotEmpty
        ? _value(
            'FIREBASE_AUTH_DOMAIN',
            const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
          )
        : '$projectId.firebaseapp.com',
  );
  static Future<FirebaseApp>? _default;
  static Future<FirebaseApp>? _phone;
  static Future<FirebaseApp> initialize() {
    if (!configured) {
      throw StateError('Identity verification is temporarily unavailable.');
    }
    return _default ??= _initialize();
  }

  static Future<FirebaseApp> _initialize() async {
    if (Firebase.apps.any((app) => app.name == '[DEFAULT]')) {
      return Firebase.app();
    }
    return Firebase.initializeApp(options: options);
  }

  static Future<FirebaseApp> phoneApp() {
    if (!configured) {
      throw StateError('Phone verification is temporarily unavailable.');
    }
    // A profile phone proof must never replace the primary Google sign-in identity.
    return _phone ??= Firebase.initializeApp(
      name: 'geosustain-phone-proof',
      options: options,
    );
  }
}
