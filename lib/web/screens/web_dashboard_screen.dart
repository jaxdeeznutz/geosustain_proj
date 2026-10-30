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
    final metrics = WebAnalysisMetrics(records);
    final summary = state.webSummary;
    final summaryReady = summary != null;
    final avg = summaryReady
        ? analysisNumber(summary['average_model_score'])
        : metrics.average;
    final frequencies = analysisListValue(summary?['frequencies']);
    final topCrop = summaryReady
        ? (frequencies.isEmpty
              ? null
              : '${analysisMapValue(frequencies.first)['crop']}')
        : metrics.mostFrequent;
    final totalArea = summaryReady
        ? (analysisNumber(summary['cumulative_area_ha']) ?? 0)
        : metrics.records.fold<double>(
            0,
            (sum, row) => sum + _recordAreaHa(row),
          );
    final weather = state.liveWeather ?? <String, dynamic>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!summaryReady)
          Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Summary of currently loaded records only. Whole-account statistics are not available yet.',
            ),
          ),
        if (state.historyError != null || state.resourceErrors.isNotEmpty)
          WebResourceWarning(state: state),
        _DashboardWelcomeRow(name: name, state: state, weather: weather),
        SizedBox(height: 18),
        WebAdaptiveRow(
          children: [
            Expanded(
              child: _DashboardKpi(
                icon: Icons.assignment_rounded,
                title: 'Total Analyses',
                value: '${summary?['analysis_count'] ?? records.length}',
                subtitle: records.isEmpty
                    ? 'No analyses yet'
                    : 'Across all saved areas',
                warning: records.isEmpty,
              ),
            ),
            SizedBox(width: 18),
            Expanded(
              child: _DashboardKpi(
                icon: Icons.eco_rounded,
                title: 'Average Model Score',
                value: avg == null ? '—' : '${avg.toStringAsFixed(1)}%',
                subtitle: avg == null
                    ? (state.isPlanner
                          ? 'No recorded model scores yet'
                          : 'Start your first crop analysis')
                    : 'Recorded crop model scores',
              ),
            ),
            SizedBox(width: 18),
            Expanded(
              child: _DashboardKpi(
                icon: Icons.spa_rounded,
                title: 'Most Frequent Recommendation',
                value: topCrop ?? '—',
                subtitle: topCrop == null
                    ? 'Not available yet'
                    : 'Most frequently recommended',
              ),
            ),
            SizedBox(width: 18),
            Expanded(
              child: _DashboardKpi(
                icon: Icons.map_rounded,
                title: 'Cumulative Analysis Area',
                value: totalArea > 0
                    ? '${totalArea.toStringAsFixed(2)} ha'
                    : '0.00 ha',
                subtitle: totalArea > 0
                    ? 'Repeated farm analyses count separately'
                    : 'No measured polygons yet',
              ),
            ),
          ],
        ),
        SizedBox(height: 18),
        WebAdaptiveRow(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 7,
              child: _DashboardGettingStarted(onStartAnalyze: onStartAnalyze),
            ),
            SizedBox(width: 18),
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  _DashboardQuickActions(
                    analyst: state.isPlanner,
                    onStartAnalyze: onStartAnalyze,
                    onOpenMapAnalysis: onOpenMapAnalysis,
                    onOpenHistory: onOpenHistory,
                    onOpenReports: onOpenReports,
                  ),
                  SizedBox(height: 18),
                  _DashboardWeather(state: state, weather: weather),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 18),
        WebAdaptiveRow(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _DashboardRecentAnalyses(
                state: state,
                records: records.take(4).toList(),
                onOpenHistory: onOpenHistory,
                titleFor: (row) =>
                    WebAnalysisMetrics.cropName(row) ??
                    '${row['recommendation_title'] ?? 'Land assessment'}',
                isCrop: WebAnalysisMetrics.isCrop,
              ),
            ),
            SizedBox(width: 18),
            Expanded(
              child: _DashboardRecentReports(
                state: state,
                onOpenReports: onOpenReports,
              ),
            ),
            SizedBox(width: 18),
            Expanded(child: _DashboardDidYouKnow()),
          ],
        ),
        if (state.isPlanner) ...[
          Text(
            'Submitted review workload',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          WebAdaptiveRow(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _AnalystWorkflowCard(
                  icon: Icons.fact_check_rounded,
                  title: 'Review farmer submissions',
                  description:
                      'Open a submitted case, inspect its saved boundary and evidence, then record your review decision.',
                  steps:
                      'Review Inbox → Inspect evidence → Verify, request information, or reject',
                  action: 'Open Review Inbox',
                  onPressed: () => PortalRoutes.go('/operator/queue'),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _AnalystWorkflowCard(
                  icon: Icons.map_rounded,
                  title: 'Map of submitted cases',
                  description:
                      'Locate farmer-submitted cases and open their saved evidence for review.',
                  steps: 'Open map → Select submitted case → Inspect evidence',
                  action: 'Open submitted case map',
                  onPressed: onOpenMapAnalysis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          WebOperatorOverview(state: state),
          const SizedBox(height: 24),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _AnalystWorkflowCard extends StatelessWidget {
  final IconData icon;
  final String title, description, steps, action;
  final VoidCallback onPressed;
  const _AnalystWorkflowCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.steps,
    required this.action,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, color: WebPortalColors.accent, size: 30),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(description),
          const SizedBox(height: 12),
          Text(steps, style: TextStyle(color: WebPortalColors.muted)),
          const SizedBox(height: 16),
          FilledButton(onPressed: onPressed, child: Text(action)),
        ],
      ),
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
            color: WebPortalColors.tint,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(
            Icons.eco_rounded,
            color: WebPortalColors.accent,
            size: 30,
          ),
        ),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome back, $name!',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 4),
              Text(
                "Here's what's happening with your agricultural insights today.",
                style: TextStyle(color: WebPortalColors.muted),
              ),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: WebPortalColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Color(0xFFE1EAE3)),
          ),
          child: Row(
            children: [
              Icon(Icons.cloud_outlined, color: WebPortalColors.accent),
              SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    temp == '--' ? 'Weather unavailable' : '$temp °C',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                  Text(
                    condition,
                    style: TextStyle(
                      color: WebPortalColors.muted,
                      fontSize: 12,
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
  Widget build(BuildContext context) {
    // Explicit palette values must update even when this widget is const.
    Theme.of(context);
    return _WebCard(
      padding: EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: WebPortalColors.tint,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(icon, color: WebPortalColors.accent, size: 28),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: WebPortalColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: warning
                        ? (WebPortalColors.dark
                              ? Color(0xFFF2CA6E)
                              : Color(0xFF805400))
                        : WebPortalColors.accent,
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
}

class _DashboardGettingStarted extends StatelessWidget {
  final VoidCallback onStartAnalyze;
  const _DashboardGettingStarted({required this.onStartAnalyze});

  @override
  Widget build(BuildContext context) => _WebCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Get Started with GeoSustain',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 8),
        Text(
          'Begin a land analysis to receive crop recommendations, land assessments, and planning insights.',
          style: TextStyle(color: WebPortalColors.muted),
        ),
        SizedBox(height: 24),
        LayoutBuilder(
          builder: (_, box) => Wrap(
            spacing: 16,
            runSpacing: 20,
            children: [
              for (final step in const [
                _DashboardStep(
                  icon: Icons.location_on_rounded,
                  title: 'Select Area',
                  subtitle: 'Choose a point or draw a polygon',
                ),
                _DashboardStep(
                  icon: Icons.layers_rounded,
                  title: 'Analyze Land',
                  subtitle: 'Evaluate soil, weather, terrain, and NDVI',
                ),
                _DashboardStep(
                  icon: Icons.eco_rounded,
                  title: 'Get Results',
                  subtitle: 'Receive a crop or land-use assessment',
                ),
                _DashboardStep(
                  icon: Icons.description_rounded,
                  title: 'Generate Report',
                  subtitle: 'Save and export your assessment',
                ),
              ])
                SizedBox(
                  width: box.maxWidth < 500
                      ? (box.maxWidth - 16) / 2
                      : (box.maxWidth - 48) / 4,
                  child: step,
                ),
            ],
          ),
        ),
        SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onStartAnalyze,
          icon: Icon(Icons.add_location_alt_rounded),
          label: Text('Start New Analysis'),
        ),
        SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: Text('How GeoSustain works'),
              content: SingleChildScrollView(
                child: Text(
                  '1. Select a point or draw a valid farm boundary.\n\n2. Analyze the area. Preliminary screening can have unassessed factors; a model score is not a soil test.\n\n3. Review sources, dates and limits. Save an analysis or generate its report.\n\n4. Use the verification queue for submitted farmer analyses when your role permits it. Review decisions do not replace field or laboratory evidence.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Close'),
                ),
              ],
            ),
          ),
          icon: Icon(Icons.help_outline_rounded),
          label: Text('How It Works'),
          style: OutlinedButton.styleFrom(
            foregroundColor: WebPortalColors.accent,
          ),
        ),
      ],
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
  Widget build(BuildContext context) {
    // Explicit palette values must update even when this widget is const.
    Theme.of(context);
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: WebPortalColors.tint,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: WebPortalColors.accent),
        ),
        SizedBox(height: 9),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: WebPortalColors.muted, fontSize: 11),
        ),
      ],
    );
  }
}

