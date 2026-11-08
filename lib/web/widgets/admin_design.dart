part of '../../main.dart';

/// Shared, scrollable admin dialogs with a fixed action row.
class _AdminDialog extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Widget child;
  final List<Widget> actions;
  final double width;
  final bool busy;
  const _AdminDialog({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    required this.actions,
    this.width = 860,
    this.busy = false,
  });
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Roboto'),
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: 'Roboto'),
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: WebPortalColors.canvas,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width,
            maxHeight: MediaQuery.sizeOf(context).height - 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(22, 22, 14, 20),
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: const AssetImage(
                      'assets/images/web/admin_valley_banner.png',
                    ),
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    opacity: WebPortalColors.dark ? .10 : .24,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (MediaQuery.sizeOf(context).width >= 600 &&
                        MediaQuery.textScalerOf(context).scale(14) <= 20) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: WebPortalColors.tint,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(
                          icon,
                          color: WebPortalColors.accent,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 23,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                              color: WebPortalColors.ink,
                            ),
                          ),
                          if (MediaQuery.sizeOf(context).width >= 600 &&
                              MediaQuery.textScalerOf(context).scale(14) <=
                                  20) ...[
                            const SizedBox(height: 6),
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: WebPortalColors.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close dialog',
                      onPressed: busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: child,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: WebPortalColors.muted.withValues(alpha: .15),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 12,
                        runSpacing: 8,
                        children: actions,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AdminFieldGrid extends StatelessWidget {
  final List<Widget> children;
  final double minimumWidth;
  final int maximumColumns;
  const _AdminFieldGrid({
    required this.children,
    this.minimumWidth = 270,
    this.maximumColumns = 2,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scaledMin =
          minimumWidth *
          (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1, 1.5);
      final columns = ((box.maxWidth + 14) / (scaledMin + 14)).floor().clamp(
        1,
        maximumColumns,
      );
      final width = math.max(
        0.0,
        (box.maxWidth - (columns - 1) * 14) / columns,
      );
      return Wrap(
        spacing: 14,
        runSpacing: 12,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class _AdminDialogSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final String? description;
  const _AdminDialogSection({
    required this.title,
    required this.icon,
    required this.child,
    this.description,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: WebPortalColors.surface,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: WebPortalColors.accent.withValues(alpha: .14)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: WebPortalColors.accent, size: 23),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: WebPortalColors.ink,
                ),
              ),
            ),
          ],
        ),
        if (description != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              description!,
              style: TextStyle(fontSize: 12, color: WebPortalColors.muted),
            ),
          ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

/// Administrator presentation only; permissions and mutations remain in the API.
class _AdminPortal extends StatefulWidget {
  final AnalysisState? state;
  final Widget navigation, child;
  final ValueChanged<String> onSearch;
  const _AdminPortal({
    required this.navigation,
    required this.child,
    required this.onSearch,
    this.state,
  });
  @override
  State<_AdminPortal> createState() => _AdminPortalState();
}

class _AdminPortalState extends State<_AdminPortal> {
  bool expanded = true;
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 1200;
    final roomy = size.width >= 1000;
    final account =
        '${widget.state?.currentUser?['username'] ?? 'Super Administrator'}';
    final theme = Theme.of(context);
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(
        color: WebPortalColors.muted.withValues(alpha: .20),
      ),
    );
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          bodyMedium: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 12,
            height: 1.4,
            color: WebPortalColors.ink,
          ),
          bodySmall: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 11,
            height: 1.35,
            color: WebPortalColors.muted,
          ),
          bodyLarge: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 13,
            color: WebPortalColors.ink,
          ),
          titleMedium: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: WebPortalColors.ink,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: WebPortalColors.surface,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 13,
          ),
          border: outline,
          enabledBorder: outline,
          focusedBorder: outline.copyWith(
            borderSide: BorderSide(color: WebPortalColors.accent),
          ),
          labelStyle: TextStyle(fontSize: 11, color: WebPortalColors.muted),
          hintStyle: TextStyle(fontSize: 11, color: WebPortalColors.muted),
        ),
        cardTheme: theme.cardTheme.copyWith(
          color: WebPortalColors.surface,
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: WebPortalColors.muted.withValues(alpha: .12),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            textStyle: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: WebPortalColors.accent,
            side: BorderSide(
              color: WebPortalColors.accent.withValues(alpha: .3),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            textStyle: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
        ),
        dataTableTheme: DataTableThemeData(
          headingRowColor: WidgetStatePropertyAll(
            WebPortalColors.tint.withValues(alpha: .65),
          ),
          headingTextStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: WebPortalColors.muted,
          ),
          dataTextStyle: TextStyle(fontSize: 11, color: WebPortalColors.ink),
          dividerThickness: .5,
          columnSpacing: 22,
          horizontalMargin: 12,
          headingRowHeight: 38,
          dataRowMinHeight: 56,
          dataRowMaxHeight: 80,
        ),
      ),
      child: Row(
        children: [
          if (wide && expanded) widget.navigation,
          Expanded(
            child: Scaffold(
              backgroundColor: WebPortalColors.canvas,
              drawer: !wide
                  ? Drawer(
                      width: 260,
                      child: SafeArea(child: widget.navigation),
                    )
                  : null,
              appBar: AppBar(
                toolbarHeight: 60,
                backgroundColor: WebPortalColors.surface,
                surfaceTintColor: Colors.transparent,
                leading: wide
                    ? IconButton(
                        tooltip: expanded
                            ? 'Collapse navigation'
                            : 'Expand navigation',
                        icon: const Icon(Icons.menu),
                        onPressed: () => setState(() => expanded = !expanded),
                      )
                    : null,
                title: !roomy
                    ? const Text(
                        'GeoSustain',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 18),
                      )
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 470),
                        child: TextField(
                          key: const ValueKey('admin-global-search'),
                          textInputAction: TextInputAction.search,
                          onSubmitted: widget.onSearch,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search, size: 19),
                            hintText:
                                'Search users, farms, analyses, submissions...',
                          ),
                        ),
                      ),
                actions: [
                  if (roomy)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _AdminWeather(state: widget.state, compact: true),
                    ),
                  IconButton(
                    tooltip: 'Open audit activity',
                    icon: const Icon(Icons.notifications_outlined, size: 21),
                    onPressed: () => PortalRoutes.go('/admin/audit'),
                  ),
                  IconButton(
                    tooltip: 'Toggle dark mode',
                    icon: Icon(
                      WebPortalColors.dark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode,
                      size: 21,
                    ),
                    onPressed: () async {
                      final dark = !WebPortalColors.dark;
                      appThemeMode.value = dark
                          ? ThemeMode.dark
                          : ThemeMode.light;
                      setState(() {});
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('settings_dark_mode', dark);
                    },
                  ),
                  if (roomy)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 15,
                            backgroundColor: softGreen,
                            child: Text(
                              account.isEmpty ? 'S' : account[0].toUpperCase(),
                              style: const TextStyle(color: green),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 145,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  account,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Super Administrator',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: WebPortalColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (size.width >= 500 ||
                      MediaQuery.textScalerOf(context).scale(14) <= 20)
                    IconButton(
                      tooltip: 'Build information',
                      icon: const Icon(Icons.info_outline, size: 21),
                      onPressed: () => showAboutDialog(
                        context: context,
                        applicationName: 'GeoSustain',
                        applicationVersion: WebBuildIdentity.id,
                      ),
                    ),
                ],
              ),
              body: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminCanvas extends StatelessWidget {
  final Widget child;
  const _AdminCanvas({required this.child});
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: WebPortalColors.canvas)),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 220,
          child: ExcludeSemantics(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: WebPortalColors.dark ? .12 : .8,
                  child: Image.asset(
                    'assets/images/web/admin_valley_banner.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        WebPortalColors.canvas.withValues(alpha: .8),
                        WebPortalColors.canvas.withValues(alpha: .02),
                      ],
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        WebPortalColors.canvas.withValues(alpha: 0),
                        WebPortalColors.canvas,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _AdminWeather extends StatelessWidget {
  final AnalysisState? state;
  final bool compact;
  const _AdminWeather({this.state, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final weather = state?.liveWeather;
    final temp = analysisNumber(
      weather?['temperature_c'] ?? weather?['temperature'],
    );
    final description =
        '${weather?['weather_description'] ?? 'Weather unavailable'}';
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          temp == null
              ? 'Weather unavailable'
              : '${temp.toStringAsFixed(1)} °C',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: compact ? 11 : 15,
          ),
        ),
        Text(
          compact ? 'Panabo City' : description,
          style: TextStyle(fontSize: 10, color: WebPortalColors.muted),
        ),
      ],
    );
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.cloud_outlined,
          color: WebPortalColors.accent,
          size: compact ? 22 : 30,
        ),
        const SizedBox(width: 10),
        Flexible(child: info),
        if (!compact) ...[
          const SizedBox(width: 20),
          Text(
            'Panabo City',
            style: TextStyle(fontSize: 11, color: WebPortalColors.muted),
          ),
        ],
      ],
    );
    return compact
        ? content
        : _WebCard(padding: const EdgeInsets.all(15), child: content);
  }
}

