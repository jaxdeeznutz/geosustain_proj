part of '../../main.dart';

class _AnalystPageCanvas extends StatelessWidget {
  final Widget child;
  const _AnalystPageCanvas({required this.child});
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
          height: 190,
          child: ExcludeSemantics(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: WebPortalColors.dark ? .08 : .52,
                  child: Image.asset(
                    'assets/images/web/eco_valley_panorama.png',
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, .6),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        WebPortalColors.canvas.withValues(alpha: .9),
                        WebPortalColors.canvas.withValues(alpha: .04),
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
        Positioned.fill(child: child),
      ],
    );
  }
}

// Presentation only: these widgets receive saved records or existing callbacks.
class _AnalystMetricGrid extends StatelessWidget {
  final List<Widget> children;
  const _AnalystMetricGrid({required this.children});
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return LayoutBuilder(
      builder: (_, box) {
        final columns = box.maxWidth >= 900
            ? children.length
            : box.maxWidth >= 540
            ? 2
            : 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var start = 0; start < children.length; start += columns) ...[
              if (start != 0) const SizedBox(height: 14),
              WebAlignedCards(
                spacing: 14,
                children: [
                  for (var col = 0; col < columns; col++)
                    start + col < children.length
                        ? ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 110),
                            child: children[start + col],
                          )
                        : const SizedBox.shrink(),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _AnalystColumns extends StatelessWidget {
  final Widget main, side;
  final int mainFlex, sideFlex;
  final double breakpoint;
  final bool equalHeight;
  const _AnalystColumns({
    required this.main,
    required this.side,
    this.mainFlex = 3,
    this.sideFlex = 1,
    this.breakpoint = 900,
    this.equalHeight = false,
  });
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return LayoutBuilder(
      builder: (_, box) {
        if (box.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [main, const SizedBox(height: 16), side],
          );
        }
        if (equalHeight) {
          return WebAlignedCards(
            flexes: [mainFlex, sideFlex],
            children: [main, side],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: mainFlex, child: main),
            const SizedBox(width: 16),
            Expanded(flex: sideFlex, child: side),
          ],
        );
      },
    );
  }
}

class _AnalystSectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? action;
  const _AnalystSectionTitle(
    this.title, {
    this.subtitle,
    this.icon = Icons.eco_rounded,
    this.action,
  });
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 21, color: WebPortalColors.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: WebPortalColors.ink,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 11, color: WebPortalColors.muted),
                ),
              ],
            ],
          ),
        ),
        ?action,
      ],
    );
  }
}

class _WebEmptyState extends StatelessWidget {
  final String title, message;
  final IconData icon;
  final String? asset;
  final Widget? action;
  const _WebEmptyState({
    required this.title,
    required this.message,
    required this.icon,
    this.asset,
    this.action,
  });
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 320),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (asset != null)
              Image.asset(
                asset!,
                height: 115,
                width: 175,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              )
            else
              ExcludeSemantics(
                child: SizedBox(
                  width: 145,
                  height: 112,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 112,
                        height: 96,
                        decoration: BoxDecoration(
                          color: WebPortalColors.tint.withValues(alpha: .45),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(50),
                            topRight: Radius.circular(40),
                            bottomLeft: Radius.circular(30),
                            bottomRight: Radius.circular(45),
                          ),
                        ),
                      ),
                      Icon(
                        Icons.description_rounded,
                        size: 70,
                        color: WebPortalColors.accent.withValues(alpha: .2),
                      ),
                      Positioned(
                        right: 20,
                        bottom: 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: WebPortalColors.surface,
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              icon,
                              size: 29,
                              color: WebPortalColors.accent,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 2,
                        bottom: 15,
                        child: Icon(
                          Icons.eco_outlined,
                          color: WebPortalColors.accent.withValues(alpha: .3),
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: WebPortalColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 650),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: WebPortalColors.muted),
              ),
            ),
            if (action != null) ...[const SizedBox(height: 22), action!],
          ],
        ),
      ),
    );
  }
}

class _AnalystChartHeading extends StatelessWidget {
  final String title, subtitle, scope;
  final IconData scopeIcon;
  const _AnalystChartHeading({
    required this.title,
    required this.subtitle,
    required this.scope,
    required this.scopeIcon,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) {
      Theme.of(context);
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(subtitle, style: TextStyle(color: WebPortalColors.muted)),
        ],
      );
      final badge = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: box.maxWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: WebPortalColors.muted.withValues(alpha: .2),
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(scopeIcon, size: 16, color: WebPortalColors.accent),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  scope,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      if (box.maxWidth < 460 ||
          MediaQuery.textScalerOf(context).scale(14) > 20) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading,
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: badge),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: heading),
          const SizedBox(width: 12),
          badge,
        ],
      );
    },
  );
}

