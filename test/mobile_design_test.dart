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
        'crop_compatibility_pct': 78.4,
        'predicted_crop': 'Cacao',
        'land_status': 'Suitable for crops',
        'analysis_summary':
            'Cacao fits the recorded soil and climate conditions. Check drainage before planting.',
        'xai_explanation': {
          'plain_summary':
              'Cacao fits the recorded soil and climate conditions.',
          'supporting_factors': ['Soil pH is within the crop profile.'],
          'limiting_factors': ['Verify drainage during wet months.'],
          'planning_advice': 'Confirm soil nutrients with a field test.',
        },
        'top_crop_recommendations': [
          {
            'crop': 'Cacao',
            'compatibility_pct': 78.4,
            'reason': 'Matches the recorded soil pH.',
          },
          {
            'crop': 'Corn',
            'compatibility_pct': 64.0,
            'reason': 'Check moisture during establishment.',
          },
        ],
        'soil_ph': 6.2,
        'ndvi': .61,
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

      await tab('Analysis');
      await capture('analysis');
      await tester.dragUntilVisible(
        find.text('Why this result?').hitTestable(),
        find
            .descendant(
              of: find.byType(MobileAnalysisPage),
              matching: find.byType(ListView),
            )
            .first,
        const Offset(0, -250),
      );
      await tester.tap(find.text('Why this result?'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The score compares crop fit'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await capture('analysis-details');
      await tab('History');
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
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      final start = DateTime.now().subtract(const Duration(seconds: 12));
      for (var i = 0; i < 3; i++) {
        gps.fixes.add(
          Position(
            latitude: 7.3 + i * .00005,
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
      await capture('gps-recording');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await gps.fixes.close();
    });
  }
}
