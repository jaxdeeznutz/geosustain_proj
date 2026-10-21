import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/farm_geometry.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> snapshot(bool supported) => {
  'analysis_schema_version': 'cagro-supported-analysis-v1',
  'center_lat': 7.39242,
  'center_lon': 125.62293,
  'area_m2': 500,
  'analysis_coverage': {
    'supported': supported,
    'matches': supported
        ? [
            {
              'locality_id': 'dapco',
              'location_name': 'FARM 3, DAPCO',
              'confidence': 'high',
              'coordinate_precision': 'mapped_farm',
              'source': 'fixture CAGRO',
              'original_cagro_gps': false,
              'match': {'method': 'mapped_locality_proximity'},
            },
          ]
        : [],
  },
};

void main() {
  test('centroid is independent of extra edge vertices and closing point', () {
    const points = [
      LatLng(7.29, 125.62),
      LatLng(7.29, 125.621),
      LatLng(7.29, 125.624),
      LatLng(7.294, 125.624),
      LatLng(7.294, 125.62),
      LatLng(7.29, 125.62),
    ];
    expect(FarmGeometry.centroid(points)!.latitude, closeTo(7.292, 1e-9));
    expect(
      FarmGeometry.centroid(points.reversed)!.longitude,
      closeTo(125.622, 1e-9),
    );
  });
  for (final supported in [true, false]) {
    testWidgets('shared Farmer/Analyst coverage card supported=$supported', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnalysisCoverageCard(record: snapshot(supported)),
            ),
          ),
        ),
      );
      expect(
        find.textContaining('Farm center latitude: 7.39242'),
        findsOneWidget,
      );
      expect(
        find.textContaining('not a soil sample coordinate'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Nutrient Source: Panabo'),
        supported ? findsOneWidget : findsNothing,
      );
      if (supported) {
        expect(
          find.textContaining('mapped_locality_proximity'),
          findsOneWidget,
        );
        expect(find.text(cagroHistoricalNotice), findsOneWidget);
      } else {
        expect(
          find.textContaining('Location not supported for formal analysis'),
          findsOneWidget,
        );
        expect(
          find.text('CAGRO soil data unavailable for this location.'),
          findsOneWidget,
        );
      }
    });
  }
  test('old snapshot does not acquire a new CAGRO claim', () {
    final text = analysisCoverageLines({'nitrogen': 80}).join('\n');
    expect(text, contains('older analysis'));
    expect(text, isNot(contains('Nutrient Source: Panabo')));
  });
  test(
    'catalog polygons preserve holes and do not fabricate marker buffers',
    () {
      final ring = [
        [125.62, 7.29],
        [125.63, 7.29],
        [125.63, 7.30],
        [125.62, 7.29],
      ];
      expect(
        coverageBoundaryPolygons({
          'reference_locations': [
            {'latitude': 7.29, 'longitude': 125.62},
          ],
        }),
        isEmpty,
      );
      final polygons = coverageBoundaryPolygons({
        'boundaries': [
          {
            'geometry': {
              'type': 'Polygon',
              'coordinates': [ring, ring],
            },
          },
        ],
      });
      expect(polygons.single.holePointsList!.length, 1);
    },
  );
  test('coverage API carries server decision and readable rejection', () async {
    SharedPreferences.setMockInitialValues({'token': 'test'});
    final api = ApiService(
      client: MockClient((request) async {
        if (request.url.path.endsWith('analysis-coverage')) {
          return http.Response(jsonEncode(snapshot(false)), 200);
        }
        return http.Response(
          jsonEncode({
            'detail': {
              'message': 'Location not supported for formal analysis',
              'analysis_coverage': {'supported': false},
            },
          }),
          422,
        );
      }),
    );
    expect(
      (await api.analysisCoverage([]))['analysis_coverage']['supported'],
      false,
    );
    await expectLater(
      api.analysisCoverageCatalog(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Location not supported for formal analysis',
        ),
      ),
    );
    api.close();
  });
  test(
    'report preserves separate original observations and generates PDF',
    () async {
      final data = snapshot(true)
        ..addAll({
          'annual_rainfall_mm': 2600,
          'rainfall_mm': 100,
          'cagro_soil': {
            'observations': [
              {'id': 'one', 'location_name': 'Original source address'},
            ],
          },
          'soil_nutrients_observed': {
            'records': [
              for (final id in ['one', 'two'])
                {
                  'record_id': id,
                  'source_file': 'original.xlsx',
                  'source_row': 5,
                  'nitrogen': {
                    'value': 0.09,
                    'unit': '%',
                    'source': 'CAGRO',
                    'quality': 'estimated_from_organic_matter',
                    'method': 'OM / 20',
                  },
                  'phosphorus': {
                    'value': 61.47,
                    'unit': 'ppm',
                    'source': 'CAGRO',
                  },
                  'potassium': {
                    'value': 1337.2,
                    'unit': 'ppm',
                    'source': 'CAGRO',
                  },
                },
            ],
          },
        });
      final lines = cagroAnalysisReportLines(data).join('\n');
      expect(lines, contains('Original source address'));
      expect(lines, contains('Historical CAGRO record two'));
      expect(lines, contains('0.09 %'));
      expect(lines, contains('1337.2 ppm'));
      expect(lines, contains('OM / 20'));
      expect(lines, contains('Not used for model prediction'));
      final bytes = await buildAnalysisPdf(data);
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    },
  );
}
