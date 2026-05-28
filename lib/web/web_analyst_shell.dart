part of geosustain_mobile;

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
    final err = state.polygonPoints.length >= 3
        ? await state.analyzePolygon()
        : await state.analyzePoint();
    if (err != null) widget.message(err);
    if (mounted) setState(() => popupVisible = true);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF4F8F5),
      child: Row(
        children: [
          _WebSidebar(
            state: state,
            selectedIndex: page,
            onSelect: (i) => setState(() => page = i),
            logout: widget.logout,
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: state,
              builder: (_, __) => _WebPageFrame(
                page: page,
                state: state,
                popupVisible: popupVisible,
                onClosePopup: () => setState(() => popupVisible = false),
                onAnalyze: runWebAnalysis,
                message: widget.message,
                onNavigate: (i) => setState(() => page = i),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WebSidebar extends StatelessWidget {
  final AnalysisState state;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback logout;
  const _WebSidebar({required this.state, required this.selectedIndex, required this.onSelect, required this.logout});

  static const items = [
    (Icons.dashboard_rounded, 'Dashboard'),
    (Icons.map_rounded, 'Map Analysis'),
    (Icons.center_focus_strong_rounded, 'Analyze Area'),
    (Icons.history_rounded, 'Analysis History'),
    (Icons.picture_as_pdf_rounded, 'Reports'),
    (Icons.show_chart_rounded, 'Crop Trends'),
    (Icons.cloud_rounded, 'Weather & Climate'),
    (Icons.landscape_rounded, 'Soil & Environment'),
    (Icons.settings_rounded, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final name = '${state.currentUser?['username'] ?? state.currentUser?['name'] ?? 'Analyst'}';
    return Container(
      width: 280,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF064E2E), Color(0xFF08733F)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
      ),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [Icon(Icons.eco_rounded, color: Colors.white, size: 34), SizedBox(width: 12), Text('GeoSustain', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900))]),
        const SizedBox(height: 34),
        Row(children: [
          CircleAvatar(radius: 26, backgroundColor: Colors.white.withOpacity(.2), child: Text(name.isEmpty ? 'A' : name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            const Text('Analyst Dashboard', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
          ])),
        ]),
        const SizedBox(height: 28),
        Expanded(child: ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (_, i) {
            final selected = selectedIndex == i;
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onSelect(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(color: selected ? Colors.white.withOpacity(.20) : Colors.transparent, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [Icon(items[i].$1, color: Colors.white, size: 22), const SizedBox(width: 14), Expanded(child: Text(items[i].$2, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)))]),
              ),
            );
          },
        )),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: logout,
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: const Row(children: [Icon(Icons.logout_rounded, color: Colors.white), SizedBox(width: 14), Text('Logout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900))])),
        ),
      ]),
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
  const _WebPageFrame({required this.page, required this.state, required this.popupVisible, required this.onClosePopup, required this.onAnalyze, required this.message, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final titles = ['Dashboard','Map Analysis','Analyze Area','Analysis History','Reports','Crop Trends','Weather & Environment','Weather & Environment','Settings'];
    final subtitles = [
      'Overview of suitability results, live conditions, and quick actions',
      'Review analyzed areas, map markers, and saved field boundaries',
      'Run point or polygon-based crop and land suitability analysis',
      'Review previously analyzed land records with dates and recommendations',
      'Open and export generated suitability reports',
      'Compare crop recommendation frequencies and suitability patterns',
      'Monitor live weather, rainfall, soil, NDVI, and environmental indicators',
      'Monitor live weather, rainfall, soil, NDVI, and environmental indicators',
      'Manage dashboard preferences and account settings'
    ];
    final index = page.clamp(0, titles.length - 1);

    Widget body;
    if (page == 0) {
      body = WebDashboardScreen(state: state, onStartAnalyze: () => onNavigate(2), onOpenMapAnalysis: () => onNavigate(1), onOpenHistory: () => onNavigate(3), onOpenReports: () => onNavigate(4));
    } else if (page == 1) {
      body = WebMapScreen(state: state, popupVisible: popupVisible, onClosePopup: onClosePopup, onAnalyze: onAnalyze);
    } else if (page == 2) {
      body = WebAnalyzeScreen(state: state, onAnalyze: onAnalyze);
    } else if (page == 3) {
      body = WebHistoryScreen(state: state);
    } else if (page == 4) {
      body = WebReportsScreen(state: state);
    } else if (page == 5) {
      body = WebCropTrendsScreen(state: state);
    } else if (page == 6 || page == 7) {
      body = WebWeatherEnvironmentScreen(state: state, message: message);
    } else {
      body = WebSettingsScreen(state: state);
    }

    return SizedBox.expand(
      child: CustomScrollView(
        key: ValueKey('web_page_$index'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _WebHeader(title: titles[index], subtitle: subtitles[index], state: state, message: message),
                const SizedBox(height: 18),
                body,
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
