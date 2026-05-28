part of geosustain_mobile;

class SuitabilityLegendCard extends StatelessWidget {
  final AnalysisState state;
  const SuitabilityLegendCard({super.key, required this.state});
  @override
  Widget build(BuildContext context) {
    final pct = state.result?['crop_compatibility_pct'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle('SUITABILITY CLASSIFICATION'),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: suitabilityColor(pct),
                borderRadius: BorderRadius.circular(14)),
            child: Text(suitabilityLabel(pct),
                style: const TextStyle(
                    fontWeight: FontWeight.w900, color: Color(0xFF102018))),
          ),
          const SizedBox(height: 12),
          const Row(children: [
            LegendDot(color: Color(0xFF1FA463), text: 'Highly Suitable'),
            SizedBox(width: 10),
            LegendDot(color: Color(0xFFE9A829), text: 'Moderate'),
            SizedBox(width: 10),
            LegendDot(color: Color(0xFFE45B5B), text: 'Not Suitable'),
          ]),
        ]),
      ),
    );
  }
}

class LegendDot extends StatelessWidget {
  final Color color;
  final String text;
  const LegendDot({super.key, required this.color, required this.text});
  @override
  Widget build(BuildContext context) => Expanded(
          child: Row(children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700))),
      ]));
}

class AnalyticsChartsCard extends StatelessWidget {
  final AnalysisState state;
  const AnalyticsChartsCard({super.key, required this.state});
  double _v(dynamic value, double fallback) {
    final n = value is num ? value : num.tryParse('$value');
    return (n ?? fallback).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final d = state.result;
    final bars = [
      ('NDVI', _v(d?['ndvi'], .45) * 100),
      ('Rainfall', _v(d?['rainfall_mm'], 80) / 2),
      ('Temp', _v(d?['temperature_c'], 28) * 2),
      ('Soil pH', _v(d?['soil_ph'], 5.8) * 12),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle('CHARTS AND ANALYTICS'),
          const SizedBox(height: 12),
          ...bars.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  SizedBox(
                      width: 70,
                      child: Text(b.$1,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700))),
                  Expanded(
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                              value: (b.$2.clamp(0, 100)) / 100,
                              minHeight: 12,
                              backgroundColor: const Color(0xFFE9EEE9),
                              color: green))),
                  const SizedBox(width: 8),
                  Text('${b.$2.clamp(0, 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 12)),
                ]),
              )),
          const SizedBox(height: 4),
          const Text(
              'UI-ready charts for NDVI, rainfall, temperature, and soil condition. Values update after analysis.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
      ),
    );
  }
}

class ReportPreviewCard extends StatelessWidget {
  final AnalysisState state;
  const ReportPreviewCard({super.key, required this.state});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionTitle('REPORT GENERATION'),
          const SizedBox(height: 10),
          Text('Crop: ${state.result?['predicted_crop'] ?? '--'}'),
          Text('Suitability: ${displaySuitability(state.result)}'),
          Text(
              'Location: ${state.result?['place_name'] ?? state.selectedPlaceName}'),
          Text(
              'Coordinates: ${state.latController.text}, ${state.lonController.text}'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => ReportPage(state: state))),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('View / Export Report'),
          ),
        ]),
      ),
    );
  }
}

