import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';

void main() {
  test('shows ten inputs and uses recorded 30-day rain, never annual rain', () {
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
          'score': 100,
          'requirement': {
            'optimal': [1500, 2000],
          },
        },
      ],
    };
    final views = environmentalFactorViews(crop, record);
    expect(views.length, 10);
    expect(views.first.label, 'Rainfall (30 days)');
    expect(views.first.value, 94.2);
    expect(views.first.min, isNull);
    expect(views.first.state, CropFactorState.unassessed);
    expect(views.firstWhere((v) => v.key == 'N').value, isNull);
    expect(views.firstWhere((v) => v.key == 'N').usedByModel, isFalse);
    expect(
      environmentalFactorViews(crop, {
        'annual_rainfall_mm': 2742.48,
      }).first.value,
      isNull,
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
      expect(views.first.value, 0);
      expect(views.first.usedByModel, isTrue);
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