class _AdminHeader extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final VoidCallback refresh;
  final AnalysisState? state;
  final List<String> failures;
  final bool weather;
  const _AdminHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.refresh,
    required this.failures,
    this.state,
    this.weather = false,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: LayoutBuilder(
      builder: (context, box) {
        final heading = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (box.maxWidth >= 540) ...[
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: WebPortalColors.tint,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 30, color: WebPortalColors.accent),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: box.maxWidth < 540 ? 23 : 27,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      color: WebPortalColors.ink,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: WebPortalColors.muted,
                    ),
                  ),
                  if (failures.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          'Could not refresh: ${failures.join(', ')}. Retry with Refresh.',
                          style: TextStyle(
                            color: WebPortalColors.dark
                                ? Colors.orange.shade200
                                : Colors.brown.shade800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Refresh administrator panels',
              onPressed: refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        );
        if (weather &&
            box.maxWidth > 1100 &&
            MediaQuery.textScalerOf(context).scale(14) <= 20) {
          return Row(
            children: [
              Expanded(child: heading),
              const SizedBox(width: 20),
              SizedBox(width: 290, child: _AdminWeather(state: state)),
            ],
          );
        }
        return heading;
      },
    ),
  );
}

class _AdminTable extends StatelessWidget {
  final List<String> columns;
  final List<DataRow> rows;
  final double minWidth;
  const _AdminTable({
    required this.columns,
    required this.rows,
    this.minWidth = 700,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      primary: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: math.max(minWidth, box.maxWidth)),
        child: DataTable(
          columns: columns
              .map((name) => DataColumn(label: Text(name)))
              .toList(),
          rows: rows,
        ),
      ),
    ),
  );
}

