part of '../../main.dart';

class WebPortalColors {
  static bool get dark => appThemeMode.value == ThemeMode.dark;
  static Color get surface => dark ? const Color(0xFF19231E) : Colors.white;
  static Color get canvas =>
      dark ? const Color(0xFF101813) : const Color(0xFFF4F8F5);
  static Color get ink =>
      dark ? const Color(0xFFEDF5EF) : const Color(0xFF17291F);
  static Color get muted =>
      dark ? const Color(0xFFBBCBBF) : const Color(0xFF526559);
  static Color get tint => dark ? const Color(0xFF223C2D) : softGreen;
  static Color get accent => dark ? const Color(0xFF9AD8AE) : green;
}

class WebResourceWarning extends StatelessWidget {
  final AnalysisState state;
  const WebResourceWarning({super.key, required this.state});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            [
              if (state.historyError != null) 'History: ${state.historyError}',
              ...state.resourceErrors.entries.map(
                (e) => '${e.key}: ${e.value}',
              ),
            ].join('\n'),
          ),
        ),
        TextButton.icon(
          onPressed: state.historyLoading ? null : state.refreshHistoryData,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry account data'),
        ),
      ],
    ),
  );
}

class WebAdaptiveRow extends StatelessWidget {
  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisAlignment mainAxisAlignment;
  const WebAdaptiveRow({
    super.key,
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.mainAxisAlignment = MainAxisAlignment.start,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) {
      if (box.maxWidth >= 850) {
        return Row(
          crossAxisAlignment: crossAxisAlignment,
          mainAxisAlignment: mainAxisAlignment,
          children: children,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in children)
            if (child is Expanded)
              child.child
            else if (child is Spacer)
              const SizedBox(height: 12)
            else if (child is SizedBox &&
                child.width != null &&
                child.height == null)
              const SizedBox(height: 12)
            else
              child,
        ],
      );
    },
  );
}

class WebPortalFrame extends StatefulWidget {
  final AnalysisState? state;
  final Widget navigation;
  final Widget child;
  const WebPortalFrame({
    super.key,
    this.state,
    required this.navigation,
    required this.child,
  });
  @override
  State<WebPortalFrame> createState() => _WebPortalFrameState();
}

class _WebPortalFrameState extends State<WebPortalFrame> {
  bool expanded = true;
  void _stateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    widget.state?.addListener(_stateChanged);
  }

  @override
  void didUpdateWidget(WebPortalFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state?.removeListener(_stateChanged);
      widget.state?.addListener(_stateChanged);
    }
  }

  @override
  void dispose() {
    widget.state?.removeListener(_stateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1200;
    final state = widget.state;
    final roomy = MediaQuery.sizeOf(context).width >= 1000;
    final accountName = '${state?.currentUser?['username'] ?? 'Analyst'}';
    return Scaffold(
      backgroundColor: WebPortalColors.canvas,
      appBar: AppBar(
        backgroundColor: WebPortalColors.surface,
        surfaceTintColor: Colors.transparent,
        title: state == null || !roomy
            ? const Text('GeoSustain')
            : ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: TextField(
                  key: const ValueKey('portal-analysis-search'),
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Search my analyses...',
                    prefixIcon: Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (value) => PortalRoutes.go(
                    '/operator/history?q=${Uri.encodeQueryComponent(value.trim())}',
                  ),
                ),
              ),
        leading: wide
            ? IconButton(
                tooltip: expanded ? 'Collapse navigation' : 'Expand navigation',
                onPressed: () => setState(() => expanded = !expanded),
                icon: const Icon(Icons.menu),
              )
            : null,
        actions: [
          if (state != null && roomy)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(Icons.cloud_outlined, color: WebPortalColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    analysisNumber(
                              state.liveWeather?['temperature_c'] ??
                                  state.liveWeather?['temperature'],
                            ) ==
                            null
                        ? 'Weather unavailable'
                        : '${analysisNumber(state.liveWeather?['temperature_c'] ?? state.liveWeather?['temperature'])!.toStringAsFixed(1)} °C',
                  ),
                ],
              ),
            ),
          if (state != null)
            IconButton(
              tooltip: 'Open activity',
              onPressed: () => PortalRoutes.go('/operator/activity'),
              icon: const Icon(Icons.notifications_outlined),
            ),
          IconButton(
            tooltip: 'Toggle dark mode',
            icon: Icon(
              WebPortalColors.dark ? Icons.light_mode : Icons.dark_mode,
            ),
            onPressed: () async {
              final dark = !WebPortalColors.dark;
              appThemeMode.value = dark ? ThemeMode.dark : ThemeMode.light;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('settings_dark_mode', dark);
            },
          ),
          if (state != null && roomy)
            TextButton.icon(
              onPressed: () => PortalRoutes.go('/operator/settings'),
              icon: CircleAvatar(
                radius: 16,
                child: Text(
                  accountName.isEmpty ? 'A' : accountName[0].toUpperCase(),
                ),
              ),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  '${state.currentUser?['username'] ?? 'Analyst'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          IconButton(
            tooltip: 'Build information',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'GeoSustain',
              applicationVersion: WebBuildIdentity.id,
            ),
          ),
        ],
      ),
      drawer: !wide
          ? Drawer(width: 280, child: SafeArea(child: widget.navigation))
          : null,
      body: Row(
        children: [
          if (wide && expanded) widget.navigation,
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}
