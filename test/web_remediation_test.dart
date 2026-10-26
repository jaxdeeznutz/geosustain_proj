import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:geosustain_clean_arranged/web/web_record_controller.dart';
import 'package:geosustain_clean_arranged/web/portal_routes.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appThemeMode.value = ThemeMode.light;
    PortalRoutes.go('/');
  });
  test(
    'bounded search discards an older query response and preserves stale data on error',
    () async {
      final slow = Completer<http.Response>();
      final requests = <Uri>[];
      final api = ApiService(
        client: MockClient((request) async {
          requests.add(request.url);
          if (request.url.queryParameters['q'] == 'first') return slow.future;
          if (request.url.queryParameters['q'] == 'error') {
            return http.Response('{"detail":"Try again"}', 503);
          }
          return http.Response(
            '{"history":[{"session_id":2}],"has_more":true}',
            200,
          );
        }),
      );
      final model = WebRecordController(api, '/api/web/history', 'history');
      model.query = 'first';
      final first = model.load();
      await Future<void>.delayed(Duration.zero);
      model.query = 'second';
      await model.load();
      slow.complete(http.Response('{"history":[{"session_id":1}]}', 200));
      await first;
      expect(model.rows.single['session_id'], 2);
      expect(model.more, isTrue);
      expect(requests.every((u) => u.queryParameters['limit'] == '20'), isTrue);
      expect(requests.length, 2);
      model.query = 'error';
      await model.load();
      expect(model.error, 'Try again');
      expect(model.rows.single['session_id'], 2);
      model.dispose();
      api.close();
    },
  );
  testWidgets(
    'desktop account deletion cancellation sends no request and identity is visible',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var calls = 0;
      final state =
          AnalysisState(
              api: ApiService(
                client: MockClient((_) async {
                  calls++;
                  return http.Response('{}', 500);
                }),
              ),
            )
            ..currentUser = {
              'id': 1,
              'role': 'analyst',
              'username': 'Test',
              'email': 'synthetic@example.com',
            };
      await tester.pumpWidget(
        GeoSustainApp(
          home: Scaffold(
            body: SingleChildScrollView(child: WebSettingsScreen(state: state)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Phone number'), findsOneWidget);
      final delete = find.text('Delete Account');
      await tester.ensureVisible(delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(find.text('Delete your account?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  for (final size in [
    const Size(1000, 500),
    const Size(480, 700),
    const Size(1280, 900),
  ]) {
    testWidgets('operator shell stays usable at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AnalysisState()
        ..currentUser = {'id': 1, 'role': 'analyst', 'username': 'Synthetic'}
        ..userLoaded = true;
      PortalRoutes.go('/operator/settings');
      await tester.pumpWidget(
        GeoSustainApp(
          home: WebAnalystDashboard(
            state: state,
            logout: () {},
            message: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.byTooltip('Toggle dark mode'), findsOneWidget);
      await tester.tap(find.byTooltip('Toggle dark mode'));
      await tester.pumpAndSettle();
      expect(appThemeMode.value, ThemeMode.dark);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    });
  }
  testWidgets(
    'real score distribution includes zero and never invents a segment',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WebModelScoreDistribution(
              records: [
                {
                  'session_id': 1,
                  'predicted_crop': 'Rice',
                  'compatibility_pct': 0,
                },
                {
                  'session_id': 2,
                  'predicted_crop': 'Rice',
                  'compatibility_pct': 100,
                },
              ],
            ),
          ),
        ),
      );
      expect(find.text('0–<25: 1 (50.0%)'), findsOneWidget);
      expect(find.text('75–100: 1 (50.0%)'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
  for (final size in [const Size(480, 700), const Size(1280, 900)]) {
    testWidgets('dashboard reflows without clipped panels at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AnalysisState()
        ..currentUser = {'id': 1, 'role': 'analyst', 'username': 'Synthetic'}
        ..userLoaded = true;
      await tester.pumpWidget(
        GeoSustainApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WebDashboardScreen(
                state: state,
                onStartAnalyze: () {},
                onOpenMapAnalysis: () {},
                onOpenHistory: () {},
                onOpenReports: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    });
  }
  test('chosen portal text/surface pairs retain normal text contrast', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      appThemeMode.value = mode;
      for (final foreground in [
        WebPortalColors.ink,
        WebPortalColors.muted,
        WebPortalColors.accent,
      ]) {
        final a = foreground.computeLuminance(),
            b = WebPortalColors.surface.computeLuminance();
        expect(
          ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });
}
