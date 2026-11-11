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
    final requested = '${record['predicted_crop']}';
    final name = names.contains(requested) ? requested : names.first;
    return _AnalysisSection(
      title: 'Explainable AI',
      icon: Icons.psychology_outlined,
      surface: const Color(0xFFEAF3FA),
      children: [
        Text(
          'Top crop: $name',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(conciseCropFit(record, name)),
        TextButton(
          onPressed: () =>
              _showLocalExplanationDetails(context, record, body, name),
          child: const Text('AI calculation details'),
        ),
      ],
    );
  }
}

void _showLocalExplanationDetails(
  BuildContext context,
  Map<String, dynamic> record,
  Map<String, dynamic> body,
  String crop,
) {
  _analysisDetails(context, 'Explainable AI details - $crop', [
    _AnalysisParagraph(
      '$crop ranked first because the saved AI model gave it the highest score for this farm’s recorded conditions. The score compares crops; it is not a harvest prediction. Soil and nutrient estimates should be checked before planting.',
    ),
  ]);
}
