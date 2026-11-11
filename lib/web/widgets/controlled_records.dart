part of '../../main.dart';

const _controlledKindLabels = {
  'crop_requirement': 'Crop requirements',
  'planting_calendar': 'Planting calendars',
  'environmental_source': 'Environmental sources',
  'model_version': 'Model version records',
  'supporting_reference': 'Supporting references',
  'system_setting': 'Analysis settings',
};

class ControlledRecordsPanel extends StatefulWidget {
  final ApiService api;
  final bool adminDesign;
  final Future<ExcelUpload?> Function()? excelPicker;
  final Future<void> Function(Uint8List, String)? excelSaver;
  const ControlledRecordsPanel({
    super.key,
    required this.api,
    this.adminDesign = false,
    this.excelPicker,
    this.excelSaver,
  });
  @override
  State<ControlledRecordsPanel> createState() => _ControlledRecordsPanelState();
}

class _ControlledRecordsPanelState extends State<ControlledRecordsPanel> {
  Map<String, dynamic> catalog = {};
  List<Map<String, dynamic>> rows = [];
  String? kind, error;
  String query = '';
  bool loading = true, busy = false, more = false;
  int offset = 0, request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final current = ++request;
    setState(() {
      loading = true;
      error = null;
    });
    final failures = <String>[];
    Future<void> loadPart(
      String label,
      Future<Map<String, dynamic>> future,
      void Function(Map<String, dynamic>) apply,
    ) async {
      try {
        final value = await future;
        if (mounted && current == request) setState(() => apply(value));
      } catch (e) {
        failures.add('$label: ${friendlyErrorMessage(e)}');
      }
    }

