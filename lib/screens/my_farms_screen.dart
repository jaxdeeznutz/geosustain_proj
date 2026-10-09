part of '../main.dart';

String _farmDate(dynamic value) {
  final parsed = DateTime.tryParse('$value')?.toLocal();
  if (parsed == null) return value == null ? 'Date unavailable' : '$value';
  return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
}

String _farmReviewLabel(dynamic value) => switch ('$value'.toLowerCase()) {
  'pending' => 'Pending Review',
  'verified' || 'approved' => 'Approved',
  'rejected' => 'Rejected',
  'null' ||
  '' ||
  'draft' ||
  'not_submitted' ||
  'unsubmitted' => 'Not Submitted',
  _ => '$value',
};

class MyFarmsPage extends StatefulWidget {
  final AnalysisState state;
  final VoidCallback? onAnalyzed;
  const MyFarmsPage({super.key, required this.state, this.onAnalyzed});
  @override
  State<MyFarmsPage> createState() => _MyFarmsPageState();
}

class _MyFarmsPageState extends State<MyFarmsPage> {
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    widget.state.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    widget.state.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _onAnalyzed() {
    if (widget.onAnalyzed != null) {
      widget.onAnalyzed!();
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      await widget.state.refreshFarms();
      if (mounted) setState(() => _error = widget.state.farmsError);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> farm) async {
    widget.state.focusFarm(farm);
    final analyzed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FarmDetailsPage(state: widget.state, farm: farm),
      ),
    );
    if (!mounted) return;
    if (analyzed == true) _onAnalyzed();
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('My Farms'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          tooltip: 'Refresh farms',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Map your land',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            _LandMethodCard(
              gps: true,
              onTap: () =>
                  openLandMethod(context, widget.state, true, _onAnalyzed),
            ),
            _LandMethodCard(
              gps: false,
              onTap: () =>
                  openLandMethod(context, widget.state, false, _onAnalyzed),
            ),
            const SizedBox(height: 20),
            const Text(
              'Saved farms',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const Text(
              'Each farm can have multiple analysis runs. Open a farm to view its boundary, results, and review feedback.',
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              _MappingNotice(_error!),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry loading farms'),
              ),
            ],
            if (!_loading && _error == null && widget.state.farms.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No farms saved yet. Choose GPS walking or map drawing above to create your first farm.',
                  ),
                ),
              ),
            ...widget.state.farms.map(
              (farm) => Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _open(farm),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.landscape_outlined, color: green),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${farm['farm_name'] ?? 'Saved farm'}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${farm['location_name'] ?? ''}'.trim().isEmpty
                              ? 'Location description not provided'
                              : '${farm['location_name']}',
                        ),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Chip(
                              label: Text(
                                farm['area_hectares'] == null
                                    ? 'Area unavailable'
                                    : '${(double.tryParse('${farm['area_hectares']}') ?? 0).toStringAsFixed(3)} ha',
                              ),
                            ),
                            Chip(
                              label: Text(
                                farm['mapping_method'] == 'gps_walk'
                                    ? 'GPS boundary'
                                    : 'Drawn polygon',
                              ),
                            ),
                            Chip(
                              label: Text(
                                '${farm['analysis_count'] ?? 0} analyses',
                              ),
                            ),
                          ],
                        ),
                        Text(
                          farm['last_analyzed_at'] == null &&
                                  farm['latest_analysis_date'] == null
                              ? 'Not analyzed yet'
                              : 'Latest analysis: ${_farmDate(farm['last_analyzed_at'] ?? farm['latest_analysis_date'])}',
                        ),
                        if (farm['latest_review_status'] != null ||
                            farm['latest_verification_status'] != null)
                          Text(
                            'Latest analysis review: ${_farmReviewLabel(farm['latest_review_status'] ?? farm['latest_verification_status'])}',
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );
}

class FarmDetailsPage extends StatefulWidget {
  final AnalysisState state;
  final Map<String, dynamic> farm;
  const FarmDetailsPage({super.key, required this.state, required this.farm});
  @override
  State<FarmDetailsPage> createState() => FarmDetailsPageState();
}

