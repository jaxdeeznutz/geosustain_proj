part of '../main.dart';

class SavedReferenceVersions extends StatelessWidget {
  final Map<String, dynamic> record;
  const SavedReferenceVersions({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final snapshot = analysisMapValue(record['configuration_snapshot']);
    final identity =
        '${record['session_id'] ?? record['id'] ?? 'unsaved'}-'
        '${record['prediction_context_id'] ?? ''}-${snapshot['content_sha256'] ?? ''}';
    return ExpansionTile(
      // The surrounding scroll view stores a double. Expansion state must
      // have its own bool slot, scoped to this saved analysis/configuration.
      key: PageStorageKey<String>('controlled-reference-details-$identity'),
      title: const Text('Saved reference versions'),
      children: [
        // SelectionArea preserves copying without SelectableText's internal
        // scrollable trying to restore the ancestor tile's bool state.
        SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final line in controlledReferenceLines(record))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Text(line),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
