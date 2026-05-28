part of geosustain_mobile;

class WebCropTrendsScreen extends StatelessWidget {
  final AnalysisState state;
  const WebCropTrendsScreen({super.key, required this.state});
  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final r in state.historyRecords) {
      final crop = '${r['crop_recommendation'] ?? r['recommended_crop'] ?? r['crop'] ?? 'Unknown'}';
      counts[crop] = (counts[crop] ?? 0) + 1;
    }
    final entries = counts.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));
    return _WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Crop Trends', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      const Text('Frequency of recommended crops from saved analyses.', style: TextStyle(color: Colors.black54)),
      const SizedBox(height: 22),
      if (entries.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(40), child: Text('Run analyses to populate crop trends.', style: TextStyle(color: Colors.black45))))
      else ...entries.map((e) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Row(children: [SizedBox(width: 190, child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w900))), Expanded(child: LinearProgressIndicator(value: e.value / (entries.first.value), minHeight: 12, borderRadius: BorderRadius.circular(99), color: green, backgroundColor: softGreen)), const SizedBox(width: 12), Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w900))]))),
    ]));
  }
}

class WebWeatherClimateScreen extends StatelessWidget {
  final AnalysisState state;
  const WebWeatherClimateScreen({super.key, required this.state});
  @override
  Widget build(BuildContext context) => WebWeatherEnvironmentScreen(state: state, message: (_) {});
}

class WebSoilEnvironmentScreen extends StatelessWidget {
  final AnalysisState state;
  const WebSoilEnvironmentScreen({super.key, required this.state});
  @override
  Widget build(BuildContext context) => WebWeatherEnvironmentScreen(state: state, message: (_) {});
}

class WebWeatherEnvironmentScreen extends StatelessWidget {
  final AnalysisState state;
  final ValueChanged<String> message;
  const WebWeatherEnvironmentScreen({super.key, required this.state, required this.message});

  @override
  Widget build(BuildContext context) {
    final w = state.liveWeather ?? {};
    final d = state.result ?? {};
    final weatherSource = '${w['weather_source'] ?? 'Open-Meteo live weather'}';
    final condition = '${w['weather_description'] ?? w['condition'] ?? w['weather_condition'] ?? '--'}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Live Weather & Climate', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            SizedBox(height: 6),
            Text('Uses the same live weather source as the mobile app.', style: TextStyle(color: Colors.black54)),
          ])),
          OutlinedButton.icon(
            onPressed: state.weatherLoading ? null : () async {
              final err = await state.refreshLiveWeather();
              if (err != null) message(err);
            },
            icon: const Icon(Icons.refresh_rounded),
            label: Text(state.weatherLoading ? 'Refreshing...' : 'Refresh Live Weather'),
            style: OutlinedButton.styleFrom(foregroundColor: green),
          ),
        ]),
        const SizedBox(height: 18),
        Wrap(spacing: 14, runSpacing: 14, children: [
          _MetricTile(icon: Icons.thermostat_rounded, label: 'Temperature', value: '${state.numText(w['temperature_c'] ?? w['temperature'])} °C'),
          _MetricTile(icon: Icons.water_drop_rounded, label: 'Rainfall Today', value: '${state.numText(w['rainfall_today_mm'] ?? w['today_rainfall_mm'] ?? w['daily_rainfall_mm'] ?? w['current_precipitation_mm'])} mm'),
          _MetricTile(icon: Icons.opacity_rounded, label: 'Humidity', value: '${state.numText(w['live_humidity'] ?? w['humidity'] ?? w['humidity_pct'])}%'),
          _MetricTile(icon: Icons.air_rounded, label: 'Wind', value: '${state.numText(w['max_wind_next_6h_kmh'] ?? w['wind_kmh'] ?? w['wind_speed'] ?? w['wind_speed_ms'])} km/h'),
          _MetricTile(icon: Icons.cloud_rounded, label: 'Condition', value: condition),
          _MetricTile(icon: Icons.schedule_rounded, label: 'Rain Next 3h', value: '${state.numText(w['rain_next_3h_mm'])} mm'),
        ]),
        const SizedBox(height: 14),
        Text('Source: $weatherSource • ${state.selectedPlaceName}', style: const TextStyle(color: Colors.black45, fontWeight: FontWeight.w600)),
      ])),
      const SizedBox(height: 18),
      _WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Soil & Environmental Indicators', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('Environmental factors are filled after running an area analysis.', style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 18),
        Wrap(spacing: 14, runSpacing: 14, children: [
          _MetricTile(icon: Icons.water_drop_rounded, label: 'Rainfall (30d)', value: '${state.numText(d['rainfall_30d'] ?? d['rainfall_mm'] ?? w['rainfall_mm'])} mm'),
          _MetricTile(icon: Icons.terrain_rounded, label: 'Elevation', value: '${state.numText(d['elevation'])} m'),
          _MetricTile(icon: Icons.show_chart_rounded, label: 'Slope', value: '${state.numText(d['slope'])}%'),
          _MetricTile(icon: Icons.eco_rounded, label: 'NDVI', value: '${d['ndvi'] ?? '--'}'),
          _MetricTile(icon: Icons.science_rounded, label: 'Soil pH', value: '${d['soil_ph'] ?? d['ph'] ?? '--'}'),
          _MetricTile(icon: Icons.landscape_rounded, label: 'Land Cover', value: '${d['land_cover'] ?? d['land_status'] ?? '--'}'),
        ]),
      ])),
      const SizedBox(height: 18),
      _WebDistributionPanel(state: state),
    ]);
  }
}

