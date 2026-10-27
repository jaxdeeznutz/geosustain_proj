part of '../main.dart';

class NotificationsPage extends StatefulWidget {
  final AnalysisState? state;
  final ApiService? api;
  final int? initialSessionId;
  const NotificationsPage({
    super.key,
    this.state,
    this.api,
    this.initialSessionId,
  });
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final ApiService api = widget.api ?? widget.state?.api ?? ApiService();
  List<Map<String, dynamic>> rows = [], local = [];
  int offset = 0, unread = 0, generation = 0;
  bool more = false, loading = true, opening = false, unreadOnly = false;
  String type = '';
  String? error;
  static const labels = {
    '': 'All activity',
    'review': 'Reviews',
    'submitted': 'Submissions',
    'analysis_ready': 'Analysis ready',
    'analysis_partial': 'Partial assessments',
    'analysis_failed': 'Analysis problems',
    'submission_received': 'Review queue',
    'farm_synced': 'Farm sync',
    'needs_information': 'Information requested',
    'resubmitted': 'Resubmissions',
    'advisory_note': 'Analyst advice',
    'followup_created': 'New follow-ups',
    'followup_completed': 'Completed follow-ups',
    'followup_due': 'Due follow-ups',
  };
  @override
  void initState() {
    super.initState();
    _load();
    if (widget.initialSessionId != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openReview(widget.initialSessionId!, null),
      );
    }
  }

  @override
  void dispose() {
    generation++;
    if (widget.api == null && widget.state == null) api.close();
    super.dispose();
  }

  Future<void> _load({int? page}) async {
    if (!mounted) return;
    final request = ++generation, target = page ?? offset;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await api.getRecordPage(
        '/api/mobile/activity',
        offset: target,
        parameters: {
          'unread_only': '$unreadOnly',
          if (type.isNotEmpty && type != 'farm_synced') 'event_type': type,
        },
      );
      var events = <Map<String, dynamic>>[];
      try {
        events = OfflineFarmStore.rows(
          (await OfflineFarmStore.read())['events'],
        );
      } catch (_) {
        /* Server inbox remains usable when device storage is unavailable. */
      }
      if (!mounted || generation != request) return;
      setState(() {
        rows = type == 'farm_synced'
            ? []
            : OfflineFarmStore.rows(data['notifications']);
        local = events
            .where(
              (e) =>
                  (!unreadOnly || e['read_at'] == null) &&
                  (type.isEmpty || type == 'farm_synced'),
            )
            .toList();
        unread =
            (data['unread_count'] as num).toInt() +
            events.where((e) => e['read_at'] == null).length;
        more = type != 'farm_synced' && data['has_more'] == true;
        offset = target;
      });
    } catch (failure) {
      if (mounted && generation == request) {
        setState(() => error = friendlyErrorMessage(failure));
      }
    } finally {
      if (mounted && generation == request) setState(() => loading = false);
    }
  }

  void _message(Object failure) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(failure))));
    }
  }

  Future<void> _openReview(
    int sessionId,
    int? id, {
    bool activity = false,
  }) async {
    if (opening || !mounted) return;
    setState(() => opening = true);
    try {
      Map<String, dynamic> detail;
      try {
        detail = await api.getAnalysis(sessionId);
      } on ApiException catch (failure) {
        if (failure.statusCode != 404 || widget.state?.isPlanner != true) {
          rethrow;
        }
        detail = await api.getPlannerSessionDetail(sessionId);
      }
      await api.markNotificationRead(
        id ?? sessionId,
        bySession: id == null,
        activity: activity,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Analysis review'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Decision: ${detail['verification_status'] ?? 'Unavailable'}',
                ),
                const SizedBox(height: 12),
                Text(
                  '${detail['planner_notes'] ?? 'No additional review notes.'}',
                ),
              ],
            ),
          ),
          actions: [
            if (widget.state != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    this.context,
                    MaterialPageRoute(
                      builder: (_) => HistoryDetailPage(
                        record: detail,
                        state: widget.state!,
                      ),
                    ),
                  );
                },
                child: const Text('Open analysis'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      await _load();
    } catch (failure) {
      _message(failure);
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Future<void> _open(Map<String, dynamic> event, {bool device = false}) async {
    if (opening) return;
    if (!device && event['case_id'] != null && widget.state != null) {
      setState(() => opening = true);
      try {
        await api.markNotificationRead(
          (event['id'] as num).toInt(),
          activity: true,
        );
        if (!mounted) return;
        if (kIsWeb && widget.state!.isPlanner) {
          PortalRoutes.go('/operator/queue?case=${event['case_id']}');
        } else {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FarmerReviewResponsePage(
                state: widget.state!,
                caseId: (event['case_id'] as num).toInt(),
              ),
            ),
          );
        }
        if (mounted) await _load();
      } catch (failure) {
        _message(failure);
      } finally {
        if (mounted) setState(() => opening = false);
      }
      return;
    }
    if (!device &&
        (event['event_type'] == 'review' || event['event_type'] == null)) {
      return _openReview(
        (event['session_id'] as num).toInt(),
        (event['id'] as num).toInt(),
        activity: event['event_type'] != null,
      );
    }
    setState(() => opening = true);
    try {
      final state = widget.state;
      if (state == null) {
        throw const ApiException(
          404,
          'Open this notification from your signed-in workspace.',
        );
      }
      Widget page;
      if (event['event_type'] == 'submission_received') {
        final detail = await api.getPlannerSessionDetail(
          (event['session_id'] as num).toInt(),
        );
        await api.markNotificationRead(
          (event['id'] as num).toInt(),
          activity: true,
        );
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (_) => _PlannerReviewDialog(state: state, row: detail),
        );
        await _load();
        return;
      } else if (event['session_id'] != null) {
        final detail = await api.getAnalysis(
          (event['session_id'] as num).toInt(),
        );
        page = HistoryDetailPage(record: detail, state: state);
      } else if (event['farm_id'] != null) {
        final farm = await api.getFarm((event['farm_id'] as num).toInt());
        page = FarmDetailsPage(state: state, farm: farm);
      } else {
        throw const ApiException(
          404,
          'The original target is unavailable. Open My Farms to check retained farms or retry.',
        );
      }
      if (device) {
        await OfflineFarmStore.markLocalRead('${event['id']}');
      } else {
        await api.markNotificationRead(
          (event['id'] as num).toInt(),
          activity: true,
        );
      }
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
      await _load();
    } catch (failure) {
      _message(failure);
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Future<void> _markAll() async {
    setState(() => opening = true);
    try {
      final snapshot = OfflineFarmStore.rows(
        (await OfflineFarmStore.read())['events'],
      );
      await api.markAllActivityRead();
      for (final event in snapshot) {
        await OfflineFarmStore.markLocalRead('${event['id']}');
      }
      await _load();
    } catch (failure) {
      _message(failure);
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  String title(Map<String, dynamic> row) => switch ('${row['event_type']}') {
    'review' || 'null' => 'Analysis review: ${row['decision']}',
    'analysis_ready' => 'Analysis ready',
    'analysis_partial' => 'Partial assessment saved',
    'analysis_failed' => 'Analysis could not complete',
    'submitted' => 'Submitted for review',
    'submission_received' => 'New submission for review',
    'needs_information' => 'Information requested',
    'resubmitted' => 'Corrected analysis resubmitted',
    'advisory_note' => 'Analyst advisory note',
    'followup_created' => 'Follow-up created',
    'followup_completed' => 'Follow-up completed',
    'followup_due' => 'Follow-up due',
    _ => 'Farm synced',
  };
  Widget tile(Map<String, dynamic> row, {bool device = false}) => Card(
    child: ListTile(
      leading: Icon(
        row['read_at'] == null
            ? Icons.mark_email_unread_outlined
            : Icons.drafts_outlined,
      ),
      title: Text(device ? 'Farm synced: ${row['farm_name']}' : title(row)),
      subtitle: Text(
        '${device ? 'Device activity · Ready for online analysis.' : row['message'] ?? ''}\n${analysisDateText(row['created_at'])} · ${row['read_at'] == null ? 'Unread' : 'Read'}',
      ),
      enabled: !opening,
      onTap: () => _open(row, device: device),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: GeoSustainHeader(
      title: 'Notifications',
      embedded: false,
      state: widget.state,
      showNotifications: false,
      trailing: GeoHeaderAction(
        tooltip: 'Refresh notifications',
        icon: Icons.refresh,
        onPressed: loading ? null : _load,
      ),
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.state != null && !widget.state!.isPlanner)
            OutlinedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FarmerReviewCasesPage(state: widget.state!),
                ),
              ),
              child: const Text('My review cases and corrections'),
            ),
          Semantics(
            liveRegion: true,
            child: Text(
              '$unread unread notifications',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: const Text('Unread only'),
                selected: unreadOnly,
                onSelected: loading
                    ? null
                    : (value) {
                        setState(() => unreadOnly = value);
                        _load(page: 0);
                      },
              ),
              DropdownButton<String>(
                value: type,
                items: [
                  for (final entry in labels.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: loading
                    ? null
                    : (value) {
                        setState(() => type = value!);
                        _load(page: 0);
                      },
              ),
              TextButton(
                onPressed: loading || opening || unread == 0 ? null : _markAll,
                child: const Text('Mark all as read'),
              ),
            ],
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            Card(
              child: ListTile(
                title: Text(error!),
                trailing: TextButton(
                  onPressed: _load,
                  child: const Text('Retry'),
                ),
              ),
            )
          else if (!loading && rows.isEmpty && (offset != 0 || local.isEmpty))
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No notifications match this view. Analysis, submission, review and farm-sync activity appear here.',
              ),
            ),
          if (error == null) ...[
            for (final row in rows) tile(row),
            if (offset == 0)
              for (final row in local) tile(row, device: true),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: loading || offset == 0
                    ? null
                    : () => _load(page: math.max(0, offset - 50)),
                child: const Text('Previous'),
              ),
              Text('Page ${offset ~/ 50 + 1}'),
              TextButton(
                onPressed: loading || !more
                    ? null
                    : () => _load(page: offset + 50),
                child: const Text('Next'),
              ),
            ],
          ),
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => WeatherNotificationsPage(state: widget.state),
              ),
            ),
            icon: const Icon(Icons.cloud_outlined),
            label: const Text('View weather advisories'),
          ),
        ],
      ),
    ),
  );
}
