part of '../../main.dart';

Future<void> _exportOperatorReport(
  BuildContext context,
  Map<String, dynamic> data, {
  bool planning = false,
  String scope = '',
}) async {
  try {
    final bytes = await buildOperatorReport(
      data,
      planning: planning,
      scope: scope,
    );
    await Printing.layoutPdf(
      name: planning
          ? 'GeoSustain-planning-summary.pdf'
          : 'GeoSustain-case-${analysisMapValue(data['case'])['id']}.pdf',
      onLayout: (_) async => bytes,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Report could not be exported: ${friendlyErrorMessage(e)}',
          ),
        ),
      );
    }
  }
}

String reviewLabel(dynamic value) => switch ('$value') {
  'pending' => 'Pending review',
  'needs_information' => 'Information requested',
  'verified' => 'Accepted',
  'rejected' => 'Rejected',
  _ => '$value'.replaceAll('_', ' '),
};
Color reviewColor(dynamic value) => switch ('$value') {
  'verified' => const Color(0xff16734b),
  'rejected' => const Color(0xffac3442),
  'needs_information' => const Color(0xff976500),
  _ => const Color(0xff38659a),
};
String reviewAge(dynamic value) {
  final time = DateTime.tryParse('$value');
  if (time == null) return 'Time unavailable';
  final hours = DateTime.now().difference(time).inHours;
  return hours < 24
      ? '${math.max(0, hours)}h since submission'
      : '${hours ~/ 24}d since submission';
}

class _OperatorFilters extends StatefulWidget {
  final WebRecordController controller;
  final bool dense;
  const _OperatorFilters(this.controller, {this.dense = false});
  @override
  State<_OperatorFilters> createState() => _OperatorFiltersState();
}

class _OperatorFiltersState extends State<_OperatorFilters> {
  WebRecordController get controller => widget.controller;
  late final search = TextEditingController(text: controller.query);
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
        floatingLabelBehavior: widget.dense
            ? FloatingLabelBehavior.always
            : FloatingLabelBehavior.auto,
      ),
    ),
    child: _WebFilterRows(
      separateDates: false,
      children: [
        SizedBox(
          width: widget.dense ? 190 : 260,
          child: TextField(
            controller: search,
            decoration: InputDecoration(
              helperText: widget.dense ? ' ' : null,
              labelText: 'Search case, farmer or farm',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: controller.search,
          ),
        ),
        SizedBox(
          width: widget.dense ? 155 : 220,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            key: ValueKey(controller.parameters['status']),
            initialValue: controller.parameters['status'] ?? 'pending',
            decoration: InputDecoration(
              labelText: 'Review status',
              helperText: widget.dense ? ' ' : null,
            ),
            items: [
              for (final value in [
                'all',
                'pending',
                'needs_information',
                'verified',
                'rejected',
              ])
                DropdownMenuItem(
                  value: value,
                  child: Text(
                    value == 'all' ? 'All statuses' : reviewLabel(value),
                  ),
                ),
            ],
            onChanged: (value) =>
                controller.filter({...controller.parameters, 'status': value!}),
          ),
        ),
        SizedBox(
          width: widget.dense ? 135 : 180,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            key: ValueKey(controller.parameters['sort']),
            initialValue: controller.parameters['sort'] ?? 'oldest',
            decoration: InputDecoration(
              labelText: 'Submission order',
              helperText: widget.dense ? ' ' : null,
            ),
            items: const [
              DropdownMenuItem(value: 'oldest', child: Text('Oldest first')),
              DropdownMenuItem(value: 'newest', child: Text('Newest first')),
            ],
            onChanged: (value) =>
                controller.filter({...controller.parameters, 'sort': value!}),
          ),
        ),
        SizedBox(
          width: widget.dense ? 155 : 220,
          child: TextFormField(
            key: ValueKey(controller.parameters['place']),
            initialValue: controller.parameters['place'],
            decoration: const InputDecoration(
              labelText: 'Place contains',
              helperText: 'Press Enter to apply',
            ),
            onFieldSubmitted: (value) => controller.filter({
              ...controller.parameters,
              'place': value.trim(),
            }),
          ),
        ),
        if (controller.path.endsWith('/inbox'))
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              key: ValueKey('view-${controller.parameters['view']}'),
              initialValue: controller.parameters['view'] ?? 'all',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Workload view'),
              items: [
                for (final e in {
                  'all': 'All cases',
                  'preliminary': 'Preliminary assessments',
                  'reviewed_week': 'Reviewed in 7 days',
                  'followups_due': 'Cases with due tasks',
                }.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) =>
                  controller.filter({...controller.parameters, 'view': v!}),
            ),
          ),
        for (final field in ['start', 'end'])
          SizedBox(
            width: 170,
            child: TextFormField(
              key: ValueKey('$field${controller.parameters[field]}'),
              initialValue: controller.parameters[field],
              decoration: InputDecoration(
                labelText:
                    '${field == 'start' ? 'From' : 'Through'} submission date',
                helperText: widget.dense
                    ? 'YYYY-MM-DD · Enter'
                    : 'YYYY-MM-DD; Enter applies',
              ),
              onFieldSubmitted: (value) => controller.filter(
                {
                  ...controller.parameters,
                  if (value.trim().isNotEmpty) field: value.trim(),
                }..removeWhere((k, v) => k == field && value.trim().isEmpty),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(top: widget.dense ? 4 : 0),
          child: OutlinedButton.icon(
            onPressed: controller.loading ? null : () => controller.load(),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ),
      ],
    ),
  );
}

