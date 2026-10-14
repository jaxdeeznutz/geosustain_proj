part of '../main.dart';

abstract final class GeoDesign {
  static const green = Color(0xFF08783F);
  static const darkGreen = Color(0xFF075F36);
  static const lightGreen = Color(0xFFE7F5EA);
  static const background = Color(0xFFF7FAF6);
  static const blue = Color(0xFFEAF6FB);
  static const yellow = Color(0xFFFFF6D9);
  static const red = Color(0xFFFDE9E9);
  static const cardRadius = 22.0;
  static const smallRadius = 16.0;
  static const buttonRadius = 17.0;
  static const buttonHeight = 54.0;
  static const headerHeight = 84.0;
  static const headerCurve = 22.0;
  static const headerAction = Color(0xFF3FAA66);
  static const actionSize = 48.0;
  static const pagePadding = 16.0;
}

class GeoSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const GeoSectionHeader(this.title, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: darkGreen,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class GeoEqualGrid extends StatelessWidget {
  final List<Widget> children;
  const GeoEqualGrid({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    final columns = MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 1 : 2;
    return Column(
      children: [
        for (var start = 0; start < children.length; start += columns)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var column = 0; column < columns; column++) ...[
                    if (column > 0) const SizedBox(width: 8),
                    Expanded(
                      child: start + column < children.length
                          ? children[start + column]
                          : const SizedBox(),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Paints the dark-green status-bar strip and then lays the page out below it,
/// so the header (see [GeoSustainHeader]) reads as one green block that runs
/// from the top edge of the screen. Drop-in replacement for [SafeArea] on any
/// page that starts with an embedded header.
class GeoSafeArea extends StatelessWidget {
  final Widget child;
  final bool bottom;
  const GeoSafeArea({super.key, required this.child, this.bottom = true});
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Column(
        children: [
          Container(height: top, color: GeoDesign.darkGreen),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: SafeArea(top: false, bottom: bottom, child: child),
            ),
          ),
        ],
      ),
    );
  }
}

/// Main header used by every mobile page: solid green bar with the leaf logo,
/// app name, page subtitle and round action buttons. The page below it has
/// rounded top corners that overlap the bar. Shared by in-page headers and
/// Scaffold.appBar. No screen-specific art.
class GeoSustainHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Widget? trailing;
  final VoidCallback? back;
  final AnalysisState? state;
  final bool embedded, nested, showMenu, showNotifications;
  const GeoSustainHeader({
    super.key,
    required this.title,
    this.trailing,
    this.back,
    this.state,
    this.embedded = true,
    this.nested = false,
    this.showMenu = true,
    this.showNotifications = true,
  });
  @override
  Size get preferredSize =>
      const Size.fromHeight(GeoDesign.headerHeight + GeoDesign.headerCurve);
  @override
  Widget build(BuildContext context) {
    final effectiveState =
        state ?? context.findAncestorStateOfType<_ShellPageState>()?.state;
    final leading =
        back ??
        (nested && Navigator.canPop(context)
            ? () => Navigator.maybePop(context)
            : null);
    final pageColor = Theme.of(context).scaffoldBackgroundColor;
    final bar = Container(
      height: GeoDesign.headerHeight,
      width: MediaQuery.sizeOf(context).width,
      color: green,
      padding: const EdgeInsets.symmetric(horizontal: GeoDesign.pagePadding),
      child: Theme(
        data: Theme.of(context).copyWith(
          iconButtonTheme: IconButtonThemeData(
            style: IconButton.styleFrom(
              fixedSize: const Size.square(GeoDesign.actionSize),
              minimumSize: const Size.square(GeoDesign.actionSize),
              maximumSize: const Size.square(GeoDesign.actionSize),
              padding: EdgeInsets.zero,
              foregroundColor: Colors.white,
              backgroundColor: Colors.black.withValues(alpha: .2),
              shape: const CircleBorder(),
            ),
          ),
        ),
        child: IconTheme(
          data: const IconThemeData(color: Colors.white, size: 22),
          child: Row(
            children: [
              if (leading != null) ...[
                GeoHeaderAction(
                  icon: Icons.arrow_back,
                  tooltip: 'Back',
                  onPressed: leading,
                ),
                const SizedBox(width: 8),
              ],
              const Icon(Icons.eco, color: Colors.white, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'GeoSustain',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 4), trailing!],
              if (showNotifications && title != 'Notifications') ...[
                const SizedBox(width: 6),
                GeoHeaderAction(
                  icon: Icons.notifications_none_rounded,
                  tooltip: 'Notifications',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NotificationsPage(state: effectiveState),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    // The page's own background, with rounded top corners, overlaps the bar.
    final curve = Container(
      height: GeoDesign.headerCurve,
      width: MediaQuery.sizeOf(context).width,
      color: green,
      alignment: Alignment.bottomCenter,
      child: Container(
        height: GeoDesign.headerCurve,
        decoration: BoxDecoration(
          color: pageColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
    );
    final block = Column(mainAxisSize: MainAxisSize.min, children: [bar, curve]);
    if (!embedded) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        child: ColoredBox(
          color: green,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: MediaQuery.paddingOf(context).top,
                color: GeoDesign.darkGreen,
              ),
              block,
            ],
          ),
        ),
      );
    }
    return SizedBox(
      height: GeoDesign.headerHeight + GeoDesign.headerCurve,
      child: OverflowBox(
        minWidth: MediaQuery.sizeOf(context).width,
        maxWidth: MediaQuery.sizeOf(context).width,
        child: block,
      ),
    );
  }
}

class GeoHeaderAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  /// Lighter green circle (used for the "+" create action).
  final bool accent;
  const GeoHeaderAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.accent = false,
  });
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: accent
        ? IconButton.styleFrom(backgroundColor: GeoDesign.headerAction)
        : null,
    icon: Icon(icon, size: 22),
  );
}

class GeoButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary, danger;
  const GeoButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.primary = false,
    this.danger = false,
  });
  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(0, GeoDesign.buttonHeight),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      backgroundColor: primary
          ? green
          : danger
          ? GeoDesign.red
          : softGreen,
      foregroundColor: primary
          ? Colors.white
          : danger
          ? const Color(0xFFCA2639)
          : darkGreen,
      disabledBackgroundColor: const Color(0xFFF0F3EF),
      disabledForegroundColor: const Color(0xFF7D8C83),
      side: BorderSide(
        color: primary
            ? green
            : danger
            ? const Color(0xFFF0CDCF)
            : const Color(0xFFD2E6D9),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GeoDesign.buttonRadius),
      ),
    );
    return SizedBox(
      height: GeoDesign.buttonHeight,
      child: OutlinedButton(
        style: style,
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GeoStatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const GeoStatusChip(
    this.label, {
    super.key,
    required this.icon,
    this.color = softGreen,
  });
  @override
  Widget build(BuildContext context) => Container(
    height: math.max(36, 20 + MediaQuery.textScalerOf(context).scale(12)),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: darkGreen),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w600,
              color: darkGreen,
            ),
          ),
        ),
      ],
    ),
  );
}

