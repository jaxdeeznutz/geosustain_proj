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
          helperText: 'Latest available year data and dated seasonal outlooks.',
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
    final hasCurrent =
        analysisMapValue(snapshot['current_year_climate'])['version'] ==
        'current-year-climate-v1';
    if (simple && planting.isNotEmpty) {
      return GeoResultCard(
        key: const ValueKey('farmer-seasonal-summary'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Seasonal planting assessment',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            SeasonalPlantingAdvice(record: record),
          ],
        ),
      );
    }
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
            else if (!hasCurrent) ...[
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
            Text(
              hasCurrent
                  ? 'Weather estimates and forecasts are labelled separately.'
                  : 'Past averages, not a forecast.',
              style: const TextStyle(fontSize: 12),
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
          for (final line in hasCurrent ? <String>[] : lines.take(2))
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
    final calendarSeason = analysisMapValue(snapshot['calendar_season']);
    if (planting.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (crop != null) ...[
            const Text(
              'Seasonal planting assessment',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            '${snapshot['selected_month_name'] ?? 'Selected month'}: ${seasonalMoistureLabel(record)}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          if (calendarSeason['selected_month_label'] != null)
            Text(
              'PAGASA calendar season: ${calendarSeason['selected_month_label']}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          const Text(
            'Historical monthly pattern; not a forecast.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class CurrentYearSeasonalEvidence extends StatelessWidget {
  final Map<String, dynamic> record;
  const CurrentYearSeasonalEvidence({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final snapshot = analysisMapValue(record['seasonal_assessment']);
    final calendarSeason = analysisMapValue(snapshot['calendar_season']);
    final current = analysisMapValue(snapshot['current_year_climate']);
    final outlook = analysisMapValue(snapshot['current_year_outlook']);
    final selected = analysisMapValue(current['selected']);
    final latest = analysisMapValue(current['latest_complete_month']);
    final reading = selected['status'] == 'available' ? selected : latest;
    final probabilities = analysisMapValue(outlook['probabilities_pct']);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (calendarSeason['current_label'] != null) ...[
          Text(
            'Current PAGASA calendar season: ${calendarSeason['current_label']}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          Text(
            'As of ${calendarSeason['current_date']} in the Philippines. The local rainfall estimate is shown separately.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
        ],
        Text(
          '${current['year']} seasonal update',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        Text(
          'Data checked: ${current['as_of']}',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        if (selected['status'] != 'available')
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '${snapshot['selected_month_name']} ${current['year']}: complete monthly estimates are not yet available.',
            ),
          ),
        if (reading.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '${reading['month_name']} ${current['year']} weather estimates',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (selected['status'] != 'available')
            const Text(
              'Latest complete month available',
              style: TextStyle(fontSize: 12),
            ),
          Text(
            'Rainfall: ${_cropNum(analysisNumber(reading['rainfall_mm']))} mm/month',
          ),
          Text(
            'Temperature: ${_cropNum(analysisNumber(reading['temperature_c']))}\u00b0C | Humidity: ${_cropNum(analysisNumber(reading['humidity_pct']))}%',
          ),
          Text(
            '${switch (reading['moisture_status']) {
              'humid' => 'Wet conditions',
              'dry' => 'Dry conditions',
              'intermediate' => 'Transitional conditions',
              _ => 'Moisture check unavailable',
            }} (monthly estimate)',
          ),
        ] else
          const Text(
            'Current-year monthly estimates are unavailable. No old values are substituted.',
          ),
        if (outlook['status'] == 'available') ...[
          const SizedBox(height: 12),
          Text(
            '${snapshot['selected_month_name']} ${outlook['year']} rainfall outlook - ${outlook['station']}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            'Below normal: ${_cropNum(analysisNumber(probabilities['below_normal']))}%\nNear normal: ${_cropNum(analysisNumber(probabilities['near_normal']))}%\nAbove normal: ${_cropNum(analysisNumber(probabilities['above_normal']))}%',
          ),
          Text(
            'Issued ${outlook['issued_on']}; valid through ${outlook['valid_until']}.',
            style: const TextStyle(fontSize: 12),
          ),
          const Text(
            'Regional station reference, not a forecast for this parcel. Below normal does not mean dry season.',
            style: TextStyle(fontSize: 12),
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => _analysisDetails(
              context,
              'Current-year climate sources',
              [
                Text('${current['source_name']}: ${current['limitation']}'),
                Text(
                  'Coverage: ${current['complete_month_count']}/12 complete months; checked ${current['as_of']}.',
                ),
                SelectableText('${current['documentation_url']}'),
                if (outlook['status'] == 'available') ...[
                  Text('${outlook['source_name']}: ${outlook['source_title']}'),
                  Text('${outlook['scope']} ${outlook['interpretation']}'),
                  SelectableText('${outlook['source_url']}'),
                ] else ...[
                  Text(
                    '${outlook['reason'] ?? 'No dated forecast saved for the selected month.'}',
                  ),
                  SelectableText('${outlook['source_url'] ?? ''}'),
                ],
                const Text(
                  'Current-year updates do not replace the five-year annual inputs or change ranking scores.',
                ),
              ],
            ),
            child: const Text('Current-year sources and coverage'),
          ),
        ),
      ],
    );
  }
}
