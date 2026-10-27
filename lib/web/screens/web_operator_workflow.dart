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
  const _OperatorFilters(this.controller);
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
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      SizedBox(
        width: 260,
        child: TextField(
          controller: search,
          decoration: const InputDecoration(
            labelText: 'Search case, farmer or farm',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: controller.search,
        ),
      ),
      SizedBox(
        width: 220,
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          key: ValueKey(controller.parameters['status']),
          initialValue: controller.parameters['status'] ?? 'pending',
          decoration: const InputDecoration(labelText: 'Review status'),
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
        width: 180,
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          key: ValueKey(controller.parameters['sort']),
          initialValue: controller.parameters['sort'] ?? 'oldest',
          decoration: const InputDecoration(labelText: 'Submission order'),
          items: const [
            DropdownMenuItem(value: 'oldest', child: Text('Oldest first')),
            DropdownMenuItem(value: 'newest', child: Text('Newest first')),
          ],
          onChanged: (value) =>
              controller.filter({...controller.parameters, 'sort': value!}),
        ),
      ),
      SizedBox(
        width: 220,
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
          width: 230,
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
              helperText: 'YYYY-MM-DD; Enter applies',
            ),
            onFieldSubmitted: (value) => controller.filter(
              {
                ...controller.parameters,
                if (value.trim().isNotEmpty) field: value.trim(),
              }..removeWhere((k, v) => k == field && value.trim().isEmpty),
            ),
          ),
        ),
      OutlinedButton.icon(
        onPressed: controller.loading ? null : () => controller.load(),
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh'),
      ),
    ],
  );
}

class _OperatorPageState extends StatelessWidget {
  final WebRecordController controller;
  final String noun;
  final Widget Function(Map<String, dynamic>) row;
  const _OperatorPageState(
    this.controller, {
    required this.row,
    this.noun = 'review cases',
  });
  @override
  Widget build(BuildContext context) => Column(
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
      if (controller.loaded)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '${controller.rows.length} $noun on page ${controller.offset ~/ controller.limit + 1}. Applied search: ${controller.appliedQuery.isEmpty ? 'none' : controller.appliedQuery}. Status: ${reviewLabel(controller.appliedParameters['status'] ?? 'all')}.',
          ),
        ),
      if (controller.loaded &&
          controller.rows.isEmpty &&
          !controller.loading &&
          controller.error == null)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No records match these filters. Change or clear the filters to see other records.',
          ),
        ),
      for (final value in controller.rows)
        Padding(padding: const EdgeInsets.only(bottom: 12), child: row(value)),
      Wrap(
        spacing: 12,
        children: [
          OutlinedButton(
            onPressed: controller.loading || controller.offset == 0
                ? null
                : () => controller.load(
                    offset: math.max(0, controller.offset - controller.limit),
                  ),
            child: const Text('Previous page'),
          ),
          OutlinedButton(
            onPressed: controller.loading || !controller.more
                ? null
                : () => controller.load(
                    offset: controller.offset + controller.limit,
                  ),
            child: const Text('Next page'),
          ),
        ],
      ),
    ],
  );
}