class _DashboardQuickActions extends StatelessWidget {
  final bool analyst;
  final VoidCallback onStartAnalyze;
  final VoidCallback onOpenMapAnalysis;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenReports;
  const _DashboardQuickActions({
    this.analyst = false,
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
        Text(
          'Quick Actions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onStartAnalyze,
            icon: Icon(Icons.add_circle_outline_rounded),
            label: const Text('Start New Analysis'),
          ),
        ),
        SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onOpenMapAnalysis,
            icon: Icon(Icons.map_rounded),
            label: Text('View Map'),
            style: OutlinedButton.styleFrom(
              foregroundColor: WebPortalColors.accent,
            ),
          ),
        ),
        SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onOpenHistory,
            icon: Icon(Icons.history_rounded),
            label: const Text('Analysis History'),
            style: OutlinedButton.styleFrom(
              foregroundColor: WebPortalColors.accent,
            ),
          ),
        ),
        SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onOpenReports,
            icon: Icon(Icons.description_rounded),
            label: Text('Reports'),
            style: OutlinedButton.styleFrom(
              foregroundColor: WebPortalColors.accent,
            ),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  'Weather Overview',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                'Panabo City',
                style: TextStyle(color: WebPortalColors.muted, fontSize: 12),
              ),
            ],
          ),
          SizedBox(height: 14),
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
          SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: WebPortalColors.tint,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_outlined, color: WebPortalColors.accent),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    condition,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: WebPortalColors.accent,
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
      Icon(icon, color: WebPortalColors.accent),
      SizedBox(height: 5),
      Text(value, style: TextStyle(fontWeight: FontWeight.w900)),
      Text(label, style: TextStyle(color: WebPortalColors.muted, fontSize: 10)),
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
        WebAdaptiveRow(
          children: [
            Expanded(
              child: Text(
                'Recent Analyses',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            TextButton(onPressed: onOpenHistory, child: Text('View All')),
          ],
        ),
        SizedBox(height: 8),
        if (records.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Column(
              children: [
                SizedBox(
                  height: 100,
                  child: Image.asset(
                    'assets/images/dashboard/recent_analysis_illustration.png',
                    fit: BoxFit.contain,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'No analyses yet',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 4),
                Text(
                  'Your recent land analyses will appear here.',
                  style: TextStyle(color: WebPortalColors.muted),
                ),
                SizedBox(height: 12),
                OutlinedButton(
                  onPressed: onOpenHistory,
                  child: Text('Open History'),
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
                margin: EdgeInsets.only(bottom: 9),
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Color(0xFFF9FCFA),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: Color(0xFFE3ECE5)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: crop ? softGreen : Color(0xFFFFE8E8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        crop ? Icons.eco_rounded : Icons.landscape_outlined,
                        color: crop ? green : Colors.redAccent,
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${row['place_name'] ?? row['location'] ?? 'Analyzed Area'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          SizedBox(height: 3),
                          Text(
                            titleFor(row),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: WebPortalColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: WebPortalColors.accent,
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
              Expanded(
                child: Text(
                  'Recent Reports',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              TextButton(onPressed: onOpenReports, child: Text('View All')),
            ],
          ),
          SizedBox(height: 8),
          if (reports.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Column(
                children: [
                  SizedBox(
                    height: 100,
                    child: Image.asset(
                      'assets/images/dashboard/report_illustration.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'No reports generated',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Reports from your analyses will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: WebPortalColors.muted),
                  ),
                ],
              ),
            )
          else
            ...reports.map(
              (r) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
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
                  style: TextStyle(fontWeight: FontWeight.w800),
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
        Text(
          'Did You Know?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 14),
        Text(
          'GeoSustain combines satellite imagery, machine learning, live weather, soil indicators, and terrain data to support smarter agricultural planning.',
          style: TextStyle(color: WebPortalColors.muted, height: 1.45),
        ),
        SizedBox(height: 22),
        Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            color: WebPortalColors.tint,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: EdgeInsets.all(8),
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
  Future<void> _action(
    BuildContext context,
    Future<bool> Function() work,
    String success,
  ) async {
    try {
      final changed = await work();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(changed ? success : 'Already in your library.'),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = state.result;
    if (data == null) {
      return _WebCard(
        child: Text(
          'Select a point or draw a boundary, then analyze the area.',
        ),
      );
    }
    return _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            state.isPlanner
                ? 'Analyst assessment'
                : WebAnalysisMetrics.preliminary(data)
                ? 'Preliminary environmental screening'
                : 'Recorded analysis',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          if (state.isPlanner) ...[
            Text(
              'Recorded result #${data['session_id'] ?? 'unavailable'} · ${analysisDateText(data['analyzed_at'])}',
            ),
            const Text(
              'This independent assessment does not verify or replace a farmer submission. Review the saved evidence and limitations below.',
            ),
            const SizedBox(height: 12),
          ],
          WebAnalysisEvidence(state: state, record: data),
          SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _action(
                  context,
                  () =>
                      state.saveAnalysisRecord(Map<String, dynamic>.from(data)),
                  'Analysis saved.',
                ),
                icon: Icon(Icons.bookmark_border),
                label: Text(state.isPlanner ? 'Save assessment' : 'Save'),
              ),
              OutlinedButton.icon(
                onPressed: () => _action(
                  context,
                  () =>
                      state.createReportRecord(Map<String, dynamic>.from(data)),
                  'Report generated.',
                ),
                icon: Icon(Icons.picture_as_pdf),
                label: Text(state.isPlanner ? 'Create report' : 'Report'),
              ),
              OutlinedButton.icon(
                onPressed: state.isPlanner
                    ? () => PortalRoutes.go('/operator/history')
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: Text('Analysis History')),
                            body: SingleChildScrollView(
                              padding: EdgeInsets.all(20),
                              child: WebHistoryScreen(state: state),
                            ),
                          ),
                        ),
                      ),
                icon: Icon(Icons.history),
                label: Text(state.isPlanner ? 'Assessment Records' : 'History'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
