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
  const ControlledRecordsPanel({super.key, required this.api});
  @override
  State<ControlledRecordsPanel> createState() => _ControlledRecordsPanelState();
}

class _ControlledRecordsPanelState extends State<ControlledRecordsPanel> {
  Map<String, dynamic> catalog = {};
  List<Map<String, dynamic>> rows = [];
  String? kind, error;
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
    try {
      final values = await Future.wait([
        widget.api.controlledRecordsRequest('/catalog'),
        widget.api.controlledRecordsRequest('', kind: kind, offset: offset),
      ]);
      if (!mounted || current != request) return;
      setState(() {
        catalog = values[0];
        rows = analysisListValue(
          values[1]['records'],
        ).map(analysisMapValue).toList();
        more = values[1]['has_more'] == true;
      });
    } catch (e) {
      if (mounted && current == request) {
        setState(() => error = friendlyErrorMessage(e));
      }
    } finally {
      if (mounted && current == request) setState(() => loading = false);
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

  Future<void> _activate(Map<String, dynamic> row, bool activate) async {
    final doc = analysisMapValue(row['document']);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${activate ? 'Activate' : 'Deactivate'} revision ${row['revision']}?',
        ),
        content: Text(
          '${doc['title']}\n${doc['reference']}\nValid: ${doc['valid_from']} to ${doc['valid_until']}\n\nThis affects new analyses only. Saved analyses keep their original records. ${row['kind'] == 'system_setting' ? 'Changing sample count can change new parcel model scores.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(activate ? 'Activate revision' : 'Deactivate revision'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.api.controlledRecordsRequest(
        '/activation',
        body: {
          'record_id': row['id'],
          'expected_generation': row['generation'] ?? 0,
          'activate': activate,
        },
      );
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (mounted) setState(() => error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _details(Map<String, dynamic> row) {
    final doc = analysisMapValue(row['document']);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${doc['title']} - revision ${row['revision']}'),
        content: SizedBox(
          width: 550,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final pair in {
                  'Category': _controlledKindLabels[row['kind']],
                  'Record key': row['record_key'],
                  'Review': doc['review_status'],
                  'Review note': doc['review_note'],
                  'Scope': doc['scope'],
                  'Evidence URL': doc['evidence_url'],
                  'Reference': doc['reference'],
                  'Method': doc['method'],
                  'Valid from': doc['valid_from'],
                  'Valid until': doc['valid_until'],
                  ...analysisMapValue(doc['payload']),
                  'Created by account': row['created_by'],
                  'Created': row['created_at'],
                  'Content checksum': row['content_sha256'],
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SelectableText('${pair.key}: ${pair.value}'),
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
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Controlled reference records',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Save a revision, review its evidence, then activate it for new analyses. Existing analyses keep their saved versions.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
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
              FilledButton.icon(
                onPressed: loading || busy || catalog.isEmpty
                    ? null
                    : () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('New record'),
              ),
              IconButton(
                onPressed: busy ? null : _load,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh records',
              ),
            ],
          ),
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
          if (!loading && rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'No controlled records saved yet. Built-in defaults remain in use.',
              ),
            ),
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
          const Divider(),
          Text(
            'Trusted model: ${analysisMapValue(catalog['installed_model'])['sha256'] ?? 'Unavailable'}',
          ),
          const Text(
            'Model records document the installed artifact. Uploading or deploying models is maintained by the project release process. NPK record entry is deferred.',
          ),
        ],
      ),
    ),
  );
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
      minLines: 1,
      maxLines: lines,
      decoration: InputDecoration(labelText: label),
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
    return AlertDialog(
      title: Text(
        widget.row == null ? 'New controlled record' : 'Create record revision',
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              select('Record type', kind, _controlledKindLabels, (v) {
                kind = v;
                if (crop == 'analysis' && kind != 'supporting_reference') {
                  crop = crops.first;
                }
              }, enabled: widget.row == null),
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
                    for (final c in crops) c: c,
                  },
                  (v) => crop = v,
                  enabled: widget.row == null,
                ),
              if (kind == 'crop_requirement') ...[
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
                Text(
                  'Unit: ${analysisMapValue(factors[factor])['unit']} | Period: ${analysisMapValue(factors[factor])['period']}',
                ),
                const SizedBox(height: 12),
                input('preferred_min', 'Preferred minimum'),
                input('preferred_max', 'Preferred maximum'),
                input('absolute_min', 'Absolute minimum'),
                input('absolute_max', 'Absolute maximum'),
              ],
              if (kind == 'planting_calendar')
                input('months', 'Planting months (1-12, separated by commas)'),
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
                  'This changes sampling for new analyses and can change their model scores. Historical results are preserved.',
                ),
              ],
              const SizedBox(height: 12),
              input('evidence_url', 'Public evidence URL (HTTPS)'),
              input('reference', 'Source section / reference'),
              input('method', 'Method and limitations', lines: 3),
              input('valid_from', 'Valid from (YYYY-MM-DD)'),
              input('valid_until', 'Valid until (YYYY-MM-DD)'),
              select('Review status', review, {
                'draft': 'Draft',
                'reviewed': 'Reviewed',
                'rejected': 'Rejected',
              }, (v) => review = v),
              input('review_note', 'Review note', lines: 3),
              const Text(
                'Scope: Panabo City. Unknown criteria stay absent. Do not enter credentials, nutrient datasets or model files.',
              ),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? 'Saving...' : 'Save revision'),
        ),
      ],
    );
  }
}
