part of '../main.dart';

class WebAnalystDashboard extends StatefulWidget {
  final AnalysisState state;
  final VoidCallback logout;
  final ValueChanged<String> message;
  const WebAnalystDashboard({
    super.key,
    required this.state,
    required this.logout,
    required this.message,
  });

  @override
  State<WebAnalystDashboard> createState() => _WebAnalystDashboardState();
}

class _WebAnalystDashboardState extends State<WebAnalystDashboard> {
  int page = 0;
  bool popupVisible = true;
  Map<String, dynamic>? previousAnalysis;
  int? previousAnalysisOwner;
  late final reviewInbox = WebRecordController(
    widget.state.api,
    '/api/operator/inbox',
    'queue',
  );
  String _lastInboxFilter = '';
  late final reviewMap = WebRecordController(
    widget.state.api,
    '/api/operator/map',
    'queue',
    limit: 50,
  )..parameters = {'status': 'all'};
  final planningMap = MapController();

  AnalysisState get state => widget.state;

  Future<void> runWebAnalysis() async {
    if (state.polygonPoints.isNotEmpty && state.polygonPoints.length < 3) {
      widget.message(
        'Complete a boundary with at least three distinct points, or clear it to analyze a point.',
      );
      return;
    }
    final epoch = state._sessionEpoch;
    final previous = state.result == null
        ? previousAnalysis
        : Map<String, dynamic>.from(state.result!);
    final owner = state.currentUser?['id'];
    final err = state.polygonPoints.length >= 3
        ? await state.analyzePolygon()
        : await state.analyzePoint();
    if (err != null) widget.message(err);
    if (mounted && epoch == state._sessionEpoch) {
      setState(() {
        popupVisible = true;
        previousAnalysis = err == null ? null : previous;
        previousAnalysisOwner = owner is int ? owner : null;
      });
    }
  }

