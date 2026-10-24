part of '../main.dart';

/// Uses the existing boundary renderer and the recorded parcel geometry.
class ParcelThumbnail extends StatelessWidget {
  final Map<String, dynamic> record;
  final double size;
  const ParcelThumbnail(this.record, {super.key, this.size = 88});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BoundaryThumbnail(record, size: size),
        ),
        Positioned(
          right: 4,
          bottom: 4,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.public,
              size: 16,
              color: GeoDesign.green800,
            ),
          ),
        ),
      ],
    ),
  );
}

class GeoResultCard extends StatelessWidget {
  final Widget child;
  final Color color;
  const GeoResultCard({
    super.key,
    required this.child,
    this.color = Colors.white,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: geoPanelColor(context, color),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: child,
  );
}

class GeoCoverBar extends StatelessWidget {
  final String label;
  final double? fraction;
  final Color color;
  final IconData icon;
  const GeoCoverBar({
    super.key,
    required this.label,
    required this.fraction,
    required this.color,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label: ${fraction == null ? 'Unavailable' : '${(fraction! * 100).toStringAsFixed(1)}%'}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (fraction != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: fraction!.clamp(0, 1),
                    minHeight: 9,
                    color: color,
                    backgroundColor: const Color(0xFFEBEDEE),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class GeoRecordSummary extends StatelessWidget {
  final Map<String, dynamic> record;
  const GeoRecordSummary(this.record, {super.key});
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ParcelThumbnail(record),
      const SizedBox(width: 12),
      Expanded(child: AnalysisIdentity(record: record, compact: true)),
    ],
  );
}

class GeoInfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const GeoInfoLine(this.icon, this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 15,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );
}

class GeoStatusPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color foreground;
  const GeoStatusPill({
    super.key,
    required this.label,
    required this.icon,
    this.foreground = GeoDesign.green800,
  });
  @override
  Widget build(BuildContext context) {
    final palette = ColorScheme.fromSeed(
      seedColor: foreground,
      brightness: Theme.of(context).brightness,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: palette.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: palette.onPrimaryContainer),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: palette.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