    await Future.wait([
      loadPart(
        'Reference catalog',
        widget.api.controlledRecordsRequest('/catalog'),
        (value) => catalog = value,
      ),
      loadPart(
        'Reference records',
        widget.api.controlledRecordsRequest('', kind: kind, offset: offset),
        (value) {
          rows = analysisListValue(
            value['records'],
          ).map(analysisMapValue).toList();
          more = value['has_more'] == true;
        },
      ),
    ]);
    if (mounted && current == request) {
      setState(() {
        error = failures.isEmpty ? null : failures.join('\n');
        loading = false;
      });
    }
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ControlledRecordEditor(
        catalog: catalog,
        row: row,
        onSave: (body) async {
          await widget.api.controlledRecordsRequest('', body: body);
        },
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Revision saved. Activate it separately after review.'),
        ),
      );
      await _load();
    }
  }

  Future<void> _excelDownload(String suffix, String name) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final bytes = await widget.api.getControlledExcelFile(suffix);
      await (widget.excelSaver ?? saveExcelFile)(bytes, name);
    } catch (failure) {
      if (mounted) setState(() => error = friendlyErrorMessage(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _importExcel() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final file = await (widget.excelPicker ?? pickExcelFile)();
      if (file == null || !mounted) return;
      if (file.bytes.length > 2 * 1024 * 1024 ||
          !file.name.toLowerCase().endsWith('.xlsx')) {
        throw const FormatException(
          'Choose an .xlsx file no larger than 2 MB.',
        );
      }
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _ControlledExcelDialog(api: widget.api, file: file),
      );
      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${result['imported']} reference rows ${result['activated'] == true ? 'saved and activated' : 'saved as drafts'}.',
            ),
          ),
        );
        await _load();
      }
    } catch (failure) {
      if (mounted) setState(() => error = friendlyErrorMessage(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _activate(Map<String, dynamic> row, bool activate) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ControlledActivationDialog(
        row: row,
        activate: activate,
        onConfirm: () async => widget.api.controlledRecordsRequest(
          '/activation',
          body: {
            'record_id': row['id'],
            'expected_generation': row['generation'] ?? 0,
            'activate': activate,
          },
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  void _details(Map<String, dynamic> row) {
    showDialog<void>(
      context: context,
      builder: (_) => _ControlledRecordDetailsDialog(
        row: row,
        history: rows
            .where(
              (item) =>
                  item['kind'] == row['kind'] &&
                  item['record_key'] == row['record_key'],
            )
            .toList(),
        onDownloadSource: (source) => _excelDownload(
          'files/${source['upload_id']}',
          '${source['filename']}',
        ),
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final doc = analysisMapValue(row['document']);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ControlledDialog(
        title: 'Delete revision ${row['revision']}?',
        subtitle: 'Remove this reference from the admin list.',
        icon: Icons.delete_outline,
        width: 600,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ControlledInfoRow(Icons.eco_outlined, 'Record', '${doc['title']}'),
            _ControlledInfoRow(
              Icons.layers_outlined,
              'Reference',
              '${row['record_key']}',
            ),
            const SizedBox(height: 14),
            const _ControlledNotice(
              'Existing analyses and audit history keep their saved evidence. An active reference will be deactivated.',
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB93535),
            ),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete revision'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.api.deleteControlledRecord(
        row['id'] as int,
        row['generation'] as int? ?? 0,
      );
      if (!mounted) return;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reference revision deleted.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _recordTable(List<Map<String, dynamic>> visible) => LayoutBuilder(
    builder: (context, bounds) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: bounds.maxWidth),
        child: DataTable(
          columnSpacing: 22,
          dataRowMinHeight: 68,
          dataRowMaxHeight: 76,
          columns: const [
            DataColumn(label: Text('Name / Description')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Version')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Updated')),
            DataColumn(label: Text('Actions')),
          ],
          rows: [
            for (final row in visible)
              DataRow(
                cells: [
                  DataCell(
                    SizedBox(
                      width: 260,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${analysisMapValue(row['document'])['title']}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${row['record_key']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${_controlledKindLabels[row['kind']] ?? row['kind']}',
                    ),
                  ),
                  DataCell(Text('v${row['revision']}')),
                  DataCell(
                    Chip(
                      label: Text(
                        row['active_record_id'] == row['id']
                            ? 'Active'
                            : 'Inactive',
                      ),
                      backgroundColor: row['active_record_id'] == row['id']
                          ? const Color(0xFFE1F6E8)
                          : const Color(0xFFFFF0D9),
                    ),
                  ),
                  DataCell(Text(analysisDateText(row['created_at']))),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'View revision',
                          onPressed: () => _details(row),
                          icon: const Icon(Icons.visibility_outlined),
                        ),
                        IconButton(
                          tooltip: 'Create revision',
                          onPressed: busy ? null : () => _edit(row),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: row['active_record_id'] == row['id']
                              ? 'Deactivate'
                              : 'Activate',
                          onPressed: busy
                              ? null
                              : () => _activate(
                                  row,
                                  row['active_record_id'] != row['id'],
                                ),
                          icon: Icon(
                            row['active_record_id'] == row['id']
                                ? Icons.pause_circle_outline
                                : Icons.check_circle_outline,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Delete revision',
                          onPressed: busy ? null : () => _delete(row),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Color(0xFFC43D3D),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.adminDesign)
            const _AnalystSectionTitle(
              'Controlled reference records',
              icon: Icons.storage_rounded,
            )
          else
            const Text(
              'Controlled reference records',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          const SizedBox(height: 6),
          const Text(
            'Import crop requirement ranges from Excel, preview the rows, then save or activate them. Existing analyses keep their saved values.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                key: const ValueKey('import-crop-excel'),
                onPressed: loading || busy ? null : _importExcel,
                icon: const Icon(Icons.upload_file),
                label: const Text('Import Excel'),
              ),
              OutlinedButton.icon(
                onPressed: loading || busy
                    ? null
                    : () => _excelDownload(
                        'template',
                        'GeoSustain_crop_requirements.xlsx',
                      ),
                icon: const Icon(Icons.download),
                label: const Text('Download template'),
              ),
              FilledButton.icon(
                onPressed: loading || busy || catalog.isEmpty
                    ? null
                    : () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('New record'),
              ),
              SizedBox(
                width: 270,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('controlled-filter-$kind'),
                  initialValue: kind ?? 'all',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Record category',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All record types'),
                    ),
                    for (final entry in _controlledKindLabels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: loading || busy
                      ? null
                      : (value) {
                          setState(() {
                            kind = value == 'all' ? null : value;
                            offset = 0;
                          });
                          _load();
                        },
                ),
              ),
              IconButton(
                onPressed: busy || loading ? null : _load,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh records',
              ),
            ],
          ),
          if (widget.adminDesign) ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('controlled-record-search'),
              onChanged: (value) => setState(() => query = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search reference records...',
              ),
            ),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(14),
              child: LinearProgressIndicator(),
            ),
          if (!loading && error == null && rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'No controlled records saved yet. Built-in defaults remain in use.',
              ),
            ),
          if (widget.adminDesign)
            _recordTable(
              rows
                  .where(
                    (row) =>
                        '${analysisMapValue(row['document'])['title']} ${row['record_key']} ${row['kind']}'
                            .toLowerCase()
                            .contains(query.toLowerCase()),
                  )
                  .toList(),
            )
          else
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFD7E3DA)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${analysisMapValue(row['document'])['title']}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${_controlledKindLabels[row['kind']]} | ${row['record_key']} | Revision ${row['revision']}',
                        ),
                        Text(
                          '${row['active_record_id'] == row['id'] ? 'Active' : 'Inactive'} | ${analysisMapValue(row['document'])['review_status']} | Valid until ${analysisMapValue(row['document'])['valid_until']}',
                        ),
                        Wrap(
                          spacing: 10,
                          children: [
                            TextButton(
                              onPressed: () => _details(row),
                              child: const Text('View revision'),
                            ),
                            TextButton(
                              onPressed: busy ? null : () => _edit(row),
                              child: const Text('Create revision'),
                            ),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => _activate(
                                      row,
                                      row['active_record_id'] != row['id'],
                                    ),
                              child: Text(
                                row['active_record_id'] == row['id']
                                    ? 'Deactivate'
                                    : 'Activate',
                              ),
                            ),
                            TextButton.icon(
                              onPressed: busy ? null : () => _delete(row),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Delete revision'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: offset == 0 || loading
                    ? null
                    : () {
                        offset -= 25;
                        _load();
                      },
                child: const Text('Previous records'),
              ),
              Text('Page ${offset ~/ 25 + 1}'),
              TextButton(
                onPressed: !more || loading
                    ? null
                    : () {
                        offset += 25;
                        _load();
                      },
                child: const Text('Next records'),
              ),
            ],
          ),
          if (!widget.adminDesign) ...[
            const Divider(),
            Text(
              'Trusted model: ${analysisMapValue(catalog['installed_model'])['sha256'] ?? (loading
                      ? 'Checking…'
                      : error != null
                      ? 'Could not retrieve status'
                      : 'Unavailable')}',
            ),
            const Text(
              'Model records document the installed artifact. Uploading or deploying models is maintained by the project release process. NPK record entry is deferred.',
            ),
          ],
        ],
      ),
    ),
  );
}

