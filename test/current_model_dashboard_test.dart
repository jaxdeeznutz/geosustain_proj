import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:geosustain_clean_arranged/web/portal_routes.dart';
import 'qa_support.dart';

final current = <String, dynamic>{
  'current_model_version': 'synthetic-seven-input-model',
  'model_scope': 'current',
  'classes': [
    'banana',
    'cacao',
    'coconut',
    'durian',
    'mango',
    'rice',
    'rubber',
  ],
  'analysis_count': 2,
  'overall_count': 5,
  'archived_count': 3,
  'scored_count': 2,
  'average_model_score': 45,
  'cumulative_area_ha': 2,
  'high_count': 1,
  'medium_count': 0,
  'low_count': 0,
  'very_low_count': 1,
  'frequencies': [
    {'crop': 'Banana', 'count': 1},
    {'crop': 'Rice', 'count': 1},
  ],
  'monthly': [
    {'month': '2026-06', 'count': 0},
    {'month': '2026-07', 'count': 0},
    {'month': '2026-08', 'count': 0},
    {'month': '2026-09', 'count': 1},
    {'month': '2026-10', 'count': 0},
    {'month': '2026-11', 'count': 1},
  ],
  'recent_records': [
    {
      'session_id': 2,
      'case_id': 2,
      'place_name': 'Synthetic parcel',
      'predicted_crop': 'Rice',
      'compatibility_pct': 0,
      'is_crop_recommended': true,
      'area_hectares': 1,
    },
  ],
};

