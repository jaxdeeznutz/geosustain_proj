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
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'qa_support.dart';

Map<String, dynamic> reviewFixture({
  String status = 'verified',
  int owner = 2,
}) => {
  'case': {
    'id': 5,
    'owner_id': owner,
    'farm_id': 3,
    'current_session_id': 32,
    'version': 2,
    'status': status,
    'submitted_at': '2026-10-19T10:13:00Z',
  },
  'analysis': {
    'session_id': 32,
    'farm_id': 3,
    'boundary_version': 1,
    'farm_name_snapshot': 'Synthetic review farm',
    'owner_display_name': 'Synthetic farmer',
    'place_name': 'Synthetic parcel',
    'center_lat': 7.3168,
    'center_lon': 125.6733,
    'area_hectares': .655,
    'intended_planting_month': 10,
    'verification_status': status,
    'analyzed_at': '2026-10-19T10:00:00Z',
    if (status == 'verified') 'verified_at': '2026-10-19T11:17:00Z',
    if (status == 'verified') 'planner_notes': 'Synthetic recorded feedback',
    'selected_polygon': [
      {'lat': 7.316, 'lng': 125.672},
      {'lat': 7.316, 'lng': 125.675},
      {'lat': 7.318, 'lng': 125.675},
      {'lat': 7.318, 'lng': 125.672},
    ],
    'heatmap_grid': [
      {'lat': 7.3165, 'lng': 125.673, 'ndvi': 0.0},
      {'lat': 7.317, 'lng': 125.674, 'ndvi': .387},
      {'lat': 7.3175, 'lng': 125.674, 'ndvi': null},
    ],
  },
  'geometry_matches_current': true,
  'current_farm_version': 1,
  'revisions': [
    {'revision': 1, 'session_id': 32},
  ],
  'events': [
    {
      'kind': 'imported_verified',
      'session_id': 32,
      'actor_name': 'Synthetic analyst',
      'created_at': '2026-10-19T11:17:00Z',
      'notes': 'Synthetic decision history',
    },
  ],
  'followups': [],
};

