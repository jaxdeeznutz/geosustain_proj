import 'dart:async';
import 'dart:io';
import 'qa_support.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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
    expect(locationSettings?.distanceFilter, 0);
    subscriptions++;
    return fixes.stream;
  }
}

void main() {
  late _TestGps gps;
  late GeolocatorPlatform original;
  late AnalysisState state;
  setUp(() {
    final previousHttp = HttpOverrides.current;
    HttpOverrides.global = QaHttpOverrides();
    addTearDown(() => HttpOverrides.global = previousHttp);
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
  testWidgets(
    'fresh GPS marker, boundary filter, camera and pause remain independent',
    (tester) async {
      await mount(tester, FarmBoundaryPage(state: state));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      final start = DateTime.now().subtract(const Duration(seconds: 12));
      Position fix(double lat, double accuracy, int seconds) => Position(
        latitude: lat,
        longitude: 125.6,
        timestamp: start.add(Duration(seconds: seconds)),
        accuracy: accuracy,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      Marker marker() =>
          tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.last;
      gps.fixes.add(fix(7.3, 5, 0));
      await tester.pumpAndSettle();
      expect(find.text('1 points'), findsOneWidget);
      gps.fixes.add(fix(7.30005, 60, 3));
      await tester.pumpAndSettle();
      expect(marker().point, const LatLng(7.30005, 125.6));
      expect(find.text('1 points'), findsOneWidget);
      expect(
        find.textContaining('boundary point not recorded'),
        findsOneWidget,
      );
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(
        map.mapController!.camera.center.latitude,
        closeTo(7.30005, .000001),
      );
      gps.fixes.add(fix(7.30006, 0, 6));
      await tester.pumpAndSettle();
      expect(find.text('Accuracy unknown'), findsOneWidget);
      expect(marker().point, const LatLng(7.30006, 125.6));
      gps.fixes.add(fix(7.3001, 5, 9));
      await tester.pumpAndSettle();
      expect(find.text('2 points'), findsOneWidget);
      gps.fixes.add(fix(7.3002, 5, -40));
      await tester.pumpAndSettle();
      expect(marker().point, const LatLng(7.3001, 125.6));
      await tester.tap(find.byTooltip('Recenter on my position'));
      await tester.pumpAndSettle();
      expect(
        map.mapController!.camera.center.latitude,
        closeTo(7.3001, .000001),
      );
      await revealControls(tester);
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      expect(gps.fixes.hasListener, isFalse);
      expect(find.text('Paused'), findsOneWidget);
      expect(
        tester
            .widget<Icon>(find.byKey(const ValueKey('gps-live-marker')))
            .color,
        Colors.grey,
      );
      gps.fixes.add(fix(7.30015, 5, 12));
      await tester.pumpAndSettle();
      expect(find.text('2 points'), findsOneWidget);
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(gps.subscriptions, 2);
      gps.fixes.addError(Exception('Location access interrupted'));
      await tester.pumpAndSettle();
      expect(gps.fixes.hasListener, isFalse);
      expect(find.textContaining('Location recording stopped'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