class _ControlledDialog extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Widget body;
  final List<Widget> actions;
  final double width;
  final bool busy;
  const _ControlledDialog({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.body,
    required this.actions,
    this.width = 790,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: width,
        maxHeight: MediaQuery.sizeOf(context).height - 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFFFFFF), Color(0xFFE8F9EA)],
                begin: Alignment.centerLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: 35,
                  bottom: -55,
                  child: Icon(
                    Icons.spa_rounded,
                    size: 170,
                    color: const Color(0xFF9DDFB0).withValues(alpha: .48),
                  ),
                ),
                Positioned(
                  right: -22,
                  bottom: -65,
                  child: Icon(
                    Icons.terrain_rounded,
                    size: 260,
                    color: const Color(0xFF9DDFB0).withValues(alpha: .36),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 14, 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F5E8),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          icon,
                          color: const Color(0xFF087D41),
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF192820),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                color: Color(0xFF59675E),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close dialog',
                        onPressed: busy ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: body,
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE3E9E4))),
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: Wrap(spacing: 10, runSpacing: 8, children: actions),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ControlledInfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _ControlledInfoRow(this.icon, this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: const Color(0xFF078245)),
        const SizedBox(width: 12),
        SizedBox(
          width: 116,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF4D5F55), fontSize: 12),
          ),
        ),
        Expanded(
          child: SelectableText(
            value.isEmpty ? '—' : value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _ControlledNotice extends StatelessWidget {
  final String text;
  const _ControlledNotice(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFEDF6F1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, color: Color(0xFF087D41)),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}

class _ControlledActivationDialog extends StatefulWidget {
  final Map<String, dynamic> row;
  final bool activate;
  final Future<Map<String, dynamic>> Function() onConfirm;
  const _ControlledActivationDialog({
    required this.row,
    required this.activate,
    required this.onConfirm,
  });
  @override
  State<_ControlledActivationDialog> createState() =>
      _ControlledActivationDialogState();
}

class _ControlledActivationDialogState
    extends State<_ControlledActivationDialog> {
  bool busy = false;
  String? error;
  Future<void> _confirm() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onConfirm();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = analysisMapValue(widget.row['document']);
    final action = widget.activate ? 'Activate' : 'Deactivate';
    return _ControlledDialog(
      title: '$action revision ${widget.row['revision']}?',
      subtitle:
          'Confirm ${action.toLowerCase()} of this reference revision. This affects new analyses only.',
      icon: Icons.layers_outlined,
      width: 650,
      busy: busy,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFBFDCC9)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                _ControlledInfoRow(
                  Icons.eco_outlined,
                  'Record',
                  '${doc['title']}',
                ),
                _ControlledInfoRow(
                  Icons.link,
                  'Reference',
                  '${doc['reference']}',
                ),
                _ControlledInfoRow(
                  Icons.calendar_today_outlined,
                  'Valid period',
                  '${doc['valid_from']} – ${doc['valid_until']}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _ControlledNotice(
            'This affects new analyses only. Saved analyses keep their original records.',
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                style: const TextStyle(color: Color(0xFFB93535)),
              ),
            ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: busy ? null : _confirm,
          icon: const Icon(Icons.check),
          label: Text('$action revision'),
        ),
      ],
    );
  }
}

