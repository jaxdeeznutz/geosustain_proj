part of '../main.dart';

class HistoryPage extends StatefulWidget {
  final ApiService api;
  final AnalysisState state;
  const HistoryPage({super.key, required this.api, required this.state});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  Future<void> refresh() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await widget.state.refreshHistoryData();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String labelFor(dynamic pct) => suitabilityLabel(pct);

  Color colorFor(String label) {
    if (label.startsWith('HIGH')) return const Color(0xFFDCF5E4);
    if (label.startsWith('MODERATE')) return const Color(0xFFFFE7B8);
    return const Color(0xFFFFD5D5);
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.state.historyRecords
        .map(widget.state.normalizeRecord)
        .toList();
    return SafeArea(
      child: Column(
        children: [
          MobileHeader(
            title: 'Analysis History',
            trailing: IconButton(
              onPressed: loading ? null : refresh,
              icon: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: loading
                        ? const CircularProgressIndicator()
                        : const Text('No analysis history yet.'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => HistoryDetailPage(
                                record: r,
                                state: widget.state,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                LocationHistoryThumb(
                                  lat: r['center_lat'],
                                  lon: r['center_lon'],
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${r['title'] ?? r['place_name'] ?? 'Analyzed Area'}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          VerificationStatusBadge(
                                            status:
                                                '${r['verification_status'] ?? 'pending'}',
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        widget.state.recommendationText(r),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.black54,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 7),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          SmallHistoryAction(
                                            icon: Icons.bookmark_border_rounded,
                                            label: 'Save',
                                            onTap: () async {
                                              final saved = await widget.state
                                                  .saveAnalysisRecord(r);
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    saved
                                                        ? 'Analysis saved.'
                                                        : 'Already saved.',
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                          SmallHistoryAction(
                                            icon: Icons.description_outlined,
                                            label: 'Report',
                                            onTap: () async {
                                              final added = await widget.state
                                                  .createReportRecord(r);
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    added
                                                        ? 'Report added.'
                                                        : 'Report already exists.',
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class HistoryDetailPage extends StatelessWidget {
  final Map<String, dynamic> record;
  final AnalysisState state;
  const HistoryDetailPage({
    super.key,
    required this.record,
    required this.state,
  });

  String _num(dynamic value, {int decimals = 2}) {
    final n = value is num ? value : num.tryParse('$value');
    if (n == null) return '--';
    return n.toStringAsFixed(decimals);
  }

  double _progress(dynamic value, double fallback) {
    final n = value is num ? value : num.tryParse('$value');
    return ((n ?? fallback).clamp(0, 100) / 100).toDouble();
  }

  Map<String, dynamic>? _xai(Map<String, dynamic> item) {
    dynamic raw = item['xai_explanation'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  List<String> _xaiLines(Map<String, dynamic> item) {
    final xai = _xai(item);
    if (xai == null) return const [];
    final lines = <String>[];
    final summary = '${xai['summary'] ?? ''}'.trim();
    if (summary.isNotEmpty) lines.add(summary);
    final supporting = xai['supporting_factors'];
    if (supporting is List) lines.addAll(supporting.map((e) => '$e'));
    final limiting = xai['limiting_factors'];
    if (limiting is List) {
      lines.addAll(limiting.map((e) => 'Limiting factor: $e'));
    }
    final comparison = '${xai['comparison'] ?? ''}'.trim();
    if (comparison.isNotEmpty) lines.add(comparison);
    return lines.where((e) => e.trim().isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final item = state.normalizeRecord(Map<String, dynamic>.from(record));
    final crop = item['predicted_crop'] ?? 'Land Analysis';
    final compatibility = item['compatibility_pct'];
    final suitability = suitabilityLabel(compatibility);
    final lat = item['center_lat'];
    final lon = item['center_lon'];
    final place = item['title'] ?? item['place_name'] ?? 'Analyzed Area';

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            MobileHeader(
              title: 'Analysis Details',
              back: () => Navigator.pop(context),
              trailing: IconButton(
                onPressed: () => generateAnalysisPdf(item, state: state),
                icon: const Icon(Icons.download_outlined),
              ),
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 170,
                    width: double.infinity,
                    child: LocationHistoryThumb(
                      lat: lat,
                      lon: lon,
                      expanded: true,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$place',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: green,
                          ),
                        ),
                        const SizedBox(height: 6),
                        VerificationStatusBadge(
                          status: '${item['verification_status'] ?? 'draft'}',
                        ),
                        if ('${item['verification_status'] ?? ''}' ==
                                'rejected' &&
                            '${item['planner_notes'] ?? ''}'
                                .trim()
                                .isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0F0),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Planner feedback: ${item['planner_notes']}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF8A2C2C),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          state.recommendationText(item),
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$crop',
                          style: const TextStyle(
                            fontSize: 18,
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
                            suitability,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if ('${item['analysis_summary'] ?? ''}'
                            .trim()
                            .isNotEmpty) ...[
                          const Divider(height: 24),
                          const Text(
                            'ANALYSIS SUMMARY',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: green,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            '${item['analysis_summary']}',
                            style: const TextStyle(fontSize: 13, height: 1.45),
                          ),
                        ],
                        const Divider(height: 28),
                        DetailLine(
                          label: 'Suitability Score',
                          value: '${compatibility ?? '--'}%',
                        ),
                        DetailLine(
                          label: 'NDVI',
                          value: _num(item['ndvi'], decimals: 3),
                        ),
                        DetailLine(
                          label: 'Rainfall',
                          value: '${_num(item['rainfall_mm'], decimals: 1)} mm',
                        ),
                        DetailLine(
                          label: 'Temperature',
                          value:
                              '${_num(item['temperature_c'], decimals: 1)} °C',
                        ),
                        DetailLine(
                          label: 'Elevation',
                          value: '${_num(item['elevation_m'], decimals: 1)} m',
                        ),
                        DetailLine(
                          label: 'Soil pH',
                          value: _num(item['soil_ph'], decimals: 2),
                        ),
                        DetailLine(
                          label: 'Nitrogen',
                          value: _num(item['nitrogen'], decimals: 0),
                        ),
                        DetailLine(
                          label: 'Phosphorus',
                          value: _num(item['phosphorus'], decimals: 0),
                        ),
                        DetailLine(
                          label: 'Potassium',
                          value: _num(item['potassium'], decimals: 0),
                        ),
                        DetailLine(
                          label: 'Weather',
                          value: '${item['weather_description'] ?? '--'}',
                        ),
                        const Divider(height: 24),
                        DetailLine(
                          label: 'Infrastructure Suitability',
                          value:
                              '${item['infrastructure_suitability'] ?? '--'}',
                        ),
                        DetailLine(
                          label: 'Infrastructure Score',
                          value: '${item['infrastructure_score'] ?? '--'}',
                        ),
                        DetailLine(
                          label: 'Infrastructure Status',
                          value: '${item['infrastructure_status'] ?? '--'}',
                        ),
                        DetailLine(
                          label: 'Infrastructure Recommendation',
                          value:
                              '${item['infrastructure_recommendation'] ?? '--'}',
                        ),
                        DetailLine(
                          label: 'Slope',
                          value:
                              state.numText(
                                    item['slope_pct'] ?? item['slope'],
                                  ) ==
                                  '--'
                              ? '--'
                              : '${state.numText(item['slope_pct'] ?? item['slope'])}%',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_xaiLines(item).isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.psychology_alt_rounded, color: green),
                          SizedBox(width: 8),
                          Expanded(
                            child: SectionTitle(
                              'EXPLAINABLE AI — WHY THIS CROP?',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._xaiLines(item).map(
                        (line) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.check_circle_rounded,
                                  color: green,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  line,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 18),
                      Text(
                        'Method: ${_xai(item)?['method'] ?? 'Local feature contribution analysis'}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Colors.black54,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SectionTitle('UNDERSTANDING THIS ANALYSIS'),
                    SizedBox(height: 10),
                    Text(
                      'Arable — land that can support crop production under the assessed conditions.',
                    ),
                    SizedBox(height: 6),
                    Text(
                      'NDVI — satellite vegetation index from -1 to 1; higher positive values generally indicate denser vegetation.',
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Suitability — the system’s comparative fit score, not a guarantee of yield.',
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Slope — terrain steepness; the summary describes the dominant condition and localized steep sections.',
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Wet/Dry season — seasonal context used to adjust, but not replace, the environmental ranking.',
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Green: favorable  •  Yellow/Orange: conditional  •  Red: limiting/not suitable',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: green,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle('CHARTS AND ANALYTICS'),
                    const SizedBox(height: 12),
                    DetailBar(
                      label: 'NDVI',
                      value: _progress(
                        (item['ndvi'] is num ? item['ndvi'] * 100 : 0),
                        45,
                      ),
                    ),
                    DetailBar(
                      label: 'Rainfall',
                      value: _progress(
                        (item['rainfall_mm'] is num
                            ? item['rainfall_mm'] / 2
                            : null),
                        70,
                      ),
                    ),
                    DetailBar(
                      label: 'Temp',
                      value: _progress(
                        (item['temperature_c'] is num
                            ? item['temperature_c'] * 2
                            : null),
                        50,
                      ),
                    ),
                    DetailBar(
                      label: 'Soil pH',
                      value: _progress(
                        (item['soil_ph'] is num ? item['soil_ph'] * 12 : null),
                        60,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final saved = await state.saveAnalysisRecord(item);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            saved ? 'Analysis saved.' : 'Already saved.',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.bookmark_border_rounded),
                    label: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final added = await state.createReportRecord(item);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            added ? 'Report added.' : 'Report already exists.',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('Report'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (('${item['verification_status'] ?? 'draft'}' == 'draft') ||
                ('${item['verification_status'] ?? ''}' == 'rejected')) ...[
              FilledButton.icon(
                onPressed: () async {
                  final isResubmission =
                      '${item['verification_status'] ?? 'draft'}' == 'rejected';
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      icon: const Icon(
                        Icons.send_rounded,
                        color: Color(0xFF0B7D49),
                        size: 34,
                      ),
                      title: Text(
                        isResubmission
                            ? 'Resubmit this analysis?'
                            : 'Submit to planner?',
                      ),
                      content: Text(
                        isResubmission
                            ? 'This analyzed land will be returned to the planner for another review. Please make sure the analysis is ready.'
                            : 'The planner will be able to review this analyzed land, its crop recommendation, environmental readings, and Explainable AI details. Continue?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton.icon(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          icon: const Icon(Icons.send_rounded),
                          label: Text(
                            isResubmission ? 'Yes, Resubmit' : 'Yes, Submit',
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true || !context.mounted) return;
                  try {
                    await state.submitAnalysisRecord(item);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Analysis submitted to the planner.'),
                      ),
                    );
                    Navigator.pop(context);
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Could not submit: ${friendlyErrorMessage(e)}',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.send_rounded),
                label: Text(
                  '${item['verification_status'] ?? 'draft'}' == 'rejected'
                      ? 'Resubmit for Analyst Review'
                      : 'Submit for Analyst Review',
                ),
              ),
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
              onPressed: () => generateAnalysisPdf(item, state: state),
              icon: const Icon(Icons.download),
              label: const Text('Download PDF Report'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows whether a planner has reviewed this analyzed land submission yet.
/// Farmers see this on their History cards and detail view; it reflects the
/// `verification_status` field returned by the backend ('pending', 'verified',
/// or 'rejected').
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
      default:
        return const Color(0xFFE9A829);
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
      default:
        return Icons.hourglass_top_rounded;
    }
  }

  String get _label {
    switch (status) {
      case 'verified':
        return 'Verified';
      case 'rejected':
        return 'Rejected';
      case 'draft':
        return 'Not submitted';
      default:
        return 'Pending';
    }
  }

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
          Text(
            _label,
            style: TextStyle(
              color: _color,
              fontWeight: FontWeight.w800,
              fontSize: 10,
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
        pw.Text(
          'Status: ${verificationStatus[0].toUpperCase()}${verificationStatus.substring(1)}',
        ),
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
