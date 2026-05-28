part of geosustain_mobile;

class _WebCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _WebCard({required this.child, this.padding = const EdgeInsets.all(22)});
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE4ECE6)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.035), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: child,
      );
}

class _SmallBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _SmallBadge(this.text, {this.color = green});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12)),
      );
}

class _WebHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final AnalysisState state;
  final ValueChanged<String> message;
  const _WebHeader({required this.title, required this.subtitle, required this.state, required this.message});
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        const Icon(Icons.menu_rounded, color: green, size: 32),
        const SizedBox(width: 18),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF102018))),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 15)),
        ])),
        OutlinedButton.icon(
          onPressed: state.weatherLoading ? null : () async {
            final err = await state.refreshLiveWeather();
            if (err != null) message(err);
          },
          icon: const Icon(Icons.refresh_rounded),
          label: Text(state.weatherLoading ? 'Refreshing...' : 'Refresh Data'),
          style: OutlinedButton.styleFrom(foregroundColor: green, side: const BorderSide(color: Color(0xFFE1E8E2)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        ),
        const SizedBox(width: 14),
        const Icon(Icons.notifications_none_rounded, color: Color(0xFF33443A), size: 28),
      ]);
}

class _WebKpiCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  const _WebKpiCard({required this.icon, required this.title, required this.value, required this.subtitle});
  @override
  Widget build(BuildContext context) => _WebCard(
        child: Row(children: [
          Container(width: 62, height: 62, decoration: BoxDecoration(color: softGreen, borderRadius: BorderRadius.circular(18)), child: Icon(icon, color: green, size: 32)),
          const SizedBox(width: 18),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: green, fontWeight: FontWeight.w800, fontSize: 12)),
          ])),
        ]),
      );
}

class _WebKpiRow extends StatelessWidget {
  final AnalysisState state;
  const _WebKpiRow({required this.state});
  @override
  Widget build(BuildContext context) {
    final data = state.result;
    final pct = data?['crop_compatibility_pct'] ?? data?['compatibility_pct'];
    final crop = '${data?['crop_recommendation'] ?? data?['recommended_crop'] ?? 'No analysis yet'}';
    return Row(children: [
      Expanded(child: _WebKpiCard(icon: Icons.grid_view_rounded, title: 'Total Analyses', value: '${state.profileCounts['analysis_count'] ?? state.historyRecords.length}', subtitle: '+ field records')),
      const SizedBox(width: 18),
      Expanded(child: _WebKpiCard(icon: Icons.eco_rounded, title: 'Most Suitable Crop', value: crop, subtitle: data == null ? 'Run analysis' : 'Latest result')),
      const SizedBox(width: 18),
      Expanded(child: _WebKpiCard(icon: Icons.donut_large_rounded, title: 'Average Suitability', value: pct == null ? '--' : '${state.numText(pct)}%', subtitle: displaySuitability(data).toLowerCase())),
      const SizedBox(width: 18),
      Expanded(child: _WebKpiCard(icon: Icons.map_rounded, title: 'Areas Analyzed', value: '${state.historyRecords.length}', subtitle: 'Saved in history')),
    ]);
  }
}

class _WebMapVisual extends StatefulWidget {
  final AnalysisState state;
  final bool showPopup;
  final VoidCallback onClosePopup;
  final Future<void> Function() onAnalyze;
  const _WebMapVisual({
    required this.state,
    required this.showPopup,
    required this.onClosePopup,
    required this.onAnalyze,
  });

  @override
  State<_WebMapVisual> createState() => _WebMapVisualState();
}

class _WebMapVisualState extends State<_WebMapVisual> {
  AnalysisState get state => widget.state;

  Future<void> _analyze() async {
    await widget.onAnalyze();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final data = state.result;
    final crop = '${data?['crop_recommendation'] ?? data?['recommended_crop'] ?? '--'}';
    final pct = data?['crop_compatibility_pct'] ?? data?['compatibility_pct'];

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: double.infinity,
        height: 440,
        child: Stack(
          children: [
            Positioned.fill(
              child: LiveFieldMap(
                analysisState: state,
                onError: (msg) => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(msg)),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(.04),
                        Colors.transparent,
                        Colors.black.withOpacity(.22),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 18,
              left: 18,
              child: _SmallBadge(state.satellite ? 'Satellite' : 'Street', color: green),
            ),
            Positioned(
              top: 18,
              right: 18,
              child: Row(
                children: [
                  _MapToolButton(icon: Icons.layers_rounded, onTap: state.toggleSatellite),
                  const SizedBox(width: 8),
                  _MapToolButton(
                    icon: state.drawing ? Icons.edit_off_rounded : Icons.polyline_rounded,
                    onTap: state.toggleDrawing,
                  ),
                  const SizedBox(width: 8),
                  _MapToolButton(icon: Icons.clear_rounded, onTap: state.clearSelection),
                ],
              ),
            ),
            Positioned(
              right: 18,
              bottom: 18,
              child: FilledButton.icon(
                onPressed: state.loading ? null : _analyze,
                icon: const Icon(Icons.analytics_rounded),
                label: Text(state.polygonPoints.length >= 3 ? 'Analyze Polygon' : 'Analyze Point'),
              ),
            ),
            Positioned(
              left: 18,
              bottom: 18,
              child: _SuitabilityLegend(),
            ),
            if (widget.showPopup)
              Positioned(
                left: 28,
                top: 82,
                child: _WebMapPopup(
                  state: state,
                  crop: crop,
                  pct: pct,
                  onClose: widget.onClosePopup,
                ),
              ),
          ],
        ),
      ),
    );
  }
}


class _WebMapPopup extends StatelessWidget {
  final AnalysisState state;
  final String crop;
  final dynamic pct;
  final VoidCallback onClose;

  const _WebMapPopup({
    required this.state,
    required this.crop,
    required this.pct,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final hasResult = state.result != null;
    final displayCrop = hasResult && crop.trim().isNotEmpty && crop != '--'
        ? crop
        : 'Select or draw an area';
    final pctText = pct == null
        ? 'Ready for analysis'
        : '${double.tryParse('$pct')?.toStringAsFixed(1) ?? pct}% suitability';

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE2ECE6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.10),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: green.withOpacity(.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.eco_rounded, color: green),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    displayCrop,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF173B2A),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              pctText,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: hasResult ? green : Colors.black54,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              state.polygonPoints.length >= 3
                  ? 'Polygon area: ${state.polygonPoints.length} points selected'
                  : 'Point: ${state.selectedPoint.latitude.toStringAsFixed(5)}, ${state.selectedPoint.longitude.toStringAsFixed(5)}',
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              state.selectedPlaceName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapToolButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MapToolButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(color: Colors.white.withOpacity(.94), borderRadius: BorderRadius.circular(12), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: SizedBox(width: 42, height: 42, child: Icon(icon, color: green))));
}

class _SuitabilityLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(width: 160, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withOpacity(.92), borderRadius: BorderRadius.circular(14)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Suitability', style: TextStyle(fontWeight: FontWeight.w900)), SizedBox(height: 8), _LegendDot(color: Color(0xFF1FA463), label: '75% - 100%'), _LegendDot(color: Color(0xFF8BDD75), label: '50% - 75%'), _LegendDot(color: Color(0xFFE9A829), label: '25% - 50%'), _LegendDot(color: Color(0xFFE45B5B), label: '0% - 25%')]));
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Container(width: 11, height: 11, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
        ]),
      );
}
