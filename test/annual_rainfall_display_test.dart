import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';

// Rice preferred/absolute ranges are the saved backend crop_requirements.py
// contract. Scores below represent backend screening, not model class scores.
Map<String, dynamic> crop(
  double value,
  num? score, {
  String unit = 'mm/year',
  String period = 'annual_mean_total',
}) => {
  'factors': [
    {
      'factor': 'rainfall',
      'unit': unit,
      'period': period,
      'value': value,
      'score': score,
      'requirement': {
        'optimal': [1500, 2000],
        'absolute': [1000, 4000],
      },
    },
  ],
};

Map<String, dynamic> record(double? annual) => {
  'rainfall_annual_mean_5y_mm': annual,
  'annual_rainfall_mm': annual,
  'rainfall_30d_mm': 100,
  'rainfall_mm': 100,
  'model_explanation': {
    'samples': [
      {
        'inputs': {'rainfall': 100},
      },
    ],
  },
};

void main() {
  for (final entry in [
    (1800.0, 100, CropFactorState.suitable, 'Suitable'),
    (2500.0, 50, CropFactorState.near, 'Limited'),
    (4500.0, 0, CropFactorState.outside, 'Outside documented range'),
  ]) {
    testWidgets('annual rainfall shows ${entry.$4} with documented range', (
      tester,
    ) async {
      final factor = environmentalFactorViews(
        crop(entry.$1, entry.$2),
        record(entry.$1),
      ).first;
      expect(factor.value, entry.$1);
      expect(factor.state, entry.$3);
      expect(factor.min, 1500);
      expect(factor.max, 2000);
      expect(factor.usedByModel, isFalse);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EnvironmentalFactorCard(factor: factor)),
        ),
      );
      expect(find.text('Annual Rainfall (5-year mean)'), findsOneWidget);
      expect(find.textContaining('mm/year'), findsNWidgets(2));
      expect(find.text(entry.$4), findsOneWidget);
      expect(find.text('Rainfall (30 days)'), findsNothing);
      expect(find.text('100 mm'), findsNothing);
      expect(find.text('Used in crop prediction'), findsNothing);
    });
  }

  test(
    'missing annual rainfall never uses recent rainfall or saved factor value',
    () {
      final input = record(null)..['annual_rainfall_mm'] = 1800;
      final factor = environmentalFactorViews(crop(1800, 100), input).first;
      expect(factor.value, isNull);
      expect(factor.state, CropFactorState.unassessed);
      expect(
        environmentalFactorViews(crop(1800, 100), {
          'rainfall_30d_mm': 150,
        }).first.value,
        isNull,
      );
    },
  );

  test(
    'rejects recent or wrong-unit requirements even if numeric values match',
    () {
      for (final input in [
        crop(1800, 100, period: 'rolling_30_days'),
        crop(1800, 100, unit: 'mm'),
      ]) {
        final factor = environmentalFactorViews(input, record(1800)).first;
        expect(factor.min, isNull);
        expect(factor.state, CropFactorState.unassessed);
      }
    },
  );

  test('missing criterion and stale scores remain unassessed', () {
    expect(
      environmentalFactorViews({}, record(1800)).first.state,
      CropFactorState.unassessed,
    );
    expect(
      environmentalFactorViews(crop(2500, 50), record(1800)).first.state,
      CropFactorState.unassessed,
    );
    expect(
      environmentalFactorViews(crop(1800, null), record(1800)).first.state,
      CropFactorState.unassessed,
    );
  });

  test('invalid annual metadata cannot be displayed as annual rainfall', () {
    final input = record(1800)
      ..['climate_field_metadata'] = {
        'rainfall_annual_mean_5y_mm': {
          'unit': 'mm',
          'period': 'rolling_30_days',
        },
      };
    expect(
      environmentalFactorViews(crop(1800, 100), input).first.value,
      isNull,
    );
  });

  test('annual zero is retained and no model inputs are mutated', () {
    final input = record(0);
    expect(environmentalFactorViews(crop(0, 0), input).first.value, 0);
    expect(recordedModelInput(input, 'rainfall'), 100);
  });
}
