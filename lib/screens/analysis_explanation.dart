part of '../main.dart';

String farmerSuitability(double score) => score >= 75
    ? 'Good match'
    : score >= 50
    ? 'Possible match'
    : score >= 25
    ? 'Limited match'
    : 'Poor match';

String farmerLandType(Map<String, dynamic> record) {
  final type = '${record['land_type'] ?? record['land_status'] ?? ''}'
      .toLowerCase();
  if (type == 'arable' || type.contains('arable / vegetated')) {
    return 'Land with plants';
  }
  if (type.contains('water')) return 'Water or flooded land';
  if (type.contains('infrastructure') || type.contains('bare')) {
    return 'Built-up or bare land';
  }
  if (type.contains('degraded')) return 'Land with little plant cover';
  return type.isEmpty ? 'Land type unavailable' : type.replaceAll('_', ' ');
}

List<Map<String, dynamic>> assessedCrops(Map<String, dynamic> record) {
  if (record['scoring_version'] != null) {
    return analysisListValue(record['crop_assessments']).whereType<Map>()
        .map((e) => Map<String,dynamic>.from(e)).toList();
  }
  final flag = record['is_crop_recommended'];
  if (flag == false || '$flag' == 'false' || '$flag' == '0') return [];
  final crops = analysisListValue(
    record['top_crop_recommendations'],
  ).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  final primary = '${record['predicted_crop'] ?? ''}'.trim();
  if (crops.isEmpty) {
    if (primary.isNotEmpty && primary != 'Land Analysis') {
      crops.add({
        'crop': primary,
        'compatibility_pct':
            record['crop_compatibility_pct'] ?? record['compatibility_pct'],
      });
    }
    crops.addAll(
      analysisListValue(
        record['alternative_crops'],
      ).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
    );
  }
  final seen = <String>{};
  crops.removeWhere(
    (c) => !seen.add('${c['crop'] ?? c['name']}'.toLowerCase()),
  );
  final index = crops.indexWhere(
    (c) => '${c['crop']}'.toLowerCase() == primary.toLowerCase(),
  );
  if (index > 0) crops.insert(0, crops.removeAt(index));
  return crops;
}

Map<String, dynamic> cropConditions(Map<String, dynamic> crop) {
  final value = analysisMapValue(crop['condition_comparison']);
  return '${value['crop']}'.toLowerCase() == '${crop['crop']}'.toLowerCase()
      ? value
      : {};
}

String cropReason(Map<String, dynamic> crop, Map<String, dynamic> record) {
  final condition = cropConditions(crop);
  for (final value in [
    condition['summary'],
    crop['reason'],
    crop['explanation'],
    crop['suitability_note'],
  ]) {
    if (value != null && '$value'.trim().isNotEmpty) return '$value';
  }
  final legacy = analysisMapValue(record['xai_explanation']);
  if ('${crop['crop']}'.toLowerCase() ==
          '${record['predicted_crop']}'.toLowerCase() &&
      '${legacy['crop']}'.toLowerCase() == '${crop['crop']}'.toLowerCase()) {
    final summary = legacy['plain_summary'] ?? legacy['summary'];
    if (summary != null && '$summary'.trim().isNotEmpty) return '$summary';
  }
  return 'Crop-specific conditions were not saved with this result. Run a new farm analysis to record them.';
}

