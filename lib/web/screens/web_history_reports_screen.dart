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
  String _status = 'all', _area = 'all', _type = 'all', _dateRange = 'all';
  bool _oldestFirst = false, _grid = false;
  late final _search = TextEditingController(
    text: PortalRoutes.current.value.queryParameters['q'] ?? '',
  );
  int get _page => _records.offset ~/ 20;
  String get _query => _records.query;
  void _changed() {
    if (mounted) {
      setState(() {
        if (!_records.rows.any((r) => _analystStatus(r) == _status)) {
          _status = 'all';
        }
        if (!_records.rows.any(
          (r) =>
              '${r['place_name'] ?? r['location'] ?? 'Analyzed Area'}' == _area,
        )) {
          _area = 'all';
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    if (!compact) {
      _records.addListener(_changed);
      _records.query = PortalRoutes.current.value.queryParameters['q'] ?? '';
      _records.load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
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

  Future<void> _open(Map<String, dynamic> row) async {
    final rawId = row['session_id'] ?? row['id'];
    final id = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
    if (id == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _WebHistoryDetailDialog(
        record: state.normalizeRecord(Map<String, dynamic>.from(row)),
        state: state,
        topCrop: _topCropFromRecord(row),
        suitabilityPct: WebAnalysisMetrics.modelScore(row),
      ),
    );
  }

  Widget _filter(
    String label,
    String value,
    Map<String, String> items,
    ValueChanged<String> change,
  ) => SizedBox(
    width: 155,
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label-$value-${items.keys.join(',')}'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final e in items.entries)
          DropdownMenuItem(
            value: e.key,
            child: Text(e.value, style: const TextStyle(fontSize: 12)),
          ),
      ],
      onChanged: (v) {
        if (v != null) {
          setState(() => change(v));
        }
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final loaded = compact
        ? state.historyRecords.take(5).toList()
        : _records.rows;
    final locations =
        loaded
            .map(
              (r) => '${r['place_name'] ?? r['location'] ?? 'Analyzed Area'}',
            )
            .toSet()
            .toList()
          ..sort();
    final statuses = loaded.map(_analystStatus).toSet().toList()..sort();
    final now = DateTime.now();
    final rows =
        loaded.where((r) {
          final location =
              '${r['place_name'] ?? r['location'] ?? 'Analyzed Area'}';
          final date = _analystRecordDate(r);
          return (_status == 'all' || _analystStatus(r) == _status) &&
              (_area == 'all' || location == _area) &&
              (_type == 'all' ||
                  (_type == 'crop'
                      ? WebAnalysisMetrics.isCrop(r)
                      : !WebAnalysisMetrics.isCrop(r))) &&
              (_dateRange == 'all' ||
                  (date != null &&
                      !date.isBefore(
                        now.subtract(Duration(days: int.parse(_dateRange))),
                      )));
        }).toList()..sort((a, b) {
          final order = (_analystRecordDate(a) ?? DateTime(1970)).compareTo(
            _analystRecordDate(b) ?? DateTime(1970),
          );
          return _oldestFirst ? order : -order;
        });
    final counts = <String, int>{};
    final monthly = <String, double>{};
    for (final r in loaded) {
      counts[_analystStatus(r)] = (counts[_analystStatus(r)] ?? 0) + 1;
      final date = _analystRecordDate(r);
      if (date != null) {
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        monthly[key] = (monthly[key] ?? 0) + 1;
      }
    }
    final months = monthly.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final cropCount = loaded.where(WebAnalysisMetrics.isCrop).length;
    final area = loaded
        .map(_analystArea)
        .whereType<double>()
        .fold<double>(0, (a, b) => a + b);
    final table = _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AnalystSectionTitle(
            state.isPlanner ? 'Recent analyst assessments' : 'Recent Analyses',
            subtitle: 'Your saved land analyses and results.',
            icon: Icons.history_rounded,
            action: compact
                ? null
                : IconButton(
                    tooltip: 'Refresh analyses',
                    onPressed: _records.loading ? null : () => _records.load(),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                  ),
          ),
          const SizedBox(height: 12),
          if (!compact)
            Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Sort by', style: TextStyle(fontSize: 11)),
                DropdownButton<bool>(
                  value: _oldestFirst,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(
                      value: false,
                      child: Text(
                        'Date (Newest)',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    DropdownMenuItem(
                      value: true,
                      child: Text(
                        'Date (Oldest)',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _oldestFirst = value ?? false),
                ),
                IconButton(
                  tooltip: 'List view',
                  isSelected: !_grid,
                  onPressed: () => setState(() => _grid = false),
                  icon: const Icon(Icons.view_list_outlined, size: 20),
                ),
                IconButton(
                  tooltip: 'Grid view',
                  isSelected: _grid,
                  onPressed: () => setState(() => _grid = true),
                  icon: const Icon(Icons.grid_view_rounded, size: 18),
                ),
                TextButton.icon(
                  onPressed: _records.loading ? null : () => _records.load(),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(
                    _records.error == null
                        ? 'Refresh records'
                        : 'Retry records',
                  ),
                ),
              ],
            ),
          if (!compact && _records.loading)
            const LinearProgressIndicator(semanticsLabel: 'Loading records'),
          if (!compact && _records.error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                '${_records.error} Previously loaded records may be out of date.',
              ),
            ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(
                    Icons.manage_search_rounded,
                    color: WebPortalColors.accent,
                    size: 38,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    loaded.isEmpty && _query.isEmpty
                        ? 'No analysis history yet.'
                        : 'No records match your search or page filters.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: WebPortalColors.muted),
                  ),
                ],
              ),
            )
          else if (_grid && !compact)
            LayoutBuilder(
              builder: (_, box) {
                final columns = box.maxWidth >= 600 ? 2 : 1;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final row in rows)
                      SizedBox(
                        width: (box.maxWidth - (columns - 1) * 12) / columns,
                        child: _historyTile(row),
                      ),
                  ],
                );
              },
            )
          else
            LayoutBuilder(
              builder: (_, box) {
                if (box.maxWidth < 650 || compact) {
                  return Column(children: rows.map(_historyTile).toList());
                }
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: box.maxWidth),
                    child: DataTable(
                      headingRowHeight: 38,
                      dataRowMinHeight: 62,
                      dataRowMaxHeight: 74,
                      horizontalMargin: 10,
                      columnSpacing: 18,
                      headingRowColor: WidgetStatePropertyAll(
                        WebPortalColors.tint.withValues(alpha: .6),
                      ),
                      headingTextStyle: TextStyle(
                        fontSize: 11,
                        color: WebPortalColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                      dataTextStyle: TextStyle(
                        fontSize: 12,
                        color: WebPortalColors.ink,
                      ),
                      columns: [
                        for (final label in [
                          '#',
                          'Analysis Name',
                          'Area (ha)',
                          'Date',
                          'Status',
                          'Recommendation',
                          'Actions',
                        ])
                          DataColumn(label: Text(label)),
                      ],
                      rows: [
                        for (var i = 0; i < rows.length; i++)
                          DataRow(
                            cells: [
                              DataCell(Text('${_records.offset + i + 1}')),
                              DataCell(
                                SizedBox(
                                  width: 155,
                                  child: Row(
                                    children: [
                                      _historyIcon(rows[i]),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${rows[i]['place_name'] ?? rows[i]['location'] ?? 'Analyzed Area'}',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            Text(
                                              WebAnalysisMetrics.isCrop(rows[i])
                                                  ? 'Crop model assessment'
                                                  : 'Land assessment',
                                              style: TextStyle(
                                                color: WebPortalColors.muted,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                onTap: () => _open(rows[i]),
                              ),
                              DataCell(
                                Text(
                                  _analystArea(rows[i])?.toStringAsFixed(2) ??
                                      '—',
                                ),
                              ),
                              DataCell(
                                Text(
                                  _analystRecordDate(
                                        rows[i],
                                      )?.toIso8601String().split('T').first ??
                                      '—',
                                ),
                              ),
                              DataCell(_historyStatus(rows[i])),
                              DataCell(
                                SizedBox(
                                  width: 130,
                                  child: Text(
                                    WebAnalysisMetrics.isCrop(rows[i])
                                        ? _topCropFromRecord(rows[i])
                                        : 'No crop recommendation',
                                    maxLines: 2,
                                  ),
                                ),
                              ),
                              DataCell(
                                IconButton(
                                  tooltip: 'Open assessment',
                                  onPressed: () => _open(rows[i]),
                                  icon: const Icon(Icons.chevron_right_rounded),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          if (!compact) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${rows.length} shown of ${loaded.length} loaded · Page ${_page + 1}',
                  style: TextStyle(fontSize: 11, color: WebPortalColors.muted),
                ),
                TextButton(
                  onPressed: !_records.loading && _page > 0
                      ? () => _records.load(offset: (_page - 1) * 20)
                      : null,
                  child: const Text('Previous'),
                ),
                TextButton(
                  onPressed: !_records.loading && _records.more
                      ? () => _records.load(offset: (_page + 1) * 20)
                      : null,
                  child: const Text('Next'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    if (compact) return table;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AnalystMetricGrid(
          children: [
            _AnalystMetric(
              icon: Icons.description_rounded,
              label: 'Loaded Analyses',
              value: '${loaded.length}',
              caption: 'Current search page',
            ),
            _AnalystMetric(
              icon: Icons.map_outlined,
              label: 'Loaded Analysis Area',
              value: '${area.toStringAsFixed(2)} ha',
              caption: 'Repeated analyses count separately',
              color: const Color(0xFF287DCA),
            ),
            _AnalystMetric(
              icon: Icons.spa_rounded,
              label: 'With Crop Rankings',
              value: '$cropCount',
              caption: 'Loaded records only',
              color: const Color(0xFFAB6900),
            ),
            _AnalystMetric(
              icon: Icons.schedule_rounded,
              label: 'Pending Review',
              value: '${counts['pending'] ?? 0}',
              caption: 'Loaded records only',
              color: const Color(0xFF8552CA),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _AnalystColumns(
          main: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WebCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        labelText: 'Search all records',
                        hintText: 'Analysis name, location, date…',
                        prefixIcon: Icon(Icons.search, size: 19),
                      ),
                      onChanged: _records.search,
                      onSubmitted: _records.search,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _filter('Date range', _dateRange, const {
                          'all': 'All time',
                          '30': 'Last 30 days',
                          '90': 'Last 90 days',
                        }, (v) => _dateRange = v),
                        _filter(
                          'Status',
                          statuses.contains(_status) ? _status : 'all',
                          {
                            'all': 'All statuses',
                            for (final status in statuses)
                              status: reviewLabel(status),
                          },
                          (v) => _status = v,
                        ),
                        _filter(
                          'Area',
                          locations.contains(_area) ? _area : 'all',
                          {
                            'all': 'All locations',
                            for (final place in locations) place: place,
                          },
                          (v) => _area = v,
                        ),
                        _filter('Analysis type', _type, const {
                          'all': 'All types',
                          'crop': 'Crop model',
                          'land': 'Land assessment',
                        }, (v) => _type = v),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _status = _area = _type = _dateRange = 'all';
                              _oldestFirst = false;
                            });
                            _search.clear();
                            _records.search('');
                          },
                          icon: const Icon(Icons.restart_alt, size: 16),
                          label: const Text('Reset'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Search covers your account. Date, status, area and type filters apply to the loaded page.',
                      style: TextStyle(
                        fontSize: 11,
                        color: WebPortalColors.muted,
                      ),
                    ),
                    if (state.isPlanner) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'My analyst assessments · These records belong to your account. Farmer submissions are in the Review Inbox.',
                      ),
                      Wrap(
                        spacing: 12,
                        children: [
                          TextButton.icon(
                            onPressed: () =>
                                PortalRoutes.go('/operator/analyze'),
                            icon: const Icon(Icons.add_location_alt, size: 16),
                            label: const Text('Analyze an area'),
                          ),
                          TextButton.icon(
                            onPressed: () => PortalRoutes.go('/operator/queue'),
                            icon: const Icon(Icons.fact_check, size: 16),
                            label: const Text('Open Review Inbox'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              table,
            ],
          ),
          side: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AnalystBars(
                title: 'Analysis Statistics',
                subtitle: 'Loaded records · last 6 recorded months',
                entries: months
                    .skip(math.max(0, months.length - 6))
                    .map((e) => MapEntry(e.key.substring(5), e.value))
                    .toList(),
                unit: 'Analyses per month',
              ),
              const SizedBox(height: 16),
              _AnalystStatusDistribution(counts),
              const SizedBox(height: 16),
              _WebCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _AnalystSectionTitle(
                      'Analysis Types',
                      subtitle: 'Loaded records only',
                      icon: Icons.pie_chart_rounded,
                    ),
                    const SizedBox(height: 16),
                    for (final entry in [
                      MapEntry('Crop model assessment', cropCount),
                      MapEntry('Land assessment', loaded.length - cropCount),
                    ]) ...[
                      Text(
                        '${entry.key} · ${entry.value}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      const SizedBox(height: 7),
                      LinearProgressIndicator(
                        value: loaded.isEmpty ? 0 : entry.value / loaded.length,
                        minHeight: 5,
                        color: WebPortalColors.accent,
                        backgroundColor: WebPortalColors.tint,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _historyIcon(Map<String, dynamic> row) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: WebPortalColors.tint,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Icon(
      WebAnalysisMetrics.isCrop(row)
          ? Icons.eco_outlined
          : Icons.landscape_outlined,
      color: WebPortalColors.accent,
      size: 21,
    ),
  );

  Widget _historyStatus(Map<String, dynamic> row) => _SmallBadge(
    reviewLabel(_analystStatus(row)),
    color: reviewColor(_analystStatus(row)),
  );

  Widget _historyTile(Map<String, dynamic> row) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: WebPortalColors.canvas,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => _open(row),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _historyIcon(row),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${row['place_name'] ?? row['location'] ?? 'Analyzed Area'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_analystRecordDate(row)?.toIso8601String().split('T').first ?? 'Date unavailable'} · ${WebAnalysisMetrics.isCrop(row) ? _topCropFromRecord(row) : 'Land assessment'}',
                      style: TextStyle(
                        color: WebPortalColors.muted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _historyStatus(row),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 18),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AnalystStatusDistribution extends StatelessWidget {
  final Map<String, int> counts;
  const _AnalystStatusDistribution(this.counts);
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final entries = counts.entries.toList();
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    return _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AnalystSectionTitle(
            'Status Distribution',
            subtitle: 'Loaded records only',
            icon: Icons.donut_small_rounded,
          ),
          const SizedBox(height: 18),
          Center(
            child: SizedBox(
              width: 130,
              height: 130,
              child: CustomPaint(
                painter: _DonutPainter(
                  values: entries.map((e) => e.value).toList(),
                  colors: entries.map((e) => reviewColor(e.key)).toList(),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$total',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Total',
                        style: TextStyle(
                          color: WebPortalColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (total == 0)
            Text(
              'No recorded statuses yet.',
              style: TextStyle(color: WebPortalColors.muted, fontSize: 11),
            ),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 9, color: reviewColor(entry.key)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reviewLabel(entry.key),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  Text(
                    '${entry.value} (${(entry.value * 100 / total).round()}%)',
                    style: TextStyle(
                      color: WebPortalColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
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
  String _dates = 'all', _type = 'all';
  final _search = TextEditingController();
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
    _search.dispose();
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

  DateTime? _reportDate(Map<String, dynamic> row) => DateTime.tryParse(
    '${row['report_created_at'] ?? row['created_at'] ?? row['date'] ?? ''}',
  );
  String _reportType(Map<String, dynamic> row) =>
      WebAnalysisMetrics.preliminary(row)
      ? 'preliminary'
      : WebAnalysisMetrics.isCrop(row)
      ? 'crop'
      : 'land';

  Widget _filter(
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> change,
    IconData icon,
  ) => SizedBox(
    width: 180,
    child: DropdownButtonFormField<String>(
      key: ValueKey('report-$label-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
      ),
      items: [
        for (final e in options.entries)
          DropdownMenuItem(
            value: e.key,
            child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v != null) {
          setState(() => change(v));
        }
      },
    ),
  );

  void _resetFilters() {
    setState(() {
      _dates = 'all';
      _type = 'all';
    });
    _search.clear();
    _records.search('');
  }

  Widget _reportTile(BuildContext context, Map<String, dynamic> row) {
    final kind = _reportType(row);
    final description = kind == 'preliminary'
        ? 'Preliminary assessment'
        : kind == 'crop'
        ? '${WebAnalysisMetrics.cropName(row)} · Crop assessment'
        : 'Land assessment';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: WebPortalColors.tint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.description_outlined, color: WebPortalColors.accent),
      ),
      title: Text(
        '${row['report_title'] ?? row['title'] ?? 'GeoSustain Analysis Report'}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '$description · ${_reportDate(row)?.toIso8601String().split('T').first ?? 'Date unavailable'}',
      ),
      trailing: IconButton(
        tooltip: 'Download PDF',
        icon: Icon(Icons.download_rounded, color: WebPortalColors.accent),
        onPressed: () => _downloadReport(context, row),
      ),
      onTap: () => _downloadReport(context, row),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final loaded = compact
        ? state.generatedReports.take(4).toList()
        : _records.rows;
    final cutoff = _dates == 'all'
        ? null
        : DateTime.now().subtract(Duration(days: int.parse(_dates)));
    final rows = loaded.where((r) {
      final date = _reportDate(r);
      return (_type == 'all' || _reportType(r) == _type) &&
          (cutoff == null || (date != null && !date.isBefore(cutoff)));
    }).toList();
    if (compact) {
      return _WebCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _AnalystSectionTitle(
              'Recent Reports',
              icon: Icons.description_outlined,
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              const Text('No reports generated yet.')
            else
              for (final row in rows) _reportTile(context, row),
          ],
        ),
      );
    }
    final empty = !_records.loading && _records.error == null && rows.isEmpty;
    final filtered = _query.isNotEmpty || _type != 'all' || _dates != 'all';
    final dateFilter = _filter(
      'Report dates',
      _dates,
      const {'all': 'All dates', '30': 'Last 30 days', '90': 'Last 90 days'},
      (v) => _dates = v,
      Icons.calendar_today_outlined,
    );
    final typeFilter = _filter(
      'Report type',
      _type,
      const {
        'all': 'All types',
        'crop': 'Crop assessment',
        'preliminary': 'Preliminary assessment',
        'land': 'Land assessment',
      },
      (v) => _type = v,
      Icons.filter_list_rounded,
    );
    final search = TextField(
      controller: _search,
      textInputAction: TextInputAction.search,
      decoration: const InputDecoration(
        labelText: 'Search all reports',
        hintText: 'Search by place, farm or analysis ID…',
        prefixIcon: Icon(Icons.search, size: 19),
      ),
      onChanged: _records.search,
      onSubmitted: _records.search,
    );
    return _WebCard(
      key: const ValueKey('reports-content-panel'),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AnalystSectionTitle(
            'Assessment and review reports',
            icon: Icons.description_outlined,
            subtitle:
                'Reports saved from a review case appear here. Download a PDF from each saved report.',
          ),
          const SizedBox(height: 14),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (_, box) {
              if (box.maxWidth < 780) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    search,
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [dateFilter, typeFilter],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 12),
                  dateFilter,
                  const SizedBox(width: 12),
                  typeFilter,
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Date and type filters apply to the loaded page.',
                style: TextStyle(fontSize: 11, color: WebPortalColors.muted),
              ),
              TextButton.icon(
                onPressed: _records.loading ? null : () => _records.load(),
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(
                  _records.error == null ? 'Refresh reports' : 'Retry reports',
                ),
              ),
              if (filtered)
                TextButton(
                  onPressed: _resetFilters,
                  child: const Text('Clear filters'),
                ),
            ],
          ),
          if (_records.loading)
            const LinearProgressIndicator(semanticsLabel: 'Loading reports'),
          if (_records.error != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  '${_records.error} ${loaded.isEmpty ? '' : 'Previously loaded reports may be out of date.'}',
                ),
              ),
            ),
          if (empty)
            _WebEmptyState(
              title: filtered
                  ? 'No reports match this view'
                  : 'No reports generated yet',
              message: filtered
                  ? 'Change or clear the filters to see other reports.'
                  : widget.state.isPlanner
                  ? 'Open a submitted case in the Review Inbox and select Save to Reports.'
                  : 'Your assessment reports will appear here once you export them. Open the Analysis Workspace to generate a report.',
              icon: Icons.description_outlined,
              asset: 'assets/images/dashboard/report_illustration.png',
              action: filtered
                  ? OutlinedButton(
                      onPressed: _resetFilters,
                      child: const Text('Clear report filters'),
                    )
                  : FilledButton.icon(
                      onPressed: () => PortalRoutes.go(
                        widget.state.isPlanner
                            ? '/operator/queue'
                            : '/operator/analyze',
                      ),
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: const Text('Open Review Inbox'),
                    ),
            ),
          for (final row in rows) _reportTile(context, row),
          if (_records.loaded) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${rows.length} shown of ${loaded.length} loaded · Page ${_page + 1}',
                  style: TextStyle(fontSize: 11, color: WebPortalColors.muted),
                ),
                TextButton(
                  onPressed: !_records.loading && _page > 0
                      ? () => _records.load(offset: (_page - 1) * 50)
                      : null,
                  child: const Text('Previous'),
                ),
                TextButton(
                  onPressed: !_records.loading && _records.more
                      ? () => _records.load(offset: (_page + 1) * 50)
                      : null,
                  child: const Text('Next'),
                ),
              ],
            ),
          ],
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
    Theme.of(context);
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
