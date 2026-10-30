// Human-readable explanations derived only from the selected saved analysis.
// No current requirements, model inference, rule boosts or external generation.
import 'dart:collection';
import 'local_explanation.dart';

double? _finite(dynamic value) =>
    value is num && value.isFinite ? value.toDouble() : null;
String summaryNumber(num value, {int decimals = 3}) => decimals == 0
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(decimals).replaceFirst(RegExp(r'\.?0+$'), '');
String _displayUnit(String value) => value == 'C' ? '\u00b0C' : value;
String _interval(List<dynamic> bounds, String unit) {
  if (bounds[0] == null) {
    return 'up to ${summaryNumber(bounds[1] as num)} $unit';
  }
  if (bounds[1] == null) {
    return 'at least ${summaryNumber(bounds[0] as num)} $unit';
  }
  return '${summaryNumber(bounds[0] as num)}-${summaryNumber(bounds[1] as num)} $unit';
}

List<Map<String, dynamic>> savedReferenceFit(
  Map<String, dynamic> record,
  String crop,
) {
  final saved = localRows(
    record['crop_assessments'],
  ).where((r) => r['crop'] == crop).firstOrNull;
  if (saved == null) {
    return [];
  }
  return [for (final row in localRows(saved['factors'])) _referenceFactor(row)];
}

Map<String, dynamic> _referenceFactor(Map<String, dynamic> factor) {
  final observation = localObject(factor['measurement']);
  final rule = localObject(factor['requirement']);
  final source = localObject(rule['source']);
  final bounds = rule['optimal'];
  final value = _finite(factor['value']), score = _finite(factor['score']);
  final unit = '${factor['unit'] ?? ''}', period = '${factor['period'] ?? ''}';
  final url = Uri.tryParse('${source['url'] ?? ''}');
  const contracts = {
    'temperature': ('C', 'annual_mean'),
    'rainfall': ('mm/year', 'annual_mean_total'),
    'soil_ph': ('pH', 'soil_surface'),
    'elevation': ('m', 'terrain'),
    'slope': ('%', 'terrain'),
    'humidity': ('%', 'annual_mean'),
  };
  final contract = contracts[factor['factor']];
  final compatible =
      value != null &&
      score != null &&
      score >= 0 &&
      score <= 100 &&
      value == _finite(observation['value']) &&
      unit.isNotEmpty &&
      period.isNotEmpty &&
      observation['unit'] == unit &&
      observation['period'] == period &&
      ['measured', 'modelled'].contains(observation['quality']) &&
      bounds is List &&
      bounds.length == 2 &&
      bounds.any((v) => _finite(v) != null) &&
      bounds.every((v) => v == null || _finite(v) != null) &&
      (bounds[0] == null ||
          bounds[1] == null ||
          (bounds[0] as num) <= (bounds[1] as num)) &&
      contract != null &&
      unit == contract.$1 &&
      period == contract.$2 &&
      source['title'] is String &&
      '${source['title']}'.trim().isNotEmpty &&
      url != null &&
      url.scheme == 'https' &&
      url.host.isNotEmpty &&
      url.userInfo.isEmpty;
  return {
    'factor': factor['factor'],
    'label': factor['label'] ?? factor['factor'],
    'status': !compatible
        ? 'not_assessed'
        : score == 100
        ? 'fits'
        : score == 0
        ? 'outside'
        : 'limited',
    'value': value,
    'unit': _displayUnit(unit),
    'period': period,
    'quality': observation['quality'],
    'preferred': compatible ? List<dynamic>.from(bounds) : null,
    'source': compatible ? source : <String, dynamic>{},
    'text': !compatible
        ? 'Not assessed: a compatible observation and cited criterion are required.'
        : '${summaryNumber(value)} ${_displayUnit(unit)}; preferred ${_interval(bounds, _displayUnit(unit))}.',
    'interpretation': compatible ? factor['result'] : null,
    'limitations': compatible ? rule['limitations'] : null,
  };
}

List<Map<String, dynamic>> _signed(
  List<Map<String, dynamic>> features,
  bool positive,
) =>
    features
        .where(
          (f) => positive
              ? (f['contribution_pp'] as num) > 0
              : (f['contribution_pp'] as num) < 0,
        )
        .toList()
      ..sort(
        (a, b) => (b['contribution_pp'] as num).abs().compareTo(
          (a['contribution_pp'] as num).abs(),
        ),
      );

