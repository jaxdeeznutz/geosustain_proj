part of geosustain_mobile;

class WebDashboardScreen extends StatelessWidget {
  final AnalysisState state;
  final VoidCallback onStartAnalyze;
  final VoidCallback onOpenMapAnalysis;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenReports;

  const WebDashboardScreen({
    super.key,
    required this.state,
    required this.onStartAnalyze,
    required this.onOpenMapAnalysis,
    required this.onOpenHistory,
    required this.onOpenReports,
  });

  @override
  Widget build(BuildContext context) {
    final data = state.result;
    final weather = state.liveWeather ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WebKpiRow(state: state),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 7,
              child: _WebCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Overview Map', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                              SizedBox(height: 4),
                              Text('Lightweight preview only. Use Analyze Area for full polygon analysis.', style: TextStyle(color: Colors.black54)),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: onOpenMapAnalysis,
                          icon: const Icon(Icons.map_rounded),
                          label: const Text('Open GIS Review'),
                          style: OutlinedButton.styleFrom(foregroundColor: green),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _WebMapPreview(state: state),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  _WebQuickActions(
                    onStartAnalyze: onStartAnalyze,
                    onOpenHistory: onOpenHistory,
                    onOpenReports: onOpenReports,
                    onOpenMapAnalysis: onOpenMapAnalysis,
                  ),
                  const SizedBox(height: 18),
                  _WebWeatherSummary(state: state, weather: weather),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: _WebRecommendedCropPanel(state: state)),
            const SizedBox(width: 18),
            Expanded(flex: 5, child: _WebEnvironmentPanel(state: state)),
            const SizedBox(width: 18),
            Expanded(flex: 4, child: _WebDistributionPanel(state: state)),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 7, child: WebHistoryScreen(state: state, compact: true)),
            const SizedBox(width: 18),
            Expanded(flex: 4, child: WebReportsScreen(state: state, compact: true)),
          ],
        ),
      ],
    );
  }
}

class _WebQuickActions extends StatelessWidget {
  final VoidCallback onStartAnalyze;
  final VoidCallback onOpenMapAnalysis;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenReports;
  const _WebQuickActions({
    required this.onStartAnalyze,
    required this.onOpenMapAnalysis,
    required this.onOpenHistory,
    required this.onOpenReports,
  });

  @override
  Widget build(BuildContext context) => _WebCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Quick Actions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 14),
      SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: onStartAnalyze, icon: const Icon(Icons.analytics_rounded), label: const Text('Start Analysis'))),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: onOpenMapAnalysis, icon: const Icon(Icons.map_rounded), label: const Text('Review Map Analysis'), style: OutlinedButton.styleFrom(foregroundColor: green))),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: onOpenHistory, icon: const Icon(Icons.history_rounded), label: const Text('History'), style: OutlinedButton.styleFrom(foregroundColor: green))),
        const SizedBox(width: 10),
        Expanded(child: OutlinedButton.icon(onPressed: onOpenReports, icon: const Icon(Icons.picture_as_pdf_rounded), label: const Text('Reports'), style: OutlinedButton.styleFrom(foregroundColor: green))),
      ]),
    ]),
  );
}

class _WebWeatherSummary extends StatelessWidget {
  final AnalysisState state;
  final Map<String, dynamic> weather;
  const _WebWeatherSummary({required this.state, required this.weather});

  @override
  Widget build(BuildContext context) => _WebCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Weather Summary', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 12),
      _MiniWeatherRow(icon: Icons.thermostat_rounded, label: 'Temperature', value: '${state.numText(weather['temperature'] ?? weather['temperature_c'])} °C'),
      _MiniWeatherRow(icon: Icons.water_drop_rounded, label: 'Rainfall', value: '${state.numText(weather['rainfall_today'] ?? weather['rainfall_mm'])} mm'),
      _MiniWeatherRow(icon: Icons.cloud_rounded, label: 'Condition', value: '${weather['condition'] ?? weather['weather_condition'] ?? '--'}'),
    ]),
  );
}

class _MiniWeatherRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _MiniWeatherRow({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(children: [
      Icon(icon, color: green),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w700))),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
    ]),
  );
}


class _WebMapPreview extends StatelessWidget {
  final AnalysisState state;
  const _WebMapPreview({required this.state});

