part of geosustain_mobile;

class HistoryPage extends StatefulWidget {
  final ApiService api;
  final AnalysisState state;
  const HistoryPage({super.key, required this.api, required this.state});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  Future<void> refresh() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await widget.state.refreshHistoryData();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String labelFor(dynamic pct) => suitabilityLabel(pct);

  Color colorFor(String label) {
    if (label.startsWith('HIGH')) return const Color(0xFFDCF5E4);
    if (label.startsWith('MODERATE')) return const Color(0xFFFFE7B8);
    return const Color(0xFFFFD5D5);
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.state.historyRecords.map(widget.state.normalizeRecord).toList();
    return SafeArea(
      child: Column(children: [
        MobileHeader(
            title: 'Analysis History',
            trailing: IconButton(
                onPressed: loading ? null : refresh,
                icon: loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh))),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(error!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: loading
                      ? const CircularProgressIndicator()
                      : const Text('No analysis history yet.'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => HistoryDetailPage(record: r, state: widget.state)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            LocationHistoryThumb(
                              lat: r['center_lat'],
                              lon: r['center_lon'],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${r['title'] ?? r['place_name'] ?? 'Analyzed Area'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.state.recommendationText(r),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                                  ),
                                  const SizedBox(height: 7),
                                  Wrap(spacing: 6, runSpacing: 6, children: [
                                    SmallHistoryAction(
                                      icon: Icons.bookmark_border_rounded,
                                      label: 'Save',
                                      onTap: () async {
                                        final saved = await widget.state.saveAnalysisRecord(r);
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saved ? 'Analysis saved.' : 'Already saved.')));
                                      },
                                    ),
                                    SmallHistoryAction(
                                      icon: Icons.description_outlined,
                                      label: 'Report',
                                      onTap: () async {
                                        final added = await widget.state.createReportRecord(r);
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(added ? 'Report added.' : 'Report already exists.')));
                                      },
                                    ),
                                  ]),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class HistoryDetailPage extends StatelessWidget {
  final Map<String, dynamic> record;
  final AnalysisState state;
  const HistoryDetailPage({super.key, required this.record, required this.state});

  String _num(dynamic value, {int decimals = 2}) {
    final n = value is num ? value : num.tryParse('$value');
    if (n == null) return '--';
    return n.toStringAsFixed(decimals);
  }

  double _progress(dynamic value, double fallback) {
    final n = value is num ? value : num.tryParse('$value');
    return ((n ?? fallback).clamp(0, 100) / 100).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final item = state.normalizeRecord(Map<String, dynamic>.from(record));
    final crop = item['predicted_crop'] ?? 'Land Analysis';
    final compatibility = item['compatibility_pct'];
    final suitability = suitabilityLabel(compatibility);
    final lat = item['center_lat'];
    final lon = item['center_lon'];
    final place = item['title'] ?? item['place_name'] ?? 'Analyzed Area';

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            MobileHeader(
              title: 'Analysis Details',
              back: () => Navigator.pop(context),
              trailing: IconButton(onPressed: () => generateAnalysisPdf(item, state: state), icon: const Icon(Icons.download_outlined)),
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 170, width: double.infinity, child: LocationHistoryThumb(lat: lat, lon: lon, expanded: true)),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$place', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: green)),
                        const SizedBox(height: 6),
                        Text(state.recommendationText(item), style: const TextStyle(color: Colors.black54)),
                        const SizedBox(height: 6),
                        Text('$crop', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: suitabilityColor(compatibility), borderRadius: BorderRadius.circular(8)),
                          child: Text('$suitability', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                        ),
                        const Divider(height: 28),
                        DetailLine(label: 'Suitability Score', value: '${compatibility ?? '--'}%'),
                        DetailLine(label: 'NDVI', value: _num(item['ndvi'], decimals: 3)),
                        DetailLine(label: 'Rainfall', value: '${_num(item['rainfall_mm'], decimals: 1)} mm'),
                        DetailLine(label: 'Temperature', value: '${_num(item['temperature_c'], decimals: 1)} °C'),
                        DetailLine(label: 'Elevation', value: '${_num(item['elevation_m'], decimals: 1)} m'),
                        DetailLine(label: 'Soil pH', value: _num(item['soil_ph'], decimals: 2)),
                        DetailLine(label: 'Nitrogen', value: _num(item['nitrogen'], decimals: 0)),
                        DetailLine(label: 'Phosphorus', value: _num(item['phosphorus'], decimals: 0)),
                        DetailLine(label: 'Potassium', value: _num(item['potassium'], decimals: 0)),
                        DetailLine(label: 'Weather', value: '${item['weather_description'] ?? '--'}'),
                        const Divider(height: 24),
                        DetailLine(label: 'Infrastructure Suitability', value: '${item['infrastructure_suitability'] ?? '--'}'),
                        DetailLine(label: 'Infrastructure Score', value: '${item['infrastructure_score'] ?? '--'}'),
                        DetailLine(label: 'Infrastructure Status', value: '${item['infrastructure_status'] ?? '--'}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionTitle('CHARTS AND ANALYTICS'),
                  const SizedBox(height: 12),
                  DetailBar(label: 'NDVI', value: _progress((item['ndvi'] is num ? item['ndvi'] * 100 : 0), 45)),
                  DetailBar(label: 'Rainfall', value: _progress((item['rainfall_mm'] is num ? item['rainfall_mm'] / 2 : null), 70)),
                  DetailBar(label: 'Temp', value: _progress((item['temperature_c'] is num ? item['temperature_c'] * 2 : null), 50)),
                  DetailBar(label: 'Soil pH', value: _progress((item['soil_ph'] is num ? item['soil_ph'] * 12 : null), 60)),
                ]),
              ),
            ),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final saved = await state.saveAnalysisRecord(item);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saved ? 'Analysis saved.' : 'Already saved.')));
                  },
                  icon: const Icon(Icons.bookmark_border_rounded),
                  label: const Text('Save'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final added = await state.createReportRecord(item);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(added ? 'Report added.' : 'Report already exists.')));
                  },
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('Report'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => generateAnalysisPdf(item, state: state),
              icon: const Icon(Icons.download),
              label: const Text('Download PDF Report'),
            ),
          ],
        ),
      ),
    );
  }
}


class SmallHistoryAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const SmallHistoryAction({super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: softGreen, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: green),
          const SizedBox(width: 3),
          Text(label, style: const TextStyle(color: green, fontWeight: FontWeight.w800, fontSize: 10)),
        ]),
      ),
    );
  }
}

Future<void> generateAnalysisPdf(Map<String, dynamic> raw, {AnalysisState? state}) async {
  final data = Map<String, dynamic>.from(raw);
  final location = state != null
      ? await state.resolvePlaceForRecord(data)
      : (data['place_name'] ?? data['title'] ?? 'Unknown location').toString();
  data['place_name'] = location;
  final lat = data['center_lat'] ?? data['lat'] ?? '--';
  final lon = data['center_lon'] ?? data['lon'] ?? '--';
  final crop = data['predicted_crop'] ?? 'Land Analysis';
  final compatibility = data['compatibility_pct'] ?? data['crop_compatibility_pct'] ?? '--';
  final recommendation = state?.recommendationText(data) ??
      (data['recommendation_title'] ?? data['subtitle'] ?? 'Land suitability analysis');
  dynamic rawAlternatives = data['alternative_crops'];
  dynamic rawTop = data['top_crop_recommendations'];
  if (rawAlternatives is String && rawAlternatives.trim().isNotEmpty) {
    try { rawAlternatives = jsonDecode(rawAlternatives); } catch (_) {}
  }
  if (rawTop is String && rawTop.trim().isNotEmpty) {
    try { rawTop = jsonDecode(rawTop); } catch (_) {}
  }
  final List<dynamic> alternatives = rawAlternatives is List && rawAlternatives.isNotEmpty
      ? rawAlternatives
      : (rawTop is List && rawTop.length > 1 ? rawTop.skip(1).toList() : []);
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      build: (context) => pw.Padding(
        padding: const pw.EdgeInsets.all(24),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('GeoSustain Analysis Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            pw.Text('Location: $location'),
            pw.Text('Coordinates: $lat, $lon'),
            pw.Text('Recommendation: $recommendation'),
            pw.Text('Crop Recommendation: $crop'),
            pw.Text('Suitability Score: $compatibility%'),
            pw.Text('Suitability: ${suitabilityLabel(compatibility)}'),
            if (alternatives.isNotEmpty) ...[
              pw.SizedBox(height: 10),
              pw.Text('Other Suitable Crops:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Table.fromTextArray(
                headers: ['Rank', 'Crop', 'Suitability'],
                data: alternatives.take(5).toList().asMap().entries.map((entry) {
                  final item = entry.value;
                  final altCrop = item is Map ? (item['crop'] ?? item['name'] ?? '--') : '$item';
                  final altPct = item is Map ? (item['compatibility_pct'] ?? item['score'] ?? item['compatibility'] ?? '--') : '--';
                  return ['${entry.key + 2}', '$altCrop', '$altPct%'];
                }).toList(),
              ),
            ],
            pw.SizedBox(height: 8),
            pw.Text('Infrastructure Suitability: ${data['infrastructure_suitability'] ?? '--'}'),
            pw.Text('Infrastructure Score: ${data['infrastructure_score'] ?? '--'}'),
            pw.Text('Infrastructure Note: ${data['infrastructure_status'] ?? '--'}'),
            pw.Divider(),
            pw.Text('NDVI: ${data['ndvi'] ?? '--'}'),
            pw.Text('Rainfall: ${data['rainfall_mm'] ?? '--'} mm'),
            pw.Text('Temperature: ${data['temperature_c'] ?? '--'} °C'),
            pw.Text('Elevation: ${data['elevation_m'] ?? '--'} m'),
            pw.Text('Soil pH: ${data['soil_ph'] ?? '--'}'),
            pw.Text('Nitrogen: ${data['nitrogen'] ?? '--'}'),
            pw.Text('Phosphorus: ${data['phosphorus'] ?? '--'}'),
            pw.Text('Potassium: ${data['potassium'] ?? '--'}'),
            pw.SizedBox(height: 16),
            pw.Text('Generated by GeoSustain mobile/web application.'),
          ],
        ),
      ),
    ),
  );
  await Printing.sharePdf(bytes: await doc.save(), filename: 'geosustain_analysis_report.pdf');
}

class DetailLine extends StatelessWidget {
  final String label;
  final String value;
  const DetailLine({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
            child: Text(
              label,
              style: const TextStyle(color: Colors.black54),
              softWrap: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              softWrap: true,
              overflow: TextOverflow.visible,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class DetailBar extends StatelessWidget {
  final String label;
  final double value;
  const DetailBar({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        SizedBox(width: 70, child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: value, minHeight: 12, backgroundColor: const Color(0xFFE9EEE9), color: green))),
        const SizedBox(width: 8),
        Text('${(value * 100).toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
      ]),
    );
  }
}

