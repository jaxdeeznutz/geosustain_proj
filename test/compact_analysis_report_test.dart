import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/compact_analysis_pdf.dart';
import 'package:geosustain_clean_arranged/recommendation_summary.dart';

Map<String, dynamic> fixture(String path) =>
    Map<String, dynamic>.from(jsonDecode(File(path).readAsStringSync()) as Map);
int pages(List<int> bytes) =>
    RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'compact export stays two pages with maps, seven ranks and long notes',
    () async {
      final record = fixture('test/fixtures/no_npk_model_explanation.json');
      final spatial = fixture('test/fixtures/spatial_analysis.json');
      record.addAll({
        'selected_polygon': spatial['selected_polygon'],
        'spatial_assessment': spatial['spatial_assessment'],
        'farm_name': List.filled(
          30,
          'Peñafrancia demonstration farm',
        ).join(' '),
        'place_name': List.filled(30, 'Panabo City').join(' '),
        'planner_notes': List.filled(
          200,
          'Confirm irrigation and drainage.',
        ).join(' '),
        'land_cover_notice': List.filled(
          30,
          'Land coverage unavailable.',
        ).join(' '),
        'verification_status': 'Needs information',
        'farmer_name': 'Panel Test Farmer',
        'analyzed_at': '2026-11-11T09:00:00Z',
        'seasonal_assessment': {
          'selected_month_name': 'November',
          'calendar_season': {
            'selected_month_label': 'Rainy season',
            'current_label': 'Rainy season',
            'current_date': '2026-11-11',
          },
        },
        'verified_at': '2026-11-08T08:00:00Z',
        'alternative_crops': [
          for (final crop in [
            'Banana',
            'Cacao',
            'Coconut',
            'Durian',
            'Mango',
            'Rubber',
          ])
            {'crop': crop, 'score': 4.5},
        ],
      });
      final before = jsonEncode(record);
      final bytes = await buildCompactAnalysisPdf(record);
      expect(pages(bytes), 2);
      expect(jsonEncode(record), before);
      final out = Directory('output/compact-report-review')
        ..createSync(recursive: true);
      File('${out.path}/stress-report.pdf').writeAsBytesSync(bytes);
      final blocked = {...record, 'analysis_mode': 'preliminary_environmental'};
      expect(pages(await buildCompactAnalysisPdf(blocked)), 2);
      final withEstimatedNutrients = {
        ...record,
        'model_input_features': [
          'N',
          'P',
          'K',
          'temperature',
          'humidity',
          'ph',
          'rainfall',
          'ndvi',
          'elevation',
          'slope',
        ],
        'nitrogen': 38.5,
        'phosphorus': 27.1,
        'potassium': 42.2,
      };
      final nutrientPdf = await buildCompactAnalysisPdf(withEstimatedNutrients);
      expect(pages(nutrientPdf), 2);
      File('${out.path}/stress-report-npk.pdf').writeAsBytesSync(nutrientPdf);
    },
  );

  test(
    'reformat the current report fixture without changing its readings or ranks',
    () async {
      final input = File('test/fixtures/no_npk_model_explanation.json');
      final record = fixture(input.path);
      final before = jsonEncode(record);
      final explanation = conciseCropFit(record, 'Mango');
      expect(
        explanation,
        contains('No compatible growing-condition checks were saved'),
      );
      expect(explanation, isNot(contains('model')));
      final bytes = await buildCompactAnalysisPdf(record);
      expect(pages(bytes), 2);
      expect(jsonEncode(record), before);
      Directory('output/pdf').createSync(recursive: true);
      File(
        'output/pdf/geosustain-analysis-summary.pdf',
      ).writeAsBytesSync(bytes);
    },
  );
}
