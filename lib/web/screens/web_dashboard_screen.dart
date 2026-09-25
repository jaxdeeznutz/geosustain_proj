part of '../../main.dart';

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

  bool _isCropRecord(Map<String, dynamic> row) {
    final flag = row['is_crop_recommended'];
    final isCrop = flag is bool
        ? flag
        : !['false', '0'].contains('$flag'.trim().toLowerCase());
    final landType = '${row['land_type'] ?? 'arable'}'.toLowerCase();
    final crop = _recordTitle(row).toUpperCase();
    return isCrop &&
        landType == 'arable' &&
        !crop.contains('ADVISORY') &&
        !crop.contains('LAND USE') &&
        !crop.contains('INFRASTRUCTURE') &&
        !crop.contains('WATER');
  }

  String _recordTitle(Map<String, dynamic> row) {
    final direct =
        row['predicted_crop'] ??
        row['crop_recommendation'] ??
        row['recommended_crop'] ??
        row['land_status'] ??
        row['recommendation_title'];
    if (direct != null && '$direct'.trim().isNotEmpty) return '$direct';
    final top = row['top_crop_recommendations'];
    if (top is List && top.isNotEmpty && top.first is Map) {
      return '${(top.first as Map)['crop'] ?? (top.first as Map)['name'] ?? 'Analysis'}';
    }
    return 'Land analysis';
  }

  double? _recordPct(Map<String, dynamic> row) {
    final raw = row['crop_compatibility_pct'] ?? row['compatibility_pct'];
    return raw is num ? raw.toDouble() : double.tryParse('$raw');
  }

  double _recordAreaHa(Map<String, dynamic> row) {
    final ha = row['area_hectares'] ?? row['area_ha'];
    final haValue = ha is num ? ha.toDouble() : double.tryParse('$ha');
    if (haValue != null && haValue > 0) return haValue;
    final m2 = row['area_m2'] ?? row['area_square_meters'];
    final m2Value = m2 is num ? m2.toDouble() : double.tryParse('$m2');
    return m2Value == null ? 0 : m2Value / 10000;
  }

  @override
  Widget build(BuildContext context) {
    final name =
        '${state.currentUser?['username'] ?? state.currentUser?['name'] ?? 'Analyst'}';
    final records = state.historyRecords
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final cropRecords = records.where(_isCropRecord).toList();
    final validPcts = cropRecords
        .map(_recordPct)
        .whereType<double>()
        .where((v) => v > 0)
        .toList();
    final avg = validPcts.isEmpty
        ? null
        : validPcts.reduce((a, b) => a + b) / validPcts.length;
    final cropCounts = <String, int>{};
    for (final row in cropRecords) {
      final crop = _recordTitle(row);
      cropCounts[crop] = (cropCounts[crop] ?? 0) + 1;
    }
    String? topCrop;
    if (cropCounts.isNotEmpty) {
      topCrop = cropCounts.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
    }
    final totalArea = records.fold<double>(
      0,
      (sum, row) => sum + _recordAreaHa(row),
    );
    final weather = state.liveWeather ?? const <String, dynamic>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DashboardWelcomeRow(name: name, state: state, weather: weather),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _DashboardKpi(
                icon: Icons.assignment_rounded,
                title: 'Total Analyses',
                value: '${records.length}',
                subtitle: records.isEmpty
                    ? 'No analyses yet'
                    : 'Across all saved areas',
                warning: records.isEmpty,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: _DashboardKpi(
                icon: Icons.eco_rounded,
                title: 'Average Suitability',
                value: avg == null ? '—' : '${avg.toStringAsFixed(1)}%',
                subtitle: avg == null
                    ? 'Start your first crop analysis'
                    : 'Verified crop recommendations',
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: _DashboardKpi(
                icon: Icons.spa_rounded,
                title: 'Most Suitable Crop',
                value: topCrop ?? '—',
                subtitle: topCrop == null
                    ? 'Not available yet'
                    : 'Most frequently recommended',
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: _DashboardKpi(
                icon: Icons.map_rounded,
                title: 'Areas Analyzed',
                value: totalArea > 0
                    ? '${totalArea.toStringAsFixed(2)} ha'
                    : '0.00 ha',
                subtitle: totalArea > 0
                    ? 'Combined polygon area'
                    : 'No measured polygons yet',
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 7,
              child: _DashboardGettingStarted(onStartAnalyze: onStartAnalyze),
            ),
            const SizedBox(width: 18),
            Expanded(
              flex: 3,
              child: SizedBox(
                height: 420,
                child: Column(
                  children: [
                    Expanded(
                      child: _DashboardQuickActions(
                        onStartAnalyze: onStartAnalyze,
                        onOpenMapAnalysis: onOpenMapAnalysis,
                        onOpenHistory: onOpenHistory,
                        onOpenReports: onOpenReports,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: _DashboardWeather(state: state, weather: weather),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _DashboardRecentAnalyses(
                  state: state,
                  records: records.take(4).toList(),
                  onOpenHistory: onOpenHistory,
                  titleFor: _recordTitle,
                  isCrop: _isCropRecord,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _DashboardRecentReports(
                  state: state,
                  onOpenReports: onOpenReports,
                ),
              ),
              const SizedBox(width: 18),
              const Expanded(child: _DashboardDidYouKnow()),
            ],
          ),
        ),
      ],
    );
  }
}

class _DashboardWelcomeRow extends StatelessWidget {
  final String name;
  final AnalysisState state;
  final Map<String, dynamic> weather;
  const _DashboardWelcomeRow({
    required this.name,
    required this.state,
    required this.weather,
  });

  @override
  Widget build(BuildContext context) {
    final temp = state.numText(
      weather['temperature_c'] ?? weather['temperature'],
    );
    final condition =
        '${weather['weather_description'] ?? weather['condition'] ?? weather['weather_condition'] ?? 'Weather unavailable'}';
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: softGreen,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.eco_rounded, color: green, size: 30),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome back, $name!',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "Here's what's happening with your agricultural insights today.",
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE1EAE3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.cloud_outlined, color: green),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    temp == '--' ? 'Weather unavailable' : '$temp °C',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    condition,
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
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

class _DashboardKpi extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final bool warning;
  const _DashboardKpi({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) => _WebCard(
    padding: const EdgeInsets.all(20),
    child: Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: softGreen,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Icon(icon, color: green, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: warning ? const Color(0xFFE09B20) : green,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DashboardGettingStarted extends StatelessWidget {
  final VoidCallback onStartAnalyze;
  const _DashboardGettingStarted({required this.onStartAnalyze});

  @override
  Widget build(BuildContext context) => _WebCard(
    child: SizedBox(
      height: 420,
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Get Started with GeoSustain',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Begin a land analysis to receive crop recommendations, land assessments, and planning insights.',
                  style: TextStyle(color: Colors.black54),
                ),
                const Spacer(),
                const Row(
                  children: [
                    Expanded(
                      child: _DashboardStep(
                        icon: Icons.location_on_rounded,
                        title: 'Select Area',
                        subtitle: 'Choose a point or draw a polygon',
                      ),
                    ),
                    _DashboardStepLine(),
                    Expanded(
                      child: _DashboardStep(
                        icon: Icons.layers_rounded,
                        title: 'Analyze Land',
                        subtitle: 'Evaluate soil, weather, terrain, and NDVI',
                      ),
                    ),
                    _DashboardStepLine(),
                    Expanded(
                      child: _DashboardStep(
                        icon: Icons.eco_rounded,
                        title: 'Get Results',
                        subtitle: 'Receive a crop or land-use assessment',
                      ),
                    ),
                    _DashboardStepLine(),
                    Expanded(
                      child: _DashboardStep(
                        icon: Icons.description_rounded,
                        title: 'Generate Report',
                        subtitle: 'Save and export your assessment',
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onStartAnalyze,
                    icon: const Icon(Icons.add_location_alt_rounded),
                    label: const Text('Start New Analysis'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.help_outline_rounded),
                    label: const Text('How It Works'),
                    style: OutlinedButton.styleFrom(foregroundColor: green),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFEAF5EC),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Image.asset(
                  'assets/images/dashboard/dashboard_map_illustration.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _DashboardStep extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _DashboardStep({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: softGreen,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Icon(icon, color: green),
      ),
      const SizedBox(height: 9),
      Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.black54, fontSize: 11),
      ),
    ],
  );
}

class _DashboardStepLine extends StatelessWidget {
  const _DashboardStepLine();
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      height: 1,
      margin: const EdgeInsets.only(bottom: 58),
      color: const Color(0xFF9BCBAA),
    ),
  );
}

class _DashboardQuickActions extends StatelessWidget {
  final VoidCallback onStartAnalyze;
  final VoidCallback onOpenMapAnalysis;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenReports;
  const _DashboardQuickActions({
    required this.onStartAnalyze,
    required this.onOpenMapAnalysis,
    required this.onOpenHistory,
    required this.onOpenReports,
  });
  @override
  Widget build(BuildContext context) => _WebCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onStartAnalyze,
            icon: const Icon(Icons.add_circle_outline_rounded),
            label: const Text('Start New Analysis'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onOpenMapAnalysis,
            icon: const Icon(Icons.map_rounded),
            label: const Text('View Map'),
            style: OutlinedButton.styleFrom(foregroundColor: green),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onOpenHistory,
            icon: const Icon(Icons.history_rounded),
            label: const Text('Analysis History'),
            style: OutlinedButton.styleFrom(foregroundColor: green),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onOpenReports,
            icon: const Icon(Icons.description_rounded),
            label: const Text('Reports'),
            style: OutlinedButton.styleFrom(foregroundColor: green),
          ),
        ),
      ],
    ),
  );
}

