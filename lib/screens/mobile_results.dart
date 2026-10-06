part of '../main.dart';

Map<String, dynamic> analysisMapValue(dynamic raw) {
  if (raw is String) {
    try {
      raw = jsonDecode(raw);
    } catch (_) {
      return {};
    }
  }
  return raw is Map ? Map<String, dynamic>.from(raw) : {};
}

List<dynamic> analysisListValue(dynamic raw) {
  if (raw is String) {
    try {
      raw = jsonDecode(raw);
    } catch (_) {
      return [];
    }
  }
  return raw is List ? raw : [];
}

double? analysisNumber(dynamic raw) {
  final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
  return value != null && value.isFinite ? value : null;
}

String analysisRecordName(Map<String, dynamic> record) {
  for (final key in ['farm_name', 'place_name', 'title', 'location_name']) {
    final value = '${record[key] ?? ''}'.trim();
    if (value.isNotEmpty && value != 'Looking up location...') return value;
  }
  return 'Analyzed area';
}

DateTime? analysisRecordDate(Map<String, dynamic> record) {
  for (final key in ['analyzed_at', 'created_at', 'date']) {
    final parsed = DateTime.tryParse('${record[key] ?? ''}');
    if (parsed != null) return parsed;
  }
  return null;
}

String analysisDateText(dynamic value) {
  final parsed = DateTime.tryParse('$value')?.toLocal();
  if (parsed == null) return 'Date unavailable';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = parsed.hour.toString().padLeft(2, '0');
  final minute = parsed.minute.toString().padLeft(2, '0');
  return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year} · $hour:$minute';
}

String analysisAreaText(Map<String, dynamic> record) {
  final hectares =
      analysisNumber(record['area_hectares']) ??
      (analysisNumber(record['area_m2']) == null
          ? null
          : analysisNumber(record['area_m2'])! / 10000);
  if (hectares == null) return 'Area unavailable';
  if (hectares < 0.01) return '${(hectares * 10000).toStringAsFixed(1)} m²';
  return '${hectares.toStringAsFixed(3)} ha';
}

List<Map<String, dynamic>> newestAnalysisRecords(
  Iterable<Map<String, dynamic>> rows,
) {
  final result = rows.map((row) => Map<String, dynamic>.from(row)).toList();
  result.sort((a, b) {
    final dates = (analysisRecordDate(b)?.millisecondsSinceEpoch ?? 0)
        .compareTo(analysisRecordDate(a)?.millisecondsSinceEpoch ?? 0);
    if (dates != 0) return dates;
    return (analysisNumber(b['session_id']) ?? 0).compareTo(
      analysisNumber(a['session_id']) ?? 0,
    );
  });
  return result;
}

String analysisProcessingLabel(Map<String, dynamic> record) {
  final status =
      '${record['analysis_status'] ?? record['processing_status'] ?? ''}'
          .toLowerCase();
  switch (status) {
    case 'completed':
    case 'success':
      return 'Completed';
    case 'processing':
    case 'running':
      return 'Processing';
    case 'failed':
    case 'error':
      return 'Failed';
    case 'queued':
      return 'Queued';
    case '':
      // The existing synchronous API persists sessions only after analysis succeeds.
      return record['session_id'] != null ? 'Completed' : 'Status unavailable';
    default:
      return status;
  }
}

String analysisReviewLabel(String status) => switch (status.toLowerCase()) {
  'draft' => 'Not Submitted',
  'pending' => 'Pending Review',
  'verified' => 'Approved',
  'rejected' => 'Rejected',
  _ => 'Review status unavailable',
};

class MobileAnalysisPage extends StatefulWidget {
  final AnalysisState state;
  final VoidCallback goFarms;
  const MobileAnalysisPage({
    super.key,
    required this.state,
    required this.goFarms,
  });

  @override
  State<MobileAnalysisPage> createState() => _MobileAnalysisPageState();
}

