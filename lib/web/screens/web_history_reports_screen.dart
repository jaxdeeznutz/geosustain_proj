part of geosustain_mobile;

class WebHistoryScreen extends StatelessWidget {
  final AnalysisState state;
  final bool compact;
  const WebHistoryScreen({super.key, required this.state, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final rows = state.historyRecords.take(compact ? 5 : 20).toList();
    return _WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Expanded(child: Text('Recent Analyses', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))), if (compact) const Text('View All', style: TextStyle(color: green, fontWeight: FontWeight.w900))]),
      const SizedBox(height: 16),
      if (rows.isEmpty) const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('No analysis history yet.', style: TextStyle(color: Colors.black45))))
      else Table(columnWidths: const {0: FlexColumnWidth(2.2), 1: FlexColumnWidth(1.6), 2: FlexColumnWidth(1.4), 3: FlexColumnWidth(1.0)}, children: [
        const TableRow(children: [_TableHead('Location'), _TableHead('Coordinates'), _TableHead('Recommended Crop'), _TableHead('Suitability')]),
        ...rows.map((r) => TableRow(children: [
          _TableCell('${r['place_name'] ?? r['location'] ?? 'Analyzed Area'}'),
          _TableCell('${r['lat'] ?? r['center_lat'] ?? '--'}, ${r['lon'] ?? r['center_lon'] ?? '--'}'),
          _TableCell('${r['crop_recommendation'] ?? r['recommended_crop'] ?? r['crop'] ?? '--'}'),
          _TableCell('${r['crop_compatibility_pct'] ?? r['compatibility_pct'] ?? '--'}%'),
        ])),
      ]),
    ]));
  }
}

class WebReportsScreen extends StatelessWidget {
  final AnalysisState state;
  final bool compact;
  const WebReportsScreen({super.key, required this.state, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final rows = state.generatedReports.take(compact ? 4 : 15).toList();
    return _WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Expanded(child: Text('Recent Reports', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))), if (compact) const Text('View All', style: TextStyle(color: green, fontWeight: FontWeight.w900))]),
      const SizedBox(height: 16),
      if (rows.isEmpty) const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('No reports generated yet.', style: TextStyle(color: Colors.black45))))
      else ...rows.map((r) => ListTile(leading: const CircleAvatar(backgroundColor: Color(0xFFFFEBEB), child: Icon(Icons.picture_as_pdf_rounded, color: Colors.red)), title: Text('${r['title'] ?? 'GeoSustain Analysis Report'}', style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${r['created_at'] ?? r['date'] ?? 'Recently generated'}'), trailing: const Icon(Icons.download_rounded, color: green))),
    ]));
  }
}

class _TableHead extends StatelessWidget {
  final String text;
  const _TableHead(this.text);
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black54)));
}

class _TableCell extends StatelessWidget {
  final String text;
  const _TableCell(this.text);
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 11), child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)));
}
