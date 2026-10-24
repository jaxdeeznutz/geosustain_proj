part of '../main.dart';

class WebAdminDashboard extends StatefulWidget {
  final ApiService? api;
  final VoidCallback logout;
  final ValueChanged<String> message;
  const WebAdminDashboard({
    super.key,
    this.api,
    required this.logout,
    required this.message,
  });
  @override
  State<WebAdminDashboard> createState() => _WebAdminDashboardState();
}

class _WebAdminDashboardState extends State<WebAdminDashboard> {
  late final api = widget.api ?? ApiService();
  int page = 0;
  bool loading = true;
  Map<String, dynamic> stats = {};
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> analyses = [];
  List<Map<String, dynamic>> crops = [];
  List<Map<String, dynamic>> auditLogs = [];
  String search = '';
  String submittedSearch = '';
  final offsets = <int, int>{1: 0, 2: 0, 4: 0};
  final hasMore = <int, bool>{};

  void _applySearch(String value) {
    submittedSearch = value.trim();
    search = submittedSearch;
    offsets.updateAll((key, value) => 0);
    _refresh();
  }

  Widget _pager() => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: TextFormField(
            initialValue: submittedSearch,
            key: ValueKey('record-search-$page-$submittedSearch'),
            decoration: const InputDecoration(
              labelText: 'Search all records',
              suffixIcon: Icon(Icons.search),
            ),
            onFieldSubmitted: _applySearch,
          ),
        ),
        Text('Page ${(offsets[page] ?? 0) ~/ 50 + 1}'),
        OutlinedButton(
          onPressed: (offsets[page] ?? 0) > 0
              ? () {
                  offsets[page] = offsets[page]! - 50;
                  _refresh();
                }
              : null,
          child: const Text('Previous'),
        ),
        FilledButton(
          onPressed: hasMore[page] == true
              ? () {
                  offsets[page] = (offsets[page] ?? 0) + 50;
                  _refresh();
                }
              : null,
          child: const Text('Next'),
        ),
      ],
    ),
  );
  List<String> panelFailures = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => loading = true);
    final failures = <String>[];
    Future<void> panel(
      String name,
      Future<dynamic> Function() fetch,
      void Function(dynamic) apply,
    ) async {
      try {
        final result = await fetch();
        if (mounted) apply(result);
      } catch (_) {
        failures.add(name);
      }
    }

    List<Map<String, dynamic>> records(dynamic result) => (result as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    await Future.wait([
      panel(
        'Dashboard totals',
        api.getAdminDashboard,
        (value) => stats = Map<String, dynamic>.from(value as Map),
      ),
      panel(
        'Users',
        () => api.getRecordPage(
          '/api/admin/users',
          offset: offsets[1]!,
          search: submittedSearch,
        ),
        (value) {
          users = records(value['users']);
          hasMore[1] = value['has_more'] == true;
        },
      ),
      panel(
        'Analyses',
        () => api.getRecordPage(
          '/api/admin/analyses',
          offset: offsets[2]!,
          search: submittedSearch,
        ),
        (value) {
          analyses = records(value['analyses']);
          hasMore[2] = value['has_more'] == true;
        },
      ),
      panel('Crops', api.getAdminCrops, (value) => crops = records(value)),
      panel(
        'Audit logs',
        () => api.getRecordPage(
          '/api/admin/audit-logs',
          offset: offsets[4]!,
          search: submittedSearch,
        ),
        (value) {
          auditLogs = records(value['logs']);
          hasMore[4] = value['has_more'] == true;
        },
      ),
    ]);
    panelFailures = failures;
    if (mounted && failures.isNotEmpty) {
      widget.message(
        'Could not refresh: ${failures.join(', ')}. Other panels remain available.',
      );
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _changeUser(
    Map<String, dynamic> row, {
    String? role,
    bool? active,
  }) async {
    try {
      await api.updateAdminUser(
        (row['id'] as num).toInt(),
        role: role,
        isActive: active,
      );
      await _refresh();
    } catch (e) {
      widget.message(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _recovery(Map<String, dynamic> user) async {
    final verified = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Verify ${user['username']} before recovery'),
        content: const Text(
          'Use the project identity-verification procedure and an established private contact channel. Issue this handoff only after confirming the account owner. It expires in 15 minutes and can be used once.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Identity verified; issue handoff'),
          ),
        ],
      ),
    );
    if (verified != true) return;
    try {
      final token = await api.issuePasswordRecovery(int.parse('${user['id']}'));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Private recovery handoff'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Send privately to the verified owner. Do not put this handoff in reports, screenshots or shared messages. Ask them to select Forgot password and choose a new password.',
              ),
              const SizedBox(height: 12),
              SelectableText(token),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      widget.message(friendlyErrorMessage(error));
    }
  }

  Future<void> _toggleCrop(Map<String, dynamic> crop, bool active) async {
    try {
      await api.updateAdminCrop('${crop['crop_key']}', isActive: active);
      await _refresh();
    } catch (e) {
      widget.message(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _editCropNote(Map<String, dynamic> crop) async {
    final controller = TextEditingController(
      text: '${crop['suitability_note'] ?? ''}',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Edit note — ${crop['label']}'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Suitability note shown to Farmers/Analysts',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await api.updateAdminCrop(
        '${crop['crop_key']}',
        suitabilityNote: controller.text.trim(),
      );
      await _refresh();
    } catch (e) {
      widget.message(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.dashboard_rounded, 'Dashboard'),
      (Icons.people_alt_rounded, 'User Management'),
      (Icons.landscape_rounded, 'Farm & Analysis Monitoring'),
      (Icons.calendar_month_rounded, 'Crop & Season Settings'),
      (Icons.history_rounded, 'Audit & System'),
    ];
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 280,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF043F25), green],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.eco_rounded, color: Colors.white, size: 34),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'GeoSustain',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                const Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.white24,
                      child: Icon(
                        Icons.admin_panel_settings_rounded,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Super Administrator',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'System Management',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Expanded(
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => InkWell(
                      onTap: () => setState(() => page = i),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: page == i
                              ? Colors.white24
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(items[i].$1, color: Colors.white),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                items[i].$2,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                InkWell(
                  onTap: widget.logout,
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.logout_rounded, color: Colors.white),
                        SizedBox(width: 14),
                        Text(
                          'Logout',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: const Color(0xFFF4F8F5),
              child: loading
                  ? const Center(child: CircularProgressIndicator(color: green))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: _page(items[page].$2),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _page(String title) {
    if (page == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_pager(), _usersPage()],
      );
    }
    if (page == 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_pager(), _analysesPage()],
      );
    }
    if (page == 3) return _settingsPage();
    if (page == 4) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_pager(), _auditPage()],
      );
    }
    return _dashboardPage();
  }

  Widget _header(String title, String subtitle) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Color(0xFF153223),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              panelFailures.isEmpty
                  ? subtitle
                  : '$subtitle\nCould not refresh: ${panelFailures.join(', ')}. Retry with Refresh.',
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
      IconButton.filledTonal(
        tooltip: 'Refresh administrator panels',
        onPressed: _refresh,
        icon: const Icon(Icons.refresh_rounded),
      ),
    ],
  );
  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE1EBE4)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .035),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );
  Widget _stat(String label, dynamic value, IconData icon) => Expanded(
    child: _card(
      Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: softGreen,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: green),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _dashboardPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _header(
        'Super Administrator Dashboard',
        'Manage GeoSustain users, records, roles, and system configuration.',
      ),
      const SizedBox(height: 24),
      Row(
        children: [
          _stat(
            'Farmers',
            stats['farmers'] ?? 'Unavailable',
            Icons.agriculture_rounded,
          ),
          const SizedBox(width: 14),
          _stat(
            'Planning Analysts',
            stats['planning_analysts'] ?? 'Unavailable',
            Icons.analytics_rounded,
          ),
          const SizedBox(width: 14),
          _stat(
            'Pending Submissions',
            stats['pending'] ?? 'Unavailable',
            Icons.pending_actions_rounded,
          ),
          const SizedBox(width: 14),
          _stat(
            'Registered Parcels',
            stats['registered_parcels'] ?? 'Unavailable',
            Icons.map_rounded,
          ),
        ],
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          _stat(
            'Total Analyses',
            stats['total_analyses'] ?? 'Unavailable',
            Icons.insights_rounded,
          ),
          const SizedBox(width: 14),
          _stat(
            'Verified',
            stats['verified'] ?? 'Unavailable',
            Icons.verified_rounded,
          ),
          const SizedBox(width: 14),
          _stat(
            'Inactive Accounts',
            stats['inactive_users'] ?? 'Unavailable',
            Icons.person_off_rounded,
          ),
          const SizedBox(width: 14),
          _stat(
            'Mapped Area (ha)',
            (stats['total_area_hectares'] as num?)?.toStringAsFixed(2) ??
                'Unavailable',
            Icons.square_foot_rounded,
          ),
        ],
      ),
      const SizedBox(height: 24),
      _card(
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Administrative responsibilities',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 12),
            Text(
              '• Manage and activate user accounts\n• Monitor registered farm parcels and analysis records\n• Maintain local crop and seasonal reference settings\n• Review system activity without replacing the Agricultural Planning Analyst’s verification role',
              style: TextStyle(height: 1.8, color: Colors.black87),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _usersPage() {
    final filtered = users
        .where(
          (u) =>
              search.isEmpty ||
              '${u['username']} ${u['email']} ${u['role']}'
                  .toLowerCase()
                  .contains(search.toLowerCase()),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          'User Management',
          'Manage Farmers, Agricultural Planning Analysts, and Super Administrators.',
        ),
        const SizedBox(height: 20),
        TextField(
          onSubmitted: _applySearch,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search users by name, email, or role',
          ),
        ),
        const SizedBox(height: 16),
        _card(
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('User')),
                DataColumn(label: Text('Role')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Sign-in method')),
                DataColumn(label: Text('Created')),
                DataColumn(label: Text('Actions')),
              ],
              rows: filtered
                  .map(
                    (u) => DataRow(
                      cells: [
                        DataCell(
                          SizedBox(
                            width: 230,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${u['username']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${u['email']}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                        DataCell(
                          DropdownButton<String>(
                            value: _normalizedRole('${u['role']}'),
                            underline: const SizedBox(),
                            items: const [
                              DropdownMenuItem(
                                value: 'farmer',
                                child: Text('Farmer'),
                              ),
                              DropdownMenuItem(
                                value: 'agricultural_planning_analyst',
                                child: Text('Agricultural Planning Analyst'),
                              ),
                              DropdownMenuItem(
                                value: 'super_admin',
                                child: Text('Super Administrator'),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) _changeUser(u, role: v);
                            },
                          ),
                        ),
                        DataCell(
                          Chip(
                            label: Text(
                              (u['is_active'] == true) ? 'Active' : 'Inactive',
                            ),
                            backgroundColor: (u['is_active'] == true)
                                ? softGreen
                                : Colors.red.shade50,
                          ),
                        ),
                        DataCell(Text('${u['auth_provider'] ?? 'email'}')),
                        DataCell(
                          Text('${u['created_at'] ?? ''}'.split('T').first),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Semantics(
                                label: 'Active account for ${u['username']}',
                                child: Switch(
                                  value: u['is_active'] == true,
                                  onChanged: (v) => _changeUser(u, active: v),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Recover account for ${u['username']}',
                                onPressed: u['is_active'] == true
                                    ? () => _recovery(u)
                                    : null,
                                icon: const Icon(Icons.lock_reset),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  String _normalizedRole(String r) {
    r = r.toLowerCase();
    if (r == 'admin' || r == 'super_admin') return 'super_admin';
    if (r.contains('analyst') || r == 'planner') {
      return 'agricultural_planning_analyst';
    }
    return 'farmer';
  }

  Widget _analysesPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _header(
        'Farm & Analysis Monitoring',
        'Monitor registered parcels and analysis records across the system.',
      ),
      const SizedBox(height: 20),
      _card(
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Owner')),
              DataColumn(label: Text('Role')),
              DataColumn(label: Text('Location')),
              DataColumn(label: Text('Result')),
              DataColumn(label: Text('Area')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Date')),
            ],
            rows: analyses
                .map(
                  (a) => DataRow(
                    cells: [
                      DataCell(Text('${a['username'] ?? 'Unknown'}')),
                      DataCell(Text(_roleLabel('${a['role']}'))),
                      DataCell(
                        SizedBox(
                          width: 220,
                          child: Text(
                            '${a['place_name'] ?? 'Mapped parcel'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        Text('${a['predicted_crop'] ?? 'Land assessment'}'),
                      ),
                      DataCell(
                        Text(
                          a['area_hectares'] == null
                              ? '—'
                              : '${(a['area_hectares'] as num).toStringAsFixed(3)} ha',
                        ),
                      ),
                      DataCell(
                        Chip(
                          label: Text('${a['verification_status'] ?? 'draft'}'),
                        ),
                      ),
                      DataCell(
                        Text('${a['analyzed_at'] ?? ''}'.split('T').first),
                      ),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
      ),
    ],
  );
  String _roleLabel(String r) {
    final n = _normalizedRole(r);
    return n == 'super_admin'
        ? 'Super Administrator'
        : n == 'agricultural_planning_analyst'
        ? 'Agricultural Planning Analyst'
        : 'Farmer';
  }

  Widget _settingsPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _header(
        'Crop & Season Settings',
        'Manage which approved crops GeoSustain can currently recommend, and their reference info.',
      ),
      const SizedBox(height: 20),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Approved crop reference',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'This is the finalized GeoSustain crop set. Deactivating a crop here removes it from new recommendations immediately — it does not add crops outside this approved list, and does not change environmental scoring.',
              style: TextStyle(
                height: 1.5,
                color: Colors.black54,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            if (crops.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No crop reference rows found.'),
              )
            else
              ...crops.map(
                (c) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBFDFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE8EFE9)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${c['label']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${c['growth_cycle'] ?? '--'} • ${c['est_yield'] ?? '--'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${c['suitability_note'] ?? ''}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _editCropNote(c),
                        icon: const Icon(Icons.edit_note_rounded, size: 20),
                        tooltip: 'Edit note',
                      ),
                      Switch(
                        value: c['is_active'] == true,
                        onChanged: (v) => _toggleCrop(c, v),
                        activeThumbColor: green,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _auditPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _header(
        'Audit & System',
        'Security-sensitive administrative activity: role changes and verification decisions.',
      ),
      TextButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MessageLogPage(api: api)),
        ),
        icon: const Icon(Icons.notifications_outlined),
        label: const Text('Push delivery log'),
      ),
      const SizedBox(height: 20),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent activity',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'Every role/status change and every Farmer-submission verification decision is recorded here, regardless of which screen or API call made it.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 14),
            if (auditLogs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No audit activity recorded yet.'),
              )
            else
              ...auditLogs.map((log) {
                final action = '${log['action']}';
                final actor =
                    log['actor_username'] ??
                    log['actor_email'] ??
                    'Unknown actor';
                final details = log['details'];
                String detailText = '';
                if (details is Map) {
                  if (action == 'verification_decision') {
                    detailText = 'Decision: ${details['decision']}';
                  } else if (action == 'user_update') {
                    final roleCh = details['role'];
                    final activeCh = details['is_active'];
                    final parts = <String>[];
                    if (roleCh is Map) {
                      parts.add('role ${roleCh['from']} → ${roleCh['to']}');
                    }
                    if (activeCh is Map) {
                      parts.add(
                        'active ${activeCh['from']} → ${activeCh['to']}',
                      );
                    }
                    detailText = parts.join(', ');
                  } else if (action == 'crop_reference_update') {
                    detailText =
                        'Crop: ${details['crop_key']} (active: ${details['is_active']})';
                  }
                }
                IconData icon = Icons.history_rounded;
                if (action == 'verification_decision') {
                  icon = Icons.fact_check_outlined;
                }
                if (action == 'user_update') {
                  icon = Icons.manage_accounts_rounded;
                }
                if (action == 'crop_reference_update') {
                  icon = Icons.grass_rounded;
                }
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(icon, color: green),
                  title: Text(
                    '$actor — ${action.replaceAll('_', ' ')}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  subtitle: Text(
                    '${detailText.isEmpty ? '' : '$detailText • '}${log['created_at'] ?? ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              }),
            const Divider(height: 28),
            ListTile(
              leading: const Icon(Icons.cloud_done_rounded, color: green),
              title: const Text('Backend and Supabase monitoring'),
              subtitle: const Text(
                'Use Render and Supabase logs for deployment, database, and infrastructure-level health.',
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