class _MobileAnalysisPageState extends State<MobileAnalysisPage> {
  bool _refreshing = false;
  bool _selecting = false;
  String? _error;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      await widget.state.refreshHistoryData();
      if (!mounted) return;
      _error = widget.state.historyError;
    } catch (e) {
      _error = friendlyErrorMessage(e);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _chooseAnalysis() async {
    final rows = newestAnalysisRecords(widget.state.historyRecords);
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Choose an analysis',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) => ListTile(
                    title: Text(analysisRecordName(rows[i])),
                    subtitle: Text(
                      '${analysisDateText(analysisRecordDate(rows[i]))}\n${analysisAreaText(rows[i])}',
                    ),
                    isThreeLine: true,
                    trailing:
                        '${rows[i]['session_id']}' ==
                            '${widget.state.result?['session_id']}'
                        ? const Icon(Icons.check_circle, color: green)
                        : null,
                    onTap: () => Navigator.pop(context, rows[i]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selecting = true;
      _error = null;
    });
    try {
      final error = await widget.state.selectAnalysis(selected);
      if (mounted) setState(() => _error = error);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final result = widget.state.result;
      return SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            key: const PageStorageKey('mobile-analysis-scroll'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              MobileHeader(
                title: 'Analysis',
                trailing: IconButton(
                  tooltip: 'Refresh analysis and review status',
                  onPressed: _refreshing ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ),
              if (_refreshing || _selecting || widget.state.loading)
                const LinearProgressIndicator(),
              if (_error != null || widget.state.historyError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error ?? widget.state.historyError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (widget.state.historyRecords.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _selecting ? null : _chooseAnalysis,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Choose a farm or analysis'),
                ),
              if (result == null) ...[
                const SizedBox(height: 32),
                const Icon(Icons.analytics_outlined, size: 54, color: green),
                const SizedBox(height: 16),
                const Text(
                  'Understand your land',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.state.historyRecords.isEmpty
                      ? 'Map your farm in My Farms, then run an analysis to see crop suitability and the factors behind the results.'
                      : 'Choose a saved analysis above to view its results and analyst feedback.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: widget.goFarms,
                  icon: const Icon(Icons.agriculture),
                  label: const Text('Go to My Farms'),
                ),
              ] else
                MobileAnalysisResult(
                  key: ValueKey('analysis-${result['session_id']}'),
                  state: widget.state,
                  record: result,
                ),
            ],
          ),
        ),
      );
    },
  );
}

class MobileAnalysisResult extends StatelessWidget {
  final AnalysisState state;
  final Map<String, dynamic> record;
  const MobileAnalysisResult({
    super.key,
    required this.state,
    required this.record,
  });