Map<String, dynamic> recommendationSummary(
  Map<String, dynamic> record,
  String crop,
) {
  final body = verifiedLocalExplanation(record);
  if (body.isEmpty) {
    return {'status': 'unavailable'};
  }
  final view = localCropView(body, crop);
  if (view.isEmpty) {
    return {'status': 'unavailable'};
  }
  final candidates =
      [
        for (final binding in localRows(body['crop_classes']))
          {
            'crop': binding['crop'],
            'score': localCropView(body, '${binding['crop']}')['score_pct'],
          },
      ]..sort((a, b) {
        final difference = (b['score'] as num).compareTo(a['score'] as num);
        return difference != 0
            ? difference
            : '${a['crop']}'.compareTo('${b['crop']}');
      });
  final index = candidates.indexWhere((r) => r['crop'] == crop);
  final rank = index + 1, score = view['score_pct'] as num;
  final tied = candidates.where((r) => r['score'] == score).length > 1;
  final other = candidates.length < 2
      ? null
      : '${candidates[index == 0 ? 1 : 0]['crop']}';
  final difference = other == null
      ? <String, dynamic>{}
      : localCropComparison(body, crop, other);
  final gap = other == null
      ? 0.0
      : (difference['score_gap_pp'] as num).toDouble();
  final gapText = gap.abs() > 0 && gap.abs() < .001
      ? 'less than 0.001'
      : gap.abs().toStringAsFixed(3);
  final features = localRows(view['features']);
  final positive = _signed(features, true), negative = _signed(features, false);
  final comparisons = savedReferenceFit(record, crop);
  final climate = localObject(record['seasonal_assessment']);
  final calendar = localObject(climate['calendar']);
  final cropCalendar = localRows(calendar['crops'])
      .where((r) => '${r['crop']}'.toLowerCase() == crop.toLowerCase())
      .firstOrNull;
  final featureInputs = {
    for (final f in localRows(body['feature_inputs']))
      '${f['feature']}': f['mean'],
  };
  final terrain = [
    for (final item in [
      ('elevation', 'Elevation', 'm'),
      ('slope', 'Slope', '%'),
      ('ndvi', 'NDVI', 'index'),
    ])
      if (_finite(featureInputs[item.$1]) != null)
        '${item.$2} ${summaryNumber(featureInputs[item.$1] as num)} ${item.$3}',
  ].join('; ');
  final citations = <String, Map<String, dynamic>>{};
  for (final factor in comparisons) {
    final source = localObject(factor['source']);
    if (source.isNotEmpty) {
      citations['${source['url']}-${source['section']}'] = source;
    }
  }
  return {
    'status': 'available',
    'crop': crop,
    'rank': rank,
    'candidate_count': candidates.length,
    'score_pct': score,
    'sample_count': body['sample_count'],
    'baseline_pct': view['base_pct'],
    'net_pp': view['net_pp'],
    'other': other,
    'gap_pp': gap,
    'heading': score <= 0
        ? 'No positive model score for $crop'
        : 'Why $crop ranks #$rank',
    'ranking': score <= 0
        ? '$crop has a recorded score of 0%; it is not a positive model recommendation.'
        : candidates.length == 1
        ? '$crop is the only enabled crop in this saved ranking (${score.toStringAsFixed(3)}%).'
        : tied
        ? '$crop shares a ${score.toStringAsFixed(3)}% score. Equal scores use alphabetical order in the displayed ranking.'
        : '$crop scored ${score.toStringAsFixed(3)}%, $gapText percentage points ${gap > 0 ? 'above' : 'below'} $other, across ${body['sample_count']} saved samples.',
    'supporting': positive.take(2).toList(),
    'limiting': negative.take(2).toList(),
    'model_summary': [
      if (positive.isNotEmpty)
        '${positive.take(2).map((f) => f['label']).join(' and ')} raise the model score.',
      if (negative.isNotEmpty)
        '${negative.take(2).map((f) => f['label']).join(' and ')} lower it.',
      if (positive.isEmpty && negative.isEmpty)
        'The inputs leave this score at its model baseline.',
    ].join(' '),
    'contrast_supporting': other == null
        ? []
        : _signed(localRows(difference['features']), true).take(2).toList(),
    'contrast_limiting': other == null
        ? []
        : _signed(localRows(difference['features']), false).take(2).toList(),
    'reference_factors': comparisons,
    'reference_sources': citations.values.toList(),
    'season': climate.isEmpty
        ? 'Seasonal context was not saved.'
        : '${climate['selected_month_name']}: historical climate ${climate['status']}. '
              '${cropCalendar == null || cropCalendar['selected_month_listed'] is! bool
                  ? 'No saved crop calendar match.'
                  : cropCalendar['selected_month_listed'] == true
                  ? 'Calendar month listed.'
                  : 'Calendar month not listed.'}',
    'terrain': terrain,
    'limit':
        'Model scores are not harvest probabilities. Nutrients are estimates; field checks are still needed.',
    'reference_note':
        'Cited requirements check growing conditions separately; they do not change the model ranking.',
  };
}

List<String> recommendationSummaryLines(
  Map<String, dynamic> record,
  String crop,
) {
  final summary = recommendationSummary(record, crop);
  if (summary['status'] != 'available') {
    return ['A verified saved model explanation is unavailable.'];
  }
  return [
    '${summary['heading']}',
    '${summary['ranking']}',
    '${summary['model_summary']}',
    for (final f in localRows(summary['contrast_supporting']))
      'Compared with ${summary['other']}: ${f['label']} adds ${localSigned(f['contribution_pp'] as num)} percentage points toward the score gap.',
    for (final f in localRows(summary['contrast_limiting']))
      'Compared with ${summary['other']}: ${f['label']} adds ${localSigned(f['contribution_pp'] as num)} percentage points toward the score gap.',
    'Research and reference fit: ${summary['reference_note']}',
    for (final factor in localRows(summary['reference_factors']))
      '${factor['label']}: ${factor['status']}. ${factor['text']}',
    for (final source in localRows(summary['reference_sources']))
      'Source: ${source['title']}; ${source['section']}; ${source['url']}. Scope: ${source['scope']}',
    '${summary['season']}',
    'Saved sample context: ${summary['terrain']}',
    '${summary['limit']}',
  ];
}
