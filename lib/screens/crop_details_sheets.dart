part of '../main.dart';

// -----------------------------------------------------------------------------
// Crop "See details" bottom sheets.
//
// UI only. Everything shown comes from the crop object / analysis record that
// was already saved; nothing is recalculated and no value is guessed. When a
// value is missing a plain "unavailable" message is shown instead.
//
//   rank 1      -> RecommendedCropDetailsSheet  (environmental factors)
//   rank 2..N   -> SecondaryCropDetailsSheet    (model explanation)
// -----------------------------------------------------------------------------

/// Sizing and colours shared by both sheets so they stay visually identical.
abstract final class CropSheetStyle {
  static const topRadius = 30.0;
  static const pagePadding = 20.0;
  static const cardRadius = 22.0;
  static const smallRadius = 18.0;
  static const cardGap = 12.0;
  static const sectionGap = 22.0;
  static const iconCircle = 52.0;
  static const closeSize = 46.0;

  static const surface = Color(0xFFF8FCF7);
  static const ink = Color(0xFF173B2A);
  static const muted = Color(0xFF53655B);
  static const border = Color(0xFFDDE9E0);

  static const greenSoft = Color(0xFFE5F3E7);
  static const amber = Color(0xFF9A6700);
  static const amberSoft = Color(0xFFFFF4D6);
  static const red = Color(0xFFC62F3E);
  static const redSoft = Color(0xFFFDECEC);
  static const blue = Color(0xFF2A6F97);
  static const blueSoft = Color(0xFFEAF4FB);
  static const lavender = Color(0xFF5B4BB7);
  static const lavenderSoft = Color(0xFFF0EDFB);
  static const grey = Color(0xFF5F6F66);
  static const greySoft = Color(0xFFEEF2EF);
}

// ------------------------------- formatting ----------------------------------

String _cropNum(num? value) {
  if (value == null) return 'Unavailable';
  var text = value.toStringAsFixed(2);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return text;
}

/// Display unit for a stored unit string ('C' -> '°C', 'pH'/'index' -> none).
String _cropUnit(Object? unit) {
  final text = '${unit ?? ''}'.trim();
  if (text == 'C') return '°C';
  if (text == 'pH' || text == 'index' || text == 'null') return '';
  return text;
}

String _withUnit(String number, String unit) {
  if (unit.isEmpty) return number;
  if (unit == '%' || unit == '°C') return '$number$unit';
  return '$number $unit';
}

String _rangeText(double? low, double? high, String unit) {
  if (low == null && high == null) return 'No crop-specific range saved';
  if (low != null && high != null) {
    final suffix = unit.isEmpty
        ? ''
        : (unit == '%' || unit == '°C' ? unit : ' $unit');
    return '${_cropNum(low)} – ${_cropNum(high)}$suffix';
  }
  if (low != null) return '≥ ${_withUnit(_cropNum(low), unit)}';
  return '≤ ${_withUnit(_cropNum(high), unit)}';
}

String ordinalRecommendation(int rank) {
  final lastTwo = rank % 100;
  final String suffix;
  if (lastTwo >= 11 && lastTwo <= 13) {
    suffix = 'th';
  } else if (rank % 10 == 1) {
    suffix = 'st';
  } else if (rank % 10 == 2) {
    suffix = 'nd';
  } else if (rank % 10 == 3) {
    suffix = 'rd';
  } else {
    suffix = 'th';
  }
  return '$rank$suffix recommendation';
}

/// Wording for the existing farmerSuitability() thresholds (unchanged).
String cropMatchDescription(double score) => score >= 75
    ? 'This crop strongly matches the environmental conditions of your selected area.'
    : score >= 50
    ? 'This crop may be suitable for your area, although some conditions are not ideal.'
    : score >= 25
    ? 'This crop may be suitable for your area, but there are notable limitations based on the current conditions.'
    : 'This crop has a low match with the current environmental conditions of your selected area.';

const _cropMissingConditionsMessage =
    'Crop-specific conditions were not saved with this result. Run a new farm analysis to record them.';

// ---------------------------------- data -------------------------------------

enum CropFactorState { suitable, near, outside, unassessed }