  @override
  Widget build(BuildContext context) {
    final xai = analysisMapValue(record['xai_explanation']);
    final score = analysisNumber(
      record['crop_compatibility_pct'] ?? record['compatibility_pct'],
    );
    final summary =
        '${record['analysis_summary'] ?? xai['plain_summary'] ?? xai['summary'] ?? ''}'
            .trim();
    final recommendation = '${record['recommendation'] ?? ''}'.trim();
    final cropName = '${record['predicted_crop'] ?? ''}'.trim();
    final actions = <String>{
      for (final value in [
        xai['planning_advice'],
        if (recommendation.toLowerCase() != cropName.toLowerCase())
          recommendation,
        if (record['recommended_planting_window'] != null)
          'Planting window: ${record['recommended_planting_window']}',
        record['season_advice'],
      ])
        if (value != null && '$value'.trim().isNotEmpty) '$value'.trim(),
      ...analysisListValue(
        record['land_use_recommendations'],
      ).map((e) => 'Land-use option: $e'),
    }.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AnalysisSection(
          title: 'Analysis overview',
          children: [
            Text(
              analysisRecordName(record),
              style: const TextStyle(
                fontSize: 22,
                color: green,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${analysisAreaText(record)} · ${analysisDateText(analysisRecordDate(record))}',
            ),
            const SizedBox(height: 8),
            Text('Analysis: ${analysisProcessingLabel(record)}'),
            const SizedBox(height: 8),
            VerificationStatusBadge(
              status: '${record['verification_status'] ?? 'draft'}',
            ),
            const SizedBox(height: 12),
            Text(
              summary.isEmpty
                  ? 'A written summary is unavailable for this analysis.'
                  : summary,
            ),
            const SizedBox(height: 8),
            const Text(
              'Automated decision support. Analyst review is shown separately below.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        _AnalysisSection(
          title: 'Land suitability',
          children: [
            Text(
              record['land_status'] == null
                  ? displaySuitability(record)
                  : '${record['land_status']}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (score != null) ...[
              const SizedBox(height: 10),
              Text(
                '${score.toStringAsFixed(1)}% · ${suitabilityLabel(score)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: score.clamp(0, 100) / 100,
                minHeight: 8,
                color: green,
                backgroundColor: softGreen,
              ),
              const SizedBox(height: 10),
              const Text(
                'A comparative crop-fit score, not the probability of a successful harvest. High: 75–100; moderate: 50–<75; marginal: 25–<50; low: below 25.',
                style: TextStyle(fontSize: 12),
              ),
            ] else ...[
              const SizedBox(height: 8),
              const Text(
                'No crop suitability score was returned for this analysis.',
              ),
            ],
          ],
        ),
        AnalysisIndicatorsCard(record: record),
        AnalysisCropsCard(record: record),
        _AnalysisSection(
          title: 'Explainable AI',
          children: [
            Text(
              '${xai['plain_summary'] ?? xai['summary'] ?? 'An explanation is unavailable for this saved analysis.'}',
            ),
            if (xai.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 12),
                title: const Text('Factors and explanation details'),
                children: [
                  if (xai['summary'] != null)
                    _AnalysisParagraph('${xai['summary']}'),
                  for (final factor in analysisListValue(
                    xai['supporting_factors'],
                  ))
                    _AnalysisParagraph('Supporting factor: $factor'),
                  for (final factor in analysisListValue(
                    xai['limiting_factors'],
                  ))
                    _AnalysisParagraph('Limiting factor: $factor'),
                  if ('${xai['comparison'] ?? ''}'.isNotEmpty)
                    _AnalysisParagraph('${xai['comparison']}'),
                  if (xai['method'] != null)
                    _AnalysisParagraph('Method: ${xai['method']}'),
                  if (record['recommendation_scoring'] != null)
                    _AnalysisParagraph(
                      'Scoring: ${record['recommendation_scoring']}',
                    ),
                ],
              ),
            const SizedBox(height: 8),
            const Text(
              'These factors explain the system’s ranking. They do not prove causes or guarantee crop performance.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        _AnalysisSection(
          title: 'Practical recommendations',
          children: [
            if (actions.isEmpty)
              const Text(
                'No practical recommendations were returned for this analysis.',
              ),
            for (var i = 0; i < actions.length && i < 3; i++)
              _AnalysisParagraph('${i + 1}. ${actions[i]}'),
            if (actions.length > 3)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('More recommendations'),
                children: [
                  for (final action in actions.skip(3))
                    _AnalysisParagraph(action),
                ],
              ),
          ],
        ),
        AnalysisBoundaryPreview(record: record),
        AnalysisReviewCard(state: state, record: record),
        OutlinedButton.icon(
          onPressed: () async {
            try {
              await generateAnalysisPdf(record, state: state);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(friendlyErrorMessage(e))),
                );
              }
            }
          },
          icon: const Icon(Icons.download_outlined),
          label: const Text('Export analysis report'),
        ),
      ],
    );
  }
}

class _AnalysisParagraph extends StatelessWidget {
  final String text;
  const _AnalysisParagraph(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Align(alignment: Alignment.centerLeft, child: Text(text)),
  );
}

class _AnalysisSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _AnalysisSection({required this.title, required this.children});
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 8),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}