Future<void> pumpReview(
  WidgetTester tester,
  Map<String, dynamic> data,
  Size size, {
  double scale = 1,
  List<http.Request>? requests,
  GlobalKey? previewKey,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = ApiService(
    client: MockClient((request) async {
      requests?.add(request);
      return http.Response(jsonEncode(data), 200);
    }),
  );
  await api.saveToken('synthetic-review-design-token');
  final state = AnalysisState(api: api)
    ..currentUser = {
      'id': 1,
      'username': 'Synthetic analyst',
      'role': 'agricultural_planning_analyst',
    };
  addTearDown(state.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF087B42)),
        fontFamily: 'Roboto',
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: RepaintBoundary(
          key: previewKey,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: WebReviewWorkbench(state: state, reference: '5'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> savePreview(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/review-case-previews')
      ..createSync(recursive: true);
    File(
      '${directory.path}/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Roboto', 'Ahem']) {
      final fonts = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
      await fonts.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final previous = HttpOverrides.current;
    HttpOverrides.global = QaHttpOverrides();
    addTearDown(() => HttpOverrides.global = previous);
  });

  for (final size in [
    const Size(360, 800),
    const Size(768, 1000),
    const Size(1440, 1000),
    const Size(1920, 1080),
  ]) {
    testWidgets('review evidence and decisions reflow at $size', (
      tester,
    ) async {
      final key = GlobalKey();
      await pumpReview(tester, reviewFixture(), size, previewKey: key);
      expect(find.text('Boundary & Measurements'), findsOneWidget);
      final locationCard = find.byKey(const ValueKey('review-location-card'));
      expect(locationCard, findsOneWidget);
      expect(
        find.descendant(
          of: locationCard,
          matching: find.text('Analyzed Farm Location'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: locationCard, matching: find.text('7.3168')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: locationCard, matching: find.text('125.6733')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await savePreview(tester, key, 'review-${size.width.toInt()}');
      await tester.ensureVisible(find.text('Review checklist and explanation'));
      await tester.pumpAndSettle();
      expect(find.text('Export analysis report'), findsOneWidget);
      expect(find.text('Export case report'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (size.width >= 1440) {
        await savePreview(tester, key, 'review-actions-${size.width.toInt()}');
      }
      await tester.ensureVisible(find.text('Create follow-up'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'tabs use saved context and do not invent attachments or issue writes',
    (tester) async {
      final requests = <http.Request>[];
      await pumpReview(
        tester,
        reviewFixture(),
        const Size(1440, 1000),
        requests: requests,
      );
      for (final index in [1, 2, 3, 0]) {
        final tab = find.byKey(ValueKey('review-evidence-tab-$index'));
        await tester.ensureVisible(tab);
        await tester.tap(tab);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (index == 1) {
          expect(find.text('Saved farm details'), findsOneWidget);
        }
        if (index == 3) {
          expect(find.text('No attachment records available'), findsOneWidget);
        }
      }
      expect(requests.length, 1);
      expect(requests.single.url.path, '/api/operator/cases/5');
      expect(requests.single.method, 'GET');
    },
  );

  testWidgets(
    'pending checks preserve decision requirements and self-review denial',
    (tester) async {
      await pumpReview(
        tester,
        reviewFixture(status: 'pending', owner: 1),
        const Size(1440, 1000),
      );
      expect(
        find.textContaining('cannot verify or reject your own submission'),
        findsOneWidget,
      );
      final verify = find.widgetWithText(FilledButton, 'Verify assessment');
      await tester.ensureVisible(verify);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(verify).onPressed, isNull);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Request information'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'verification keeps the four-check gate and cancellation sends no write',
    (tester) async {
      final requests = <http.Request>[];
      await pumpReview(
        tester,
        reviewFixture(status: 'pending'),
        const Size(1440, 1000),
        requests: requests,
      );
      final verify = find.widgetWithText(FilledButton, 'Verify assessment');
      expect(tester.widget<FilledButton>(verify).onPressed, isNull);
      for (var index = 0; index < 4; index++) {
        final checkbox = find.byType(CheckboxListTile).at(index);
        await tester.ensureVisible(checkbox);
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
      }
      expect(tester.widget<FilledButton>(verify).onPressed, isNotNull);
      await tester.ensureVisible(verify);
      await tester.tap(verify);
      await tester.pumpAndSettle();
      expect(find.text('Confirm decision'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(requests.where((request) => request.method == 'POST'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changed geometry is visible and enlarged text keeps actions reachable',
    (tester) async {
      final data = reviewFixture()..['geometry_matches_current'] = false;
      await pumpReview(tester, data, const Size(480, 900), scale: 2);
      expect(
        find.textContaining('current farm boundary has changed'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Send advisory note'));
      await tester.pumpAndSettle();
      expect(find.text('Send advisory note').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final raster in [false, true]) {
    testWidgets(
      '${raster ? 'raster' : 'sample'} review map fits the polygon and ignores camera gestures',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final record = raster
            ? Map<String, dynamic>.from(
                jsonDecode(
                      File(
                        'test/fixtures/spatial_analysis.json',
                      ).readAsStringSync(),
                    )
                    as Map,
              )
            : Map<String, dynamic>.from(reviewFixture()['analysis'] as Map);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: OperatorEvidenceMap(record: record),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final map = find.byType(FlutterMap).first;
        expect(
          tester.widget<FlutterMap>(map).options.interactionOptions.flags,
          InteractiveFlag.none,
        );
        MapCamera camera() =>
            MapCamera.of(tester.element(find.byType(PolygonLayer).first));
        final before = camera();
        for (final point in (record['selected_polygon'] as List).cast<Map>()) {
          expect(
            before.visibleBounds.contains(
              LatLng(
                (point['lat'] as num).toDouble(),
                ((point['lng'] ?? point['lon']) as num).toDouble(),
              ),
            ),
            isTrue,
          );
        }
        await tester.drag(map, const Offset(100, 50));
        await tester.pumpAndSettle();
        await tester.ensureVisible(map);
        await tester.tap(map);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(map);
        await tester.pumpAndSettle();
        expect(camera().center, before.center);
        expect(camera().zoom, before.zoom);
        await tester.tap(find.text('Map').first);
        await tester.pumpAndSettle();
        expect(camera().center, before.center);
        expect(camera().zoom, before.zoom);
        await tester.tap(find.text('Satellite').first);
        await tester.pumpAndSettle();
        expect(camera().center, before.center);
        expect(camera().zoom, before.zoom);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
