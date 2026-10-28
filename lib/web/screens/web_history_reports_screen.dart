part of '../../main.dart';

class WebHistoryScreen extends StatefulWidget {
  final AnalysisState state;
  final bool compact;
  const WebHistoryScreen({
    super.key,
    required this.state,
    this.compact = false,
  });

  @override
  State<WebHistoryScreen> createState() => _WebHistoryScreenState();
}

class _WebHistoryScreenState extends State<WebHistoryScreen> {
  AnalysisState get state => widget.state;
  bool get compact => widget.compact;
  late final _records = WebRecordController(
    state.api,
    '/api/web/history',
    'history',
    limit: 20,
  );
  int get _page => _records.offset ~/ 20;
  String get _query => _records.query;
  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    if (!compact) {
      _records.addListener(_changed);
      _records.load();
    }
  }

  @override
  void dispose() {
    _records.removeListener(_changed);
    _records.dispose();
    super.dispose();
  }

  String _topCropFromRecord(Map<String, dynamic> r) {
    final direct =
        r['crop_recommendation'] ??
        r['recommended_crop'] ??
        r['predicted_crop'] ??
        r['crop'];
    if (direct != null && '$direct'.trim().isNotEmpty && '$direct' != '--') {
      return '$direct';
    }
    final top = r['top_crop_recommendations'];
    if (top is List && top.isNotEmpty && top.first is Map) {
      final first = top.first as Map;
      final name = first['crop'] ?? first['name'];
      if (name != null && '$name'.trim().isNotEmpty) return '$name';
    }
    return '--';
  }

  @override
  Widget build(BuildContext context) {
    final rows = compact
        ? state.historyRecords.take(5).toList()
        : _records.rows;
    return _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.isPlanner && !compact) ...[
            const Text(
              'My analyst assessments',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const Text(
              'These records belong to your account. Review farmer submissions and their decisions in the Review Inbox.',
            ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => PortalRoutes.go('/operator/analyze'),
                  icon: const Icon(Icons.add_location_alt),
                  label: const Text('Analyze an area'),
                ),
                TextButton.icon(
                  onPressed: () => PortalRoutes.go('/operator/queue'),
                  icon: const Icon(Icons.fact_check),
                  label: const Text('Open Review Inbox'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (!compact) ...[
            TextField(
              decoration: InputDecoration(
                labelText: 'Search all records',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _records.search,
            ),
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${rows.length} records · Page ${_page + 1}'),
                TextButton(
                  onPressed: !_records.loading && _page > 0
                      ? () => _records.load(offset: (_page - 1) * 20)
                      : null,
                  child: Text('Previous'),
                ),
                TextButton(
                  onPressed: !_records.loading && _records.more
                      ? () => _records.load(offset: (_page + 1) * 20)
                      : null,
                  child: Text('Next'),
                ),
              ],
            ),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  state.isPlanner
                      ? 'Recent analyst assessments'
                      : 'Recent Analyses',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              if (compact)
                Text(
                  'View All',
                  style: TextStyle(
                    color: WebPortalColors.accent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          SizedBox(height: 16),
          if (!compact) ...[
            if (_records.loading)
              LinearProgressIndicator(semanticsLabel: 'Loading records'),
            if (_records.error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  '${_records.error} ${rows.isEmpty ? '' : 'Previously loaded records may be out of date.'}',
                ),
              ),
            TextButton.icon(
              onPressed: _records.loading ? null : () => _records.load(),
              icon: Icon(Icons.refresh),
              label: Text(
                _records.error == null ? 'Refresh records' : 'Retry records',
              ),
            ),
          ],
          if (rows.isEmpty &&
              (compact || (!_records.loading && _records.error == null)))
            Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: Text(
                  _query.isNotEmpty
                      ? 'No records match your search.'
                      : 'No analysis history yet.',
                  style: TextStyle(color: WebPortalColors.muted),
                ),
              ),
            )
          else
            ...rows.map((r) {
              final pctRaw =
                  r['crop_compatibility_pct'] ?? r['compatibility_pct'];
              final pct = pctRaw is num
                  ? pctRaw.toDouble()
                  : double.tryParse('$pctRaw');
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final rawId = r['session_id'] ?? r['id'];
                  final sessionId = rawId is num
                      ? rawId.toInt()
                      : int.tryParse('$rawId');
                  if (sessionId == null) return;
                  await showDialog<void>(
                    context: context,
                    builder: (_) => _WebHistoryDetailDialog(
                      record: state.normalizeRecord(
                        Map<String, dynamic>.from(r),
                      ),
                      state: state,
                      topCrop: _topCropFromRecord(r),
                      suitabilityPct: pct,
                    ),
                  );
                },
                child: Container(
                  margin: EdgeInsets.only(bottom: 12),
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: WebPortalColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Color(0xFFE3ECE5)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: WebPortalColors.tint,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.eco_rounded,
                          color: WebPortalColors.accent,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        flex: 22,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${r['place_name'] ?? r['location'] ?? 'Analyzed Area'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '${r['date'] ?? r['analyzed_at'] ?? ''}'
                                  .split('T')
                                  .first,
                              style: TextStyle(
                                color: WebPortalColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 14,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'RECOMMENDED CROP',
                              style: TextStyle(
                                fontSize: 10,
                                color: WebPortalColors.muted,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              _topCropFromRecord(r),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'SUITABILITY',
                              style: TextStyle(
                                fontSize: 10,
                                color: WebPortalColors.muted,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              pct == null ? '--' : '${pct.toStringAsFixed(1)}%',
                              style: TextStyle(
                                color: WebPortalColors.accent,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 10),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: WebPortalColors.accent,
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class WebReportsScreen extends StatefulWidget {
  final AnalysisState state;
  final bool compact;
  const WebReportsScreen({
    super.key,
    required this.state,
    this.compact = false,
  });

  @override
  State<WebReportsScreen> createState() => _WebReportsScreenState();
}

class _WebReportsScreenState extends State<WebReportsScreen> {
  AnalysisState get state => widget.state;
  bool get compact => widget.compact;
  late final _records = WebRecordController(
    state.api,
    '/api/mobile/reports',
    'reports',
    limit: 50,
  );
  int get _page => _records.offset ~/ 50;
  String get _query => _records.query;
  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    if (!compact) {
      _records.addListener(_changed);
      _records.load();
    }
  }

  @override
  void dispose() {
    _records.removeListener(_changed);
    _records.dispose();
    super.dispose();
  }

  Future<void> _downloadReport(
    BuildContext context,
    Map<String, dynamic> raw,
  ) async {
    final item = state.normalizeRecord(Map<String, dynamic>.from(raw));
    try {
      await generateAnalysisPdf(item, state: state);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = compact
        ? state.generatedReports.take(4).toList()
        : _records.rows;
    return _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.isPlanner && !compact) ...[
            const Text(
              'Assessment and review reports',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Your generated assessment reports appear below. Export a review case from its workspace, or a planning summary from the Dashboard.',
            ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => PortalRoutes.go('/operator/queue'),
                  child: const Text('Open review cases'),
                ),
                TextButton(
                  onPressed: () => PortalRoutes.go('/operator/dashboard'),
                  child: const Text('Open planning summary'),
                ),
                TextButton.icon(
                  onPressed: () => PortalRoutes.go('/operator/trends'),
                  icon: const Icon(Icons.show_chart),
                  label: const Text('Recommendation Patterns'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (!compact) ...[
            TextField(
              decoration: InputDecoration(
                labelText: 'Search all records',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _records.search,
            ),
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${rows.length} records · Page ${_page + 1}'),
                TextButton(
                  onPressed: !_records.loading && _page > 0
                      ? () => _records.load(offset: (_page - 1) * 50)
                      : null,
                  child: Text('Previous'),
                ),
                TextButton(
                  onPressed: !_records.loading && _records.more
                      ? () => _records.load(offset: (_page + 1) * 50)
                      : null,
                  child: Text('Next'),
                ),
              ],
            ),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  'Recent Reports',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              if (compact)
                Text(
                  'View All',
                  style: TextStyle(
                    color: WebPortalColors.accent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          SizedBox(height: 16),
          if (!compact) ...[
            if (_records.loading)
              LinearProgressIndicator(semanticsLabel: 'Loading records'),
            if (_records.error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  '${_records.error} ${rows.isEmpty ? '' : 'Previously loaded records may be out of date.'}',
                ),
              ),
            TextButton.icon(
              onPressed: _records.loading ? null : () => _records.load(),
              icon: Icon(Icons.refresh),
              label: Text(
                _records.error == null ? 'Refresh records' : 'Retry records',
              ),
            ),
          ],
          if (rows.isEmpty &&
              (compact || (!_records.loading && _records.error == null)))
            Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: Text(
                  _query.isNotEmpty
                      ? 'No records match your search.'
                      : 'No reports generated yet.',
                  style: TextStyle(color: WebPortalColors.muted),
                ),
              ),
            )
          else
            ...rows.map((r) {
              final item = state.normalizeRecord(Map<String, dynamic>.from(r));
              final title =
                  '${r['report_title'] ?? r['title'] ?? 'GeoSustain Analysis Report'}';
              final date =
                  '${r['report_created_at'] ?? r['created_at'] ?? r['date'] ?? 'Recently generated'}';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(0xFFFFEBEB),
                  child: Icon(Icons.picture_as_pdf_rounded, color: Colors.red),
                ),
                title: Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${item['predicted_crop'] ?? 'Land analysis'} · $date',
                ),
                trailing: IconButton(
                  tooltip: 'Download PDF',
                  icon: Icon(
                    Icons.download_rounded,
                    color: WebPortalColors.accent,
                  ),
                  onPressed: () => _downloadReport(context, r),
                ),
                onTap: () => _downloadReport(context, r),
              );
            }),
        ],
      ),
    );
  }
}

class _WebHistoryDetailDialog extends StatefulWidget {
  final Map<String, dynamic> record;
  final AnalysisState state;
  final String topCrop;
  final double? suitabilityPct;

  const _WebHistoryDetailDialog({
    required this.record,
    required this.state,
    required this.topCrop,
    required this.suitabilityPct,
  });

  @override
  State<_WebHistoryDetailDialog> createState() =>
      _WebHistoryDetailDialogState();
}

class _WebHistoryDetailDialogState extends State<_WebHistoryDetailDialog> {
  bool _saving = false;
  bool _reporting = false;

  String _num(dynamic value, {int decimals = 2}) {
    final n = value is num ? value : num.tryParse('$value');
    if (n == null) return '--';
    return n.toStringAsFixed(decimals);
  }

  String _slopeText(Map<String, dynamic> record) {
    final raw = record['slope_pct'] ?? record['slope'];
    final text = widget.state.numText(raw);
    return text == '--' ? '--' : '$text%';
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final saved = await widget.state.saveAnalysisRecord(widget.record);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(saved ? 'Analysis saved.' : 'Already saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addToReports() async {
    if (_reporting) return;
    setState(() => _reporting = true);
    try {
      final added = await widget.state.createReportRecord(widget.record);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            added
                ? 'Added to Reports. You can download it from the Reports page.'
                : 'This analysis is already in Reports.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Report failed: $e')));
    } finally {
      if (mounted) setState(() => _reporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final state = widget.state;
    final topCrop = widget.topCrop;
    final place = record['title'] ?? record['place_name'] ?? 'Analyzed Area';
    final lat = record['center_lat'] ?? record['lat'];
    final lon = record['center_lon'] ?? record['lon'];
    final compatibility = WebAnalysisMetrics.modelScore(record);
    final suitability = WebAnalysisMetrics.preliminary(record)
        ? 'Preliminary screening ? model score not assessed'
        : 'Model score';
    final infraData = <String, dynamic>{...record};

    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      contentPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: LocationHistoryThumb(lat: lat, lon: lon, expanded: true),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(22, 18, 22, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$place',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: WebPortalColors.accent,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      state.recommendationText(record),
                      style: TextStyle(
                        color: WebPortalColors.muted,
                        height: 1.35,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      topCrop,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 10),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: suitabilityColor(compatibility),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$suitability · ${compatibility == null ? 'Not assessed' : '${compatibility.toStringAsFixed(1)}%'}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Coordinates: $lat, $lon',
                      style: TextStyle(
                        fontSize: 13,
                        color: WebPortalColors.muted,
                      ),
                    ),
                    if (record['date'] != null) ...[
                      SizedBox(height: 4),
                      Text(
                        'Analyzed: ${record['date']}',
                        style: TextStyle(
                          fontSize: 13,
                          color: WebPortalColors.muted,
                        ),
                      ),
                    ],
                    Divider(height: 28),
                    WebAnalysisEvidence(state: state, record: record),
                    Text(
                      'ENVIRONMENTAL DATA',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: WebPortalColors.accent,
                        letterSpacing: 0.4,
                      ),
                    ),
                    SizedBox(height: 10),
                    DetailLine(
                      label: 'NDVI',
                      value: _num(record['ndvi'], decimals: 3),
                    ),
                    DetailLine(
                      label: 'Rainfall',
                      value: '${_num(record['rainfall_mm'], decimals: 1)} mm',
                    ),
                    DetailLine(
                      label: 'Temperature',
                      value: '${_num(record['temperature_c'], decimals: 1)} °C',
                    ),
                    DetailLine(
                      label: 'Elevation',
                      value: '${_num(record['elevation_m'], decimals: 1)} m',
                    ),
                    DetailLine(
                      label: 'Soil pH',
                      value: _num(record['soil_ph'], decimals: 2),
                    ),
                    DetailLine(
                      label: 'Nitrogen',
                      value: _num(record['nitrogen'], decimals: 0),
                    ),
                    DetailLine(
                      label: 'Phosphorus',
                      value: _num(record['phosphorus'], decimals: 0),
                    ),
                    DetailLine(
                      label: 'Potassium',
                      value: _num(record['potassium'], decimals: 0),
                    ),
                    DetailLine(
                      label: 'Humidity',
                      value: record['live_humidity'] == null
                          ? '--'
                          : '${_num(record['live_humidity'], decimals: 0)}%',
                    ),
                    DetailLine(
                      label: 'Weather',
                      value: '${record['weather_description'] ?? '--'}',
                    ),
                    if (record['land_status'] != null)
                      DetailLine(
                        label: 'Land Status',
                        value: '${record['land_status']}',
                      ),
                    Divider(height: 28),
                    Text(
                      'INFRASTRUCTURE REPORT',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: WebPortalColors.accent,
                        letterSpacing: 0.4,
                      ),
                    ),
                    SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: infrastructureColor(
                          infraData,
                        ).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: infrastructureColor(
                            infraData,
                          ).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${record['infrastructure_suitability'] ?? '--'}',
                            style: TextStyle(
                              color: infrastructureColor(infraData),
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            '${record['infrastructure_status'] ?? 'No infrastructure status recorded for this analysis.'}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                          if (record['infrastructure_recommendation'] !=
                              null) ...[
                            SizedBox(height: 6),
                            Text(
                              '${record['infrastructure_recommendation']}',
                              style: TextStyle(
                                fontSize: 12,
                                color: WebPortalColors.muted,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(height: 12),
                    DetailLine(
                      label: 'Infrastructure Score',
                      value: '${record['infrastructure_score'] ?? '--'}',
                    ),
                    DetailLine(
                      label: 'Risk Level',
                      value:
                          '${record['infrastructure_risk'] ?? record['risk_level'] ?? record['infrastructure_suitability'] ?? '--'}',
                    ),
                    DetailLine(label: 'Slope', value: _slopeText(record)),
                    DetailLine(
                      label: 'Elevation',
                      value: '${_num(record['elevation_m'], decimals: 1)} m',
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.bookmark_border_rounded, size: 18),
                      label: Text('Save'),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _reporting ? null : _addToReports,
                      icon: _reporting
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(Icons.description_outlined, size: 18),
                      label: Text('Report'),
                    ),
                  ),
                  SizedBox(width: 10),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
