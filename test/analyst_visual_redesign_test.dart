import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/web/portal_routes.dart';
import 'qa_support.dart';

// Every number below is a synthetic UI fixture, never a provider observation.
final _records = <Map<String, dynamic>>[
  {
    'session_id': 71,
    'place_name': 'Synthetic North parcel',
    'predicted_crop': 'Rice',
    'compatibility_pct': 0,
    'area_hectares': 1.25,
    'verification_status': 'verified',
    'analyzed_at': '2026-10-01T08:00:00Z',
  },
  {
    'session_id': 72,
    'place_name': 'Synthetic South parcel',
    'predicted_crop': 'Mango',
    'compatibility_pct': 100,
    'area_hectares': 2.5,
    'verification_status': 'pending',
    'analyzed_at': '2026-10-02T08:00:00Z',
  },
  {
    'session_id': 73,
    'place_name': 'Synthetic West parcel',
    'analysis_mode': 'preliminary_environmental',
    'area_hectares': 0.5,
    'verification_status': 'not_submitted',
    'analyzed_at': '2026-09-01T08:00:00Z',
  },
];

final _cases = <Map<String, dynamic>>[
  {
    'case_id': 41,
    'farm_id': 81,
    'farm_name': 'Synthetic farmer parcel',
    'verification_status': 'pending',
    'center_lat': 7.29,
    'center_lon': 125.62,
    'area_hectares': 1.25,
    'submitted_at': '2026-10-02T08:00:00Z',
    'selected_polygon': [
      {'lat': 7.29, 'lng': 125.62},
      {'lat': 7.291, 'lng': 125.62},
      {'lat': 7.291, 'lng': 125.621},
    ],
  },
];

Future<AnalysisState> _fixture(
  List<http.Request> requests, {
  List<Map<String, dynamic>> reportRows = const [],
  List<Map<String, dynamic>> activityRows = const [],
}) async {
  var activityRead = false;
  final api = ApiService(
    client: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (path.endsWith('/activity/read-all')) {
        activityRead = true;
        return http.Response('{}', 200);
      }
      if (path.endsWith('/activity')) {
        final params = request.url.queryParameters;
        final rows = activityRows
            .map((r) => {...r, if (activityRead) 'read_at': '2026-10-30'})
            .where(
              (r) =>
                  (params['event_type'] == null ||
                      r['event_type'] == params['event_type']) &&
                  (params['unread_only'] != 'true' || r['read_at'] == null),
            )
            .toList();
        return http.Response(
          jsonEncode({
            'notifications': rows,
            'unread_count': activityRead
                ? 0
                : activityRows.where((r) => r['read_at'] == null).length,
            'has_more': false,
          }),
          200,
        );
      }
      if (path.endsWith('/reports')) {
        final query = request.url.queryParameters['q'] ?? '';
        return http.Response(
          jsonEncode({
            'reports': reportRows
                .where(
                  (r) =>
                      '${r['session_id']} ${r['place_name']} ${r['farm_name_snapshot']}'
                          .toLowerCase()
                          .contains(query.toLowerCase()),
                )
                .toList(),
            'has_more': false,
          }),
          200,
        );
      }
      if (path.endsWith('/history')) {
        final query = request.url.queryParameters['q'] ?? '';
        return http.Response(
          jsonEncode({
            'history': _records
                .where(
                  (r) => '${r['place_name']}'.toLowerCase().contains(
                    query.toLowerCase(),
                  ),
                )
                .toList(),
            'has_more': false,
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'queue': path.endsWith('/map') ? _cases : [],
          'history': [],
          'reports': [],
          'has_more': false,
        }),
        200,
      );
    }),
  );
  await api.saveToken('synthetic-design-token');
  return AnalysisState(api: api)
    ..currentUser = {
      'id': 1,
      'role': 'analyst',
      'username': 'Synthetic Analyst',
    }
    ..userLoaded = true
    ..historyRecords.addAll(_records)
    ..liveWeather = {
      'temperature_c': 26.7,
      'rainfall_today_mm': 3.7,
      'humidity_pct': 77,
      'condition': 'Synthetic weather',
    }
    ..webSummary = {
      'analysis_count': 3,
      'average_model_score': 50,
      'cumulative_area_ha': 4.25,
      'frequencies': [
        {'crop': 'Rice', 'count': 1},
        {'crop': 'Mango', 'count': 1},
      ],
      'monthly': [
        {'month': '2026-09', 'count': 1},
        {'month': '2026-10', 'count': 1},
      ],
      'scored_count': 2,
      'high_count': 1,
      'medium_count': 0,
      'low_count': 0,
      'very_low_count': 1,
    };
}

