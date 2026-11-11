part of '../main.dart';

class NotificationsPage extends StatefulWidget {
  final AnalysisState? state;
  final ApiService? api;
  final int? initialSessionId;
  final bool webLayout;
  const NotificationsPage({
    super.key,
    this.state,
    this.api,
    this.initialSessionId,
    this.webLayout = false,
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
      try {
        final cached = OfflineFarmStore.rows(
          (await OfflineFarmStore.read())['events'],
        );
        if (mounted && generation == request) {
          setState(() {
            local = cached
                .where(
                  (event) =>
                      (!unreadOnly || event['read_at'] == null) &&
                      (type.isEmpty || type == 'farm_synced'),
                )
                .toList();
          });
        }
      } catch (_) {
        // Online notifications remain available without device storage.
      }
      final data = await api.getRecordPage(
        '/api/mobile/activity',
        offset: target,
        requestTimeout: const Duration(seconds: 18),
        recoveryAttempts: 1,
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
      widget.state?.setUnreadNotifications(unread);
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
        if (kIsWeb && state.isPlanner) {
          await api.markNotificationRead(
            (event['id'] as num).toInt(),
            activity: true,
          );
          if (mounted) {
            PortalRoutes.go('/operator/queue?session=${event['session_id']}');
          }
          return;
        }
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

  DateTime? _eventTime(Map<String, dynamic> row) =>
      DateTime.tryParse('${row['created_at'] ?? ''}')?.toLocal();

  String _dayLabel(DateTime? value) {
    if (value == null) return 'Earlier';
    final today = DateTime.now();
    final day = DateTime(value.year, value.month, value.day);
    final difference = DateTime(
      today.year,
      today.month,
      today.day,
    ).difference(day).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    const months = [
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
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  Widget _mobileTile(Map<String, dynamic> row, {bool device = false}) {
    final kind = '${row['event_type']}';
    final icon = switch (kind) {
      'analysis_ready' || 'analysis_partial' => Icons.check_circle_outline,
      'analysis_failed' || 'needs_information' => Icons.info_outline,
      'review' ||
      'submitted' ||
      'submission_received' => Icons.description_outlined,
      _ => Icons.notifications_none,
    };
    final tint = kind == 'analysis_failed' || kind == 'needs_information'
        ? const Color(0xFFB98215)
        : green;
    final timestamp = _eventTime(row);
    final time = timestamp == null
        ? ''
        : '${timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12}:${timestamp.minute.toString().padLeft(2, '0')} ${timestamp.hour < 12 ? 'AM' : 'PM'}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: row['read_at'] == null
            ? const Color(0xFFEAF7EF)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: opening ? null : () => _open(row, device: device),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: tint.withValues(alpha: .12),
                  child: Icon(icon, color: tint),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device
                            ? 'Farm synced: ${row['farm_name']}'
                            : title(row),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        device
                            ? 'Ready for online analysis.'
                            : '${row['message'] ?? ''}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(time, style: Theme.of(context).textTheme.labelSmall),
                    if (row['read_at'] == null) ...[
                      const SizedBox(height: 8),
                      const CircleAvatar(radius: 4, backgroundColor: green),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _mobileEvents() {
    final events =
        <({Map<String, dynamic> row, bool device})>[
          for (final row in rows) (row: row, device: false),
          if (offset == 0)
            for (final row in local) (row: row, device: true),
        ]..sort(
          (a, b) => (_eventTime(b.row) ?? DateTime(1970)).compareTo(
            _eventTime(a.row) ?? DateTime(1970),
          ),
        );
    final widgets = <Widget>[];
    String? lastDay;
    for (final event in events) {
      final day = _dayLabel(_eventTime(event.row));
      if (day != lastDay) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 20, 0, 12),
            child: Text(
              day,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
        lastDay = day;
      }
      widgets.add(_mobileTile(event.row, device: event.device));
    }
    return widgets;
  }

  Widget _webActivity(BuildContext context) {
    final empty =
        !loading &&
        error == null &&
        rows.isEmpty &&
        (offset != 0 || local.isEmpty);
    final filter = SizedBox(
      width: 220,
      child: DropdownButtonFormField<String>(
        key: ValueKey('web-activity-filter-$type'),
        initialValue: type,
        isExpanded: true,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.tune_rounded, size: 18),
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        items: [
          for (final entry in labels.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: loading
            ? null
            : (value) {
                if (value != null) {
                  setState(() => type = value);
                  _load(page: 0);
                }
              },
      ),
    );
    return _WebCard(
      key: const ValueKey('activity-content-panel'),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (_, box) {
              const heading = _AnalystSectionTitle(
                'Recent Activity',
                icon: Icons.history_rounded,
                subtitle:
                    'Track your latest analyses, submissions, reviews, and system updates.',
              );
              if (box.maxWidth < 650) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [heading, const SizedBox(height: 14), filter],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 20),
                  filter,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  '$unread unread notifications',
                  style: TextStyle(fontSize: 12, color: WebPortalColors.muted),
                ),
              ),
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
              TextButton(
                onPressed: loading || opening || unread == 0 ? null : _markAll,
                child: const Text('Mark all as read'),
              ),
              TextButton.icon(
                onPressed: loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 17),
                label: const Text('Refresh activity'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (loading)
            const LinearProgressIndicator(semanticsLabel: 'Loading activity'),
          if (error != null)
            Semantics(
              liveRegion: true,
              child: MaterialBanner(
                content: Text(error!),
                actions: [
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            ),
          Container(
            key: const ValueKey('activity-results-panel'),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: WebPortalColors.muted.withValues(alpha: .14),
              ),
            ),
            padding: const EdgeInsets.all(10),
            child: empty
                ? _WebEmptyState(
                    title: type.isEmpty && !unreadOnly
                        ? 'No recent activity'
                        : 'No activity matches this view',
                    message:
                        'Your activity will appear here once you create analyses, submit cases, or receive updates.',
                    icon: Icons.schedule_outlined,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (error == null) ...[
                        for (final row in rows) tile(row),
                        if (offset == 0)
                          for (final row in local) tile(row, device: true),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: loading || offset == 0
                    ? null
                    : () => _load(page: math.max(0, offset - 50)),
                child: const Text('Previous'),
              ),
              Text(
                'Page ${offset ~/ 50 + 1}',
                style: TextStyle(fontSize: 12, color: WebPortalColors.muted),
              ),
              TextButton(
                onPressed: loading || !more
                    ? null
                    : () => _load(page: offset + 50),
                child: const Text('Next'),
              ),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        WeatherNotificationsPage(state: widget.state),
                  ),
                ),
                icon: const Icon(Icons.cloud_outlined, size: 17),
                label: const Text('View weather advisories'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.webLayout) {
      return _webActivity(context);
    }
    return Scaffold(
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Notifications',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: loading || opening || unread == 0
                      ? null
                      : _markAll,
                  icon: const Icon(Icons.mark_email_read_outlined, size: 18),
                  label: const Text('Mark all read'),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Notification options',
                  onSelected: (choice) {
                    if (choice == 'unread') {
                      setState(() => unreadOnly = !unreadOnly);
                      _load(page: 0);
                    } else if (choice == 'settings') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsPage(
                            section: SettingsSection.notifications,
                          ),
                        ),
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'unread',
                      child: Text(unreadOnly ? 'Show all' : 'Unread only'),
                    ),
                    const PopupMenuItem(
                      value: 'settings',
                      child: Text('Notification settings'),
                    ),
                  ],
                ),
              ],
            ),
            if (unread > 0)
              Text(
                '$unread unread',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (loading) ...[
              const LinearProgressIndicator(),
              if (rows.isEmpty && local.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('Loading notifications...'),
                ),
            ],
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
            if (error == null || local.isNotEmpty) ...[..._mobileEvents()],
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
}
