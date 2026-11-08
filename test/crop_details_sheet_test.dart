import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
      builder: (context, child) => RepaintBoundary(
        key: const ValueKey('crop-sheet-preview'),
        child: child!,
      ),
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
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets('crop opens directly from seasonal summary into Explainable AI', (
    tester,
  ) async {
    final record = Map<String, dynamic>.from(
      jsonDecode(
            File(
              'test/fixtures/no_npk_model_explanation.json',
            ).readAsStringSync(),
          )
          as Map,
    );
    record['seasonal_assessment'] =
        (jsonDecode(
              File(
                'test/fixtures/current_year_seasonal_2026.json',
              ).readAsStringSync(),
            )
            as Map)['seasonal_assessment'];
    final before = jsonEncode(record);
    final crop = Map<String, dynamic>.from(
      (record['top_crop_recommendations'] as List).first as Map,
    );
    await _open(tester, crop, record, 1);
    expect(find.text('November: Wet conditions'), findsOneWidget);
    expect(find.text('Explainable AI'), findsOneWidget);
    for (final removed in [
      'Latest weather & sources',
      'Check irrigation and planting schedule',
      '2026 seasonal update',
    ]) {
      expect(find.text(removed), findsNothing);
    }
    expect(
      tester.getTopLeft(find.text('Explainable AI')).dy,
      greaterThan(tester.getTopLeft(find.text('November: Wet conditions')).dy),
    );
    expect(find.text('Soil pH'), findsOneWidget);
    expect(find.text('Soil pH in water'), findsNothing);
    expect(jsonEncode(record), before);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('crop-sheet-preview')),
      );
      final picture = await boundary.toImage();
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/seasonal-trim-previews').createSync(recursive: true);
      File(
        'build/seasonal-trim-previews/crop-sheet.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
      picture.dispose();
    });
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('AI ranking score is not labeled as poor agronomic suitability', (
    tester,
  ) async {
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
    expect(find.text('Ranking score'), findsOneWidget);
    expect(find.text('AI-ranked recommendation'), findsOneWidget);
    expect(find.text('Poor match'), findsNothing);
    expect(find.text('Good match: 75–100'), findsNothing);
    expect(
      find.textContaining('raw AI ranking score determines the ranking'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
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
    expect(
      find.text('Environmental & Soil Reference Assessment'),
      findsOneWidget,
    );
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
    expect(
      find.text('Environmental & Soil Reference Assessment'),
      findsOneWidget,
    );
    expect(find.byType(EnvironmentalFactorCard), findsNWidgets(10));
    expect(find.text('Explainable AI'), findsOneWidget);
    expect(find.text('Recorded AI ranking score'), findsOneWidget);
    expect(
      find.text(
        'An explanation was not saved with this result. Scores are unchanged.',
      ),
      findsOneWidget,
    );
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
      find.textContaining('AI ranking score was not recorded'),
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