Future<void> _pumpPortal(
  WidgetTester tester,
  AnalysisState state,
  String page,
  Size size, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  PortalRoutes.go('/operator/$page');
  await tester.pumpWidget(
    GeoSustainApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: RepaintBoundary(
          key: const ValueKey('analyst-design-preview'),
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
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('analyst-design-preview')),
    );
    final picture = await boundary.toImage();
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/analyst-redesign-previews')
      ..createSync(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  setUpAll(() async {
    // Readable preview typography. Noto Sans is only a test fallback for Roboto.
    final loader = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    await loader.load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HttpOverrides.global = QaHttpOverrides();
    appThemeMode.value = ThemeMode.light;
  });
  tearDown(() => HttpOverrides.global = null);

  testWidgets(
    'review layout keeps all filters and empty-results pagination separate',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <http.Request>[];
      final state = await _fixture(requests);
      await _pumpPortal(tester, state, 'queue', const Size(1440, 1100));
      expect(
        find.byKey(const ValueKey('review-filters-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('review-results-panel')),
        findsOneWidget,
      );
      expect(find.text('No review cases found'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'From submission date'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextField, 'Through submission date'),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Review status'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accepted').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();
      expect(
        requests
            .lastWhere((r) => r.url.path.endsWith('/inbox'))
            .url
            .queryParameters['status'],
        'verified',
      );
      expect(find.text('Previous page'), findsOneWidget);
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'web activity keeps server filters and explicit mark-read behavior',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <http.Request>[];
      final state = await _fixture(
        requests,
        activityRows: [
          {
            'id': 8,
            'event_type': 'review',
            'session_id': 71,
            'decision': 'verified',
            'created_at': '2026-10-30',
            'message': 'Synthetic review event',
            'read_at': null,
          },
        ],
      );
      await _pumpPortal(tester, state, 'activity', const Size(1440, 1100));
      expect(
        find.byKey(const ValueKey('activity-content-panel')),
        findsOneWidget,
      );
      expect(find.text('Recent Activity'), findsOneWidget);
      expect(find.text('Notifications'), findsNothing);
      expect(find.text('1 unread notifications'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reviews').last);
      await tester.pumpAndSettle();
      expect(
        requests
            .lastWhere((r) => r.url.path.endsWith('/activity'))
            .url
            .queryParameters['event_type'],
        'review',
      );
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      await tester.tap(find.text('Mark all as read'));
      await tester.pumpAndSettle();
      expect(
        requests.where(
          (r) =>
              r.method == 'POST' && r.url.path.endsWith('/activity/read-all'),
        ),
        hasLength(1),
      );
      expect(find.text('0 unread notifications'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'report date and type filters keep the account search and export links',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <http.Request>[];
      final state = await _fixture(
        requests,
        reportRows: [
          {
            'session_id': 71,
            'report_title': 'Synthetic crop report',
            'place_name': 'Synthetic crop parcel',
            'predicted_crop': 'Rice',
            'report_created_at': DateTime.now().toIso8601String(),
          },
          {
            'session_id': 72,
            'report_title': 'Synthetic screening report',
            'place_name': 'Synthetic screening parcel',
            'analysis_mode': 'preliminary_environmental',
            'report_created_at': DateTime.now()
                .subtract(const Duration(days: 120))
                .toIso8601String(),
          },
        ],
      );
      await _pumpPortal(tester, state, 'reports', const Size(1440, 1100));
      expect(find.text('Synthetic crop report'), findsOneWidget);
      expect(find.text('Synthetic screening report'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Report dates'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last 30 days').last);
      await tester.pumpAndSettle();
      expect(find.text('Synthetic crop report'), findsOneWidget);
      expect(find.text('Synthetic screening report'), findsNothing);
      await tester.tap(find.text('Clear filters'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Report type'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preliminary assessment').last);
      await tester.pumpAndSettle();
      expect(find.text('Synthetic crop report'), findsNothing);
      expect(find.text('Synthetic screening report'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Search all reports'),
        'crop',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(
        requests
            .lastWhere((r) => r.url.path.endsWith('/reports'))
            .url
            .queryParameters['q'],
        'crop',
      );
      expect(find.text('No reports match this view'), findsOneWidget);
      expect(find.text('Open review cases'), findsOneWidget);
      expect(find.text('Open planning summary'), findsOneWidget);
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'empty report action opens the review inbox without creating a report',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <http.Request>[];
      final state = await _fixture(requests);
      await _pumpPortal(tester, state, 'reports', const Size(1440, 1100));
      final action = find.text('Generate a report');
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(PortalRoutes.current.value.path, '/operator/queue');
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  for (final page in ['dashboard', 'trends']) {
    for (final empty in [false, true]) {
      testWidgets('$page desktop card edges align with empty=$empty', (
        tester,
      ) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = await _fixture([]);
        if (empty) {
          state.historyRecords.clear();
          state.webSummary = {
            'analysis_count': 0,
            'average_model_score': null,
            'cumulative_area_ha': 0,
            'frequencies': [],
            'monthly': [],
            'scored_count': 0,
            'high_count': 0,
            'medium_count': 0,
            'low_count': 0,
            'very_low_count': 0,
          };
        }
        for (final width in [1280.0, 1440.0, 1920.0]) {
          await _pumpPortal(tester, state, page, Size(width, 1100));
          Rect rect(String key) => tester.getRect(find.byKey(ValueKey(key)));
          void aligned(String first, String second) {
            expect(rect(first).top, closeTo(rect(second).top, .1));
            expect(rect(first).bottom, closeTo(rect(second).bottom, .1));
          }

          if (page == 'dashboard') {
            expect(find.text('Review farmer submissions'), findsOneWidget);
            expect(find.text('Map of submitted cases'), findsOneWidget);
            expect(find.text('Review workload'), findsOneWidget);
            expect(find.text('Start Analysis'), findsNothing);
            expect(find.text('Analysis Workspace'), findsNothing);
            expect(find.text('My Analyses'), findsNothing);
          } else {
            aligned('patterns-frequency-panel', 'patterns-distribution-panel');
            aligned('patterns-trend-panel', 'patterns-insights-panel');
            aligned(
              'metric-Total Saved Analyses',
              'metric-Most Recommended Crop',
            );
            aligned(
              'metric-Total Saved Analyses',
              'metric-Average Model Score',
            );
          }
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      });
    }
  }

  for (final lowBandwidth in [false, true]) {
    testWidgets(
      'Map and Satellite preserve camera and overlays with lowBandwidth=$lowBandwidth',
      (tester) async {
        final previousLowBandwidth = lowBandwidthMode.value;
        addTearDown(() => lowBandwidthMode.value = previousLowBandwidth);
        SharedPreferences.setMockInitialValues({
          'settings_low_bandwidth': lowBandwidth,
        });
        lowBandwidthMode.value = lowBandwidth;
        final controller = MapController();
        final boundary = <LatLng>[
          const LatLng(7.29, 125.62),
          const LatLng(7.291, 125.62),
          const LatLng(7.291, 125.621),
        ];
        final before = List<LatLng>.of(boundary);
        await tester.pumpWidget(
          GeoSustainApp(
            home: Scaffold(
              body: SizedBox(
                width: 500,
                height: 320,
                child: ContextMap(
                  mapController: controller,
                  options: const MapOptions(
                    initialCenter: LatLng(7.29, 125.62),
                    initialZoom: 14,
                  ),
                  children: [
                    PolygonLayer(polygons: [Polygon(points: boundary)]),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate,
          contains(lowBandwidth ? 'openstreetmap' : 'World_Imagery'),
        );
        if (lowBandwidth) {
          await tester.tap(find.text('Satellite'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate,
            contains('World_Imagery'),
          );
        }
        controller.move(const LatLng(7.3, 125.63), 15);
        await tester.pumpAndSettle();
        final center = controller.camera.center;
        await tester.tap(find.text('Map'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate,
          contains('openstreetmap'),
        );
        expect(controller.camera.center, center);
        expect(controller.camera.zoom, 15);
        expect(boundary, before);
        expect(find.byType(PolygonLayer), findsOneWidget);
        await tester.tap(find.text('Satellite'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate,
          contains('World_Imagery'),
        );
        expect(controller.camera.center, center);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }

  for (final page in [
    'dashboard',
    'map',
    'history',
    'trends',
    'queue',
    'activity',
    'reports',
  ]) {
    for (final size in [
      const Size(360, 800),
      const Size(480, 800),
      const Size(1440, 1000),
      const Size(1920, 1080),
    ]) {
      testWidgets(
        '$page stays usable at $size with real record-derived charts',
        (tester) async {
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final requests = <http.Request>[];
          final state = await _fixture(requests);
          await _pumpPortal(tester, state, page, size);
          expect(tester.takeException(), isNull);
          await _capture(tester, '$page-${size.width.toInt()}');
          final scrollable = find
              .descendant(
                of: find.byType(CustomScrollView).first,
                matching: find.byType(Scrollable),
              )
              .first;
          final position = tester.state<ScrollableState>(scrollable).position;
          // Visit the full page, including filters, chart legends and workload.
          for (var y = 0.0; y < position.maxScrollExtent; y += 400) {
            position.jumpTo(y.clamp(0, position.maxScrollExtent));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          position.jumpTo(position.maxScrollExtent);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          appThemeMode.value = ThemeMode.dark;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(requests.where((r) => r.method != 'GET'), isEmpty);
          await tester.pumpWidget(const SizedBox());
          state.dispose();
        },
      );
    }
  }

  testWidgets(
    'sidebar starts above the header and collapses without losing routes',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = await _fixture([]);
      await _pumpPortal(tester, state, 'history', const Size(1440, 1000));
      expect(
        tester.getTopLeft(find.text('GeoSustain').first).dy,
        lessThan(tester.getBottomLeft(find.byType(AppBar)).dy),
      );
      expect(tester.getTopLeft(find.byType(AppBar)).dx, 224);
      await tester.tap(find.byTooltip('Collapse navigation'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(AppBar)).dx, 0);
      await tester.tap(find.byTooltip('Expand navigation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recommendation Patterns').first);
      await tester.pumpAndSettle();
      expect(PortalRoutes.current.value.path, '/operator/trends');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'retired history opens inbox and global search targets submitted cases',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <http.Request>[];
      final state = await _fixture(requests);
      await _pumpPortal(tester, state, 'history', const Size(1440, 1100));
      expect(PortalRoutes.current.value.path, '/operator/queue');
      expect(find.text('Analysis Workspace'), findsNothing);
      expect(find.text('My Analyses'), findsNothing);
      final field = find.widgetWithText(TextField, 'Search submitted cases...');
      await tester.enterText(field, 'South');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(PortalRoutes.current.value.queryParameters['q'], 'South');
      expect(
        requests
            .lastWhere((r) => r.url.path.endsWith('/inbox'))
            .url
            .queryParameters['q'],
        'South',
      );
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets('patterns preserve zero scores and never use mockup numbers', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = await _fixture([]);
    await _pumpPortal(tester, state, 'trends', const Size(1440, 1000));
    expect(find.text('50.0%'), findsOneWidget);
    expect(find.text('50% (1)'), findsNWidgets(2));
    expect(find.text('0% (0)'), findsNWidgets(2));
    expect(find.text('84.3%'), findsNothing);
    expect(find.text('275.35 ha'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets(
    'map layer switches change visibility without changing saved cases',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <http.Request>[];
      final state = await _fixture(requests);
      await _pumpPortal(tester, state, 'map', const Size(1920, 1080));
      final filters = tester.getRect(
        find.byKey(const ValueKey('planning-filters-panel')),
      );
      final layers = tester.getRect(
        find.byKey(const ValueKey('planning-layers-panel')),
      );
      final mapPanel = tester.getRect(
        find.byKey(const ValueKey('planning-map-panel')),
      );
      final info = tester.getRect(
        find.byKey(const ValueKey('planning-info-panel')),
      );
      expect(filters.top, closeTo(layers.top, .1));
      expect(mapPanel.bottom, closeTo(info.bottom, .1));
      final layer = find.widgetWithText(CheckboxListTile, 'Project cases');
      expect(tester.widget<CheckboxListTile>(layer).value, isTrue);
      await tester.tap(layer);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(layer).value, isFalse);
      expect(find.text('Loaded cases'), findsOneWidget);
      expect(find.text('1 (current filter)'), findsOneWidget);
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
