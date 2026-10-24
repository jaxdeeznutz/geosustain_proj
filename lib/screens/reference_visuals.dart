part of '../main.dart';

const supportedCropNames = [
  'Banana',
  'Coconut',
  'Rice',
  'Durian',
  'Mango',
  'Rubber',
  'Cacao',
];

class FarmBanner extends StatelessWidget {
  final String title, description;
  const FarmBanner(this.title, this.description, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: geoPanelColor(context),
      borderRadius: BorderRadius.circular(GeoDesign.cardRadius),
    ),
    child: LayoutBuilder(
      builder: (context, c) => Stack(
        children: [
          if (c.maxWidth >= 330)
            const Positioned(
              right: 0,
              bottom: 0,
              width: 130,
              height: 135,
              child: GeoFieldIllustration(),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              c.maxWidth >= 330 ? 116 : 16,
              16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class BoundaryThumbnail extends StatelessWidget {
  final Map<String, dynamic> record;
  final double size;
  const BoundaryThumbnail(this.record, {super.key, this.size = 88});
  @override
  Widget build(BuildContext context) {
    final points = FarmGeometry.fromPayload(
      record['selected_polygon'] ?? record['polygon'],
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: size,
        height: size,
        child: points.length < 3
            ? Container(
                color: softGreen,
                child: const Center(
                  child: Icon(Icons.map_outlined, color: green),
                ),
              )
            : FlutterMap(
                options: MapOptions(
                  initialCameraFit: CameraFit.coordinates(
                    coordinates: points,
                    padding: const EdgeInsets.all(13),
                  ),
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                    userAgentPackageName: 'com.geosustain.mobile',
                  ),
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: points,
                        color: green.withValues(alpha: .35),
                        borderColor: const Color(0xFF70FFD0),
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      for (final p in points)
                        Marker(
                          point: p,
                          width: 5,
                          height: 5,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Align(
                    alignment: Alignment.bottomRight,
                    child: ColoredBox(
                      color: Colors.white70,
                      child: Text('Esri', style: TextStyle(fontSize: 8)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class ReferenceStat extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final VoidCallback onTap;
  final Color tint;
  const ReferenceStat(
    this.value,
    this.label,
    this.icon,
    this.onTap, {
    super.key,
    this.tint = softGreen,
  });
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: tint,
                  child: Icon(icon, size: 19, color: green),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: MediaQuery.textScalerOf(context).scale(11) * 2.5,
              child: Text(
                label,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ReferenceAction extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool blue, compact;
  const ReferenceAction(
    this.title,
    this.subtitle,
    this.icon,
    this.onTap, {
    super.key,
    this.blue = false,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final padding = compact ? 8.0 : 14.0;
      final titleStyle = TextStyle(
        fontFamily: 'Roboto',
        fontSize: compact ? 11 : 14,
        height: 1.15,
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.onSurface,
      );
      final bodyStyle = TextStyle(
        fontFamily: 'Roboto',
        fontSize: compact ? 10 : 12,
        height: 1.3,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
      double sharedHeight(List<String> labels, TextStyle style) {
        var result = 0.0;
        for (final label in labels) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: constraints.maxWidth - padding * 2);
          result = math.max(result, painter.height);
          painter.dispose();
        }
        return result.ceilToDouble();
      }

      final titleHeight = sharedHeight([
        'Create a Farm Boundary',
        'Analyze Land Using a Polygon',
        'View My Farms',
        'Analysis History',
      ], titleStyle);
      final bodyHeight = sharedHeight([
        'Walk your perimeter with live GPS.',
        'Outline an area and explore crop suitability.',
        'Walk or draw your farm area.',
        'Explore crop suitability.',
        'Manage your saved areas.',
        'Check your previous results.',
      ], bodyStyle);
      return Card(
        margin: EdgeInsets.zero,
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.surfaceContainerHigh
            : blue
            ? GeoDesign.blue
            : softGreen,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(GeoDesign.cardRadius),
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: compact ? 17 : 20,
                  backgroundColor: blue
                      ? const Color(0xFFD5EDF8)
                      : const Color(0xFFD2ECDD),
                  child: Icon(
                    icon,
                    size: 24,
                    color: blue ? const Color(0xFF216D8A) : green,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: titleHeight,
                  child: Text(title, style: titleStyle),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: bodyHeight,
                  child: Text(subtitle, style: bodyStyle),
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.bottomRight,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: green,
                    child: Icon(
                      Icons.arrow_forward,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class CropArtwork extends StatelessWidget {
  final String crop;
  final double size;
  const CropArtwork(this.crop, {super.key, this.size = 48});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: const Color(0xFFEDF4D9),
      borderRadius: BorderRadius.circular(13),
    ),
    child: CustomPaint(painter: _CropPainter(crop.toLowerCase())),
  );
}

class _CropPainter extends CustomPainter {
  final String crop;
  const _CropPainter(this.crop);
  @override
  void paint(Canvas c, Size s) {
    c.save();
    c.scale(s.width / 48, s.height / 48);
    final stem = Paint()
      ..color = const Color(0xFF31753C)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    c.drawLine(const Offset(25, 8), const Offset(24, 42), stem);
    if (crop.contains('banana')) {
      for (var i = 0; i < 3; i++) {
        c.drawPath(
          Path()
            ..moveTo(12 + i * 7, 8)
            ..quadraticBezierTo(3 + i * 7, 44, 38, 32 + i * 3),
          Paint()
            ..color = Color(0xFFFFC92B + i * 0x00000500)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7
            ..strokeCap = StrokeCap.round,
        );
      }
    } else if (crop.contains('rice')) {
      for (var i = 0; i < 5; i++) {
        c.drawOval(
          Rect.fromLTWH(10 + i * 2, 8 + i * 5, 10, 5),
          Paint()..color = const Color(0xFFE0B947),
        );
        c.drawOval(
          Rect.fromLTWH(26, 6 + i * 5, 10, 5),
          Paint()..color = const Color(0xFFF0D376),
        );
      }
    } else if (crop.contains('rubber')) {
      c.drawCircle(const Offset(24, 18), 17, Paint()..color = green);
      c.drawCircle(
        const Offset(13, 25),
        11,
        Paint()..color = const Color(0xFF65A751),
      );
    } else if (crop.contains('coconut')) {
      c.drawCircle(
        const Offset(21, 27),
        16,
        Paint()..color = const Color(0xFF836036),
      );
      c.drawCircle(
        const Offset(29, 28),
        13,
        Paint()..color = const Color(0xFFFFFAE2),
      );
      c.drawCircle(
        const Offset(29, 28),
        7,
        Paint()..color = const Color(0xFFBB8C55),
      );
    } else {
      final durian = crop.contains('durian');
      final cacao = crop.contains('cacao');
      c.drawOval(
        const Rect.fromLTWH(10, 10, 29, 33),
        Paint()
          ..color = durian
              ? const Color(0xFF91A53A)
              : cacao
              ? const Color(0xFFB56B34)
              : const Color(0xFFFFBD36),
      );
      if (durian) {
        for (var i = 0; i < 4; i++) {
          for (var j = 0; j < 4; j++) {
            c.drawPath(
              Path()
                ..moveTo(12 + i * 6, 16 + j * 6)
                ..lineTo(15 + i * 6, 11 + j * 6)
                ..lineTo(17 + i * 6, 16 + j * 6),
              Paint()..color = const Color(0xFF526C25),
            );
          }
        }
      }
      if (cacao) {
        for (var i = 0; i < 3; i++) {
          c.drawArc(
            Rect.fromLTWH(13 + i * 5, 12, 12, 28),
            -1.5,
            3,
            false,
            Paint()
              ..color = const Color(0xFF713E27)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      }
      c.drawOval(const Rect.fromLTWH(23, 3, 19, 8), Paint()..color = green);
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.crop != crop;
}
