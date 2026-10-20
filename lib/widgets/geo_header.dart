part of '../main.dart';

class _HillsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p1 = Paint()..color = Colors.white.withValues(alpha: 0.07);
    final p2 = Paint()..color = Colors.white.withValues(alpha: 0.06);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(s.width * .38, s.height + 6),
        width: s.width * .7,
        height: 70,
      ),
      p1,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(s.width * .9, s.height + 4),
        width: s.width * .5,
        height: 80,
      ),
      p2,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(s.width * .05, s.height + 14),
        width: s.width * .5,
        height: 70,
      ),
      p2,
    );
    // small sprout, right edge
    final sprout = Paint()..color = Colors.white.withValues(alpha: 0.14);
    final c = Offset(s.width - 22, s.height - 24);
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy + 26)
        ..quadraticBezierTo(c.dx - 18, c.dy + 4, c.dx - 6, c.dy - 16)
        ..quadraticBezierTo(c.dx + 4, c.dy + 2, c.dx, c.dy + 26),
      sprout,
    );
    canvas.drawPath(
      Path()
        ..moveTo(c.dx + 2, c.dy + 26)
        ..quadraticBezierTo(c.dx + 8, c.dy + 6, c.dx + 20, c.dy - 6)
        ..quadraticBezierTo(c.dx + 20, c.dy + 14, c.dx + 2, c.dy + 26),
      sprout,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _HeaderCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _HeaderCircleButton({required this.icon, this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: 0.16),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox(
        width: 46,
        height: 46,
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    ),
  );
}

/// Green header with logo, title/subtitle and a trailing widget.
class GeoHeader extends StatelessWidget {
  final String subtitle;
  final Widget? leading, action;
  final Widget trailing;
  const GeoHeader({
    super.key,
    required this.subtitle,
    required this.trailing,
    this.leading,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    const top = 0.0;
    return Container(
      height: top + (action == null ? 108 : 154),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [GeoDesign.green800, GeoDesign.green900],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _HillsPainter())),
          Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              top + 4,
              12,
              action == null ? 24 : 70,
            ),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 10)],
                const Icon(Icons.eco, color: Colors.white, size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'GeoSustain',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 14.5,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                trailing,
              ],
            ),
          ),
          if (action != null) Positioned(right: 12, bottom: 28, child: action!),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 24,
              decoration: const BoxDecoration(
                color: GeoDesign.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// History introduction extracted from the visual reference.
class GeoHistoryBanner extends StatelessWidget {
  const GeoHistoryBanner({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFEAF6EE), Color(0xFFDDF0E3)],
      ),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: GeoDesign.mintBorder),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Analysis History',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: GeoDesign.green900,
                  height: 1.1,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'View your past land analyses, check statuses, and revisit your results.',
                style: TextStyle(
                  fontSize: 15,
                  color: GeoDesign.muted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 96,
          height: 90,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                right: 0,
                top: 4,
                child: Container(
                  width: 66,
                  height: 76,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      const SizedBox(height: 14),
                      for (var i = 0; i < 3; i++)
                        Container(
                          margin: const EdgeInsets.symmetric(
                            vertical: 3,
                            horizontal: 12,
                          ),
                          height: 3,
                          decoration: BoxDecoration(
                            color: GeoDesign.green700,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const Positioned(
                left: 4,
                bottom: 2,
                child: Icon(Icons.eco, color: GeoDesign.green700, size: 34),
              ),
              const Positioned(
                right: 0,
                bottom: 0,
                child: Icon(Icons.history, color: GeoDesign.green900, size: 44),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
