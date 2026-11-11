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
    final requested = widget.initialCrop ?? '${record['predicted_crop']}';
    final name = names.contains(requested) ? requested : names.first;
    final rank = names.indexOf(name) + 1;
    return _AnalysisSection(
      title: 'Explainable AI',
      icon: Icons.psychology_outlined,
      surface: const Color(0xFFEAF3FA),
      children: [
        Text(
          widget.initialCrop == null ? 'Top crop: $name' : 'Crop $rank: $name',
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
  final names = localRows(
    body['crop_classes'],
  ).map((row) => '${row['crop']}').toList();
  final rank = names.indexOf(crop) + 1;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: geoPanelColor(context, Colors.white),
    builder: (sheetContext) => SafeArea(
      child: FractionallySizedBox(
        heightFactor: .78,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: green),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Explainable AI details',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close, size: 17),
                  label: const Text('Close'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEAF7EE), Color(0xFFBBEEC6)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  CropArtwork(crop, size: 55),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        crop,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Ranked #${rank > 0 ? rank : 1}',
                        style: const TextStyle(
                          color: green,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Why this crop?',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              '$crop received its saved AI ranking from this farm’s recorded conditions.',
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: geoPanelColor(sheetContext, const Color(0xFFF4FAF5)),
                border: Border.all(color: const Color(0xFFCDE8D5)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.layers_outlined, color: green),
                      SizedBox(width: 8),
                      Text(
                        'Key reasons',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _explanationReason(
                    Icons.bar_chart,
                    'Saved AI score',
                    'The model compared this crop with the other enabled crops.',
                  ),
                  const Divider(),
                  _explanationReason(
                    Icons.eco_outlined,
                    'Farm conditions',
                    conciseCropFit(record, crop),
                  ),
                  const Divider(),
                  _explanationReason(
                    Icons.grass_outlined,
                    'Pre-planting checks',
                    'Verify soil and nutrient estimates before planting.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFE9F4EF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: green),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'The score compares crops; it is not a harvest prediction.',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _explanationReason(IconData icon, String title, String detail) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    CircleAvatar(
      backgroundColor: const Color(0xFFE3F5E9),
      child: Icon(icon, color: green),
    ),
    const SizedBox(width: 12),
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(detail),
        ],
      ),
    ),
  ],
);