String? cropRankingContext(
  Map<String, dynamic> crop,
  Map<String, dynamic> record,
) {
  final crops = assessedCrops(record);
  if (crops.isEmpty || crops.first['crop'] == crop['crop']) return null;
  final leader = crops.first;
  final sampleId = cropConditions(crop)['sample_id'];
  if (sampleId == null || sampleId != cropConditions(leader)['sample_id']) {
    return null;
  }
  final scoring = analysisMapValue(crop['score_breakdown']);
  if (scoring['model_class_available'] == false) {
    return 'The model has no matching class for this crop. Its score uses the existing neutral model component and the recorded growing conditions.';
  }
  final model = analysisNumber(crop['ml_score_component']);
  final topModel = analysisNumber(leader['ml_score_component']);
  final environment = analysisNumber(crop['environment_fit_pct']);
  final topEnvironment = analysisNumber(leader['environment_fit_pct']);
  final reasons = <String>[
    if (model != null && topModel != null && model < topModel)
      'a lower model score',
    if (environment != null &&
        topEnvironment != null &&
        environment < topEnvironment)
      'a weaker growing-condition match',
  ];
  if (reasons.isNotEmpty) {
    return 'Compared with ${leader['crop']}, this crop has ${reasons.join(' and ')}. Ranking and seasonal rules also affect the displayed score.';
  }
  return 'The saved rule adjustments and rank calibration place this crop below ${leader['crop']}. View details for its recorded scores.';
}

/// Measures the actual layout so even short text enlarged by accessibility
/// settings gets a working expansion control when it no longer fits.
class AnalysisReadableText extends StatefulWidget {
  final String text;
  const AnalysisReadableText(this.text, {super.key});
  @override
  State<AnalysisReadableText> createState() => _AnalysisReadableTextState();
}

class _AnalysisReadableTextState extends State<AnalysisReadableText> {
  bool expanded = false;
  @override
  void didUpdateWidget(AnalysisReadableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) expanded = false;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = DefaultTextStyle.of(
        context,
      ).style.copyWith(fontSize: 16, height: 1.45);
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: style),
        maxLines: 3,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: constraints.maxWidth);
      final needsExpansion = painter.didExceedMaxLines;
      painter.dispose();
      final text = Text(
        widget.text,
        style: style,
        maxLines: expanded ? null : 3,
        overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (MediaQuery.disableAnimationsOf(context))
            text
          else
            AnimatedSize(
              alignment: Alignment.topLeft,
              duration: const Duration(milliseconds: 160),
              child: text,
            ),
          if (needsExpansion)
            TextButton(
              onPressed: () => setState(() => expanded = !expanded),
              child: Text(expanded ? 'See less' : 'See more'),
            ),
        ],
      );
    },
  );
}

