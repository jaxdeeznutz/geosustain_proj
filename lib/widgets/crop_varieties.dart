part of '../main.dart';

Map<String, dynamic>? _bananaVarietyReference;

Future<Map<String, dynamic>> loadBananaVarietyReference() async =>
    _bananaVarietyReference ??= analysisMapValue(
      jsonDecode(
        await rootBundle.loadString('assets/data/banana_varieties.json'),
      ),
    );

/// General reference information, independent of a saved analysis and its score.
class CropVarietyReference extends StatefulWidget {
  final String crop;
  final bool initiallyExpanded;
  const CropVarietyReference({
    super.key,
    required this.crop,
    this.initiallyExpanded = false,
  });
  @override
  State<CropVarietyReference> createState() => _CropVarietyReferenceState();
}

class _CropVarietyReferenceState extends State<CropVarietyReference> {
  late final reference = loadBananaVarietyReference();
  @override
  Widget build(BuildContext context) {
    if (widget.crop.trim().toLowerCase() != 'banana') {
      return const SizedBox.shrink();
    }
    return FutureBuilder<Map<String, dynamic>>(
      future: reference,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              snapshot.hasError
                  ? 'Banana variety reference is unavailable.'
                  : 'Loading banana variety reference…',
            ),
          );
        }
        final data = snapshot.data!;
        final profiles = analysisListValue(
          data['profiles'],
        ).map(analysisMapValue).toList();
        final colors = Theme.of(context).colorScheme;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(14),
            color: colors.surface,
          ),
          child: ExpansionTile(
            key: const ValueKey('banana-variety-reference'),
            initiallyExpanded: widget.initiallyExpanded,
            shape: const Border(),
            collapsedShape: const Border(),
            title: const Text(
              'Banana varieties',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              profiles.map((p) => '${p['label']}').join(' · '),
              style: const TextStyle(fontSize: 12),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final profile in profiles)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${profile['label']}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${profile['description']}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      for (final line in analysisListValue(
                        profile['guidance_lines'],
                      ))
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '$line',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const Divider(),
              Text('${data['note']}', style: const TextStyle(fontSize: 12)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.menu_book_outlined, size: 17),
                  label: const Text('Variety sources'),
                  onPressed: () {
                    final sources = <String, Map<String, dynamic>>{};
                    for (final profile in profiles) {
                      for (final value in analysisListValue(
                        profile['sources'],
                      )) {
                        final source = analysisMapValue(value);
                        sources['${source['url']}'] = source;
                      }
                    }
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Banana variety sources'),
                        content: SizedBox(
                          width: 520,
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${data['local_scope_note']}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                if (data['guidance_scope_note'] != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '${data['guidance_scope_note']}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                for (final source in sources.values)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${source['title']}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        SelectableText('${source['url']}'),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
