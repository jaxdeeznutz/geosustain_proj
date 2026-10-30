part of '../main.dart';

bool farmCanAnalyze(Map<String, dynamic> farm) {
  final coverage = analysisMapValue(farm['analysis_coverage']);
  return coverage['can_analyze'] is bool
      ? coverage['can_analyze'] == true
      : coverage['supported'] != false;
}

const cagroHistoricalNotice =
    'CAGRO nutrient records provide locally available historical soil information for supported Panabo City locations. They may not represent the current exact soil condition of every point within the farm and should be supplemented by field or laboratory assessment when necessary.';
const cagroCoverageNotice =
    'Land analysis is available within the Panabo City reference boundary using estimated nitrogen, phosphorus and potassium. These are model inputs, not a current farm soil test.';

/// Shared Farmer, Analyst and report provenance; never reconstruct an old match.
List<String> analysisCoverageLines(Map<String, dynamic> record) {
  final coverage = analysisMapValue(record['analysis_coverage']);
  final cagroDisabled =
      coverage['cagro_enabled'] == false ||
      record['cagro_reference_enabled'] == false ||
      analysisMapValue(record['cagro_soil'])['status'] == 'disabled';
  final estimated =
      record['nutrient_display_basis'] == 'legacy_model_estimates' ||
      coverage['analysis_mode'] == 'legacy_model_estimates';
  final lines = <String>[
    'Analyzed Farm Location',
    'Farm center latitude: ${record['center_lat'] ?? record['lat'] ?? 'Not recorded'}',
    'Farm center longitude: ${record['center_lon'] ?? record['lon'] ?? 'Not recorded'}',
    'Approximate area: ${analysisAreaText(record)}',
    'Farm center is not a soil sample coordinate.',
    if (cagroDisabled)
      'Analysis coverage: ${coverage['can_analyze'] == false ? 'Outside supported Panabo City boundary' : 'Estimated NPK analysis within Panabo City'}'
    else
      'CAGRO coverage: ${coverage.isEmpty
          ? 'Not recorded under the current coverage policy (older analysis).'
          : coverage['supported'] == true
          ? 'Supported'
          : estimated && coverage['can_analyze'] == true
          ? 'No matching historical record; model analysis uses estimated NPK'
          : coverage['preliminary_supported'] == true
          ? 'Preliminary screening; CAGRO NPK unavailable'
          : coverage['can_analyze'] == false
          ? 'Outside supported Panabo City boundary'
          : 'Location not supported for formal analysis'}',
  ];
  if (estimated) {
    lines.add(
      cagroDisabled
          ? 'Model nutrient source: Recorded nitrogen, phosphorus and potassium estimates.'
          : 'Model nutrient source: Estimated NPK inputs; historical CAGRO observations are separate.',
    );
    final count = analysisNumber(
      analysisMapValue(record['model_nutrient_aggregation'])['sample_count'],
    );
    if (count != null) {
      lines.add(
        'NPK display: ${count.toInt() == 1 ? 'Recorded model input values' : 'Average of recorded model inputs from ${count.toInt()} analysis samples'}. Estimates are not a soil test or fertilizer application rates.',
      );
    }
  }
  if (record['land_cover_notice'] != null) {
    lines.add('Land-cover note: ${record['land_cover_notice']}');
  }
  if (cagroDisabled) return lines;
  if (coverage['supported'] == true) {
    lines.add(
      estimated
          ? 'Historical reference source: Panabo City CAGRO soil records (not used for prediction)'
          : 'Nutrient Source: Panabo City CAGRO historical soil record',
    );
    final seen = <String>{};
    for (final item in analysisListValue(coverage['matches'])) {
      final match = analysisMapValue(item);
      final rule = analysisMapValue(match['match']);
      final boundary = analysisMapValue(rule['boundary']);
      final text =
          'Locality: ${match['locality_id']} / ${match['location_name']}; match: ${analysisMapValue(match['match'])['method']}; confidence: ${match['confidence']}; precision: ${match['coordinate_precision']}; source: ${match['source']}; original sample GPS: ${match['original_cagro_gps'] == true ? 'available' : 'unavailable'}';
      if (seen.add(text)) lines.add(text);
      final evidence = rule['method'] == 'mapped_locality_proximity'
          ? 'Admission rule: all farm vertices within ${rule['radius_m'] ?? 'not recorded'} m; maximum vertex distance ${rule['maximum_vertex_distance_m'] ?? 'not recorded'} m from the reconstructed reference location.'
          : 'Admission rule: farm fully contained in reviewed boundary ${boundary['boundary_id'] ?? 'not recorded'}; boundary source: ${boundary['source'] ?? 'not recorded'}; reviewed: ${boundary['verified_on'] ?? 'date not supplied'}.';
      if (seen.add(evidence)) lines.add(evidence);
    }
    lines.add(cagroHistoricalNotice);
    lines.add(
      'Prediction path: existing Random Forest with legacy nutrient proxies. CAGRO values are local historical evidence, not model inputs.',
    );
  } else if (coverage.isNotEmpty) {
    lines.add('CAGRO soil data unavailable for this location.');
    lines.add(
      estimated
          ? cagroCoverageNotice
          : 'Preliminary environmental screening is available within the Panabo City reference boundary. CAGRO NPK is shown only where a matching historical soil record exists; elsewhere it is unavailable.',
    );
  }
  return lines;
}

