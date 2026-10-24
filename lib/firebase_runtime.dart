import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseRuntime {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );
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
    authDomain: const String.fromEnvironment('FIREBASE_AUTH_DOMAIN').isNotEmpty
        ? const String.fromEnvironment('FIREBASE_AUTH_DOMAIN')
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
