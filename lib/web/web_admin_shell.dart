part of '../main.dart';

class WebAdminDashboard extends StatefulWidget {
  final ApiService? api;
  final AnalysisState? state;
  final VoidCallback logout;
  final ValueChanged<String> message;
  const WebAdminDashboard({
    super.key,
    this.api,
    this.state,
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
  Map<String, dynamic>? systemStatus;
  String? monitoringError;
  String submittedSearch = '';
  final offsets = <int, int>{1: 0, 2: 0, 4: 0};
  final hasMore = <int, bool>{};
  int get _pageSize => switch (page) {
    2 => 6,
    4 => 8,
    _ => 50,
  };
  int refreshGeneration = 0;

  void _applySearch(String value) {
    submittedSearch = value.trim();
    draftSearch = submittedSearch;
    offsets.updateAll((key, value) => 0);
    _refresh();
  }

  List<String> panelFailures = [];

  @override
  void initState() {
    super.initState();
    PortalRoutes.start();
    page = PortalRoutes.pageFor(routePages, 'admin');
    PortalRoutes.current.addListener(_routeChanged);
    appThemeMode.addListener(_themeChanged);
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) {
      return;
    }
    final generation = ++refreshGeneration;
    setState(() => loading = true);
    final failures = <String>[];
    Future<void> panel(
      String name,
      Future<dynamic> Function() fetch,
      void Function(dynamic) apply,
    ) async {
      try {
        final result = await fetch();
        if (mounted && generation == refreshGeneration) {
          apply(result);
        }
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
          parameters: const {'limit': '6'},
        ),
        (value) {
          analyses = records(value['analyses']);
          hasMore[2] = value['has_more'] == true;
        },
      ),
      panel('Crops', api.getAdminCrops, (value) => crops = records(value)),
      panel(
        'System status',
        () async {
          try {
            final value = await api.getAdminSystemStatus();
            if (value['checked_at'] == null || value['checks'] is! List) {
              throw const FormatException('Missing monitoring result');
            }
            return value;
          } catch (error) {
            if (mounted && generation == refreshGeneration) {
              systemStatus = null;
              monitoringError =
                  'Could not check service status. Refresh to retry.';
            }
            rethrow;
          }
        },
        (value) {
          systemStatus = Map<String, dynamic>.from(value as Map);
          monitoringError = null;
        },
      ),
      panel(
        'Audit logs',
        () => api.getRecordPage(
          '/api/admin/audit-logs',
          offset: offsets[4]!,
          search: submittedSearch,
          parameters: const {'limit': '8'},
        ),
        (value) {
          auditLogs = records(value['logs']);
          hasMore[4] = value['has_more'] == true;
        },
      ),
    ]);
    if (!mounted || generation != refreshGeneration) {
      return;
    }
    panelFailures = failures;
    if (mounted && failures.isNotEmpty) {
      widget.message(
        'Could not refresh: ${failures.join(', ')}. Other panels remain available.',
      );
    }
    if (mounted) {
      setState(() => loading = false);
    }
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
        content: Text(
          'Use the project identity-verification procedure and an established private contact channel. Issue this handoff only after confirming the account owner. It expires in 15 minutes and can be used once.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Identity verified; issue handoff'),
          ),
        ],
      ),
    );
    if (verified != true) {
      return;
    }
    try {
      final token = await api.issuePasswordRecovery(int.parse('${user['id']}'));
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Private recovery handoff'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Send privately to the verified owner. Do not put this handoff in reports, screenshots or shared messages. Ask them to select Forgot password and choose a new password.',
              ),
              SizedBox(height: 12),
              SelectableText(token),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close'),
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
          decoration: InputDecoration(
            labelText: 'Suitability note shown to Farmers/Analysts',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) {
      return;
    }
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

  static const routePages = [
    'dashboard',
    'users',
    'analyses',
    'crops',
    'audit',
  ];
  static const _items = [
    (Icons.dashboard_rounded, 'Dashboard'),
    (Icons.people_alt_rounded, 'User Management'),
    (Icons.landscape_rounded, 'Farm & Analysis Monitoring'),
    (Icons.calendar_month_rounded, 'Crop & Season Settings'),
    (Icons.verified_user_rounded, 'Audit & System'),
  ];
  String userRole = 'all', userStatus = 'all', provider = 'all';
  String analysisRole = 'all',
      analysisStatus = 'all',
      place = 'all',
      crop = 'all';
  String cropQuery = '', auditAction = 'all', auditTab = 'activity';
  bool cropAscending = true, cropGrid = false;
  String draftSearch = '';

  void _routeChanged() {
    if (mounted) {
      final previous = page;
      setState(() => page = PortalRoutes.pageFor(routePages, 'admin'));
      if (page == 4 && previous != page) unawaited(_refresh());
    }
  }

  void _themeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    PortalRoutes.current.removeListener(_routeChanged);
    appThemeMode.removeListener(_themeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return _AdminPortal(
      state: widget.state,
      navigation: Builder(builder: (navContext) => _navigation(navContext)),
      onSearch: (value) {
        PortalRoutes.go('/admin/users');
        _applySearch(value);
      },
      child: _AdminCanvas(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                key: PageStorageKey('admin-page-$page'),
                padding: EdgeInsets.all(
                  MediaQuery.sizeOf(context).width < 600 ? 16 : 20,
                ),
                child: switch (page) {
                  1 => _usersPage(),
                  2 => _analysesPage(),
                  3 => _settingsPage(),
                  4 => _auditPage(),
                  _ => _dashboardPage(),
                },
              ),
      ),
    );
  }

  Widget _navigation(BuildContext navContext) => SizedBox(
    width: 224,
    child: Material(
      color: const Color(0xFF003D32),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 330,
            child: ExcludeSemantics(
              child: Image.asset(
                'assets/images/web/analyst_sidebar_valley.png',
                fit: BoxFit.fitWidth,
                alignment: Alignment.bottomCenter,
              ),
            ),
          ),
          ListView(
            primary: false,
            padding: const EdgeInsets.fromLTRB(12, 22, 12, 26),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 7),
                child: Row(
                  children: [
                    Icon(Icons.eco_rounded, color: Color(0xFF79DBAA), size: 29),
                    SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'GeoSustain',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Agricultural Insights Platform',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 8.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 7),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Color(0xFF16896A),
                      child: Text('S', style: TextStyle(color: Colors.white)),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Super Administrator',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'System Management',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 25),
              for (var i = 0; i < _items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: ValueKey('admin-nav-${routePages[i]}'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        PortalRoutes.go('/admin/${routePages[i]}');
                        if (Scaffold.maybeOf(navContext)?.isDrawerOpen ==
                            true) {
                          Navigator.pop(navContext);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: page == i
                              ? const Color(0xFF287B60)
                              : Colors.transparent,
                        ),
                        child: Row(
                          children: [
                            Icon(_items[i].$1, color: Colors.white, size: 19),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _items[i].$2,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: page == i
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const Divider(color: Colors.white24, height: 28),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: const Icon(
                  Icons.logout_rounded,
                  color: Colors.white,
                  size: 19,
                ),
                title: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Log out?'),
                      content: const Text(
                        'You can sign in again to manage GeoSustain.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Log out'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) widget.logout();
                },
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _header(
    String title,
    String subtitle,
    IconData icon, {
    bool weather = false,
  }) => _AdminHeader(
    title: title,
    subtitle: subtitle,
    icon: icon,
    refresh: _refresh,
    failures: panelFailures,
    state: widget.state,
    weather: weather,
  );

  Widget _metric(
    String label,
    dynamic value,
    IconData icon,
    String caption, [
    Color? color,
  ]) => _AnalystMetric(
    icon: icon,
    label: label,
    value: '${value ?? 'Unavailable'}',
    caption: caption,
    color: color,
  );

  int? get _totalUsers =>
      stats['active_users'] is num && stats['inactive_users'] is num
      ? (stats['active_users'] as num).toInt() +
            (stats['inactive_users'] as num).toInt()
      : null;

  Widget _metrics(List<Widget> children) => _AdminGrid(children: children);

  Widget _dashboardPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _header(
        'Super Administrator Dashboard',
        'Manage GeoSustain users, records, roles, and system configuration.',
        Icons.workspace_premium_rounded,
        weather: true,
      ),
      const SizedBox(height: 20),
      _metrics([
        _metric(
          'Total Farmers',
          stats['farmers'],
          Icons.people_alt_rounded,
          'Registered farmers',
        ),
        _metric(
          'Analysts',
          stats['planning_analysts'],
          Icons.bar_chart_rounded,
          'Registered analysts',
          const Color(0xFF197BD1),
        ),
        _metric(
          'Pending Submissions',
          stats['pending'],
          Icons.assignment_outlined,
          'Analyses awaiting review',
          const Color(0xFFA96500),
        ),
        _metric(
          'Registered Parcels',
          stats['registered_parcels'],
          Icons.map_rounded,
          'Current land parcels',
          const Color(0xFF8353C8),
        ),
      ]),
      const SizedBox(height: 14),
      _metrics([
        _metric(
          'Total Analyses',
          stats['total_analyses'],
          Icons.show_chart_rounded,
          'All analysis records',
        ),
        _metric(
          'Verified Analyses',
          stats['verified'],
          Icons.verified_user_rounded,
          'Recorded review decisions',
          const Color(0xFF197BD1),
        ),
        _metric(
          'Inactive Accounts',
          stats['inactive_users'],
          Icons.person_off_rounded,
          'Disabled accounts',
          const Color(0xFFC1364D),
        ),
        _metric(
          'Mapped Area',
          analysisNumber(stats['total_area_hectares']) == null
              ? null
              : '${analysisNumber(stats['total_area_hectares'])!.toStringAsFixed(2)} ha',
          Icons.landscape_rounded,
          'Current registered parcels',
        ),
      ]),
      const SizedBox(height: 16),
      _AnalystColumns(
        mainFlex: 2,
        sideFlex: 1,
        equalHeight: true,
        main: _WebCard(
          key: const ValueKey('admin-recent-activity'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AnalystSectionTitle(
                'Recent User Activity',
                subtitle: 'Recorded administrative actions',
                icon: Icons.history_rounded,
                action: TextButton(
                  onPressed: () => PortalRoutes.go('/admin/audit'),
                  child: const Text('View All →'),
                ),
              ),
              const SizedBox(height: 14),
              _auditTable(auditLogs.take(4).toList(), dashboard: true),
            ],
          ),
        ),
        side: _systemOverview(),
      ),
      const SizedBox(height: 16),
      _WebCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _AnalystSectionTitle(
              'Quick Actions',
              subtitle: 'Common administrative tasks for system management.',
              icon: Icons.bolt_rounded,
            ),
            const SizedBox(height: 14),
            _metrics([
              _quickAction(
                'Manage Users',
                'Roles, status and recovery',
                Icons.people_alt_rounded,
                1,
              ),
              _quickAction(
                'Monitor Analyses',
                'Inspect saved records',
                Icons.bar_chart_rounded,
                2,
              ),
              _quickAction(
                'Crop References',
                'Review and activate revisions',
                Icons.description_outlined,
                3,
              ),
              _quickAction(
                'View Audit Logs',
                'Recorded administrative history',
                Icons.history_rounded,
                4,
              ),
            ]),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'Analysts record Farmer-submission decisions. Administrators manage access and reference configuration.',
        style: TextStyle(fontSize: 11, color: WebPortalColors.muted),
      ),
    ],
  );

  Widget _quickAction(
    String title,
    String subtitle,
    IconData icon,
    int destination,
  ) => Material(
    color: WebPortalColors.surface,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => PortalRoutes.go('/admin/${routePages[destination]}'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: WebPortalColors.muted.withValues(alpha: .15),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: WebPortalColors.accent, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: WebPortalColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 17, color: WebPortalColors.accent),
          ],
        ),
      ),
    ),
  );

  Widget _systemOverview() => _WebCard(
    key: const ValueKey('admin-system-overview'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _AnalystSectionTitle(
          'System Overview',
          subtitle: 'Account and record inventory',
          icon: Icons.settings_rounded,
        ),
        const SizedBox(height: 16),
        _AdminGrid(
          small: true,
          children: [
            _mini(
              'Users',
              '${_totalUsers ?? 'Unavailable'}',
              Icons.people_alt_rounded,
            ),
            _mini(
              'Analyses',
              '${stats['total_analyses'] ?? 'Unavailable'}',
              Icons.bar_chart_rounded,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _AdminGrid(
          small: true,
          children: [
            _mini(
              'Active accounts',
              '${stats['active_users'] ?? 'Unavailable'}',
              Icons.person_rounded,
            ),
            _mini(
              'Administrators',
              '${stats['super_admins'] ?? 'Unavailable'}',
              Icons.shield_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Infrastructure monitoring',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: WebPortalColors.ink,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Storage, backups and service health are available in Render and Supabase logs.',
          style: TextStyle(fontSize: 11, color: WebPortalColors.muted),
        ),
      ],
    ),
  );

  Widget _mini(String label, String value, IconData icon) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: WebPortalColors.tint.withValues(alpha: .35),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Icon(icon, color: WebPortalColors.accent, size: 21),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10)),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _filter(
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> changed, {
    double width = 155,
  }) => SizedBox(
    width: math.min(
      width * MediaQuery.textScalerOf(context).scale(12) / 12,
      MediaQuery.sizeOf(context).width -
          (MediaQuery.sizeOf(context).width >= 1200 ? 224 : 0) -
          64,
    ),
    child: DropdownButtonFormField<String>(
      key: ValueKey('admin-filter-$label-$value'),
      initialValue: options.containsKey(value) ? value : 'all',
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: options.entries
          .map(
            (entry) =>
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          )
          .toList(),
      onChanged: (next) {
        if (next != null) {
          setState(() => changed(next));
        }
      },
    ),
  );

  static const _roles = {
    'all': 'All roles',
    'farmer': 'Farmer',
    'agricultural_planning_analyst': 'Analyst',
    'super_admin': 'Super Administrator',
  };

  Widget _searchFilters(List<Widget> filters, VoidCallback reset) => _WebCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (_, box) => Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: math.min(340, box.maxWidth),
                child: TextFormField(
                  key: ValueKey('admin-search-$page-$submittedSearch'),
                  initialValue: submittedSearch,
                  onChanged: (value) => draftSearch = value,
                  onFieldSubmitted: _applySearch,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: 'Search all records...',
                  ),
                ),
              ),
              ...filters,
              FilledButton.icon(
                onPressed: () => _applySearch(draftSearch),
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Search'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  reset();
                  draftSearch = '';
                  _applySearch('');
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reset'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        Text(
          'Search covers all records. Filters below apply to the loaded page (up to $_pageSize records).',
          style: TextStyle(fontSize: 10, color: WebPortalColors.muted),
        ),
      ],
    ),
  );

  Widget _recordPager(int count) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '$count displayed · Page ${(offsets[page] ?? 0) ~/ _pageSize + 1}',
          style: TextStyle(fontSize: 11, color: WebPortalColors.muted),
        ),
        OutlinedButton(
          onPressed: (offsets[page] ?? 0) > 0
              ? () {
                  offsets[page] = offsets[page]! - _pageSize;
                  _refresh();
                }
              : null,
          child: const Text('Previous'),
        ),
        FilledButton(
          onPressed: hasMore[page] == true
              ? () {
                  offsets[page] = (offsets[page] ?? 0) + _pageSize;
                  _refresh();
                }
              : null,
          child: const Text('Next'),
        ),
      ],
    ),
  );

  List<Map<String, dynamic>> get _filteredUsers => users
      .where(
        (u) =>
            (userRole == 'all' ||
                _normalizedRole('${u['role']}') == userRole) &&
            (userStatus == 'all' ||
                (u['is_active'] == true) == (userStatus == 'active')) &&
            (provider == 'all' ||
                '${u['auth_provider'] ?? 'email'}' == provider),
      )
      .toList();

  Widget _usersPage() {
    final rows = _filteredUsers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          'User Management',
          'Manage Farmers, Analysts, and Super Administrators.',
          Icons.people_alt_rounded,
        ),
        const SizedBox(height: 20),
        _metrics([
          _metric(
            'Total Users',
            _totalUsers,
            Icons.people_alt_rounded,
            'All registered users',
          ),
          _metric(
            'Farmers',
            stats['farmers'],
            Icons.eco_rounded,
            'Farmer accounts',
          ),
          _metric(
            'Analysts',
            stats['planning_analysts'],
            Icons.bar_chart_rounded,
            'Analysis team',
            const Color(0xFF197BD1),
          ),
          _metric(
            'Super Administrators',
            stats['super_admins'],
            Icons.shield_rounded,
            'System administrators',
            const Color(0xFF8353C8),
          ),
        ]),
        const SizedBox(height: 16),
        _searchFilters(
          [
            _filter('Role', userRole, _roles, (v) => userRole = v),
            _filter(
              'Status',
              userStatus,
              const {
                'all': 'All status',
                'active': 'Active',
                'inactive': 'Inactive',
              },
              (v) => userStatus = v,
              width: 135,
            ),
            _filter('Sign-in Method', provider, {
              'all': 'All methods',
              'email': 'Email',
              'google': 'Google',
              for (final u in users)
                if (u['auth_provider'] != null)
                  '${u['auth_provider']}': '${u['auth_provider']}',
            }, (v) => provider = v),
          ],
          () {
            userRole = userStatus = provider = 'all';
          },
        ),
        const SizedBox(height: 16),
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AnalystSectionTitle(
                'User List',
                subtitle: 'Manage roles, account status and private recovery.',
                icon: Icons.badge_outlined,
                action: _exportButton(
                  'Users',
                  [
                    'User',
                    'Email',
                    'Role',
                    'Status',
                    'Sign-in Method',
                    'Created',
                  ],
                  rows
                      .map(
                        (u) => [
                          '${u['username']}',
                          '${u['email']}',
                          _roleLabel('${u['role']}'),
                          u['is_active'] == true ? 'Active' : 'Inactive',
                          '${u['auth_provider'] ?? 'email'}',
                          _adminDate(u['created_at']),
                        ],
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),
              if (rows.isEmpty)
                const _WebEmptyState(
                  title: 'No users found',
                  message:
                      'Change or clear these filters to see other accounts.',
                  icon: Icons.people_outline,
                )
              else
                _AdminTable(
                  minWidth: 1000,
                  columns: const [
                    'User',
                    'Role',
                    'Status',
                    'Sign-in Method',
                    'Created',
                    'Actions',
                  ],
                  rows: rows
                      .map(
                        (u) => DataRow(
                          cells: [
                            DataCell(
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 15,
                                    backgroundColor: softGreen,
                                    child: Text(
                                      '${u['username'] ?? ''}'.trim().isEmpty
                                          ? 'U'
                                          : '${u['username']}'
                                                .trim()[0]
                                                .toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: green,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 195,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${u['username'] ?? 'Unnamed'}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          '${u['email'] ?? ''}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: WebPortalColors.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            DataCell(
                              DropdownButton<String>(
                                key: ValueKey('admin-role-${u['id']}'),
                                value: _normalizedRole('${u['role']}'),
                                underline: const SizedBox.shrink(),
                                items: _roles.entries
                                    .where((entry) => entry.key != 'all')
                                    .map(
                                      (entry) => DropdownMenuItem(
                                        value: entry.key,
                                        child: Text(
                                          entry.value,
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    _changeUser(u, role: v);
                                  }
                                },
                              ),
                            ),
                            DataCell(
                              _SmallBadge(
                                u['is_active'] == true ? 'Active' : 'Inactive',
                                color: _adminStatusColor(
                                  u['is_active'] == true
                                      ? 'active'
                                      : 'inactive',
                                ),
                              ),
                            ),
                            DataCell(Text('${u['auth_provider'] ?? 'email'}')),
                            DataCell(Text(_adminDate(u['created_at']))),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Semantics(
                                    label:
                                        'Active account for ${u['username']}',
                                    child: Switch(
                                      key: ValueKey('admin-active-${u['id']}'),
                                      value: u['is_active'] == true,
                                      onChanged: (v) =>
                                          _changeUser(u, active: v),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip:
                                        'Recover account for ${u['username']}',
                                    onPressed: u['is_active'] == true
                                        ? () => _recovery(u)
                                        : null,
                                    icon: const Icon(
                                      Icons.lock_reset,
                                      size: 19,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              _recordPager(rows.length),
            ],
          ),
        ),
      ],
    );
  }

  String _normalizedRole(String r) {
    r = r.toLowerCase();
    if (r == 'admin' || r == 'super_admin') {
      return 'super_admin';
    }
    if (r.contains('analyst') || r == 'planner') {
      return 'agricultural_planning_analyst';
    }
    return 'farmer';
  }

  String _roleLabel(String r) => _roles[_normalizedRole(r)] ?? 'Farmer';

  List<Map<String, dynamic>> get _filteredAnalyses => analyses
      .where(
        (a) =>
            (analysisRole == 'all' ||
                _normalizedRole('${a['role']}') == analysisRole) &&
            (analysisStatus == 'all' ||
                '${a['verification_status'] ?? 'draft'}' == analysisStatus) &&
            (place == 'all' || '${a['place_name'] ?? ''}' == place) &&
            (crop == 'all' || '${a['predicted_crop'] ?? ''}' == crop),
      )
      .toList();

  Widget _analysesPage() {
    final rows = _filteredAnalyses;
    final counts = <String, double>{};
    for (final row in rows) {
      if (_hasCropResult(row)) {
        final name = '${row['predicted_crop']}';
        counts[name] = (counts[name] ?? 0) + 1;
      }
    }
    final frequencies = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          'Farm & Analysis Monitoring',
          'Monitor registered parcels and saved analysis records across the system.',
          Icons.landscape_rounded,
        ),
        const SizedBox(height: 20),
        _metrics([
          _metric(
            'Total Parcels',
            stats['registered_parcels'],
            Icons.map_rounded,
            'Current registered parcels',
          ),
          _metric(
            'Total Analyses',
            stats['total_analyses'],
            Icons.analytics_rounded,
            'All analysis records',
            const Color(0xFF197BD1),
          ),
          _metric(
            'Mapped Area',
            analysisNumber(stats['total_area_hectares']) == null
                ? null
                : '${analysisNumber(stats['total_area_hectares'])!.toStringAsFixed(2)} ha',
            Icons.eco_rounded,
            'Current registered parcels',
          ),
          _metric(
            'Pending Review',
            stats['pending'],
            Icons.schedule_rounded,
            'Analyses awaiting review',
            const Color(0xFFA96500),
          ),
        ]),
        const SizedBox(height: 16),
        _searchFilters(
          [
            _filter(
              'Owner role',
              analysisRole,
              _roles,
              (v) => analysisRole = v,
            ),
            _filter('Location', place, {
              'all': 'All locations',
              for (final a in analyses)
                if ('${a['place_name'] ?? ''}'.isNotEmpty)
                  '${a['place_name']}': '${a['place_name']}',
            }, (v) => place = v),
            _filter('Crop', crop, {
              'all': 'All crops',
              for (final a in analyses)
                if (_hasCropResult(a))
                  '${a['predicted_crop']}': '${a['predicted_crop']}',
            }, (v) => crop = v),
            _filter('Review status', analysisStatus, {
              'all': 'All status',
              for (final a in analyses)
                '${a['verification_status'] ?? 'draft'}':
                    '${a['verification_status'] ?? 'draft'}'.replaceAll(
                      '_',
                      ' ',
                    ),
            }, (v) => analysisStatus = v),
          ],
          () {
            analysisRole = analysisStatus = place = crop = 'all';
          },
        ),
        const SizedBox(height: 16),
        _AnalystColumns(
          main: _WebCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AnalystSectionTitle(
                  'Farm & Analysis Records',
                  subtitle: 'Saved records on the current filtered page.',
                  icon: Icons.assignment_outlined,
                  action: _exportButton(
                    'Analyses',
                    [
                      'Owner',
                      'Role',
                      'Location',
                      'Recorded Result',
                      'Area (ha)',
                      'Review Status',
                      'Date',
                    ],
                    rows
                        .map(
                          (a) => [
                            '${a['username'] ?? 'Unknown'}',
                            _roleLabel('${a['role']}'),
                            '${a['place_name'] ?? ''}',
                            _result(a),
                            _area(a),
                            '${a['verification_status'] ?? 'draft'}',
                            _adminDate(a['analyzed_at']),
                          ],
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 16),
                if (rows.isEmpty)
                  const _WebEmptyState(
                    title: 'No analysis records found',
                    message:
                        'Saved analyses will appear here. Change the filters to see other records.',
                    icon: Icons.analytics_outlined,
                  )
                else
                  _AdminTable(
                    minWidth: 930,
                    columns: const [
                      'Owner',
                      'Role',
                      'Location',
                      'Recorded Result',
                      'Area (ha)',
                      'Review Status',
                      'Date',
                      'Details',
                    ],
                    rows: rows
                        .map(
                          (a) => DataRow(
                            cells: [
                              DataCell(_ownerCell(a)),
                              DataCell(
                                _SmallBadge(
                                  _roleLabel('${a['role']}'),
                                  color: WebPortalColors.accent,
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 125,
                                  child: Text(
                                    '${a['place_name'] ?? 'Not recorded'}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(width: 120, child: Text(_result(a))),
                              ),
                              DataCell(Text(_area(a))),
                              DataCell(
                                _SmallBadge(
                                  '${a['verification_status'] ?? 'draft'}'
                                      .replaceAll('_', ' '),
                                  color: _adminStatusColor(
                                    '${a['verification_status'] ?? 'draft'}',
                                  ),
                                ),
                              ),
                              DataCell(Text(_adminDate(a['analyzed_at']))),
                              DataCell(
                                IconButton(
                                  tooltip: 'View analysis ${a['session_id']}',
                                  onPressed: () => _analysisDetails(a),
                                  icon: const Icon(
                                    Icons.visibility_outlined,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                _recordPager(rows.length),
              ],
            ),
          ),
          side: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AdminDistribution(rows),
              const SizedBox(height: 16),
              _AnalystBars(
                entries: frequencies.take(5).toList(),
                title: 'Top Recorded Crops',
                subtitle: 'Recorded crop results · filtered page',
                unit: 'records',
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _hasCropResult(Map<String, dynamic> a) => WebAnalysisMetrics.isCrop(a);
  String _result(Map<String, dynamic> a) =>
      _hasCropResult(a) ? '${a['predicted_crop']}' : 'Land assessment';
  String _area(Map<String, dynamic> a) =>
      analysisNumber(a['area_hectares'])?.toStringAsFixed(3) ?? 'Not recorded';

  Widget _ownerCell(Map<String, dynamic> a) => SizedBox(
    width: 140,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${a['username'] ?? 'Unknown'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text(
          '${a['email'] ?? ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10, color: WebPortalColors.muted),
        ),
      ],
    ),
  );

  Future<void> _analysisDetails(Map<String, dynamic> a) => showDialog<void>(
    context: context,
    builder: (context) {
      final status = '${a['verification_status'] ?? 'draft'}';
      final statusLabel = status.isEmpty
          ? 'Not recorded'
          : status[0].toUpperCase() + status.substring(1).replaceAll('_', ' ');
      Widget tile(String label, String value, IconData icon) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: WebPortalColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: WebPortalColors.accent.withValues(alpha: .12),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: WebPortalColors.tint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: WebPortalColors.accent, size: 21),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: WebPortalColors.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: WebPortalColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      return _AdminDialog(
        width: 720,
        title: 'Saved Analysis #${a['session_id']}',
        subtitle: 'Saved assessment details',
        icon: Icons.description_outlined,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AdminFieldGrid(
              minimumWidth: 185,
              maximumColumns: 3,
              children: [
                tile(
                  'Owner',
                  '${a['username'] ?? 'Unknown'}',
                  Icons.person_outline,
                ),
                tile(
                  'Location',
                  '${a['place_name'] ?? 'Not recorded'}',
                  Icons.location_on_outlined,
                ),
                tile('Area', '${_area(a)} ha', Icons.area_chart_outlined),
                tile('Recorded result', _result(a), Icons.layers_outlined),
                tile(
                  'Review status',
                  statusLabel,
                  Icons.verified_user_outlined,
                ),
                tile(
                  'Saved at',
                  _adminDate(a['analyzed_at'], time: true),
                  Icons.calendar_month_outlined,
                ),
              ],
            ),
            const SizedBox(height: 18),
            _AdminDialogSection(
              title: 'Review summary',
              icon: Icons.fact_check_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if ('${a['planner_notes'] ?? ''}'.trim().isNotEmpty) ...[
                    Text('${a['planner_notes']}'),
                    const SizedBox(height: 10),
                  ],
                  const Text(
                    'Review status describes the assessment review. A recorded crop result does not guarantee crop success.',
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _settingsPage() {
    final filtered =
        crops
            .where(
              (c) =>
                  "${c['label']} ${c['crop_key']} ${analysisListValue(c['varieties']).map((v) => analysisMapValue(v)['label']).join(' ')}"
                      .toLowerCase()
                      .contains(cropQuery.toLowerCase()),
            )
            .toList()
          ..sort(
            (a, b) => cropAscending
                ? '${a['label']}'.compareTo('${b['label']}')
                : '${b['label']}'.compareTo('${a['label']}'),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          'Crop & Season Settings',
          'Manage which approved crops GeoSustain can currently recommend, and their reference information.',
          Icons.calendar_month_rounded,
        ),
        const SizedBox(height: 20),
        _metrics([
          _metric(
            'Approved Crop Groups',
            crops.length,
            Icons.spa_rounded,
            'Approved reference set',
          ),
          _metric(
            'Active Crop Groups',
            crops.where((c) => c['is_active'] == true).length,
            Icons.check_circle_rounded,
            'Available for new recommendations',
            const Color(0xFF197BD1),
          ),
          _metric(
            'Inactive Crop Groups',
            crops.where((c) => c['is_active'] != true).length,
            Icons.pause_circle_outline,
            'Excluded from new recommendations',
            const Color(0xFFA96500),
          ),
          _metric(
            'Reference Versions',
            'Preserved',
            Icons.storage_rounded,
            'Existing analyses keep saved versions',
          ),
        ]),
        const SizedBox(height: 16),
        _AnalystColumns(
          main: ControlledRecordsPanel(api: api, adminDesign: true),
          side: _WebCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _AnalystSectionTitle(
                  'How it works',
                  icon: Icons.lightbulb_outline,
                ),
                const SizedBox(height: 16),
                for (final step in [
                  (1, 'Download the template and enter crop requirements.'),
                  (2, 'Import Excel and check the row preview.'),
                  (3, 'Save drafts or activate the checked rows.'),
                  (4, 'Existing analyses retain their saved versions.'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 11,
                          backgroundColor: WebPortalColors.tint,
                          child: Text(
                            '${step.$1}',
                            style: TextStyle(
                              fontSize: 10,
                              color: WebPortalColors.accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            step.$2,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _AnalystSectionTitle(
                'Approved crop reference',
                icon: Icons.eco_rounded,
                subtitle:
                    'Deactivating a crop removes it from new recommendations. The approved crop set and environmental scoring stay the same.',
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (_, box) => Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: math.min(300, box.maxWidth),
                      child: TextFormField(
                        key: const ValueKey('admin-crop-search'),
                        initialValue: cropQuery,
                        onChanged: (value) => setState(() => cropQuery = value),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search, size: 18),
                          hintText: 'Search crops or varieties...',
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          setState(() => cropAscending = !cropAscending),
                      icon: const Icon(Icons.sort_by_alpha, size: 17),
                      label: Text(cropAscending ? 'Name (A–Z)' : 'Name (Z–A)'),
                    ),
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: false,
                          icon: const Icon(Icons.view_list),
                          label: box.maxWidth >= 400
                              ? const Text('List')
                              : null,
                          tooltip: 'List view',
                        ),
                        ButtonSegment(
                          value: true,
                          icon: const Icon(Icons.grid_view),
                          label: box.maxWidth >= 400
                              ? const Text('Grid')
                              : null,
                          tooltip: 'Grid view',
                        ),
                      ],
                      selected: {cropGrid},
                      onSelectionChanged: (values) =>
                          setState(() => cropGrid = values.first),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (filtered.isEmpty)
                const _WebEmptyState(
                  title: 'No crop reference rows found',
                  message: 'Change the crop search to see other references.',
                  icon: Icons.spa_outlined,
                )
              else
                LayoutBuilder(
                  builder: (_, box) {
                    final columns = cropGrid && box.maxWidth >= 800 ? 2 : 1;
                    return Column(
                      children: [
                        for (
                          var start = 0;
                          start < filtered.length;
                          start += columns
                        )
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: WebAlignedCards(
                              spacing: 10,
                              children: [
                                for (
                                  var index = start;
                                  index <
                                      math.min(
                                        start + columns,
                                        filtered.length,
                                      );
                                  index++
                                )
                                  _cropRow(filtered[index]),
                                if (columns == 2 &&
                                    start + 1 == filtered.length)
                                  const SizedBox.shrink(),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cropRow(Map<String, dynamic> c) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: WebPortalColors.tint.withValues(alpha: .18),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: WebPortalColors.muted.withValues(alpha: .12)),
    ),
    child: LayoutBuilder(
      builder: (_, box) {
        final info = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CropArtwork('${c['label']}', size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${c['label']}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${c['growth_cycle'] ?? 'Cycle not recorded'} · ${c['est_yield'] ?? 'Yield not recorded'}',
                    style: TextStyle(
                      fontSize: 10,
                      color: WebPortalColors.muted,
                    ),
                  ),
                  if ('${c['suitability_note'] ?? ''}'.isNotEmpty)
                    Text(
                      '${c['suitability_note']}',
                      style: TextStyle(
                        fontSize: 10,
                        color: WebPortalColors.muted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
        final actions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Edit note for ${c['label']}',
              onPressed: () => _editCropNote(c),
              icon: const Icon(Icons.edit_note, size: 20),
            ),
            Semantics(
              label: 'Active crop ${c['label']}',
              child: Switch(
                key: ValueKey('admin-crop-${c['crop_key']}'),
                value: c['is_active'] == true,
                onChanged: (value) => _toggleCrop(c, value),
              ),
            ),
          ],
        );
        final header =
            box.maxWidth < 460 ||
                MediaQuery.textScalerOf(context).scale(14) > 20
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  info,
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              )
            : Row(
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 10),
                  actions,
                ],
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            if (c['crop_key'] == 'banana')
              const CropVarietyReference(crop: 'banana'),
          ],
        );
      },
    ),
  );

  List<Map<String, dynamic>> get _filteredAudit => auditLogs
      .where((log) => auditAction == 'all' || log['action'] == auditAction)
      .toList();

  Widget _auditPage() {
    final rows = _filteredAudit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          'Audit & System',
          'Monitor recorded administrative activity and review access and reference changes.',
          Icons.verified_user_rounded,
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final tab in [
              ('activity', 'Recent Activity', Icons.monitor_heart_outlined),
              ('logs', 'Logs', Icons.description_outlined),
              ('monitoring', 'System Monitoring', Icons.cloud_outlined),
            ])
              ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(tab.$3, size: 16),
                    const SizedBox(width: 8),
                    Text(tab.$2),
                  ],
                ),
                selected: auditTab == tab.$1,
                onSelected: (_) => setState(() => auditTab = tab.$1),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (auditTab == 'monitoring')
          _monitoringCard()
        else ...[
          if (auditTab == 'activity') ...[
            _WebCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _AnalystSectionTitle(
                    'Activity Overview',
                    subtitle: 'Recorded events on the loaded audit page',
                    icon: Icons.bar_chart_rounded,
                  ),
                  const SizedBox(height: 14),
                  _metrics([
                    _mini(
                      'Loaded events',
                      '${auditLogs.length}',
                      Icons.people_alt_rounded,
                    ),
                    _mini(
                      'Account changes',
                      '${auditLogs.where((a) => a['action'] == 'user_update').length}',
                      Icons.manage_accounts_outlined,
                    ),
                    _mini(
                      'Review decisions',
                      '${auditLogs.where((a) => a['action'] == 'verification_decision' || a['action'] == 'review_verified' || a['action'] == 'review_rejected').length}',
                      Icons.fact_check_outlined,
                    ),
                    _mini(
                      'Reference changes',
                      '${auditLogs.where((a) => '${a['action']}'.startsWith('controlled_record_') || a['action'] == 'crop_reference_update').length}',
                      Icons.calendar_month_outlined,
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          _searchFilters([
            _filter(
              'Action',
              auditAction,
              {
                'all': 'All actions',
                for (final log in auditLogs)
                  '${log['action']}': log['action'] == 'sign_in'
                      ? 'Signed in'
                      : '${log['action']}'.replaceAll('_', ' '),
              },
              (v) => auditAction = v,
              width: 240,
            ),
          ], () => auditAction = 'all'),
          const SizedBox(height: 16),
          _AnalystColumns(
            main: _WebCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AnalystSectionTitle(
                    'Recent Activity Logs',
                    subtitle:
                        'Sign-ins, account changes, reference updates and review decisions.',
                    icon: Icons.description_rounded,
                    action: _exportButton(
                      'Audit Logs',
                      ['Timestamp', 'User', 'Role', 'Action', 'Details'],
                      rows
                          .map(
                            (a) => [
                              _adminDate(a['created_at'], time: true),
                              _actor(a),
                              _auditRole(a),
                              '${a['action']}',
                              _auditDetails(a),
                            ],
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _auditTable(rows),
                  _recordPager(rows.length),
                ],
              ),
            ),
            side: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _monitoringCard(),
                const SizedBox(height: 16),
                _WebCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _AnalystSectionTitle(
                        'Quick Actions',
                        icon: Icons.bolt_rounded,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MessageLogPage(api: api),
                          ),
                        ),
                        icon: const Icon(
                          Icons.notifications_outlined,
                          size: 17,
                        ),
                        label: const Text('Push delivery log'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => PortalRoutes.go('/admin/users'),
                        icon: const Icon(Icons.shield_outlined, size: 17),
                        label: const Text('Manage Access'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _monitoringCard() {
    final checks = analysisListValue(
      systemStatus?['checks'],
    ).map(analysisMapValue).toList();
    final healthy = systemStatus?['status'] == 'healthy';
    String label(String status) => switch (status) {
      'healthy' => 'Available',
      'unavailable' => 'Needs attention',
      'client_side' => 'Browser check',
      _ => 'Not checked',
    };
    return _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AnalystSectionTitle(
            'System Monitoring',
            icon: Icons.monitor_heart_outlined,
            action: IconButton(
              tooltip: 'Check services now',
              onPressed: loading ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ),
          const SizedBox(height: 14),
          if (systemStatus == null) ...[
            Text(
              loading ? 'Checking services...' : 'Service check unavailable',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (!loading)
              Text(monitoringError ?? 'Refresh to request a new check.'),
          ] else ...[
            _SmallBadge(
              healthy ? 'Server checks passed' : 'Service needs attention',
              color: healthy
                  ? WebPortalColors.accent
                  : Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 8),
            Text(
              'Checked ${_adminDate(systemStatus!['checked_at'], time: true)}',
              style: TextStyle(fontSize: 11, color: WebPortalColors.muted),
            ),
            const SizedBox(height: 12),
            for (final service in checks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      service['status'] == 'healthy'
                          ? Icons.check_circle_outline
                          : service['status'] == 'unavailable'
                          ? Icons.warning_amber_rounded
                          : Icons.language,
                      size: 19,
                      color: service['status'] == 'unavailable'
                          ? Theme.of(context).colorScheme.error
                          : WebPortalColors.accent,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${service['label']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${service['message']}',
                            style: TextStyle(
                              fontSize: 11,
                              color: WebPortalColors.muted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            label('${service['status']}'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: service['status'] == 'unavailable'
                                  ? Theme.of(context).colorScheme.error
                                  : WebPortalColors.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(),
            Text(
              'Point-in-time checks. Maps require a browser check; hosting uptime and backups remain in Render and Supabase.',
              style: TextStyle(fontSize: 11, color: WebPortalColors.muted),
            ),
          ],
        ],
      ),
    );
  }

  String _auditRole(Map<String, dynamic> log) {
    final role = '${log['actor_role'] ?? ''}';
    if (role == 'system_migration') return 'System';
    if (role == 'trusted_operator') return 'Setup operator';
    if (role.isEmpty) return 'Not recorded';
    if (![
      'farmer',
      'analyst',
      'planner',
      'admin',
      'super_admin',
      'agricultural_planning_analyst',
    ].contains(role)) {
      return role.replaceAll('_', ' ');
    }
    return _roleLabel(role);
  }

  String _actor(Map<String, dynamic> log) {
    if (log['actor_username'] != null) return '${log['actor_username']}';
    if (log['actor_email'] != null) return '${log['actor_email']}';
    if (log['actor_role'] == 'system_migration') return 'System maintenance';
    if (log['actor_role'] == 'trusted_operator') return 'Setup operator';
    return '${log['actor_reference'] ?? 'Unknown actor'}';
  }

  String _auditDetails(Map<String, dynamic> log) {
    final detail = log['details'];
    if (detail is! Map) {
      return 'No additional details';
    }
    final safe = _safeAuditDetails(detail);
    return safe.isEmpty
        ? 'No additional details'
        : safe.entries
              .map((e) => '${e.key.replaceAll('_', ' ')}: ${e.value}')
              .join(' · ');
  }

  Map<String, dynamic> _safeAuditDetails(Map details) => {
    for (final key in [
      'decision',
      'method',
      'channel',
      'role',
      'before_role',
      'is_active',
      'crop_key',
      'kind',
      'record_key',
      'revision',
      'before_record_id',
      'after_record_id',
      'generation',
    ])
      if (details.containsKey(key)) key: details[key],
  };

  Widget _auditTable(
    List<Map<String, dynamic>> rows, {
    bool dashboard = false,
  }) => rows.isEmpty
      ? const _WebEmptyState(
          title: 'No audit activity recorded yet',
          message: 'Recorded administrative changes will appear here.',
          icon: Icons.history_rounded,
        )
      : _AdminTable(
          minWidth: dashboard ? 620 : 850,
          columns: const ['User', 'Role', 'Action', 'Details', 'Date & Time'],
          rows: rows
              .map(
                (log) => DataRow(
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 130,
                        child: Text(
                          _actor(log),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    DataCell(
                      _SmallBadge(
                        _auditRole(log),
                        color: WebPortalColors.accent,
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 115,
                        child: Text(
                          log['action'] == 'sign_in'
                              ? 'Signed in'
                              : '${log['action']}'.replaceAll('_', ' '),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 170,
                        child: Text(
                          _auditDetails(log),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Recorded change details'),
                          content: SingleChildScrollView(
                            child: SelectableText(
                              'Actor: ${_actor(log)}\nDate: ${_adminDate(log['created_at'], time: true)}\n${_auditDetails(log)}',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    DataCell(Text(_adminDate(log['created_at'], time: true))),
                  ],
                ),
              )
              .toList(),
        );

  Widget _exportButton(
    String title,
    List<String> headers,
    List<List<String>> rows,
  ) => IconButton.outlined(
    tooltip: 'Export displayed ${title.toLowerCase()}',
    icon: const Icon(Icons.download_outlined, size: 18),
    onPressed: rows.isEmpty
        ? null
        : () async {
            try {
              final regular = await rootBundle.load(
                'assets/fonts/NotoSans-Regular.ttf',
              );
              final bold = await rootBundle.load(
                'assets/fonts/NotoSans-Bold.ttf',
              );
              final symbols = await rootBundle.load(
                'assets/fonts/NotoSansSymbols2-Regular.ttf',
              );
              final document = pw.Document(
                theme: pw.ThemeData.withFont(
                  base: pw.Font.ttf(regular),
                  bold: pw.Font.ttf(bold),
                  fontFallback: [pw.Font.ttf(symbols)],
                ),
              );
              document.addPage(
                pw.MultiPage(
                  pageFormat: PdfPageFormat.a4.landscape,
                  build: (_) => [
                    pw.Header(level: 0, child: pw.Text('GeoSustain - $title')),
                    pw.Paragraph(
                      text:
                          'Displayed records only. Search: ${submittedSearch.isEmpty ? 'none' : submittedSearch}. Page ${(offsets[page] ?? 0) ~/ _pageSize + 1}.',
                    ),
                    pw.TableHelper.fromTextArray(
                      headers: headers,
                      data: rows,
                      cellStyle: const pw.TextStyle(fontSize: 8),
                      headerStyle: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
              final bytes = await document.save();
              await Printing.layoutPdf(
                name: 'GeoSustain-${title.replaceAll(' ', '-')}.pdf',
                onLayout: (_) async => bytes,
              );
            } catch (error) {
              widget.message('Export failed: ${friendlyErrorMessage(error)}');
            }
          },
  );
}
