import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';

const disabledRecord = <String, dynamic>{
  'cagro_reference_enabled': false,
  'cagro_soil': {'status': 'disabled', 'observations': []},
  'analysis_coverage': {
    'cagro_enabled': false,
    'can_analyze': true,
    'supported': false,
    'analysis_mode': 'legacy_model_estimates',
  },
  'nutrient_display_basis': 'legacy_model_estimates',
  'nitrogen': 80,
  'phosphorus': 47,
  'potassium': 50,
  'model_explanation': {
    'samples': [
      {
        'inputs': {'N': 80, 'P': 47, 'K': 50},
      },
    ],
  },
  'land_cover_notice':
      'Land-cover observations unavailable. Model estimates continue.',
};

void main() {
  testWidgets('disabled historical soil card does not hide NPK estimates', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                CagroSoilObservationsCard(record: disabledRecord),
                AnalysisIndicatorsCard(record: disabledRecord),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      find.text('CAGRO soil data unavailable for this farm.'),
      findsNothing,
    );
    expect(find.text('CAGRO historical soil observations'), findsNothing);
    expect(find.text('Local soil data'), findsNothing);
    for (final value in ['80.0', '47.0', '50.0']) {
      expect(find.text(value), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  test(
    'disabled coverage displays model source and warning without CAGRO failure',
    () {
      final lines = analysisCoverageLines(disabledRecord).join('\n');
      expect(lines, contains('Estimated NPK analysis within Panabo City'));
      expect(lines, contains('Land-cover note:'));
      expect(lines, isNot(contains('CAGRO')));
      final nutrients = environmentalFactorViews(
        {},
        disabledRecord,
      ).where((f) => ['N', 'P', 'K'].contains(f.key)).toList();
      expect(nutrients.map((f) => f.value), [80, 47, 50]);
      expect(nutrients.every((f) => !f.referenceBased), isTrue);
    },
  );
}