  @override
  Widget build(BuildContext context) {
    final data = state.result;
    final crop = '${data?['crop_recommendation'] ?? data?['recommended_crop'] ?? 'No analysis yet'}';
    final pct = data?['crop_compatibility_pct'] ?? data?['compatibility_pct'];
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 300,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE9F5ED), Color(0xFFD6EBDD)],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _LightMapPreviewPainter(),
              ),
            ),
            Positioned(left: 18, top: 18, child: _SmallBadge('Dashboard Preview')),
            Positioned(
              left: 24,
              bottom: 24,
              child: _SuitabilityLegend(),
            ),
            Positioned(
              right: 18,
              bottom: 18,
              child: Container(
                width: 330,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white.withOpacity(.94), borderRadius: BorderRadius.circular(18)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(crop, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(pct == null ? 'Use Analyze Area for the interactive map and polygon analysis.' : '${state.numText(pct)}% • ${displaySuitability(data)}', style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
            Positioned(
              left: 0, right: 0, top: 0, bottom: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(.84), borderRadius: BorderRadius.circular(18)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map_rounded, color: green),
                      SizedBox(width: 10),
                      Text('Light preview only — open Analyze Area for full GIS tools', style: TextStyle(fontWeight: FontWeight.w900, color: darkGreen)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LightMapPreviewPainter extends CustomPainter {
  const _LightMapPreviewPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFF8CC9A2).withOpacity(.18)
      ..strokeWidth = 1.5;
    final field = Paint()
      ..color = const Color(0xFF0B7F43).withOpacity(.18)
      ..style = PaintingStyle.fill;
    final road = Paint()
      ..color = Colors.white.withOpacity(.75)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    for (double x = -size.width; x < size.width * 2; x += 90) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), grid);
    }
    for (double y = 40; y < size.height; y += 70) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 25), grid);
    }
    final p = ui.Path()
      ..moveTo(size.width * .18, size.height * .25)
      ..lineTo(size.width * .42, size.height * .18)
      ..lineTo(size.width * .55, size.height * .44)
      ..lineTo(size.width * .30, size.height * .60)
      ..close();
    canvas.drawPath(p, field);
    final roadPath = ui.Path()
      ..moveTo(size.width * .05, size.height * .80)
      ..cubicTo(size.width * .30, size.height * .63, size.width * .58, size.height * .92, size.width * .95, size.height * .66);
    canvas.drawPath(roadPath, road);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WebRecommendedCropPanel extends StatelessWidget {
  final AnalysisState state;
  const _WebRecommendedCropPanel({required this.state});
  @override
  Widget build(BuildContext context) {
    final data = state.result;
    final crop = '${data?['crop_recommendation'] ?? data?['recommended_crop'] ?? 'No crop selected'}';
    final pct = data?['crop_compatibility_pct'] ?? data?['compatibility_pct'];
    final List<dynamic> recs = (data?['top_crop_recommendations'] is List) ? data!['top_crop_recommendations'] as List : const [];
    return _WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Container(width: 50, height: 50, decoration: BoxDecoration(color: const Color(0xFFFFF1CC), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.emoji_events_rounded, color: Color(0xFFE9A829))), const SizedBox(width: 14), const Text('Recommended Crop', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))]),
      const SizedBox(height: 22),
      Row(children: [Container(width: 120, height: 100, decoration: BoxDecoration(color: softGreen, borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.eco_rounded, color: green, size: 58)), const SizedBox(width: 18), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(crop, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)), const SizedBox(height: 8), _SmallBadge(pct == null ? '-' : '${state.numText(pct)}%'), const SizedBox(height: 8), Text(displaySuitability(data).toLowerCase(), style: const TextStyle(color: Colors.black54))]))]),
      const SizedBox(height: 24),
      const Row(children: [SizedBox(width: 50, child: Text('Rank', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w800))), Expanded(child: Text('Crop', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w800))), SizedBox(width: 90, child: Text('Suitability', textAlign: TextAlign.right, style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w800)))]),
      const Divider(),
      if (recs.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 36), child: Center(child: Text('Run an area analysis to show crop ranking.', style: TextStyle(color: Colors.black45))))
      else ...recs.take(5).toList().asMap().entries.map((e) {
        final item = e.value;
        final name = item is Map ? '${item['crop'] ?? item['name'] ?? '--'}' : '$item';
        final score = item is Map ? (item['score'] ?? item['suitability'] ?? item['suitability_pct']) : null;
        return Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: Row(children: [SizedBox(width: 50, child: Text('${e.key + 1}')), Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700))), SizedBox(width: 90, child: Text(score == null ? '--' : '${state.numText(score)}%', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800)))]));
      }),
    ]));
  }
}
