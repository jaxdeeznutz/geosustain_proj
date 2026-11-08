part of '../main.dart';

class LocalExplanationCard extends StatefulWidget {
  final Map<String, dynamic> record;
  final String? initialCrop;
  final bool showCropPicker;
  const LocalExplanationCard({
    super.key,
    required this.record,
    this.initialCrop,
    this.showCropPicker = true,
  });
  @override
  State<LocalExplanationCard> createState() => _LocalExplanationCardState();
}

class _LocalExplanationCardState extends State<LocalExplanationCard> {
  String? selected;
  @override
  void didUpdateWidget(LocalExplanationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record['prediction_context_id'] !=
            widget.record['prediction_context_id'] ||
        oldWidget.initialCrop != widget.initialCrop) {
      selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    String? issue;
    final body = verifiedLocalExplanation(
      record,
      onRejected: (code) => issue = code,
    );
    if (body.isEmpty) {
      final raw = localObject(record['local_model_explanation']);
      return _AnalysisSection(
        title: 'Explainable AI',
        icon: Icons.psychology_outlined,
        surface: const Color(0xFFEAF3FA),
        children: [
          Text(
            issue == 'not_saved'
                ? 'An explanation was not saved with this result. Scores are unchanged.'
                : issue == 'server_unavailable'
                ? 'The explanation could not be generated. Scores are unchanged.'
                : 'The saved explanation could not be verified. Scores are unchanged.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Explanation details'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'No model factors are shown until the saved explanation matches the result.',
                        ),
                        if (raw['status'] == 'unavailable' &&
                            raw['reason'] != null) ...[
                          const SizedBox(height: 12),
                          Text('${raw['reason']}'),
                        ],
                        const SizedBox(height: 12),
                        SelectableText('Check: ${issue ?? 'invalid_snapshot'}'),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text: const JsonEncoder.withIndent(
                              '  ',
                            ).convert(localExplanationDiagnostics(record)),
                          ),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Check details copied.'),
                            ),
                          );
                        }
                      },
                      child: const Text('Copy check details'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
              child: const Text('Explanation details'),
            ),
          ),
        ],
      );
    }
    final bindings = localRows(body['crop_classes']);
    final names = bindings.map((v) => '${v['crop']}').toList();
    final requested =
        selected ?? widget.initialCrop ?? '${record['predicted_crop']}';
    final name = names.contains(requested) ? requested : names.first;
    final summary = recommendationSummary(record, name);
    final referenceFactors = localRows(summary['reference_factors']);
    final assessed = referenceFactors
        .where((factor) => factor['status'] != 'not_assessed')
        .toList();
    Widget summaryPanel(List<Widget> children) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
    final modelWidgets = <Widget>[
      Text(
        'How the model used the farm conditions',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      Text('${summary['model_summary']}'),
      const SizedBox(height: 8),
      const Text(
        'These factors explain the model score; they do not establish crop suitability.',
      ),
    ];
    final referenceWidgets = <Widget>[
      Text(
        'Growing conditions for $name',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      if (assessed.isEmpty)
        const Text('No compatible cited condition check was saved.')
      else ...[
        for (final group in [
          ('fits', 'Fits reference ranges'),
          ('limited', 'Partial fit'),
          ('outside', 'Outside reference ranges'),
        ])
          if (assessed.any((factor) => factor['status'] == group.$1))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${group.$2}: ${assessed.where((factor) => factor['status'] == group.$1).map((factor) => factor['label']).join(', ')}.',
              ),
            ),
      ],
      if (referenceFactors.length > assessed.length)
        Text(
          '${referenceFactors.length - assessed.length} other conditions were not assessed.',
        ),
      Text('${summary['reference_note']}'),
      TextButton.icon(
        onPressed: () => _showReferenceFit(context, record, name),
        icon: const Icon(Icons.menu_book_outlined),
        label: const Text('View cited conditions'),
      ),
    ];
    return _AnalysisSection(
      title: 'Explainable AI',
      icon: Icons.psychology_outlined,
      surface: const Color(0xFFEAF3FA),
      children: [
        if (widget.showCropPicker)
          DropdownButtonFormField<String>(
            key: ValueKey('xai-crop-${body['prediction_context_id']}-$name'),
            initialValue: name,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Explain this crop'),
            items: [
              for (final value in names)
                DropdownMenuItem(value: value, child: Text(value)),
            ],
            onChanged: (value) => setState(() {
              selected = value;
            }),
          )
        else
          Text(
            'Explaining $name',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        const SizedBox(height: 10),
        Text('Based on ${body['sample_count']} saved farm samples.'),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final modelPanel = summaryPanel(modelWidgets);
            final referencePanel = summaryPanel(referenceWidgets);
            if (constraints.maxWidth >= 900 &&
                MediaQuery.textScalerOf(context).scale(14) <= 20) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: modelPanel),
                  const SizedBox(width: 16),
                  Expanded(child: referencePanel),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                modelPanel,
                const SizedBox(height: 12),
                referencePanel,
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'Model patterns do not prove crop success, causes or measured soil nutrients.',
          style: TextStyle(fontSize: 12),
        ),
        TextButton.icon(
          onPressed: () =>
              _showLocalExplanationDetails(context, record, body, name),
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('View local explanation details'),
        ),
      ],
    );
  }
}

