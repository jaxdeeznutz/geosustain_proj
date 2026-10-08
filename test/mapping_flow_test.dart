import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestGps extends GeolocatorPlatform {
  final fixes = StreamController<Position>.broadcast();
  LocationPermission permission = LocationPermission.whileInUse;
  bool enabled = true;
  int subscriptions = 0;
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async => permission;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    subscriptions++;
    return fixes.stream;
  }
}

void main() {
  late _TestGps gps;
  late GeolocatorPlatform original;
  late AnalysisState state;
  setUp(() {
    original = GeolocatorPlatform.instance;
    gps = _TestGps();
    GeolocatorPlatform.instance = gps;
    state = AnalysisState();
  });
  tearDown(() async {
    GeolocatorPlatform.instance = original;
    await gps.fixes.close();
    state.dispose();
  });

  Future<void> mount(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(GeoSustainApp(home: page));
    await tester.pumpAndSettle();
  }

  Future<void> revealControls(WidgetTester tester) async {
    // Dragging over the map pans it, so scroll the surrounding page directly.
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'denied GPS permission gives guidance without starting a stream',
    (tester) async {
      gps.permission = LocationPermission.deniedForever;
      await mount(tester, FarmBoundaryPage(state: state));
      await revealControls(tester);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Allow location access'), findsOneWidget);
      expect(gps.subscriptions, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'GPS backgrounding pauses and never resumes without a user action',
    (tester) async {
      await mount(tester, FarmBoundaryPage(state: state));
      await revealControls(tester);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(gps.subscriptions, 1);
      gps.fixes.add(
        Position(
          latitude: 7.3,
          longitude: 125.6,
          timestamp: DateTime.now(),
          accuracy: 5,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        ),
      );
      await tester.pumpAndSettle();
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(300);
      await tester.pumpAndSettle();
      expect(find.text('1 points'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(gps.fixes.hasListener, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining('Recording paused because'), findsOneWidget);
      expect(gps.subscriptions, 1);
      expect(find.text('Resume'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'GPS perimeter closes and saves once without automatically requesting review',
    (tester) async {
      SharedPreferences.setMockInitialValues({'token': 'fixture-token'});
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        expect(request.url.path, '/api/mobile/farms');
        final body = jsonDecode(request.body);
        expect(body['mapping_method'], 'gps_walk');
        expect(body['farm_name'], 'Walked farm');
        final polygon = body['polygon'] as List;
        expect(polygon.length, 5);
        expect(polygon.first, polygon.last);
        return http.Response(
          jsonEncode({
            'farm': {'id': 8, ...body},
          }),
          201,
        );
      });
      state.dispose();
      state = AnalysisState(api: ApiService(client: client));
      await mount(tester, FarmBoundaryPage(state: state));
      await revealControls(tester);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      final time = DateTime.now().subtract(const Duration(seconds: 12));
      final points = [
        [7.3, 125.6],
        [7.3001, 125.6],
        [7.3001, 125.6001],
        [7.3, 125.6001],
      ];
      for (var i = 0; i < points.length; i++) {
        gps.fixes.add(
          Position(
            latitude: points[i][0],
            longitude: points[i][1],
            timestamp: time.add(Duration(seconds: i * 3)),
            accuracy: 5,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          ),
        );
        await tester.pumpAndSettle();
      }
      await revealControls(tester);
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(gps.fixes.hasListener, isFalse);
      await revealControls(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Farm name'),
        'Walked farm',
      );
      await revealControls(tester);
      await tester.tap(find.text('Confirm and Save Farm'));
      await tester.pumpAndSettle();
      expect(requests.length, 1);
      expect(state.farms.single['id'], 8);
      expect(find.text('Analyze This Farm'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'drawing works without requesting GPS and validates an empty area',
    (tester) async {
      gps.permission = LocationPermission.deniedForever;
      await mount(tester, PolygonDrawingPage(state: state));
      await revealControls(tester);
      await tester.tap(find.text('Analyze Area'));
      await tester.pumpAndSettle();
      expect(find.textContaining('at least three distinct'), findsOneWidget);
      expect(gps.subscriptions, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