class WebSettingsScreen extends StatelessWidget {
  final AnalysisState state;
  const WebSettingsScreen({super.key, required this.state});
  @override
  Widget build(BuildContext context) => _WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
    const SizedBox(height: 12),
    Text('Signed in as ${state.currentUser?['email'] ?? '--'}', style: const TextStyle(color: Colors.black54)),
    const SizedBox(height: 18),
    const ListTile(leading: Icon(Icons.verified_user_rounded, color: green), title: Text('Role-based access'), subtitle: Text('Web dashboard is restricted to analyst/planner accounts.')),
    const ListTile(leading: Icon(Icons.storage_rounded, color: green), title: Text('Data source'), subtitle: Text('Analysis records are stored through the Render/PostgreSQL backend.')),
  ]));
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _MetricTile({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Container(width: 180, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFF7FAF7), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE4ECE6))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: green), const SizedBox(height: 10), Text(label, style: const TextStyle(color: Colors.black54)), const SizedBox(height: 6), Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))]));
}

class _WebEnvironmentPanel extends StatelessWidget {
  final AnalysisState state;
  const _WebEnvironmentPanel({required this.state});
  @override
  Widget build(BuildContext context) {
    final d = state.result ?? state.liveWeather ?? {};
    return _WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Environmental Overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      const Text('Key environmental factors for the selected area', style: TextStyle(color: Colors.black54)),
      const SizedBox(height: 18),
      Wrap(spacing: 14, runSpacing: 14, children: [
        _MetricTile(icon: Icons.water_drop_rounded, label: 'Rainfall (30d)', value: '${state.numText(d['rainfall_30d'] ?? d['rainfall_mm'])} mm'),
        _MetricTile(icon: Icons.thermostat_rounded, label: 'Temperature', value: '${state.numText(d['temperature'] ?? d['temperature_c'])} °C'),
        _MetricTile(icon: Icons.terrain_rounded, label: 'Elevation', value: '${state.numText(d['elevation'])} m'),
        _MetricTile(icon: Icons.eco_rounded, label: 'NDVI', value: '${d['ndvi'] ?? '--'}'),
        _MetricTile(icon: Icons.landscape_rounded, label: 'Land Cover', value: '${d['land_cover'] ?? d['land_status'] ?? '--'}'),
      ]),
    ]));
  }
}

class _WebDistributionPanel extends StatelessWidget {
  final AnalysisState state;
  const _WebDistributionPanel({required this.state});
  @override
  Widget build(BuildContext context) => _WebCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Suitability Distribution', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
    const SizedBox(height: 10),
    const Text('Distribution of suitability levels based on history records.', style: TextStyle(color: Colors.black54)),
    const SizedBox(height: 22),
    Center(child: SizedBox(width: 160, height: 160, child: Stack(alignment: Alignment.center, children: [CircularProgressIndicator(value: state.historyRecords.isEmpty ? .05 : .72, strokeWidth: 18, color: green, backgroundColor: softGreen), Text('${state.historyRecords.length}\nTotal', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900))]))),
    const SizedBox(height: 20),
    const _LegendDot(color: Color(0xFF1FA463), label: 'Highly Suitable'),
    const _LegendDot(color: Color(0xFF8BDD75), label: 'Moderately Suitable'),
    const _LegendDot(color: Color(0xFFE9A829), label: 'Marginally Suitable'),
  ]));
}
