import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:geosustain_clean_arranged/web/portal_routes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'audit uses eight records, next/previous offsets and resets search to page one',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <Uri>[];
      final api = ApiService(
        client: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/audit-logs')) {
            requests.add(request.url);
            expect(request.url.queryParameters['limit'], '8');
            final offset = int.parse(request.url.queryParameters['offset']!);
            final q = request.url.queryParameters['q'] ?? '';
            final rows = List.generate(
              9,
              (i) => <String, dynamic>{
                'id': i + 1,
                'actor_username': 'Audit actor ${i + 1}',
                'actor_role': 'farmer',
                'action': 'sign_in',
                'details': {'method': 'password'},
                'created_at': '2026-11-09T00:00:00Z',
              },
            ).where((row) => '${row['actor_username']}'.contains(q)).toList();
            return http.Response(
              jsonEncode({
                'logs': rows.skip(offset).take(8).toList(),
                'has_more': rows.length > offset + 8,
              }),
              200,
            );
          }
          if (path.endsWith('/system-status')) {
            return http.Response(
              jsonEncode({
                'checked_at': '2026-11-09T00:00:00Z',
                'status': 'healthy',
                'checks': [],
              }),
              200,
            );
          }
          if (path.endsWith('/dashboard')) {
            return http.Response('{"stats":{}}', 200);
          }
          return http.Response(
            jsonEncode({
              path.endsWith('/users')
                      ? 'users'
                      : path.endsWith('/analyses')
                      ? 'analyses'
                      : 'crops':
                  [],
              'has_more': false,
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      PortalRoutes.go('/admin/audit');
      await tester.pumpWidget(
        MaterialApp(
          home: WebAdminDashboard(api: api, logout: () {}, message: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Audit actor 8'), findsOneWidget);
      expect(find.text('Audit actor 9'), findsNothing);
      expect(find.textContaining('up to 8 records'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Next'));
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      expect(requests.last.queryParameters['offset'], '8');
      expect(find.text('1 displayed · Page 2'), findsOneWidget);
      expect(find.text('Audit actor 9'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Previous'));
      await tester.pumpAndSettle();
      expect(requests.last.queryParameters['offset'], '0');
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('admin-search-4-'));
      await tester.ensureVisible(search);
      await tester.enterText(search, 'Audit actor 2');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(requests.last.queryParameters['offset'], '0');
      expect(requests.last.queryParameters['q'], 'Audit actor 2');
      expect(find.text('1 displayed · Page 1'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == 'Audit actor 2',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reference catalog stays visible while records time out, then refresh recovers',
    (tester) async {
      final pending = Completer<http.Response>();
      var recordCalls = 0;
      final catalog =
          jsonDecode(
                File(
                  'test/fixtures/controlled_catalog.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final hash = (catalog['installed_model'] as Map)['sha256'];
      final api = ApiService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/catalog')) {
            return http.Response(jsonEncode(catalog), 200);
          }
          recordCalls++;
          if (recordCalls == 1) return pending.future;
          return http.Response('{"records":[],"has_more":false}', 200);
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ControlledRecordsPanel(api: api),
            ),
          ),
        ),
      );
      expect(find.text('Trusted model: Checking…'), findsOneWidget);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Trusted model: $hash'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('Reference records:'), findsOneWidget);
      expect(find.text('Trusted model: $hash'), findsOneWidget);
      expect(
        find.textContaining('No controlled records saved yet'),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Refresh records'));
      await tester.pumpAndSettle();
      expect(recordCalls, 2);
      expect(find.textContaining('Reference records:'), findsNothing);
      expect(
        find.textContaining('No controlled records saved yet'),
        findsOneWidget,
      );
      pending.complete(http.Response('{"records":[],"has_more":false}', 200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
