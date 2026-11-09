part of '../../main.dart';

class _ControlledExcelDialog extends StatefulWidget {
  final ApiService api;
  final ExcelUpload file;
  const _ControlledExcelDialog({required this.api, required this.file});
  @override
  State<_ControlledExcelDialog> createState() => _ControlledExcelDialogState();
}

class _ControlledExcelDialogState extends State<_ControlledExcelDialog> {
  bool loading = true, saving = false, reviewed = false;
  String? error;
  Map<String, dynamic>? preview;
  List<Map<String, dynamic>> get rows =>
      analysisListValue(preview?['rows']).map(analysisMapValue).toList();
  bool get ready =>
      !loading &&
      !saving &&
      preview?['upload_id'] != null &&
      rows.isNotEmpty &&
      rows.every((row) => analysisListValue(row['errors']).isEmpty);
  bool get validToday {
    final now = DateTime.now(), today = DateTime(now.year, now.month, now.day);
    return rows.every((row) {
      final from = DateTime.tryParse('${row['valid_from']}'),
          until = DateTime.tryParse('${row['valid_until']}');
      return from != null &&
          until != null &&
          !from.isAfter(today) &&
          !until.isBefore(today);
    });
  }

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    setState(() {
      loading = true;
      reviewed = false;
      error = null;
      preview = null;
    });
    try {
      final value = await widget.api.controlledRecordsRequest(
        '/excel/preview',
        body: {
          'filename': widget.file.name,
          'content_base64': base64Encode(widget.file.bytes),
        },
      );
      if (value['upload_id'] is! String ||
          value['rows'] is! List ||
          value['valid_rows'] is! num ||
          value['total_rows'] is! num) {
        throw const FormatException(
          'The Excel preview could not be read. Try again.',
        );
      }
      if (mounted) setState(() => preview = value);
    } catch (failure) {
      if (mounted) setState(() => error = friendlyErrorMessage(failure));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _apply(bool activate) async {
    if (!ready || (activate && (!reviewed || !validToday))) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await widget.api.controlledRecordsRequest(
        '/excel/apply',
        body: {
          'upload_id': preview!['upload_id'],
          'expected': rows
              .map((row) => analysisMapValue(row['expected']))
              .toList(),
          'activate': activate,
          'review_note': activate
              ? 'Reviewed the imported ranges and source from ${widget.file.name}.'
              : '',
        },
      );
      if (mounted) Navigator.pop(context, result);
    } catch (failure) {
      if (mounted) setState(() => error = friendlyErrorMessage(failure));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: _AdminDialog(
      title: 'Import crop requirements',
      subtitle:
          'The system reads your Excel rows. Check the preview before applying them.',
      icon: Icons.upload_file,
      width: 1000,
      busy: saving,
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          onPressed: ready ? () => _apply(false) : null,
          child: const Text('Save drafts'),
        ),
        FilledButton(
          onPressed: ready && reviewed && validToday
              ? () => _apply(true)
              : null,
          child: const Text('Save and activate'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.file.name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Updates growing-condition checks for the existing crops. AI training and saved analyses stay unchanged.',
          ),
          if (loading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const Text('Reading Excel and checking rows…'),
          ],
          if (error != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: saving || loading ? null : _read,
                child: const Text('Read file again'),
              ),
            ),
          ],
          if (preview != null) ...[
            const SizedBox(height: 16),
            Text(
              '${preview!['valid_rows']} of ${preview!['total_rows']} rows ready',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            if (rows.any((row) => analysisListValue(row['errors']).isNotEmpty))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Fix the listed rows in Excel, then upload the corrected file. No changes have been saved.',
                ),
              ),
            const SizedBox(height: 12),
            for (final row in rows)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Row ${row['row']} · ${row['crop'] ?? 'Check crop'} · ${row['factor'] ?? 'Check factor'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (row['payload'] != null) ...[
                      Text(
                        'Preferred: ${analysisMapValue(row['payload'])['preferred_min']} to ${analysisMapValue(row['payload'])['preferred_max']} ${analysisMapValue(row['payload'])['unit']}',
                      ),
                      Text(
                        'Outer limits: ${analysisMapValue(row['payload'])['absolute_min']} to ${analysisMapValue(row['payload'])['absolute_max']} ${analysisMapValue(row['payload'])['unit']}',
                      ),
                      Text(
                        'Period: ${analysisMapValue(row['payload'])['period']}',
                      ),
                      Text('Source: ${row['source']}'),
                    ],
                    for (final problem in analysisListValue(row['errors']))
                      Text(
                        '$problem',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            if (ready && !validToday)
              const Text(
                'Some rows are outside their validity dates. Save drafts or correct the dates before activation.',
              ),
            CheckboxListTile(
              key: const ValueKey('excel-import-reviewed'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: reviewed,
              onChanged: ready
                  ? (value) => setState(() => reviewed = value == true)
                  : null,
              title: const Text(
                'I checked the imported ranges and their source.',
              ),
            ),
            const Text(
              'The uploaded Excel file is kept as the source. A website link is optional.',
            ),
          ],
          if (saving) const LinearProgressIndicator(),
        ],
      ),
    ),
  );
}
