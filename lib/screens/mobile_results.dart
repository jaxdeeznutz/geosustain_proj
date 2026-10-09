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

bool analysisIsCompleted(Map<String, dynamic> record) =>
    record['session_id'] != null &&
    analysisProcessingLabel(record) == 'Completed';

String analysisRecordName(Map<String, dynamic> record) {
  final name = '${record['farm_name'] ?? ''}'.trim();
  return record['farm_id'] != null && name.isNotEmpty ? name : 'Unnamed area';
}

String analysisLocation(Map<String, dynamic> record) {
  for (final key in ['location_name', 'place_name']) {
    final value = '${record[key] ?? ''}'.trim();
    if (value.isNotEmpty &&
        value != 'Looking up location...' &&
        value != analysisRecordName(record)) {
      return value;
    }
  }
  return '';
}

class AnalysisIdentity extends StatelessWidget {
  final Map<String, dynamic> record;
  final bool compact;
  const AnalysisIdentity({
    super.key,
    required this.record,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) {
    final owner = '${record['owner_display_name'] ?? ''}'.trim();
    final location = analysisLocation(record);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          analysisRecordName(record),
          style: TextStyle(
            fontSize: compact ? 17 : 25,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF20382C),
          ),
        ),
        if (owner.isNotEmpty)
          Text('Owner: $owner', style: const TextStyle(fontSize: 13)),
        if (location.isNotEmpty)
          Text(
            location,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        const SizedBox(height: 6),
        Text(
          '${analysisAreaText(record)} · ${analysisDateText(analysisRecordDate(record))}',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }
}

class AnalysisHistoryRow extends StatelessWidget {
  final Map<String, dynamic> record;
  final VoidCallback? onTap;
  const AnalysisHistoryRow({super.key, required this.record, this.onTap});
  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnalysisIdentity(record: record, compact: true),
                  const SizedBox(height: 8),
                  VerificationStatusBadge(
                    status: '${record['verification_status'] ?? 'draft'}',
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: green),
          ],
        ),
      ),
    ),
  );
}

class NoAnalyses extends StatelessWidget {
  final VoidCallback? goFarms;
  const NoAnalyses({super.key, this.goFarms});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Column(
      children: [
        const Icon(Icons.analytics_outlined, size: 42, color: green),
        const SizedBox(height: 16),
        const Text(
          'No analyses yet',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Analyze a farm to see its results.',
          textAlign: TextAlign.center,
        ),
        if (goFarms != null)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: FilledButton.icon(
              onPressed: goFarms,
              icon: const Icon(Icons.agriculture_outlined),
              label: const Text('Go to My Farms'),
            ),
          ),
      ],
    ),
  );
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
    final rows = newestAnalysisRecords(
      widget.state.historyRecords.where(analysisIsCompleted),
    );
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
                  itemBuilder: (context, i) => AnalysisHistoryRow(
                    record: rows[i],
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
      final state = widget.state;
      final completed = newestAnalysisRecords(
        state.historyRecords.where(analysisIsCompleted),
      );
      final scoped = completed
          .where(
            (r) =>
                state.selectedFarmId == null ||
                '${r['farm_id']}' == '${state.selectedFarmId}',
          )
          .toList();
      final busy =
          _refreshing || _selecting || state.loading || state.historyLoading;
      final error = _error ?? state.analysisError ?? state.historyError;
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
                  tooltip: 'Refresh',
                  onPressed: busy ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ),
              if (busy) const LinearProgressIndicator(),
              if (state.loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(state.loadingMessage),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (result != null) ...[
                if (completed.length > 1)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: busy ? null : _chooseAnalysis,
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Switch analysis'),
                    ),
                  ),
                MobileAnalysisResult(
                  key: ValueKey('analysis-${result['session_id']}'),
                  state: state,
                  record: result,
                ),
              ] else if (!busy && error == null && state.historyLoaded) ...[
                if (state.selectedFarm != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '${state.selectedFarm!['farm_name'] ?? 'Selected farm'}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                if (scoped.isEmpty)
                  NoAnalyses(goFarms: widget.goFarms)
                else ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Choose an analysis',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  for (final row in scoped)
                    AnalysisHistoryRow(
                      record: row,
                      onTap: () async {
                        setState(() => _selecting = true);
                        final failure = await state.selectAnalysis(row);
                        if (mounted) {
                          setState(() {
                            _selecting = false;
                            _error = failure;
                          });
                        }
                      },
                    ),
                ],
              ] else if (!busy && !state.historyLoaded)
                TextButton(
                  onPressed: _refresh,
                  child: const Text('Load analyses'),
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
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: AnalysisIdentity(record: record),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: VerificationStatusBadge(
            status: '${record['verification_status'] ?? 'draft'}',
          ),
        ),
        _AnalysisSection(
          title: 'Land suitability',
          children: [
            Text(
              record['land_status'] == null
                  ? displaySuitability(record)
                  : '${record['land_status']}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (score != null) ...[
              const SizedBox(height: 8),
              Text(
                '${score.toStringAsFixed(1)}% · ${suitabilityLabel(score)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: score.clamp(0, 100) / 100,
                minHeight: 6,
                color: green,
                backgroundColor: softGreen,
              ),
            ],
            if (summary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  summary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        AnalysisCropsCard(record: record),
        _AnalysisSection(
          title: 'Key factors',
          children: [
            for (final factor in analysisListValue(
              xai['supporting_factors'],
            ).take(2))
              _AnalysisParagraph('• $factor'),
            for (final factor in analysisListValue(
              xai['limiting_factors'],
            ).take(2))
              _AnalysisParagraph('• $factor'),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Why this result?'),
              children: [
                if (summary.isNotEmpty) _AnalysisParagraph(summary),
                if (xai['summary'] != null && '${xai['summary']}' != summary)
                  _AnalysisParagraph('${xai['summary']}'),
                for (final factor in analysisListValue(
                  xai['supporting_factors'],
                ))
                  _AnalysisParagraph('Supporting factor: $factor'),
                for (final factor in analysisListValue(xai['limiting_factors']))
                  _AnalysisParagraph('Limiting factor: $factor'),
                if (xai['comparison'] != null)
                  _AnalysisParagraph('${xai['comparison']}'),
                if (xai['method'] != null)
                  _AnalysisParagraph('Method: ${xai['method']}'),
                if (record['recommendation_scoring'] != null)
                  _AnalysisParagraph(
                    'Scoring: ${record['recommendation_scoring']}',
                  ),
                const _AnalysisParagraph(
                  'The score compares crop fit; it is not a harvest probability. High: 75–100; moderate: 50–<75; marginal: 25–<50; low: below 25. Automated analysis is separate from analyst approval.',
                ),
                const _AnalysisParagraph(
                  'Satellite and soil-proxy estimates do not replace field observations or soil tests. Vegetation uses 10 m imagery; elevation and weather data are coarser. Small boundaries may share data with surrounding land.',
                ),
                for (final warning in analysisListValue(
                  record['data_quality_warnings'],
                ))
                  _AnalysisParagraph('$warning'),
              ],
            ),
          ],
        ),
        ExpansionTile(
          title: const Text('Land indicators'),
          tilePadding: EdgeInsets.zero,
          children: [AnalysisIndicatorsCard(record: record)],
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
