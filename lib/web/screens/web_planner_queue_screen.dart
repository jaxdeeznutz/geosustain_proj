part of '../../main.dart';

Future<void> openPlannerAnalysisReview(
  BuildContext context,
  AnalysisState state,
  int sessionId,
) async {
  try {
    // Load the complete record before opening the route. This avoids the
    // zero-size temporary dialog that previously left only the dark barrier.
    final detail = await state.loadPlannerSessionDetail(sessionId);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.black.withValues(alpha: .62),
      builder: (_) => _PlannerReviewDialog(state: state, row: detail),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open analysis details: $e')),
    );
  }
}

class WebPlannerQueueScreen extends StatefulWidget {
  final AnalysisState state;
  const WebPlannerQueueScreen({super.key, required this.state});

  @override
  State<WebPlannerQueueScreen> createState() => _WebPlannerQueueScreenState();
}

class _WebPlannerQueueScreenState extends State<WebPlannerQueueScreen> {
  AnalysisState get state => widget.state;
  bool _loadedOnce = false;
  int _page = 0;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final err = await state.loadPlannerQueue();
    _loadedOnce = true;
    if (mounted && err != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load queue: $err')));
    }
  }

  Future<void> _openReview(Map<String, dynamic> row) async {
    final normalized = state.normalizeRecord(Map<String, dynamic>.from(row));
    final rawSessionId = normalized['session_id'] ?? normalized['id'];
    final sessionId = rawSessionId is num
        ? rawSessionId.toInt()
        : int.tryParse('$rawSessionId');

    if (sessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('This record has no valid session ID.')),
      );
      return;
    }

    await openPlannerAnalysisReview(context, state, sessionId);
  }

  @override
  Widget build(BuildContext context) {
    final counts = state.plannerCounts;
    final filtered = state.plannerQueue
        .where(
          (r) => '${r['session_id']} ${r['farmer_name']} ${r['place_name']}'
              .toLowerCase()
              .contains(_query.toLowerCase()),
        )
        .toList();
    final maxPage = filtered.isEmpty ? 0 : (filtered.length - 1) ~/ 50;
    if (_page > maxPage) _page = maxPage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _WebKpiCard(
                icon: Icons.hourglass_top_rounded,
                title: 'Pending Review',
                value: '${counts['pending_count'] ?? 0}',
                subtitle: 'Awaiting your decision',
              ),
            ),
            SizedBox(width: 18),
            Expanded(
              child: _WebKpiCard(
                icon: Icons.check_circle_rounded,
                title: 'Verified',
                value: '${counts['verified_count'] ?? 0}',
                subtitle: 'Approved land analyses',
              ),
            ),
            SizedBox(width: 18),
            Expanded(
              child: _WebKpiCard(
                icon: Icons.cancel_rounded,
                title: 'Rejected',
                value: '${counts['rejected_count'] ?? 0}',
                subtitle: 'Returned to farmers',
              ),
            ),
          ],
        ),
        SizedBox(height: 20),
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Submitted Land Verification',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Open a submission to review the complete parcel analysis.',
                          style: TextStyle(color: WebPortalColors.muted),
                        ),
                      ],
                    ),
                  ),
                  for (final item in [
                    ('Pending', 'pending'),
                    ('Verified', 'verified'),
                    ('Rejected', 'rejected'),
                    ('All', 'all'),
                  ]) ...[
                    _StatusFilterChip(
                      label: item.$1,
                      value: item.$2,
                      current: state.plannerQueueStatus,
                      onSelect: (v) => state.loadPlannerQueue(status: v),
                    ),
                    SizedBox(width: 8),
                  ],
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _refresh,
                    icon: Icon(
                      Icons.refresh_rounded,
                      color: WebPortalColors.accent,
                    ),
                  ),
                ],
              ),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Search all submissions',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() {
                  _query = value;
                  _page = 0;
                }),
              ),
              Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${filtered.length} submissions · Page ${_page + 1}'),
                  TextButton(
                    onPressed: _page > 0 ? () => setState(() => _page--) : null,
                    child: Text('Previous'),
                  ),
                  TextButton(
                    onPressed: _page < maxPage
                        ? () => setState(() => _page++)
                        : null,
                    child: Text('Next'),
                  ),
                ],
              ),
              SizedBox(height: 18),
              if (state.plannerQueueLoading && !_loadedOnce)
                Padding(
                  padding: EdgeInsets.all(44),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: WebPortalColors.accent,
                    ),
                  ),
                )
              else if (state.plannerQueue.isEmpty)
                Padding(
                  padding: EdgeInsets.all(42),
                  child: Center(
                    child: Text(
                      'No submissions found.',
                      style: TextStyle(color: WebPortalColors.muted),
                    ),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, c) {
                    final width = (c.maxWidth - 16) / 2;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: filtered
                          .skip(_page * 50)
                          .take(50)
                          .map(
                            (r) => SizedBox(
                              width: width,
                              child: _PlannerQueueCard(
                                row: r,
                                onTap: () => _openReview(r),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlannerReviewLoader extends StatefulWidget {
  final AnalysisState state;
  final int sessionId;

  const _PlannerReviewLoader({required this.state, required this.sessionId});

  @override
  State<_PlannerReviewLoader> createState() => _PlannerReviewLoaderState();
}

class _PlannerReviewLoaderState extends State<_PlannerReviewLoader> {
  late final Future<Map<String, dynamic>> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = widget.state.loadPlannerSessionDetail(widget.sessionId);
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final width = viewport.width > 1248
        ? 1200.0
        : (viewport.width - 48).clamp(320.0, 1200.0).toDouble();
    final height = viewport.height > 898
        ? 850.0
        : (viewport.height - 48).clamp(420.0, 850.0).toDouble();

    return FutureBuilder<Map<String, dynamic>>(
      future: _detailFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Dialog(
            insetPadding: EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: SizedBox(
              width: 420,
              height: 220,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: WebPortalColors.accent),
                  SizedBox(height: 18),
                  Text(
                    'Loading complete land analysis...',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Dialog(
            insetPadding: EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: SizedBox(
              width: 520,
              child: Padding(
                padding: EdgeInsets.all(26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFE45B5B),
                      size: 46,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Could not open analysis review',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '${snapshot.error ?? 'No detail was returned.'}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: WebPortalColors.muted),
                    ),
                    SizedBox(height: 18),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Close'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Dialog(
          insetPadding: EdgeInsets.all(24),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: SizedBox(
            width: width,
            height: height,
            child: _PlannerReviewDialog(
              state: widget.state,
              row: snapshot.data!,
              embedded: true,
            ),
          ),
        );
      },
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  final String label, value, current;
  final ValueChanged<String> onSelect;
  const _StatusFilterChip({
    required this.label,
    required this.value,
    required this.current,
    required this.onSelect,
  });
  @override
  Widget build(BuildContext context) {
    final selected = current == value;
    return InkWell(
      onTap: () => onSelect(value),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? green : softGreen,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : green,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _PlannerQueueCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onTap;
  const _PlannerQueueCard({required this.row, required this.onTap});

  double? _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');
  Color _statusColor(String s) => s == 'verified'
      ? Color(0xFF1FA463)
      : s == 'rejected'
      ? Color(0xFFE45B5B)
      : Color(0xFFE9A829);

  @override
  Widget build(BuildContext context) {
    final status = '${row['verification_status'] ?? 'pending'}';
    final crop =
        '${row['predicted_crop'] ?? row['recommendation_title'] ?? 'No crop'}';
    final score = _n(row['compatibility_pct']);
    final place = '${row['place_name'] ?? 'Unnamed field'}';
    final farmer = '${row['farmer_name'] ?? 'Unknown farmer'}';
    final date = '${row['analyzed_at'] ?? ''}'.split('T').first;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: WebPortalColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Color(0xFFE3ECE5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .035),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: WebPortalColors.tint,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.eco_rounded,
                      color: WebPortalColors.accent,
                      size: 27,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          place,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Submitted by $farmer',
                          style: TextStyle(
                            color: WebPortalColors.muted,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _SmallBadge(
                    status[0].toUpperCase() + status.substring(1),
                    color: _statusColor(status),
                  ),
                ],
              ),
              SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _CardFact(label: 'RECOMMENDED CROP', value: crop),
                  ),
                  Expanded(
                    child: _CardFact(
                      label: 'SUITABILITY',
                      value: score == null
                          ? '--'
                          : '${score.toStringAsFixed(1)}%',
                      valueColor: green,
                    ),
                  ),
                  Expanded(
                    child: _CardFact(
                      label: 'ANALYZED',
                      value: date.isEmpty ? '--' : date,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.touch_app_rounded,
                    size: 17,
                    color: WebPortalColors.accent,
                  ),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Open complete analysis review',
                      style: TextStyle(
                        color: WebPortalColors.accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: WebPortalColors.accent.withValues(alpha: .8),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardFact extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  const _CardFact({required this.label, required this.value, this.valueColor});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          color: WebPortalColors.muted,
          fontWeight: FontWeight.w900,
          letterSpacing: .4,
        ),
      ),
      SizedBox(height: 5),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w900,
          color: valueColor,
        ),
      ),
    ],
  );
}

class _PlannerReviewDialog extends StatefulWidget {
  final AnalysisState state;
  final Map<String, dynamic> row;
  final bool embedded;
  const _PlannerReviewDialog({
    required this.state,
    required this.row,
    this.embedded = false,
  });
  @override
  State<_PlannerReviewDialog> createState() => _PlannerReviewDialogState();
}

class _PlannerReviewDialogState extends State<_PlannerReviewDialog> {
  final notes = TextEditingController();
  String layer = 'NDVI';
  bool saving = false;

  Map<String, dynamic> get r => widget.row;
  double? n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');
  List<dynamic> list(dynamic v) => v is List ? v : [];

  @override
  void initState() {
    super.initState();
    notes.text = '${r['planner_notes'] ?? ''}';
  }

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  LatLng? _polygonPoint(dynamic raw) {
    if (raw is Map) {
      final lat = n(raw['lat'] ?? raw['latitude']);
      final lng = n(raw['lng'] ?? raw['lon'] ?? raw['longitude']);
      if (lat != null && lng != null) return LatLng(lat, lng);
    }
    if (raw is List && raw.length >= 2) {
      final first = n(raw[0]);
      final second = n(raw[1]);
      if (first != null && second != null) return LatLng(first, second);
    }
    return null;
  }

  List<LatLng> get polygon => list(
    r['selected_polygon'],
  ).map(_polygonPoint).whereType<LatLng>().toList();
  List<Map<String, dynamic>> get grid => list(
    r['heatmap_grid'],
  ).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  LatLng get parcelCenter {
    final points = polygon;
    if (points.length >= 3) {
      final lat =
          points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
      final lng =
          points.map((p) => p.longitude).reduce((a, b) => a + b) /
          points.length;
      return LatLng(lat, lng);
    }
    return LatLng(
      n(r['center_lat']) ?? panaboCenter.latitude,
      n(r['center_lon']) ?? panaboCenter.longitude,
    );
  }

  String keyForLayer() => {
    'NDVI': 'ndvi',
    'Suitability': 'crop_suitability',
    'Soil pH': 'soil_ph',
    'Rainfall': 'rainfall',
    'Elevation': 'elevation',
    'Slope': 'slope',
  }[layer]!;
  Color heatColor(double value, List<double> values) {
    if (values.isEmpty) return green;
    final minV = values.reduce((a, b) => a < b ? a : b),
        maxV = values.reduce((a, b) => a > b ? a : b);
    final t = maxV == minV ? .75 : ((value - minV) / (maxV - minV)).clamp(0, 1);
    if (t >= .75) return Color(0xFF16A765);
    if (t >= .5) return Color(0xFF8BD450);
    if (t >= .25) return Color(0xFFF0AA20);
    return Color(0xFFE95B55);
  }

  Future<void> decide(String status) async {
    if (status == 'rejected' && notes.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Add a rejection reason in Planning Analyst Notes first.',
          ),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          status == 'verified'
              ? 'Verify this land analysis?'
              : 'Reject this land analysis?',
        ),
        content: Text(
          status == 'verified'
              ? 'The farmer will see this result as verified.'
              : 'The farmer will receive your planner note and can review the analysis.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: status == 'verified' ? green : Color(0xFFE45B5B),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(status == 'verified' ? 'Verify' : 'Reject'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => saving = true);
    final id = (r['session_id'] as num?)?.toInt();
    final err = id == null
        ? 'Missing session ID'
        : await widget.state.verifyPlannerSubmission(
            id,
            status,
            notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
          );
    if (!mounted) return;
    setState(() => saving = false);
    if (err == null) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawCropFlag = r['is_crop_recommended'];
    final isCrop = rawCropFlag is bool
        ? rawCropFlag
        : !['false', '0'].contains('$rawCropFlag'.trim().toLowerCase()) &&
              '${r['land_type'] ?? 'arable'}'.trim().toLowerCase() == 'arable';
    final crop = isCrop
        ? '${r['predicted_crop'] ?? 'No crop'}'
        : '${r['land_status'] ?? r['recommendation_title'] ?? 'Land assessment'}';
    final status = '${r['verification_status'] ?? 'pending'}';
    final score = n(r['compatibility_pct']);
    final center = parcelCenter;
    final values = grid
        .map((e) => n(e[keyForLayer()]))
        .whereType<double>()
        .toList();
    final xai = r['xai_explanation'] is Map
        ? Map<String, dynamic>.from(r['xai_explanation'])
        : <String, dynamic>{};
    final bullets = <String>[
      if ('${xai['summary'] ?? ''}'.trim().isNotEmpty) '${xai['summary']}',
      ...list(xai['supporting_factors']).take(2).map((e) => '$e'),
      if (list(xai['limiting_factors']).isNotEmpty)
        '${list(xai['limiting_factors']).first}',
      if ('${xai['planning_advice'] ?? ''}'.trim().isNotEmpty)
        '${xai['planning_advice']}',
    ].take(isCrop ? 3 : 4).toList();
    if (!isCrop && bullets.isEmpty) {
      final ndvi = n(r['ndvi']);
      bullets.add(
        'A complete crop recommendation is unavailable. Review coverage and source quality below.',
      );
      if (ndvi != null) {
        bullets.add(
          'The measured NDVI is ${ndvi.toStringAsFixed(3)}, indicating limited vegetation or a non-arable surface.',
        );
      }
      final infra = '${r['infrastructure_recommendation'] ?? ''}'.trim();
      bullets.add(
        infra.isNotEmpty
            ? infra
            : 'Review zoning, drainage, land conversion, environmental constraints, and field conditions before agricultural use.',
      );
    }
    final alts = list(r['alternative_crops']);

    final ownerEmail = '${r['farmer_email'] ?? r['owner_email'] ?? ''}'
        .trim()
        .toLowerCase();
    final currentRoleRaw =
        '${widget.state.currentUser?['role'] ?? widget.state.currentUser?['account_type'] ?? 'analyst'}'
            .toLowerCase();
    final currentRoleLabel =
        (currentRoleRaw == 'analyst' || currentRoleRaw == 'planner')
        ? 'Agricultural Planning Analyst'
        : 'Farmer';
    final ownerRoleRaw = '${r['farmer_role'] ?? r['owner_role'] ?? ''}'
        .trim()
        .toLowerCase();
    final isFarmerSubmission = ownerRoleRaw == 'farmer' && status != 'draft';
    final ownerTitle = isFarmerSubmission ? 'Submitted by' : 'Analysis Owner';
    final ownerRoleLabel = isFarmerSubmission ? 'Farmer' : currentRoleLabel;
    final ownerName = '${r['farmer_name'] ?? r['owner_name'] ?? 'Unknown'}';

    final viewport = MediaQuery.sizeOf(context);
    final dialogWidth = viewport.width > 1248 ? 1200.0 : viewport.width - 48.0;
    final dialogHeight = viewport.height > 898 ? 850.0 : viewport.height - 48.0;

    final content = SizedBox(
      width: dialogWidth,
      height: dialogHeight,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(22, 16, 12, 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: WebPortalColors.tint,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.fact_check_outlined,
                    color: WebPortalColors.accent,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Analysis Review',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                SizedBox(width: 12),
                _SmallBadge(
                  status == 'pending'
                      ? 'Pending Review'
                      : status[0].toUpperCase() + status.substring(1),
                  color: status == 'verified'
                      ? Color(0xFF1FA463)
                      : status == 'rejected'
                      ? Color(0xFFE45B5B)
                      : Color(0xFFE9A829),
                ),
                Spacer(),
                IconButton(
                  tooltip: 'Close analysis review',
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  // Compact two-column hero: square map on the left, summary on the right.
                  AnalysisCoverageCard(record: r),
                  CagroSoilObservationsCard(record: r),
                  ModelExplanationCard(record: r),
                  if (r['analysis_schema_version'] != null) ...[
                    Text('AI Crop Ranking — Model scores'),
                    for (final raw in analysisListValue(
                      r['top_crop_recommendations'],
                    ).take(5))
                      Text(
                        '${analysisMapValue(raw)['crop']}: ${analysisMapValue(raw)['compatibility_pct']}% Model score',
                      ),
                    Text('Environmental & Soil Reference Assessment'),
                    for (final factor in environmentalFactorViews(
                      analysisMapValue(
                        analysisListValue(
                          r['top_crop_recommendations'],
                        ).firstOrNull,
                      ),
                      r,
                    ))
                      EnvironmentalFactorCard(factor: factor),
                    for (final warning in analysisListValue(
                      r['data_quality_warnings'],
                    ))
                      Text('$warning'),
                  ],
                  SizedBox(
                    height: 320,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 5,
                          child: _PlannerMapPreview(
                            height: 320,
                            center: center,
                            polygon: polygon,
                            grid: grid,
                            valueKey: keyForLayer(),
                            values: values,
                            heatColor: heatColor,
                            selectedLayer: layer,
                            onLayerChanged: (value) =>
                                setState(() => layer = value),
                          ),
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          flex: 5,
                          child: _ReviewSection(
                            title: 'Land Analysis Summary',
                            icon: Icons.assignment_outlined,
                            child: LayoutBuilder(
                              builder: (context, c) {
                                final gap = 10.0;
                                final cellWidth = (c.maxWidth - gap) / 2;
                                return SingleChildScrollView(
                                  child: Wrap(
                                    spacing: gap,
                                    runSpacing: gap,
                                    children: [
                                      SizedBox(
                                        width: cellWidth,
                                        child: _SummaryFact(
                                          icon: isCrop
                                              ? Icons.eco_outlined
                                              : Icons.landscape_outlined,
                                          label: isCrop
                                              ? 'Recommended Crop'
                                              : 'Land Assessment',
                                          value: crop,
                                        ),
                                      ),
                                      SizedBox(
                                        width: cellWidth,
                                        child: _SummaryFact(
                                          icon:
                                              Icons.workspace_premium_outlined,
                                          label: isCrop
                                              ? (isModelRanked(r)
                                                    ? 'Model score'
                                                    : 'Recorded score')
                                              : 'Agricultural Use',
                                          value: isCrop
                                              ? (score == null
                                                    ? '--'
                                                    : '${score.toStringAsFixed(1)}%')
                                              : 'Not assessed',
                                          caption: isCrop
                                              ? (isModelRanked(r)
                                                    ? 'AI Crop Ranking'
                                                    : 'Recorded model score')
                                              : '${r['recommendation_title'] ?? ''}',
                                        ),
                                      ),
                                      SizedBox(
                                        width: cellWidth,
                                        child: _SummaryFact(
                                          icon: Icons.person_outline,
                                          label: ownerTitle,
                                          value: ownerName,
                                          caption:
                                              '$ownerRoleLabel${ownerEmail.isNotEmpty ? ' • $ownerEmail' : ''}',
                                        ),
                                      ),
                                      SizedBox(
                                        width: cellWidth,
                                        child: _SummaryFact(
                                          icon: Icons.place_outlined,
                                          label: 'Location',
                                          value:
                                              '${r['place_name'] ?? 'Unnamed field'}',
                                        ),
                                      ),
                                      SizedBox(
                                        width: cellWidth,
                                        child: _SummaryFact(
                                          icon: Icons.calendar_today_outlined,
                                          label: 'Date Analyzed',
                                          value: '${r['analyzed_at'] ?? ''}'
                                              .split('T')
                                              .first,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 14),
                  if (r['analysis_schema_version'] == null)
                    _ReviewSection(
                      title: 'Environmental & Soil Data',
                      icon: Icons.eco_outlined,
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final gap = 10.0;
                          final itemWidth = (c.maxWidth - gap * 4) / 5;
                          bool isEst(String key) {
                            final dq = r['data_quality'];
                            if (dq is! Map) return false;
                            final entry = dq[key];
                            if (entry is! Map) return false;
                            final q =
                                '${entry['overall_quality'] ?? entry['quality'] ?? ''}';
                            return q != 'measured' && q.isNotEmpty;
                          }

                          final items = <Widget>[
                            _MetricBox(
                              'NDVI',
                              r['ndvi'],
                              Icons.insights_rounded,
                              decimals: 3,
                              estimated: isEst('ndvi'),
                            ),
                            _MetricBox(
                              'Rainfall',
                              r['rainfall_mm'],
                              Icons.water_drop_outlined,
                              suffix: ' mm',
                              decimals: 1,
                              estimated: isEst('rainfall'),
                            ),
                            _MetricBox(
                              'Temperature',
                              r['temperature_c'],
                              Icons.thermostat_rounded,
                              suffix: ' °C',
                              decimals: 1,
                              estimated: isEst('temperature'),
                            ),
                            _MetricBox(
                              'Elevation',
                              r['elevation_m'],
                              Icons.terrain_rounded,
                              suffix: ' m',
                              decimals: 1,
                              estimated: isEst('elevation'),
                            ),
                            _MetricBox(
                              'Soil pH',
                              r['soil_ph'],
                              Icons.science_outlined,
                              decimals: 2,
                              estimated: isEst('soil_ph'),
                            ),
                            _MetricBox(
                              'Humidity',
                              r['live_humidity'],
                              Icons.opacity_rounded,
                              suffix: '%',
                              decimals: 1,
                              estimated: isEst('humidity'),
                            ),
                            _MetricBox(
                              'Nitrogen',
                              r['nitrogen'],
                              Icons.grass_rounded,
                              decimals: 0,
                              estimated: isEst('nitrogen'),
                            ),
                            _MetricBox(
                              'Phosphorus',
                              r['phosphorus'],
                              Icons.grain_rounded,
                              decimals: 0,
                              estimated: true,
                            ),
                            _MetricBox(
                              'Potassium',
                              r['potassium'],
                              Icons.spa_outlined,
                              decimals: 0,
                              estimated: true,
                            ),
                            _MetricBox(
                              'Slope',
                              r['slope_pct'],
                              Icons.show_chart_rounded,
                              suffix: '%',
                              decimals: 1,
                            ),
                          ];
                          return Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: items
                                .map(
                                  (item) =>
                                      SizedBox(width: itemWidth, child: item),
                                )
                                .toList(),
                          );
                        },
                      ),
                    ),
                  SizedBox(height: 14),
                  SizedBox(
                    height: 270,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: isFarmerSubmission ? 6 : 7,
                          child: _ReviewSection(
                            title: isCrop
                                ? 'Explainable AI — Why $crop?'
                                : 'Why was crop recommendation stopped?',
                            icon: Icons.auto_awesome_outlined,
                            child: bullets.isEmpty
                                ? Text(
                                    'No explanation stored for this older analysis.',
                                    style: TextStyle(
                                      color: WebPortalColors.muted,
                                    ),
                                  )
                                : SingleChildScrollView(
                                    child: Column(
                                      children: bullets
                                          .map(
                                            (b) => Padding(
                                              padding: EdgeInsets.only(
                                                bottom: 9,
                                              ),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Icon(
                                                    Icons.check_circle_rounded,
                                                    color:
                                                        WebPortalColors.accent,
                                                    size: 17,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      b,
                                                      style: TextStyle(
                                                        height: 1.35,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                          ),
                        ),
                        if (isCrop) ...[
                          SizedBox(width: 14),
                          Expanded(
                            flex: isFarmerSubmission ? 3 : 4,
                            child: _ReviewSection(
                              title: 'Other Ranked Crops',
                              icon: Icons.local_florist_outlined,
                              child: alts.isEmpty
                                  ? Text(
                                      'No alternative crops stored.',
                                      style: TextStyle(
                                        color: WebPortalColors.muted,
                                      ),
                                    )
                                  : SingleChildScrollView(
                                      child: Column(
                                        children: alts.take(4).map((a) {
                                          final m = a is Map
                                              ? Map<String, dynamic>.from(a)
                                              : <String, dynamic>{};
                                          return Padding(
                                            padding: EdgeInsets.only(
                                              bottom: 10,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.eco_rounded,
                                                  color: WebPortalColors.accent,
                                                  size: 18,
                                                ),
                                                SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    '${m['crop'] ?? m['name'] ?? a}',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  '${m['compatibility_pct'] ?? m['score'] ?? ''}${m['compatibility_pct'] != null || m['score'] != null ? '%' : ''}',
                                                  style: TextStyle(
                                                    color:
                                                        WebPortalColors.accent,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                        if (isFarmerSubmission) ...[
                          SizedBox(width: 14),
                          Expanded(
                            flex: 4,
                            child: _ReviewSection(
                              title: 'Planning Analyst Notes',
                              icon: Icons.note_alt_outlined,
                              child: status == 'pending'
                                  ? TextField(
                                      controller: notes,
                                      maxLength: 500,
                                      minLines: 5,
                                      maxLines: 6,
                                      decoration: InputDecoration(
                                        hintText:
                                            'Add verification notes for the farmer...',
                                      ),
                                    )
                                  : SingleChildScrollView(
                                      child: Text(
                                        notes.text.trim().isEmpty
                                            ? 'No planner notes were added.'
                                            : notes.text.trim(),
                                        style: TextStyle(height: 1.45),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1),
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: saving ? null : () => Navigator.pop(context),
                  child: Text('Close'),
                ),
                SizedBox(width: 10),
                if (isFarmerSubmission && status == 'pending') ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Color(0xFFE45B5B),
                      side: BorderSide(color: Color(0xFFE45B5B)),
                    ),
                    onPressed: saving ? null : () => decide('rejected'),
                    icon: Icon(Icons.close_rounded),
                    label: Text('Reject'),
                  ),
                  SizedBox(width: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: green),
                    onPressed: saving ? null : () => decide('verified'),
                    icon: saving
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(Icons.check_rounded),
                    label: Text('Verify'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (widget.embedded) {
      return Material(
        color: WebPortalColors.surface,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: content,
      );
    }

    return Dialog(
      insetPadding: EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: content,
    );
  }
}

class _ReviewSection extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Widget child;
  const _ReviewSection({this.title, this.icon, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: WebPortalColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Color(0xFFE3ECE5)),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: .025), blurRadius: 12),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Row(
            children: [
              Icon(
                icon ?? Icons.info_outline,
                color: WebPortalColors.accent,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                title!,
                style: TextStyle(
                  color: WebPortalColors.accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          SizedBox(height: 13),
        ],
        child,
      ],
    ),
  );
}

class _SummaryFact extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final String? caption;
  const _SummaryFact({
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: WebPortalColors.tint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: WebPortalColors.accent, size: 20),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: WebPortalColors.muted),
              ),
              SizedBox(height: 3),
              Text(
                value,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
              ),
              if (caption != null && caption!.isNotEmpty)
                Text(
                  caption!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: WebPortalColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MetricBox extends StatelessWidget {
  final String label;
  final dynamic value;
  final IconData icon;
  final String suffix;
  final int decimals;
  final bool estimated;
  const _MetricBox(
    this.label,
    this.value,
    this.icon, {
    this.suffix = '',
    this.decimals = 2,
    this.estimated = false,
  });
  String _shownValue() {
    if (value == null) return '--';
    final parsed = value is num
        ? (value as num).toDouble()
        : double.tryParse('$value');
    if (parsed == null) return '$value$suffix';
    return '${parsed.toStringAsFixed(decimals)}$suffix';
  }

  @override
  Widget build(BuildContext context) => Container(
    width: 165,
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Color(0xFFFBFDFC),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(
        color: estimated ? Color(0xFFF0C987) : Color(0xFFE8EFE9),
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: WebPortalColors.tint,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: WebPortalColors.accent, size: 18),
        ),
        SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: WebPortalColors.muted,
                    ),
                  ),
                  if (estimated)
                    Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.info_outline_rounded,
                        size: 11,
                        color: Color(0xFFB26A00),
                      ),
                    ),
                ],
              ),
              Text(
                _shownValue(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PlannerMapPreview extends StatelessWidget {
  final double height;
  final LatLng center;
  final List<LatLng> polygon;
  final List<Map<String, dynamic>> grid;
  final String valueKey;
  final List<double> values;
  final Color Function(double value, List<double> values) heatColor;
  final String selectedLayer;
  final ValueChanged<String> onLayerChanged;

  const _PlannerMapPreview({
    required this.height,
    required this.center,
    required this.polygon,
    required this.grid,
    required this.valueKey,
    required this.values,
    required this.heatColor,
    required this.selectedLayer,
    required this.onLayerChanged,
  });

  double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  String _satelliteUrl() {
    final points = <LatLng>[...polygon];
    for (final item in grid) {
      final lat = _number(item['lat']);
      final lng = _number(item['lng'] ?? item['lon']);
      if (lat != null && lng != null) points.add(LatLng(lat, lng));
    }
    if (points.isEmpty) points.add(center);

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final point in points.skip(1)) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    final latPad = ((maxLat - minLat).abs() * .22).clamp(.0012, .02);
    final lngPad = ((maxLng - minLng).abs() * .22).clamp(.0012, .02);
    final bbox =
        '${minLng - lngPad},${minLat - latPad},${maxLng + lngPad},${maxLat + latPad}';
    return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/export'
        '?bbox=$bbox&bboxSR=4326&size=1100,620&imageSR=4326&format=png32&transparent=false&f=image';
  }

  @override
  Widget build(BuildContext context) {
    final layers = [
      'NDVI',
      'Suitability',
      'Soil pH',
      'Rainfall',
      'Elevation',
      'Slope',
    ];
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              semanticLabel: 'Satellite view of the submitted farm boundary',
              _satelliteUrl(),
              fit: BoxFit.fill,
              errorBuilder: (_, _, _) => Container(
                color: Color(0xFFE7EFE8),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.map_outlined,
                      color: WebPortalColors.accent,
                      size: 42,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Map preview unavailable',
                      style: TextStyle(
                        color: WebPortalColors.accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(color: Colors.black.withValues(alpha: .08)),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _PlannerParcelPainter(
                    center: center,
                    polygon: polygon,
                    grid: grid,
                    valueKey: valueKey,
                    values: values,
                    heatColor: heatColor,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: WebPortalColors.surface.withValues(alpha: .96),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .10),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: layers.map((item) {
                        final selected = selectedLayer == item;
                        return Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(item),
                            selected: selected,
                            onSelected: (_) => onLayerChanged(item),
                            selectedColor: softGreen,
                            labelStyle: TextStyle(
                              color: selected ? green : WebPortalColors.muted,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: WebPortalColors.surface.withValues(alpha: .95),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(radius: 5, backgroundColor: Color(0xFFE95B55)),
                    SizedBox(width: 5),
                    Text('Low', style: TextStyle(fontSize: 11)),
                    SizedBox(width: 12),
                    CircleAvatar(radius: 5, backgroundColor: Color(0xFFF0AA20)),
                    SizedBox(width: 5),
                    Text('Moderate', style: TextStyle(fontSize: 11)),
                    SizedBox(width: 12),
                    CircleAvatar(radius: 5, backgroundColor: Color(0xFF16A765)),
                    SizedBox(width: 5),
                    Text('High', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),
            if (grid.isEmpty)
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: WebPortalColors.surface.withValues(alpha: .95),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    polygon.length >= 3
                        ? 'Polygon saved • no heatmap samples available'
                        : 'Point analysis • no polygon boundary saved',
                    style: TextStyle(
                      color: WebPortalColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlannerParcelPainter extends CustomPainter {
  final LatLng center;
  final List<LatLng> polygon;
  final List<Map<String, dynamic>> grid;
  final String valueKey;
  final List<double> values;
  final Color Function(double value, List<double> values) heatColor;

  _PlannerParcelPainter({
    required this.center,
    required this.polygon,
    required this.grid,
    required this.valueKey,
    required this.values,
    required this.heatColor,
  });

  double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  @override
  void paint(Canvas canvas, Size size) {
    final points = <LatLng>[...polygon];
    for (final item in grid) {
      final lat = _number(item['lat']);
      final lng = _number(item['lng'] ?? item['lon']);
      if (lat != null && lng != null) points.add(LatLng(lat, lng));
    }
    if (points.isEmpty) points.add(center);

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final point in points.skip(1)) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    final latPad = ((maxLat - minLat).abs() * .22).clamp(.0012, .02);
    final lngPad = ((maxLng - minLng).abs() * .22).clamp(.0012, .02);
    minLat -= latPad;
    maxLat += latPad;
    minLng -= lngPad;
    maxLng += lngPad;

    Offset convert(LatLng point) {
      final dx = maxLng == minLng
          ? .5
          : (point.longitude - minLng) / (maxLng - minLng);
      final dy = maxLat == minLat
          ? .5
          : 1 - ((point.latitude - minLat) / (maxLat - minLat));
      return Offset(dx * size.width, dy * size.height);
    }

    if (polygon.length >= 3) {
      final path = Path()
        ..moveTo(convert(polygon.first).dx, convert(polygon.first).dy);
      for (final point in polygon.skip(1)) {
        final offset = convert(point);
        path.lineTo(offset.dx, offset.dy);
      }
      path.close();

      // The sampled points are still used to calculate the selected layer,
      // but the review map presents one clean parcel classification instead
      // of a group of circles. This is easier for farmers and planners to read.
      final average = values.isEmpty
          ? null
          : values.reduce((a, b) => a + b) / values.length;
      final fill = average == null
          ? green.withValues(alpha: .22)
          : heatColor(average, values).withValues(alpha: .46);
      canvas.drawPath(path, Paint()..color = fill);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    // A center marker is only useful for genuine point analyses. Polygon
    // analyses should display the submitted boundary instead of implying that
    // only one coordinate was analyzed.
    if (polygon.length < 3) {
      final marker = convert(center);
      canvas.drawCircle(marker, 8, Paint()..color = green);
      canvas.drawCircle(
        marker,
        8,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PlannerParcelPainter oldDelegate) {
    return oldDelegate.valueKey != valueKey ||
        oldDelegate.grid != grid ||
        oldDelegate.polygon != polygon ||
        oldDelegate.center != center;
  }
}
