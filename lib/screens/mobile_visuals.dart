part of '../main.dart';

/// Code-drawn field accents are decorative and never placed on a working map.
class _FieldIcon extends StatelessWidget {
  final IconData icon;
  const _FieldIcon(this.icon);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: softGreen,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Icon(icon, color: darkGreen, size: 24),
  );
}

class _FieldLandscape extends StatelessWidget {
  const _FieldLandscape();
  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: SizedBox(
      height: 90,
      width: 180,
      child: CustomPaint(painter: _FieldPainter()),
    ),
  );
}

class _FieldPainter extends CustomPainter {
  const _FieldPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.height / 90);
    final width = size.width * 90 / size.height;
    canvas.drawCircle(
      Offset(width - 34, 20),
      15,
      Paint()..color = const Color(0xFFE6C875),
    );
    final back = Path()
      ..moveTo(0, 63)
      ..quadraticBezierTo(width * .3, 4, width, 61)
      ..lineTo(width, 90)
      ..lineTo(0, 90)
      ..close();
    canvas.drawPath(back, Paint()..color = const Color(0xFFA8CCAA));
    final front = Path()
      ..moveTo(0, 76)
      ..quadraticBezierTo(width * .54, 27, width, 70)
      ..lineTo(width, 90)
      ..lineTo(0, 90)
      ..close();
    canvas.drawPath(front, Paint()..color = const Color(0xFF4B9263));
    canvas.save();
    canvas.clipPath(front);
    for (var i = 0; i < 6; i++) {
      canvas.drawPath(
        Path()
          ..moveTo(width * .3 + i * width * .072, 46)
          ..quadraticBezierTo(
            width * .14 + i * width * .14,
            66,
            -10 + i * width * .24,
            96,
          ),
        Paint()
          ..color = const Color(0xFFCCE3B5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    canvas.restore();
    final stem = Paint()
      ..color = darkGreen
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(34, 64), const Offset(34, 25), stem);
    canvas.drawOval(
      const Rect.fromLTWH(17, 28, 18, 10),
      Paint()..color = green,
    );
    canvas.drawOval(
      const Rect.fromLTWH(34, 19, 19, 11),
      Paint()..color = green,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FieldPainter oldDelegate) => false;
}

class _HarvestSurface extends StatelessWidget {
  final Widget child;
  const _HarvestSurface({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFE3F1DF), cream],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: const Color(0xFFD9E7D4)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        const SizedBox(
          height: 66,
          child: ExcludeSemantics(child: CustomPaint(painter: _FieldPainter())),
        ),
      ],
    ),
  );
}

/// Only the recording status pulses; location markers always reflect device fixes.
class _RecordingDot extends StatefulWidget {
  final bool active;
  const _RecordingDot({super.key, required this.active});
  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );
  void _sync() {
    if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_RecordingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: .35, end: 1).animate(_pulse),
    child: Icon(
      widget.active ? Icons.fiber_manual_record : Icons.pause_circle_outline,
      color: darkGreen,
      size: 16,
    ),
  );
}
