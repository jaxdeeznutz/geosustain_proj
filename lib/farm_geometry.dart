import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Shared map/GPS coordinate contract: latitude/longitude objects, closed ring.
class FarmGeometry {
  static const earthRadius = 6378137.0;
  static bool insideCoverage(LatLng point) =>
      point.latitude.isFinite &&
      point.longitude.isFinite &&
      point.latitude >= 7.20 &&
      point.latitude <= 7.41 &&
      point.longitude >= 125.50 &&
      point.longitude <= 125.72;

  static double distance(LatLng a, LatLng b) {
    final lat = (b.latitude - a.latitude) * math.pi / 180;
    final lon = (b.longitude - a.longitude) * math.pi / 180;
    final h =
        math.pow(math.sin(lat / 2), 2) +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            math.pow(math.sin(lon / 2), 2);
    return 2 * earthRadius * math.asin(math.sqrt(h.clamp(0, 1)));
  }

  static List<LatLng> vertices(Iterable<LatLng> input) {
    final points = <LatLng>[];
    for (final point in input) {
      if (points.isEmpty || distance(points.last, point) >= .5) {
        points.add(point);
      }
    }
    if (points.length > 1 && distance(points.first, points.last) < .5) {
      points.removeLast();
    }
    return points;
  }

  static List<Map<String, double>> payload(Iterable<LatLng> input) {
    final points = vertices(input);
    if (points.isEmpty) return [];
    return [
      ...points,
      points.first,
    ].map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
  }

  static List<LatLng> fromPayload(dynamic raw) {
    if (raw is! List) return [];
    final points = <LatLng>[];
    for (final item in raw) {
      if (item is! Map) return [];
      final lat = double.tryParse('${item['lat'] ?? item['latitude']}');
      final lng = double.tryParse(
        '${item['lng'] ?? item['lon'] ?? item['longitude']}',
      );
      if (lat == null ||
          lng == null ||
          !lat.isFinite ||
          !lng.isFinite ||
          lat < -90 ||
          lat > 90 ||
          lng < -180 ||
          lng > 180) {
        return [];
      }
      points.add(LatLng(lat, lng));
    }
    return vertices(points);
  }

  /// Same mean-latitude equirectangular projection as the backend. Translating
  /// to the first point avoids cancellation for small farm areas.
  static double areaSquareMetres(Iterable<LatLng> input) {
    final points = vertices(input);
    if (points.length < 3) return 0;
    final lat0 =
        points.fold<double>(0, (v, p) => v + p.latitude) /
        points.length *
        math.pi /
        180;
    final scale = earthRadius * math.pi / 180;
    double x(LatLng p) =>
        (p.longitude - points.first.longitude) * scale * math.cos(lat0);
    double y(LatLng p) => (p.latitude - points.first.latitude) * scale;
    double twiceArea = 0;
    for (var i = 0; i < points.length; i++) {
      final a = points[i], b = points[(i + 1) % points.length];
      twiceArea += x(a) * y(b) - x(b) * y(a);
    }
    return twiceArea.abs() / 2;
  }

  static double _cross(LatLng a, LatLng b, LatLng c) =>
      (b.longitude - a.longitude) * (c.latitude - a.latitude) -
      (b.latitude - a.latitude) * (c.longitude - a.longitude);
  static bool _onSegment(LatLng a, LatLng b, LatLng p) =>
      _cross(a, b, p).abs() <= 1e-14 &&
      p.latitude >= math.min(a.latitude, b.latitude) - 1e-12 &&
      p.latitude <= math.max(a.latitude, b.latitude) + 1e-12 &&
      p.longitude >= math.min(a.longitude, b.longitude) - 1e-12 &&
      p.longitude <= math.max(a.longitude, b.longitude) + 1e-12;