class _DashboardWeather extends StatelessWidget {
  final AnalysisState state;
  final Map<String, dynamic> weather;
  const _DashboardWeather({required this.state, required this.weather});
  @override
  Widget build(BuildContext context) {
    String value(dynamic raw, String suffix) {
      final text = state.numText(raw);
      return text == '--' ? '—' : '$text$suffix';
    }

    final condition =
        '${weather['weather_description'] ?? weather['condition'] ?? weather['weather_condition'] ?? 'Unavailable'}';
    return _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Weather Overview',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                'Panabo City',
                style: TextStyle(color: Colors.black45, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _DashboardWeatherMetric(
                  icon: Icons.thermostat_rounded,
                  label: 'Temperature',
                  value: value(
                    weather['temperature_c'] ?? weather['temperature'],
                    '°C',
                  ),
                ),
              ),
              Expanded(
                child: _DashboardWeatherMetric(
                  icon: Icons.water_drop_rounded,
                  label: 'Rainfall',
                  value: value(
                    weather['rainfall_today_mm'] ?? weather['rainfall_mm'],
                    ' mm',
                  ),
                ),
              ),
              Expanded(
                child: _DashboardWeatherMetric(
                  icon: Icons.opacity_rounded,
                  label: 'Humidity',
                  value: value(
                    weather['live_humidity'] ??
                        weather['relative_humidity_2m'] ??
                        weather['humidity_pct'] ??
                        weather['humidity'],
                    '%',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: softGreen,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                const Icon(Icons.cloud_outlined, color: green),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    condition,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: darkGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardWeatherMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DashboardWeatherMetric({
    required this.icon,
    required this.label,
    required this.value,
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, color: green),
      const SizedBox(height: 5),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
      Text(label, style: const TextStyle(color: Colors.black45, fontSize: 10)),
    ],
  );
}

class _DashboardRecentAnalyses extends StatelessWidget {
  final AnalysisState state;
  final List<Map<String, dynamic>> records;
  final VoidCallback onOpenHistory;
  final String Function(Map<String, dynamic>) titleFor;
  final bool Function(Map<String, dynamic>) isCrop;
  const _DashboardRecentAnalyses({
    required this.state,
    required this.records,
    required this.onOpenHistory,
    required this.titleFor,
    required this.isCrop,
  });
  @override
  Widget build(BuildContext context) => _WebCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Recent Analyses',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            TextButton(onPressed: onOpenHistory, child: const Text('View All')),
          ],
        ),
        const SizedBox(height: 8),
        if (records.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(
              children: [
                SizedBox(
                  height: 100,
                  child: Image.asset(
                    'assets/images/dashboard/recent_analysis_illustration.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'No analyses yet',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Your recent land analyses will appear here.',
                  style: TextStyle(color: Colors.black45),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: onOpenHistory,
                  child: const Text('Open History'),
                ),
              ],
            ),
          )
        else
          ...records.map((row) {
            final crop = isCrop(row);
            return InkWell(
              onTap: onOpenHistory,
              borderRadius: BorderRadius.circular(13),
              child: Container(
                margin: const EdgeInsets.only(bottom: 9),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FCFA),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: const Color(0xFFE3ECE5)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: crop ? softGreen : const Color(0xFFFFE8E8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        crop ? Icons.eco_rounded : Icons.landscape_outlined,
                        color: crop ? green : Colors.redAccent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${row['place_name'] ?? row['location'] ?? 'Analyzed Area'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            titleFor(row),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: green,
                      size: 18,
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    ),
  );
}

class _DashboardRecentReports extends StatelessWidget {
  final AnalysisState state;
  final VoidCallback onOpenReports;
  const _DashboardRecentReports({
    required this.state,
    required this.onOpenReports,
  });
  @override
  Widget build(BuildContext context) {
    final reports = state.generatedReports.take(3).toList();
    return _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent Reports',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              TextButton(
                onPressed: onOpenReports,
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (reports.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                children: [
                  SizedBox(
                    height: 100,
                    child: Image.asset(
                      'assets/images/dashboard/report_illustration.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'No reports generated',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Reports from your analyses will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black45),
                  ),
                ],
              ),
            )
          else
            ...reports.map(
              (r) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFE8E8),
                  child: Icon(
                    Icons.picture_as_pdf_rounded,
                    color: Colors.redAccent,
                  ),
                ),
                title: Text(
                  '${r['report_title'] ?? r['title'] ?? 'Analysis Report'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${r['created_at'] ?? r['date'] ?? ''}'.split('T').first,
                ),
                onTap: onOpenReports,
              ),
            ),
        ],
      ),
    );
  }
}