/// One environmental factor, normalised from either saved-result format.
class CropFactorView {
  final String key, label, unit, interpretation;
  final double? value, min, max;
  final CropFactorState state;
  final bool usedByModel;
  const CropFactorView({
    required this.key,
    required this.label,
    required this.unit,
    required this.interpretation,
    required this.value,
    required this.min,
    required this.max,
    required this.state,
    this.usedByModel = false,
  });
}

/// Reads the factors already stored with the crop. Returns an empty list when
/// the result did not save crop-specific conditions.
List<CropFactorView> cropFactorViews(
  Map<String, dynamic> crop,
  Map<String, dynamic> record,
) {
  final views = <CropFactorView>[];
  if (record['scoring_version'] != null) {
    for (final raw in analysisListValue(crop['factors']).whereType<Map>()) {
      final factor = Map<String, dynamic>.from(raw);
      final requirement = analysisMapValue(factor['requirement']);
      final optimal = analysisListValue(requirement['optimal']);
      final score = analysisNumber(factor['score']);
      final value = analysisNumber(factor['value']);
      views.add(
        CropFactorView(
          key: '${factor['factor']}',
          label: '${factor['label'] ?? factor['factor']}',
          unit: _cropUnit(factor['unit']),
          interpretation: '${factor['result'] ?? 'Result unavailable'}',
          value: value,
          min: optimal.length == 2 ? analysisNumber(optimal[0]) : null,
          max: optimal.length == 2 ? analysisNumber(optimal[1]) : null,
          state: score == null
              ? CropFactorState.unassessed
              : score >= 100
              ? CropFactorState.suitable
              : score <= 0
              ? CropFactorState.outside
              : CropFactorState.near,
        ),
      );
    }
    return views;
  }
  final condition = cropConditions(crop);
  for (final raw in analysisListValue(condition['factors']).whereType<Map>()) {
    final factor = Map<String, dynamic>.from(raw);
    final value = analysisNumber(factor['value']);
    final low = analysisNumber(factor['preferred_min']);
    final high = analysisNumber(factor['preferred_max']);
    final fit = analysisNumber(factor['fit']);
    final inside =
        value != null &&
        (low == null || value >= low) &&
        (high == null || value <= high);
    // 0.78 is the "within or close to" cut-off the backend already uses.
    final suitable = fit != null ? fit >= .78 : inside;
    views.add(
      CropFactorView(
        key: '${factor['feature']}',
        label: '${factor['label'] ?? factor['feature']}',
        unit: _cropUnit(factor['unit']),
        interpretation: value == null
            ? 'Measurement unavailable.'
            : suitable
            ? 'Within or close to the preferred range.'
            : 'Outside the preferred range; this lowers the crop’s fit.',
        value: value,
        min: low,
        max: high,
        state: value == null
            ? CropFactorState.unassessed
            : suitable
            ? CropFactorState.suitable
            : CropFactorState.outside,
      ),
    );
  }
  return views;
}

/// The ten recorded environmental inputs, separate from reference scoring.
const environmentalFactorDefinitions = [
  (
    'rainfall',
    'Rainfall (30 days)',
    'mm',
    ['rainfall_30d_mm', 'rainfall_monthly_mm', 'monthly_rainfall_mm', 'rain'],
  ),
  (
    'temperature',
    'Temperature',
    '°C',
    ['temperature_c', 'surface_temp_c', 'temp'],
  ),
  ('humidity', 'Humidity', '%', ['humidity', 'live_humidity']),
  ('ndvi', 'Vegetation (NDVI)', '', ['ndvi']),
  ('ph', 'Soil pH', '', ['soil_ph']),
  ('N', 'Nitrogen (N)', '', ['nitrogen']),
  ('P', 'Phosphorus (P)', '', ['phosphorus']),
  ('K', 'Potassium (K)', '', ['potassium']),
  ('elevation', 'Elevation', 'm', ['elevation_m']),
  ('slope', 'Slope', '%', ['slope_pct']),
];

