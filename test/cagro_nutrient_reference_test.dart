import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';

// Backend-like synthetic assessment fixtures test rendering, not agronomy.
Map<String, dynamic> referenceRecord({
  String status = 'Not assessed',
  bool multiple = false,
}) => {
  'model_explanation': {
    'samples': [
      {
        'inputs': {'N': 80, 'P': 47, 'K': 50},
      },
    ],
  },
  'soil_nutrient_reference': {
    'status': 'matched',
    'crops': {
      'Rice': {
        'records': [
          for (final id in multiple ? ['one', 'two'] : ['one'])
            {
              'record_id': id,
              'factors': [
                for (final n in ['nitrogen', 'phosphorus', 'potassium'])
                  {
                    'factor': n,
                    'value': n == 'nitrogen' ? 0.09 : 61.47,
                    'unit': n == 'nitrogen' ? '%' : 'ppm',
                    'status': status,
                    'reason': 'Test-only backend status',
                    if (status != 'Not assessed')
                      'requirement': {
                        'optimal': [0.01, 0.1],
                        'unit': n == 'nitrogen' ? '%' : 'ppm',
                        'source': {'title': 'Synthetic fixture only'},
                      },
                  },
              ],
            },
        ],
      },
    },
  },
};

void main() {
  for (final status in [
    'Suitable',
    'Limited',
    'Outside documented range',
    'Not assessed',
  ]) {
    testWidgets('CAGRO source and $status display without model proxy', (
      tester,
    ) async {
      final input = referenceRecord(status: status);
      final factor = environmentalFactorViews({
        'crop': 'Rice',
      }, input).firstWhere((f) => f.key == 'N');
      expect(factor.value, 0.09);
      expect(factor.unit, '%');
      expect(factor.usedByModel, isFalse);
      expect(recordedModelInput(input, 'N'), 80);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EnvironmentalFactorCard(factor: factor)),
        ),
      );
      expect(find.text('Nitrogen (CAGRO)'), findsOneWidget);
      expect(
        find.textContaining('CAGRO historical soil observation.'),
        findsOneWidget,
      );
      expect(
        find.text(
          status == 'Outside documented range' ? 'Not suitable' : status,
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Existing model estimate'), findsNothing);
      expect(find.text('Used in crop prediction'), findsNothing);
    });
  }

  test('multiple observations are not selected or averaged', () {
    final factor = environmentalFactorViews({
      'crop': 'Rice',
    }, referenceRecord(multiple: true)).firstWhere((f) => f.key == 'N');
    expect(factor.value, isNull);
    expect(factor.valueText, 'Multiple historical observations');
    expect(factor.state, CropFactorState.unassessed);
    expect(factor.usedByModel, isFalse);
    expect(
      cagroReferenceRecords({
        'crop': 'Rice',
      }, referenceRecord(multiple: true)).length,
      2,
    );
  });

  test('no match keeps legacy estimate labelled as estimate', () {
    final input = referenceRecord()
      ..['soil_nutrient_reference'] = {'status': 'unavailable'};
    final factor = environmentalFactorViews({
      'crop': 'Rice',
    }, input).firstWhere((f) => f.key == 'N');
    expect(factor.value, 80);
    expect(factor.label, 'Nitrogen (N)');
    expect(factor.interpretation, 'Existing model estimate; not a soil test.');
    expect(factor.referenceBased, isFalse);
  });

  test(
    'old matched snapshot prefers original CAGRO value without inventing a criterion',
    () {
      final input = {
        'cagro_soil': {
          'status': 'matched',
          'observations': [
            {
              'id': 'historical',
              'estimated_nitrogen_pct': 0.09,
              'units': {'estimated_nitrogen_pct': '%'},
              'match': {'method': 'mapped_locality_proximity'},
            },
          ],
        },
        'model_explanation': {
          'samples': [
            {
              'inputs': {'N': 80},
            },
          ],
        },
      };
      final factor = environmentalFactorViews({
        'crop': 'Rice',
      }, input).firstWhere((f) => f.key == 'N');
      expect(factor.value, 0.09);
      expect(factor.state, CropFactorState.unassessed);
      expect(factor.min, isNull);
    },
  );
}
