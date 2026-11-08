part of '../main.dart';

class PlantingMonthPicker extends StatelessWidget {
  final AnalysisState state;
  final bool enabled;
  const PlantingMonthPicker({
    super.key,
    required this.state,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: DropdownButtonFormField<int>(
        key: ValueKey('planting-month-${state.intendedPlantingMonth}'),
        initialValue: state.intendedPlantingMonth,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Intended Planting Month',
          prefixIcon: Icon(Icons.calendar_month_outlined),
          helperText:
              'Seasonal planting guidance; historical climate, not a forecast.',
          helperMaxLines: 2,
        ),
        items: [
          for (var month = 1; month <= 12; month++)
            DropdownMenuItem(
              value: month,
              child: Text(AnalysisState.monthNames[month]),
            ),
        ],
        onChanged: enabled && !state.loading
            ? state.setIntendedPlantingMonth
            : null,
      ),
    ),
  );
}

class SeasonalContextCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final bool simple;
  const SeasonalContextCard({
    super.key,
    required this.record,
    this.simple = false,
  });

  @override
  Widget build(BuildContext context) {
    final lines = seasonalAssessmentLines(record);
    final snapshot = analysisMapValue(record['seasonal_assessment']);
    final planting = analysisMapValue(snapshot['planting_assessment']);
    if (simple) {
      final climate = analysisMapValue(snapshot['monthly_climate']);
      final metrics = analysisMapValue(climate['metrics']);
      final month = int.tryParse(
        '${snapshot['selected_month'] ?? record['intended_planting_month']}',
      );
      final monthName =
          snapshot['selected_month_name'] ??
          (month != null && month >= 1 && month <= 12
              ? AnalysisState.monthNames[month]
              : null);
      return GeoResultCard(
        key: const ValueKey('farmer-seasonal-summary'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              planting.isNotEmpty
                  ? 'Seasonal planting assessment${monthName == null ? '' : ' - $monthName'}'
                  : monthName == null
                  ? 'Past weather'
                  : 'Past weather in $monthName',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (planting.isNotEmpty) ...[
              const Text(
                'Published-reference guidance. Annual AI ranking is separate.',
              ),
              SeasonalPlantingAdvice(record: record),
              const Divider(),
            ],
            if (snapshot.isEmpty)
              const Text('No monthly weather saved.')
            else ...[
              for (final item in [
                ('temperature', Icons.thermostat_outlined, 'Temperature', '°C'),
                ('rainfall', Icons.water_drop_outlined, 'Monthly rain', 'mm'),
                ('humidity', Icons.air, 'Humidity', '%'),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(item.$2, size: 20, color: green),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item.$3)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Builder(
                          builder: (_) {
                            final metric = analysisMapValue(metrics[item.$1]);
                            final value = analysisNumber(metric['value']);
                            final unitMatches = switch (item.$1) {
                              'temperature' => [
                                'C',
                                '°C',
                              ].contains(metric['unit']),
                              'rainfall' => metric['unit'] == 'mm/month',
                              _ => metric['unit'] == '%',
                            };
                            return Text(
                              [
                                        'available',
                                        'partial',
                                      ].contains(metric['status']) &&
                                      value != null &&
                                      unitMatches
                                  ? '${value.toStringAsFixed(1)} ${item.$4}${metric['status'] == 'partial' ? ' (limited)' : ''}'
                                  : 'Not available',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              if (climate['baseline_start_year'] != null &&
                  climate['baseline_end_year'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Averages: ${climate['baseline_start_year']}–${climate['baseline_end_year']}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
            const SizedBox(height: 6),
            const Text(
              'Past averages, not a forecast.',
              style: TextStyle(fontSize: 12),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Seasonal sources and details'),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final line in lines)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(line),
                            ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Source & details'),
              ),
            ),
          ],
        ),
      );
    }
    final identity =
        '${record['session_id'] ?? record['id'] ?? 'unsaved'}-'
        '${snapshot['captured_at'] ?? record['analyzed_at'] ?? ''}-'
        '${snapshot['selected_month'] ?? record['intended_planting_month'] ?? ''}';
    return GeoResultCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            planting.isNotEmpty
                ? 'Seasonal planting assessment'
                : 'Seasonal context',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (planting.isNotEmpty) SeasonalPlantingAdvice(record: record),
          for (final line in lines.take(2))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(line),
            ),
          if (lines.length > 2)
            ExpansionTile(
              // Expansion state is bool; the surrounding list stores a double
              // scroll offset. Keep their PageStorage identities independent.
              key: PageStorageKey<String>('seasonal-context-details-$identity'),
              tilePadding: EdgeInsets.zero,
              title: const Text('Monthly climate evidence and limitations'),
              children: [
                for (final line in lines.skip(2))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(line),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Reads only the saved seasonal snapshot; never regrades an older analysis.
class SeasonalPlantingAdvice extends StatelessWidget {
  final Map<String, dynamic> record;
  final String? crop;
  const SeasonalPlantingAdvice({super.key, required this.record, this.crop});

  @override
  Widget build(BuildContext context) {
    final snapshot = analysisMapValue(record['seasonal_assessment']);
    final planting = analysisMapValue(snapshot['planting_assessment']);
    if (planting.isEmpty) return const SizedBox.shrink();
    final rows = analysisListValue(planting['crops'])
        .map(analysisMapValue)
        .where(
          (row) =>
              crop == null ||
              '${row['crop']}'.toLowerCase() == crop!.toLowerCase(),
        )
        .toList();
    final scheme = Theme.of(context).colorScheme;
    final blocked =
        '${planting['land_cover_notice'] ?? ''}'.isNotEmpty ||
        (rows.isNotEmpty &&
            rows.every(
              (row) => '${row['label']}'.contains('blocked by land assessment'),
            ));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (crop != null)
          const Padding(
            padding: EdgeInsets.only(top: 12, bottom: 6),
            child: Text(
              'Seasonal planting assessment',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${snapshot['selected_month_name'] ?? 'Selected month'}: ${seasonalMoistureLabel(record)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const Text(
                'Historical moisture estimate, not a forecast or official season declaration.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        if (blocked) ...[
          const Text(
            'Planting advice unavailable',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const Text(
            'Land cover is unverified or the land check does not allow crop recommendations. Wet conditions alone cannot clear this check.',
          ),
        ],
        for (final row in blocked ? <Map<String, dynamic>>[] : rows)
          ExpansionTile(
            key: ValueKey(
              'seasonal-${row['crop']}-${snapshot['captured_at']}-${snapshot['selected_month']}',
            ),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 12),
            leading: Icon(
              switch ('${row['status']}') {
                'favorable_moisture' => Icons.water_drop_outlined,
                'unavailable' => Icons.help_outline,
                _ => Icons.warning_amber_rounded,
              },
              color: switch ('${row['status']}') {
                'favorable_moisture' => scheme.primary,
                'water_support_needed' => scheme.error,
                _ => scheme.onSurfaceVariant,
              },
            ),
            title: Text(
              '${row['crop']}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${row['crop']}'.toLowerCase() == 'rice' &&
                      row['status'] == 'conditional'
                  ? 'Check irrigation and planting schedule'
                  : '${row['label']}',
            ),
            children: [
              if ('${row['crop']}'.toLowerCase() == 'rice' &&
                  row['status'] == 'conditional')
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'The model rank is separate from planting readiness. Confirm field water, irrigation and the local rice calendar.',
                  ),
                ),
              for (final reason in analysisListValue(row['reasons']))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('$reason'),
                  ),
                ),
              if (analysisListValue(
                row['moisture_supported_months'],
              ).isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Months meeting these moisture checks: ${analysisListValue(row['moisture_supported_months']).map((m) => int.tryParse('$m')).whereType<int>().where((m) => m >= 1 && m <= 12).map((m) => AnalysisState.monthNames[m]).join(', ')}. These are historical screening results, not an official planting calendar.',
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${row['stage']}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('${row['crop']} seasonal evidence'),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${planting['window_description']}'),
                          Text('${planting['water_supply_assumption']}'),
                          Text('${planting['local_validation']}'),
                          const Divider(),
                          for (final id in analysisListValue(
                            row['source_ids'],
                          )) ...[
                            Text(
                              '${analysisMapValue(analysisMapValue(planting['sources'])['$id'])['title']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${analysisMapValue(analysisMapValue(planting['sources'])['$id'])['criterion']}',
                            ),
                            SelectableText(
                              '${analysisMapValue(analysisMapValue(planting['sources'])['$id'])['url']}',
                            ),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Seasonal evidence and sources'),
              ),
            ],
          ),
        if (rows.isEmpty) const Text('No crop-specific seasonal advice saved.'),
        const SizedBox(height: 6),
        const Text(
          'Historical moisture screening, not a forecast. Confirm field water and drainage before planting.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
