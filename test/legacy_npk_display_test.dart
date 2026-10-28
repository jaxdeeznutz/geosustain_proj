import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';

void main() {
  testWidgets('farmer shows recorded NPK estimates, including zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnalysisIndicatorsCard(
              record: {
                'nutrient_display_basis': 'legacy_model_estimates',
                'nitrogen': 0,
                'phosphorus': 47,
                'potassium': 50,
                'data_quality': {
                  'nitrogen': {'quality': 'fallback_default'},
                },
              },
            ),
          ),
        ),
      ),
    );
    for (final name in ['Nitrogen', 'Phosphorus', 'Potassium']) {
      expect(find.text('$name (estimated)'), findsOneWidget);
    }
    for (final value in ['0.0', '47.0', '50.0']) {
      expect(find.text(value), findsOneWidget);
    }
    expect(find.text('fallback default'), findsOneWidget);
    expect(
      find.textContaining('not fertilizer application rates'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('new coverage distinguishes model analysis from optional CAGRO', () {
    final lines = analysisCoverageLines({
      'nutrient_display_basis': 'legacy_model_estimates',
      'analysis_coverage': {
        'supported': false,
        'can_analyze': true,
        'preliminary_supported': true,
        'analysis_mode': 'legacy_model_estimates',
      },
      'model_nutrient_aggregation': {'sample_count': 9},
    }).join('\n');
    expect(lines, contains('model analysis uses estimated NPK'));
    expect(
      lines,
      contains('Average of recorded model inputs from 9 analysis samples'),
    );
    expect(
      lines,
      isNot(contains('Preliminary screening; CAGRO NPK unavailable')),
    );
    expect(
      lines,
      isNot(contains('Location not supported for formal analysis')),
    );
  });

  test('old preliminary coverage keeps its recorded interpretation', () {
    final lines = analysisCoverageLines({
      'analysis_mode': 'preliminary_environmental',
      'analysis_coverage': {
        'supported': false,
        'can_analyze': true,
        'preliminary_supported': true,
      },
    }).join('\n');
    expect(lines, contains('Preliminary screening; CAGRO NPK unavailable'));
    expect(lines, isNot(contains('Model nutrient source:')));
  });
}