/// Report text comes from saved evidence, never from a fresh spatial lookup.
List<String> cagroAnalysisReportLines(Map<String, dynamic> record) {
  final lines = analysisCoverageLines(record);
  lines.addAll(seasonalAssessmentLines(record));
  if (record['analysis_scope_notice'] != null) {
    lines.add('${record['analysis_scope_notice']}');
  }
  final soil = analysisMapValue(record['soil_nutrients_observed']);
  final originals = analysisListValue(
    analysisMapValue(record['cagro_soil'])['observations'],
  );
  for (final raw in analysisListValue(soil['records'])) {
    final row = analysisMapValue(raw);
    final original = analysisMapValue(
      originals
          .where((r) => analysisMapValue(r)['id'] == row['record_id'])
          .firstOrNull,
    );
    lines.add(
      'Historical CAGRO record ${row['record_id']}: ${original['location_name'] ?? 'Address not recorded'}; file ${row['source_file']}; row ${row['source_row']}; date/year ${row['sample_date'] ?? row['sample_year'] ?? 'Not supplied'}',
    );
    for (final nutrient in ['nitrogen', 'phosphorus', 'potassium']) {
      final n = analysisMapValue(row[nutrient]);
      lines.add(
        '$nutrient: ${n['value'] ?? 'Unavailable'} ${n['unit'] ?? ''}; source: ${n['source']}; quality: ${n['quality']}; method: ${n['method'] ?? 'Not documented'}. Not used for model prediction.',
      );
    }
  }
  for (final raw in analysisListValue(
    record['top_crop_recommendations'],
  ).take(5)) {
    final crop = analysisMapValue(raw);
    lines.add('Environmental & Soil Reference Assessment: ${crop['crop']}');
    for (final factor in environmentalFactorViews(crop, record)) {
      final status = switch (factor.state) {
        CropFactorState.suitable => 'Suitable',
        CropFactorState.near => 'Limited',
        CropFactorState.outside => 'Outside documented range',
        CropFactorState.unassessed => 'Not assessed',
      };
      lines.add(
        '${factor.label}: ${factor.valueText ?? factor.value ?? 'Unavailable'} ${factor.unit}; preferred: ${factor.min ?? 'Not documented'} - ${factor.max ?? 'Not documented'} ${factor.unit}; $status. ${factor.interpretation}',
      );
    }
  }
  final xai = verifiedModelExplanation(record);
  if (xai.isNotEmpty) {
    lines.add(
      'Model explanation: ${xai['method_label']}; model version: ${xai['model_version']}; selected crop: ${record['predicted_crop']}; model score: ${record['crop_compatibility_pct']}%; prediction context: ${xai['prediction_context_id'] ?? 'Not recorded'}; input snapshot hash: ${xai['input_snapshot_hash'] ?? 'Not recorded'}.',
    );
    lines.add(
      'Global feature importance describes the trained model, not per-farm causal contributions.',
    );
    for (final raw in analysisListValue(xai['features'])) {
      final f = analysisMapValue(raw);
      lines.add('${f['label']}: global importance ${f['importance']}');
    }
  }
  return lines;
}

class AnalysisCoverageCard extends StatelessWidget {
  final Map<String, dynamic> record;
  const AnalysisCoverageCard({super.key, required this.record});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in analysisCoverageLines(record))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(line),
            ),
        ],
      ),
    ),
  );
}

/// Optional catalogue map plus server preflight; map browsing remains unrestricted.
class CoverageExplorer extends StatefulWidget {
  final ApiService api;
  final List<LatLng> points;
  const CoverageExplorer({super.key, required this.api, required this.points});
  @override
  State<CoverageExplorer> createState() => _CoverageExplorerState();
}

