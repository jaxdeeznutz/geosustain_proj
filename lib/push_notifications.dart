import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'firebase_runtime.dart';

class PushNotifications {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const vapidKey = String.fromEnvironment('FIREBASE_WEB_VAPID_KEY');
  static bool get configured =>
      apiKey.isNotEmpty &&
      projectId.isNotEmpty &&
      senderId.isNotEmpty &&
      (kIsWeb
          ? webAppId.isNotEmpty && vapidKey.isNotEmpty
          : androidAppId.isNotEmpty &&
                defaultTargetPlatform == TargetPlatform.android);
  static StreamSubscription<String>? _refresh;
  static StreamSubscription<RemoteMessage>? _opened;
  static StreamSubscription<RemoteMessage>? _foreground;
  static void Function(int)? onReviewOpened;
  static void Function(int)? onReviewReceived;

  static int? reviewId(Map<String, dynamic> data) {
    final id = int.tryParse('${data['session_id']}');
    return id != null && id > 0 ? id : null;
  }

  static Future<void> _listen() async {
    if (_opened != null) return;
    _opened = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final id = reviewId(message.data);
      if (id != null) onReviewOpened?.call(id);
    });
    _foreground = FirebaseMessaging.onMessage.listen((message) {
      final id = reviewId(message.data);
      if (id != null) onReviewReceived?.call(id);
    });
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      final id = reviewId(initial.data);
      if (id != null) onReviewOpened?.call(id);
    }
  }

  static Future<void> _initialize() async {
    if (!configured) {
      throw StateError(
        'Push setup is incomplete. Ask the project administrator to configure Firebase.',
      );
    }
    if (!Firebase.apps.any((app) => app.name == '[DEFAULT]')) {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: apiKey,
          appId: kIsWeb ? webAppId : androidAppId,
          messagingSenderId: senderId,
          projectId: projectId,
          authDomain: FirebaseRuntime.options.authDomain,
        ),
      );
    }
  }

  static Future<bool> enabled() async {
    final prefs = await SharedPreferences.getInstance();
    final owner = prefs.getString('account_id');
    return owner != null && (prefs.getBool('push_enabled_$owner') ?? false);
  }

  static Future<void> setEnabled(ApiService api, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final owner = prefs.getString('account_id');
    final sessionToken = await api.getToken();
    if (owner == null) throw StateError('Sign in before changing push alerts.');
    await _initialize();
    if (value) {
      await _listen();
      final permission = await FirebaseMessaging.instance.requestPermission();
      if (permission.authorizationStatus != AuthorizationStatus.authorized &&
          permission.authorizationStatus != AuthorizationStatus.provisional) {
        throw StateError(
          'Notification permission was not granted. Enable it in your device or browser settings.',
        );
      }
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
    }
    final token = await FirebaseMessaging.instance.getToken(
      vapidKey: kIsWeb ? vapidKey : null,
    );
    if (token == null && value) {
      throw StateError('This device did not return a push registration token.');
    }
    if (prefs.getString('account_id') != owner ||
        await api.getToken() != sessionToken) {
      return;
    }
    if (token != null) {
      await api.setPushSubscription(token, value, expectedToken: sessionToken);
    }
    if (prefs.getString('account_id') != owner) return;
    await prefs.setBool('push_enabled_$owner', value);
    await _refresh?.cancel();
    _refresh = null;
    if (value) {
      _refresh = FirebaseMessaging.instance.onTokenRefresh.listen((
        token,
      ) async {
        try {
          if (prefs.getString('account_id') == owner && await enabled()) {
            await api.setPushSubscription(
              token,
              true,
              expectedToken: sessionToken,
            );
          }
        } catch (_) {
          /* Re-register on the next sign-in/settings visit. */
        }
      });
    } else {
      await stop();
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
      await FirebaseMessaging.instance.deleteToken();
    }
  }

  static Future<void> restore(ApiService api) async {
    if (!configured || !await enabled()) return;
    try {
      await _initialize();
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        await setEnabled(api, true);
      }
    } catch (_) {
      /* Network failures leave the preference available for retry. */
    }
  }

  static Future<void> stop() async {
    await _refresh?.cancel();
    _refresh = null;
    await _opened?.cancel();
    await _foreground?.cancel();
    _opened = null;
    _foreground = null;
  }
}
