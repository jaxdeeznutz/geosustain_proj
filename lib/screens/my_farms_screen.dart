part of '../main.dart';

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
  String _search = '', _filter = 'All Farms';
  bool _loading = true;
  String? _error;
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> get _visibleFarms => widget.state.farms
      .where(
        (f) =>
            '${f['farm_name']} ${f['location_name']}'.toLowerCase().contains(
              _search,
            ) &&
            (_filter == 'All Farms' ||
                (_filter == 'Analyzed') ==
                    ((analysisNumber(f['analysis_count']) ?? 0) > 0)),
      )
      .toList();
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
    _searchController.dispose();
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

  Future<void> _open(Map<String, dynamic> farm, {String? action}) async {
    if (farm['_local_only'] == true) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LocalFarmPage(state: widget.state, farm: farm),
        ),
      );
      if (mounted) setState(() {});
      return;
    }
    widget.state.focusFarm(farm);
    final analyzed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FarmDetailsPage(
          state: widget.state,
          farm: farm,
          initialAction: action,
        ),
      ),
    );
    if (!mounted) return;
    if (analyzed == true) _onAnalyzed();
    await _load();
  }

  Future<void> _analyzeFarm(Map<String, dynamic> farm) async {
    if (farm['_local_only'] == true) {
      await _open(farm);
      return;
    }
    if (widget.state.loading) return;
    final error = await widget.state.analyzeSavedFarm(farm);
    if (!mounted) return;
    if (error != null) {
      setState(() => _error = error);
    } else {
      _onAnalyzed();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: GeoSafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            GeoSustainHeader(
              title: 'My Farms',
              state: widget.state,
              showNotifications: false,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GeoHeaderAction(
                    tooltip: 'Create a farm',
                    accent: true,
                    onPressed: () => showLandMethodPicker(
                      context,
                      widget.state,
                      _onAnalyzed,
                    ),
                    icon: Icons.add,
                  ),
                ],
              ),
            ),
            const FarmBanner(
              'Manage Your Farms',
              'View, edit, and analyze your saved farm areas. Create a new boundary or analyze an existing area anytime.',
            ),
            PlantingMonthPicker(state: widget.state),
            if (widget.state.offlineWorkspace ||
                widget.state.pendingFarmCount > 0)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.state.offlineWorkspace
                            ? 'Offline workspace'
                            : 'Device farm sync',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${widget.state.pendingFarmCount} pending farms. GPS works offline; map tiles and analysis need internet. Sync does not start an analysis.',
                      ),
                      FilledButton.icon(
                        onPressed: widget.state.syncingFarms
                            ? null
                            : () async {
                                try {
                                  await widget.state.syncPendingFarms();
                                  await _load();
                                } catch (error) {
                                  if (mounted) {
                                    setState(
                                      () =>
                                          _error = friendlyErrorMessage(error),
                                    );
                                  }
                                }
                              },
                        icon: const Icon(Icons.sync),
                        label: Text(
                          widget.state.syncingFarms ? 'Syncing…' : 'Sync now',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ReferenceAction(
                    'Create a Farm Boundary',
                    'Walk your perimeter with live GPS.',
                    Icons.directions_walk,
                    () => openLandMethod(
                      context,
                      widget.state,
                      true,
                      _onAnalyzed,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: ReferenceAction(
                    'Analyze Land Using a Polygon',
                    'Outline an area and explore crop suitability.',
                    Icons.edit_square,
                    () => openLandMethod(
                      context,
                      widget.state,
                      false,
                      _onAnalyzed,
                    ),
                    blue: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                Text(
                  'Saved Farms',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                DropdownButton<String>(
                  value: _filter,
                  items: [
                    for (final f in ['All Farms', 'Not analyzed', 'Analyzed'])
                      DropdownMenuItem(value: f, child: Text(f)),
                  ],
                  onChanged: (v) => setState(() => _filter = v!),
                ),
              ],
            ),
            const Text('Your boundaries, results, and review updates.'),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search farms',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _search = '');
                          },
                        ),
                ),
                onChanged: (v) => setState(() => _search = v.toLowerCase()),
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) _MappingNotice(_error!),
            if (!_loading && _error == null && widget.state.farms.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No farms saved yet. Walk or draw your first boundary above.',
                  ),
                ),
              ),
            if (!_loading &&
                _error == null &&
                widget.state.farms.isNotEmpty &&
                _visibleFarms.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No matching farms. Try another name or change the filter.',
                  ),
                ),
              ),
            for (final farm in _visibleFarms)
              GeoFarmCard(
                farm: farm,
                busy: widget.state.loading,
                onOpen: () => _open(farm),
                onAnalyze: () => _analyzeFarm(farm),
                onResults: () => _open(farm, action: 'results'),
                onEdit: () => _open(farm, action: 'edit'),
                onArchive: () => _open(farm, action: 'archive'),
              ),
          ],
        ),
      ),
    ),
  );
}

