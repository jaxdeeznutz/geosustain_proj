import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';

Map<String, dynamic> slopeFixture() =>
    jsonDecode(
          File('test/fixtures/seven_crop_slope_checks.json').readAsStringSync(),
        )
        as Map<String, dynamic>;

void main() {
  test('all seven crops display the saved crop-specific slope comparison', () {
    final record = slopeFixture();
    final before = jsonEncode(record);
    final crops = (record['crop_assessments'] as List)
        .cast<Map<String, dynamic>>();
    expect(crops, hasLength(7));
    for (final crop in crops) {
      final view = environmentalFactorViews(
        crop,
        record,
      ).singleWhere((f) => f.key == 'slope');
      expect(view.value, 5.83, reason: '${crop['crop']}');
      expect(view.unit, '%');
      expect(view.referenceBased, isTrue);
      expect(view.applicationScreening, isFalse);
      expect(
        view.state,
        crop['crop'] == 'Rice'
            ? CropFactorState.near
            : CropFactorState.suitable,
      );
    }
    expect(jsonEncode(record), before);
  });

  test(
    'missing saved slope criteria stay unassessed for historical records',
    () {
      final record = slopeFixture();
      for (final crop
          in (record['crop_assessments'] as List)
              .cast<Map<String, dynamic>>()) {
        final factors = (crop['factors'] as List).cast<Map<String, dynamic>>();
        final slope = factors.singleWhere(
          (factor) => factor['factor'] == 'slope',
        );
        slope['score'] = null;
        slope['requirement'] = null;
        final view = environmentalFactorViews(
          crop,
          record,
        ).singleWhere((f) => f.key == 'slope');
        expect(
          view.state,
          CropFactorState.unassessed,
          reason: '${crop['crop']}',
        );
      }
    },
  );
}