class _CropAssessmentCard extends StatelessWidget {
  final Map<String, dynamic> crop, record;
  final int rank;
  const _CropAssessmentCard({
    super.key,
    required this.crop,
    required this.record,
    required this.rank,
  });
  @override
  Widget build(BuildContext context) {
    final top = rank == 1;
    final name = '${crop['crop'] ?? crop['name'] ?? 'Unnamed crop'}';
    final score = analysisNumber(crop['compatibility_pct'] ?? crop['score']);
    final condition = cropConditions(crop);
    final rankingContext = cropRankingContext(crop, record);
    return _AnalysisSection(
      title: top ? 'Top recommendation' : '$rank. $name',
      surface: top ? const Color(0xFFE6F2E4) : Colors.white,
      icon: Icons.eco_outlined,
      children: [
        if (top)
          Text(
            name,
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              color: darkGreen,
            ),
          ),
        if (score != null) ...[
          const SizedBox(height: 8),
          Text(
            'Suitability for $name: ${score.toStringAsFixed(1)}%',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            farmerSuitability(score),
            style: const TextStyle(
              color: darkGreen,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: score.clamp(0, 100) / 100,
            minHeight: 6,
            borderRadius: BorderRadius.circular(8),
            color: green,
            backgroundColor: const Color(0xFFD4E3D3),
          ),
        ] else
          const Text('Suitability score unavailable'),
        const SizedBox(height: 14),
        const Text(
          'Crop growing requirements',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        AnalysisReadableText(
          cropReason(crop, record),
          key: ValueKey('reason-$name-${record['session_id']}'),
        ),
        if (rankingContext != null) ...[
          const SizedBox(height: 12),
          const Text(
            'Score context',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          AnalysisReadableText(rankingContext),
        ],
        if (condition['main_limitation'] != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF2D4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: AnalysisReadableText(
              'Main limitation: ${condition['main_limitation']}',
            ),
          ),
        ],
        TextButton.icon(
          onPressed: () => _showCropDetails(context, crop, record),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('View details'),
        ),
      ],
    );
  }
}

void _analysisDetails(
  BuildContext context,
  String title,
  List<Widget> children,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .86,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: darkGreen,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: DefaultTextStyle.merge(
                style: const TextStyle(fontSize: 16, height: 1.45),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void _showCropDetails(
  BuildContext context,
  Map<String, dynamic> crop,
  Map<String, dynamic> record,
) {
  if (record['scoring_version'] != null) {
    showModalBottomSheet(context: context, isScrollControlled: true, showDragHandle: true,
      backgroundColor: const Color(0xFFF5FBF5),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _ReferenceCropDetails(crop:crop,record:record));
    return;
  }
  final condition = cropConditions(crop);
  final scoring = analysisMapValue(crop['score_breakdown']);
  final rain = analysisMapValue(condition['rainfall_context']);
  _analysisDetails(context, '${crop['crop']} details', [
    const _AnalysisParagraph(
      'Crop growing requirements — condition comparisons, not model contributions.',
    ),
    _AnalysisParagraph(cropReason(crop, record)),
    if (condition['scope'] == 'ranking_sample')
      const _AnalysisParagraph(
        'These values belong to the recorded sample used for the crop ranking. Land conditions below the crop list are farm averages.',
      ),
    for (final factor in analysisListValue(
      condition['factors'],
    ).whereType<Map>())
      _AnalysisParagraph(
        '${factor['label']}: ${analysisNumber(factor['value'])?.toStringAsFixed(2) ?? 'unavailable'} ${factor['unit'] ?? ''}. '
        'Preferred range: ${factor['preferred_min']}–${factor['preferred_max']} ${factor['unit'] ?? ''}.',
      ),
    if (rain.isNotEmpty)
      _AnalysisParagraph(
        'Recent 30-day rainfall: ${rain['recent_30d_mm']} mm. Rainfall used in crop scoring: ${rain['scoring_mm']} mm. ${rain['method']}.',
      ),
    if (condition['note'] != null) _AnalysisParagraph('${condition['note']}'),
    if (crop['season_note'] != null)
      _AnalysisParagraph('${crop['season_note']}'),
    const Divider(),
    const _AnalysisParagraph('Why the model recommended this crop'),
    const _AnalysisParagraph(
      'This model provides overall feature importance only. It does not provide crop-specific contributions or show which inputs increased or decreased this prediction.',
    ),
    if (crop['model_probability_pct'] != null)
      _AnalysisParagraph(
        'Recorded model class score: ${crop['model_probability_pct']}%. This is separate from the final crop suitability score and is not a harvest probability.',
      ),
    if (analysisListValue(crop['model_labels']).isNotEmpty)
      _AnalysisParagraph(
        'Model class labels mapped to this crop: ${analysisListValue(crop['model_labels']).join(', ')}.',
      ),
    if (scoring['model_class_available'] == false)
      const _AnalysisParagraph(
        'The trained model has no mapped class for this crop. The existing scoring rule used a neutral model component.',
      ),
    if (scoring.isNotEmpty) ...[
      _AnalysisParagraph(
        'Before display calibration: model component ${scoring['model_component']} × ${scoring['ml_weight']}; '
        'environment component ${scoring['environment_component']} × ${scoring['environment_weight']}; rule penalty ${scoring['rule_penalty']}. '
        'Raw score after limits: ${scoring['raw_score']}.',
      ),
      _AnalysisParagraph(
        '${scoring['display_method']}. These are scoring rules, not learned feature contributions.',
      ),
    ],
    const _AnalysisParagraph(
      'The score compares crop fit; it is not a harvest probability. Good match: 75–100; possible match: 50–<75; limited match: 25–<50; poor match: below 25. The existing thresholds are unchanged.',
    ),
    if ('${crop['crop']}'.toLowerCase() ==
        '${record['predicted_crop']}'.toLowerCase()) ...[
      if (record['analysis_summary'] != null) ...[
        const Divider(),
        const _AnalysisParagraph('Original saved analysis summary'),
        _AnalysisParagraph('${record['analysis_summary']}'),
      ],
      if (condition.isEmpty &&
          analysisMapValue(record['xai_explanation']).isNotEmpty) ...[
        const _AnalysisParagraph(
          'Original saved condition notes. Older records may not identify which crop these notes describe; they are not model feature contributions.',
        ),
        for (final text in [
          analysisMapValue(record['xai_explanation'])['plain_summary'],
          analysisMapValue(record['xai_explanation'])['summary'],
          ...analysisListValue(
            analysisMapValue(record['xai_explanation'])['supporting_factors'],
          ),
          ...analysisListValue(
            analysisMapValue(record['xai_explanation'])['limiting_factors'],
          ),
        ].where((text) => text != null && '$text'.trim().isNotEmpty).toSet())
          _AnalysisParagraph('$text'),
      ],
    ],
  ]);
}

/// Refuse unbound or mismatched explanations instead of borrowing the current model.
Map<String, dynamic> verifiedModelExplanation(Map<String, dynamic> record) {
  final explanation = analysisMapValue(record['model_explanation']);
  if (explanation['schema_version'] != 1 ||
      explanation['scope'] != 'global' ||
      explanation['method'] != 'random_forest_mean_decrease_in_impurity' ||
      record['prediction_context_id'] == null ||
      record['model_version'] == null ||
      explanation['prediction_context_id'] != record['prediction_context_id'] ||
      explanation['model_version'] != record['model_version'] ||
      explanation['selected_output'] != record['predicted_crop'] ||
      analysisNumber(explanation['selected_score']) !=
          analysisNumber(
            record['crop_compatibility_pct'] ?? record['compatibility_pct'],
          )) {
    return {};
  }
  final samples = analysisListValue(explanation['samples']);
  if (samples.isEmpty ||
      samples.any(
        (s) => s is! Map || s['model_version'] != explanation['model_version'],
      )) {
    return {};
  }
  return explanation;
}

class ModelExplanationCard extends StatelessWidget {
  final Map<String, dynamic> record;
  const ModelExplanationCard({super.key, required this.record});
  @override
  Widget build(BuildContext context) {
    final explanation = verifiedModelExplanation(record);
    final features =
        analysisListValue(explanation['features'])
            .whereType<Map>()
            .where((f) {
              final n = analysisNumber(f['importance']);
              return n != null && n >= 0 && n <= 1;
            })
            .map((f) => Map<String, dynamic>.from(f))
            .toList()
          ..sort(
            (a, b) => analysisNumber(
              b['importance'],
            )!.compareTo(analysisNumber(a['importance'])!),
          );
    final available =
        explanation['status'] == 'available' &&
        features.isNotEmpty &&
        features.length == analysisListValue(explanation['features']).length;
    final sampleNames = analysisListValue(
      explanation['samples'],
    ).whereType<Map>().map((s) => '${s['raw_prediction']}').toSet().join(', ');
    return _AnalysisSection(
      title: 'Why the model recommended this crop',
      surface: const Color(0xFFEAF3FA),
      icon: Icons.insights_outlined,
      children: [
        Text(
          'Selected recommendation: ${record['predicted_crop'] ?? 'Unavailable'}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'A farm-specific explanation is not supported by the existing model. It cannot tell us which factors raised or lowered this crop’s prediction.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Overall model factors',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: Color(0xFF234F6E),
          ),
        ),
        const SizedBox(height: 8),
        if (available) ...[
          Text(
            '${features.take(2).map((f) => f['label'] ?? f['feature']).join(' and ')} have the largest importance across the trained forest. These values apply to the whole model, not this farm or one crop.',
          ),
          const SizedBox(height: 10),
          for (final feature in features.take(5))
            _ModelImportanceBar(feature: feature),
          const SizedBox(height: 8),
          const Text(
            'Share of overall feature importance. No positive or negative direction.',
            style: TextStyle(fontSize: 16),
          ),
        ] else
          Text(
            explanation.isEmpty
                ? 'A matching model-importance snapshot was not saved with this analysis. Run a new farm analysis to record it. Historical inputs are not replaced.'
                : '${explanation['reason'] ?? 'Model importance could not be generated for this analysis.'} Run a new analysis to retry.',
          ),
        const SizedBox(height: 8),
        if (sampleNames.isNotEmpty)
          Text(
            'Recorded model output${sampleNames.contains(',') ? 's' : ''}: $sampleNames. Crop mapping, condition scoring and seasonal rules determine the final recommendation.',
          ),
        if (explanation.isNotEmpty)
          TextButton.icon(
            onPressed: () => _showModelDetails(context, explanation, features),
            icon: const Icon(Icons.bar_chart),
            label: const Text('View detailed explanation'),
          ),
      ],
    );
  }
}

class _ModelImportanceBar extends StatelessWidget {
  final Map<String, dynamic> feature;
  const _ModelImportanceBar({required this.feature});
  @override
  Widget build(BuildContext context) {
    final value = analysisNumber(feature['importance'])!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${feature['label'] ?? feature['feature']} · ${(value * 100).toStringAsFixed(2)}%',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Semantics(
            label:
                '${feature['label']}: ${(value * 100).toStringAsFixed(2)} percent overall model importance',
            child: ExcludeSemantics(
              child: LinearProgressIndicator(
                value: value,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
                color: const Color(0xFF39769A),
                backgroundColor: const Color(0xFFD2E3EE),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _showModelDetails(
  BuildContext context,
  Map<String, dynamic> explanation,
  List<Map<String, dynamic>> features,
) {
  _analysisDetails(context, 'Overall model factors', [
    _AnalysisParagraph(
      'Method: ${explanation['method_label']}. The values are normalized decreases in Gini impurity from training, not farm-specific effects. They can favor features with many distinct values.',
    ),
    _AnalysisParagraph(
      'Model version (SHA-256): ${explanation['model_version']}',
    ),
    _AnalysisParagraph(
      'Analysis context: ${explanation['prediction_context_id']}',
    ),
    for (final feature in features) ...[
      _ModelImportanceBar(feature: feature),
      _AnalysisParagraph('Exact importance: ${feature['importance']}'),
    ],
    if (explanation['aggregation'] != null)
      _AnalysisParagraph('${explanation['aggregation']}'),
    const _AnalysisParagraph('Inputs recorded at prediction time'),
    for (final (index, raw) in analysisListValue(
      explanation['samples'],
    ).indexed)
      if (raw is Map) ...[
        _AnalysisParagraph(
          'Sample ${index + 1} — model output: ${raw['raw_prediction']}',
        ),
        for (final input in analysisMapValue(raw['inputs']).entries)
          _AnalysisParagraph(
            '${features.where((f) => f['feature'] == input.key).firstOrNull?['label'] ?? input.key}: '
            '${input.value} ${features.where((f) => f['feature'] == input.key).firstOrNull?['unit'] ?? ''}',
          ),
        if (raw['data_quality'] != null)
          for (final quality in analysisMapValue(raw['data_quality']).entries)
            _AnalysisParagraph(
              '${quality.key}: ${analysisMapValue(quality.value)['quality'] ?? 'quality unavailable'}; '
              '${analysisMapValue(quality.value)['source'] ?? 'source unavailable'}',
            ),
        const Divider(),
      ],
    const _AnalysisParagraph(
      'Plant cover (NDVI) is a vegetation index, not a direct soil fertility measurement. Nutrient units are unspecified in the existing model contract.',
    ),
  ]);
}
