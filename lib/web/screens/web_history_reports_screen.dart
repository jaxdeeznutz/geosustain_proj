part of '../../main.dart';

class WebHistoryScreen extends StatelessWidget {
  final AnalysisState state;
  final bool compact;
  const WebHistoryScreen({
    super.key,
    required this.state,
    this.compact = false,
  });

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
    final rows = state.historyRecords.take(compact ? 5 : 20).toList();
    return _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent Analyses',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              if (compact)
                const Text(
                  'View All',
                  style: TextStyle(color: green, fontWeight: FontWeight.w900),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: Text(
                  'No analysis history yet.',
                  style: TextStyle(color: Colors.black45),
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
                  if (state.isPlanner && sessionId != null) {
                    await openPlannerAnalysisReview(context, state, sessionId);
                    return;
                  }
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
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE3ECE5)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: softGreen,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.eco_rounded, color: green),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 22,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${r['place_name'] ?? r['location'] ?? 'Analyzed Area'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${r['date'] ?? r['analyzed_at'] ?? ''}'
                                  .split('T')
                                  .first,
                              style: const TextStyle(
                                color: Colors.black45,
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
                            const Text(
                              'RECOMMENDED CROP',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.black45,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _topCropFromRecord(r),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'SUITABILITY',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.black45,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              pct == null ? '--' : '${pct.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                color: green,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.arrow_forward_rounded, color: green),
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

class WebReportsScreen extends StatelessWidget {
  final AnalysisState state;
  final bool compact;
  const WebReportsScreen({
    super.key,
    required this.state,
    this.compact = false,
  });

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
    final rows = state.generatedReports.take(compact ? 4 : 50).toList();
    return _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent Reports',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              if (compact)
                const Text(
                  'View All',
                  style: TextStyle(color: green, fontWeight: FontWeight.w900),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: Text(
                  'No reports generated yet.',
                  style: TextStyle(color: Colors.black45),
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
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFEBEB),
                  child: Icon(Icons.picture_as_pdf_rounded, color: Colors.red),
                ),
                title: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${item['predicted_crop'] ?? 'Land analysis'} · $date',
                ),
                trailing: IconButton(
                  tooltip: 'Download PDF',
                  icon: const Icon(Icons.download_rounded, color: green),
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
    final compatibility = record['compatibility_pct'] ?? widget.suitabilityPct;
    final suitability = suitabilityLabel(compatibility);
    final infraData = <String, dynamic>{...record};

    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      contentPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: LocationHistoryThumb(lat: lat, lon: lon, expanded: true),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$place',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: green,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      state.recommendationText(record),
                      style: const TextStyle(
                        color: Colors.black54,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      topCrop,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: suitabilityColor(compatibility),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$suitability · ${compatibility == null ? '--' : '${(compatibility is num ? compatibility : num.tryParse('$compatibility'))?.toStringAsFixed(1) ?? compatibility}%'}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Coordinates: $lat, $lon',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                    if (record['date'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Analyzed: ${record['date']}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                    const Divider(height: 28),
                    const Text(
                      'ENVIRONMENTAL DATA',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: green,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 10),
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
                    const Divider(height: 28),
                    const Text(
                      'INFRASTRUCTURE REPORT',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: green,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
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
                          const SizedBox(height: 6),
                          Text(
                            '${record['infrastructure_status'] ?? 'No infrastructure status recorded for this analysis.'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                          if (record['infrastructure_recommendation'] !=
                              null) ...[
                            const SizedBox(height: 6),
                            Text(
                              '${record['infrastructure_recommendation']}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.bookmark_border_rounded, size: 18),
                      label: const Text('Save'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _reporting ? null : _addToReports,
                      icon: _reporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.description_outlined, size: 18),
                      label: const Text('Report'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
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