class ReportPage extends StatelessWidget {
  final AnalysisState state;
  const ReportPage({super.key, required this.state});
  @override
  Widget build(BuildContext context) {
    final d = state.result;
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          MobileHeader(
              title: 'Land Suitability Report',
              back: () => Navigator.pop(context),
              trailing: IconButton(
                  onPressed: () => generateAnalysisPdf(d ?? {}, state: state), icon: const Icon(Icons.download_outlined))),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('GeoSustain Analysis Report',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: green)),
                        const SizedBox(height: 10),
                        Text(
                            'Location: ${d?['place_name'] ?? state.selectedPlaceName}'),
                        Text(
                            'Coordinates: ${state.latController.text}, ${state.lonController.text}'),
                        Text(
                            'Crop Recommendation: ${d?['predicted_crop'] ?? '--'}'),
                        Text(
                            'Compatibility: ${d?['crop_compatibility_pct'] ?? '--'}%'),
                        Text(
                            'Suitability Level: ${displaySuitability(d)}'),
                        const Divider(height: 28),
                        Text('NDVI: ${state.numText(d?['ndvi'])}'),
                        Text(
                            'Rainfall: ${state.numText(d?['rainfall_mm'])} mm'),
                        Text(
                            'Temperature: ${state.numText(d?['temperature_c'])} °C'),
                        Text(
                            'Elevation: ${state.numText(d?['elevation_m'])} m'),
                        Text('Soil pH: ${state.numText(d?['soil_ph'])}'),
                        const Divider(height: 28),
                        Text('Infrastructure Suitability: ${d?['infrastructure_suitability'] ?? '--'}'),
                        Text('Infrastructure Score: ${d?['infrastructure_score'] ?? '--'}'),
                        Text('Infrastructure Status: ${d?['infrastructure_status'] ?? '--'}'),
                        Text('Infrastructure Recommendation: ${d?['infrastructure_recommendation'] ?? '--'}'),
                      ]))),
          AnalyticsChartsCard(state: state),
          const SizedBox(height: 8),
          FilledButton.icon(
              onPressed: () => generateAnalysisPdf(d ?? {}, state: state),
              icon: const Icon(Icons.download),
              label: const Text('Download PDF Report')),
          const Text(
              'Note: PDF export is connected. On mobile, use the share/save option to keep the report file.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
      ),
    );
  }
}

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          MobileHeader(
              title: 'Admin Dashboard', back: () => Navigator.pop(context)),
          _AdminStat(
              title: 'Users', value: '24', icon: Icons.people_alt_outlined),
          _AdminStat(
              title: 'Datasets', value: '6', icon: Icons.dataset_outlined),
          _AdminStat(
              title: 'Analysis Logs',
              value: '128',
              icon: Icons.analytics_outlined),
          Card(
              child: Column(children: const [
            ListTile(
                leading: Icon(Icons.person, color: green),
                title: Text('Manage Users'),
                subtitle: Text('Farmers and independent analysts/planners')),
            Divider(height: 1),
            ListTile(
                leading: Icon(Icons.cloud_upload_outlined, color: green),
                title: Text('Dataset Management'),
                subtitle: Text('NPK, rainfall, elevation, NDVI sources')),
            Divider(height: 1),
            ListTile(
                leading: Icon(Icons.receipt_long_outlined, color: green),
                title: Text('Generated Reports'),
                subtitle: Text('View and export suitability reports')),
          ])),
        ]),
      ),
    );
  }
}

class _AdminStat extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  const _AdminStat(
      {required this.title, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) => Card(
      child: ListTile(
          leading: CircleAvatar(
              backgroundColor: softGreen, child: Icon(icon, color: green)),
          title: Text(title),
          trailing: Text(value,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w900, color: green))));
}


class NotificationsPage extends StatelessWidget {
  final AnalysisState? state;
  const NotificationsPage({super.key, this.state});

  @override
  Widget build(BuildContext context) {
    final st = state;
    if (st == null) {
      return Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              MobileHeader(title: 'Notifications', back: () => Navigator.pop(context), trailing: const SizedBox(width: 48)),
              const SizedBox(height: 8),
              const Card(child: ListTile(leading: CircleAvatar(backgroundColor: softGreen, child: Icon(Icons.cloud_done_outlined, color: green)), title: Text('Live Weather Advisory'), subtitle: Text('Open the Home page to refresh real-time weather alerts.'))),
            ],
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: st,
      builder: (context, _) {
        final alerts = WeatherAlertLogic.build(st.liveWeather, loading: st.weatherLoading);
        return Scaffold(
          backgroundColor: bg,
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                await st.refreshLiveWeather();
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  MobileHeader(title: 'Notifications', back: () => Navigator.pop(context), trailing: const SizedBox(width: 48)),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: const BoxDecoration(color: softGreen, shape: BoxShape.circle),
                            child: const Icon(Icons.campaign_outlined, color: green),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(child: Text('Live Weather Broadcast', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
                          TextButton(
                            onPressed: st.weatherLoading ? null : () => st.refreshLiveWeather(),
                            child: Text(st.weatherLoading ? 'Updating...' : 'Refresh', style: const TextStyle(color: green, fontWeight: FontWeight.w800)),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        Text(
                          WeatherAlertLogic.summary(st.liveWeather, loading: st.weatherLoading),
                          style: const TextStyle(color: Colors.black54, height: 1.35),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...alerts.map((a) => Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          leading: CircleAvatar(backgroundColor: a.bgColor, child: Icon(a.icon, color: green)),
                          title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                          subtitle: Text(a.body),
                        ),
                      )),
                  const SizedBox(height: 10),
                  const Card(
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: Color(0xFFEAF2FF), child: Icon(Icons.info_outline, color: green)),
                      title: Text('Not connected to land analysis'),
                      subtitle: Text('These alerts are generated from live and upcoming weather data only. Crop analysis does not control this warning section.'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