class _CoverageExplorerState extends State<CoverageExplorer> {
  Map<String, dynamic>? _catalog, _checked;
  String? _error;
  bool _busy = false;
  String get _fingerprint => jsonEncode(FarmGeometry.payload(widget.points));
  String? _checkedFingerprint;
  Future<void> _load() async {
    try {
      final data = await widget.api.analysisCoverageCatalog();
      if (mounted) setState(() => _catalog = data);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Coverage map unavailable. Analysis still uses the server city-boundary check.',
        );
      }
    }
  }

  Future<void> _check() async {
    final fingerprint = _fingerprint;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.api.analysisCoverage(
        FarmGeometry.payload(widget.points),
      );
      if (mounted && fingerprint == _fingerprint) {
        setState(() {
          _checked = data;
          _checkedFingerprint = fingerprint;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = FarmGeometry.centroid(widget.points);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(cagroCoverageNotice),
        if (center != null)
          Text(
            'Farm center: ${center.latitude.toStringAsFixed(6)}, ${center.longitude.toStringAsFixed(6)}\nApproximate area: ${(FarmGeometry.areaSquareMetres(widget.points) / 10000).toStringAsFixed(4)} ha\nNot a soil sample coordinate.',
          ),
        OutlinedButton(
          onPressed: _busy || center == null ? null : _check,
          child: Text(
            _busy ? 'Checking analysis coverage…' : 'Check analysis coverage',
          ),
        ),
        if (_checked != null && _checkedFingerprint == _fingerprint)
          AnalysisCoverageCard(record: _checked!),
        if (_error != null) Text(_error!),
        ExpansionTile(
          title: const Text('Panabo City analysis coverage'),
          subtitle: const Text('Supported city reference boundary'),
          onExpansionChanged: (open) {
            if (open && _catalog == null) _load();
          },
          children: [
            if (_catalog == null)
              const Text('Open to load the supported-location catalogue.')
            else ...[
              Text('${_catalog!['note'] ?? ''}'),
              if (_catalog!['error'] != null) Text('${_catalog!['error']}'),
              SizedBox(
                height: 270,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: panaboCenter,
                    initialZoom: 11,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.geosustain.mobile',
                    ),
                    PolygonLayer(polygons: coverageBoundaryPolygons(_catalog!)),
                    MarkerLayer(
                      markers: [
                        for (final raw in analysisListValue(
                          _catalog!['reference_locations'],
                        ))
                          if (analysisNumber(
                                    analysisMapValue(raw)['latitude'],
                                  ) !=
                                  null &&
                              analysisNumber(
                                    analysisMapValue(raw)['longitude'],
                                  ) !=
                                  null)
                            Marker(
                              point: LatLng(
                                analysisNumber(
                                  analysisMapValue(raw)['latitude'],
                                )!,
                                analysisNumber(
                                  analysisMapValue(raw)['longitude'],
                                )!,
                              ),
                              width: 40,
                              height: 40,
                              child: Tooltip(
                                message:
                                    'CAGRO reference location: ${analysisMapValue(raw)['location_name']}',
                                child: const Icon(
                                  Icons.location_on,
                                  color: Colors.deepPurple,
                                  size: 34,
                                ),
                              ),
                            ),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                _catalog!['cagro_enabled'] == false
                    ? 'Blue outline: Panabo City reference boundary (2020, geoBoundaries / NAMRIA / PSA / OCHA; CC BY 3.0 IGO).'
                    : 'Blue outline: Panabo City reference boundary (2020, geoBoundaries / NAMRIA / PSA / OCHA; CC BY 3.0 IGO). Green shading: reviewed CAGRO area. Purple marker: historical soil reference, not exact farm NPK.',
              ),
              for (final raw in analysisListValue(
                _catalog!['reference_locations'],
              ))
                Text(
                  'CAGRO reference location: ${analysisMapValue(raw)['location_name']}',
                ),
            ],
          ],
        ),
      ],
    );
  }
}

List<Polygon> coverageBoundaryPolygons(Map<String, dynamic> catalog) {
  final result = <Polygon>[];
  final features = [
    ...analysisListValue(catalog['boundaries']),
    if (catalog['city_boundary'] is Map) catalog['city_boundary'],
  ];
  for (final raw in features) {
    final isCity =
        analysisMapValue(analysisMapValue(raw)['properties'])['shapeName'] ==
        'City of Panabo';
    final geometry = analysisMapValue(analysisMapValue(raw)['geometry']);
    final polygons = geometry['type'] == 'Polygon'
        ? [geometry['coordinates']]
        : analysisListValue(geometry['coordinates']);
    for (final polygon in polygons) {
      final rings = analysisListValue(polygon)
          .map(
            (ring) => analysisListValue(ring).map((p) {
              final point = analysisListValue(p);
              return LatLng(
                (point[1] as num).toDouble(),
                (point[0] as num).toDouble(),
              );
            }).toList(),
          )
          .toList();
      if (rings.isNotEmpty) {
        result.add(
          Polygon(
            points: rings.first,
            holePointsList: rings.skip(1).toList(),
            color: (isCity ? Colors.blue : Colors.green).withValues(
              alpha: isCity ? .08 : .25,
            ),
            borderColor: isCity ? Colors.blue : Colors.green,
            borderStrokeWidth: 2,
          ),
        );
      }
    }
  }
  return result;
}
