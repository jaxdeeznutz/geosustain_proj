import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:geosustain_clean_arranged/web/web_record_controller.dart';
import 'package:geosustain_clean_arranged/web/portal_routes.dart';
import 'operator_workflow_test.dart' show fixture;
import 'qa_support.dart';

final cases = [
  for (var i = 1; i <= 5; i++)
    {
      'case_id': i,
      'farm_id': i,
      'farm_name': 'Synthetic farm $i',
      'farmer_name': 'Synthetic farmer',
      'place_name': 'Panabo City',
      'verification_status': 'pending',
      'review_version': i,
      'submitted_at': '2026-11-01',
      'center_lat': 7.29,
      'center_lon': 125.62,
      'analysis_mode': 'crop_model',
      'is_crop_recommended': true,
      'compatibility_pct': i == 1 ? 0 : 40 + i,
      'selected_polygon': [
        {'lat': 7.29, 'lng': 125.62},
        {'lat': 7.291, 'lng': 125.62},
        {'lat': 7.291, 'lng': 125.621},
      ],
    },
];
final totals = {
  'cases': 25,
  'pending_count': 5,
  'information_count': 3,
  'verified_count': 15,
  'rejected_count': 2,
};

void main() {
  setUpAll(() async {
    for (final family in ['Roboto', 'Ahem']) {
      final font = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
      await font.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HttpOverrides.global = QaHttpOverrides();
    appThemeMode.value = ThemeMode.light;
    PortalRoutes.go('/');
  });
  tearDown(() {
    HttpOverrides.global = null;
    appThemeMode.value = ThemeMode.light;
  });

  test(
    'fresh analyst sign-in lands on overview and retired URLs preserve submitted references',
    () {
      for (final role in [
        'analyst',
        'planner',
        'agricultural_planning_analyst',
      ]) {
        expect(PortalRoutes.signInLanding(role), '/operator/dashboard');
      }
      expect(PortalRoutes.signInLanding('farmer'), isNull);
      expect(
        PortalRoutes.analystRoute(Uri.parse('/operator/analyze')).path,
        '/operator/dashboard',
      );
      expect(
        PortalRoutes.analystRoute(
          Uri.parse('/operator/history?session=42'),
        ).toString(),
        '/operator/queue?session=42',
      );
      expect(
        PortalRoutes.analystRoute(
          Uri.parse('/operator/queue?case=7'),
        ).toString(),
        '/operator/queue?case=7',
      );
    },
  );

  for (final variant in [
    (const Size(1920, 1080), 1.0, false),
    (const Size(1440, 1000), 1.0, true),
    (const Size(768, 1000), 1.0, false),
    (const Size(360, 800), 2.0, true),
  ]) {
    testWidgets('inbox real counts, cards and accessible filters at $variant', (
      tester,
    ) async {
      tester.view.physicalSize = variant.$1;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      appThemeMode.value = variant.$3 ? ThemeMode.dark : ThemeMode.light;
      final requests = <http.Request>[];
      final api = ApiService(
        client: MockClient((r) async {
          requests.add(r);
          return http.Response(
            jsonEncode(
              r.url.path.endsWith('/overview')
                  ? totals
                  : {'queue': cases, 'has_more': false},
            ),
            200,
          );
        }),
      );
      await api.saveToken('synthetic-review-test');
      final state = AnalysisState(api: api)
        ..currentUser = {
          'id': 99,
          'role': 'analyst',
          'username': 'Synthetic Analyst',
        };
      final c = WebRecordController(api, '/api/operator/inbox', 'queue');
      await c.filter({'status': 'pending'});
      PortalRoutes.go('/operator/queue');
      const preview = ValueKey('inbox-preview');
      await tester.pumpWidget(
        GeoSustainApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: variant.$1,
              textScaler: TextScaler.linear(variant.$2),
            ),
            child: RepaintBoundary(
              key: preview,
              child: WebAnalystDashboard(
                state: state,
                logout: () {},
                message: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('25'), findsOneWidget);
      expect(find.text('Decision History'), findsOneWidget);
      expect(find.text('0.0%'), findsOneWidget);
      expect(find.byKey(const ValueKey('inbox-case-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (variant.$2 == 1) {
        await tester.runAsync(() async {
          final context = tester.element(find.byType(WebAnalystDashboard));
          await precacheImage(
            const AssetImage('assets/images/web/eco_valley_panorama.png'),
            context,
          );
          await precacheImage(
            const AssetImage('assets/images/web/analyst_sidebar_valley.png'),
            context,
          );
        });
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final render = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(preview),
          );
          final picture = await render.toImage();
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final dir = Directory('build/analyst-review-previews')
            ..createSync(recursive: true);
          File(
            '${dir.path}/inbox-${variant.$1.width.toInt()}-${variant.$3 ? 'dark' : 'light'}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }
      await tester.ensureVisible(find.text('List View'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('List View'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('inbox-case-5')), findsOneWidget);
      await tester.ensureVisible(find.text('Decision History'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Decision History'));
      await tester.pumpAndSettle();
      expect(
        requests
            .lastWhere((r) => r.url.path.endsWith('/inbox'))
            .url
            .queryParameters['view'],
        'decisions',
      );
      await tester.ensureVisible(find.text('Requests (3)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Requests (3)'));
      await tester.pumpAndSettle();
      expect(
        requests
            .lastWhere((r) => r.url.path.endsWith('/inbox'))
            .url
            .queryParameters['status'],
        'needs_information',
      );
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      state.dispose();
    });
  }

  testWidgets(
    'filter drafts survive totals loading, dates validate before requests and details are read-only',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final summary = Completer<http.Response>();
      final requests = <http.Request>[];
      final api = ApiService(
        client: MockClient((r) async {
          requests.add(r);
          return r.url.path.endsWith('/overview')
              ? summary.future
              : http.Response(
                  jsonEncode({
                    'queue': [cases.first],
                    'has_more': false,
                  }),
                  200,
                );
        }),
      );
      await api.saveToken('synthetic-filters');
      final c = WebRecordController(api, '/api/operator/inbox', 'queue');
      await c.filter({'status': 'pending'});
      await tester.pumpWidget(
        GeoSustainApp(
          home: Scaffold(
            body: SingleChildScrollView(child: WebOperatorInbox(controller: c)),
          ),
        ),
      );
      await tester.pump();
      final search = find.widgetWithText(
        TextField,
        'Search case, farmer or farm',
      );
      await tester.enterText(search, 'Draft farm');
      summary.complete(http.Response(jsonEncode(totals), 200));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, 'Draft farm');
      final date = find.widgetWithText(TextField, 'From submission date');
      await tester.enterText(date, '2026-02-30');
      final count = requests.length;
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Enter valid YYYY-MM-DD dates'),
        findsOneWidget,
      );
      expect(requests.length, count);
      await tester.enterText(date, '2026-11-01');
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();
      final applied = requests
          .lastWhere((r) => r.url.path.endsWith('/inbox'))
          .url
          .queryParameters;
      expect(applied['q'], 'Draft farm');
      expect(applied['start'], '2026-11-01');
      final beforeDetails = requests.length;
      await tester.ensureVisible(find.text('View Details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View Details'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(requests.length, beforeDetails);
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      api.close();
    },
  );

  testWidgets(
    'case timeout ends loading, retry succeeds and late response cannot overwrite',
    (tester) async {
      final slow = Completer<http.Response>();
      var count = 0;
      final api = ApiService(
        client: MockClient((r) async {
          count++;
          return count == 1
              ? slow.future
              : http.Response(jsonEncode(fixture()), 200);
        }),
      );
      await api.saveToken('synthetic-timeout');
      final state = AnalysisState(api: api)
        ..currentUser = {'id': 1, 'role': 'analyst'};
      await tester.pumpWidget(
        GeoSustainApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WebReviewWorkbench(state: state, reference: '7'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 21));
      await tester.pump();
      expect(find.textContaining('Case loading took too long'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(count, 1);
      await tester.tap(find.text('Retry loading case'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Case loading took too long'), findsNothing);
      expect(count, 2);
      slow.complete(http.Response('{}', 200));
      await tester.pumpAndSettle();
      expect(find.textContaining('incomplete case details'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'shared map location opens case chooser and navigates to selected case',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ApiService(
        client: MockClient(
          (r) async => http.Response(
            jsonEncode({'queue': cases, 'has_more': false}),
            200,
          ),
        ),
      );
      await api.saveToken('synthetic-map');
      final state = AnalysisState(api: api)
        ..currentUser = {'id': 1, 'role': 'analyst'};
      final c = WebRecordController(
        api,
        '/api/operator/map',
        'queue',
        limit: 50,
      );
      await c.load();
      await tester.pumpWidget(
        GeoSustainApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WebOperatorMap(
                state: state,
                controller: c,
                mapController: MapController(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final marker = find.byType(ReviewCaseMapMarker);
      expect(marker, findsOneWidget);
      expect(tester.getSize(marker), const Size(72, 72));
      await tester.ensureVisible(marker);
      await tester.tap(marker);
      await tester.pumpAndSettle();
      expect(find.text('Cases at this location'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('Synthetic farm 3'),
        ),
      );
      await tester.pumpAndSettle();
      expect(PortalRoutes.current.value.toString(), '/operator/queue?case=3');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      state.dispose();
    },
  );
}
