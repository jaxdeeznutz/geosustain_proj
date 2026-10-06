import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/farm_geometry.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const square = [
    LatLng(7.30, 125.60),
    LatLng(7.30, 125.601),
    LatLng(7.301, 125.601),
    LatLng(7.301, 125.60),
  ];
  group('Farm boundary contract', () {
    test('open and explicitly closed rings have the same area and payload', () {
      expect(FarmGeometry.validate(square), isNull);
      final closed = [...square, square.first];
      expect(FarmGeometry.validate(closed), isNull);
      expect(FarmGeometry.payload(square), FarmGeometry.payload(closed));
      expect(FarmGeometry.payload(square).length, 5);
      expect(
        FarmGeometry.payload(square).first,
        FarmGeometry.payload(square).last,
      );
      expect(FarmGeometry.areaSquareMetres(square), closeTo(12292, 10));
      expect(
        FarmGeometry.areaSquareMetres(closed),
        FarmGeometry.areaSquareMetres(square),
      );
    });
    test(
      'adjacent GPS duplicates collapse while retaining a valid triangle',
      () {
        final boundary = [
          square[0],
          square[0],
          square[1],
          square[2],
          square[0],
        ];
        expect(FarmGeometry.vertices(boundary).length, 3);
        expect(FarmGeometry.validate(boundary), isNull);
      },
    );
    test('a repeated interior vertex is rejected', () {
      expect(
        FarmGeometry.validate([
          square[0],
          square[1],
          square[2],
          square[1],
          square[3],
        ]),
        isNotNull,
      );
    });
    test('collinear points and too few distinct points are rejected', () {
      expect(
        FarmGeometry.validate([square[0], square[0], square[1]]),
        isNotNull,
      );
      expect(
        FarmGeometry.validate(const [
          LatLng(7.3, 125.60),
          LatLng(7.3, 125.601),
          LatLng(7.3, 125.602),
        ]),
        isNotNull,
      );
    });
    test('a bowtie and nonadjacent touching edge are rejected', () {
      expect(
        FarmGeometry.validate([square[0], square[2], square[1], square[3]]),
        isNotNull,
      );
      expect(
        FarmGeometry.validate(const [
          LatLng(7.3, 125.60),
          LatLng(7.3, 125.602),
          LatLng(7.302, 125.602),
          LatLng(7.3, 125.601),
          LatLng(7.302, 125.60),
        ]),
        isNotNull,
      );
    });
    test('overlapping consecutive edges are rejected', () {
      expect(
        FarmGeometry.validate(const [
          LatLng(7.3, 125.60),
          LatLng(7.3, 125.602),
          LatLng(7.3, 125.601),
          LatLng(7.302, 125.601),
          LatLng(7.302, 125.60),
        ]),
        isNotNull,
      );
    });
    test(
      'sub-four-square-metre polygons and unsupported coverage are rejected',
      () {
        expect(
          FarmGeometry.validate(const [
            LatLng(7.3, 125.60),
            LatLng(7.3, 125.60001),
            LatLng(7.30001, 125.60001),
            LatLng(7.30001, 125.60),
          ]),
          isNotNull,
        );
        expect(
          FarmGeometry.validate([...square.take(3), const LatLng(8, 125.60)]),
          contains('Panabo'),
        );
      },
    );
    test('long GPS walks still receive self-intersection validation', () {
      final ring = List.generate(
        600,
        (i) => LatLng(
          7.30 + .005 * math.sin(i * 2 * math.pi / 600),
          125.60 + .005 * math.cos(i * 2 * math.pi / 600),
        ),
      );
      expect(FarmGeometry.validate(ring), isNull);
      final temp = ring[100];
      ring[100] = ring[400];
      ring[400] = temp;
      expect(FarmGeometry.validate(ring), isNotNull);
    });
    test(
      'payload parsing preserves latitude/longitude and rejects malformed data',
      () {
        expect(FarmGeometry.fromPayload(FarmGeometry.payload(square)), square);
        expect(
          FarmGeometry.fromPayload([
            {'lat': 'bad', 'lng': 125.6},
          ]),
          isEmpty,
        );
        expect(
          FarmGeometry.fromPayload([
            {'lat': double.nan, 'lng': 125.6},
          ]),
          isEmpty,
        );
      },
    );
  });

  group('GPS recording filter', () {
    final now = DateTime.utc(2026, 10, 2, 10);
    const start = LatLng(7.3, 125.6);
    String? check(
      LatLng point, {
      double accuracy = 8,
      DateTime? time,
      LatLng? previous = start,
      DateTime? previousTime,
    }) => FarmGpsFilter.rejection(
      point: point,
      accuracy: accuracy,
      timestamp: time ?? now,
      previous: previous,
      previousTimestamp:
          previousTime ?? now.subtract(const Duration(seconds: 2)),
      now: now,
    );
    test('accepts a first fix and plausible movement', () {
      expect(check(start, previous: null), isNull);
      expect(check(const LatLng(7.30005, 125.6)), isNull);
    });
    test('rejects inaccurate, duplicate, stale and unreasonable fixes', () {
      expect(
        check(const LatLng(7.30005, 125.6), accuracy: 21),
        contains('Weak'),
      );
      expect(check(start), contains('movement'));
      expect(
        check(
          start,
          previous: null,
          time: now.subtract(const Duration(seconds: 30)),
        ),
        contains('old'),
      );
      expect(check(const LatLng(7.301, 125.6)), contains('jumped'));
      expect(check(const LatLng(7.3005, 125.6)), contains('fast'));
      expect(check(const LatLng(8, 125.6)), contains('outside'));
    });
  });
}
