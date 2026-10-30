import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/local_explanation.dart';
import 'package:geosustain_clean_arranged/web/operator_report.dart';

Map<String, dynamic> localRecord() => Map<String, dynamic>.from(
  jsonDecode(File('test/fixtures/local_analysis.json').readAsStringSync())
      as Map,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('binary hashes match Python, including tiny and negative numbers', () {
    expect(
      localNumericHash('domain', {'z': 1, 'a': 'test'}, [1e-20, -4.5, 0.0]),
      'be935ac5227caf0495875ca5569444d25caabfed07f3b06ff99b93d282beb9ac',
    );
    expect(
      localInputHash(List.filled(64, 'a').join(), ['N', 'P'], {'P': 7, 'N': 0}),
      '475b401b5b3eb71c4525a2bf5f93194c56ea8ab90622353b4d67a84eb865d9a0',
    );
  });
  test(
    'actual saved parcel attribution reconstructs every crop and comparison',
    () {
      final record = localRecord();
      final body = verifiedLocalExplanation(record);
      expect(body, isNotEmpty);
      expect(body['sample_count'], greaterThan(1));
      expect(
        localCropSummary(body, 'Rice'),
        'Humidity raises Rice\'s model score most. Elevation lowers Rice\'s model score most.',
      );
      expect(
        localCropSummary(body, 'Mango'),
        'Recent rainfall (30 days) raises Mango\'s model score most. Humidity lowers Mango\'s model score most.',
      );
      for (final crop in localRows(body['crop_classes'])) {
        final view = localCropView(body, crop['crop'] as String);
        expect(
          (view['base_pct'] as num) + (view['net_pp'] as num),
          closeTo(view['score_pct'] as num, 1e-7),
        );
      }
      final names = localRows(
        body['crop_classes'],
      ).map((v) => v['crop'] as String).toList();
      final comparison = localCropComparison(body, names[0], names[1]);
      final net = localRows(
        comparison['features'],
      ).fold<double>(0, (sum, row) => sum + (row['contribution_pp'] as num));
      expect(
        (comparison['baseline_gap_pp'] as num) + net,
        closeTo(comparison['score_gap_pp'] as num, 1e-7),
      );
      record['local_model_explanation'] = jsonEncode(
        record['local_model_explanation'],
      );
      record['model_explanation'] = jsonEncode(record['model_explanation']);
      expect(verifiedLocalExplanation(record), isNotEmpty);
    },
  );
  final corruptions = <String, void Function(Map<String, dynamic>)>{
    'context': (r) => r['prediction_context_id'] = 'wrong-context',
    'model': (r) => r['model_version'] = List.filled(64, 'b').join(),
    'input': (r) => r['model_explanation']['samples'][0]['inputs']['N'] += 1,
    'sample score': (r) =>
        r['model_explanation']['samples'][0]['local_attribution']['model_scores'][0] +=
            .01,
    'contribution': (r) =>
        r['local_model_explanation']['contributions'][0][0] += .01,
    'class': (r) =>
        r['local_model_explanation']['crop_classes'][0]['class_index'] = 999,
    'selected score': (r) => r['crop_compatibility_pct'] += 1,
    'snapshot': (r) => r.remove('local_model_explanation'),
  };
  for (final entry in corruptions.entries) {
    test('reject mismatched ${entry.key} without inventing signed factors', () {
      final record = localRecord();
      entry.value(record);
      expect(verifiedLocalExplanation(record), isEmpty);
      expect(localExplanationLines(record).single, contains('unavailable'));
    });
  }
  for (final spec in [
    (360.0, 1.0),
    (360.0, 1.6),
    (360.0, 2.0),
    (1280.0, 1.0),
  ]) {
    testWidgets(
      'Explainable AI remains usable at ${spec.$1} scale ${spec.$2}',
      (tester) async {
        tester.view.physicalSize = Size(spec.$1, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final record = localRecord();
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(spec.$2)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: LocalExplanationCard(record: record),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Explainable AI'), findsOneWidget);
        expect(find.text('Why Rice ranks #1'), findsOneWidget);
        expect(find.text('Research and reference fit'), findsOneWidget);
        expect(
          find.textContaining('3.413 percentage points above Mango'),
          findsOneWidget,
        );
        expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        final citations = find.text('View cited conditions');
        await tester.ensureVisible(citations);
        await tester.tap(citations);
        await tester.pumpAndSettle();
        expect(find.text('Research and reference fit - Rice'), findsOneWidget);
        expect(
          find.textContaining('https://ecocrop.apps.fao.org'),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        final details = find.text('View local explanation details');
        await tester.ensureVisible(details);
        await tester.tap(details);
        await tester.pumpAndSettle();
        expect(find.textContaining('Explainable AI details'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('older saved record exposes explanation unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LocalExplanationCard(record: {})),
      ),
    );
    expect(find.text('Explainable AI'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.textContaining('not saved'), findsOneWidget);
  });
  test('farmer and analyst export the same saved local explanations', () async {
    final record = localRecord();
    expect(verifiedLocalExplanation(record), isNotEmpty);
    final directory = Directory('build/phase-07/export-qa');
    await directory.create(recursive: true);
    final farmer = await buildAnalysisPdf(record);
    final analyst = await buildOperatorReport({
      'case': {'id': 505, 'version': 1, 'status': 'pending'},
      'analysis': record,
      'revisions': [],
      'events': [],
    });
    expect(farmer.length, greaterThan(1000));
    expect(analyst.length, greaterThan(1000));
    await File(
      '${directory.path}/farmer-explanation-report.pdf',
    ).writeAsBytes(farmer);
    await File(
      '${directory.path}/analyst-explanation-report.pdf',
    ).writeAsBytes(analyst);
  });
}