class _WebFilterRows extends StatelessWidget {
  final List<Widget> children;
  final bool separateDates;
  const _WebFilterRows({required this.children, required this.separateDates});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) {
      if (!separateDates) {
        return Wrap(spacing: 12, runSpacing: 12, children: children);
      }
      final fields = children.take(children.length - 3).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (box.maxWidth >= 950)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  if (i != 0) const SizedBox(width: 12),
                  Expanded(flex: i == 0 || i == 3 ? 12 : 10, child: fields[i]),
                ],
              ],
            )
          else
            Wrap(spacing: 12, runSpacing: 12, children: fields),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: children.skip(children.length - 3).toList(),
          ),
        ],
      );
    },
  );
}

class _OperatorPageState extends StatelessWidget {
  final WebRecordController controller;
  final String noun;
  final Widget Function(Map<String, dynamic>) row;
  final bool illustrateEmpty;
  final Widget Function(List<Map<String, dynamic>>)? rowsBuilder;
  const _OperatorPageState(
    this.controller, {
    required this.row,
    this.noun = 'review cases',
    this.illustrateEmpty = false,
    this.rowsBuilder,
  });
  @override
  Widget build(BuildContext context) {
    final empty =
        controller.loaded &&
        controller.rows.isEmpty &&
        !controller.loading &&
        controller.error == null;
    final scope = Text(
      '${controller.rows.length} $noun on page ${controller.offset ~/ controller.limit + 1}. Applied search: ${controller.appliedQuery.isEmpty ? 'none' : controller.appliedQuery}. Status: ${reviewLabel(controller.appliedParameters['status'] ?? 'all')}.',
      textAlign: illustrateEmpty && empty ? TextAlign.center : TextAlign.start,
      style: TextStyle(fontSize: 11, color: WebPortalColors.muted),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.loading)
          const LinearProgressIndicator(semanticsLabel: 'Loading records'),
        if (controller.error != null)
          MaterialBanner(
            content: Text(
              '${controller.error}\n${controller.loaded ? 'Previously loaded records remain visible; filters have not been applied.' : 'Records are unavailable.'}',
            ),
            actions: [
              TextButton(
                onPressed: () => controller.load(),
                child: const Text('Retry'),
              ),
            ],
          ),
        if (controller.loaded && !(illustrateEmpty && empty))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: scope,
          ),
        if (empty)
          if (illustrateEmpty)
            const _WebEmptyState(
              title: 'No review cases found',
              message:
                  'No records match these filters. Change or clear the filters to see other records.',
              icon: Icons.fact_check_outlined,
            )
          else
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No records match these filters. Change or clear the filters to see other records.',
              ),
            ),
        if (rowsBuilder != null) rowsBuilder!(controller.rows),
        if (rowsBuilder == null)
          for (final value in controller.rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: row(value),
            ),
        if (illustrateEmpty && empty) ...[scope, const SizedBox(height: 16)],
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: controller.loading || controller.offset == 0
                  ? null
                  : () => controller.load(
                      offset: math.max(0, controller.offset - controller.limit),
                    ),
              icon: const Icon(Icons.chevron_left, size: 16),
              label: const Text('Previous page'),
            ),
            OutlinedButton.icon(
              onPressed: controller.loading || !controller.more
                  ? null
                  : () => controller.load(
                      offset: controller.offset + controller.limit,
                    ),
              icon: const Icon(Icons.chevron_right, size: 16),
              label: const Text('Next page'),
            ),
          ],
        ),
      ],
    );
  }
}

class WebOperatorOverview extends StatefulWidget {
  final AnalysisState state;
  const WebOperatorOverview({super.key, required this.state});
  @override
  State<WebOperatorOverview> createState() => _WebOperatorOverviewState();
}

class _WebOperatorOverviewState extends State<WebOperatorOverview> {
  Map<String, dynamic>? data;
  String? error;
  bool loading = true;
  int generation = 0;
  final place = TextEditingController();
  String appliedPlace = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    generation++;
    place.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final request = ++generation;
    final filterPlace = place.text.trim();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.state.api.getRecordPage(
        '/api/operator/overview',
        parameters: {'place': filterPlace},
      );
      if (mounted && request == generation) {
        setState(() {
          data = value;
          appliedPlace = filterPlace;
        });
      }
    } catch (e) {
      if (mounted && request == generation) {
        setState(() => error = friendlyErrorMessage(e));
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => _WebCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Review workload',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const Text(
          'Submitted project records. This is an operational review summary, not a citywide farm inventory.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: place,
                decoration: const InputDecoration(labelText: 'Filter place'),
                onSubmitted: (_) => load(),
              ),
            ),
            OutlinedButton(
              onPressed: loading ? null : load,
              child: const Text('Apply / refresh'),
            ),
            OutlinedButton.icon(
              onPressed: loading || error != null || data == null
                  ? null
                  : () => _exportOperatorReport(
                      context,
                      data!,
                      planning: true,
                      scope: appliedPlace,
                    ),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Export planning summary'),
            ),
          ],
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Text(
            '$error Previous values may be stale; refresh before use.',
            style: const TextStyle(color: Colors.red),
          ),
        if (data != null) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final item in [
                ('pending_count', 'Pending', 'pending'),
                (
                  'information_count',
                  'Information requested',
                  'needs_information',
                ),
                ('reviewed_week', 'Reviewed in 7 days', 'all'),
                ('preliminary_count', 'Preliminary cases', 'all'),
                ('followups_due', 'Due follow-ups', 'all'),
              ])
                SizedBox(
                  width: 190,
                  child: Card(
                    child: InkWell(
                      onTap: () => PortalRoutes.go(
                        Uri(
                          path: '/operator/queue',
                          queryParameters: {
                            'status': item.$3,
                            'place': appliedPlace,
                            'view': item.$1 == 'preliminary_count'
                                ? 'preliminary'
                                : item.$1 == 'reviewed_week'
                                ? 'reviewed_week'
                                : item.$1 == 'followups_due'
                                ? 'followups_due'
                                : 'all',
                          },
                        ).toString(),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.$2),
                            Text(
                              '${data![item.$1]}',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text('Open submitted cases'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Text(
            'Oldest pending: ${data!['oldest_pending'] == null ? 'none' : analysisDateText(data!['oldest_pending'])}. Distinct farms: ${data!['distinct_farms']}. Latest parcel area sum: ${analysisNumber(data!['parcel_area_sum_ha'])?.toStringAsFixed(3) ?? 'unavailable'} ha; boundaries may overlap. Farms with unavailable area: ${data!['farms_without_area'] ?? 'unavailable'}.',
          ),
          Text('${data!['scope']}'),
        ],
      ],
    ),
  );
}