class _DashboardDidYouKnow extends StatelessWidget {
  const _DashboardDidYouKnow();
  @override
  Widget build(BuildContext context) => _WebCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Did You Know?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 14),
        const Text(
          'GeoSustain combines satellite imagery, machine learning, live weather, soil indicators, and terrain data to support smarter agricultural planning.',
          style: TextStyle(color: Colors.black54, height: 1.45),
        ),
        const SizedBox(height: 22),
        Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            color: softGreen,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Image.asset(
              'assets/images/dashboard/agriculture_tip_illustration.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ],
    ),
  );
}

class _WebRecommendedCropPanel extends StatelessWidget {
  final AnalysisState state;
  const _WebRecommendedCropPanel({required this.state});

  String _fallbackCrop(Map<String, dynamic>? data, List<dynamic> recs) {
    final direct =
        data?['predicted_crop'] ??
        data?['crop_recommendation'] ??
        data?['recommended_crop'] ??
        data?['crop'];
    if (direct != null && '$direct'.trim().isNotEmpty && '$direct' != '--') {
      return '$direct';
    }
    if (recs.isNotEmpty && recs.first is Map<String, dynamic>) {
      final top = recs.first as Map<String, dynamic>;
      final name = top['crop'] ?? top['name'];
      if (name != null && '$name'.trim().isNotEmpty) return '$name';
    }
    return 'No crop selected';
  }