class _ControlledRecordDetailsDialog extends StatefulWidget {
  final Map<String, dynamic> row;
  final List<Map<String, dynamic>> history;
  final Future<void> Function(Map<String, dynamic>) onDownloadSource;
  const _ControlledRecordDetailsDialog({
    required this.row,
    required this.history,
    required this.onDownloadSource,
  });
  @override
  State<_ControlledRecordDetailsDialog> createState() =>
      _ControlledRecordDetailsDialogState();
}

class _ControlledRecordDetailsDialogState
    extends State<_ControlledRecordDetailsDialog> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final row = widget.row, doc = analysisMapValue(row['document']);
    final payload = analysisMapValue(doc['payload']);
    final source = analysisMapValue(doc['source_file']);
    Widget panel(Widget child) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFDCE6DF)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
    Widget tabButton(int index, IconData icon, String label) => TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: tab == index
            ? const Color(0xFF087D41)
            : const Color(0xFF27352B),
        backgroundColor: tab == index ? const Color(0xFFE4F5E9) : null,
      ),
      onPressed: () => setState(() => tab = index),
      icon: Icon(icon, size: 19),
      label: Text(label),
    );
    return _ControlledDialog(
      title: '${doc['title']} – Revision ${row['revision']}',
      subtitle: 'Reference record details and review information',
      icon: Icons.description_outlined,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              tabButton(0, Icons.list, 'Overview'),
              tabButton(1, Icons.attach_file, 'Evidence & Files'),
              tabButton(2, Icons.history, 'History'),
            ],
          ),
          const Divider(height: 24),
          if (tab == 0) ...[
            _AdminFieldGrid(
              minimumWidth: 190,
              maximumColumns: 3,
              children: [
                panel(
                  _ControlledInfoRow(
                    Icons.track_changes,
                    'Category',
                    '${_controlledKindLabels[row['kind']] ?? row['kind']}',
                  ),
                ),
                panel(
                  _ControlledInfoRow(
                    Icons.layers_outlined,
                    'Record key',
                    '${row['record_key']}',
                  ),
                ),
                panel(
                  _ControlledInfoRow(
                    Icons.check_circle_outline,
                    'Review status',
                    '${doc['review_status']}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            panel(
              _AdminFieldGrid(
                minimumWidth: 285,
                children: [
                  Column(
                    children: [
                      _ControlledInfoRow(
                        Icons.assignment_outlined,
                        'Review draft',
                        '${doc['review_status']}',
                      ),
                      _ControlledInfoRow(
                        Icons.calendar_today_outlined,
                        'Valid from',
                        '${doc['valid_from']}',
                      ),
                      _ControlledInfoRow(
                        Icons.event_outlined,
                        'Valid until',
                        '${doc['valid_until']}',
                      ),
                      _ControlledInfoRow(
                        Icons.eco_outlined,
                        'Crop',
                        '${payload['crop'] ?? '—'}',
                      ),
                      _ControlledInfoRow(
                        Icons.straighten,
                        'Unit',
                        '${payload['unit'] ?? '—'}',
                      ),
                      _ControlledInfoRow(
                        Icons.bar_chart,
                        'Factor',
                        '${payload['factor'] ?? '—'}',
                      ),
                      _ControlledInfoRow(
                        Icons.timeline,
                        'Period',
                        '${payload['period'] ?? '—'}',
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      for (final key in [
                        'absolute_max',
                        'absolute_min',
                        'preferred_max',
                        'preferred_min',
                      ])
                        if (payload.containsKey(key))
                          _ControlledInfoRow(
                            Icons.tune,
                            key.replaceAll('_', ' '),
                            '${payload[key]}',
                          ),
                      _ControlledInfoRow(
                        Icons.person_outline,
                        'Created by',
                        'Account ${row['created_by'] ?? 'unknown'}',
                      ),
                      _ControlledInfoRow(
                        Icons.calendar_today_outlined,
                        'Created on',
                        analysisDateText(row['created_at']),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            panel(
              _ControlledInfoRow(
                Icons.notes_outlined,
                'Review note',
                '${doc['review_note'] ?? ''}',
              ),
            ),
            const SizedBox(height: 10),
            panel(
              _ControlledInfoRow(
                Icons.link,
                'Evidence URL',
                '${doc['evidence_url'] ?? ''}',
              ),
            ),
            if (source.isNotEmpty) ...[
              const SizedBox(height: 10),
              panel(
                Row(
                  children: [
                    const Icon(Icons.attach_file, color: Color(0xFF087D41)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Excel source\n${source['filename']}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Download source Excel',
                      onPressed: () => widget.onDownloadSource(source),
                      icon: const Icon(Icons.download),
                    ),
                  ],
                ),
              ),
            ],
          ] else if (tab == 1) ...[
            panel(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ControlledInfoRow(
                    Icons.link,
                    'Evidence URL',
                    '${doc['evidence_url'] ?? ''}',
                  ),
                  _ControlledInfoRow(
                    Icons.menu_book_outlined,
                    'Reference',
                    '${doc['reference'] ?? ''}',
                  ),
                  _ControlledInfoRow(
                    Icons.notes_outlined,
                    'Method',
                    '${doc['method'] ?? ''}',
                  ),
                  if (source.isNotEmpty) ...[
                    _ControlledInfoRow(
                      Icons.attach_file,
                      'Excel source',
                      '${source['filename']}',
                    ),
                    _ControlledInfoRow(
                      Icons.fingerprint,
                      'File SHA-256',
                      '${source['sha256']}',
                    ),
                    TextButton.icon(
                      onPressed: () => widget.onDownloadSource(source),
                      icon: const Icon(Icons.download),
                      label: const Text('Download source Excel'),
                    ),
                  ],
                  _ControlledInfoRow(
                    Icons.fingerprint,
                    'Record SHA-256',
                    '${row['content_sha256']}',
                  ),
                ],
              ),
            ),
          ] else ...[
            for (final item in widget.history)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: panel(
                  _ControlledInfoRow(
                    Icons.history,
                    'Revision ${item['revision']}',
                    '${analysisMapValue(item['document'])['review_status']} • ${analysisDateText(item['created_at'])}${item['active_record_id'] == item['id'] ? ' • Active' : ''}',
                  ),
                ),
              ),
          ],
        ],
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () => saveBrowserFile(
            Uint8List.fromList(
              utf8.encode(const JsonEncoder.withIndent('  ').convert(row)),
            ),
            '${row['record_key']}-revision-${row['revision']}.json',
            'application/json',
          ),
          icon: const Icon(Icons.download),
          label: const Text('Download record'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ControlledRecordEditor extends StatefulWidget {
  final Map<String, dynamic> catalog;
  final Map<String, dynamic>? row;
  final Future<void> Function(Map<String, dynamic>) onSave;
  const _ControlledRecordEditor({
    required this.catalog,
    this.row,
    required this.onSave,
  });
  @override
  State<_ControlledRecordEditor> createState() =>
      _ControlledRecordEditorState();
}

class _ControlledRecordEditorState extends State<_ControlledRecordEditor> {
  final controllers = <String, TextEditingController>{};
  late String kind, crop, factor, layer, review;
  String? error;
  bool saving = false;
  List<String> get crops =>
      analysisListValue(widget.catalog['crops']).cast<String>();
  @override
  void initState() {
    super.initState();
    final row = widget.row ?? {},
        doc = analysisMapValue(row['document']),
        payload = analysisMapValue(doc['payload']);
    kind = '${row['kind'] ?? 'crop_requirement'}';
    crop = '${payload['crop'] ?? payload['applies_to'] ?? crops.first}';
    factor = '${payload['factor'] ?? 'rainfall'}';
    layer = '${payload['layer'] ?? 'ndvi'}';
    review = '${doc['review_status'] ?? 'draft'}';
    final defaults = {
      'record_key': row['record_key'] ?? '',
      'title': doc['title'] ?? '',
      'evidence_url': doc['evidence_url'] ?? '',
      'reference': doc['reference'] ?? '',
      'method': doc['method'] ?? '',
      'review_note': doc['review_note'] ?? '',
      'valid_from':
          doc['valid_from'] ??
          DateTime.now().toIso8601String().substring(0, 10),
      'valid_until': doc['valid_until'] ?? '',
      'preferred_min': payload['preferred_min'] ?? '',
      'preferred_max': payload['preferred_max'] ?? '',
      'absolute_min': payload['absolute_min'] ?? '',
      'absolute_max': payload['absolute_max'] ?? '',
      'months': analysisListValue(payload['months']).join(', '),
      'sample_count': payload['sample_count'] ?? 9,
      'sha256':
          payload['sha256'] ??
          analysisMapValue(widget.catalog['installed_model'])['sha256'] ??
          '',
      'citation': payload['citation'] ?? '',
    };
    for (final entry in defaults.entries) {
      controllers[entry.key] = TextEditingController(text: '${entry.value}');
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String value(String key) => controllers[key]!.text.trim();
  Widget input(String key, String label, {int lines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controllers[key],
      minLines: lines,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: key.startsWith('valid_')
            ? IconButton(
                tooltip: 'Choose date',
                icon: const Icon(Icons.calendar_month_outlined),
                onPressed: saving
                    ? null
                    : () async {
                        final initial =
                            DateTime.tryParse(value(key)) ?? DateTime.now();
                        final date = await showDatePicker(
                          context: context,
                          initialDate:
                              initial.isBefore(DateTime(1900)) ||
                                  initial.isAfter(DateTime(2200))
                              ? DateTime.now()
                              : initial,
                          firstDate: DateTime(1900),
                          lastDate: DateTime(2200),
                        );
                        if (date != null && mounted) {
                          controllers[key]!.text = date
                              .toIso8601String()
                              .substring(0, 10);
                        }
                      },
              )
            : null,
      ),
    ),
  );
  Widget select(
    String label,
    String selected,
    Map<String, String> options,
    ValueChanged<String> changed, {
    bool enabled = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label-$selected'),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final e in options.entries)
          DropdownMenuItem(value: e.key, child: Text(e.value)),
      ],
      onChanged: enabled
          ? (v) {
              if (v != null) setState(() => changed(v));
            }
          : null,
    ),
  );

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final factors = analysisMapValue(widget.catalog['factors']),
          layers = analysisMapValue(widget.catalog['layers']);
      String key;
      Map<String, dynamic> payload;
      switch (kind) {
        case 'crop_requirement':
          final spec = analysisMapValue(factors[factor]);
          key = '${crop}_$factor';
          payload = {
            'crop': crop,
            'factor': factor,
            'unit': spec['unit'],
            'period': spec['period'],
            for (final k in [
              'preferred_min',
              'preferred_max',
              'absolute_min',
              'absolute_max',
            ])
              k: double.parse(value(k)),
          };
        case 'planting_calendar':
          key = crop;
          payload = {
            'crop': crop,
            'months': value(
              'months',
            ).split(',').map((v) => int.parse(v.trim())).toList(),
          };
        case 'environmental_source':
          key = layer;
          payload = {
            'layer': layer,
            for (final k in ['source_id', 'unit', 'period'])
              k: analysisMapValue(layers[layer])[k],
          };
        case 'model_version':
          key = 'installed_model';
          payload = {'sha256': value('sha256')};
        case 'supporting_reference':
          key = value('record_key');
          payload = {'applies_to': crop, 'citation': value('citation')};
        case 'system_setting':
          key = 'analysis_sampling';
          payload = {'sample_count': int.parse(value('sample_count'))};
        default:
          throw const FormatException('Unsupported record category.');
      }
      await widget.onSave(<String, dynamic>{
        if (analysisMapValue(widget.row?['document'])['source_file'] != null)
          'source_file': analysisMapValue(
            widget.row?['document'],
          )['source_file'],
        'kind': kind,
        'record_key': key,
        'expected_revision': widget.row?['revision'] ?? 0,
        'scope': 'Panabo City',
        'payload': payload,
        'review_status': review,
        for (final k in [
          'title',
          'evidence_url',
          'reference',
          'method',
          'valid_from',
          'valid_until',
          'review_note',
        ])
          k: value(k),
      });
      if (mounted) Navigator.pop(context, true);
    } on FormatException {
      if (mounted) {
        setState(
          () =>
              error = 'Check numeric values and comma-separated month numbers.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final factors = analysisMapValue(widget.catalog['factors']),
        layers = analysisMapValue(widget.catalog['layers']);
    return _AdminDialog(
      title: widget.row == null
          ? 'New controlled record'
          : 'Create record revision',
      subtitle:
          'Save a revision, review its evidence, then activate it for new analyses.',
      icon: Icons.layers_outlined,
      busy: saving,
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: saving ? null : save,
          icon: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(saving ? 'Saving...' : 'Save revision'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AdminDialogSection(
            title: 'Record details',
            icon: Icons.description_outlined,
            child: _AdminFieldGrid(
              children: [
                select(
                  'Record type',
                  kind,
                  _controlledKindLabels,
                  (v) {
                    kind = v;
                    if (crop == 'analysis' && kind != 'supporting_reference') {
                      crop = crops.first;
                    }
                  },
                  enabled: widget.row == null,
                ),
                input('title', 'Title'),
                if (kind == 'crop_requirement' ||
                    kind == 'planting_calendar' ||
                    kind == 'supporting_reference')
                  select(
                    'Crop / reference scope',
                    crop,
                    {
                      if (kind == 'supporting_reference')
                        'analysis': 'All analysis reports',
                      for (final c in crops)
                        c: c[0].toUpperCase() + c.substring(1),
                    },
                    (v) => crop = v,
                    enabled: widget.row == null,
                  ),
                if (kind == 'crop_requirement')
                  select(
                    'Environmental factor',
                    factor,
                    {
                      for (final e in factors.entries)
                        e.key: '${analysisMapValue(e.value)['label']}',
                    },
                    (v) => factor = v,
                    enabled: widget.row == null,
                  ),
              ],
            ),
          ),
          if (kind == 'crop_requirement')
            _AdminDialogSection(
              title: 'Measurement criteria',
              icon: Icons.bar_chart_rounded,
              description:
                  'Unit: ${analysisMapValue(factors[factor])['unit']} | Period: ${analysisMapValue(factors[factor])['period']}',
              child: _AdminFieldGrid(
                minimumWidth: 160,
                maximumColumns: 4,
                children: [
                  input('preferred_min', 'Preferred minimum'),
                  input('preferred_max', 'Preferred maximum'),
                  input('absolute_min', 'Absolute minimum'),
                  input('absolute_max', 'Absolute maximum'),
                ],
              ),
            ),
          if (kind != 'crop_requirement')
            _AdminDialogSection(
              title: 'Reference scope',
              icon: Icons.tune_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (kind == 'planting_calendar')
                    input(
                      'months',
                      'Planting months (1-12, separated by commas)',
                    ),
                  if (kind == 'environmental_source') ...[
                    select(
                      'Installed raster layer',
                      layer,
                      {
                        for (final e in layers.entries)
                          e.key: '${analysisMapValue(e.value)['label']}',
                      },
                      (v) => layer = v,
                      enabled: widget.row == null,
                    ),
                    Text(
                      'Source: ${analysisMapValue(layers[layer])['source_id']}\nUnit: ${analysisMapValue(layers[layer])['unit']} | Period: ${analysisMapValue(layers[layer])['period']}',
                    ),
                  ],
                  if (kind == 'model_version')
                    input('sha256', 'Model SHA-256 (metadata only)'),
                  if (kind == 'supporting_reference') ...[
                    if (widget.row == null)
                      input(
                        'record_key',
                        'Reference identifier (lowercase letters, numbers, underscores)',
                      ),
                    input('citation', 'Citation', lines: 3),
                  ],
                  if (kind == 'system_setting') ...[
                    input('sample_count', 'Maximum parcel samples (1, 5 or 9)'),
                    const Text(
                      'Sampling applies to new analyses. Historical results are preserved.',
                    ),
                  ],
                ],
              ),
            ),
          _AdminDialogSection(
            title: 'Reference & details',
            icon: Icons.menu_book_outlined,
            description: 'Add the source, method and validity dates.',
            child: _AdminFieldGrid(
              children: [
                input('evidence_url', 'Public evidence URL (HTTPS)'),
                input('reference', 'Source section / reference'),
                input('method', 'Method and limitations', lines: 3),
                Column(
                  children: [
                    input('valid_from', 'Valid from (YYYY-MM-DD)'),
                    input('valid_until', 'Valid until (YYYY-MM-DD)'),
                  ],
                ),
              ],
            ),
          ),
          _AdminDialogSection(
            title: 'Review',
            icon: Icons.fact_check_outlined,
            child: _AdminFieldGrid(
              children: [
                select('Review status', review, {
                  'draft': 'Draft',
                  'reviewed': 'Reviewed',
                  'rejected': 'Rejected',
                }, (v) => review = v),
                input('review_note', 'Review note', lines: 2),
              ],
            ),
          ),
          const Text(
            'Scope: Panabo City. Saving a revision does not activate it.',
            style: TextStyle(fontSize: 12),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
