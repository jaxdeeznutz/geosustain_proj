import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';

void main() {
  test(
    'report embeds Unicode fonts and retains historical rows across pages',
    () async {
      final record = Map<String, dynamic>.from(
        jsonDecode(File('test/fixtures/model_analysis.json').readAsStringSync())
            as Map,
      );
      final observations =
          jsonDecode(
                File('backend/data/cagro_observations.json').readAsStringSync(),
              )
              as List;
      final locations =
          jsonDecode(
                File('backend/data/cagro_locations.json').readAsStringSync(),
              )
              as List;
      final rows = observations
          .take(5)
          .map(
            (r) => <String, dynamic>{
              ...Map<String, dynamic>.from(
                locations.firstWhere((l) => l['id'] == r['location_id']) as Map,
              ),
              ...Map<String, dynamic>.from(r as Map),
              'match': {'method': 'test_fixture_only'},
            },
          )
          .toList();
      record.addAll({
        'analysis_schema_version': 'defense-pdf-fixture',
        'farm_name': List.filled(
          10,
          'Peñafrancia demonstration farm',
        ).join(' '),
        'place_name':
            'Panabo – historical reference; 27 °C, 0.09 %, 1337.2 ppm',
        'analyzed_at': '2026-10-23T00:00:00Z',
        'area_hectares': 1.229,
        'cagro_soil': {
          'status': 'matched',
          'observations': rows,
          'message': 'Historical reference; not a current measurement.',
        },
        'soil_nutrients_observed': {
          'records': rows
              .map(
                (r) => {
                  'record_id': r['id'],
                  'source_file': r['source_file'],
                  'source_row': r['source_row'],
                  'nitrogen': {
                    'value': r['nitrogen_pct'] ?? r['estimated_nitrogen_pct'],
                    'unit': '%',
                    'source': 'CAGRO',
                    'quality': 'estimated_from_organic_matter',
                    'method': r['nitrogen_method'],
                  },
                  'phosphorus': {
                    'value': r['phosphorus_ppm'],
                    'unit': 'ppm',
                    'source': 'CAGRO',
                  },
                  'potassium': {
                    'value': r['potassium_ppm'],
                    'unit': 'ppm',
                    'source': 'CAGRO',
                  },
                },
              )
              .toList(),
        },
        'verification_status': 'verified',
        'planner_notes': 'TEST DATA ONLY. End review marker.',
        'data_quality_warnings': [
          'TEST REPORT ONLY. No live farm or accuracy claim.',
          'Historical observations are not current field measurements. 🌱',
        ],
      });
      final bytes = await buildAnalysisPdf(record);
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes.length, greaterThan(10000));
      final dir = Directory('defense-evidence/readiness-execution/phase-02/regression-reports')
        ..createSync(recursive: true);
      File('${dir.path}/unicode-historical-report.pdf').writeAsBytesSync(bytes);
      File(
        '${dir.path}/unicode-historical-report-input.json',
      ).writeAsStringSync(jsonEncode(record));
    },
  );
}
