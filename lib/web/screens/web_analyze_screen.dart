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
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 7,
                    child: _WebMapVisual(
                      state: state,
                      showPopup: true,
                      onClosePopup: () {},
                      onAnalyze: onAnalyze,
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
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: _WebEnvironmentPanel(state: state)),
            const SizedBox(width: 18),
            Expanded(flex: 5, child: _WebInfrastructurePanel(state: state)),
            const SizedBox(width: 18),
            Expanded(flex: 4, child: _WebDistributionPanel(state: state)),
          ],
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

class _WebInfrastructurePanel extends StatelessWidget {
  final AnalysisState state;
  const _WebInfrastructurePanel({required this.state});

  @override
  Widget build(BuildContext context) {
    final d = state.result ?? {};
    return _WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Infrastructure & Risk Suitability', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 12),
      _InfoLine(icon: Icons.business_rounded, title: 'Infrastructure Score', value: '${d['infrastructure_score'] ?? '--'}'),
      _InfoLine(icon: Icons.warning_amber_rounded, title: 'Risk Level', value: '${d['risk_level'] ?? d['infrastructure_suitability'] ?? '--'}'),
      _InfoLine(icon: Icons.terrain_rounded, title: 'Slope', value: '${state.numText(d['slope'])}%'),
      _InfoLine(icon: Icons.height_rounded, title: 'Elevation', value: '${state.numText(d['elevation'])} m'),
      const SizedBox(height: 8),
      Text('${d['infrastructure_note'] ?? 'Run an analysis to generate infrastructure and environmental risk notes.'}', style: const TextStyle(color: Colors.black54, height: 1.4)),
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
