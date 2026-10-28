part of '../main.dart';

/// Historical locality records are separate from the prediction model's inputs.
class CagroSoilObservationsCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final Map<String, dynamic>? crop;
  const CagroSoilObservationsCard({super.key, required this.record, this.crop});

  String _precision(dynamic value) => switch ('$value') {
    'mapped_farm' => 'Mapped farm locality',
    'mapped_purok' => 'Mapped purok locality',
    'farm_area_anchor' => 'Approximate farm-area anchor',
    'barangay_area_anchor' => 'Approximate barangay-area anchor',
    'barangay_anchor' => 'Approximate barangay anchor',
    _ => 'Precision not recorded',
  };

  @override
  Widget build(BuildContext context) {
    final soil = analysisMapValue(record['cagro_soil']);
    if (soil.isEmpty ||
        soil['status'] == 'disabled' ||
        record['cagro_reference_enabled'] == false) {
      return const SizedBox.shrink();
    }
    final scope =
        record['session_id'] ??
        record['id'] ??
        record['farm_id'] ??
        jsonEncode(soil);
    final rows = analysisListValue(
      soil['status'] == 'matched' ? soil['observations'] : [],
    ).whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList();
    if (rows.isEmpty) {
      return GeoResultCard(
        child: ExpansionTile(
          key: PageStorageKey('cagro-$scope-unavailable'),
          tilePadding: EdgeInsets.zero,
          title: const Text(
            'Local soil data',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text('CAGRO soil data unavailable for this farm.'),
          children: [
            const Text('CAGRO soil NPK: Unavailable'),
            Text('${soil['message'] ?? 'No reliable locality match.'}'),
            const SizedBox(height: 8),
            const Text(
              'Missing local soil records do not determine the satellite land-cover result.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Current production model nutrient inputs were trained using a different NPK representation. CAGRO soil NPK observations are shown separately and are not yet used directly by the production model.',
            ),
          ],
        ),
      );
    }
    return GeoResultCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CAGRO historical soil observations',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text('${soil['message'] ?? 'Locality-linked historical records.'}'),
          if (record['analysis_schema_version'] != null)
            const Text(cagroHistoricalNotice),
          const SizedBox(height: 8),
          Text(
            'Primary local soil source: CAGRO. Historical observations are kept separate; a locality match is not a current farm soil test. Crop estimates require compatible nutrient data.',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('CAGRO soil NPK: Unavailable'),
            ),
          for (final row in rows)
            ExpansionTile(
              key: PageStorageKey(
                'cagro-$scope-${row['id'] ?? '${row['source_file']}-${row['source_row']}'}',
              ),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 16),
              title: Text(
                '${row['location_name']}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              subtitle: Text(
                '${_precision(row['coordinate_precision'])}\n'
                '${row['sample_year'] ?? 'Year not supplied'} · Source row ${row['source_row'] ?? 'unavailable'}',
                style: const TextStyle(fontSize: 12),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Source: ${row['source']}'),
                      Text(
                        'Match type: ${analysisMapValue(row['match'])['method'] ?? 'Not recorded'}',
                      ),
                      if (crop != null)
                        for (final assessment in cagroReferenceRecords(
                          crop!,
                          record,
                        ))
                          if (assessment['record_id'] == row['id'])
                            for (final raw in analysisListValue(
                              assessment['factors'],
                            ))
                              Builder(
                                builder: (context) {
                                  final factor = analysisMapValue(raw);
                                  final name = '${factor['factor']}';
                                  return EnvironmentalFactorCard(
                                    factor: cagroNutrientView(
                                      name,
                                      name.isEmpty
                                          ? 'Nutrient'
                                          : '${name[0].toUpperCase()}${name.substring(1)}',
                                      factor,
                                    ),
                                  );
                                },
                              ),
                      Text(
                        'Location precision: ${_precision(row['coordinate_precision'])}',
                      ),
                      Text(
                        'Locality confidence: ${'${row['confidence'] ?? 'not recorded'}'.replaceAll('_', ' ')}',
                      ),
                      Text(
                        'Original CAGRO sample GPS: ${row['original_cagro_gps'] == true ? 'Yes' : 'No'}',
                      ),
                      Text(
                        'Locality anchor: ${row['latitude']}, ${row['longitude']}',
                      ),
                      const SizedBox(height: 10),
                      for (final field in const [
                        ('soil_ph', 'Soil pH', ''),
                        ('organic_matter_pct', 'Organic matter', '%'),
                        (
                          'estimated_nitrogen_pct',
                          'Estimated Nitrogen (%) derived from Organic Matter',
                          '%',
                        ),
                        ('nitrogen_pct', 'Reported Nitrogen (%)', '%'),
                        (
                          'phosphorus_ppm',
                          'Reported soil Phosphorus (ppm)',
                          ' ppm',
                        ),
                        (
                          'potassium_ppm',
                          'Reported soil Potassium (ppm)',
                          ' ppm',
                        ),
                      ])
                        if (analysisNumber(row[field.$1]) != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Text(
                              '${field.$2}: ${_cropNum(analysisNumber(row[field.$1]))}${field.$3}',
                            ),
                          ),
                      const SizedBox(height: 8),
                      Text('${row['nitrogen_method'] ?? ''}'),
                      const Text(
                        'Phosphorus extraction method: Not documented',
                      ),
                      const Text(
                        'Potassium analytical/extraction method: Not documented',
                      ),
                      Text(
                        'Sample date: ${row['sample_date'] ?? 'Not supplied'}',
                      ),
                      const SizedBox(height: 8),
                      Text('${row['data_note'] ?? ''}'),
                      Text(
                        '${row['location_note'] ?? ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Source record: ${row['source_file']}, row ${row['source_row']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
