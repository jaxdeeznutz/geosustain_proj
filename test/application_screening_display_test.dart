import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';

Map<String, dynamic> screenedRecord(String status) {
  final humidity = <String, dynamic>{
    'value': 60,
    'unit': '%',
    'period': 'current',
    'quality': 'modelled',
  };
  final ndvi = <String, dynamic>{
    'value': .65,
    'unit': 'index',
    'period': 'latest_scene',
    'quality': 'modelled',
  };
  return {
    'nitrogen': 80,
    'phosphorus': 47,
    'potassium': 50,
    'nutrient_display_basis': 'legacy_model_estimates',
    'environmental_measurements': {'humidity_current': humidity, 'ndvi': ndvi},
    'application_screening': {
      'version': 'application-screening-v1',
      'used_for_ranking': false,
      'crops': [
        {
          'crop': 'Banana',
          'profile_key': 'banana (cavendish/lakatan)',
          'factors': {
            'humidity': {
              'measurement_key': 'humidity_current',
              'measurement': Map.of(humidity),
              'value': 60,
              'preferred': [70, 95],
              'accepted': [55, 100],
              'status': status,
              'interpretation':
                  'Current humidity check; not a climate average.',
            },
            'ndvi': {
              'measurement_key': 'ndvi',
              'measurement': Map.of(ndvi),
              'value': .65,
              'preferred': [.45, .85],
              'accepted': [.25, .95],
              'status': 'suitable',
              'interpretation':
                  'Vegetation condition; not proof of crop suitability.',
            },
          },
        },
      ],
    },
  };
}

void main() {
  for (final (status, state) in [
    ('suitable', CropFactorState.suitable),
    ('limited', CropFactorState.near),
    ('not_suitable', CropFactorState.outside),
    ('unassessed', CropFactorState.unassessed),
  ]) {
    test(
      'saved humidity status $status is separate from annual criteria and NPK',
      () {
        final views = environmentalFactorViews({
          'crop': 'Banana',
        }, screenedRecord(status));
        final humidity = views.firstWhere((f) => f.key == 'humidity');
        expect(humidity.state, state);
        expect(humidity.applicationScreening, isTrue);
        expect(humidity.referenceBased, isFalse);
        expect(humidity.label, 'Humidity (current)');
        expect(
          views.firstWhere((f) => f.key == 'ndvi').state,
          CropFactorState.suitable,
        );
        for (final key in ['N', 'P', 'K']) {
          final nutrient = views.firstWhere((f) => f.key == key);
          expect(nutrient.value, isNotNull);
          expect(nutrient.state, CropFactorState.unassessed);
        }
      },
    );
  }

  test('missing or mismatched observation cannot inherit a saved grade', () {
    for (final value in [null, 81]) {
      final record = screenedRecord('suitable');
      record['environmental_measurements']['humidity_current']['value'] = value;
      final factor = environmentalFactorViews({
        'crop': 'Banana',
      }, record).firstWhere((f) => f.key == 'humidity');
      expect(factor.state, CropFactorState.unassessed);
    }
  });

  test(
    'old records and crops without screening receive no heuristic grade',
    () {
      final record = screenedRecord('suitable')
        ..remove('application_screening');
      record['humidity_current_pct'] = 80;
      record['ndvi'] = .65;
      for (final key in ['humidity', 'ndvi']) {
        final factor = environmentalFactorViews({
          'crop': 'Banana',
        }, record).firstWhere((f) => f.key == key);
        expect(factor.state, CropFactorState.unassessed);
        expect(factor.applicationScreening, isFalse);
      }
      final factor = environmentalFactorViews({
        'crop': 'Mango',
      }, screenedRecord('suitable')).firstWhere((f) => f.key == 'ndvi');
      expect(factor.state, CropFactorState.unassessed);
    },
  );

  testWidgets('application screening and limitation status are visible', (
    tester,
  ) async {
    final factor = environmentalFactorViews({
      'crop': 'Banana',
    }, screenedRecord('limited')).firstWhere((f) => f.key == 'humidity');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EnvironmentalFactorCard(factor: factor),
          ),
        ),
      ),
    );
    expect(find.text('Application screening'), findsOneWidget);
    expect(find.text('Limited'), findsOneWidget);
    expect(find.textContaining('not a climate average'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