class AnalysisIndicatorsCard extends StatelessWidget {
  final Map<String, dynamic> record;
  const AnalysisIndicatorsCard({super.key, required this.record});
  @override
  Widget build(BuildContext context) {
    final quality = analysisMapValue(record['data_quality']);
    const indicators = [
      ('ndvi', 'Vegetation (NDVI)', '', 'ndvi'),
      ('soil_ph', 'Soil pH', '', 'soil_ph'),
      ('rainfall_mm', '30-day rainfall', 'mm', 'rainfall'),
      ('temperature_c', 'Temperature', '°C', 'temperature'),
      ('live_humidity', 'Humidity', '%', 'humidity'),
      ('elevation_m', 'Elevation', 'm', 'elevation'),
      ('slope_pct', 'Slope', '%', 'slope'),
      ('nitrogen', 'Nitrogen', '', 'nitrogen'),
      ('phosphorus', 'Phosphorus', '', 'phosphorus'),
      ('potassium', 'Potassium', '', 'potassium'),
    ];
    final present = indicators
        .where((item) => analysisNumber(record[item.$1]) != null)
        .toList();
    final warnings = analysisListValue(record['data_quality_warnings']);
    return _AnalysisSection(
      title: 'Land indicators',
      children: [
        if (present.isEmpty)
          const Text(
            'Environmental measurements are unavailable for this analysis.',
          ),
        for (final item in present)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(item.$2)),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        '${analysisNumber(record[item.$1])!.toStringAsFixed(item.$1 == 'ndvi' ? 3 : 1)}${item.$3.isEmpty ? '' : ' ${item.$3}'}',
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                if (quality[item.$4] != null)
                  Text(
                    '${analysisMapValue(quality[item.$4])['overall_quality'] ?? analysisMapValue(quality[item.$4])['quality'] ?? 'Source quality unavailable'}'
                        .replaceAll('_', ' '),
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
              ],
            ),
          ),
        if (present.any(
          (i) => ['nitrogen', 'phosphorus', 'potassium'].contains(i.$1),
        ))
          const Text(
            'Nutrient values are model inputs. Units are not specified in these records; they are not fertilizer application rates.',
            style: TextStyle(fontSize: 12),
          ),
        if (warnings.isNotEmpty || quality.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Data sources and limitations'),
            children: [
              for (final warning in warnings) _AnalysisParagraph('$warning'),
              for (final item in present)
                if (analysisMapValue(quality[item.$4])['source'] != null)
                  _AnalysisParagraph(
                    '${item.$2}: ${analysisMapValue(quality[item.$4])['source']}',
                  ),
              const _AnalysisParagraph(
                'NDVI describes vegetation, from −1 to 1. Soil and terrain estimates should be checked in the field when making planting decisions.',
              ),
            ],
          ),
      ],
    );
  }
}

class AnalysisCropsCard extends StatelessWidget {
  final Map<String, dynamic> record;
  const AnalysisCropsCard({super.key, required this.record});
  @override
  Widget build(BuildContext context) {
    final flag = record['is_crop_recommended'];
    final cropAllowed =
        flag != false && '$flag'.toLowerCase() != 'false' && '$flag' != '0';
    final crops = <Map<String, dynamic>>[];
    if (cropAllowed) {
      final top = analysisListValue(record['top_crop_recommendations']);
      if (top.isNotEmpty) {
        crops.addAll(
          top.whereType<Map>().map((row) => Map<String, dynamic>.from(row)),
        );
      } else {
        final primary = '${record['predicted_crop'] ?? ''}'.trim();
        if (primary.isNotEmpty &&
            primary != 'Land Analysis' &&
            primary.toLowerCase() != 'no crop recommended') {
          crops.add({
            'crop': primary,
            'compatibility_pct':
                record['crop_compatibility_pct'] ?? record['compatibility_pct'],
          });
        }
        crops.addAll(
          analysisListValue(
            record['alternative_crops'],
          ).whereType<Map>().map((row) => Map<String, dynamic>.from(row)),
        );
      }
    }
    final unique = <String>{};
    crops.removeWhere(
      (crop) => !unique.add('${crop['crop'] ?? crop['name']}'.toLowerCase()),
    );
    final xai = analysisMapValue(record['xai_explanation']);
    return _AnalysisSection(
      title: 'Recommended crops',
      children: [
        if (crops.isEmpty)
          Text(
            cropAllowed
                ? 'No crop recommendations are available for this analysis.'
                : 'The analysis did not recommend planting a crop in this area. See its land assessment and practical recommendations.',
          ),
        for (var i = 0; i < crops.length; i++) ...[
          if (i > 0) const Divider(height: 24),
          Text(
            '${i + 1}. ${crops[i]['crop'] ?? crops[i]['name'] ?? 'Unnamed crop'}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 6),
          if (analysisNumber(crops[i]['compatibility_pct'] ?? crops[i]['score'])
              case final double score) ...[
            Text('${score.toStringAsFixed(1)}% · ${suitabilityLabel(score)}'),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: score.clamp(0, 100) / 100,
              minHeight: 6,
              color: green,
              backgroundColor: softGreen,
            ),
          ] else
            const Text('Suitability score unavailable'),
          const SizedBox(height: 8),
          Text(
            '${crops[i]['reason'] ?? crops[i]['explanation'] ?? crops[i]['suitability_note'] ?? (i == 0 ? xai['plain_summary'] : null) ?? 'No crop-specific explanation was returned.'}',
          ),
        ],
      ],
    );
  }
}

