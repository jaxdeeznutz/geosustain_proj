import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';

Map<String, dynamic> savedFixture() => Map<String, dynamic>.from(
  jsonDecode(File('test/fixtures/model_analysis.json').readAsStringSync()),
);

void main() {
  test('explanation is bound to analysis context, model, output and score', () {
    final record = savedFixture();
    expect(verifiedModelExplanation(record), isNotEmpty);
    for (final key in [
      'prediction_context_id',
      'model_version',
      'predicted_crop',
      'crop_compatibility_pct',
    ]) {
      expect(verifiedModelExplanation({...record, key: 'wrong'}), isEmpty);
    }
    final normalized = AnalysisState().normalizeRecord(record);
    expect(verifiedModelExplanation(normalized), isNotEmpty);
  });

  test(
    'JSON-string snapshots parse without substituting global current state',
    () {
      final record = savedFixture();
      final parsed = verifiedModelExplanation({
        ...record,
        'model_explanation': jsonEncode(record['model_explanation']),
      });
      expect(parsed['features'], record['model_explanation']['features']);
      expect(verifiedModelExplanation({'predicted_crop': 'Rice'}), isEmpty);
    },
  );

  test('condition comparisons cannot be borrowed from another crop', () {
    expect(
      cropConditions({
        'crop': 'Rice',
        'condition_comparison': {'crop': 'Cacao', 'summary': 'Wrong crop'},
      }),
      isEmpty,
    );
    expect(farmerSuitability(75), 'Good match');
    expect(farmerSuitability(50), 'Possible match');
    expect(farmerSuitability(25), 'Limited match');
    expect(farmerSuitability(24.9), 'Poor match');
    expect(
      farmerLandType({'land_status': 'ARABLE / VEGETATED'}),
      'Land with plants',
    );
  });

  test(
    'lower-crop score context uses its own saved score and matching sample',
    () {
      final record = savedFixture();
      final crops = assessedCrops(record);
      expect(
        cropRankingContext(crops[1], record),
        contains('lower model score'),
      );
      final otherSample = {
        ...crops[1],
        'condition_comparison': {
          ...cropConditions(crops[1]),
          'sample_id': 'another-analysis',
        },
      };
      expect(cropRankingContext(otherSample, record), isNull);
    },
  );

  for (final scale in [1.0, 1.6, 2.0]) {
    testWidgets(
      'native importance chart is visible and readable at 360px / $scale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 880);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ModelExplanationCard(record: savedFixture()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ExpansionTile), findsNothing);
        expect(find.text('Overall model factors'), findsOneWidget);
        expect(find.textContaining('18.85%'), findsOneWidget);
        final bars = tester.widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(bars.first.value, closeTo(0.18854783430473399, 1e-12));
        expect(bars.length, 5);
        await tester.ensureVisible(find.text('View detailed explanation'));
        await tester.tap(find.text('View detailed explanation'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('normalized decreases in Gini impurity'),
          findsOneWidget,
        );
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('historical and mismatched results show no borrowed chart', (
    tester,
  ) async {
    for (final record in [
      {'predicted_crop': 'Corn'},
      {...savedFixture(), 'model_version': 'old-model'},
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ModelExplanationCard(record: record),
            ),
          ),
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.textContaining('matching model-importance snapshot was not saved'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'complete Analysis page supports doubled text and reachable final controls',
    (tester) async {
      tester.view.physicalSize = const Size(360, 880);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AnalysisState()..currentUser = {'role': 'farmer'};
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: MobileAnalysisResult(state: state, record: savedFixture()),
            ),
            bottomNavigationBar: NavigationBar(
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
                NavigationDestination(
                  icon: Icon(Icons.agriculture),
                  label: 'My Farms',
                ),
                NavigationDestination(
                  icon: Icon(Icons.analytics),
                  label: 'Analysis',
                ),
                NavigationDestination(
                  icon: Icon(Icons.history),
                  label: 'History',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Submit for Analyst Review'));
      await tester.pumpAndSettle();
      expect(
        find.text('Submit for Analyst Review').hitTestable(),
        findsOneWidget,
      );
      expect(
        tester.getBottomLeft(find.text('Submit for Analyst Review')).dy,
        lessThan(tester.getTopLeft(find.byType(NavigationBar)).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid chart data keeps a compact text state without exceptions',
    (tester) async {
      final record = savedFixture();
      record['model_explanation']['features'] = [
        {'feature': 'rainfall', 'importance': 'NaN'},
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ModelExplanationCard(record: record),
            ),
          ),
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.textContaining('Model importance could not be generated'),
        findsOneWidget,
      );
      expect(find.textContaining('Recorded model output'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long crop descriptions expand independently and details close', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final long = List.filled(
      8,
      'Recorded temperature falls outside this crop’s preferred range.',
    ).join(' ');
    final record = {
      'top_crop_recommendations': [
        {'crop': 'Rice', 'compatibility_pct': 78.1, 'reason': long},
        {
          'crop': 'Cacao',
          'compatibility_pct': 58.1,
          'reason': '$long A different crop.',
        },
      ],
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: AnalysisCropsCard(record: record)),
        ),
      ),
    );
    expect(find.text('See more'), findsNWidgets(2));
    await tester.tap(find.text('See more').first);
    await tester.pumpAndSettle();
    expect(find.text('See less'), findsOneWidget);
    expect(find.text('See more'), findsOneWidget);
    expect(tester.widget<Text>(find.text(long)).maxLines, isNull);
    await tester.ensureVisible(find.text('See less'));
    await tester.tap(find.text('See less'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View details').first);
    await tester.tap(find.text('View details').first);
    await tester.pumpAndSettle();
    expect(find.text('Rice details'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(record['top_crop_recommendations']!.length, 2);
    expect(tester.takeException(), isNull);
  });
}
