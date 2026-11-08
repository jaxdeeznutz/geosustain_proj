import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/seasonal_context.dart';

Map<String, dynamic> seasonalPlantingFixture() => {
  'session_id': 123,
  'seasonal_assessment': {
    'version': 'seasonal-context-v2',
    'selected_month': 6,
    'selected_month_name': 'June',
    'captured_at': '2026-11-07T05:00:00Z',
    'summary': 'June seasonal guidance; annual model scores are unchanged.',
    'monthly_climate': {
      'source_name': 'NASA POWER fixture',
      'baseline_start_year': 2005,
      'baseline_end_year': 2024,
      'monthly_cycle': [
        {'month': 6, 'moisture_status': 'humid'},
      ],
      'metrics': {
        'rainfall': {
          'value': 300,
          'unit': 'mm/month',
          'status': 'available',
          'valid_observations': 20,
          'expected_observations': 20,
        },
      },
    },
    'planting_assessment': {
      'version': 'seasonal-planting-v1',
      'basis': 'Published-reference seasonal moisture screening',
      'window_description': 'Selected month and next three months',
      'water_supply_assumption': 'Irrigation and field moisture are unknown.',
      'local_validation': 'Not field-validated in Panabo.',
      'moisture_method': 'Rain / estimated reference ETo',
      'sources': {
        'fixture': {
          'title': 'Published guide fixture',
          'criterion': 'Plant with adequate moisture.',
          'url': 'https://example.org/guide',
        },
      },
      'crops': [
        for (final name in [
          'Banana',
          'Cacao',
          'Coconut',
          'Durian',
          'Mango',
          'Rice',
          'Rubber',
        ])
          {
            'crop': name,
            'status': name == 'Rice' ? 'conditional' : 'favorable_moisture',
            'label': name == 'Rice'
                ? 'Seasonal planting: check conditions'
                : 'Seasonal moisture favorable',
            'reasons': [
              name == 'Rice'
                  ? 'Confirm the local rice water schedule.'
                  : 'Historical moisture supports establishment in June.',
            ],
            'moisture_supported_months': name == 'Rice' ? [] : [6, 7],
            'stage': 'Establishment, not harvest timing',
            'source_ids': ['fixture'],
          },
      ],
    },
  },
};

void main() {
  test('wet and dry descriptions require saved selected-month evidence', () {
    final record = seasonalPlantingFixture();
    final snapshot = record['seasonal_assessment'] as Map;
    final climate = snapshot['monthly_climate'] as Map;
    for (final entry in {
      'humid': 'Wet conditions',
      'dry': 'Dry conditions',
      'intermediate': 'Transitional conditions',
      'unavailable': 'Seasonal conditions unavailable',
    }.entries) {
      climate['monthly_cycle'] = [
        {'month': 6, 'moisture_status': entry.key},
        {'month': 7, 'moisture_status': 'humid'},
      ];
      expect(seasonalMoistureLabel(record), entry.value);
    }
    climate.remove('monthly_cycle');
    expect(seasonalMoistureLabel(record), 'Seasonal conditions unavailable');
  });

  testWidgets('land gate shows one explanation without seven blocked rows', (
    tester,
  ) async {
    final record = seasonalPlantingFixture();
    final planting =
        (record['seasonal_assessment'] as Map)['planting_assessment'] as Map;
    planting['land_cover_notice'] = 'Land cover is unverified.';
    for (final row in planting['crops'] as List) {
      row['status'] = 'unavailable';
      row['label'] = 'Seasonal planting blocked by land assessment';
    }
    final before = jsonEncode(record);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SeasonalPlantingAdvice(record: record)),
      ),
    );
    expect(find.text('June: Wet conditions'), findsOneWidget);
    expect(find.text('Rice'), findsNothing);
    expect(
      find.text('Seasonal planting blocked by land assessment'),
      findsNothing,
    );
    expect(find.byType(ExpansionTile), findsNothing);
    expect(jsonEncode(record), before);
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('compact seasonal summary fits $brightness at scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final record = seasonalPlantingFixture();
        final saved = jsonEncode(record);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: SeasonalContextCard(record: record, simple: true),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Seasonal planting assessment'), findsOneWidget);
        expect(find.text('June: Wet conditions'), findsOneWidget);
        for (final crop in [
          'Banana',
          'Cacao',
          'Coconut',
          'Durian',
          'Mango',
          'Rice',
          'Rubber',
        ]) {
          expect(find.text(crop), findsNothing);
        }
        expect(find.byType(ExpansionTile), findsNothing);
        expect(find.text('Latest weather & sources'), findsNothing);
        expect(jsonEncode(record), saved);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('crop detail shows month without repeating crop advice', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeasonalPlantingAdvice(
            record: seasonalPlantingFixture(),
            crop: 'rice',
          ),
        ),
      ),
    );
    expect(find.text('Rice'), findsNothing);
    expect(find.text('June: Wet conditions'), findsOneWidget);
    expect(find.text('Banana'), findsNothing);
    expect(find.text('Check irrigation and planting schedule'), findsNothing);
    expect(find.byType(ExpansionTile), findsNothing);
  });

  test('reports retain all seven seasonal outcomes and their sources', () {
    final lines = seasonalAssessmentLines(seasonalPlantingFixture()).join('\n');
    expect(
      lines,
      contains('Seasonal planting assessment: Published-reference'),
    );
    expect(lines, contains('Rice: Seasonal planting: check conditions'));
    expect(lines, contains('Rubber: Seasonal moisture favorable'));
    expect(lines, contains('Seasonal source: Published guide fixture'));
    expect(lines, contains('Not field-validated in Panabo.'));
  });

  testWidgets(
    'older saved analyses never acquire invented seasonal assessments',
    (tester) async {
      final record = {
        'seasonal_assessment': {'version': 'seasonal-context-v1'},
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SeasonalPlantingAdvice(record: record)),
        ),
      );
      expect(find.text('Seasonal planting assessment'), findsNothing);
      expect(find.byType(ExpansionTile), findsNothing);
    },
  );
}
