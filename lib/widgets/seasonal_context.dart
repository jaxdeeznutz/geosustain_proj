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
  const SeasonalContextCard({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final lines = seasonalAssessmentLines(record);
    final snapshot = analysisMapValue(record['seasonal_assessment']);
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