  @override
  Widget build(BuildContext context) {
    final data = state.result;
    final List<dynamic> recs = (data?['top_crop_recommendations'] is List)
        ? data!['top_crop_recommendations'] as List
        : const [];
    final top = recs.isNotEmpty && recs.first is Map<String, dynamic>
        ? recs.first as Map<String, dynamic>
        : null;
    final topScore = top == null
        ? null
        : (top['compatibility_pct'] ??
              top['score'] ??
              top['compatibility'] ??
              top['suitability'] ??
              top['suitability_pct']);
    final rawCropFlag = data?['is_crop_recommended'];
    final isCrop = rawCropFlag is bool
        ? rawCropFlag
        : !['false', '0'].contains('$rawCropFlag'.trim().toLowerCase()) &&
              '${data?['land_type'] ?? 'arable'}'.trim().toLowerCase() ==
                  'arable';
    final crop = isCrop
        ? _fallbackCrop(data, recs)
        : '${data?['land_status'] ?? data?['recommendation_title'] ?? 'Non-arable area'}';
    final pct =
        data?['crop_compatibility_pct'] ??
        data?['compatibility_pct'] ??
        topScore;
    final panelTitle = isCrop ? 'Recommended Crop' : 'Land Assessment';
    if (data == null) {
      return _WebCard(
        child: SizedBox(
          height: 340,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.eco_outlined, size: 58, color: Color(0xFF79B98D)),
              SizedBox(height: 14),
              Text(
                'No current analysis',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 6),
              Text(
                'Draw or select an area, then run an analysis. Clearing the selection will also clear this result.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }
    return _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1CC),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  isCrop
                      ? Icons.emoji_events_rounded
                      : Icons.landscape_outlined,
                  color: const Color(0xFFE9A829),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                panelTitle,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Container(
                width: 120,
                height: 100,
                decoration: BoxDecoration(
                  color: softGreen,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.eco_rounded, color: green, size: 58),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      crop,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SmallBadge(
                      isCrop
                          ? (pct == null ? '-' : '${state.numText(pct)}% final')
                          : 'Not recommended',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isCrop
                          ? displaySuitability(data).toLowerCase()
                          : '${data['recommendation_title'] ?? 'Land-use advisory'}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isCrop) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAF7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFDDE9DF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_month_rounded,
                        size: 18,
                        color: green,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '${(data['season_label'] == null || '${data['season_label']}'.trim().isEmpty) ? 'Season calendar unavailable' : data['season_label']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: darkGreen,
                          ),
                        ),
                      ),
                      Text(
                        '${data['intended_planting_month_name'] ?? state.intendedPlantingMonthName}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 18,
                    runSpacing: 6,
                    children: [
                      Text(
                        'Environmental: ${state.numText(data['environmental_suitability_pct'] ?? pct)}%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Final: ${state.numText(data['season_adjusted_score'] ?? pct)}%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${data['season_note'] ?? data['season_advice'] ?? ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Suggested window: ${(data['recommended_planting_window'] == null || '${data['recommended_planting_window']}'.trim().isEmpty || '${data['recommended_planting_window']}'.toLowerCase() == 'null') ? 'Local calendar not configured for this crop' : data['recommended_planting_window']}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await state.saveAnalysisRecord(
                      Map<String, dynamic>.from(data),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'Saved to analysis library.'
                                : 'Already saved.',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.bookmark_border_rounded),
                  label: const Text('Save'),
                  style: OutlinedButton.styleFrom(foregroundColor: green),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await state.createReportRecord(
                      Map<String, dynamic>.from(data),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok ? 'Report generated.' : 'Report already exists.',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text('Report'),
                  style: OutlinedButton.styleFrom(foregroundColor: green),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await state.refreshHistoryData();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('History refreshed.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('History'),
                  style: OutlinedButton.styleFrom(foregroundColor: green),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (!isCrop)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: softGreen,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${data['recommendation'] ?? 'Crop recommendation was stopped for this location.'}',
                style: const TextStyle(
                  color: darkGreen,
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
              ),
            )
          else ...[
            const Row(
              children: [
                SizedBox(
                  width: 50,
                  child: Text(
                    'Rank',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Crop',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: Text(
                    'Final score',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(),
            if (recs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Text(
                    'Run an area analysis to show crop ranking.',
                    style: TextStyle(color: Colors.black45),
                  ),
                ),
              )
            else
              ...recs.take(5).toList().asMap().entries.map((e) {
                final item = e.value;
                final name = item is Map
                    ? '${item['crop'] ?? item['name'] ?? '--'}'
                    : '$item';
                final score = item is Map
                    ? (item['compatibility_pct'] ??
                          item['score'] ??
                          item['compatibility'] ??
                          item['suitability'] ??
                          item['suitability_pct'])
                    : null;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: [
                      SizedBox(width: 50, child: Text('${e.key + 1}')),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(
                          score == null ? '--' : '${state.numText(score)}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }
}