List<CropFactorView> environmentalFactorViews(
  Map<String, dynamic> crop,
  Map<String, dynamic> record,
) {
  final saved = cropFactorViews(crop, record);
  return environmentalFactorDefinitions.map((definition) {
    final key = definition.$1;
    final modelValue = recordedModelInput(record, key);
    double? value = modelValue;
    // A model snapshot with missing inputs must not be silently filled with
    // readings from another source or date.
    if (analysisListValue(
      analysisMapValue(record['model_explanation'])['samples'],
    ).isEmpty) {
      for (final alias in definition.$4) {
        value ??= analysisNumber(record[alias]);
      }
      for (final candidate in saved) {
        if ((candidate.key == key || definition.$4.contains(candidate.key)) &&
            candidate.unit == definition.$3) {
          value ??= candidate.value;
        }
      }
    }
    CropFactorView? comparison;
    for (final candidate in saved) {
      final matches =
          candidate.key == key || definition.$4.contains(candidate.key);
      if (matches &&
          candidate.unit == definition.$3 &&
          (candidate.value == value ||
              ['ph', 'elevation', 'slope'].contains(key)) &&
          value != null &&
          (candidate.min != null || candidate.max != null)) {
        comparison = candidate;
        break;
      }
    }
    final nutrient = ['N', 'P', 'K'].contains(key);
    return CropFactorView(
      key: key,
      label: definition.$2,
      unit: definition.$3,
      value: value,
      min: comparison?.min,
      max: comparison?.max,
      state: comparison == null
          ? CropFactorState.unassessed
          : comparison.value == value
          ? comparison.state
          : (comparison.min == null || value! >= comparison.min!) &&
                (comparison.max == null || value! <= comparison.max!)
          ? CropFactorState.suitable
          : CropFactorState.outside,
      usedByModel: modelValue != null,
      interpretation: value == null
          ? 'Not recorded for this analysis.'
          : nutrient
          ? 'Existing model estimate; not a soil test.'
          : comparison != null && comparison.value != value
          ? ((comparison.min == null || value >= comparison.min!) &&
                    (comparison.max == null || value <= comparison.max!)
                ? 'Within the recorded preferred range.'
                : 'Outside the recorded preferred range.')
          : comparison?.interpretation ??
                (modelValue != null
                    ? 'Used with the other inputs to predict crop rankings.'
                    : 'Recorded observation; no comparable crop range recorded.'),
    );
  }).toList();
}

/// Rank of the tapped crop: explicit argument, stored rank, else list position.
int? cropDisplayRank(
  Map<String, dynamic> crop,
  Map<String, dynamic> record, {
  int? rank,
}) {
  if (rank != null && rank > 0) return rank;
  final stored = analysisNumber(crop['rank']);
  if (stored != null && stored > 0) return stored.round();
  final name = '${crop['crop'] ?? crop['name']}'.toLowerCase();
  final index = assessedCrops(
    record,
  ).indexWhere((c) => '${c['crop'] ?? c['name']}'.toLowerCase() == name);
  return index >= 0 ? index + 1 : null;
}

/// Entry point used by every "See details" / "View details" button.
void showCropDetailsSheet(
  BuildContext context,
  Map<String, dynamic> crop,
  Map<String, dynamic> record, {
  int? rank,
}) {
  final resolved = cropDisplayRank(crop, record, rank: rank);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => resolved == 1
        ? RecommendedCropDetailsSheet(crop: crop, record: record)
        : SecondaryCropDetailsSheet(crop: crop, record: record, rank: resolved),
  );
}

void _openCropSources(
  BuildContext context,
  Map<String, dynamic> crop,
  Map<String, dynamic> record,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFFF5FBF5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _ReferenceCropDetails(crop: crop, record: record),
  );
}

// ------------------------------- frame/header --------------------------------

/// Shared bottom-sheet shell: rounded top, drag handle, fixed header, scrolling
/// body. Both sheet types use it so spacing and sizes cannot drift apart.
class CropSheetFrame extends StatelessWidget {
  final Widget header;
  final List<Widget> children;
  const CropSheetFrame({
    super.key,
    required this.header,
    required this.children,
  });
  @override
  Widget build(BuildContext context) {
    const pad = CropSheetStyle.pagePadding;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .92,
      ),
      child: Material(
        color: CropSheetStyle.surface,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(CropSheetStyle.topRadius),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFC3CFC7),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(pad, 14, pad, 14),
              child: header,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(pad, 2, pad, 24 + bottomInset),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(color: CropSheetStyle.ink),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CropDetailsHeader extends StatelessWidget {
  final String cropName, title;
  final Widget badge;
  final String? caption;
  const CropDetailsHeader({
    super.key,
    required this.cropName,
    required this.title,
    required this.badge,
    this.caption,
  });
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CropArtwork(cropName, size: 64),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 22,
                height: 1.15,
                fontWeight: FontWeight.w800,
                color: darkGreen,
              ),
            ),
            const SizedBox(height: 8),
            badge,
            if (caption != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  caption!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: CropSheetStyle.muted,
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(width: 10),
      SizedBox.square(
        dimension: CropSheetStyle.closeSize,
        child: IconButton(
          tooltip: 'Close',
          style: IconButton.styleFrom(
            backgroundColor: softGreen,
            foregroundColor: darkGreen,
            padding: EdgeInsets.zero,
            shape: const CircleBorder(),
          ),
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, size: 22),
        ),
      ),
    ],
  );
}