class FarmDetailsPage extends StatefulWidget {
  final AnalysisState state;
  final Map<String, dynamic> farm;
  final String? initialAction;
  const FarmDetailsPage({
    super.key,
    required this.state,
    required this.farm,
    this.initialAction,
  });
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
    _load().then((_) {
      if (!mounted || _notice != null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.initialAction == 'edit') _editDetails();
        if (widget.initialAction == 'archive') _archive();
        if (widget.initialAction == 'results' && _analyses.isNotEmpty) {
          _openResult(_analyses.first);
        }
      });
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
      if (mounted) {
        setState(() => _notice = friendlyErrorMessage(error));
      }
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
      final updated = await widget.state.api
          .updateFarm(int.parse('${_farm['id']}'), {
            'farm_name': newName,
            'location_name': newLocation,
            'expected_boundary_version': _farm['boundary_version'],
          });
      _farm = {..._farm, ...updated};
      widget.state.replaceFarms(
        widget.state.farms
            .map((f) => '${f['id']}' == '${_farm['id']}' ? _farm : f)
            .toList(),
      );
    } catch (error) {
      if (error is ApiException && error.statusCode == 409) {
        try {
          final fresh = await widget.state.api.getFarm(
            int.parse('${_farm['id']}'),
          );
          if (mounted) {
            setState(() {
              _farm = fresh;
              _notice =
                  'Another edit was saved. The farm has been reloaded; review it and edit again.';
            });
          }
        } catch (_) {
          if (mounted) {
            setState(
              () => _notice =
                  'Another edit was saved. Reload the farm before editing again.',
            );
          }
        }
      } else if (mounted) {
        setState(() => _notice = friendlyErrorMessage(error));
      }
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
        'expected_boundary_version': _farm['boundary_version'],
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
        appBar: GeoSustainHeader(
          title: 'Farm Details',
          embedded: false,
          nested: true,
          state: widget.state,
          trailing: PopupMenuButton<String>(
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
              if (_notice != null) _MappingNotice(_notice!),
              if (!_loading && _recordsLoaded && analyses.isEmpty)
                const Text(
                  'Not analyzed yet',
                  style: TextStyle(color: Colors.black54),
                ),
              AnalysisCoverageCard(record: _farm),
              CoverageExplorer(api: widget.state.api, points: points),
              if (points.isNotEmpty)
                _BoundaryMap(
                  key: ValueKey('${_farm['id']}-${_farm['boundary_version']}'),
                  points: points,
                )
              else
                const _MappingNotice('This farm has no readable boundary.'),
              const SizedBox(height: 12),
              if (_loading || _busy) const LinearProgressIndicator(),
              PlantingMonthPicker(
                state: widget.state,
                enabled: !_busy && !_loading,
              ),
              if (_busy && widget.state.loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(widget.state.loadingMessage),
                ),
              FilledButton.icon(
                onPressed:
                    _busy ||
                        _loading ||
                        points.isEmpty ||
                        !farmCanAnalyze(_farm)
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
