part of '../../main.dart';

class WebOperatorInbox extends StatefulWidget {
  final WebRecordController controller;
  const WebOperatorInbox({super.key, required this.controller});
  @override
  State<WebOperatorInbox> createState() => _WebOperatorInboxState();
}

class _WebOperatorInboxState extends State<WebOperatorInbox> {
  WebRecordController get records => widget.controller;
  Map<String, dynamic>? summary;
  String? summaryError;
  bool cards = true, summaryLoading = false, wasLoading = false;
  int summaryGeneration = 0;
  String summarySignature = '';

  @override
  void initState() {
    super.initState();
    wasLoading = records.loading;
    records.addListener(_recordsChanged);
    _loadSummary();
  }

  void _recordsChanged() {
    final finished = wasLoading && !records.loading;
    wasLoading = records.loading;
    if (finished && records.error == null) _loadSummary();
  }

  @override
  void didUpdateWidget(WebOperatorInbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != records) {
      oldWidget.controller.removeListener(_recordsChanged);
      records.addListener(_recordsChanged);
      wasLoading = records.loading;
      _loadSummary();
    }
  }

  @override
  void dispose() {
    summaryGeneration++;
    records.removeListener(_recordsChanged);
    super.dispose();
  }

  Future<void> _loadSummary() async {
    final request = ++summaryGeneration;
    final filters = {
      for (final key in ['place', 'start', 'end'])
        if ((records.appliedParameters[key] ?? records.parameters[key] ?? '')
            .isNotEmpty)
          key: records.appliedParameters[key] ?? records.parameters[key]!,
    };
    final search = records.loaded ? records.appliedQuery : records.query;
    final signature = jsonEncode([search, filters]);
    setState(() {
      summaryLoading = true;
      summaryError = null;
      if (signature != summarySignature) summary = null;
      summarySignature = signature;
    });
    try {
      final value = await records.api.getRecordPage(
        '/api/operator/overview',
        search: search,
        parameters: filters,
        requestTimeout: const Duration(seconds: 20),
        recoveryAttempts: 1,
      );
      if (mounted && request == summaryGeneration) {
        setState(() => summary = value);
      }
    } catch (_) {
      if (mounted && request == summaryGeneration) {
        setState(() => summaryError = 'Case totals are unavailable.');
      }
    } finally {
      if (mounted && request == summaryGeneration) {
        setState(() => summaryLoading = false);
      }
    }
  }

  void _tab(int index) {
    final filters = Map<String, String>.of(records.parameters)..remove('view');
    records.filter({
      ...filters,
      'status': index == 1
          ? 'needs_information'
          : index == 2
          ? 'all'
          : 'pending',
      if (index == 2) 'view': 'decisions',
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: records,
    builder: (context, _) {
      final tab = records.parameters['view'] == 'decisions'
          ? 2
          : records.parameters['status'] == 'needs_information'
          ? 1
          : 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in [
                (0, Icons.description_outlined, 'Cases'),
                (
                  1,
                  Icons.chat_bubble_outline,
                  'Requests${summary?['information_count'] is num ? ' (${summary!['information_count']})' : ''}',
                ),
                (2, Icons.history_rounded, 'Decision History'),
              ])
                if (tab == item.$1)
                  FilledButton.icon(
                    onPressed: () => _tab(item.$1),
                    icon: Icon(item.$2, size: 18),
                    label: Text(item.$3),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => _tab(item.$1),
                    icon: Icon(item.$2, size: 18),
                    label: Text(item.$3),
                  ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, box) {
              final scale = MediaQuery.textScalerOf(
                context,
              ).scale(1).clamp(1.0, 2.0);
              final columns = math.max(
                1,
                math.min(5, (box.maxWidth / (190 * scale)).floor()),
              );
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final entry in [
                    (
                      'cases',
                      'Total Cases',
                      Icons.description_outlined,
                      const Color(0xFF087B42),
                    ),
                    (
                      'pending_count',
                      'Pending Review',
                      Icons.hourglass_empty,
                      const Color(0xFF9A6500),
                    ),
                    (
                      'verified_count',
                      'Accepted',
                      Icons.check_circle_outline,
                      const Color(0xFF087B42),
                    ),
                    (
                      'information_count',
                      'Needs Information',
                      Icons.info_outline,
                      const Color(0xFFAD3442),
                    ),
                    (
                      'rejected_count',
                      'Rejected',
                      Icons.cancel_outlined,
                      const Color(0xFF7350AD),
                    ),
                  ])
                    SizedBox(
                      width: (box.maxWidth - 12 * (columns - 1)) / columns,
                      child: _WebCard(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: entry.$4.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                entry.$3,
                                color: WebPortalColors.dark
                                    ? Color.lerp(entry.$4, Colors.white, .5)
                                    : entry.$4,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    summary?[entry.$1] is num
                                        ? '${summary![entry.$1]}'
                                        : '\u2014',
                                    style: TextStyle(
                                      fontSize: 25,
                                      fontWeight: FontWeight.w800,
                                      color: WebPortalColors.ink,
                                    ),
                                  ),
                                  Text(
                                    entry.$2,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: WebPortalColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (summaryError != null)
            Row(
              children: [
                Expanded(child: Text(summaryError!)),
                TextButton(
                  onPressed: summaryLoading ? null : _loadSummary,
                  child: const Text('Retry totals'),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Totals match search, place and submission dates across submitted cases. Status and tab filters apply to the list below.',
              style: TextStyle(fontSize: 11, color: WebPortalColors.muted),
            ),
          ),
          _WebCard(
            key: const ValueKey('review-filters-panel'),
            child: _ReviewInboxFilters(controller: records),
          ),
          const SizedBox(height: 16),
          _WebCard(
            key: const ValueKey('review-results-panel'),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 10,
                  spacing: 14,
                  children: [
                    Text(
                      '${tab == 1
                          ? 'Information requests'
                          : tab == 2
                          ? 'Decision history'
                          : 'Submitted cases'} (${records.rows.length})',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: WebPortalColors.ink,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _viewButton(
                          true,
                          Icons.grid_view_outlined,
                          'Card View',
                        ),
                        _viewButton(
                          false,
                          Icons.view_list_outlined,
                          'List View',
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _OperatorPageState(
                  records,
                  illustrateEmpty: true,
                  row: (r) => _ReviewInboxCaseCard(row: r),
                  rowsBuilder: (rows) => LayoutBuilder(
                    builder: (context, box) {
                      final scale = MediaQuery.textScalerOf(
                        context,
                      ).scale(1).clamp(1.0, 2.0);
                      final columns = cards
                          ? math.max(
                              1,
                              math.min(
                                3,
                                (box.maxWidth / (330 * scale)).floor(),
                              ),
                            )
                          : 1;
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          for (final row in rows)
                            SizedBox(
                              width:
                                  (box.maxWidth - 16 * (columns - 1)) / columns,
                              child: _ReviewInboxCaseCard(
                                row: row,
                                list: !cards,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _viewButton(bool value, IconData icon, String title) => cards == value
      ? FilledButton.icon(
          onPressed: () => setState(() => cards = value),
          icon: Icon(icon, size: 17),
          label: Text(title),
        )
      : OutlinedButton.icon(
          onPressed: () => setState(() => cards = value),
          icon: Icon(icon, size: 17),
          label: Text(title),
        );
}

class _ReviewInboxFilters extends StatefulWidget {
  final WebRecordController controller;
  const _ReviewInboxFilters({required this.controller});
  @override
  State<_ReviewInboxFilters> createState() => _ReviewInboxFiltersState();
}

class _ReviewInboxFiltersState extends State<_ReviewInboxFilters> {
  late final search = TextEditingController(text: widget.controller.query);
  late final place = TextEditingController(
    text: widget.controller.parameters['place'],
  );
  late final start = TextEditingController(
    text: widget.controller.parameters['start'],
  );
  late final end = TextEditingController(
    text: widget.controller.parameters['end'],
  );
  late String status = widget.controller.parameters['status'] ?? 'pending';
  late String sort = widget.controller.parameters['sort'] ?? 'oldest';
  String? error;
  String signature = '';

  @override
  void initState() {
    super.initState();
    signature = jsonEncode([
      widget.controller.query,
      widget.controller.parameters,
    ]);
  }

  @override
  void didUpdateWidget(_ReviewInboxFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = jsonEncode([
      widget.controller.query,
      widget.controller.parameters,
    ]);
    if (next != signature) {
      signature = next;
      search.text = widget.controller.query;
      place.text = widget.controller.parameters['place'] ?? '';
      start.text = widget.controller.parameters['start'] ?? '';
      end.text = widget.controller.parameters['end'] ?? '';
      status = widget.controller.parameters['status'] ?? 'pending';
      sort = widget.controller.parameters['sort'] ?? 'oldest';
    }
  }

  @override
  void dispose() {
    for (final controller in [search, place, start, end]) {
      controller.dispose();
    }
    super.dispose();
  }

  void apply({bool reset = false}) {
    if (reset) {
      for (final c in [search, place, start, end]) {
        c.clear();
      }
      status = 'pending';
      sort = 'oldest';
    }
    final from = DateTime.tryParse(start.text.trim());
    final through = DateTime.tryParse(end.text.trim());
    bool valid(String value, DateTime? date) =>
        value.trim().isEmpty ||
        date != null &&
            RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value.trim()) &&
            date.toIso8601String().substring(0, 10) == value.trim();
    if (!valid(start.text, from) ||
        !valid(end.text, through) ||
        from != null && through != null && from.isAfter(through)) {
      setState(
        () => error =
            'Enter valid YYYY-MM-DD dates, with the start on or before the end.',
      );
      return;
    }
    setState(() => error = null);
    widget.controller.query = search.text.trim();
    widget.controller.filter({
      if (!reset && widget.controller.parameters['view'] != null)
        'view': widget.controller.parameters['view']!,
      'status': status,
      'sort': sort,
      if (place.text.trim().isNotEmpty) 'place': place.text.trim(),
      if (start.text.trim().isNotEmpty) 'start': start.text.trim(),
      if (end.text.trim().isNotEmpty) 'end': end.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, box) {
          final available =
              box.maxWidth /
              MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
          final columns = available >= 1100
              ? 7
              : available >= 650
              ? 3
              : available >= 400
              ? 2
              : 1;
          final width = (box.maxWidth - 12 * (columns - 1)) / columns;
          Widget field(Widget child) => SizedBox(width: width, child: child);
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              field(
                TextField(
                  controller: search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => apply(),
                  decoration: const InputDecoration(
                    labelText: 'Search case, farmer or farm',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              field(
                DropdownButtonFormField<String>(
                  key: ValueKey('inbox-status-$status'),
                  initialValue: status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Review status'),
                  items: [
                    for (final s in [
                      'all',
                      'pending',
                      'needs_information',
                      'verified',
                      'rejected',
                    ])
                      DropdownMenuItem(
                        value: s,
                        child: Text(
                          s == 'all' ? 'All statuses' : reviewLabel(s),
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => status = v!),
                ),
              ),
              field(
                DropdownButtonFormField<String>(
                  initialValue: sort,
                  key: ValueKey('inbox-sort-$sort'),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Submission order',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'oldest',
                      child: Text('Oldest first'),
                    ),
                    DropdownMenuItem(
                      value: 'newest',
                      child: Text('Newest first'),
                    ),
                  ],
                  onChanged: (v) => setState(() => sort = v!),
                ),
              ),
              field(
                TextField(
                  controller: place,
                  onSubmitted: (_) => apply(),
                  decoration: const InputDecoration(
                    labelText: 'Place contains',
                  ),
                ),
              ),
              for (final entry in [
                (start, 'From submission date'),
                (end, 'Through submission date'),
              ])
                field(
                  TextField(
                    controller: entry.$1,
                    onSubmitted: (_) => apply(),
                    decoration: InputDecoration(
                      labelText: entry.$2,
                      hintText: 'YYYY-MM-DD',
                      prefixIcon: const Icon(
                        Icons.calendar_today_outlined,
                        size: 17,
                      ),
                    ),
                  ),
                ),
              SizedBox(
                width: width,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    FilledButton.icon(
                      onPressed: widget.controller.loading
                          ? null
                          : () => apply(),
                      icon: const Icon(Icons.filter_alt_outlined, size: 17),
                      label: const Text('Apply Filters'),
                    ),
                    TextButton(
                      onPressed: widget.controller.loading
                          ? null
                          : () => apply(reset: true),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );
}

class _ReviewInboxCaseCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool list;
  const _ReviewInboxCaseCard({required this.row, this.list = false});
  void open() => PortalRoutes.go('/operator/queue?case=${row['case_id']}');
  @override
  Widget build(BuildContext context) {
    final score = analysisNumber(row['compatibility_pct']);
    final scored =
        row['analysis_mode'] != 'preliminary_environmental' &&
        row['is_crop_recommended'] != false &&
        score != null &&
        score >= 0 &&
        score <= 100;
    final boundary = FarmGeometry.fromPayload(row['selected_polygon']);
    return Container(
      key: ValueKey('inbox-case-${row['case_id']}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WebPortalColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WebPortalColors.muted.withValues(alpha: .16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                label: boundary.length >= 3
                    ? 'Saved farm boundary'
                    : 'No saved farm boundary',
                child: BoundaryThumbnail(row, size: 92),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    VerificationStatusBadge(
                      status: '${row['verification_status']}',
                    ),
                    const SizedBox(height: 9),
                    Text(
                      'Case #${row['case_id']}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: WebPortalColors.ink,
                      ),
                    ),
                    Text(
                      '${row['farm_name'] ?? row['place_name'] ?? 'Unnamed farm'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${row['farmer_name'] ?? 'Farmer not recorded'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: WebPortalColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Submitted ${analysisDateText(row['submitted_at'])}',
            style: TextStyle(fontSize: 11, color: WebPortalColors.muted),
          ),
          const Divider(height: 24),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _fact(
                Icons.eco_outlined,
                'Model score',
                scored ? '${score.toStringAsFixed(1)}%' : 'Unavailable',
              ),
              _fact(
                Icons.schedule,
                'Since submission',
                reviewAge(
                  row['submitted_at'],
                ).replaceAll(' since submission', ''),
              ),
              _fact(
                Icons.layers_outlined,
                'Case version',
                row['review_version'] == null
                    ? 'Not recorded'
                    : 'v${row['review_version']}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: open,
                icon: const Icon(Icons.arrow_forward, size: 17),
                label: const Text('Review Case'),
              ),
              OutlinedButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Case #${row['case_id']}'),
                    content: SizedBox(
                      width: 420,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${row['farm_name'] ?? row['place_name'] ?? 'Unnamed farm'}',
                            ),
                            Text(
                              '${row['farmer_name'] ?? 'Farmer not recorded'}',
                            ),
                            Text(reviewLabel(row['verification_status'])),
                            Text(
                              'Submitted ${analysisDateText(row['submitted_at'])}',
                            ),
                            Text(
                              'Model score: ${scored ? '${score.toStringAsFixed(1)}%' : 'Unavailable'}',
                            ),
                            Text(
                              'Case version: ${row['review_version'] ?? 'Not recorded'}',
                            ),
                          ],
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(context);
                          open();
                        },
                        child: const Text('Review Case'),
                      ),
                    ],
                  ),
                ),
                icon: const Icon(Icons.description_outlined, size: 17),
                label: const Text('View Details'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fact(IconData icon, String label, String value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 17, color: WebPortalColors.accent),
      const SizedBox(width: 6),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 10, color: WebPortalColors.muted),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ],
  );
}

class ReviewCaseMapMarker extends StatelessWidget {
  final String caseId, status;
  final int count;
  final VoidCallback onTap;
  const ReviewCaseMapMarker({
    super.key,
    required this.caseId,
    required this.status,
    this.count = 1,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: count > 1
        ? '$count cases at this location'
        : 'Case #$caseId · ${reviewLabel(status)}',
    child: Semantics(
      button: true,
      label: count > 1
          ? 'Open $count cases at this location'
          : 'Open case $caseId, ${reviewLabel(status)}',
      child: SizedBox(
        width: 72,
        height: 72,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(36),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(
                  Icons.location_on,
                  size: 57,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Color(0x66000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                Icon(Icons.location_on, size: 47, color: reviewColor(status)),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF17362A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Text(
                      count > 1 ? '$count' : '#$caseId',
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
