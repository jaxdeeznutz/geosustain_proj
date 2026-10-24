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
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        if (owner.isNotEmpty)
          GeoInfoLine(Icons.person_outline, 'Owner: $owner'),
        if (location.isNotEmpty)
          GeoInfoLine(Icons.location_on_outlined, location),
        GeoInfoLine(
          Icons.calendar_today_outlined,
          analysisDateText(analysisRecordDate(record)),
        ),
        const SizedBox(height: 6),
        GeoStatusPill(label: analysisAreaText(record), icon: Icons.crop_free),
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
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ParcelThumbnail(record),
            const SizedBox(width: 12),
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
        const _FieldLandscape(),
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
      return GeoSafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            key: const PageStorageKey('mobile-analysis-scroll'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              GeoSustainHeader(
                title: 'Analysis',
                state: state,
                trailing: IconButton(
                  tooltip: 'Refresh',
                  onPressed: busy ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ),
              if (result != null && completed.length > 1)
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      shape: const StadiumBorder(),
                    ),
                    onPressed: busy ? null : _chooseAnalysis,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Switch analysis'),
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
  Widget build(BuildContext context) =>
      ReferenceAnalysisContent(state: state, record: record);
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
  final Color surface;
  final IconData? icon;
  const _AnalysisSection({
    required this.title,
    required this.children,
    this.surface = Colors.white,
    this.icon,
  });
  @override
  Widget build(BuildContext context) => Card(
    color: geoPanelColor(context, surface),
    elevation: .5,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: BorderSide(color: darkGreen.withValues(alpha: .08)),
    ),
    margin: const EdgeInsets.symmetric(vertical: 8),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: 16, height: 1.4, color: Color(0xFF263C32)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    color: Theme.of(context).colorScheme.onSurface,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
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
      ('ndvi', 'Plant cover (NDVI)', '', 'ndvi'),
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
      title: 'Land conditions',
      icon: Icons.landscape_outlined,
      children: [
        Text(
          'Land type: ${farmerLandType(record)}',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const _AnalysisParagraph(
          'Land type comes from plant-cover rules. It does not prove that every crop will grow here.',
        ),
        if (present.isEmpty)
          Text('Environmental measurements are unavailable for this analysis.'),
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
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                if (quality[item.$4] != null)
                  Text(
                    '${analysisMapValue(quality[item.$4])['overall_quality'] ?? analysisMapValue(quality[item.$4])['quality'] ?? 'Source quality unavailable'}'
                        .replaceAll('_', ' '),
                    style: TextStyle(fontSize: 14, color: Color(0xFF536258)),
                  ),
              ],
            ),
          ),
        if (present.any(
          (i) => ['nitrogen', 'phosphorus', 'potassium'].contains(i.$1),
        ))
          Text(
            'Nutrient values are model inputs. Units are not specified in these records; they are not fertilizer application rates.',
            style: TextStyle(fontSize: 16),
          ),
        if (warnings.isNotEmpty || quality.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Data sources and limitations'),
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
    final crops = rankedCropRecommendations(record);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (crops.isEmpty) Text('No crop assessments were saved.'),
        for (var i = 0; i < crops.length; i++)
          _CropAssessmentCard(
            key: ValueKey('crop-${crops[i]['crop']}'),
            crop: crops[i],
            record: record,
            rank: i + 1,
          ),
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
        title: Text('Analyzed boundary'),
        subtitle: Text(analysisAreaText(record)),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          Text(
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
        SnackBar(
          content: Text(
            widget.record['verification_status'] == 'verified' ||
                    widget.record['verification_status'] == 'rejected'
                ? 'This assessment has already been reviewed.'
                : 'Analysis submitted for analyst review.',
          ),
        ),
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
        status == 'draft';
    return _AnalysisSection(
      title: 'Analyst review',
      children: [
        VerificationStatusBadge(status: status),
        if (widget.record['is_crop_recommended'] == false)
          const Text(
            'Review covers this partial assessment. It does not fill missing observations or establish crop suitability.',
          ),
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