class WebReviewWorkbench extends StatefulWidget {
  final AnalysisState state;
  final String reference;
  final bool bySession;
  const WebReviewWorkbench({
    super.key,
    required this.state,
    required this.reference,
    this.bySession = false,
  });
  @override
  State<WebReviewWorkbench> createState() => _WebReviewWorkbenchState();
}

class _WebReviewWorkbenchState extends State<WebReviewWorkbench> {
  Map<String, dynamic>? data;
  String? error;
  bool loading = true, busy = false;
  int generation = 0;
  final notes = TextEditingController(), task = TextEditingController();
  DateTime due = DateTime.now().add(const Duration(days: 7));
  String reason = 'boundary_clarification';
  final checks = {
    'reference': false,
    'geometry': false,
    'coverage': false,
    'limitations': false,
  };
  Map<String, dynamic> get c => analysisMapValue(data?['case']);
  bool get ownSubmission =>
      widget.state.currentUser?['id'] != null &&
      '${c['owner_id']}' == '${widget.state.currentUser?['id']}';
  String get base => '/api/operator/cases/${c['id']}';
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(WebReviewWorkbench oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference ||
        oldWidget.bySession != widget.bySession) {
      data = null;
      notes.clear();
      load();
    }
  }

  @override
  void dispose() {
    generation++;
    notes.dispose();
    task.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.state.api.getRecordPage(
        '/api/operator/cases/${widget.bySession ? 'by-session/' : ''}${widget.reference}',
        requestTimeout: const Duration(seconds: 20),
        recoveryAttempts: 1,
      );
      if (value['case'] is! Map || value['analysis'] is! Map) {
        throw const FormatException(
          'The server returned incomplete case details. Retry loading this case.',
        );
      }
      if (mounted && request == generation) {
        setState(() {
          data = value;
          checks.updateAll((k, v) => false);
        });
      }
    } catch (e) {
      if (mounted && request == generation) {
        setState(
          () => error = e is TimeoutException
              ? 'Case loading took too long. Retry loading this case, or return to the inbox.'
              : friendlyErrorMessage(e),
        );
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  Future<void> action(String path, Map<String, dynamic> body) async {
    if (busy || loading) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await widget.state.api.operatorPost('$base/$path', body);
      if (mounted) setState(() => data = value);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiException && e.statusCode == 409
              ? 'This case changed. Your notes are retained. Reload before making another decision.'
              : friendlyErrorMessage(e),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> decide(String status) async {
    if (ownSubmission) return;
    if (status != 'verified' && notes.text.trim().isEmpty) {
      setState(
        () => error =
            'Add a clear explanation below the evidence before requesting information or rejecting.',
      );
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          status == 'verified'
              ? 'Verify assessment?'
              : '${reviewLabel(status)}?',
        ),
        content: Text(
          'Case #${c['id']}, analysis #${c['current_session_id']}. ${status == 'needs_information' ? 'The farmer can respond with a new linked analysis.' : 'This records a final decision on this submission.'}\n${notes.text.trim()}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm decision'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await action('decision', {
        'status': status,
        'version': c['version'],
        'notes': notes.text.trim(),
        'reason': reason,
        'checklist': checks,
      });
    }
  }

  Future<void> revision(Map<String, dynamic> r) async {
    final request = widget.state.api.getRecordPage(
      '$base/revisions/${r['session_id']}',
      requestTimeout: const Duration(seconds: 20),
      recoveryAttempts: 1,
    );
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Recorded revision ${r['revision']}'),
        content: SizedBox(
          width: 760,
          child: FutureBuilder<Map<String, dynamic>>(
            future: request,
            builder: (context, snapshot) => SingleChildScrollView(
              child: snapshot.hasError
                  ? Text(friendlyErrorMessage(snapshot.error!))
                  : snapshot.hasData
                  ? WebAnalysisEvidence(
                      state: widget.state,
                      record: snapshot.data!,
                      lockMaps: true,
                    )
                  : const Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 12,
        children: [
          OutlinedButton.icon(
            onPressed: () => PortalRoutes.go('/operator/queue'),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Return to inbox'),
          ),
          OutlinedButton(
            onPressed: loading || busy ? null : load,
            child: Text(
              error != null ? 'Retry loading case' : 'Reload current case',
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (loading)
        const LinearProgressIndicator(semanticsLabel: 'Loading review case'),
      if (error != null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Semantics(
            liveRegion: true,
            child: Text(error!, style: const TextStyle(color: Colors.red)),
          ),
        ),
      if (data != null) ...[
        _ReviewCaseHeading(data: data!, state: widget.state),
        const SizedBox(height: 16),
        if (data!['geometry_matches_current'] == false)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'The current farm boundary has changed. Review uses the saved analysis boundary.',
            ),
          ),
        if (c['farm_id'] == null)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Historical submission without a saved-farm association. Preserve its original evidence and review history; do not infer a farm boundary.',
            ),
          ),
        if (ownSubmission)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'You cannot verify or reject your own submission. Another analyst must review it.',
            ),
          ),
        _ReviewEvidenceLayout(
          key: ValueKey(
            'review-evidence-${c['id']}-${c['current_session_id']}',
          ),
          data: data!,
        ),
        const SizedBox(height: 16),
        ReferenceAnalysisContent(
          key: ValueKey(
            'review-analysis-${c['id']}-${c['current_session_id']}',
          ),
          state: widget.state,
          record: analysisMapValue(data!['analysis']),
          showActions: false,
          reviewLayout: true,
          lockMap: true,
        ),
        const SizedBox(height: 16),
        _ReviewDecisionSummary(
          data: data!,
          exportCase: loading || busy || error != null
              ? null
              : () => _exportOperatorReport(context, data!),
          exportAnalysis: loading || busy || error != null
              ? null
              : () async {
                  try {
                    await generateAnalysisPdf(
                      analysisMapValue(data!['analysis']),
                      state: widget.state,
                    );
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(friendlyErrorMessage(e))),
                      );
                    }
                  }
                },
        ),
        const SizedBox(height: 16),
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _AnalystSectionTitle(
                'Review checklist and explanation',
                icon: Icons.fact_check_outlined,
              ),
              const SizedBox(height: 14),
              _AnalystColumns(
                mainFlex: 1,
                sideFlex: 1,
                breakpoint: 850,
                main: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final item in [
                      (
                        'reference',
                        'I reviewed the recorded date, data sources and reference context.',
                      ),
                      (
                        'geometry',
                        'I checked the recorded boundary and any change to the current farm.',
                      ),
                      (
                        'coverage',
                        'I checked coverage, preliminary status and unavailable measurements.',
                      ),
                      (
                        'limitations',
                        'I recorded or acknowledged limitations and the appropriate next step.',
                      ),
                    ])
                      CheckboxListTile(
                        value: checks[item.$1],
                        onChanged:
                            c['status'] != 'pending' ||
                                busy ||
                                loading ||
                                ownSubmission
                            ? null
                            : (v) => setState(() => checks[item.$1] = v!),
                        title: Text(item.$2),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                  ],
                ),
                side: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: notes,
                      maxLength: 500,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Decision explanation / advisory note',
                        helperMaxLines: 3,
                        helperText:
                            'Required for information requests and rejection. Do not include passwords or unnecessary personal data.',
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: reason,
                      decoration: const InputDecoration(labelText: 'Reason'),
                      items: [
                        for (final value in [
                          'boundary_clarification',
                          'missing_evidence',
                          'coverage_limitation',
                          'data_inconsistency',
                          'other',
                        ])
                          DropdownMenuItem(
                            value: value,
                            child: Text(reviewLabel(value)),
                          ),
                      ],
                      onChanged: (v) => setState(() => reason = v!),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (c['status'] == 'pending') ...[
                          FilledButton(
                            onPressed:
                                busy ||
                                    loading ||
                                    ownSubmission ||
                                    !checks.values.every((v) => v)
                                ? null
                                : () => decide('verified'),
                            child: const Text('Verify assessment'),
                          ),
                          OutlinedButton(
                            onPressed: busy || loading || ownSubmission
                                ? null
                                : () => decide('needs_information'),
                            child: const Text('Request information'),
                          ),
                          OutlinedButton(
                            onPressed: busy || loading || ownSubmission
                                ? null
                                : () => decide('rejected'),
                            child: const Text('Reject submission'),
                          ),
                        ],
                        OutlinedButton(
                          onPressed: busy || loading
                              ? null
                              : () async {
                                  if (notes.text.trim().isEmpty) {
                                    setState(
                                      () => error =
                                          'Enter an advisory note first.',
                                    );
                                    return;
                                  }
                                  await action('notes', {
                                    'notes': notes.text.trim(),
                                  });
                                },
                          child: const Text('Send advisory note'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _AnalystSectionTitle(
                'Revisions and decision timeline',
                icon: Icons.history,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                children: [
                  for (final r in analysisListValue(
                    data!['revisions'],
                  ).map(analysisMapValue))
                    OutlinedButton(
                      onPressed: () => revision(r),
                      child: Text(
                        'Revision ${r['revision']} · #${r['session_id']}',
                      ),
                    ),
                ],
              ),
              for (final e in analysisListValue(
                data!['events'],
              ).map(analysisMapValue))
                _ReviewEventTile(event: e),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _AnalystSectionTitle(
                'Follow-up tasks',
                icon: Icons.playlist_add_check_outlined,
              ),
              const SizedBox(height: 8),
              const Text(
                'New tasks are assigned to you. Due reminders appear when Activity is refreshed; background delivery requires a configured provider.',
              ),
              for (final f in analysisListValue(
                data!['followups'],
              ).map(analysisMapValue))
                ListTile(
                  title: Text('${f['title']} · due ${f['due_on']}'),
                  subtitle: Text(
                    '${f['assigned_name']} · ${f['completed_at'] == null ? 'Open' : 'Completed'}',
                  ),
                  trailing:
                      f['completed_at'] == null &&
                          f['assigned_to'] == widget.state.currentUser?['id']
                      ? TextButton(
                          onPressed: busy || loading
                              ? null
                              : () =>
                                    action('followups/${f['id']}/complete', {}),
                          child: const Text('Complete'),
                        )
                      : null,
                ),
              TextField(
                controller: task,
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'Follow-up title'),
              ),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: () async {
                      final value = await showDatePicker(
                        context: context,
                        initialDate: due,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 365),
                        ),
                        lastDate: DateTime.now().add(
                          const Duration(days: 3650),
                        ),
                      );
                      if (value != null && mounted) setState(() => due = value);
                    },
                    child: Text(
                      'Due ${due.toIso8601String().substring(0, 10)}',
                    ),
                  ),
                  FilledButton(
                    onPressed: busy || loading
                        ? null
                        : () async {
                            if (task.text.trim().isEmpty) {
                              setState(() => error = 'Add a follow-up title.');
                              return;
                            }
                            await action('followups', {
                              'title': task.text.trim(),
                              'due_on': due.toIso8601String().substring(0, 10),
                            });
                          },
                    child: const Text('Create follow-up'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ],
  );
}