class FarmDetailsPageState extends State<FarmDetailsPage> {
  bool _busy = false, _loading = true;
  String? _notice;
  late Map<String, dynamic> _farm;
  List<Map<String, dynamic>> _records = [];
  bool _recordsLoaded = false;
  @override
  void initState() {
    super.initState();
    _farm = Map.of(widget.farm);
    widget.state.addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    widget.state.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _notice = null;
      });
    }
    try {
      final epoch = widget.state._sessionEpoch;
      _recordsLoaded = false;
      final values = await Future.wait<dynamic>([
        widget.state.api.getFarm(int.parse('${_farm['id']}')),
        widget.state.api.getFarmHistory(int.parse('${_farm['id']}')),
      ]);
      if (!mounted || epoch != widget.state._sessionEpoch) return;
      final freshFarm = Map<String, dynamic>.from(values[0] as Map);
      if ('${freshFarm['id']}' != '${_farm['id']}') {
        throw const FormatException(
          'The farm could not be verified. Refresh and try again.',
        );
      }
      setState(() {
        _farm = freshFarm;
        _records = (values[1] as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .where((r) => widget.state._ownsRecord(r))
            .toList();
        _recordsLoaded = true;
      });
    } catch (error) {
      if (mounted) setState(() => _notice = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _analyses => newestAnalysisRecords(
    _records.where(
      (record) =>
          '${record['farm_id']}' == '${_farm['id']}' &&
          analysisIsCompleted(record),
    ),
  );

  Future<void> _analyze() async {
    if (_busy) return;
    setState(() => _busy = true);
    final error = await widget.state.analyzeSavedFarm(_farm);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _notice = error;
    });
    if (error == null) Navigator.pop(context, true);
  }

  Future<void> _openResult(Map<String, dynamic> record) async {
    if (_busy) return;
    setState(() => _busy = true);
    final error = await widget.state.selectAnalysis(record);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _notice = error;
    });
    if (error == null) Navigator.pop(context, true);
  }

  Future<void> _editDetails() async {
    final name = TextEditingController(text: '${_farm['farm_name'] ?? ''}');
    final location = TextEditingController(
      text: '${_farm['location_name'] ?? ''}',
    );
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit farm details'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Farm name'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a farm name.'
                      : null,
                ),
                TextFormField(
                  controller: location,
                  maxLength: 250,
                  decoration: const InputDecoration(
                    labelText: 'Location description',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final newName = name.text.trim(), newLocation = location.text.trim();
    // The route retains its text fields during the dismissal animation.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    name.dispose();
    location.dispose();
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.state.api.updateFarm(
        int.parse('${_farm['id']}'),
        {'farm_name': newName, 'location_name': newLocation},
      );
      _farm = {..._farm, ...updated};
      widget.state.replaceFarms(
        widget.state.farms
            .map((f) => '${f['id']}' == '${_farm['id']}' ? _farm : f)
            .toList(),
      );
    } catch (error) {
      if (mounted) setState(() => _notice = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive this farm?'),
        content: const Text(
          'The farm will be hidden from My Farms. Its past analyses and analyst reviews remain in History.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.state.api.updateFarm(int.parse('${_farm['id']}'), {
        'is_archived': true,
      });
      widget.state.replaceFarms(
        widget.state.farms
            .where((f) => '${f['id']}' != '${_farm['id']}')
            .toList(),
      );
      if (mounted) {
        setState(() => _busy = false);
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _notice = friendlyErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = FarmGeometry.fromPayload(_farm['polygon']);
    final analyses = _analyses;
    final latest = analyses.firstOrNull;
    return PopScope<bool>(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Farm details'),
          actions: [
            PopupMenuButton<String>(
              enabled: !_busy,
              tooltip: 'Farm actions',
              onSelected: (action) {
                if (action == 'refresh') _load();
                if (action == 'edit') _editDetails();
                if (action == 'archive') _archive();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'refresh', child: Text('Refresh')),
                PopupMenuItem(value: 'edit', child: Text('Edit farm details')),
                PopupMenuItem(value: 'archive', child: Text('Archive farm')),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${_farm['farm_name'] ?? 'Farm'}',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF20382C),
                ),
              ),
              if ('${_farm['owner_display_name'] ?? ''}'.isNotEmpty)
                Text('Owner: ${_farm['owner_display_name']}'),
              if ('${_farm['location_name'] ?? ''}'.isNotEmpty)
                Text(
                  '${_farm['location_name']}',
                  style: const TextStyle(color: Colors.black54),
                ),
              const SizedBox(height: 6),
              Text(
                '${analysisAreaText(_farm)} · ${_farm['mapping_method'] == 'gps_walk' ? 'GPS boundary' : 'Drawn boundary'}',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              if (points.isNotEmpty)
                _BoundaryMap(
                  key: ValueKey('${_farm['id']}-${_farm['boundary_version']}'),
                  points: points,
                )
              else
                const _MappingNotice('This farm has no readable boundary.'),
              const SizedBox(height: 12),
              if (_loading || _busy) const LinearProgressIndicator(),
              if (!_loading && _recordsLoaded && analyses.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Not analyzed yet',
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
              if (_notice != null) _MappingNotice(_notice!),
              if (_busy && widget.state.loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(widget.state.loadingMessage),
                ),
              FilledButton.icon(
                onPressed: _busy || _loading || points.isEmpty
                    ? null
                    : _analyze,
                icon: const Icon(Icons.analytics_outlined),
                label: Text(
                  _busy
                      ? 'Please wait…'
                      : widget.state.analysisPending &&
                            widget.state.selectedFarmId ==
                                int.tryParse('${_farm['id']}')
                      ? 'Check analysis'
                      : 'Analyze This Farm',
                ),
              ),
              if (latest != null)
                TextButton.icon(
                  onPressed: _busy ? null : () => _openResult(latest),
                  icon: const Icon(Icons.assessment_outlined),
                  label: const Text('Latest results'),
                ),
              if (points.isNotEmpty &&
                  FarmGeometry.areaSquareMetres(points) < 100)
                const ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    'Small boundary · limited detail',
                    style: TextStyle(fontSize: 13),
                  ),
                  children: [
                    Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'This boundary is smaller than a 10 m satellite pixel. Results may describe surrounding land. Check the boundary and verify conditions on site.',
                      ),
                    ),
                  ],
                ),
              if (analyses.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'Previous analyses',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                for (final record in analyses)
                  AnalysisHistoryRow(
                    record: record,
                    onTap: _busy ? null : () => _openResult(record),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
