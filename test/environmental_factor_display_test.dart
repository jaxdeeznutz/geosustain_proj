import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:geosustain_clean_arranged/main.dart';

void main() {
  test(
    'new climate labels distinguish periods and exclude annual humidity ranges',
    () {
      final views = environmentalFactorViews(
        {
          'factors': [
            {
              'factor': 'humidity',
              'value': 80,
              'unit': '%',
              'period': 'annual_mean',
              'score': 100,
              'requirement': {
                'optimal': [75, 90],
              },
            },
          ],
        },
        {
          'climate_contract_version': 'climate-periods-v1',
          'temperature_mean_5y_c': 27,
          'humidity_current_pct': 80,
        },
      );
      expect(views[1].label, 'Air temperature (5-year mean)');
      expect(views[1].value, 27);
      expect(views[2].label, 'Humidity (current)');
      expect(views[2].min, isNull);
    },
  );
  test(
    'saved soil range compares parcel input even when reference reading differs',
    () {
      final crop = <String, dynamic>{
        'factors': [
          {
            'factor': 'soil_ph',
            'value': 6.2,
            'unit': 'pH',
            'score': 100,
            'requirement': {
              'optimal': [5.5, 7],
            },
          },
        ],
      };
      final record = <String, dynamic>{
        'scoring_version': 'model',
        'model_explanation': {
          'samples': [
            {
              'inputs': {'ph': 8},
            },
          ],
        },
      };
      final factor = environmentalFactorViews(
        crop,
        record,
      ).firstWhere((f) => f.key == 'ph');
      expect(factor.value, 8);
      expect(factor.min, 5.5);
      expect(factor.state, CropFactorState.outside);
    },
  );

  testWidgets(
    'model input without a compatible criterion is explicitly not assessed',
    (tester) async {
      final factor = environmentalFactorViews({}, {
        'model_explanation': {
          'samples': [
            {
              'inputs': {'K': 51.78},
            },
          ],
        },
      }).firstWhere((f) => f.key == 'K');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EnvironmentalFactorCard(factor: factor)),
        ),
      );
      expect(find.text('Used in crop prediction'), findsNothing);
      expect(find.text('Not assessed'), findsOneWidget);
      expect(find.text('No compatible crop criterion saved'), findsOneWidget);
      expect(find.text('No crop-specific range saved'), findsNothing);
    },
  );

  test('shows annual rainfall comparison, never the recent model rainfall', () {
    final record = <String, dynamic>{
      'scoring_version': 'reference',
      'annual_rainfall_mm': 2742.48,
      'rainfall_30d_mm': 94.2,
    };
    final crop = <String, dynamic>{
      'factors': [
        {
          'factor': 'annual_rainfall_mm',
          'value': 2742.48,
          'unit': 'mm/year',
          'period': 'annual_mean_total',
          'score': 50,
          'requirement': {
            'optimal': [1500, 2000],
          },
        },
      ],
    };
    final views = environmentalFactorViews(crop, record);
    expect(views.length, 10);
    expect(views.first.label, 'Annual Rainfall');
    expect(views.first.value, 2742.48);
    expect(views.first.unit, 'mm/year');
    expect(views.first.min, 1500);
    expect(views.first.max, 2000);
    expect(views.first.state, CropFactorState.near);
    expect(views.first.usedByModel, isFalse);
    expect(views.firstWhere((v) => v.key == 'N').value, isNull);
    expect(views.firstWhere((v) => v.key == 'N').usedByModel, isFalse);
    expect(
      environmentalFactorViews(crop, {
        'annual_rainfall_mm': 2742.48,
      }).first.value,
      2742.48,
    );
  });
  test(
    'model snapshots take precedence, retain zero and do not fill missing inputs',
    () {
      final views = environmentalFactorViews({}, {
        'rainfall_30d_mm': 999,
        'nitrogen': 123,
        'model_explanation': {
          'samples': [
            {
              'inputs': {'rainfall': 0, 'temperature': 27},
            },
            {
              'inputs': {'rainfall': 0, 'temperature': 29},
            },
          ],
        },
      });
      expect(views.first.value, isNull);
      expect(views.first.usedByModel, isFalse);
      expect(views[1].value, 28);
      expect(views.firstWhere((v) => v.key == 'N').value, isNull);
      expect(views.firstWhere((v) => v.key == 'N').usedByModel, isFalse);
    },
  );
  test('compatible saved comparison retains its original status', () {
    final views = environmentalFactorViews(
      {
        'factors': [
          {
            'factor': 'soil_ph',
            'value': 6,
            'unit': 'pH',
            'score': 100,
            'requirement': {
              'optimal': [5.5, 7],
            },
          },
        ],
      },
      {'scoring_version': 'reference', 'soil_ph': 6},
    );
    expect(views[4].min, 5.5);
    expect(views[4].state, CropFactorState.suitable);
  });
}
