/// Descriptive statistics of stored model rankings, never agronomic grades.
class WebAnalysisMetrics {
  WebAnalysisMetrics(Iterable<Map<String, dynamic>> input) {
    final seen = <String>{};
    for (final row in input) {
      final id = row['session_id'] ?? row['id'];
      if (id != null && !seen.add('$id')) continue;
      records.add(row);
      if (!isCrop(row)) continue;
      final crop = cropName(row);
      if (crop != null) frequencies[crop] = (frequencies[crop] ?? 0) + 1;
      final score = modelScore(row);
      if (score == null) continue;
      scores.add(score);
      scoreBands[score >= 75
          ? 0
          : score >= 50
          ? 1
          : score >= 25
          ? 2
          : 3]++;
    }
  }
  final records = <Map<String, dynamic>>[];
  final frequencies = <String, int>{};
  final scores = <double>[];
  final scoreBands = [0, 0, 0, 0];
  static bool preliminary(Map<String, dynamic> row) =>
      row['analysis_mode'] == 'preliminary_environmental';
  static String? cropName(Map<String, dynamic> row) {
    final value =
        row['predicted_crop'] ??
        row['crop_recommendation'] ??
        row['recommended_crop'] ??
        row['crop'];
    if (value == null ||
        '$value'.trim().isEmpty ||
        ['--', 'null', 'unknown', 'no crop'].contains('$value'.toLowerCase())) {
      return null;
    }
    return '$value';
  }

  static bool isCrop(Map<String, dynamic> row) =>
      !preliminary(row) &&
      ![false, 'false', 0, '0'].contains(row['is_crop_recommended']) &&
      '${row['land_type'] ?? 'arable'}'.toLowerCase() == 'arable' &&
      cropName(row) != null;
  static double? modelScore(Map<String, dynamic> row) {
    if (!isCrop(row)) return null;
    final raw = row['crop_compatibility_pct'] ?? row['compatibility_pct'];
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
    return value != null && value.isFinite && value >= 0 && value <= 100
        ? value
        : null;
  }

  double? get average =>
      scores.isEmpty ? null : scores.reduce((a, b) => a + b) / scores.length;
  String? get mostFrequent {
    final ordered = frequencies.entries.toList()
      ..sort((a, b) {
        final count = b.value.compareTo(a.value);
        return count == 0 ? a.key.compareTo(b.key) : count;
      });
    return ordered.isEmpty ? null : ordered.first.key;
  }
}
