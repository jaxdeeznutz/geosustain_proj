/// Shared saved-snapshot text for farmer, analyst and exported reports.
/// Never fetch or reconstruct climate evidence when reopening old records.
List<String> seasonalAssessmentLines(Map<String, dynamic> record) {
  Map<String, dynamic> object(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  final saved = object(record['seasonal_assessment']);
  if (saved.isEmpty) {
    final month = int.tryParse('${record['intended_planting_month']}');
    return [
      if (month != null && month >= 1 && month <= 12)
        'Recorded planting month: $month',
      'Seasonal context was not recorded for this older analysis.',
    ];
  }
  final climate = object(saved['monthly_climate']);
  final metrics = object(climate['metrics']);
  final lines = <String>[
    'Selected planting month: ${saved['selected_month_name']}',
    '${saved['summary']}',
    'Saved seasonal context: ${saved['captured_at']}; version: ${saved['version']}',
    'Source: ${climate['source_name'] ?? 'Unavailable'}; baseline: ${climate['baseline_start_year'] ?? 'Unknown'}-${climate['baseline_end_year'] ?? 'Unknown'}',
    '${climate['spatial_method'] ?? 'Spatial method unavailable'}',
    'Spatial resolution: ${climate['spatial_resolution'] ?? 'Not recorded'}',
  ];
  for (final item in [
    ('temperature', 'Historical selected-month mean temperature'),
    ('rainfall', 'Historical selected-month mean rainfall total'),
    ('humidity', 'Historical selected-month mean humidity'),
  ]) {
    final metric = object(metrics[item.$1]);
    final value = metric['value'];
    final text = value is num && value.isFinite
        ? '${value.toStringAsFixed(1)} ${metric['unit'] ?? ''}'
        : 'Unavailable';
    lines.add(
      '${item.$2}: $text; ${metric['valid_observations'] ?? 0}/${metric['expected_observations'] ?? 20} valid years; ${metric['status'] ?? 'unavailable'}',
    );
  }
  lines.add(
    'Planting calendar: ${object(saved['calendar'])['reason'] ?? 'Unavailable'}',
  );
  for (final item
      in (saved['limitations'] is List ? saved['limitations'] as List : [])) {
    lines.add('$item');
  }
  return lines;
}