class GeoInfoCard extends StatelessWidget {
  final Widget icon;
  final String label, subtitle;
  final Color color;
  const GeoInfoCard({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    this.color = softGreen,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(GeoDesign.smallRadius),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .6),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: icon,
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: MediaQuery.textScalerOf(context).scale(12) * 2.3,
          child: Text(
            label,
            maxLines: 2,
            style: const TextStyle(
              fontSize: 12,
              height: 1.15,
              fontWeight: FontWeight.w700,
              color: darkGreen,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 3,
          style: const TextStyle(
            fontSize: 10,
            height: 1.2,
            color: Color(0xFF53635B),
          ),
        ),
      ],
    ),
  );
}

/// Vector illustration stays crisp and does not depend on a network image.
class GeoFieldIllustration extends StatelessWidget {
  const GeoFieldIllustration({super.key});
  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: CustomPaint(painter: _GeoFieldIllustrationPainter()),
  );
}

class GeoFarmCard extends StatelessWidget {
  final Map<String, dynamic> farm;
  final bool busy;
  final VoidCallback onOpen, onAnalyze, onResults, onEdit, onArchive;
  const GeoFarmCard({
    super.key,
    required this.farm,
    required this.busy,
    required this.onOpen,
    required this.onAnalyze,
    required this.onResults,
    required this.onEdit,
    required this.onArchive,
  });
  @override
  Widget build(BuildContext context) {
    final count = (analysisNumber(farm['analysis_count']) ?? 0).toInt();
    final location = '${farm['location_name'] ?? ''}'.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: onOpen,
                  child: BoundaryThumbnail(farm, size: 92),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${farm['farm_name'] ?? 'Saved farm'}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: darkGreen,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        location.isEmpty
                            ? 'Location description not provided'
                            : location,
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.3,
                          color: Color(0xFF59675E),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          GeoStatusChip(
                            analysisAreaText(farm),
                            icon: Icons.eco,
                          ),
                          GeoStatusChip(
                            farm['mapping_method'] == 'gps_walk'
                                ? 'GPS boundary'
                                : 'Drawn polygon',
                            icon: Icons.polyline_outlined,
                          ),
                          GeoStatusChip(
                            '$count analyses',
                            icon: Icons.bar_chart,
                            color: GeoDesign.blue,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    tooltip: 'Farm actions',
                    onSelected: (value) {
                      if (value == 'open') onOpen();
                      if (value == 'edit') onEdit();
                      if (value == 'archive') onArchive();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'open', child: Text('Farm details')),
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'archive', child: Text('Archive')),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  count == 0 ? Icons.circle : Icons.check_circle,
                  size: 13,
                  color: count == 0 ? const Color(0xFFE7A11D) : green,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    count == 0 ? 'Not analyzed yet' : 'Land analysis completed',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: count == 0 ? const Color(0xFF9D6011) : green,
                    ),
                  ),
                ),
              ],
            ),
            if (count == 0)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Analyze this farm to get crop recommendations.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF59675E)),
                ),
              ),
            if (count > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: VerificationStatusBadge(
                  status:
                      '${farm['latest_verification_status'] ?? farm['latest_review_status'] ?? 'draft'}',
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: count == 0 ? 2 : 1,
                  child: GeoButton(
                    label: count == 0 ? 'Analyze This Farm' : 'View Results',
                    icon: count == 0
                        ? Icons.center_focus_strong
                        : Icons.bar_chart,
                    primary: count == 0,
                    onPressed: busy
                        ? null
                        : count == 0
                        ? onAnalyze
                        : onResults,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GeoButton(
                    label: 'Edit',
                    icon: Icons.edit_outlined,
                    onPressed: busy ? null : onEdit,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: GeoButton(
                      label: 'Archive',
                      icon: Icons.archive_outlined,
                      danger: true,
                      onPressed: busy ? null : onArchive,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GeoFieldIllustrationPainter extends CustomPainter {
  const _GeoFieldIllustrationPainter();
  @override
  void paint(Canvas c, Size s) {
    c.save();
    c.scale(s.width / 180, s.height / 150);
    c.drawCircle(
      const Offset(145, 25),
      13,
      Paint()..color = const Color(0xFFF4D87F),
    );
    for (final layer in [
      (50.0, const Color(0xFFCEEBDA)),
      (75.0, const Color(0xFF99D4B4)),
      (100.0, const Color(0xFF53AF87)),
    ]) {
      c.drawPath(
        Path()
          ..moveTo(0, layer.$1 + 30)
          ..quadraticBezierTo(65, layer.$1 - 30, 110, layer.$1)
          ..quadraticBezierTo(155, layer.$1 - 25, 180, layer.$1)
          ..lineTo(180, 150)
          ..lineTo(0, 150)
          ..close(),
        Paint()..color = layer.$2,
      );
    }
    c.drawPath(
      Path()
        ..moveTo(0, 150)
        ..quadraticBezierTo(95, 85, 180, 100)
        ..lineTo(180, 150)
        ..close(),
      Paint()..color = green,
    );
    for (var i = 0; i < 7; i++) {
      c.drawPath(
        Path()
          ..moveTo(105, 106)
          ..quadraticBezierTo(65 + i * 20, 115, i * 34 - 15, 150),
        Paint()
          ..color = const Color(0xFF99CD72)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    c.drawPath(
      Path()
        ..moveTo(108, 105)
        ..cubicTo(101, 95, 87, 82, 87, 72)
        ..cubicTo(87, 45, 129, 45, 129, 72)
        ..cubicTo(129, 83, 116, 97, 108, 105)
        ..close(),
      Paint()..color = Colors.white,
    );
    c.drawCircle(const Offset(108, 71), 9, Paint()..color = green);
    c.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
