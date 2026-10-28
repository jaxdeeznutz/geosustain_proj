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
    page = PortalRoutes.pageFor(routePages, 'operator');
    PortalRoutes.current.addListener(_routeChanged);
    if (state.isPlanner) _loadInboxRoute();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openLinkedRecord());
  }

  void _routeChanged() {
    if (!mounted) return;
    final previousPage = page;
    setState(() => page = PortalRoutes.pageFor(routePages, 'operator'));
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
    if (uri.path.endsWith('/queue') &&
        uri.queryParameters.containsKey('status')) {
      final signature = uri.query;
      if (signature != _lastInboxFilter) {
        _lastInboxFilter = signature;
        reviewInbox.filter({
          'status': uri.queryParameters['status']!,
          'place': uri.queryParameters['place'] ?? '',
          'view': uri.queryParameters['view'] ?? 'all',
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
    (0, Icons.dashboard_rounded, isPlanner ? 'Dashboard' : 'Overview'),
    if (isPlanner) (6, Icons.fact_check_rounded, 'Review Inbox'),
    (1, Icons.map_rounded, 'Planning Map'),
    (
      2,
      Icons.center_focus_strong_rounded,
      isPlanner ? 'Analyze Area' : 'Analysis Workspace',
    ),
    (
      3,
      Icons.history_rounded,
      isPlanner ? 'Assessment Records' : 'My Analyses',
    ),
    (4, Icons.picture_as_pdf_rounded, 'Reports'),
    if (!isPlanner) (5, Icons.show_chart_rounded, 'Recommendation Patterns'),
    (isPlanner ? 7 : 6, Icons.settings_rounded, 'Settings'),
    (isPlanner ? 8 : 7, Icons.notifications_outlined, 'Activity'),
  ];

  @override
  Widget build(BuildContext context) {
    final name =
        '${state.currentUser?['username'] ?? state.currentUser?['name'] ?? 'Analyst'}';
    return Container(
      width: 280,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF064E2E), Color(0xFF08733F)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: ListView(
        children: [
          Row(
            children: [
              Icon(Icons.eco_rounded, color: Colors.white, size: 34),
              SizedBox(width: 12),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'GeoSustain',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 34),
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: WebPortalColors.surface.withValues(alpha: .2),
                child: Text(
                  name.isEmpty ? 'A' : name[0].toUpperCase(),
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'Agricultural Planning Analyst',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 28),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: itemsFor(state.isPlanner).length,
            separatorBuilder: (_, i) => i == 5
                ? const Divider(color: Colors.white30, height: 28)
                : const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final rowItems = itemsFor(state.isPlanner);
              final item = rowItems[i];
              final selected =
                  selectedIndex == item.$1 ||
                  (selectedIndex == 5 && item.$1 == 4);
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  if (Scaffold.maybeOf(context)?.isDrawerOpen == true) {
                    Navigator.pop(context);
                  }
                  onSelect(item.$1);
                },
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: .20)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(item.$2, color: Colors.white, size: 22),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          item.$3,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: logout,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.logout_rounded, color: Colors.white),
                  SizedBox(width: 14),
                  Text(
                    'Logout',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
    final isPlanner = state.isPlanner;
    final titles = [
      isPlanner ? 'Dashboard' : 'Overview',
      'Planning Map',
      isPlanner ? 'Analyze Area' : 'Analysis Workspace',
      isPlanner ? 'Assessment Records' : 'My Analyses',
      'Reports',
      'Recommendation Patterns',
      if (isPlanner) 'Review Inbox',
      'Settings',
      'Activity',
    ];
    final subtitles = [
      'Overview of suitability results, live conditions, and quick actions',
      'Review analyzed areas, map markers, and saved field boundaries',
      isPlanner
          ? 'Create an independent analyst assessment using a point or boundary'
          : 'Run point or polygon-based crop and land suitability analysis',
      isPlanner
          ? 'Your analyst assessments; farmer submissions are in the Review Inbox'
          : 'Review previously analyzed land records with dates and recommendations',
      'Open and export generated suitability reports',
      'Compare crop recommendation frequencies and suitability patterns',
      if (isPlanner)
        'Review saved evidence, request information and record decisions',
      'Manage dashboard preferences and account settings',
      'Analysis, review and account activity',
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
              onContinue: () => onNavigate(2),
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
      body = WebHistoryScreen(state: state);
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
      body = NotificationsPage(state: state);
    } else {
      body = WebSettingsScreen(state: state);
    }

    return SizedBox.expand(
      child: CustomScrollView(
        key: PageStorageKey(
          'web_page_${index}_${PortalRoutes.current.value.queryParameters['case'] ?? PortalRoutes.current.value.queryParameters['session'] ?? 'list'}',
        ),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(32, 28, 32, 40),
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
                if (page == (isPlanner ? 8 : 7))
                  SizedBox(
                    height: math.max(
                      400.0,
                      MediaQuery.sizeOf(context).height - 220,
                    ),
                    child: body,
                  )
                else
                  body,
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
