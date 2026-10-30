import 'dart:convert';
import 'dart:io';
import 'package:geosustain_clean_arranged/recommendation_summary.dart';
import 'package:geosustain_clean_arranged/local_explanation.dart';

Map<String, dynamic> summaryFixture([String name = 'local_analysis']) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;

void checkSummary(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

Map<String, dynamic> summaryFactor(
  Map<String, dynamic> record,
  String factor, [
  String crop = 'Rice',
]) => (record['crop_assessments'] as List)
    .cast<Map<String, dynamic>>()
    .firstWhere((row) => row['crop'] == crop)['factors']
    .cast<Map<String, dynamic>>()
    .firstWhere((row) => row['factor'] == factor);

final summaryCases = <String, void Function()>{
  'explains first place with the saved runner-up and signed factor differences':
      () {
        final record = summaryFixture();
        final before = jsonEncode(record);
        final summary = recommendationSummary(record, 'Rice');
        checkSummary(
          summary['rank'] == 1 && summary['other'] == 'Mango',
          'Wrong ranking comparison',
        );
        checkSummary(
          (summary['gap_pp'] as num) > 3.412 &&
              (summary['gap_pp'] as num) < 3.414,
          'Wrong score gap',
        );
        checkSummary(
          '${summary['ranking']}'.contains(
            '3.413 percentage points above Mango',
          ),
          'Missing plain ranking reason',
        );
        checkSummary(
          localRows(summary['supporting']).first['feature'] == 'humidity',
          'Wrong supporting factor',
        );
        checkSummary(
          localRows(summary['limiting']).first['feature'] == 'elevation',
          'Wrong limiting factor',
        );
        checkSummary(
          localRows(summary['contrast_supporting']).first['feature'] ==
              'humidity',
          'Wrong comparison explanation',
        );
        checkSummary(
          '${summary['terrain']}'.contains('Elevation'),
          'Missing saved terrain',
        );
        checkSummary(
          '${summary['season']}'.contains('November'),
          'Missing selected season',
        );
        checkSummary(
          jsonEncode(record) == before,
          'Summary mutated the saved analysis',
        );
      },
  'cited reference fit includes limits without changing model ranking': () {
    final record = summaryFixture();
    final rows = savedReferenceFit(record, 'Rice');
    checkSummary(
      rows.firstWhere((f) => f['factor'] == 'temperature')['status'] == 'fits',
      'Temperature fit lost',
    );
    checkSummary(
      rows.firstWhere((f) => f['factor'] == 'soil_ph')['status'] == 'fits',
      'pH fit lost',
    );
    final rainfall = rows.firstWhere((f) => f['factor'] == 'rainfall');
    checkSummary(rainfall['status'] == 'limited', 'Annual rainfall overstated');
    checkSummary(
      rainfall['text'].contains('1500-2000 mm/year'),
      'Saved range missing',
    );
    checkSummary(
      rainfall['source']['title'] == 'FAO EcoCrop: Oryza sativa',
      'Source missing',
    );
    final summary = recommendationSummary(record, 'Mango');
    checkSummary(
      summary['rank'] == 2 && (summary['gap_pp'] as num) < 0,
      'Alternative rank wrong',
    );
    checkSummary(
      localRows(summary['supporting']).first['feature'] == 'rainfall',
      'Saved rainfall support lost',
    );
    checkSummary(
      savedReferenceFit(
            record,
            'Mango',
          ).firstWhere((f) => f['factor'] == 'rainfall')['status'] ==
          'not_assessed',
      'Invented Mango rainfall criterion',
    );
  },
  'rejects wrong periods, missing citations, reversed ranges and estimated proxy grades':
      () {
        for (final mutation in <void Function(Map<String, dynamic>)>[
          (f) {
            f['period'] = 'rolling_30_days';
            f['measurement']['period'] = 'rolling_30_days';
          },
          (f) {
            f['measurement']['unit'] = 'mm';
          },
          (f) {
            f['requirement']['source'] = null;
          },
          (f) {
            f['requirement']['optimal'] = [2000, 1500];
          },
          (f) {
            f['measurement']['quality'] = 'estimated_proxy';
          },
          (f) {
            f['score'] = null;
          },
        ]) {
          final record = summaryFixture();
          mutation(summaryFactor(record, 'rainfall'));
          checkSummary(
            savedReferenceFit(
                  record,
                  'Rice',
                ).firstWhere((f) => f['factor'] == 'rainfall')['status'] ==
                'not_assessed',
            'Incompatible evidence claimed a fit',
          );
          checkSummary(
            recommendationSummary(record, 'Rice')['rank'] == 1,
            'Reference check altered ranking',
          );
        }
      },
  'uses saved controlled ranges and saved calendar revisions': () {
    final record = summaryFixture('controlled_analysis');
    final before = jsonEncode(record);
    final summary = recommendationSummary(record, 'Rice');
    final rainfall = savedReferenceFit(
      record,
      'Rice',
    ).firstWhere((f) => f['factor'] == 'rainfall');
    checkSummary(
      rainfall['status'] == 'fits' && rainfall['text'].contains('2000-2500'),
      'Ignored saved controlled criterion',
    );
    checkSummary(
      rainfall['source']['url'] == 'https://example.org/controlled-fixture',
      'Replaced saved source',
    );
    checkSummary(
      '${summary['season']}'.contains('Calendar month listed'),
      'Saved calendar not applied',
    );
    checkSummary(jsonEncode(record) == before, 'Replaced history snapshot');
  },
  'rejects missing or mismatched model explanations and unsupported crops': () {
    checkSummary(
      recommendationSummary({}, 'Rice')['status'] == 'unavailable',
      'Invented explanation',
    );
    final record = summaryFixture();
    checkSummary(
      recommendationSummary(record, 'Unknown crop')['status'] == 'unavailable',
      'Invented crop',
    );
    record['prediction_context_id'] = 'different-analysis';
    checkSummary(
      recommendationSummary(record, 'Rice')['status'] == 'unavailable',
      'Used mismatched model data',
    );
  },
};
