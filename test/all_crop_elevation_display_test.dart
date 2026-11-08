import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';

Map<String, dynamic> elevationFixture() =>
    jsonDecode(
          File(
            'test/fixtures/seven_crop_elevation_checks.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

void main() {
  test(
    'all seven crops display saved altitude evidence without regrading history',
    () {
      final record = elevationFixture();
      final before = jsonEncode(record);
      final crops = (record['crop_assessments'] as List)
          .cast<Map<String, dynamic>>();
      expect(crops, hasLength(7));
      for (final crop in crops) {
        final view = environmentalFactorViews(
          crop,
          record,
        ).singleWhere((f) => f.key == 'elevation');
        expect(view.value, 29.89, reason: '${crop['crop']}');
        expect(view.unit, 'm');
        expect(view.referenceBased, isTrue);
        expect(view.state, CropFactorState.suitable);
        expect(
          view.statusLabel,
          ['Cacao', 'Rubber'].contains(crop['crop']) ? null : 'Within limit',
        );
        if (view.statusLabel != null) {
          expect(view.interpretation, contains('not an optimum'));
        }
      }
      expect(jsonEncode(record), before);
      for (final crop in crops) {
        final item = (crop['factors'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((f) => f['factor'] == 'elevation');
        item['score'] = null;
        item['requirement'] = null;
        final view = environmentalFactorViews(
          crop,
          record,
        ).singleWhere((f) => f.key == 'elevation');
        expect(view.state, CropFactorState.unassessed);
        expect(view.statusLabel, isNull);
      }
    },
  );

  testWidgets(
    'altitude cards show strict versus inclusive limits and honest status labels',
    (tester) async {
      final record = elevationFixture();
      final crops = (record['crop_assessments'] as List)
          .cast<Map<String, dynamic>>();
      for (final name in [
        'Coconut',
        'Durian',
        'Banana',
        'Mango',
        'Rice',
        'Cacao',
        'Rubber',
      ]) {
        final crop = crops.singleWhere((c) => c['crop'] == name);
        final view = environmentalFactorViews(
          crop,
          record,
        ).singleWhere((f) => f.key == 'elevation');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: EnvironmentalFactorCard(factor: view),
              ),
            ),
          ),
        );
        expect(find.text('Suitable'), findsOneWidget);
        final prefix = view.upperExclusive ? '<' : '≤';
        expect(find.text('$prefix ${view.max!.toInt()} m'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      final coconut = crops.singleWhere((c) => c['crop'] == 'Coconut');
      final factor = (coconut['factors'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((f) => f['factor'] == 'elevation');
      factor['value'] = 600;
      (factor['measurement'] as Map)['value'] = 600;
      factor['score'] = 0;
      final outside = environmentalFactorViews(
        coconut,
        record,
      ).singleWhere((f) => f.key == 'elevation');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EnvironmentalFactorCard(factor: outside)),
        ),
      );
      expect(find.text('Not suitable'), findsOneWidget);
    },
  );
}
