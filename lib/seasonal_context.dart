/// A selected month's moisture class, never inferred from its calendar name.
String seasonalMoistureLabel(Map<String, dynamic> record) {
  Map<String, dynamic> object(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  final saved = object(record['seasonal_assessment']);
  final cycle = object(saved['monthly_climate'])['monthly_cycle'];
  final month = int.tryParse('${saved['selected_month']}');
  String? status;
  if (month != null && month >= 1 && month <= 12 && cycle is List) {
    for (final row in cycle) {
      final item = object(row);
      if (int.tryParse('${item['month']}') == month) {
        status = '${item['moisture_status']}';
        break;
      }
    }
  }
  return switch (status) {
    'humid' => 'Wet conditions',
    'dry' => 'Dry conditions',
    'intermediate' => 'Transitional conditions',
    _ => 'Seasonal conditions unavailable',
  };
}

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
  final calendarSeason = object(saved['calendar_season']);
  final metrics = object(climate['metrics']);
  final lines = <String>[
    'Selected planting month: ${saved['selected_month_name']}',
    if (calendarSeason['selected_month_label'] != null)
      'PAGASA calendar season for the selected month: ${calendarSeason['selected_month_label']}. This is a national calendar label, not measured farm moisture.',
    if (calendarSeason['current_label'] != null)
      'PAGASA calendar season on ${calendarSeason['current_date']}: ${calendarSeason['current_label']}.',
    '${seasonalMoistureLabel(record)} (historical moisture estimate, not a forecast or official season declaration)',
    '${saved['summary']}',
    'Saved seasonal context: ${saved['captured_at']}; version: ${saved['version']}',
    'Source: ${climate['source_name'] ?? 'Unavailable'}; baseline: ${climate['baseline_start_year'] ?? 'Unknown'}-${climate['baseline_end_year'] ?? 'Unknown'}',
    '${climate['spatial_method'] ?? 'Spatial method unavailable'}',
    'Spatial resolution: ${climate['spatial_resolution'] ?? 'Not recorded'}',
  ];
  final current = object(saved['current_year_climate']);
  final outlook = object(saved['current_year_outlook']);
  if (current['version'] == 'current-year-climate-v1') {
    final selected = object(current['selected']);
    final latest = object(current['latest_complete_month']);
    final reading = selected['status'] == 'available' ? selected : latest;
    lines.insertAll(1, [
      '${current['year']} climate update; checked ${current['as_of']}; ${current['complete_month_count']}/12 complete monthly estimates.',
      if (selected['status'] != 'available')
        '${saved['selected_month_name']} ${current['year']}: complete monthly estimates unavailable; no old values substituted.',
      if (reading.isNotEmpty)
        '${reading['month_name']} ${current['year']} ${selected['status'] == 'available' ? 'selected-month' : 'latest available month'}: rainfall ${reading['rainfall_mm']} mm/month; temperature ${reading['temperature_c']} C; humidity ${reading['humidity_pct']}%. NASA POWER gridded estimates, not field measurements.',
      '${current['limitation']}',
      'Current-year source: ${current['documentation_url']}',
      if (outlook['status'] == 'available') ...[
        'PAGASA ${saved['selected_month_name']} ${outlook['year']} outlook: ${outlook['station']} station; issued ${outlook['issued_on']}; valid through ${outlook['valid_until']}.',
        'Forecast probabilities: below normal ${object(outlook['probabilities_pct'])['below_normal']}%; near normal ${object(outlook['probabilities_pct'])['near_normal']}%; above normal ${object(outlook['probabilities_pct'])['above_normal']}%.',
        '${outlook['scope']} ${outlook['interpretation']}',
        'Outlook source: ${outlook['source_url']}',
      ],
      'Current-year updates do not replace annual model inputs or adjust crop ranks.',
    ]);
  }
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
  final planting = object(saved['planting_assessment']);
  if (planting.isNotEmpty) {
    lines.add('Seasonal planting assessment: ${planting['basis']}');
    lines.add('${planting['window_description']}');
    lines.add('${planting['water_supply_assumption']}');
    lines.add('${planting['local_validation']}');
    lines.add('Moisture method: ${planting['moisture_method']}');
    for (final row
        in (planting['crops'] is List ? planting['crops'] as List : [])) {
      final crop = object(row);
      lines.add('${crop['crop']}: ${crop['label']}');
      for (final reason
          in (crop['reasons'] is List ? crop['reasons'] as List : [])) {
        lines.add('  $reason');
      }
    }
    for (final row
        in (climate['monthly_cycle'] is List
            ? climate['monthly_cycle'] as List
            : [])) {
      final item = object(row);
      String amount(dynamic value) => value is num && value.isFinite
          ? value.toStringAsFixed(1)
          : 'Unavailable';
      lines.add(
        '${item['month_name']}: rain ${amount(item['rainfall_mm'])} mm/month; estimated reference ETo ${amount(item['reference_eto_mm'])} mm/month; moisture ${item['moisture_status']}; ${(item['paired_valid_years'] is List ? item['paired_valid_years'] as List : []).length}/${item['expected_years']} paired years',
      );
    }
    for (final entry in object(planting['sources']).entries) {
      final source = object(entry.value);
      lines.add(
        'Seasonal source: ${source['title']}. ${source['criterion']} ${source['url']}',
      );
    }
  }
  for (final item
      in (saved['limitations'] is List ? saved['limitations'] as List : [])) {
    lines.add('$item');
  }
  return lines;
}