void main() {
  setUpAll(() async {
    for (final family in ['Roboto', 'Ahem']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
    }
  });
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HttpOverrides.global = QaHttpOverrides();
    PortalRoutes.go('/operator/dashboard');
    appThemeMode.value = ThemeMode.light;
  });
  tearDown(() {
    HttpOverrides.global = null;
    appThemeMode.value = ThemeMode.light;
  });

  testWidgets(
    'analyst dashboard replaces loading values when live summary arrives',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ApiService(
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      final state = AnalysisState(api: api)
        ..currentUser = {'id': 1, 'role': 'analyst', 'username': 'Synthetic'};
      addTearDown(state.dispose);
      await tester.pumpWidget(
        GeoSustainApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: state,
                builder: (_, _) => WebDashboardScreen(
                  state: state,
                  onStartAnalyze: () {},
                  onOpenMapAnalysis: () {},
                  onOpenHistory: () {},
                  onOpenReports: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final submitted = find.byKey(const ValueKey('metric-Submitted Analyses'));
      expect(
        find.descendant(of: submitted, matching: find.text('…')),
        findsOneWidget,
      );
      state.currentModelSummary = current;
      state.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: submitted, matching: find.text('2')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final variant in [
    (const Size(1440, 1100), 1.0, false),
    (const Size(1440, 1100), 1.0, true),
    (const Size(360, 800), 2.0, true),
  ]) {
    testWidgets(
      'restored overview keeps metrics and dashboard panels at $variant',
      (tester) async {
        tester.view.physicalSize = variant.$1;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        appThemeMode.value = variant.$3 ? ThemeMode.dark : ThemeMode.light;
        final api = ApiService(
          client: MockClient((r) async => http.Response('{}', 200)),
        );
        final state = AnalysisState(api: api)
          ..currentUser = {'id': 1, 'role': 'analyst', 'username': 'Synthetic'}
          ..currentModelSummary = current;
        const key = ValueKey('overview-current-preview');
        await tester.pumpWidget(
          GeoSustainApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: variant.$1,
                textScaler: TextScaler.linear(variant.$2),
              ),
              child: RepaintBoundary(
                key: key,
                child: Scaffold(
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
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final title in [
          'Submitted Analyses',
          'Average Ranking Score',
          'Most Frequent Recommendation',
          'Get Started with GeoSustain',
          'Quick Actions',
          'Recent Submissions',
        ]) {
          expect(find.text(title), findsOneWidget);
        }
        expect(find.text('45.0%'), findsOneWidget);
        expect(find.text('Start New Analysis'), findsNothing);
        expect(PortalRoutes.signInLanding('analyst'), '/operator/dashboard');
        expect(tester.takeException(), isNull);
        if (variant.$2 == 1) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(key),
            );
            final img = await boundary.toImage();
            final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
            final dir = Directory('build/overview-patterns-previews')
              ..createSync(recursive: true);
            File(
              '${dir.path}/overview-${variant.$3 ? 'dark' : 'light'}.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
            img.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      },
    );
  }

  testWidgets(
    'analyst patterns default to all submitted cases and allow a current-model filter',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <http.Request>[];
      final api = ApiService(
        client: MockClient((r) async {
          requests.add(r);
          return http.Response(
            jsonEncode({
              ...current,
              if (r.url.queryParameters['model_scope'] == 'all') ...{
                'model_scope': 'all',
                'average_model_score': 84.3,
                'frequencies': [
                  {'crop': 'Banana (Cavendish/Lakatan)', 'count': 11},
                ],
              },
            }),
            200,
          );
        }),
      );
      await api.saveToken('synthetic-patterns');
      final state = AnalysisState(api: api)
        ..currentUser = {'id': 1, 'role': 'analyst'}
        ..currentModelSummary = current
        ..webSummary = {'average_model_score': 84.3, 'analysis_count': 18};
      await tester.pumpWidget(
        GeoSustainApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WebCropTrendsScreen(state: state),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('84.3%'), findsOneWidget);
      expect(find.text('45.0%'), findsNothing);
      expect(find.text('Banana (Cavendish/Lakatan)'), findsWidgets);
      expect(find.textContaining('not directly comparable'), findsOneWidget);
      final chart = find.descendant(
        of: find.byKey(const ValueKey('patterns-trend-panel')),
        matching: find.byType(CustomPaint),
      );
      expect(tester.getSize(chart).width, greaterThan(500));
      await tester.tap(find.byKey(const ValueKey('patterns-model-scope')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Current seven-crop version').last);
      await tester.pumpAndSettle();
      expect(requests.last.url.path, '/api/operator/recommendation-patterns');
      expect(requests.last.url.queryParameters['model_scope'], 'current');
      expect(find.text('45.0%'), findsOneWidget);
      expect(find.text('Rubber'), findsOneWidget);
      expect(find.textContaining('3 older or unversioned'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'patterns replace cached empty totals with fresh submitted rankings',
    (tester) async {
      var requests = 0;
      final api = ApiService(
        client: MockClient((r) async {
          requests++;
          return http.Response(
            jsonEncode({
              ...current,
              'model_scope': 'all',
              'average_model_score': 47.8,
              'high_count': 0,
              'medium_count': 1,
              'low_count': 1,
              'very_low_count': 0,
              'frequencies': [
                {'crop': 'Mango', 'count': 2},
              ],
            }),
            200,
          );
        }),
      );
      await api.saveToken('synthetic-refresh');
      final state = AnalysisState(api: api)
        ..currentUser = {'id': 1, 'role': 'analyst'}
        ..currentModelSummary = {
          ...current,
          'scored_count': 0,
          'average_model_score': null,
          'frequencies': [],
          'monthly': [],
        };
      await tester.pumpWidget(
        GeoSustainApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WebCropTrendsScreen(state: state),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('47.8%'), findsOneWidget);
      expect(find.text('Mango'), findsWidgets);
      expect(find.text('No data'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'failed patterns request never falls back to old all-time scores',
    (tester) async {
      final api = ApiService(
        client: MockClient(
          (r) async => http.Response('{"detail":"Unavailable"}', 503),
        ),
      );
      await api.saveToken('synthetic-failure');
      final state = AnalysisState(api: api)
        ..currentUser = {'id': 1, 'role': 'analyst'}
        ..webSummary = {'analysis_count': 18, 'average_model_score': 84.3};
      await tester.pumpWidget(
        GeoSustainApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WebCropTrendsScreen(state: state),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('84.3%'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Refresh patterns'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
