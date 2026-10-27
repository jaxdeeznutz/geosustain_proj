import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:geosustain_clean_arranged/push_notifications.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final width in [360.0, 1280.0]) {
    testWidgets('login gives field-specific missing/format errors at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const GeoSustainApp(home: LoginPage()));
      final button = find.widgetWithText(FilledButton, 'Sign In');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'invalid-email');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a valid email address, such as you@example.com.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
  test('push routing rejects invalid record identities', () {
    for (final value in [null, 'abc', '-1', '0', 'https://example.com']) {
      expect(PushNotifications.reviewId({'session_id': value}), isNull);
    }
    expect(PushNotifications.reviewId({'session_id': '25'}), 25);
  });
  testWidgets(
    'notification read persists across reload; paging remains bounded',
    (tester) async {
      bool read = false;
      final requests = <Uri>[];
      final api = ApiService(
        client: MockClient((request) async {
          requests.add(request.url);
          if (request.url.path.endsWith('/activity/7/read')) {
            read = true;
            return http.Response('{}', 200);
          }
          if (request.url.path.endsWith('/analyses/8')) {
            return http.Response(
              '{"analysis":{"verification_status":"verified","planner_notes":"Synthetic accepted review"}}',
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'notifications': [
                {
                  'id': 7,
                  'session_id': 8,
                  'decision': 'verified',
                  'event_type': 'review',
                  'created_at': '2026-10-23',
                  'read_at': read ? '2026-10-23' : null,
                },
              ],
              'unread_count': read ? 0 : 1,
              'has_more': true,
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(GeoSustainApp(home: NotificationsPage(api: api)));
      await tester.pumpAndSettle();
      expect(find.text('1 unread notifications'), findsOneWidget);
      await tester.tap(find.text('Analysis review: verified'));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic accepted review'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('0 unread notifications'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(requests.last.queryParameters['offset'], '50');
      expect(requests.last.queryParameters['limit'], '50');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('notification failure explains retry instead of empty success', (
    tester,
  ) async {
    bool fail = true;
    final api = ApiService(
      client: MockClient(
        (request) async => fail
            ? http.Response('{"detail":"Inbox unavailable"}', 503)
            : http.Response(
                '{"notifications":[],"unread_count":0,"has_more":false}',
                200,
              ),
      ),
    );
    addTearDown(api.close);
    await tester.pumpWidget(GeoSustainApp(home: NotificationsPage(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('No notifications match'), findsNothing);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No notifications match'), findsOneWidget);
  });
  testWidgets(
    'foreign notification tap never displays or marks a review read',
    (tester) async {
      int writes = 0;
      final api = ApiService(
        client: MockClient((request) async {
          if (request.method == 'POST') writes++;
          if (request.url.path.contains('/analyses/')) {
            return http.Response('{"detail":"Analysis not found"}', 404);
          }
          return http.Response(
            '{"notifications":[],"unread_count":0,"has_more":false}',
            200,
          );
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        GeoSustainApp(home: NotificationsPage(api: api, initialSessionId: 99)),
      );
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(find.text('Analysis review'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
