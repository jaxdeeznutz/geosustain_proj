// Rendered layout checks use fixtures and neutral offline map tiles.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'analysis_scope_test.dart' as fixture;
import 'qa_support.dart';

class _DesignApi extends fixture.ScopeApi {
  @override
  Future<Map<String, dynamic>> getLiveWeather(double lat, double lon) async =>
      {};
}

class _DesignGps extends GeolocatorPlatform {
  final fixes = StreamController<Position>.broadcast();
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      fixes.stream;
}

void main() {
  setUpAll(() async {
    final config = File('.dart_tool/package_config.json').absolute;
    final packages =
        jsonDecode(await config.readAsString())['packages'] as List;
    final flutter = packages.firstWhere((p) => p['name'] == 'flutter');
    final root = Directory.fromUri(
      config.uri.resolve(flutter['rootUri']),
    ).parent.parent;
    for (final entry in {
      'Roboto': 'roboto-regular.ttf',
      'Ahem': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key);
      loader.addFont(
        File(
          '${root.path}/bin/cache/artifacts/material_fonts/${entry.value}',
        ).readAsBytes().then((b) => ByteData.sublistView(b)),
      );
      await loader.load();
    }
  });
  for (final width in [402.0, 360.0]) {
    testWidgets('affected screens render at $width px', (tester) async {
      SharedPreferences.setMockInitialValues({
        'token': 'qa-only',
        'account_id': '10',
      });
      final originalHttp = HttpOverrides.current;
      HttpOverrides.global = QaHttpOverrides();
      addTearDown(() => HttpOverrides.global = originalHttp);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      tester.view.physicalSize = Size(width, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      Future<void> mount(Widget screen) async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: GeoSustainApp(home: screen),
          ),
        );
        await tester.runAsync(() async {
          for (final asset in ['farm_hero.png', 'field_header.png']) {
            await precacheImage(
              AssetImage('assets/images/dashboard/$asset'),
              tester.element(find.byType(MaterialApp)),
            );
          }
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      Future<void> capture(String name) async {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('build/mobile-qa/october');
          await directory.create(recursive: true);
          await File(
            '${directory.path}/$name-${width.toInt()}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      final api = _DesignApi();
      final state = AnalysisState(api: api)
        ..currentUser = {'id': 10, 'role': 'farmer', 'username': 'Test Farmer'}
        ..userLoaded = true;
      final record = {
        ...fixture.analysis(9, 1),
        ...Map<String, dynamic>.from(
          jsonDecode(
            File('test/fixtures/model_analysis.json').readAsStringSync(),
          ),
        ),
      };
      api.rows = [
        record,
        {...fixture.analysis(8, 2), 'verification_status': 'verified'},
        fixture.analysis(7, null),
      ];
      state.focusFarm(fixture.farm(1));
      api.rows = [];
      await mount(FarmDetailsPage(state: state, farm: fixture.farm(1)));
      expect(find.text('Not analyzed yet'), findsOneWidget);
      await capture('farm-empty');
      await tester.pumpWidget(const SizedBox());
      api.rows = [
        record,
        {...fixture.analysis(8, 2), 'verification_status': 'verified'},
        fixture.analysis(7, null),
      ];
      await state.refreshHistoryData();
      state.selectedFarm = null;
      state.result = record;
      await mount(ShellPage(analysisState: state));
      Future<void> tab(String name) async {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(name),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await capture('home');
      await tab('My Farms');
      await capture('my-farms');
      await tab('Profile');
      await capture('profile');
      await tab('Analysis');
      await capture('analysis');
      await tester.tap(find.text('See more').first);
      await tester.pumpAndSettle();
      await capture('analysis-expanded');
      await tester.ensureVisible(find.text('See less').first);
      await tester.tap(find.text('See less').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.textContaining('1. Rice').first);
      await tester.tap(find.textContaining('1. Rice').first);
      await tester.pumpAndSettle();
      await capture('crop-details');
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('View detailed explanation').hitTestable(),
        find
            .descendant(
              of: find.byType(MobileAnalysisPage),
              matching: find.byType(ListView),
            )
            .first,
        const Offset(0, -250),
      );
      await capture('analysis-chart');
      await tester.tap(find.text('View detailed explanation'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('normalized decreases in Gini impurity'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await capture('analysis-details');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Recommended'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recommended'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await capture('other-crops');
      await tester.ensureVisible(find.text('Key Factors'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Key Factors'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await capture('land-conditions');
      expect(state.result?['session_id'], record['session_id']);
      await tab('History');
      await tester.scrollUntilVisible(
        find.text('Unnamed area'),
        180,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('mobile-history-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Unnamed area'), findsOneWidget);
      await capture('history');
      await tester.pumpWidget(const SizedBox());

      final gps = _DesignGps(), originalGps = GeolocatorPlatform.instance;
      GeolocatorPlatform.instance = gps;
      addTearDown(() => GeolocatorPlatform.instance = originalGps);
      final gpsState = AnalysisState(api: _DesignApi());
      addTearDown(gpsState.dispose);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await mount(FarmBoundaryPage(state: gpsState));
      await capture('gps-ready');
      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      final start = DateTime.now().subtract(const Duration(seconds: 12));
      for (var i = 0; i < 3; i++) {
        gps.fixes.add(
          Position(
            latitude: 7.3 + i * .0001,
            longitude: 125.6,
            timestamp: start.add(Duration(seconds: i * 3)),
            accuracy: 8,
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
      expect(find.text('3 points'), findsOneWidget);
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await capture('gps-recording');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await gps.fixes.close();
      await mount(PolygonDrawingPage(state: gpsState));
      await capture('polygon');
      await tester.pumpWidget(const SizedBox());
      final nestedState = AnalysisState(api: api)
        ..currentUser = {'id': 10, 'role': 'farmer', 'username': 'Test Farmer'}
        ..userLoaded = true
        ..result = record;
      addTearDown(nestedState.dispose);
      for (final page in <String, Widget>{
        'settings': const SettingsPage(),
        'saved-analyses': SavedAnalysesPage(state: nestedState),
        'reports': ReportsListPage(state: nestedState),
        'edit-profile': EditProfilePage(state: nestedState, logout: () {}),
        'security': ChangePasswordPage(api: api),
        'notifications': NotificationsPage(state: nestedState),
        'history-detail': HistoryDetailPage(state: nestedState, record: record),
        'saved-result': SavedAnalysisDetailPage(
          state: nestedState,
          record: record,
          title: 'Saved Analysis',
        ),
        'report-detail': ReportPage(state: nestedState),
      }.entries) {
        await mount(page.value);
        await capture(page.key);
        await tester.pumpWidget(const SizedBox());
      }
      final modelCrops = [
        for (final entry in {
          'Durian': 10.0,
          'Cacao': 20.0,
          'Rice': 25.0,
          'Rubber': 8.0,
          'Coconut': 5.0,
          'Mango': 12.0,
          'Banana': 15.0,
        }.entries)
          {
            'crop': entry.key,
            'compatibility_pct': entry.value,
            'classification': 'Model score',
          },
      ];
      await mount(
        Scaffold(
          body: SingleChildScrollView(
            child: ReferenceAnalysisContent(
              state: nestedState,
              record: {
                ...record,
                'recommendation_basis': 'model_probability',
                'scoring_version': 'random-forest-probability-v1',
                'crop_assessments': modelCrops,
                'analysis_summary':
                    'Model-ranked crops; environmental comparisons do not change this ranking.',
              },
            ),
          ),
        ),
      );
      expect(find.text('1. Rice'), findsOneWidget);
      expect(find.text('5. Durian'), findsOneWidget);
      expect(find.text('6. Rubber'), findsNothing);
      expect(find.text('Top model recommendation'), findsOneWidget);
      await capture('model-ranking');
      expect(tester.takeException(), isNull);
    });
  }
}