class _AnalystMetric extends StatelessWidget {
  final IconData icon;
  final String label, value, caption;
  final Color? color;
  final List<double> series;
  const _AnalystMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    this.color,
    this.series = const [],
  });
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final accent = color ?? WebPortalColors.accent;
    return _WebCard(
      key: ValueKey('metric-$label'),
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 76),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accent, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: WebPortalColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: WebPortalColors.ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    caption,
                    style: TextStyle(
                      fontSize: 10,
                      color: WebPortalColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (series.length >= 2) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 65,
                height: 36,
                child: CustomPaint(painter: _AnalystSparkline(series, accent)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnalystSparkline extends CustomPainter {
  final List<double> values;
  final Color color;
  _AnalystSparkline(this.values, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) {
      return;
    }
    final min = values.reduce(math.min), max = values.reduce(math.max);
    final range = max == min ? 1.0 : max - min;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - 3 - (values[i] - min) / range * (size.height - 6);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _AnalystSparkline oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

double? _analystArea(Map<String, dynamic> row) {
  final ha = analysisNumber(row['area_hectares'] ?? row['area_ha']);
  if (ha != null && ha.isFinite && ha >= 0) {
    return ha;
  }
  final m2 = analysisNumber(row['area_m2'] ?? row['area_square_meters']);
  return m2 != null && m2.isFinite && m2 >= 0 ? m2 / 10000 : null;
}

DateTime? _analystRecordDate(Map<String, dynamic> row) => DateTime.tryParse(
  '${row['date'] ?? row['analyzed_at'] ?? row['saved_at'] ?? row['created_at'] ?? ''}',
);

String _analystStatus(Map<String, dynamic> row) =>
    '${row['verification_status'] ?? row['review_status'] ?? 'not_submitted'}';

class _AnalystBars extends StatelessWidget {
  final List<MapEntry<String, double>> entries;
  final String title, subtitle, unit;
  const _AnalystBars({
    super.key,
    required this.entries,
    required this.title,
    required this.subtitle,
    this.unit = '',
  });
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AnalystSectionTitle(
            title,
            subtitle: subtitle,
            icon: Icons.bar_chart_rounded,
          ),
          const SizedBox(height: 18),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'No recorded values yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: WebPortalColors.muted),
              ),
            )
          else
            SizedBox(
              height: 140,
              child: Semantics(
                label: entries
                    .map((e) => '${e.key}: ${e.value.toStringAsFixed(2)} $unit')
                    .join('; '),
                child: CustomPaint(
                  painter: _AnalystBarPainter(
                    entries,
                    WebPortalColors.accent,
                    WebPortalColors.muted,
                  ),
                ),
              ),
            ),
          if (unit.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              unit,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: WebPortalColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnalystBarPainter extends CustomPainter {
  final List<MapEntry<String, double>> entries;
  final Color color, textColor;
  _AnalystBarPainter(this.entries, this.color, this.textColor);
  void label(
    Canvas canvas,
    String text,
    Offset at,
    double width, {
    TextAlign align = TextAlign.center,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: textColor, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: width);
    painter.paint(canvas, Offset(at.dx + (width - painter.width) / 2, at.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty) {
      return;
    }
    final max = math.max(1.0, entries.map((e) => e.value).reduce(math.max));
    final chart = Rect.fromLTRB(28, 5, size.width - 4, size.height - 24);
    for (var i = 0; i <= 4; i++) {
      final y = chart.bottom - chart.height * i / 4;
      canvas.drawLine(
        Offset(chart.left, y),
        Offset(chart.right, y),
        Paint()..color = textColor.withValues(alpha: .14),
      );
      label(
        canvas,
        (max * i / 4).toStringAsFixed(max < 5 ? 1 : 0),
        Offset(0, y - 5),
        24,
      );
    }
    final step = chart.width / entries.length;
    for (var i = 0; i < entries.length; i++) {
      final rect = Rect.fromLTWH(
        chart.left + step * i + step * .22,
        chart.bottom - chart.height * entries[i].value / max,
        step * .56,
        chart.height * entries[i].value / max,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: .55), color],
          ).createShader(chart),
      );
      label(
        canvas,
        entries[i].key,
        Offset(chart.left + step * i, chart.bottom + 9),
        step,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AnalystBarPainter oldDelegate) =>
      oldDelegate.entries != entries ||
      oldDelegate.color != color ||
      oldDelegate.textColor != textColor;
}

class _AnalystAreaSummary extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  const _AnalystAreaSummary(this.records);
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final grouped = <String, double>{};
    final ordered =
        records
            .where(
              (r) => _analystRecordDate(r) != null && _analystArea(r) != null,
            )
            .toList()
          ..sort(
            (a, b) => _analystRecordDate(a)!.compareTo(_analystRecordDate(b)!),
          );
    for (final r in ordered) {
      final date = _analystRecordDate(r)!;
      final key = date.toIso8601String().split('T').first;
      grouped[key] = (grouped[key] ?? 0) + _analystArea(r)!;
    }
    final entries = grouped.entries.toList();
    return _AnalystBars(
      key: const ValueKey('overview-area-panel'),
      title: 'Analysis Area Summary',
      subtitle: 'Last 7 recorded dates · loaded records',
      unit: 'Area (ha) · repeated analyses count separately',
      entries: entries.skip(math.max(0, entries.length - 7)).toList(),
    );
  }
}

class _AnalystBotanicalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = green.withValues(alpha: .055);
    for (var i = 0; i < 6; i++) {
      final x = size.width - 20.0 - i * 26, y = size.height - 12.0 - i * 9;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(-.7 - i * .15);
      final leaf = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(-25, -32, 0, -75)
        ..quadraticBezierTo(29, -32, 0, 0);
      canvas.drawPath(leaf, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _AnalystBotanicalPainter oldDelegate) => false;
}