class OperatorEvidenceMap extends StatefulWidget {
  final Map<String, dynamic> record;
  const OperatorEvidenceMap({super.key, required this.record});
  @override
  State<OperatorEvidenceMap> createState() => _OperatorEvidenceMapState();
}

class _OperatorEvidenceMapState extends State<OperatorEvidenceMap> {
  String layer = 'ndvi';
  static const labels = {
    'ndvi': 'NDVI (index)',
    'rainfall': 'Recorded rainfall (mm; see source period)',
    'elevation': 'Elevation (m)',
    'slope': 'Slope',
    'crop_suitability': 'Stored grid index (not an agronomic grade)',
  };
  @override
  Widget build(BuildContext context) {
    if (widget.record['spatial_assessment'] != null) {
      return SpatialRasterCard(record: widget.record, lockMap: true);
    }
    final labels = <String, String>{
      ..._OperatorEvidenceMapState.labels,
      if (widget.record['climate_contract_version'] ==
          'climate-annual-five-year-v2')
        'rainfall': 'Annual rainfall (5-year mean, mm/year)',
      'slope': analysisNumber(widget.record['slope_pct']) != null
          ? 'Slope (%)'
          : 'Slope (unit not recorded)',
    };
    final grid = analysisListValue(
      widget.record['heatmap_grid'],
    ).map(analysisMapValue).toList();
    final values =
        grid
            .map((r) => analysisNumber(r[layer]))
            .whereType<double>()
            .where((v) => v.isFinite)
            .toList()
          ..sort();
    final polygon = FarmGeometry.fromPayload(widget.record['selected_polygon']);
    final center = polygon.isEmpty
        ? LatLng(
            analysisNumber(widget.record['center_lat']) ??
                panaboCenter.latitude,
            analysisNumber(widget.record['center_lon']) ??
                panaboCenter.longitude,
          )
        : FarmGeometry.centroid(polygon) ?? polygon.first;
    Color color(dynamic value) {
      final t = observedPosition(analysisNumber(value), values);
      return t == null
          ? Colors.grey
          : Color.lerp(const Color(0xffd9e5f3), const Color(0xff294a82), t)!;
    }

    return _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AnalystSectionTitle(
            'Recorded boundary and sampled measurements',
            icon: Icons.layers_outlined,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: layer,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Recorded layer'),
            items: [
              for (final e in labels.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => layer = v!),
          ),
          const SizedBox(height: 12),
          Text(
            values.isEmpty
                ? 'Layer unavailable. The boundary remains visible; no measurement is inferred.'
                : 'Observed range ${values.first.toStringAsFixed(3)} to ${values.last.toStringAsFixed(3)}. Light to dark blue = lower to higher recorded values; gray = missing. Equal values use one neutral blue. Colors are not suitability grades.',
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 360,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ContextMap(
                key: ValueKey(
                  'review-map-${widget.record['session_id']}-${jsonEncode(widget.record['selected_polygon'])}',
                ),
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 16,
                  initialCameraFit: polygon.length >= 3
                      ? CameraFit.coordinates(
                          coordinates: polygon,
                          padding: const EdgeInsets.all(48),
                        )
                      : null,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  if (polygon.length >= 3)
                    PolygonLayer(
                      polygons: [
                        Polygon(
                          points: polygon,
                          color: Colors.blueGrey.withValues(alpha: .08),
                          borderColor: Colors.blueGrey,
                          borderStrokeWidth: 3,
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      for (final r in grid)
                        if (analysisNumber(r['lat']) != null &&
                            analysisNumber(r['lng'] ?? r['lon']) != null)
                          Marker(
                            point: LatLng(
                              analysisNumber(r['lat'])!,
                              analysisNumber(r['lng'] ?? r['lon'])!,
                            ),
                            width: 22,
                            height: 22,
                            child: Tooltip(
                              message:
                                  '${labels[layer]}: ${r[layer] ?? 'Unavailable'}',
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: color(r[layer]),
                                  border: Border.all(color: Colors.black54),
                                ),
                              ),
                            ),
                          ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            polygon.length >= 3
                ? 'Map fixed to the saved boundary. Use Map or Satellite to change the background.'
                : 'Saved boundary unavailable. Map is locked; background imagery is context only.',
          ),
          const Text(
            'Basemap is navigation context. Samples and boundary come from this saved analysis; current imagery is not a new measurement.',
          ),
        ],
      ),
    );
  }
}

class WebAnalystPlanningMap extends StatefulWidget {
  final AnalysisState state;
  final WebRecordController controller;
  final MapController mapController;
  const WebAnalystPlanningMap({
    super.key,
    required this.state,
    required this.controller,
    required this.mapController,
  });