class _AdminGrid extends StatelessWidget {
  final List<Widget> children;
  final bool small;
  const _AdminGrid({required this.children, this.small = false});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) {
      final columns = small
          ? (box.maxWidth >= 285 ? 2 : 1)
          : box.maxWidth >= 880
          ? math.min(4, children.length)
          : box.maxWidth >= 500
          ? 2
          : 1;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var start = 0; start < children.length; start += columns) ...[
            if (start > 0) const SizedBox(height: 12),
            WebAlignedCards(
              spacing: small ? 10 : 14,
              children: [
                for (var col = 0; col < columns; col++)
                  start + col < children.length
                      ? children[start + col]
                      : const SizedBox.shrink(),
              ],
            ),
          ],
        ],
      );
    },
  );
}

Color _adminStatusColor(String status) => switch (status.toLowerCase()) {
  'verified' || 'accepted' || 'active' =>
    WebPortalColors.dark ? const Color(0xFF8CE0B2) : const Color(0xFF168052),
  'pending' || 'pending_review' =>
    WebPortalColors.dark ? const Color(0xFFFFD47C) : const Color(0xFF9B6400),
  'rejected' || 'inactive' =>
    WebPortalColors.dark ? const Color(0xFFFFA7B3) : const Color(0xFFC1364D),
  _ => WebPortalColors.dark ? const Color(0xFFA0CCFF) : const Color(0xFF326BA8),
};

String _adminDate(dynamic raw, {bool time = false}) {
  final date = DateTime.tryParse('$raw')?.toLocal();
  if (date == null) {
    return 'Not recorded';
  }
  final value =
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  return time
      ? '$value ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
      : value;
}

class _AdminDistribution extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  const _AdminDistribution(this.records);
  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final row in records) {
      final status = '${row['verification_status'] ?? 'draft'}';
      counts[status] = (counts[status] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AnalystSectionTitle(
            'Review Status Distribution',
            subtitle: 'Filtered records on this page',
            icon: Icons.donut_small,
          ),
          const SizedBox(height: 18),
          Center(
            child: SizedBox(
              width: 150,
              height: 150,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _AdminRing(entries)),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${records.length}',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text('Total', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            const Text(
              'No review statuses recorded.',
              textAlign: TextAlign.center,
            ),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 8,
                    color: _adminStatusColor(entry.key),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.key.replaceAll('_', ' '),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  Text(
                    '${entry.value} (${(entry.value / records.length * 100).round()}%)',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AdminRing extends CustomPainter {
  final List<MapEntry<String, int>> entries;
  _AdminRing(this.entries);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(13, 13, size.width - 26, size.height - 26);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 25;
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      paint..color = WebPortalColors.tint,
    );
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    if (total == 0) {
      return;
    }
    var start = -math.pi / 2;
    for (final entry in entries) {
      final sweep = entry.value / total * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        paint..color = _adminStatusColor(entry.key),
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_AdminRing oldDelegate) => true;
}