class AnalysisBoundaryPreview extends StatelessWidget {
  final Map<String, dynamic> record;
  const AnalysisBoundaryPreview({super.key, required this.record});
  @override
  Widget build(BuildContext context) {
    final points = <LatLng>[];
    for (final point in analysisListValue(record['selected_polygon'])) {
      if (point is! Map) continue;
      final lat = analysisNumber(point['lat']);
      final lng = analysisNumber(point['lng'] ?? point['lon']);
      if (lat != null && lng != null && lat.abs() <= 90 && lng.abs() <= 180) {
        points.add(LatLng(lat, lng));
      }
    }
    if (points.length < 3) return const SizedBox.shrink();
    return Card(
      child: ExpansionTile(
        title: const Text('Analyzed boundary'),
        subtitle: Text(analysisAreaText(record)),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          const Text(
            'This boundary belongs to this analysis. Later edits to the farm do not change it.',
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 230,
            child: FlutterMap(
              key: ValueKey('boundary-${record['session_id']}'),
              options: MapOptions(
                initialCameraFit: CameraFit.coordinates(
                  coordinates: points,
                  padding: const EdgeInsets.all(24),
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.geosustain.mobile',
                ),
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: points,
                      color: green.withValues(alpha: .2),
                      borderColor: green,
                      borderStrokeWidth: 3,
                    ),
                  ],
                ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AnalysisReviewCard extends StatefulWidget {
  final AnalysisState state;
  final Map<String, dynamic> record;
  const AnalysisReviewCard({
    super.key,
    required this.state,
    required this.record,
  });
  @override
  State<AnalysisReviewCard> createState() => _AnalysisReviewCardState();
}

class _AnalysisReviewCardState extends State<AnalysisReviewCard> {
  bool _submitting = false;
  String? _error;
  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final saved = await widget.state.submitAnalysisRecord(widget.record);
      if (!saved) {
        throw StateError(
          'This analysis has not been saved to the server. Refresh before submitting.',
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Analysis submitted for analyst review.')),
      );
    } catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = '${widget.record['verification_status'] ?? 'draft'}';
    final eligible =
        widget.state.accountRole == 'farmer' &&
        widget.record['session_id'] != null &&
        analysisProcessingLabel(widget.record) == 'Completed' &&
        ['draft', 'rejected'].contains(status);
    return _AnalysisSection(
      title: 'Analyst review',
      children: [
        VerificationStatusBadge(status: status),
        const SizedBox(height: 10),
        Text(switch (status) {
          'verified' =>
            'An analyst approved this analysis. This decision applies to this analysis and its recorded boundary.',
          'pending' =>
            'Your analysis is awaiting an analyst’s decision. Refresh to retrieve the latest review.',
          'rejected' =>
            'Review the analyst’s feedback before submitting again. A new analysis starts with its own review status.',
          _ =>
            'Completing an automated analysis does not submit it or approve it. Submit when you are ready for an analyst to review these results.',
        }),
        if (widget.record['verified_at'] != null) ...[
          const SizedBox(height: 8),
          Text('Reviewed: ${analysisDateText(widget.record['verified_at'])}'),
        ],
        if ('${widget.record['planner_notes'] ?? ''}'.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Analyst feedback: ${widget.record['planner_notes']}'),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (eligible) ...[
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(
              _submitting
                  ? 'Submitting…'
                  : status == 'rejected'
                  ? 'Resubmit for Analyst Review'
                  : 'Submit for Analyst Review',
            ),
          ),
        ],
      ],
    );
  }
}