  static bool _intersects(LatLng a, LatLng b, LatLng c, LatLng d) {
    final abC = _cross(a, b, c), abD = _cross(a, b, d);
    final cdA = _cross(c, d, a), cdB = _cross(c, d, b);
    return (abC * abD < 0 && cdA * cdB < 0) ||
        _onSegment(a, b, c) ||
        _onSegment(a, b, d) ||
        _onSegment(c, d, a) ||
        _onSegment(c, d, b);
  }

  static String? validate(Iterable<LatLng> input) {
    final raw = input.toList();
    if (raw.any((p) => !insideCoverage(p))) {
      return 'Keep the entire boundary within the supported Panabo City map area.';
    }
    final points = vertices(raw);
    if (points.length < 3) {
      return 'A boundary needs at least three distinct points.';
    }
    // Reject too many vertices rather than silently skipping geometry checks.
    if (points.length > 2000) return 'Use no more than 2,000 boundary points.';
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        if (distance(points[i], points[j]) < .5) {
          return 'The boundary revisits a vertex. Undo or edit the repeated point.';
        }
      }
      final previous = points[(i + points.length - 1) % points.length];
      final next = points[(i + 1) % points.length];
      if (_onSegment(previous, points[i], next) ||
          _onSegment(points[i], next, previous)) {
        return 'The boundary doubles back over an edge. Undo or edit that point.';
      }
      for (var j = i + 1; j < points.length; j++) {
        if (j == i + 1 || (i == 0 && j == points.length - 1)) continue;
        if (_intersects(
          points[i],
          next,
          points[j],
          points[(j + 1) % points.length],
        )) {
          return 'The boundary crosses or touches itself. Undo or edit the crossing points.';
        }
      }
    }
    if (areaSquareMetres(points) < 4) {
      return 'The boundary must enclose at least 4 m². Points on one line cannot form a farm.';
    }
    return null;
  }
}

/// Filters GPS fixes without modifying accepted points. A rejection is always
/// returned to the UI, so weak fixes and jumps are never silently recorded.
class FarmGpsFilter {
  static const maxAccuracyMetres = 20.0;
  static String? rejection({
    required LatLng point,
    required double accuracy,
    required DateTime timestamp,
    LatLng? previous,
    DateTime? previousTimestamp,
    double? previousAccuracy,
    DateTime? now,
  }) {
    if (!FarmGeometry.insideCoverage(point)) {
      return 'GPS position is outside the supported Panabo City map area.';
    }
    final age = (now ?? DateTime.now()).difference(timestamp);
    if (age.inSeconds > 20 || age.inSeconds < -5) {
      return 'This GPS fix is old or has an invalid time. Waiting for a fresh location.';
    }
    if (!accuracy.isFinite || accuracy <= 0) {
      return 'GPS accuracy is unavailable. Waiting before recording a point.';
    }
    if (accuracy > maxAccuracyMetres) {
      return 'Accuracy is outside ±20 m. Live position updated; boundary point not recorded.';
    }
    if (previous == null) return null;
    final gap = FarmGeometry.distance(previous, point);
    // Keep the 4 m floor, but do not treat displacement inside either fix's
    // reported uncertainty as evidence of walking. This is a conservative
    // sampling rule, not a survey accuracy guarantee.
    final spacing = math.max(
      4.0,
      math.max(
        accuracy,
        previousAccuracy != null &&
                previousAccuracy.isFinite &&
                previousAccuracy > 0
            ? previousAccuracy
            : accuracy,
      ),
    );
    if (gap < spacing) {
      return 'Move farther to record the next point. Waiting for movement beyond ${spacing.toStringAsFixed(0)} m.';
    }
    if (gap > 80) {
      return 'GPS jumped ${gap.toStringAsFixed(0)} m. Return near the last point or undo it before resuming.';
    }
    if (previousTimestamp != null) {
      final seconds =
          timestamp.difference(previousTimestamp).inMilliseconds / 1000;
      if (seconds <= 0) return 'Waiting for a newer GPS reading.';
      if (gap / seconds > 12) {
        return 'An unusually fast GPS jump was ignored. Wait for a stable signal.';
      }
    }
    return null;
  }
}
