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
  final Widget navigation;
  final Widget child;
  const WebPortalFrame({
    super.key,
    required this.navigation,
    required this.child,
  });
  @override
  State<WebPortalFrame> createState() => _WebPortalFrameState();
}

class _WebPortalFrameState extends State<WebPortalFrame> {
  bool expanded = true;
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1200;
    return Scaffold(
      backgroundColor: WebPortalColors.canvas,
      appBar: AppBar(
        title: const Text('GeoSustain'),
        leading: wide
            ? IconButton(
                tooltip: expanded ? 'Collapse navigation' : 'Expand navigation',
                onPressed: () => setState(() => expanded = !expanded),
                icon: const Icon(Icons.menu),
              )
            : null,
        actions: [
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
