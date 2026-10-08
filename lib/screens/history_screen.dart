part of '../main.dart';

class HistoryPage extends StatefulWidget {
  final ApiService api;
  final AnalysisState state;
  final FutureOr<void> Function(Map<String, dynamic>)? onOpenAnalysis;
  final VoidCallback? goFarms;
  const HistoryPage({
    super.key,
    required this.api,
    required this.state,
    this.onOpenAnalysis,
    this.goFarms,
  });
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  bool loading = false;
  bool opening = false;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) refresh();
    });
  }

  Future<void> refresh() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await widget.state.refreshHistoryData();
      if (mounted) error = widget.state.historyError;
    } catch (e) {
      error = friendlyErrorMessage(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> open(Map<String, dynamic> record) async {
    if (opening) return;
    setState(() => opening = true);
    try {
      if (widget.onOpenAnalysis != null) {
        await widget.onOpenAnalysis!(record);
      } else {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                HistoryDetailPage(record: record, state: widget.state),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final rows = newestAnalysisRecords(widget.state.historyRecords);
      return SafeArea(
        child: Column(
          children: [
            MobileHeader(
              title: 'History',
              trailing: IconButton(
                tooltip: 'Refresh analyses and analyst decisions',
                onPressed: loading ? null : refresh,
                icon: const Icon(Icons.refresh),
              ),
            ),
            if (loading || opening) const LinearProgressIndicator(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: refresh,
                child: ListView(
                  key: const PageStorageKey('mobile-history-scroll'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Previous analyses and their separate analyst review status. Pull down to refresh.',
                      ),
                    ),
                    if (error != null || widget.state.historyError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          error ?? widget.state.historyError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (rows.isEmpty && !loading) ...[
                      const SizedBox(height: 32),
                      const Icon(Icons.history, size: 54, color: green),
                      const SizedBox(height: 16),
                      const Text(
                        'No analyses yet',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Create a boundary or draw an area in My Farms, then analyze it. Saving a farm alone does not create an analysis.',
                        textAlign: TextAlign.center,
                      ),
                      if (widget.goFarms != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: FilledButton.icon(
                            onPressed: widget.goFarms,
                            icon: const Icon(Icons.agriculture),
                            label: const Text('Go to My Farms'),
                          ),
                        ),
                    ],
                    for (final row in rows)
                      Card(
                        key: ValueKey('history-${row['session_id']}'),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: opening ? null : () => open(row),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        analysisRecordName(row),
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  analysisDateText(analysisRecordDate(row)),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(analysisAreaText(row)),
                                const SizedBox(height: 10),
                                Text(
                                  'Analysis: ${analysisProcessingLabel(row)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                VerificationStatusBadge(
                                  status:
                                      '${row['verification_status'] ?? 'draft'}',
                                ),
                                if (row['verified_at'] != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Reviewed: ${analysisDateText(row['verified_at'])}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                                if ('${row['planner_notes'] ?? ''}'
                                    .trim()
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Analyst feedback: ${row['planner_notes']}',
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 12),
                                const Text(
                                  'View full result and feedback',
                                  style: TextStyle(
                                    color: green,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Keeps the existing standalone detail route usable while mobile History
/// normally opens the exact selected analysis in the Analysis tab.
class HistoryDetailPage extends StatefulWidget {
  final Map<String, dynamic> record;
  final AnalysisState state;
  const HistoryDetailPage({
    super.key,
    required this.record,
    required this.state,
  });
  @override
  State<HistoryDetailPage> createState() => _HistoryDetailPageState();
}

class _HistoryDetailPageState extends State<HistoryDetailPage> {
  bool loading = true;
  String? error;
  Map<String, dynamic>? detail;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load();
    });
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final failure = await widget.state.selectAnalysis(widget.record);
      if (!mounted) return;
      error = failure;
      if (failure == null) detail = widget.state.result;
    } catch (e) {
      error = friendlyErrorMessage(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Analysis details')),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: widget.state,
        builder: (context, _) {
          final selected =
              '${widget.state.result?['session_id']}' ==
                  '${widget.record['session_id']}'
              ? widget.state.result
              : detail;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (loading) const LinearProgressIndicator(),
              if (error != null) ...[
                Text(error!),
                TextButton(onPressed: load, child: const Text('Retry')),
              ],
              if (selected != null && !loading)
                MobileAnalysisResult(state: widget.state, record: selected),
            ],
          );
        },
      ),
    ),
  );
}

class VerificationStatusBadge extends StatelessWidget {
  final String status;
  const VerificationStatusBadge({super.key, required this.status});

  Color get _color {
    switch (status) {
      case 'verified':
        return const Color(0xFF1FA463);
      case 'rejected':
        return const Color(0xFFE45B5B);
      case 'draft':
        return const Color(0xFF667085);
      case 'pending':
        return const Color(0xFF805700);
      default:
        return const Color(0xFF667085);
    }
  }

  IconData get _icon {
    switch (status) {
      case 'verified':
        return Icons.verified_rounded;
      case 'rejected':
        return Icons.report_gmailerrorred_rounded;
      case 'draft':
        return Icons.edit_note_rounded;
      case 'pending':
        return Icons.hourglass_top_rounded;
      default:
        return Icons.help_outline;
    }
  }

  String get _label => analysisReviewLabel(status);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 12, color: _color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              _label,
              style: TextStyle(
                color: _color,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SmallHistoryAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const SmallHistoryAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: softGreen,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: green),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                color: green,
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> generateAnalysisPdf(
  Map<String, dynamic> raw, {
  AnalysisState? state,
}) async {
  final data = Map<String, dynamic>.from(raw);
  final location = state != null
      ? await state.resolvePlaceForRecord(data)
      : (data['place_name'] ?? data['title'] ?? 'Unknown location').toString();
  data['place_name'] = location;
  final lat = data['center_lat'] ?? data['lat'] ?? '--';
  final lon = data['center_lon'] ?? data['lon'] ?? '--';
  final crop = data['predicted_crop'] ?? 'Land Analysis';
  final compatibility =
      data['crop_compatibility_pct'] ?? data['compatibility_pct'] ?? '--';
  final recommendation =
      state?.recommendationText(data) ??
      (data['recommendation_title'] ??
          data['subtitle'] ??
          'Land suitability analysis');
  dynamic rawAlternatives = data['alternative_crops'];
  dynamic rawTop = data['top_crop_recommendations'];
  if (rawAlternatives is String && rawAlternatives.trim().isNotEmpty) {
    try {
      rawAlternatives = jsonDecode(rawAlternatives);
    } catch (_) {}
  }
  if (rawTop is String && rawTop.trim().isNotEmpty) {
    try {
      rawTop = jsonDecode(rawTop);
    } catch (_) {}
  }
  final List<dynamic> alternatives =
      rawAlternatives is List && rawAlternatives.isNotEmpty
      ? rawAlternatives
      : (rawTop is List && rawTop.length > 1 ? rawTop.skip(1).toList() : []);

  // --- Section 25 fields: farm identity/area, planting month, XAI,
  // verification status, and data-quality caveats. ---
  final farmName = data['farm_name'];
  final areaHectares = data['area_hectares'];
  const monthNames = [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final plantingMonthRaw =
      data['intended_planting_month'] ?? data['planting_month'];
  final plantingMonthIdx = plantingMonthRaw is num
      ? plantingMonthRaw.toInt()
      : int.tryParse('$plantingMonthRaw');
  final plantingMonth =
      (plantingMonthIdx != null &&
          plantingMonthIdx >= 1 &&
          plantingMonthIdx <= 12)
      ? monthNames[plantingMonthIdx]
      : null;

  dynamic rawXai = data['xai_explanation'];
  if (rawXai is String && rawXai.trim().isNotEmpty) {
    try {
      rawXai = jsonDecode(rawXai);
    } catch (_) {}
  }
  final Map xai = rawXai is Map ? rawXai : const {};
  final supportingFactors = (xai['supporting_factors'] is List)
      ? List.from(xai['supporting_factors'])
      : const [];
  final limitingFactors = (xai['limiting_factors'] is List)
      ? List.from(xai['limiting_factors'])
      : const [];

  final verificationStatus = (data['verification_status'] ?? 'draft')
      .toString();
  final plannerNotes = data['planner_notes'];
  final verifiedAt = data['verified_at'];

  dynamic rawQuality = data['data_quality_warnings'];
  if (rawQuality is String && rawQuality.trim().isNotEmpty) {
    try {
      rawQuality = jsonDecode(rawQuality);
    } catch (_) {}
  }
  final List<dynamic> qualityWarnings = rawQuality is List
      ? rawQuality
      : const [];

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      build: (context) => [
        pw.Text(
          'GeoSustain Analysis Report',
          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 12),
        if (farmName != null)
          pw.Text(
            'Farm: $farmName',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        pw.Text('Location: $location'),
        pw.Text('Analyzed: ${analysisDateText(analysisRecordDate(data))}'),
        pw.Text('Coordinates: $lat, $lon'),
        if (areaHectares != null)
          pw.Text(
            'Approximate area: ${(areaHectares is num ? areaHectares.toStringAsFixed(3) : areaHectares)} hectares (agricultural estimate, not a cadastral survey)',
          ),
        if (plantingMonth != null)
          pw.Text('Selected planting month: $plantingMonth'),
        pw.SizedBox(height: 6),
        pw.Text('Recommendation: $recommendation'),
        pw.Text('Crop Recommendation: $crop'),
        pw.Text('Suitability Score: $compatibility%'),
        pw.Text('Suitability: ${suitabilityLabel(compatibility)}'),
        if (alternatives.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text(
            'Other Suitable Crops:',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: ['Rank', 'Crop', 'Suitability'],
            data: alternatives.take(5).toList().asMap().entries.map((entry) {
              final item = entry.value;
              final altCrop = item is Map
                  ? (item['crop'] ?? item['name'] ?? '--')
                  : '$item';
              final altPct = item is Map
                  ? (item['compatibility_pct'] ??
                        item['score'] ??
                        item['compatibility'] ??
                        '--')
                  : '--';
              return ['${entry.key + 2}', '$altCrop', '$altPct%'];
            }).toList(),
          ),
        ],
        pw.SizedBox(height: 8),
        pw.Text(
          'Infrastructure Suitability: ${data['infrastructure_suitability'] ?? '--'}',
        ),
        pw.Text(
          'Infrastructure Score: ${data['infrastructure_score'] ?? '--'}',
        ),
        pw.Text(
          'Infrastructure Note: ${data['infrastructure_status'] ?? '--'}',
        ),
        pw.Text(
          'Infrastructure Recommendation: ${data['infrastructure_recommendation'] ?? '--'}',
        ),
        pw.Text('Slope: ${data['slope_pct'] ?? data['slope'] ?? '--'}%'),
        pw.Divider(),
        pw.Text('NDVI: ${data['ndvi'] ?? '--'}'),
        pw.Text('Rainfall: ${data['rainfall_mm'] ?? '--'} mm'),
        pw.Text('Temperature: ${data['temperature_c'] ?? '--'} °C'),
        pw.Text('Elevation: ${data['elevation_m'] ?? '--'} m'),
        pw.Text('Soil pH: ${data['soil_ph'] ?? '--'}'),
        pw.Text('Nitrogen: ${data['nitrogen'] ?? '--'}'),
        pw.Text(
          'Phosphorus: ${data['phosphorus'] ?? '--'} (estimated from proxies, not a direct soil test)',
        ),
        pw.Text(
          'Potassium: ${data['potassium'] ?? '--'} (estimated from proxies, not a direct soil test)',
        ),
        if (qualityWarnings.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.orange200),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Data quality notes:',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
                for (final w in qualityWarnings)
                  pw.Text('• $w', style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
        ],
        if (xai['summary'] != null) ...[
          pw.SizedBox(height: 14),
          pw.Text(
            'Why this recommendation (explainability)',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
          ),
          pw.SizedBox(height: 4),
          pw.Text('${xai['summary']}', style: const pw.TextStyle(fontSize: 10)),
          if (supportingFactors.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              'Supporting factors:',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            ),
            for (final f in supportingFactors)
              pw.Text('• $f', style: const pw.TextStyle(fontSize: 9)),
          ],
          if (limitingFactors.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              'Limiting factors:',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            ),
            for (final f in limitingFactors)
              pw.Text('• $f', style: const pw.TextStyle(fontSize: 9)),
          ],
          if ('${xai['comparison'] ?? ''}'.trim().isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              '${xai['comparison']}',
              style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic),
            ),
          ],
        ],
        pw.SizedBox(height: 14),
        pw.Text(
          'Verification status',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
        ),
        pw.SizedBox(height: 4),
        pw.Text('Status: ${analysisReviewLabel(verificationStatus)}'),
        if (verifiedAt != null) pw.Text('Reviewed: $verifiedAt'),
        if (plannerNotes != null && '$plannerNotes'.trim().isNotEmpty)
          pw.Text('Analyst notes: $plannerNotes'),
        pw.SizedBox(height: 18),
        pw.Divider(),
        pw.Text(
          'This report is an AI-assisted agricultural estimate generated from satellite, weather, and soil-proxy data. '
          'It is not a certified soil test, a cadastral or legal land survey, or a guarantee of crop performance. '
          'Farmers and planners should use it as a decision-support reference alongside on-site verification and local agricultural extension guidance.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Generated by GeoSustain mobile/web application.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    ),
  );
  await Printing.sharePdf(
    bytes: await doc.save(),
    filename: 'geosustain_analysis_report.pdf',
  );
}

class DetailLine extends StatelessWidget {
  final String label;
  final String value;
  const DetailLine({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
            child: Text(
              label,
              style: const TextStyle(color: Colors.black54),
              softWrap: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              softWrap: true,
              overflow: TextOverflow.visible,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class DetailBar extends StatelessWidget {
  final String label;
  final double value;
  const DetailBar({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 12,
                backgroundColor: const Color(0xFFE9EEE9),
                color: green,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(value * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