  @override
  State<WebAnalystPlanningMap> createState() => _WebAnalystPlanningMapState();
}

class _WebAnalystPlanningMapState extends State<WebAnalystPlanningMap> {
  @override
  Widget build(BuildContext context) => WebOperatorMap(
    state: widget.state,
    controller: widget.controller,
    mapController: widget.mapController,
  );
}

class WebOperatorMap extends StatefulWidget {
  final AnalysisState state;
  final WebRecordController controller;
  final MapController mapController;
  const WebOperatorMap({
    super.key,
    required this.state,
    required this.controller,
    required this.mapController,
  });
  @override
  State<WebOperatorMap> createState() => _WebOperatorMapState();
}

class _WebOperatorMapState extends State<WebOperatorMap> {
  WebRecordController get records => widget.controller;
  MapController get map => widget.mapController;
  bool _markers = true, _boundaries = true, _basemap = true, _ready = false;
  LatLng _viewCenter = panaboCenter;
  double _zoom = 12;
  @override
  void initState() {
    super.initState();
    if (!records.loaded && !records.loading) records.load();
  }

  LatLng center(Map<String, dynamic> r) => LatLng(
    analysisNumber(r['center_lat']) ?? panaboCenter.latitude,
    analysisNumber(r['center_lon']) ?? panaboCenter.longitude,
  );

