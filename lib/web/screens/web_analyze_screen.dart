part of geosustain_mobile;

class WebAnalyzeScreen extends StatelessWidget {
  final AnalysisState state;
  final Future<void> Function() onAnalyze;
  const WebAnalyzeScreen({super.key, required this.state, required this.onAnalyze});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Analyze Area Workspace', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                        SizedBox(height: 4),
                        Text('Use the same analysis engine as mobile: select a point, draw a polygon, then run crop and environmental suitability.', style: TextStyle(color: Colors.black54)),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.toggleDrawing,
                    icon: Icon(state.drawing ? Icons.edit_off_rounded : Icons.polyline_rounded),
                    label: Text(state.drawing ? 'Stop Drawing' : 'Draw Polygon'),
                    style: OutlinedButton.styleFrom(foregroundColor: green),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: state.clearSelection,
                    icon: const Icon(Icons.clear_rounded),
                    label: const Text('Clear'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: state.loading ? null : onAnalyze,
                    icon: const Icon(Icons.analytics_rounded),
                    label: Text(state.polygonPoints.length >= 3 ? 'Analyze Polygon' : 'Analyze Point'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 7,
                    child: Column(
                      children: [
                        _WebMapVisual(
                          state: state,
                          showPopup: false,
                          onClosePopup: () {},
                          onAnalyze: onAnalyze,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 340,
                                child: _WebEnvironmentPanel(state: state, compact: true),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 340,
                                child: _WebInfrastructurePanel(state: state, compact: true),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 340,
                                child: _WebDistributionPanel(state: state, compact: true),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        _WebAnalyzeInputPanel(state: state, onAnalyze: onAnalyze),
                        const SizedBox(height: 18),
                        _WebRecommendedCropPanel(state: state),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WebAnalyzeInputPanel extends StatelessWidget {
  final AnalysisState state;
  final Future<void> Function() onAnalyze;
  const _WebAnalyzeInputPanel({required this.state, required this.onAnalyze});

  @override
  Widget build(BuildContext context) => _WebCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Selected Field', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          TextField(controller: state.latController, decoration: const InputDecoration(labelText: 'Latitude', prefixIcon: Icon(Icons.location_on_outlined))),
          const SizedBox(height: 10),
          TextField(controller: state.lonController, decoration: const InputDecoration(labelText: 'Longitude', prefixIcon: Icon(Icons.location_on_outlined))),
          const SizedBox(height: 14),
          _InfoLine(icon: Icons.place_rounded, title: 'Selected Area', value: state.selectedPlaceName),
          _InfoLine(icon: Icons.polyline_rounded, title: 'Polygon Points', value: '${state.polygonPoints.length}'),
          _InfoLine(icon: Icons.layers_rounded, title: 'Selection Type', value: state.polygonPoints.length >= 3 ? 'Boundary polygon' : 'Single point'),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: state.intendedPlantingMonth,
            decoration: const InputDecoration(labelText: 'Intended Planting Month', prefixIcon: Icon(Icons.calendar_month_rounded)),
            items: List.generate(12, (index) {
              final month = index + 1;
              return DropdownMenuItem(value: month, child: Text(AnalysisState.monthNames[month]));
            }),
            onChanged: state.loading ? null : state.setIntendedPlantingMonth,
          ),
          const SizedBox(height: 10),
          const _WebSeasonLegend(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: state.loading ? null : onAnalyze,
              icon: const Icon(Icons.analytics_rounded),
              label: Text(state.polygonPoints.length >= 3 ? 'Analyze Polygon' : 'Analyze Point'),
            ),
          ),
        ]),
      );
}


class _WebSeasonLegend extends StatelessWidget {
  const _WebSeasonLegend();
  @override
  Widget build(BuildContext context) {
    Widget chip(Color color, String label, String tip) => Tooltip(
      message: tip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(.35))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 6), Flexible(child: Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)))]),
      ),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFF7FAF7), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDDE9DF))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Season legend', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: green)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          chip(const Color(0xFF168A4A), 'In season', 'Inside the preferred local planting window.'),
          chip(const Color(0xFF57A96B), 'Establishment', 'Preferred period for establishing perennial crops.'),
          chip(const Color(0xFFE6A21A), 'Managed', 'Possible year-round with irrigation or moisture management.'),
          chip(const Color(0xFFD9534F), 'Out of season', 'Seasonal penalty is applied to the crop score.'),
        ]),
      ]),
    );
  }
}

class _WebInfrastructurePanel extends StatelessWidget {
  final AnalysisState state;
  final bool compact;
  const _WebInfrastructurePanel({required this.state, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final d = state.result ?? {};
    final slope = d['slope_pct'] ?? d['slope'];
    final elevation = d['elevation_m'] ?? d['elevation'];
    return _WebCard(
      padding: compact ? const EdgeInsets.all(14) : const EdgeInsets.all(22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Infrastructure & Risk Suitability', style: TextStyle(fontSize: compact ? 16 : 20, fontWeight: FontWeight.w900)),
      SizedBox(height: compact ? 8 : 12),
      _InfoLine(icon: Icons.business_rounded, title: 'Infrastructure Score', value: '${d['infrastructure_score'] ?? '--'}'),
      _InfoLine(icon: Icons.warning_amber_rounded, title: 'Risk Level', value: '${d['risk_level'] ?? d['infrastructure_suitability'] ?? '--'}'),
      _InfoLine(icon: Icons.terrain_rounded, title: 'Slope', value: '${state.numText(slope)}%'),
      _InfoLine(icon: Icons.height_rounded, title: 'Elevation', value: '${state.numText(elevation)} m'),
      SizedBox(height: compact ? 0 : 8),
      Text(
        '${d['infrastructure_note'] ?? 'Run an analysis to generate infrastructure and environmental risk notes.'}',
        maxLines: compact ? 2 : null,
        overflow: compact ? TextOverflow.ellipsis : TextOverflow.visible,
        style: TextStyle(color: Colors.black54, height: compact ? 1.25 : 1.4, fontSize: compact ? 12 : 14),
      ),
    ]));
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  const _InfoLine({required this.icon, required this.title, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Icon(icon, color: green),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
          ])),
        ]),
      );
}