void _showReferenceFit(
  BuildContext context,
  Map<String, dynamic> record,
  String crop,
) {
  final summary = recommendationSummary(record, crop);
  _analysisDetails(context, 'Research and reference fit - $crop', [
    _AnalysisParagraph('${summary['reference_note']}'),
    for (final factor in localRows(summary['reference_factors'])) ...[
      _AnalysisParagraph(
        '${factor['label']}: ${factor['status']}. ${factor['text']}',
      ),
      if (localObject(factor['source']).isNotEmpty)
        SelectionArea(
          child: Text(
            [
              for (final key in ['title', 'section', 'url', 'scope'])
                '${localObject(factor['source'])[key] ?? ''}',
            ].where((line) => line.isNotEmpty).join('\n'),
          ),
        ),
    ],
    _AnalysisParagraph('${summary['season']}'),
    _AnalysisParagraph('Saved sample context: ${summary['terrain']}'),
    _AnalysisParagraph('${summary['limit']}'),
  ]);
}

class _LocalContributionBar extends StatelessWidget {
  final Map<String, dynamic> feature;
  final double maximum;
  const _LocalContributionBar({required this.feature, required this.maximum});
  @override
  Widget build(BuildContext context) {
    final value = (feature['contribution_pp'] as num).toDouble();
    final fraction = maximum == 0
        ? 0.0
        : (value.abs() / maximum).clamp(0.0, 1.0).toDouble();
    Widget half(bool left) => Expanded(
      child: Align(
        alignment: left ? Alignment.centerRight : Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: (left ? value < 0 : value > 0) ? fraction : 0,
          child: Container(
            height: 8,
            color: left ? const Color(0xFF9A4D00) : const Color(0xFF176E8A),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Semantics(
        label:
            '${feature['label']}, ${localSigned(value)} percentage points relative to the model baseline',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 6,
              runSpacing: 4,
              children: [
                Text(
                  '${feature['label']}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text('${localSigned(value)} pp'),
              ],
            ),
            const SizedBox(height: 4),
            ExcludeSemantics(
              child: Row(
                children: [
                  half(true),
                  Container(width: 1, height: 13, color: Colors.blueGrey),
                  half(false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showLocalExplanationDetails(
  BuildContext context,
  Map<String, dynamic> record,
  Map<String, dynamic> body,
  String crop,
) {
  final view = localCropView(body, crop);
  final features = localRows(view['features']);
  final maximum = features
      .map((v) => (v['contribution_pp'] as num).abs().toDouble())
      .fold(0.0, math.max);
  _analysisDetails(context, 'Explainable AI details - $crop', [
    _AnalysisParagraph(
      '${recommendationSummary(record, crop)['model_summary']}',
    ),
    if (isAnnualPrototypeRecord(record))
      const _AnalysisParagraph(annualPrototypeShortNotice),
    _AnalysisParagraph(
      'Method: ${body['method_label']} (${body['method_version']}). Each tree contributes its root baseline and signed child-minus-parent changes along the actual prediction path.',
    ),
    _AnalysisParagraph(
      '${body['baseline_definition']}. ${body['aggregation']}',
    ),
    const _AnalysisParagraph(
      'Input summaries describe the original saved samples. The model was not run on these means.',
    ),
    for (final feature in features) ...[
      _LocalContributionBar(feature: feature, maximum: maximum),
      _AnalysisParagraph(
        'Saved input: mean ${(feature['mean'] as num).toStringAsFixed(3)}; range ${(feature['minimum'] as num).toStringAsFixed(3)} to ${(feature['maximum'] as num).toStringAsFixed(3)} ${feature['unit']}.',
      ),
    ],
    _AnalysisParagraph('Model SHA-256: ${body['model_version']}'),
    _AnalysisParagraph('Analysis context: ${body['prediction_context_id']}'),
    _AnalysisParagraph('Input snapshot hash: ${body['input_snapshot_hash']}'),
    _AnalysisParagraph('Attribution checksum: ${body['snapshot_hash']}'),
    const _AnalysisParagraph(
      'Base plus all signed feature contributions reconstructs the model class score within 0.0000001 percentage points. Display values are rounded.',
    ),
    for (final (index, sample) in localRows(
      localObject(record['model_explanation'])['samples'],
    ).indexed) ...[
      _AnalysisParagraph(
        'Sample ${index + 1}: local input checksum ${localObject(sample['local_attribution'])['input_hash']}',
      ),
      for (final entry in localObject(sample['inputs']).entries)
        _AnalysisParagraph('${entry.key}: ${entry.value}'),
    ],
    for (final limitation in body['limitations'] as List)
      _AnalysisParagraph('$limitation'),
  ]);
}
