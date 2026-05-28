part of geosustain_mobile;

class WebMapScreen extends StatelessWidget {
  final AnalysisState state;
  final bool popupVisible;
  final VoidCallback onClosePopup;
  final Future<void> Function() onAnalyze;
  const WebMapScreen({
    super.key,
    required this.state,
    required this.popupVisible,
    required this.onClosePopup,
    required this.onAnalyze,
  });

  @override
  Widget build(BuildContext context) {
    final rows = state.historyRecords.take(8).toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 7,
          child: _WebCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('GIS Review Workspace', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    SizedBox(height: 4),
                    Text('Review analyzed markers, saved polygons, suitability indicators, and infrastructure overlays.', style: TextStyle(color: Colors.black54)),
                  ]),
                ),
                OutlinedButton.icon(
                  onPressed: state.toggleSatellite,
                  icon: const Icon(Icons.layers_rounded),
                  label: Text(state.satellite ? 'Satellite' : 'Street'),
                  style: OutlinedButton.styleFrom(foregroundColor: green),
                ),
              ]),
              const SizedBox(height: 16),
              _WebReviewMap(state: state),
            ]),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          flex: 4,
          child: Column(children: [
            _WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Comparison Mode', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              const Text('Use this page to review past analyzed lands. New analysis is done in Analyze Area.', style: TextStyle(color: Colors.black54, height: 1.45)),
              const SizedBox(height: 14),
              _ReviewChip(icon: Icons.location_on_rounded, label: '${state.historyRecords.length} analyzed markers'),
              _ReviewChip(icon: Icons.polyline_rounded, label: '${state.polygonPoints.length} active polygon points'),
              _ReviewChip(icon: Icons.business_rounded, label: '${state.result?['infrastructure_suitability'] ?? state.result?['infrastructure_note'] ?? 'Infrastructure overlays ready'}'),
              _ReviewChip(icon: Icons.thermostat_rounded, label: '${state.numText((state.liveWeather ?? {})['temperature'])} °C live temperature'),
            ])),
            const SizedBox(height: 18),
            _WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Previously Analyzed Lands', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No analyzed areas yet.', style: TextStyle(color: Colors.black45))))
              else
                ...rows.map((r) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(backgroundColor: softGreen, child: Icon(Icons.eco_rounded, color: green)),
                  title: Text('${r['place_name'] ?? r['location'] ?? 'Analyzed Area'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text('${r['crop_recommendation'] ?? r['recommended_crop'] ?? r['crop'] ?? '--'} • ${r['crop_compatibility_pct'] ?? r['compatibility_pct'] ?? '--'}%'),
                )),
            ])),
          ]),
        ),
      ],
    );
  }
}

class _ReviewChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ReviewChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Container(width: 36, height: 36, decoration: BoxDecoration(color: softGreen, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: green, size: 20)),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))),
    ]),
  );
}

class _WebReviewMap extends StatelessWidget {
  final AnalysisState state;
  const _WebReviewMap({required this.state});

  LatLng? _pointFromRecord(Map<String, dynamic> r) {
    final latRaw = r['center_lat'] ?? r['lat'];
    final lonRaw = r['center_lon'] ?? r['lon'];
    final lat = latRaw is num ? latRaw.toDouble() : double.tryParse('$latRaw');
    final lon = lonRaw is num ? lonRaw.toDouble() : double.tryParse('$lonRaw');
    if (lat == null || lon == null) return null;
    return LatLng(lat, lon);
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      Marker(point: state.selectedPoint, width: 42, height: 42, child: const Icon(Icons.location_pin, color: Colors.red, size: 40)),
      ...state.historyRecords.take(30).map((r) {
        final p = _pointFromRecord(r);
        if (p == null) return null;
        return Marker(
          point: p,
          width: 26,
          height: 26,
          child: const Icon(Icons.circle, color: Color(0xFFE9A829), size: 18),
        );
      }).whereType<Marker>(),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 560,
        child: Stack(children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: state.selectedPoint,
              initialZoom: 12.8,
              minZoom: 12,
              maxZoom: 18,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom | InteractiveFlag.scrollWheelZoom | InteractiveFlag.doubleTapZoom,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: state.satellite
                    ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.geosustain.mobile',
              ),
              if (state.polygonPoints.length >= 3)
                PolygonLayer(polygons: [
                  Polygon(points: state.polygonPoints, color: green.withOpacity(.18), borderColor: green, borderStrokeWidth: 3),
                ]),
              MarkerLayer(markers: markers),
            ],
          ),
          Positioned(left: 18, bottom: 18, child: _SuitabilityLegend()),
          Positioned(top: 18, left: 18, child: _SmallBadge('Review Mode')),
        ]),
      ),
    );
  }
}
