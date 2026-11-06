import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';

void main() {
  testWidgets('experimental annual scores remain visibly unvalidated', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AnalysisState()..currentUser = {'id': 2, 'role': 'farmer'};
    addTearDown(state.dispose);
    final record = <String, dynamic>{
      'session_id': 7,
      'farm_id': 3,
      'owner_id': 2,
      'farm_name_snapshot': 'Prototype fixture farm',
      'model_usage': 'seven_crop_raw_annual_prototype_v1',
      'model_validation_status': 'unvalidated',
      'analysis_status': 'completed',
      'verification_status': 'draft',
      'analysis_mode': 'legacy_model_estimates',
      'recommendation_basis': 'model_probability',
      'is_crop_recommended': true,
      'predicted_crop': 'Rice',
      'crop_compatibility_pct': 30.0,
      'top_crop_recommendations': [
        {'crop': 'Rice', 'compatibility_pct': 30.0, 'rank': 1, 'factors': []},
      ],
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FarmerAnalysisContent(state: state, record: record),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Experimental model'), findsOneWidget);
    expect(
      find.text(
        'Annual inputs are not validated for this model. Ask an analyst before planting.',
      ),
      findsOneWidget,
    );
    expect(
      analysisCoverageLines(record).join(' '),
      contains('Experimental seven-crop model'),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'annual reference result explains pending model without a crop score',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AnalysisState()..currentUser = {'id': 2, 'role': 'farmer'};
      addTearDown(state.dispose);
      final record = <String, dynamic>{
        'session_id': 6,
        'farm_id': 3,
        'owner_id': 2,
        'farm_name_snapshot': 'Annual fixture farm',
        'analysis_status': 'completed',
        'verification_status': 'draft',
        'analysis_mode': 'preliminary_environmental',
        'reference_screening_reason': 'annual_model_pending',
        'model_ranking_status': 'unavailable',
        'recommendation_basis': 'environmental_reference_screening',
        'is_crop_recommended': false,
        'rainfall_annual_mean_5y_mm': 2100,
        'temperature_mean_5y_c': 27,
        'crop_compatibility_pct': null,
        'crop_assessments': [
          for (final name in [
            'Banana',
            'Coconut',
            'Rice',
            'Durian',
            'Mango',
            'Rubber',
            'Cacao',
          ])
            {
              'crop': name,
              'compatibility_pct': null,
              'assessed_count': 2,
              'factors': [],
            },
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FarmerAnalysisContent(state: state, record: record),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Annual land check'), findsOneWidget);
      expect(
        find.text(
          'Five-year climate and terrain checks. NPK is not yet assessed.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Model score:'), findsNothing);
      final details = find.text('Full analysis details');
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(
        find.text('Environmental factors (10)'),
        findsOneWidget,
      );
      expect(find.text('Annual environmental condition checks'), findsNothing);
      expect(find.textContaining('Missing CAGRO NPK prevents'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'annual indicators do not relabel recent rain as an annual total',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnalysisIndicatorsCard(
                record: {
                  'rainfall_annual_mean_5y_mm': 2100,
                  'rainfall_mm': 100,
                },
              ),
            ),
          ),
        ),
      );
      expect(find.text('Annual Rainfall (5-year mean)'), findsOneWidget);
      expect(find.text('2100.0 mm/year'), findsOneWidget);
      expect(find.textContaining('30-day'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