class _CropPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color background, foreground;
  const _CropPill({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: foreground),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Soft amber pill: "2nd recommendation", "3rd recommendation", ...
class RankingBadge extends StatelessWidget {
  final String label;
  const RankingBadge({super.key, required this.label});
  @override
  Widget build(BuildContext context) => _CropPill(
    label: label,
    icon: Icons.eco,
    background: CropSheetStyle.amberSoft,
    foreground: CropSheetStyle.amber,
  );
}

/// Icon + status text for one environmental factor.
class MatchStatusBadge extends StatelessWidget {
  final CropFactorState state;
  const MatchStatusBadge({super.key, required this.state});
  static Color colorFor(CropFactorState state) => switch (state) {
    CropFactorState.suitable => const Color(0xFF14833B),
    CropFactorState.near => CropSheetStyle.amber,
    CropFactorState.outside => CropSheetStyle.red,
    CropFactorState.unassessed => CropSheetStyle.grey,
  };
  static Color softFor(CropFactorState state) => switch (state) {
    CropFactorState.suitable => const Color(0xFFE7F5EA),
    CropFactorState.near => CropSheetStyle.amberSoft,
    CropFactorState.outside => CropSheetStyle.redSoft,
    CropFactorState.unassessed => CropSheetStyle.greySoft,
  };
  @override
  Widget build(BuildContext context) {
    final color = colorFor(state);
    final (icon, label) = switch (state) {
      CropFactorState.suitable => (Icons.check_circle, 'Suitable'),
      CropFactorState.near => (Icons.error_outline, 'Near range'),
      CropFactorState.outside => (Icons.error, 'Outside range'),
      CropFactorState.unassessed => (Icons.help_outline, 'Not assessed'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

// --------------------------------- cards -------------------------------------

class _ScoreDial extends StatelessWidget {
  final double? score;
  final double size;
  final String label;
  const _ScoreDial({
    required this.score,
    required this.size,
    this.label = 'Suitability',
  });
  @override
  Widget build(BuildContext context) {
    final value = ((score ?? 0).clamp(0, 100)) / 100;
    final color = score == null
        ? CropSheetStyle.grey
        : score! >= 75
        ? const Color(0xFF14833B)
        : score! >= 25
        ? const Color(0xFFF2B01E)
        : CropSheetStyle.red;
    return Semantics(
      label: score == null
          ? 'Suitability unavailable'
          : '$label ${_cropNum(score)} percent',
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CircularProgressIndicator(
                  value: value.toDouble(),
                  strokeWidth: 10,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.white.withValues(alpha: .8),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        score == null ? 'N/A' : '${_cropNum(score)}%',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: CropSheetStyle.ink,
                        ),
                      ),
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 11,
                          color: CropSheetStyle.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Large light-green card: circular score on the left, text on the right.
class SuitabilityScoreCard extends StatelessWidget {
  final double? score;
  final String title, description;
  final String scoreLabel;
  const SuitabilityScoreCard({
    super.key,
    required this.score,
    required this.title,
    required this.description,
    this.scoreLabel = 'Suitability',
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          constraints.maxWidth < 300 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.35;
      final text = Column(
        crossAxisAlignment: stacked
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: stacked ? TextAlign.center : TextAlign.start,
            style: const TextStyle(
              fontSize: 18,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: darkGreen,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: stacked ? TextAlign.center : TextAlign.start,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.35,
              color: CropSheetStyle.muted,
            ),
          ),
        ],
      );
      final dial = _ScoreDial(
        score: score,
        size: stacked ? 112 : 104,
        label: scoreLabel,
      );
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CropSheetStyle.greenSoft,
          borderRadius: BorderRadius.circular(CropSheetStyle.cardRadius),
        ),
        child: stacked
            ? Column(children: [dial, const SizedBox(height: 14), text])
            : Row(
                children: [
                  dial,
                  Container(
                    width: 1,
                    height: 76,
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    color: green.withValues(alpha: .18),
                  ),
                  Expanded(child: text),
                ],
              ),
      );
    },
  );
}

class _SheetHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SheetHeading(this.title, {this.subtitle});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: CropSheetStyle.cardGap),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: darkGreen,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: const TextStyle(
              fontSize: 13,
              height: 1.35,
              color: CropSheetStyle.muted,
            ),
          ),
        ],
      ],
    ),
  );
}

