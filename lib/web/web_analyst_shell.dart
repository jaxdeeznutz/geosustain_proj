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

  AnalysisState get state => widget.state;

  Future<void> runWebAnalysis() async {
    if (state.polygonPoints.isNotEmpty && state.polygonPoints.length < 3) {
      widget.message(
        'Complete a boundary with at least three distinct points, or clear it to analyze a point.',
      );
      return;
    }
    final err = state.polygonPoints.length >= 3
        ? await state.analyzePolygon()
        : await state.analyzePoint();
    if (err != null) widget.message(err);
    if (mounted) setState(() => popupVisible = true);
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _openLinkedRecord());
  }

  void _routeChanged() {
    if (!mounted) return;
    setState(() => page = PortalRoutes.pageFor(routePages, 'operator'));
    _openLinkedRecord();
  }

  void _navigate(int index) {
    PortalRoutes.go('/operator/${routePages[index]}');
  }

  int? _openedRecord;
  Future<void> _openLinkedRecord() async {
    final id = int.tryParse(
      PortalRoutes.current.value.queryParameters['session'] ?? '',
    );
    if (id == null || id <= 0 || id == _openedRecord) return;
    _openedRecord = id;
    if (page == routePages.indexOf('queue') && state.isPlanner) {
      await openPlannerAnalysisReview(context, state, id);
    } else if (page == routePages.indexOf('history')) {
      try {
        final record = await state.api.getAnalysis(id);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('Recorded analysis'),
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

  static final _baseItems = [
    (Icons.dashboard_rounded, 'Dashboard'),
    (Icons.map_rounded, 'Map Analysis'),
    (Icons.center_focus_strong_rounded, 'Analyze Area'),
    (Icons.history_rounded, 'Analysis History'),
    (Icons.picture_as_pdf_rounded, 'Reports'),
    (Icons.show_chart_rounded, 'Crop Trends'),
  ];
  static final _plannerItem = (Icons.fact_check_rounded, 'Verification Queue');
  static final _settingsItem = (Icons.settings_rounded, 'Settings');
  static final _activityItem = (Icons.notifications_outlined, 'Activity');

  static List<(IconData, String)> itemsFor(bool isPlanner) => [
    ..._baseItems,
    if (isPlanner) _plannerItem,
    _settingsItem,
    _activityItem,
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
            separatorBuilder: (_, _) => SizedBox(height: 6),
            itemBuilder: (_, i) {
              final rowItems = itemsFor(state.isPlanner);
              final selected = selectedIndex == i;
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  if (Scaffold.maybeOf(context)?.isDrawerOpen == true) {
                    Navigator.pop(context);
                  }
                  onSelect(i);
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
                      Icon(rowItems[i].$1, color: Colors.white, size: 22),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          rowItems[i].$2,
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
  });

  @override
  Widget build(BuildContext context) {
    final isPlanner = state.isPlanner;
    final titles = [
      'Dashboard',
      'Map Analysis',
      'Analyze Area',
      'Analysis History',
      'Reports',
      'Crop Trends',
      if (isPlanner) 'Verification Queue',
      'Settings',
      'Activity',
    ];
    final subtitles = [
      'Overview of suitability results, live conditions, and quick actions',
      'Review analyzed areas, map markers, and saved field boundaries',
      'Run point or polygon-based crop and land suitability analysis',
      'Review previously analyzed land records with dates and recommendations',
      'Open and export generated suitability reports',
      'Compare crop recommendation frequencies and suitability patterns',
      if (isPlanner)
        'Review farmer-submitted land analyses and approve or reject them',
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
      body = WebMapScreen(
        state: state,
        popupVisible: popupVisible,
        onClosePopup: onClosePopup,
        onGoToAnalyzeArea: () => onNavigate(2),
      );
    } else if (page == 2) {
      body = WebAnalyzeScreen(state: state, onAnalyze: onAnalyze);
    } else if (page == 3) {
      body = WebHistoryScreen(state: state);
    } else if (page == 4) {
      body = WebReportsScreen(state: state);
    } else if (page == 5) {
      body = WebCropTrendsScreen(state: state);
    } else if (isPlanner && page == 6) {
      body = WebPlannerQueueScreen(state: state);
    } else if (page == (isPlanner ? 8 : 7)) {
      body = NotificationsPage(state: state);
    } else {
      body = WebSettingsScreen(state: state);
    }

    return SizedBox.expand(
      child: CustomScrollView(
        key: ValueKey('web_page_$index'),
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