class WebOperatorInbox extends StatelessWidget {
  final WebRecordController controller;
  const WebOperatorInbox({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (_, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Submitted cases',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const Text(
                'Oldest submissions first. Acceptance records an analyst decision; it does not certify an unmeasured soil value.',
              ),
              const SizedBox(height: 16),
              _OperatorFilters(controller),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _OperatorPageState(
          controller,
          row: (r) => Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(18),
              isThreeLine: true,
              title: Text(
                'Case #${r['case_id']} · ${r['farm_name'] ?? r['place_name'] ?? 'Unnamed farm'}',
              ),
              subtitle: Text(
                '${r['farmer_name']} · ${reviewLabel(r['verification_status'])}\nSubmitted ${analysisDateText(r['submitted_at'])} · ${reviewAge(r['submitted_at'])}\n'
                '${r['analysis_mode'] == 'preliminary_environmental' ? 'Preliminary screening · model score unavailable' : 'Model score: ${r['compatibility_pct'] == null ? 'unavailable' : '${r['compatibility_pct']}%'}'} · analyzed ${analysisDateText(r['analyzed_at'])}',
              ),
              trailing: const Icon(Icons.arrow_forward),
              onTap: () =>
                  PortalRoutes.go('/operator/queue?case=${r['case_id']}'),
            ),
          ),
        ),
      ],
    ),
  );
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
  String get base => '/api/operator/cases/${c['id']}';
  @override
  void initState() {
    super.initState();
    load();
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
      );
      if (mounted && request == generation) {
        setState(() {
          data = value;
          checks.updateAll((k, v) => false);
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
        title: Text('${reviewLabel(status)}?'),
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
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Recorded revision ${r['revision']}'),
        content: SizedBox(
          width: 760,
          child: FutureBuilder<Map<String, dynamic>>(
            future: widget.state.api.getRecordPage(
              '$base/revisions/${r['session_id']}',
            ),
            builder: (context, snapshot) => SingleChildScrollView(
              child: snapshot.hasError
                  ? Text(friendlyErrorMessage(snapshot.error!))
                  : snapshot.hasData
                  ? WebAnalysisEvidence(
                      state: widget.state,
                      record: snapshot.data!,
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
            child: const Text('Reload current case'),
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
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Case #${c['id']} · ${reviewLabel(c['status'])}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Current analysis #${c['current_session_id']} · case version ${c['version']} · ${reviewAge(c['submitted_at'])}',
              ),
              Text(
                'Recorded boundary vs current farm: ${data!['geometry_matches_current'] == true
                    ? 'same coordinates; farm metadata may have changed'
                    : data!['geometry_matches_current'] == false
                    ? 'CHANGED — this review uses the recorded boundary'
                    : 'current farm unavailable'}. Current farm version ${data!['current_farm_version'] ?? 'unavailable'}.',
              ),
              const Text(
                'Evidence below is the saved analysis snapshot. Acceptance does not replace a soil test or remove recorded limitations.',
              ),
              OutlinedButton.icon(
                onPressed: loading || error != null
                    ? null
                    : () => _exportOperatorReport(context, data!),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Export case report'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OperatorEvidenceMap(record: analysisMapValue(data!['analysis'])),
        const SizedBox(height: 16),
        WebAnalysisEvidence(
          state: widget.state,
          record: analysisMapValue(data!['analysis']),
        ),
        const SizedBox(height: 16),
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Review checklist and explanation',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
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
                  onChanged: c['status'] != 'pending' || busy || loading
                      ? null
                      : (v) => setState(() => checks[item.$1] = v!),
                  title: Text(item.$2),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              TextField(
                controller: notes,
                maxLength: 500,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Decision explanation / advisory note',
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
                          busy || loading || !checks.values.every((v) => v)
                          ? null
                          : () => decide('verified'),
                      child: const Text('Accept review'),
                    ),
                    OutlinedButton(
                      onPressed: busy || loading
                          ? null
                          : () => decide('needs_information'),
                      child: const Text('Request information'),
                    ),
                    OutlinedButton(
                      onPressed: busy || loading
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
                                () => error = 'Enter an advisory note first.',
                              );
                              return;
                            }
                            await action('notes', {'notes': notes.text.trim()});
                          },
                    child: const Text('Send advisory note'),
                  ),
                ],
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
              const Text(
                'Revisions and decision timeline',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
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
                ListTile(
                  title: Text(
                    '${reviewLabel(e['kind'])} · ${analysisDateText(e['created_at'])}',
                  ),
                  subtitle: Text(
                    '${e['actor_name'] ?? 'Recorded system event'} · analysis #${e['session_id']}\n${e['notes'] ?? ''}${e['reason'] == null ? '' : '\nReason: ${reviewLabel(e['reason'])}'}',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Follow-up tasks',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
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
    'slope': 'Slope (degrees)',
    'crop_suitability': 'Stored grid index (not an agronomic grade)',
  };
  @override
  Widget build(BuildContext context) {
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
          const Text(
            'Recorded boundary and sampled measurements',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
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
            height: 340,
            child: FlutterMap(
              key: ValueKey(widget.record['session_id']),
              options: MapOptions(initialCenter: center, initialZoom: 15),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.geosustain.mobile',
                ),
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
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),
          const Text(
            'Basemap is navigation context. Samples and boundary come from this saved analysis; current imagery is not a new measurement.',
          ),
        ],
      ),
    );
  }
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
  @override
  void initState() {
    super.initState();
    if (!records.loaded && !records.loading) records.load();
  }

  LatLng center(Map<String, dynamic> r) => LatLng(
    analysisNumber(r['center_lat']) ?? panaboCenter.latitude,
    analysisNumber(r['center_lon']) ?? panaboCenter.longitude,
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: records,
    builder: (_, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Planning map · submitted project cases',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const Text(
                'Up to 50 cases per page. Colors show review status. Markers are parcel centers; this is not a citywide farm or infrastructure inventory. Open a case for its saved measurements and layer availability.',
              ),
              const SizedBox(height: 12),
              _OperatorFilters(records),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: () => records.filter({
                      ...records.parameters,
                      'west': '${map.camera.visibleBounds.west}',
                      'east': '${map.camera.visibleBounds.east}',
                      'south': '${map.camera.visibleBounds.south}',
                      'north': '${map.camera.visibleBounds.north}',
                    }),
                    child: const Text('Search this map area (centers)'),
                  ),
                  TextButton(
                    onPressed: () => records.filter(
                      Map.of(records.parameters)..removeWhere(
                        (k, v) =>
                            ['west', 'east', 'north', 'south'].contains(k),
                      ),
                    ),
                    child: const Text('Clear map bounds'),
                  ),
                ],
              ),
              if (records.parameters.containsKey('west'))
                const Text(
                  'Map bounds are active. Panning alone does not change the applied results.',
                ),
              Text(
                'Loaded distinct farms: ${records.rows.where((r) => r['farm_id'] != null).map((r) => r['farm_id']).toSet().length}. Multiple cases may refer to one farm.',
              ),
              Wrap(
                spacing: 16,
                children: [
                  for (final s in [
                    'pending',
                    'needs_information',
                    'verified',
                    'rejected',
                  ])
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 12, color: reviewColor(s)),
                        const SizedBox(width: 4),
                        Text(reviewLabel(s)),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 450,
          child: FlutterMap(
            mapController: map,
            options: MapOptions(initialCenter: panaboCenter, initialZoom: 12),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.geosustain.mobile',
              ),
              PolygonLayer(
                polygons: [
                  for (final r in records.rows)
                    if (FarmGeometry.fromPayload(
                          r['selected_polygon'],
                        ).length >=
                        3)
                      Polygon(
                        points: FarmGeometry.fromPayload(r['selected_polygon']),
                        color: reviewColor(
                          r['verification_status'],
                        ).withValues(alpha: .15),
                        borderColor: reviewColor(r['verification_status']),
                        borderStrokeWidth: 2,
                      ),
                ],
              ),
              MarkerLayer(
                markers: [
                  for (final r in records.rows)
                    Marker(
                      point: center(r),
                      width: 48,
                      height: 48,
                      child: IconButton(
                        tooltip:
                            'Case #${r['case_id']} · ${reviewLabel(r['verification_status'])}',
                        icon: Icon(
                          Icons.location_on,
                          color: reviewColor(r['verification_status']),
                        ),
                        onPressed: () => PortalRoutes.go(
                          '/operator/queue?case=${r['case_id']}',
                        ),
                      ),
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
        const SizedBox(height: 12),
        _OperatorPageState(
          records,
          noun: 'map cases',
          row: (r) => Card(
            child: ListTile(
              title: Text(
                'Case #${r['case_id']} · ${r['farm_name'] ?? r['place_name']}',
              ),
              subtitle: Text(
                '${reviewLabel(r['verification_status'])} · submitted ${analysisDateText(r['submitted_at'])}',
              ),
              trailing: const Icon(Icons.arrow_forward),
              onTap: () =>
                  PortalRoutes.go('/operator/queue?case=${r['case_id']}'),
            ),
          ),
        ),
      ],
    ),
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
            if (c['status'] == 'needs_information') ...[
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
