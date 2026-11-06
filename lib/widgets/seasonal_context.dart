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
          helperText: 'Historical monthly context; not a weather forecast.',
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
              monthName == null ? 'Past weather' : 'Past weather in $monthName',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
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
                    title: const Text('Weather source and details'),
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
          const Text(
            'Seasonal context',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
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