  void openCases(List<Map<String, dynamic>> cases) {
    if (cases.length == 1) {
      PortalRoutes.go('/operator/queue?case=${cases.single['case_id']}');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cases at this location'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final row in cases)
                  ListTile(
                    leading: Icon(
                      Icons.location_on,
                      color: reviewColor(row['verification_status']),
                    ),
                    title: Text(
                      'Case #${row['case_id']} · ${row['farm_name'] ?? 'Submitted farm'}',
                    ),
                    subtitle: Text(reviewLabel(row['verification_status'])),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(context);
                      PortalRoutes.go('/operator/queue?case=${row['case_id']}');
                    },
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
        ],
      ),
    );
  }

  Widget _layer(
    String label,
    IconData icon,
    bool checked,
    ValueChanged<bool> change,
  ) => CheckboxListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    controlAffinity: ListTileControlAffinity.leading,
    value: checked,
    onChanged: (v) => setState(() => change(v ?? false)),
    title: Row(
      children: [
        Icon(icon, size: 17, color: WebPortalColors.accent),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: records,
    builder: (_, _) {
      final markerGroups = <String, List<Map<String, dynamic>>>{};
      for (final row in records.rows) {
        final point = center(row);
        final key =
            '${point.latitude.toStringAsFixed(6)},${point.longitude.toStringAsFixed(6)}';
        markerGroups.putIfAbsent(key, () => []).add(row);
      }
      final polygons = records.rows
          .where(
            (r) => FarmGeometry.fromPayload(r['selected_polygon']).length >= 3,
          )
          .toList();
      final areas = records.rows.map(_analystArea).whereType<double>().toList();
      final totalArea = areas.fold<double>(0, (a, b) => a + b);
      final farms = records.rows
          .where((r) => r['farm_id'] != null)
          .map((r) => r['farm_id'])
          .toSet()
          .length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AnalystMetricGrid(
            children: [
              _AnalystMetric(
                icon: Icons.folder_shared_outlined,
                label: 'Loaded Project Cases',
                value: '${records.rows.length}',
                caption: 'Current filtered page · up to 50',
              ),
              _AnalystMetric(
                icon: Icons.map_outlined,
                label: 'Mapped Area',
                value: areas.isEmpty
                    ? 'Not recorded'
                    : '${totalArea.toStringAsFixed(2)} ha',
                caption: '${areas.length} loaded cases with saved area',
              ),
              _AnalystMetric(
                icon: Icons.schedule_rounded,
                label: 'Pending Review',
                value:
                    '${records.rows.where((r) => r['verification_status'] == 'pending').length}',
                caption: 'Current filtered page',
                color: const Color(0xFFAD7200),
              ),
              _AnalystMetric(
                icon: Icons.check_circle_outline_rounded,
                label: 'Accepted Cases',
                value:
                    '${records.rows.where((r) => r['verification_status'] == 'verified').length}',
                caption: 'Review status · loaded cases',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _AnalystColumns(
            mainFlex: 4,
            sideFlex: 1,
            breakpoint: 1000,
            equalHeight: true,
            main: WebStretchCards(
              spacing: 12,
              children: [
                _WebCard(
                  key: const ValueKey('planning-filters-panel'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _AnalystSectionTitle(
                        'Planning map · submitted project cases',
                        icon: Icons.map_outlined,
                        subtitle:
                            'Up to 50 cases per page. Markers are parcel centers, not a citywide farm or infrastructure inventory.',
                      ),
                      const SizedBox(height: 16),
                      _OperatorFilters(records, dense: true),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: !_ready
                                ? null
                                : () => records.filter({
                                    ...records.parameters,
                                    'west': '${map.camera.visibleBounds.west}',
                                    'east': '${map.camera.visibleBounds.east}',
                                    'south':
                                        '${map.camera.visibleBounds.south}',
                                    'north':
                                        '${map.camera.visibleBounds.north}',
                                  }),
                            icon: const Icon(Icons.search, size: 16),
                            label: const Text('Search this map area (centers)'),
                          ),
                          TextButton.icon(
                            onPressed: () => records.filter(
                              Map.of(records.parameters)..removeWhere(
                                (k, v) => [
                                  'west',
                                  'east',
                                  'north',
                                  'south',
                                ].contains(k),
                              ),
                            ),
                            icon: const Icon(
                              Icons.layers_clear_outlined,
                              size: 16,
                            ),
                            label: const Text('Clear map bounds'),
                          ),
                        ],
                      ),
                      if (records.parameters.containsKey('west'))
                        const Text(
                          'Map bounds are active. Panning alone does not change the applied results.',
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Loaded distinct farms: $farms. Multiple cases may refer to one farm.',
                        style: TextStyle(
                          color: WebPortalColors.muted,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 14,
                        runSpacing: 7,
                        children: [
                          for (final status in [
                            'pending',
                            'needs_information',
                            'verified',
                            'rejected',
                          ])
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 9,
                                  color: reviewColor(status),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  reviewLabel(status),
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                ClipRRect(
                  key: const ValueKey('planning-map-panel'),
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    height: 480,
                    child: Stack(
                      children: [
                        ContextMap(
                          basemapVisible: _basemap,
                          mapController: map,
                          options: MapOptions(
                            initialCenter: panaboCenter,
                            initialZoom: 12,
                            onMapReady: () {
                              if (mounted) setState(() => _ready = true);
                            },
                            onPositionChanged: (position, gesture) {
                              if (mounted) {
                                setState(() {
                                  _viewCenter = position.center;
                                  _zoom = position.zoom;
                                });
                              }
                            },
                          ),
                          children: [
                            if (_boundaries)
                              PolygonLayer(
                                polygons: [
                                  for (final r in polygons)
                                    Polygon(
                                      points: FarmGeometry.fromPayload(
                                        r['selected_polygon'],
                                      ),
                                      color: reviewColor(
                                        r['verification_status'],
                                      ).withValues(alpha: .15),
                                      borderColor: reviewColor(
                                        r['verification_status'],
                                      ),
                                      borderStrokeWidth: 2,
                                    ),
                                ],
                              ),
                            if (_markers)
                              MarkerLayer(
                                markers: [
                                  for (final group in markerGroups.values)
                                    Marker(
                                      point: center(group.first),
                                      width: 72,
                                      height: 72,
                                      alignment: Marker.computePixelAlignment(
                                        width: 72,
                                        height: 72,
                                        left: 36,
                                        top: 60,
                                      ),
                                      child: ReviewCaseMapMarker(
                                        caseId: '${group.first['case_id']}',
                                        status:
                                            '${group.first['verification_status']}',
                                        count: group.length,
                                        onTap: () => openCases(group),
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        ),
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Material(
                            color: WebPortalColors.surface,
                            elevation: 2,
                            borderRadius: BorderRadius.circular(9),
                            child: Column(
                              children: [
                                IconButton(
                                  tooltip: 'Zoom in',
                                  onPressed: !_ready
                                      ? null
                                      : () => map.move(
                                          _viewCenter,
                                          math.min(18.0, _zoom + 1),
                                        ),
                                  icon: const Icon(Icons.add, size: 20),
                                ),
                                IconButton(
                                  tooltip: 'Zoom out',
                                  onPressed: !_ready
                                      ? null
                                      : () => map.move(
                                          _viewCenter,
                                          math.max(3.0, _zoom - 1),
                                        ),
                                  icon: const Icon(Icons.remove, size: 20),
                                ),
                                IconButton(
                                  tooltip: 'Center on Panabo City',
                                  onPressed: !_ready
                                      ? null
                                      : () => map.move(panaboCenter, 12),
                                  icon: const Icon(
                                    Icons.my_location_rounded,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            side: WebStretchCards(
              children: [
                _WebCard(
                  key: const ValueKey('planning-layers-panel'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _AnalystSectionTitle(
                        'Map Layers',
                        icon: Icons.layers_outlined,
                      ),
                      const SizedBox(height: 10),
                      _layer(
                        'Project cases',
                        Icons.location_on_outlined,
                        _markers,
                        (v) => _markers = v,
                      ),
                      _layer(
                        'Farm boundaries',
                        Icons.crop_free_rounded,
                        _boundaries,
                        (v) => _boundaries = v,
                      ),
                      _layer(
                        'Basemap imagery',
                        Icons.map_outlined,
                        _basemap,
                        (v) => _basemap = v,
                      ),
                      const Divider(),
                      Text(
                        'Terrain, NDVI and soil evidence are available inside each case when saved. Open a case to inspect its recorded layers.',
                        style: TextStyle(
                          fontSize: 11,
                          color: WebPortalColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                _WebCard(
                  key: const ValueKey('planning-info-panel'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _AnalystSectionTitle(
                        'Map Information',
                        icon: Icons.info_outline,
                      ),
                      const SizedBox(height: 18),
                      for (final entry in [
                        (
                          Icons.place_outlined,
                          'Current view',
                          '${_viewCenter.latitude.toStringAsFixed(4)}, ${_viewCenter.longitude.toStringAsFixed(4)}',
                        ),
                        (
                          Icons.folder_outlined,
                          'Loaded cases',
                          '${records.rows.length} (current filter)',
                        ),
                        (
                          Icons.crop_free_rounded,
                          'Saved boundaries',
                          '${polygons.length} in loaded cases',
                        ),
                        (
                          Icons.layers_outlined,
                          'Visible layers',
                          '${[_markers, _boundaries, _basemap].where((v) => v).length} of 3 enabled',
                        ),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                entry.$1,
                                size: 18,
                                color: WebPortalColors.muted,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.$2,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      entry.$3,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: WebPortalColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _WebCard(
            padding: const EdgeInsets.all(14),
            child: _OperatorPageState(
              records,
              noun: 'map cases',
              row: (r) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.location_on_outlined,
                  color: reviewColor(r['verification_status']),
                ),
                title: Text(
                  'Case #${r['case_id']} · ${r['farm_name'] ?? r['place_name']}',
                ),
                subtitle: Text(
                  '${reviewLabel(r['verification_status'])} · submitted ${analysisDateText(r['submitted_at'])}',
                ),
                trailing: const Icon(Icons.arrow_forward, size: 18),
                onTap: () =>
                    PortalRoutes.go('/operator/queue?case=${r['case_id']}'),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class FarmerReviewCasesPage extends StatefulWidget {
  final AnalysisState state;
  const FarmerReviewCasesPage({super.key, required this.state});
  @override
  State<FarmerReviewCasesPage> createState() => _FarmerReviewCasesPageState();
}

class _FarmerReviewCasesPageState extends State<FarmerReviewCasesPage> {
  late final records = WebRecordController(
    widget.state.api,
    '/api/mobile/review-cases',
    'cases',
  );
  @override
  void initState() {
    super.initState();
    records.load();
  }

  @override
  void dispose() {
    records.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My review cases')),
    body: ListenableBuilder(
      listenable: records,
      builder: (_, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _OperatorPageState(
          records,
          row: (r) => Card(
            child: ListTile(
              title: Text(
                'Case #${r['case_id']} · ${r['farm_name'] ?? 'Farm'}',
              ),
              subtitle: Text(reviewLabel(r['status'])),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FarmerReviewResponsePage(
                    state: widget.state,
                    caseId: (r['case_id'] as num).toInt(),
                  ),
                ),
              ).then((_) => records.load()),
            ),
          ),
        ),
      ),
    ),
  );
}

class FarmerReviewResponsePage extends StatefulWidget {
  final AnalysisState state;
  final int caseId;
  const FarmerReviewResponsePage({
    super.key,
    required this.state,
    required this.caseId,
  });
  @override
  State<FarmerReviewResponsePage> createState() =>
      _FarmerReviewResponsePageState();
}

class _FarmerReviewResponsePageState extends State<FarmerReviewResponsePage> {
  Map<String, dynamic>? data;
  List<Map<String, dynamic>> choices = [];
  int? selected;
  String? error;
  bool loading = true, busy = false;
  final notes = TextEditingController();
  String get base => '/api/mobile/review-cases/${widget.caseId}';
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.state.api.getRecordPage(base);
      final candidates =
          analysisMapValue(value['case'])['status'] == 'needs_information'
          ? await widget.state.api.getRecordPage('$base/candidates')
          : <String, dynamic>{};
      if (mounted) {
        setState(() {
          data = value;
          choices = analysisListValue(
            candidates['analyses'],
          ).map(analysisMapValue).toList();
          selected = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = analysisMapValue(data?['case']);
    return Scaffold(
      appBar: AppBar(
        title: Text('Review case #${widget.caseId}'),
        actions: [
          IconButton(
            tooltip: 'Refresh case',
            onPressed: loading || busy ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (loading || busy) const LinearProgressIndicator(),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
          if (data != null) ...[
            Text(
              reviewLabel(c['status']),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            for (final e in analysisListValue(
              data!['events'],
            ).map(analysisMapValue))
              ListTile(
                title: Text(reviewLabel(e['kind'])),
                subtitle: Text(
                  '${e['notes'] ?? ''}\n${analysisDateText(e['created_at'])}',
                ),
              ),
            if (c['status'] == 'needs_information' && c['farm_id'] == null)
              const Text(
                'This historical case has no saved farm to link a correction to. Create or open a saved farm, analyze its current boundary and submit a new formal case. The original case and notes remain in your history.',
              ),
            if (c['status'] == 'needs_information' && c['farm_id'] != null) ...[
              const Text(
                'Correct the farm or provide the requested evidence, run a new analysis of this same farm, then select it here. Your earlier analysis stays in the review history.',
              ),
              if (c['farm_id'] != null)
                OutlinedButton(
                  onPressed: loading || busy
                      ? null
                      : () async {
                          try {
                            final farm = await widget.state.api.getFarm(
                              (c['farm_id'] as num).toInt(),
                            );
                            if (!context.mounted) return;
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FarmDetailsPage(
                                  state: widget.state,
                                  farm: farm,
                                ),
                              ),
                            );
                            if (mounted) load();
                          } catch (e) {
                            if (mounted) {
                              setState(() => error = friendlyErrorMessage(e));
                            }
                          }
                        },
                  child: const Text('Open farm to correct / analyze'),
                ),
              if (choices.isEmpty)
                const Text(
                  'No new unsubmitted analysis is available for this farm yet. Run the corrected analysis and refresh this case.',
                ),
              DropdownButtonFormField<int>(
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'New analysis for this farm',
                ),
                items: [
                  for (final r in choices)
                    DropdownMenuItem(
                      value: (r['session_id'] as num).toInt(),
                      child: Text(
                        '#${r['session_id']} · ${analysisDateText(r['analyzed_at'])}',
                      ),
                    ),
                ],
                onChanged: busy || loading
                    ? null
                    : (v) => setState(() => selected = v),
              ),
              TextField(
                controller: notes,
                maxLength: 500,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Describe your correction',
                ),
              ),
              FilledButton(
                onPressed: busy || loading || selected == null
                    ? null
                    : () async {
                        if (notes.text.trim().isEmpty) {
                          setState(
                            () => error =
                                'Describe the correction before resubmitting.',
                          );
                          return;
                        }
                        setState(() => busy = true);
                        try {
                          await widget.state.api
                              .operatorPost('$base/resubmit', {
                                'version': c['version'],
                                'session_id': selected,
                                'notes': notes.text.trim(),
                              });
                          if (mounted) await load();
                        } catch (e) {
                          if (mounted) {
                            setState(() => error = friendlyErrorMessage(e));
                          }
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: const Text('Submit linked revision for review'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