  List<String> get routePages => [
    'dashboard',
    'map',
    'analyze',
    'history',
    'reports',
    'trends',
    if (state.isPlanner) 'queue',
    'settings',
    'activity',
  ];
  @override
  void initState() {
    super.initState();
    PortalRoutes.start();
    unawaited(state.refreshCurrentModelSummary());
    if (state.isPlanner) {
      final canonical = PortalRoutes.analystRoute(PortalRoutes.current.value);
      if (canonical != PortalRoutes.current.value) {
        PortalRoutes.go('$canonical');
      }
    }
    page = PortalRoutes.pageFor(routePages, 'operator');
    PortalRoutes.current.addListener(_routeChanged);
    if (state.isPlanner) _loadInboxRoute();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openLinkedRecord());
  }

  void _routeChanged() {
    if (!mounted) return;
    if (state.isPlanner) {
      final canonical = PortalRoutes.analystRoute(PortalRoutes.current.value);
      if (canonical != PortalRoutes.current.value) {
        PortalRoutes.go('$canonical');
        return;
      }
    }
    final previousPage = page;
    setState(() => page = PortalRoutes.pageFor(routePages, 'operator'));
    if (page != previousPage && page == routePages.indexOf('dashboard')) {
      unawaited(state.refreshCurrentModelSummary());
    }
    if (state.isPlanner) _loadInboxRoute();
    _openLinkedRecord();
    if (state.isPlanner &&
        previousPage == routePages.indexOf('queue') &&
        page == previousPage &&
        !PortalRoutes.current.value.queryParameters.containsKey('case') &&
        !PortalRoutes.current.value.queryParameters.containsKey('session') &&
        !reviewInbox.loading) {
      reviewInbox.load();
    }
  }

  void _navigate(int index) {
    PortalRoutes.go('/operator/${routePages[index]}');
  }

  void _loadInboxRoute() {
    final uri = PortalRoutes.current.value;
    if (uri.queryParameters.containsKey('case') ||
        uri.queryParameters.containsKey('session')) {
      return;
    }
    // Returning from a case keeps the inbox page and applied filters.
    if (uri.path.endsWith('/queue') && uri.queryParameters.isNotEmpty) {
      final signature = uri.query;
      if (signature != _lastInboxFilter) {
        _lastInboxFilter = signature;
        reviewInbox.query = uri.queryParameters['q'] ?? '';
        reviewInbox.filter({
          'status': uri.queryParameters['status'] ?? 'pending',
          'place': uri.queryParameters['place'] ?? '',
          'view': uri.queryParameters['view'] ?? 'all',
          'sort': uri.queryParameters['sort'] ?? 'oldest',
          if (uri.queryParameters['start'] != null)
            'start': uri.queryParameters['start']!,
          if (uri.queryParameters['end'] != null)
            'end': uri.queryParameters['end']!,
        });
      }
    } else if (!reviewInbox.loaded && !reviewInbox.loading) {
      reviewInbox.filter({'status': 'pending'});
    }
  }

  int? _openedRecord;
  int _recordGeneration = 0;
  Future<void> _openLinkedRecord() async {
    final request = ++_recordGeneration;
    if (page != routePages.indexOf('history')) {
      _openedRecord = null;
      return;
    }
    final id = int.tryParse(
      PortalRoutes.current.value.queryParameters['session'] ?? '',
    );
    if (id == null) {
      _openedRecord = null;
      return;
    }
    if (id <= 0 || id == _openedRecord) return;
    _openedRecord = id;
    if (page == routePages.indexOf('queue') && state.isPlanner) {
      return; // The routed workbench owns its loading, errors and evidence.
    } else if (page == routePages.indexOf('history')) {
      try {
        final record = await state.api.getAnalysis(id);
        if (!mounted || request != _recordGeneration) return;
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('Recorded analysis #$id'),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: WebAnalysisEvidence(state: state, record: record),
              ),
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
  }

  @override
  void dispose() {
    PortalRoutes.current.removeListener(_routeChanged);
    reviewInbox.dispose();
    reviewMap.dispose();
    planningMap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WebPortalFrame(
    state: state,
    navigation: _WebSidebar(
      state: state,
      selectedIndex: page,
      onSelect: _navigate,
      logout: widget.logout,
    ),
    child: ListenableBuilder(
      listenable: state,
      builder: (_, _) => _WebPageFrame(
        page: page,
        state: state,
        popupVisible: popupVisible,
        onClosePopup: () => setState(() => popupVisible = false),
        onAnalyze: runWebAnalysis,
        message: widget.message,
        onNavigate: _navigate,
        reviewInbox: reviewInbox,
        reviewMap: reviewMap,
        planningMap: planningMap,
        previousAnalysis: previousAnalysisOwner == state.currentUser?['id']
            ? previousAnalysis
            : null,
      ),
    ),
  );
}

class _WebSidebar extends StatelessWidget {
  final AnalysisState state;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback logout;
  const _WebSidebar({
    required this.state,
    required this.selectedIndex,
    required this.onSelect,
    required this.logout,
  });

  // Keep existing route indices so saved links and browser history still work.
  static List<(int, IconData, String)> itemsFor(bool isPlanner) => [
    (0, Icons.dashboard_rounded, 'Overview'),
    (1, Icons.map_rounded, 'Planning Map'),
    if (!isPlanner)
      (2, Icons.center_focus_strong_rounded, 'Analysis Workspace'),
    if (!isPlanner) (3, Icons.history_rounded, 'My Analyses'),
    (4, Icons.picture_as_pdf_rounded, 'Reports'),
    (5, Icons.show_chart_rounded, 'Recommendation Patterns'),
    if (isPlanner) (6, Icons.fact_check_rounded, 'Review Inbox'),
    (isPlanner ? 7 : 6, Icons.settings_rounded, 'Settings'),
    (isPlanner ? 8 : 7, Icons.notifications_outlined, 'Activity'),
  ];

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final name =
        '${state.currentUser?['username'] ?? state.currentUser?['name'] ?? 'Analyst'}';
    return Material(
      color: const Color(0xFF003D32),
      child: Container(
        width: 224,
        decoration: const BoxDecoration(
          color: Color(0xFF003D32),
          image: DecorationImage(
            image: AssetImage('assets/images/web/analyst_sidebar_valley.png'),
            alignment: Alignment.bottomCenter,
            fit: BoxFit.fitWidth,
          ),
        ),
        child: ListView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(14, 22, 14, 180),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.eco_rounded,
                    color: Color(0xFF76D99D),
                    size: 32,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GeoSustain',
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Agricultural Insights Platform',
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            color: Color(0xFFCEE3DB),
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: const Color(0xFF2D8068),
                    child: Text(
                      name.isEmpty ? 'A' : name[0].toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'Roboto',
                        color: Colors.white,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Roboto',
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Text(
                          'Analyst',
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            color: Color(0xFFCEE3DB),
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
            for (final item in itemsFor(state.isPlanner)) ...[
              if (item.$3 == 'Settings')
                const Divider(color: Colors.white24, height: 24),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Semantics(
                  selected: selectedIndex == item.$1,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        if (Scaffold.maybeOf(context)?.isDrawerOpen == true) {
                          Navigator.pop(context);
                        }
                        onSelect(item.$1);
                      },
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient: selectedIndex == item.$1
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFF16784F),
                                    Color(0xFF237F56),
                                  ],
                                )
                              : null,
                          borderRadius: BorderRadius.circular(10),
                          border: selectedIndex == item.$1
                              ? Border.all(
                                  color: const Color(0xFF7DD7A4),
                                  width: .6,
                                )
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(item.$2, color: Colors.white, size: 20),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                item.$3,
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: selectedIndex == item.$1
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
              ),
            ],
            TextButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Log out?'),
                    content: const Text(
                      'You can sign in again to continue reviewing submissions.',
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
                if (confirmed == true) logout();
              },
              icon: const Icon(Icons.logout_rounded, size: 20),
              label: const Align(
                alignment: Alignment.centerLeft,
                child: Text('Logout'),
              ),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WebPageFrame extends StatelessWidget {
  final Map<String, dynamic>? previousAnalysis;
  final WebRecordController reviewInbox;
  final WebRecordController reviewMap;
  final MapController planningMap;
  final int page;
  final AnalysisState state;
  final bool popupVisible;
  final VoidCallback onClosePopup;
  final Future<void> Function() onAnalyze;
  final ValueChanged<String> message;
  final ValueChanged<int> onNavigate;
  const _WebPageFrame({
    required this.page,
    required this.state,
    required this.popupVisible,
    required this.onClosePopup,
    required this.onAnalyze,
    required this.message,
    required this.onNavigate,
    required this.reviewInbox,
    required this.reviewMap,
    required this.planningMap,
    required this.previousAnalysis,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final isPlanner = state.isPlanner;
    final titles = [
      'Overview',
      'Planning Map',
      'Analysis Workspace',
      'My Analyses',
      'Reports',
      'Recommendation Patterns',
      if (isPlanner) 'Review Inbox',
      'Settings',
      'Activity',
    ];
    final subtitles = [
      'Overview of suitability results, live conditions, and quick actions',
      'Review analyzed areas, map markers, and saved field boundaries',
      'Run an independent point or boundary analysis; review farmer submissions separately in the inbox',
      isPlanner
          ? 'Your analyst assessments; farmer submissions are in the Review Inbox'
          : 'Review previously analyzed land records with dates and recommendations',
      'Open and export generated suitability reports',
      'Compare crop recommendation frequencies and suitability patterns',
      if (isPlanner)
        'Review saved evidence, request information and record decisions',
      'Manage dashboard preferences and account settings',
      'Your recent activity across analyses, submissions, and reviews.',
    ];
    final index = page.clamp(0, titles.length - 1);

    Widget body;
    if (page == 0) {
      body = WebDashboardScreen(
        state: state,
        onStartAnalyze: () => onNavigate(2),
        onOpenMapAnalysis: () => onNavigate(1),
        onOpenHistory: () => onNavigate(3),
        onOpenReports: () => onNavigate(4),
      );
    } else if (page == 1) {
      body = isPlanner
          ? WebAnalystPlanningMap(
              state: state,
              controller: reviewMap,
              mapController: planningMap,
            )
          : WebMapScreen(
              state: state,
              popupVisible: popupVisible,
              onClosePopup: onClosePopup,
              onGoToAnalyzeArea: () => onNavigate(2),
            );
    } else if (page == 2) {
      body = WebAnalyzeScreen(
        state: state,
        onAnalyze: onAnalyze,
        previousAnalysis: previousAnalysis,
      );
    } else if (page == 3) {
      body = WebHistoryScreen(
        key: ValueKey(
          'history-${PortalRoutes.current.value.queryParameters['q'] ?? ''}',
        ),
        state: state,
      );
    } else if (page == 4) {
      body = WebReportsScreen(state: state);
    } else if (page == 5) {
      body = WebCropTrendsScreen(state: state);
    } else if (isPlanner && page == 6) {
      final query = PortalRoutes.current.value.queryParameters;
      final reference = query['case'] ?? query['session'];
      body = reference == null
          ? WebOperatorInbox(controller: reviewInbox)
          : WebReviewWorkbench(
              key: ValueKey('case-${query['case']}-${query['session']}'),
              state: state,
              reference: reference,
              bySession: !query.containsKey('case'),
            );
    } else if (page == (isPlanner ? 8 : 7)) {
      body = NotificationsPage(state: state, webLayout: true);
    } else {
      body = WebSettingsScreen(state: state);
    }

    return _AnalystPageCanvas(
      child: CustomScrollView(
        key: PageStorageKey(
          'web_page_${index}_${PortalRoutes.current.value.queryParameters['case'] ?? PortalRoutes.current.value.queryParameters['session'] ?? 'list'}',
        ),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              MediaQuery.sizeOf(context).width < 600 ? 16 : 22,
              20,
              MediaQuery.sizeOf(context).width < 600 ? 16 : 22,
              32,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (page != 0) ...[
                  _WebHeader(
                    title: titles[index],
                    subtitle: subtitles[index],
                    state: state,
                    message: message,
                  ),
                  SizedBox(height: 18),
                ],
                body,
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