(IconData, Color, Color) _factorIcon(String key) {
  final k = key.toLowerCase();
  if (k.contains('ndvi')) {
    return (Icons.eco, const Color(0xFF14833B), const Color(0xFFE7F5EA));
  }
  if (k.contains('temp')) {
    return (Icons.thermostat, CropSheetStyle.red, CropSheetStyle.redSoft);
  }
  if (k.contains('ph')) {
    return (
      Icons.science_outlined,
      CropSheetStyle.amber,
      const Color(0xFFFFF0DC),
    );
  }
  if (k.contains('humid')) {
    return (Icons.water_drop, CropSheetStyle.blue, CropSheetStyle.blueSoft);
  }
  if (k.contains('rain')) {
    return (Icons.cloud_outlined, CropSheetStyle.blue, CropSheetStyle.blueSoft);
  }
  if (k.contains('elev')) {
    return (Icons.terrain, CropSheetStyle.grey, CropSheetStyle.greySoft);
  }
  if (k.contains('slope')) {
    return (Icons.trending_up, CropSheetStyle.grey, CropSheetStyle.greySoft);
  }
  return (Icons.grass, const Color(0xFF14833B), const Color(0xFFE7F5EA));
}

/// One measured factor: icon, name, current value, interpretation and the
/// preferred range with its status.
class EnvironmentalFactorCard extends StatelessWidget {
  final CropFactorView factor;
  const EnvironmentalFactorCard({super.key, required this.factor});
  @override
  Widget build(BuildContext context) {
    final (icon, tint, tintBg) = _factorIcon(factor.key);
    final statusColor = MatchStatusBadge.colorFor(factor.state);
    final current = factor.value == null
        ? 'Unavailable'
        : _withUnit(_cropNum(factor.value), factor.unit);
    final hasRange = factor.min != null || factor.max != null;
    final rangeBox = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: MatchStatusBadge.softFor(factor.state),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasRange ? 'Preferred range comparison' : 'Model assessment',
            style: TextStyle(fontSize: 10.5, color: CropSheetStyle.muted),
          ),
          const SizedBox(height: 2),
          Text(
            hasRange
                ? _rangeText(factor.min, factor.max, factor.unit)
                : factor.usedByModel
                ? 'Used in crop prediction'
                : 'Model input not recorded',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: factor.state == CropFactorState.outside
                  ? statusColor
                  : CropSheetStyle.ink,
            ),
          ),
          const SizedBox(height: 6),
          if (hasRange)
            MatchStatusBadge(state: factor.state)
          else
            Text(
              factor.usedByModel
                  ? 'The model evaluates factors together; it does not assign a separate suitability grade to each input.'
                  : 'This saved result cannot confirm whether the model used this factor.',
              style: const TextStyle(fontSize: 12, color: CropSheetStyle.muted),
            ),
        ],
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          factor.label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          current,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          factor.interpretation,
          style: const TextStyle(
            fontSize: 12,
            height: 1.3,
            color: CropSheetStyle.muted,
          ),
        ),
      ],
    );
    final iconCircle = Container(
      width: CropSheetStyle.iconCircle,
      height: CropSheetStyle.iconCircle,
      decoration: BoxDecoration(color: tintBg, shape: BoxShape.circle),
      child: Icon(icon, color: tint, size: 26),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: CropSheetStyle.cardGap),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(CropSheetStyle.smallRadius),
          border: Border.all(color: CropSheetStyle.border),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 320 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.35;
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      iconCircle,
                      const SizedBox(width: 12),
                      Expanded(child: details),
                    ],
                  ),
                  const SizedBox(height: 10),
                  rangeBox,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                iconCircle,
                const SizedBox(width: 12),
                Expanded(child: details),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 104,
                    maxWidth: 132,
                  ),
                  child: rangeBox,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Soft coloured information card with an icon, a title and body content.
class InfoExplanationCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  final Color background, accent;
  const InfoExplanationCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.background = CropSheetStyle.greenSoft,
    this.accent = darkGreen,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: CropSheetStyle.cardGap),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(CropSheetStyle.smallRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: CropSheetStyle.iconCircle,
            height: CropSheetStyle.iconCircle,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .85),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: DefaultTextStyle.merge(
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: CropSheetStyle.muted,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: CropSheetStyle.ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  ...children,
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _gap(double h) => SizedBox(height: h);

// ------------------------------ rank 1 sheet ---------------------------------

class RecommendedCropDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> crop, record;
  const RecommendedCropDetailsSheet({
    super.key,
    required this.crop,
    required this.record,
  });
  @override
  Widget build(BuildContext context) {
    final name = '${crop['crop'] ?? crop['name'] ?? 'Unnamed crop'}';
    final score = analysisNumber(crop['compatibility_pct'] ?? crop['score']);
    final factors = environmentalFactorViews(crop, record);
    final seasonNote = crop['season_note'];
    return CropSheetFrame(
      header: CropDetailsHeader(
        cropName: name,
        title: name,
        caption: 'Details',
        badge: const _CropPill(
          label: 'Recommended',
          icon: Icons.eco,
          background: CropSheetStyle.greenSoft,
          foreground: Color(0xFF14833B),
        ),
      ),
      children: [
        SuitabilityScoreCard(
          score: score,
          scoreLabel: isModelRanked(record) ? 'Model score' : 'Suitability',
          title: '$name was selected as the best match.',
          description: isModelRanked(record)
              ? 'Highest mean Random Forest class probability across the farm samples. Environmental comparisons below do not change this ranking.'
              : 'The explanation below shows the measured conditions that contributed most to that result.',
        ),
        _gap(CropSheetStyle.sectionGap),
        _SheetHeading(
          'Environmental Factors',
          subtitle:
              'Ten environmental factors used together by the model. Recorded crop-range comparisons are separate from the prediction.',
        ),
        if (factors.isEmpty)
          const InfoExplanationCard(
            icon: Icons.info_outline,
            title: 'Environmental data unavailable',
            background: CropSheetStyle.greySoft,
            accent: CropSheetStyle.grey,
            children: [Text(_cropMissingConditionsMessage)],
          )
        else
          for (final factor in factors) EnvironmentalFactorCard(factor: factor),
        if (seasonNote != null && '$seasonNote'.trim().isNotEmpty)
          InfoExplanationCard(
            icon: Icons.event_note_outlined,
            title: 'Seasonal note',
            background: CropSheetStyle.amberSoft,
            accent: CropSheetStyle.amber,
            children: [Text('$seasonNote')],
          ),
        InfoExplanationCard(
          icon: Icons.info,
          title: 'Note',
          background: CropSheetStyle.blueSoft,
          accent: CropSheetStyle.blue,
          children: [
            Text(
              isModelRanked(record)
                  ? 'Model class scores are not harvest probabilities. Training includes synthetic GIS features, and nutrient inputs include estimated proxies.'
                  : 'These values are based on the environmental conditions retrieved for your selected area. The suitability score considers all factors together.',
            ),
          ],
        ),
        if (record['scoring_version'] != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openCropSources(context, crop, record),
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: const Text('Requirements, sources & method'),
            ),
          ),
      ],
    );
  }
}

// ----------------------------- rank 2+ sheet ---------------------------------

class SecondaryCropDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> crop, record;
  final int? rank;
  const SecondaryCropDetailsSheet({
    super.key,
    required this.crop,
    required this.record,
    required this.rank,
  });
  @override
  Widget build(BuildContext context) {
    final name = '${crop['crop'] ?? crop['name'] ?? 'Unnamed crop'}';
    final score = analysisNumber(crop['compatibility_pct'] ?? crop['score']);
    final factors = environmentalFactorViews(crop, record);
    final modelRanked = isModelRanked(record);
    final scored = record['scoring_version'] != null && !modelRanked;
    final scoring = analysisMapValue(crop['score_breakdown']);
    final modelScore = analysisNumber(crop['model_probability_pct']);
    final rankValue = rank;
    return CropSheetFrame(
      header: CropDetailsHeader(
        cropName: name,
        title: '$name details',
        badge: RankingBadge(
          label: rankValue == null
              ? 'Not ranked'
              : ordinalRecommendation(rankValue),
        ),
      ),
      children: [
        SuitabilityScoreCard(
          score: score,
          scoreLabel: modelRanked ? 'Model score' : 'Suitability',
          title: score == null
              ? 'Suitability unavailable'
              : modelRanked
              ? 'Model-ranked recommendation'
              : farmerSuitability(score),
          description: score == null
              ? 'There was not enough recorded data to calculate a suitability score for this crop.'
              : modelRanked
              ? 'Ranked by mean Random Forest class probability across farm samples. This is not a probability of a successful harvest.'
              : cropMatchDescription(score),
        ),
        _gap(CropSheetStyle.cardGap),
        InfoExplanationCard(
          icon: Icons.spa,
          title: 'About these details',
          children: [
            const Text(
              'Crop growing requirements — condition comparisons, not model contributions.',
            ),
            const SizedBox(height: 8),
            Text(cropReason(crop, record)),
          ],
        ),
        if (factors.isNotEmpty) ...[
          _gap(CropSheetStyle.cardGap),
          _SheetHeading(
            'Environmental Factors',
            subtitle:
                'Ten environmental factors. Model input availability and recorded range comparisons are shown separately.',
          ),
          for (final factor in factors) EnvironmentalFactorCard(factor: factor),
        ],
        _gap(CropSheetStyle.cardGap),
        _SheetHeading(
          scored
              ? 'How this score was calculated'
              : 'Why the model recommended this crop',
        ),
        if (scored)
          InfoExplanationCard(
            icon: Icons.insights,
            title: 'Scoring method',
            background: CropSheetStyle.blueSoft,
            accent: CropSheetStyle.blue,
            children: [
              const Text(
                'This index compares documented requirements with the available observations. It is not a harvest probability, yield forecast, or model prediction.',
              ),
              if (crop['scoring_version'] != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Configuration: ${crop['scoring_version']}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ],
          )
        else ...[
          const InfoExplanationCard(
            icon: Icons.bar_chart,
            title: 'Model explanation',
            background: CropSheetStyle.blueSoft,
            accent: CropSheetStyle.blue,
            children: [
              Text(
                'This model provides overall feature importance only. It does not provide crop-specific contributions or show which inputs increased or decreased this prediction.',
              ),
            ],
          ),
          InfoExplanationCard(
            icon: Icons.description_outlined,
            title: 'Recorded model class score',
            background: CropSheetStyle.amberSoft,
            accent: CropSheetStyle.amber,
            children: [
              Text(
                modelScore == null
                    ? 'A model class score was not recorded for this crop in this analysis.'
                    : modelRanked
                    ? '${_cropNum(modelScore)}%. This raw model class score determines the ranking; it is not a harvest probability.'
                    : '${_cropNum(modelScore)}%. This is separate from the final crop suitability score and is not a harvest probability.',
              ),
              if (scoring['model_class_available'] == false) ...[
                const SizedBox(height: 6),
                const Text(
                  'The trained model has no mapped class for this crop. The existing scoring rule used a neutral model component.',
                ),
              ],
            ],
          ),
        ],
        if (!modelRanked)
          const InfoExplanationCard(
            icon: Icons.info,
            title: 'How to interpret the score',
            background: CropSheetStyle.lavenderSoft,
            accent: CropSheetStyle.lavender,
            children: [
              Text(
                'The score compares crop fit; it is not a harvest probability.',
              ),
              SizedBox(height: 6),
              Text('Good match: 75–100'),
              Text('Possible match: 50–<75'),
              Text('Limited match: 25–<50'),
              Text('Poor match: below 25'),
              SizedBox(height: 6),
              Text('The existing thresholds are unchanged.'),
            ],
          ),
        if (scored)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openCropSources(context, crop, record),
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: const Text('Requirements, sources & method'),
            ),
          ),
      ],
    );
  }
}
