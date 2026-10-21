import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';

Future<void> _open(
  WidgetTester tester,
  Map<String, dynamic> crop,
  Map<String, dynamic> record,
  int rank,
) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showCropDetailsSheet(context, crop, record, rank: rank),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'model class score is not labeled as poor agronomic suitability',
    (tester) async {
      await _open(
        tester,
        {
          'crop': 'Rice',
          'compatibility_pct': 12.5,
          'model_probability_pct': 12.5,
        },
        {
          'scoring_version': 'random-forest-probability-v1',
          'recommendation_basis': 'model_probability',
        },
        2,
      );
      expect(find.text('Model score'), findsOneWidget);
      expect(find.text('Model-ranked recommendation'), findsOneWidget);
      expect(find.text('Poor match'), findsNothing);
      expect(find.text('Good match: 75–100'), findsNothing);
      expect(
        find.textContaining('raw model class score determines the ranking'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  test('ordinal ranking labels', () {
    expect(ordinalRecommendation(2), '2nd recommendation');
    expect(ordinalRecommendation(3), '3rd recommendation');
    expect(ordinalRecommendation(4), '4th recommendation');
    expect(ordinalRecommendation(5), '5th recommendation');
    expect(ordinalRecommendation(11), '11th recommendation');
    expect(ordinalRecommendation(21), '21st recommendation');
  });

  testWidgets('rank 1 shows environmental factors with statuses', (
    tester,
  ) async {
    final crop = {
      'crop': 'Corn (White/Yellow)',
      'compatibility_pct': 82.5,
      'condition_comparison': {
        'crop': 'Corn (White/Yellow)',
        'factors': [
          {
            'feature': 'ndvi',
            'label': 'Vegetation Index (NDVI)',
            'unit': 'index',
            'value': 0.66,
            'preferred_min': 0.32,
            'preferred_max': 0.75,
            'fit': 1.0,
          },
          {
            'feature': 'rain',
            'label': '30-day Rainfall',
            'unit': 'mm',
            'value': 25.63,
            'preferred_min': 60,
            'preferred_max': 180,
            'fit': 0.2,
          },
        ],
      },
    };
    await _open(tester, crop, {}, 1);
    expect(find.text('Recommended'), findsOneWidget);
    expect(find.text('Environmental & Soil Reference Assessment'), findsOneWidget);
    expect(find.text('0.66'), findsOneWidget);
    expect(find.text('0.32 – 0.75'), findsOneWidget);
    expect(find.text('25.63 mm'), findsNothing);
    expect(find.text('Annual Rainfall'), findsOneWidget);
    expect(find.text('Rainfall (30 days)'), findsNothing);
    expect(find.textContaining('Annual rainfall unavailable.'), findsOneWidget);
    expect(find.text('Suitable'), findsOneWidget);
    expect(find.text('Outside range'), findsNothing);
    expect(find.text('Note'), findsOneWidget);
    expect(find.text('2nd recommendation'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Recommended'), findsNothing);
  });

  testWidgets('rank 2 uses the secondary layout and stored model score', (
    tester,
  ) async {
    final crop = {
      'crop': 'Watermelon',
      'compatibility_pct': 36.49,
      'model_probability_pct': 36.49,
    };
    await _open(tester, crop, {}, 2);
    expect(find.text('Watermelon details'), findsOneWidget);
    expect(find.text('2nd recommendation'), findsOneWidget);
    expect(find.text('Limited match'), findsOneWidget);
    expect(find.text('About these details'), findsOneWidget);
    expect(
      find.textContaining('Crop-specific conditions were not saved'),
      findsOneWidget,
    );
    expect(find.text('Environmental & Soil Reference Assessment'), findsOneWidget);
    expect(find.byType(EnvironmentalFactorCard), findsNWidgets(10));
    expect(find.text('Model explanation'), findsOneWidget);
    expect(find.textContaining('36.49%. This is separate'), findsOneWidget);
    expect(find.text('How to interpret the score'), findsOneWidget);
    expect(find.text('Recommended'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing model score is reported, not invented', (tester) async {
    await _open(tester, {'crop': 'Papaya', 'compatibility_pct': 20.0}, {}, 5);
    expect(find.text('5th recommendation'), findsOneWidget);
    expect(find.text('Poor match'), findsOneWidget);
    expect(
      find.textContaining('model class score was not recorded'),
      findsOneWidget,
    );
  });

  testWidgets('long crop names fit at 320 px and 1.5x text', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCropDetailsSheet(
                context,
                {
                  'crop': 'Corn (White/Yellow) with a very long variety name',
                  'compatibility_pct': 82.5,
                },
                {},
                rank: 1,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
