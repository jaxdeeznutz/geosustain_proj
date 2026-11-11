import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/local_explanation.dart';
import 'package:geosustain_clean_arranged/web/operator_report.dart';

Map<String, dynamic> noNpkFixture() =>
    jsonDecode(
          File(
            'test/fixtures/no_npk_model_explanation.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'seven-input saved local explanation verifies and has no nutrient factors',
    () {
      final record = noNpkFixture();
      expect(isAnnualPrototypeRecord(record), isTrue);
      expect(isNoNpkModelRecord(record), isTrue);
      final body = verifiedLocalExplanation(record);
      expect(body, isNotEmpty);
      expect(body['feature_order'], [
        'temperature',
        'humidity',
        'ph',
        'rainfall',
        'ndvi',
        'elevation',
        'slope',
      ]);
      expect(body['sample_count'], 9);
      for (final crop
          in (record['crop_assessments'] as List)
              .cast<Map<String, dynamic>>()) {
        final factors = environmentalFactorViews(crop, record);
        expect(factors, hasLength(7));
        expect(factors.any((f) => ['N', 'P', 'K'].contains(f.key)), isFalse);
      }
      final coverage = analysisCoverageLines(record).join(' ');
      expect(coverage, contains('NPK excluded'));
      expect(coverage, isNot(contains('Estimated NPK analysis')));
      expect(coverage, isNot(contains('Recorded nitrogen')));
    },
  );

  test(
    'altered input, context or displayed score still rejects seven-input explanations',
    () {
      for (final change in ['input', 'score', 'context']) {
        final record = noNpkFixture();
        if (change == 'input') {
          (((record['model_explanation'] as Map)['samples'] as List)
                      .first['inputs']
                  as Map)['rainfall'] =
              1;
        } else if (change == 'score') {
          record['crop_compatibility_pct'] =
              (record['crop_compatibility_pct'] as num) + 1;
        } else {
          record['prediction_context_id'] = 'different';
        }
        expect(verifiedLocalExplanation(record), isEmpty, reason: change);
      }
    },
  );

  testWidgets(
    'farmer result identifies no-NPK model without a repeated notice box',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AnalysisState()..currentUser = {'id': 2, 'role': 'farmer'};
      addTearDown(state.dispose);
      final record = noNpkFixture()
        ..addAll({
          'session_id': 17,
          'owner_id': 2,
          'farm_id': 3,
          'farm_name_snapshot': 'Controlled no-NPK fixture',
          'analysis_status': 'completed',
          'verification_status': 'draft',
        });
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
      expect(find.text('Experimental model'), findsNothing);
      expect(find.text('NPK not used. PAGRO soil data pending.'), findsNothing);
      expect(
        find.text('Estimated soil data — not a field soil test.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('old ten-input records retain their historical prototype identity', () {
    final old = {
      'model_usage': annualPrototypeMode,
      'nutrient_display_basis': 'legacy_model_estimates',
    };
    expect(isAnnualPrototypeRecord(old), isTrue);
    expect(isNoNpkModelRecord(old), isFalse);
  });

  test(
    'farmer and analyst PDFs export the same verified seven-input explanation',
    () async {
      final record = noNpkFixture();
      final farmer = await buildAnalysisPdf(record);
      final analyst = await buildOperatorReport({
        'case': {'id': 517, 'version': 1, 'status': 'pending'},
        'analysis': record,
        'revisions': [],
        'events': [],
      });
      expect(farmer.length, greaterThan(1000));
      expect(analyst.length, greaterThan(1000));
      final directory = Directory('build/no-npk-integration');
      await directory.create(recursive: true);
      await File(
        '${directory.path}/farmer-model-report.pdf',
      ).writeAsBytes(farmer);
      await File(
        '${directory.path}/analyst-model-report.pdf',
      ).writeAsBytes(analyst);
    },
  );
}
