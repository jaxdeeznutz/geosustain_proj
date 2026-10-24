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

Map<String, dynamic> factor(
  String key,
  double value,
  double score,
  String unit,
  String period,
  List<num> range,
) => {
  'factor': key,
  'label': key == 'soil_ph' ? 'Soil pH' : 'Air temperature',
  'value': value,
  'score': score,
  'unit': unit,
  'period': period,
  'result': score == 100
      ? 'Within documented range'
      : score == 0
      ? 'Outside documented range'
      : 'Within absolute range only',
  'measurement': {
    'value': value,
    'unit': unit,
    'period': period,
    'quality': 'modelled',
  },
  'requirement': {'optimal': range},
};

void main() {
  test(
    'saved reference uses compatible climate observation, not model importance',
    () {
      final crop = {
        'factors': [
          factor('temperature', 27, 100, 'C', 'annual_mean', [20, 30]),
        ],
      };
      final view = savedEnvironmentalReference('temperature', crop)!;
      expect(view.state, CropFactorState.suitable);
      expect(view.value, 27);
      expect(view.referenceBased, isTrue);
      expect(view.label, contains('climate mean'));
      expect(savedEnvironmentalReference('ndvi', crop), isNull);
    },
  );
  test('current humidity cannot inherit an annual climate grade', () {
    final entry = factor('humidity', 80, 100, '%', 'annual_mean', [75, 90]);
    (entry['measurement'] as Map)['period'] = 'current';
    expect(
      savedEnvironmentalReference('humidity', {
        'factors': [entry],
      }),
      isNull,
    );
  });
  test(
    'preliminary admission differs from CAGRO matching and supports old replies',
    () {
      expect(
        farmCanAnalyze({
          'analysis_coverage': {'supported': false, 'can_analyze': true},
        }),
        isTrue,
      );
      expect(
        farmCanAnalyze({
          'analysis_coverage': {'supported': false, 'can_analyze': false},
        }),
        isFalse,
      );
      expect(
        farmCanAnalyze({
          'analysis_coverage': {'supported': false},
        }),
        isFalse,
      );
    },
  );
  test(
    'transient Render 503 wakes without clearing the saved session',
    () async {
      SharedPreferences.setMockInitialValues({'token': 'synthetic-session'});
      var attempts = 0;
      final api = ApiService(
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer synthetic-session');
          attempts++;
          return attempts == 1
              ? http.Response('<html>Starting</html>', 503)
              : http.Response(
                  jsonEncode({
                    'user': {
                      'id': 888,
                      'role': 'farmer',
                      'username': 'Fixture',
                    },
                  }),
                  200,
                );
        }),
      );
      addTearDown(api.close);
      expect((await api.getMe())['id'], 888);
      expect(attempts, 2);
      expect(await api.getToken(), 'synthetic-session');
    },
  );
  testWidgets(
    'preliminary crop details do not claim a recommendation or forest inference',
    (t) async {
      final crop = <String, dynamic>{
        'crop': 'Rice',
        'factors': [
          factor('temperature', 27, 100, 'C', 'annual_mean', [20, 30]),
        ],
      };
      final record = <String, dynamic>{
        'analysis_mode': 'preliminary_environmental',
      };
      for (final sheet in <Widget>[
        RecommendedCropDetailsSheet(crop: crop, record: record),
        SecondaryCropDetailsSheet(crop: crop, record: record, rank: 2),
      ]) {
        await t.pumpWidget(MaterialApp(home: Scaffold(body: sheet)));
        await t.pumpAndSettle();
        expect(find.text('Preliminary comparison'), findsOneWidget);
        expect(
          find.text('Preliminary environmental comparison'),
          findsOneWidget,
        );
        expect(find.text('Rice was selected as the best match.'), findsNothing);
        expect(find.text('Why the model recommended this crop'), findsNothing);
        expect(find.text('Model explanation'), findsNothing);
        expect(t.takeException(), isNull);
      }
    },
  );
  testWidgets('all four factor states are explicit and render without overflow', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    // Readable host-rendered fixture, not a real farm or phone screenshot.
    await t.runAsync(() async {
      final configFile = File('.dart_tool/package_config.json').absolute;
      final config = jsonDecode(await configFile.readAsString()) as Map;
      final flutter = (config['packages'] as List).firstWhere(
        (p) => p['name'] == 'flutter',
      );
      final sdk = Directory.fromUri(
        configFile.uri.resolve(flutter['rootUri']),
      ).parent.parent;
      for (final entry in {
        'Ahem': 'roboto-regular.ttf',
        'Roboto': 'roboto-regular.ttf',
        'MaterialIcons': 'materialicons-regular.otf',
      }.entries) {
        final font = FontLoader(entry.key)
          ..addFont(
            File(
              '${sdk.path}/bin/cache/artifacts/material_fonts/${entry.value}',
            ).readAsBytes().then(ByteData.sublistView),
          );
        await font.load();
      }
    });
    final key = GlobalKey();
    final fields = [
      savedEnvironmentalReference('temperature', {
        'factors': [
          factor('temperature', 27, 100, 'C', 'annual_mean', [20, 30]),
        ],
      })!,
      const CropFactorView(
        key: 'annual_rainfall_mm',
        label: 'Annual rainfall',
        unit: 'mm/year',
        interpretation: 'Rendering fixture: documented accepted range.',
        value: 2600,
        min: 1500,
        max: 2000,
        state: CropFactorState.near,
        referenceBased: true,
      ),
      savedEnvironmentalReference('ph', {
        'factors': [
          factor('soil_ph', 9.5, 0, 'pH', 'soil_surface', [5.5, 7]),
        ],
      })!,
      const CropFactorView(
        key: 'N',
        label: 'CAGRO Nitrogen',
        unit: '',
        interpretation: 'CAGRO NPK unavailable for this location.',
        value: null,
        min: null,
        max: null,
        state: CropFactorState.unassessed,
        referenceBased: true,
      ),
    ];
    await t.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const Text(
                  'Rendering fixture: factor status labels',
                  style: TextStyle(fontSize: 16),
                ),
                for (final field in fields)
                  EnvironmentalFactorCard(factor: field),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    for (final label in [
      'Suitable',
      'Limited',
      'Not suitable',
      'Not assessed',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Used in crop prediction'), findsNothing);
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final target = File(
        'defense-evidence/2026-10-24/crop-screening-update/factor-status-rendering-fixture.png',
      );
      await target.parent.create(recursive: true);
      await target.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
