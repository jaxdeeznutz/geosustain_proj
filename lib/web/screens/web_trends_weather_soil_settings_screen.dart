part of '../../main.dart';

class WebCropTrendsScreen extends StatefulWidget {
  final AnalysisState state;
  const WebCropTrendsScreen({super.key, required this.state});
  @override
  State<WebCropTrendsScreen> createState() => _WebCropTrendsScreenState();
}

class _WebCropTrendsScreenState extends State<WebCropTrendsScreen> {
  String scope = 'current';
  Map<String, dynamic>? loaded;
  bool loading = false;
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    if (widget.state.currentModelSummary == null) unawaited(load());
  }

  Future<void> load() async {
    final request = ++generation;
    final selectedScope = scope;
    final owner = widget.state.currentUser?['id'];
    setState(() {
      loading = true;
      error = null;
      loaded = null;
    });
    try {
      final value = await widget.state.api.getRecommendationPatterns(
        submitted: widget.state.isPlanner,
        modelScope: selectedScope,
      );
      if (value['current_model_version'] == null ||
          value['model_scope'] != selectedScope) {
        throw Exception(
          'The model summary is unavailable. Deploy the matching backend and refresh.',
        );
      }
      if (mounted &&
          request == generation &&
          owner == widget.state.currentUser?['id']) {
        setState(() => loaded = value);
      }
    } catch (e) {
      if (mounted && request == generation) {
        setState(() => error = friendlyErrorMessage(e));
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final summary =
        loaded ??
        (scope == 'current' && !loading && error == null
            ? widget.state.currentModelSummary
            : null);
    final counts = <String, int>{};
    for (final raw in analysisListValue(summary?['frequencies'])) {
      final row = analysisMapValue(raw);
      final count = analysisNumber(row['count']);
      if (row['crop'] != null && count != null) {
        counts['${row['crop']}'] = count.toInt();
      }
    }
    if (scope == 'current' && summary != null) {
      for (final name in analysisListValue(summary['classes'])) {
        final label = '${name[0]}'.toUpperCase() + '$name'.substring(1);
        counts.putIfAbsent(label, () => 0);
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final order = b.value.compareTo(a.value);
        return order == 0 ? a.key.compareTo(b.key) : order;
      });
    final monthly = <MapEntry<DateTime, int>>[];
    for (final raw in analysisListValue(summary?['monthly'])) {
      final row = analysisMapValue(raw);
      final month = DateTime.tryParse('${row['month']}-01');
      final count = analysisNumber(row['count']);
      if (month != null && count != null) {
        monthly.add(MapEntry(month, count.toInt()));
      }
    }
    monthly.sort((a, b) => a.key.compareTo(b.key));
    final scored = (analysisNumber(summary?['scored_count']) ?? 0).toInt();
    final distribution = [
      for (final name in [
        'high_count',
        'medium_count',
        'low_count',
        'very_low_count',
      ])
        (analysisNumber(summary?[name]) ?? 0).toInt(),
    ];
    final topCount = entries.isEmpty ? 0 : entries.first.value;
    final topCrop = topCount == 0 ? 'No data' : entries.first.key;
    final archived = (analysisNumber(summary?['archived_count']) ?? 0).toInt();
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WebCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 280,
                      child: DropdownButtonFormField<String>(
                        key: const ValueKey('patterns-model-scope'),
                        isExpanded: true,
                        initialValue: scope,
                        decoration: const InputDecoration(
                          labelText: 'Model results',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'current',
                            child: Text('Current seven-crop model'),
                          ),
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('All model versions (historical)'),
                          ),
                        ],
                        onChanged: loading
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => scope = value);
                                  unawaited(load());
                                }
                              },
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: loading ? null : load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh patterns'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  scope == 'current'
                      ? 'Current model only. $archived older or unversioned results are excluded.'
                      : 'Historical results include older models and crop labels. Their scores are not directly comparable.',
                ),
                Text(
                  widget.state.isPlanner
                      ? 'Submitted farmer cases ? latest revision of each case.'
                      : 'Your saved analyses.',
                ),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (!loading && error == null && summary == null)
                  const Text(
                    'No model summary is available. Refresh to retry.',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (summary != null) ...[
            _AnalystMetricGrid(
              children: [
                _AnalystMetric(
                  icon: Icons.article_rounded,
                  label: widget.state.isPlanner
                      ? 'Submitted Analyses'
                      : 'Saved Analyses',
                  value: '${summary['analysis_count'] ?? 0}',
                  series: monthly.map((e) => e.value.toDouble()).toList(),
                  caption: scope == 'current'
                      ? 'Current model version'
                      : 'All model versions',
                ),
                _AnalystMetric(
                  icon: Icons.emoji_events_rounded,
                  label: 'Most Recommended Crop',
                  value: topCrop,
                  caption: topCount == 0
                      ? 'No recommendations yet'
                      : 'Recommended $topCount times',
                ),
                _AnalystMetric(
                  icon: Icons.speed_rounded,
                  label: 'Average Model Score',
                  value: scored == 0
                      ? 'Not assessed'
                      : '${(analysisNumber(summary['average_model_score']) ?? 0).toStringAsFixed(1)}%',
                  caption: '$scored saved top-crop scores',
                ),
              ],
            ),
            if (topCount == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'No saved recommendations from this model yet. Submit a new analysis to populate these charts.',
                ),
              ),
            const SizedBox(height: 18),
            _AnalystColumns(
              mainFlex: 3,
              sideFlex: 2,
              breakpoint: 880,
              equalHeight: true,
              main: _CropFrequencyCard(entries: entries),
              side: _SuitabilityDistributionCard(
                values: distribution,
                total: scored,
              ),
            ),
            const SizedBox(height: 18),
            _AnalystColumns(
              mainFlex: 3,
              sideFlex: 2,
              breakpoint: 880,
              equalHeight: true,
              main: _RecentTrendCard(entries: monthly),
              side: _TrendInsightsCard(
                topCrop: topCrop,
                topCount: topCount,
                high: distribution[0],
                total: scored,
                monthly: monthly,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CropFrequencyCard extends StatelessWidget {
  final List<MapEntry<String, int>> entries;
  const _CropFrequencyCard({required this.entries});
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final shown = entries.take(7).toList();
    final maxValue = shown.isEmpty || shown.first.value == 0
        ? 1
        : shown.first.value;
    return _WebCard(
      key: const ValueKey('patterns-frequency-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AnalystChartHeading(
            title: 'Recommendation Frequency by Crop',
            subtitle: 'Frequency of recommended crops from saved analyses',
            scope: 'All Time',
            scopeIcon: Icons.calendar_today_outlined,
          ),
          SizedBox(height: 20),
          if (shown.isEmpty)
            SizedBox(
              height: 210,
              child: Center(
                child: Text(
                  'No saved crop recommendations in this scope.',
                  style: TextStyle(color: WebPortalColors.muted),
                ),
              ),
            )
          else
            ...shown.asMap().entries.map((row) {
              final e = row.value;
              final opacity = (1.0 - (row.key * 0.1).clamp(0.0, 0.45))
                  .toDouble();
              return Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    SizedBox(
                      width: MediaQuery.sizeOf(context).width < 600 ? 108 : 165,
                      child: Text(
                        e.key,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: e.value / maxValue,
                          minHeight: 15,
                          color: WebPortalColors.accent.withValues(
                            alpha: opacity,
                          ),
                          backgroundColor: WebPortalColors.tint,
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${e.value}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          if (shown.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                left: MediaQuery.sizeOf(context).width < 600 ? 120 : 177,
                top: 2,
              ),
              child: Text(
                'Number of Recommendations',
                style: TextStyle(fontSize: 12, color: WebPortalColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _SuitabilityDistributionCard extends StatelessWidget {
  final List<int> values;
  final int total;
  const _SuitabilityDistributionCard({
    required this.values,
    required this.total,
  });
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final labels = [
      'High (75% - 100%)',
      'Medium (50% - 75%)',
      'Low (25% - 50%)',
      'Very Low (0% - 25%)',
    ];
    final colors = [
      Color(0xFF067A3C),
      Color(0xFF36A65C),
      Color(0xFF79BF8D),
      Color(0xFFC7E6D0),
    ];
    return _WebCard(
      key: const ValueKey('patterns-distribution-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Model Score Distribution',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 5),
          Text(
            'Recorded model score bands, not agronomic grades',
            style: TextStyle(color: WebPortalColors.muted),
          ),
          SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, box) {
              final stack = box.maxWidth < 350;
              final chart = SizedBox(
                width: 140,
                height: 140,
                child: CustomPaint(
                  painter: _DonutPainter(values: values, colors: colors),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$total',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Total',
                          style: TextStyle(
                            color: WebPortalColors.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
              final legend = Column(
                children: List.generate(4, (i) {
                  final pct = total == 0
                      ? 0
                      : (values[i] * 100 / total).round();
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: colors[i],
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            labels[i],
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          '$pct% (${values[i]})',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              );
              if (stack) {
                return Column(
                  children: [
                    Center(child: chart),
                    SizedBox(height: 14),
                    legend,
                  ],
                );
              }
              return Row(
                children: [
                  chart,
                  SizedBox(width: 18),
                  Expanded(child: legend),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RecentTrendCard extends StatelessWidget {
  final List<MapEntry<DateTime, int>> entries;
  const _RecentTrendCard({required this.entries});
  @override
  Widget build(BuildContext context) => _WebCard(
    key: const ValueKey('patterns-trend-panel'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _AnalystChartHeading(
          title: 'Recent Trend',
          subtitle: 'Number of recommendations over time',
          scope: 'Latest 6 calendar months',
          scopeIcon: Icons.date_range_rounded,
        ),
        SizedBox(height: 18),
        SizedBox(
          height: 190,
          width: double.infinity,
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    'No dated analyses yet.',
                    style: TextStyle(color: WebPortalColors.muted),
                  ),
                )
              : CustomPaint(painter: _TrendLinePainter(entries)),
        ),
      ],
    ),
  );
}

class _TrendInsightsCard extends StatelessWidget {
  final String topCrop;
  final int topCount;
  final int high;
  final int total;
  final List<MapEntry<DateTime, int>> monthly;
  const _TrendInsightsCard({
    required this.topCrop,
    required this.topCount,
    required this.high,
    required this.total,
    required this.monthly,
  });
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final highPct = total == 0 ? 0 : (high * 100 / total).round();
    final increasing =
        monthly.length >= 2 && monthly.last.value >= monthly.first.value;
    return _WebCard(
      key: const ValueKey('patterns-insights-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Key Insights',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 18),
          _InsightRow(
            icon: Icons.eco_rounded,
            title: topCount == 0
                ? 'No recommendation leader yet.'
                : '$topCrop is the most frequently recommended crop,',
            subtitle: topCount == 0
                ? 'Run analyses to generate insights.'
                : 'appearing in $topCount ${topCount == 1 ? 'analysis' : 'analyses'}.',
          ),
          SizedBox(height: 16),
          _InsightRow(
            icon: Icons.bar_chart_rounded,
            title: total == 0
                ? 'No saved model scores yet.'
                : 'High model-score records account for $highPct%',
            subtitle: 'of all scored recommendations.',
          ),
          SizedBox(height: 16),
          _InsightRow(
            icon: Icons.trending_up_rounded,
            title: monthly.length < 2
                ? 'More dated records are needed to describe a trend.'
                : increasing
                ? 'Recommendation activity is stable or increasing.'
                : 'Recommendation activity has recently slowed.',
            subtitle: 'Compared with the first available month shown.',
          ),
        ],
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _InsightRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: WebPortalColors.tint.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: WebPortalColors.tint,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: WebPortalColors.accent, size: 19),
        ),
        SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
              SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(color: WebPortalColors.muted, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DonutPainter extends CustomPainter {
  final List<int> values;
  final List<Color> colors;
  _DonutPainter({required this.values, required this.colors});
  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<int>(0, (a, b) => a + b);
    final rect = Offset.zero & size;
    final stroke = size.shortestSide * .22;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    if (total == 0) {
      paint.color = Color(0xFFE7EFE9);
      canvas.drawArc(rect.deflate(stroke / 2), -1.5708, 6.2832, false, paint);
      return;
    }
    double start = -1.5708;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 6.2832;
      paint.color = colors[i];
      canvas.drawArc(rect.deflate(stroke / 2), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.values != values;
}

class _TrendLinePainter extends CustomPainter {
  final List<MapEntry<DateTime, int>> entries;
  _TrendLinePainter(this.entries);
  String _month(DateTime d) {
    final names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return "${names[d.month - 1]} '${d.year.toString().substring(2)}";
  }

  @override
  void paint(Canvas canvas, Size size) {
    final left = 34.0, right = 12.0, top = 10.0, bottom = 30.0;
    final chart = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final maxY = entries
        .map((e) => e.value)
        .fold<int>(1, (a, b) => a > b ? a : b)
        .clamp(3, 999);
    final grid = Paint()
      ..color = Color(0xFFE6ECE8)
      ..strokeWidth = 1;
    final label = TextPainter(textDirection: TextDirection.ltr);
    final step = (maxY / 4).ceil();
    for (var i = 0; i <= maxY; i += step) {
      final y = chart.bottom - chart.height * i / maxY;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
      label.text = TextSpan(
        text: '$i',
        style: TextStyle(fontSize: 10, color: WebPortalColors.muted),
      );
      label.layout();
      label.paint(canvas, Offset(4, y - 6));
    }
    final points = <Offset>[];
    for (var i = 0; i < entries.length; i++) {
      final x = entries.length == 1
          ? chart.center.dx
          : chart.left + chart.width * i / (entries.length - 1);
      final y = chart.bottom - chart.height * entries[i].value / maxY;
      points.add(Offset(x, y));
      label.text = TextSpan(
        text: _month(entries[i].key),
        style: TextStyle(fontSize: 10, color: WebPortalColors.muted),
      );
      label.layout();
      label.paint(canvas, Offset(x - label.width / 2, chart.bottom + 9));
    }
    if (points.isEmpty) return;
    final area = Path()
      ..moveTo(points.first.dx, chart.bottom)
      ..lineTo(points.first.dx, points.first.dy);
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      line.lineTo(points[i].dx, points[i].dy);
      area.lineTo(points[i].dx, points[i].dy);
    }
    area.lineTo(points.last.dx, chart.bottom);
    area.close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [green.withValues(alpha: .22), green.withValues(alpha: .02)],
        ).createShader(chart),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    for (final p in points) {
      canvas.drawCircle(p, 4.5, Paint()..color = green);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendLinePainter oldDelegate) =>
      oldDelegate.entries != entries;
}

class WebWeatherClimateScreen extends StatelessWidget {
  final AnalysisState state;
  const WebWeatherClimateScreen({super.key, required this.state});
  @override
  Widget build(BuildContext context) =>
      WebWeatherEnvironmentScreen(state: state, message: (_) {});
}

class WebSoilEnvironmentScreen extends StatelessWidget {
  final AnalysisState state;
  const WebSoilEnvironmentScreen({super.key, required this.state});
  @override
  Widget build(BuildContext context) =>
      WebWeatherEnvironmentScreen(state: state, message: (_) {});
}

class WebWeatherEnvironmentScreen extends StatelessWidget {
  final AnalysisState state;
  final ValueChanged<String> message;
  const WebWeatherEnvironmentScreen({
    super.key,
    required this.state,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final w = state.liveWeather ?? {};
    final d = state.result ?? {};
    final weatherSource = '${w['weather_source'] ?? 'Open-Meteo live weather'}';
    final condition =
        '${w['weather_description'] ?? w['condition'] ?? w['weather_condition'] ?? '--'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Live Weather & Climate',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Uses the same live weather source as the mobile app.',
                          style: TextStyle(color: WebPortalColors.muted),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.weatherLoading
                        ? null
                        : () async {
                            final err = await state.refreshLiveWeather();
                            if (err != null) message(err);
                          },
                    icon: Icon(Icons.refresh_rounded),
                    label: Text(
                      state.weatherLoading
                          ? 'Refreshing...'
                          : 'Refresh Live Weather',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: WebPortalColors.accent,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 18),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _MetricTile(
                    icon: Icons.thermostat_rounded,
                    label: 'Temperature',
                    value:
                        '${state.numText(w['temperature_c'] ?? w['temperature'])} °C',
                  ),
                  _MetricTile(
                    icon: Icons.water_drop_rounded,
                    label: 'Rainfall Today',
                    value:
                        '${state.numText(w['rainfall_today_mm'] ?? w['today_rainfall_mm'] ?? w['daily_rainfall_mm'] ?? w['current_precipitation_mm'])} mm',
                  ),
                  _MetricTile(
                    icon: Icons.opacity_rounded,
                    label: 'Humidity',
                    value:
                        '${state.numText(w['live_humidity'] ?? w['humidity'] ?? w['humidity_pct'])}%',
                  ),
                  _MetricTile(
                    icon: Icons.air_rounded,
                    label: 'Wind',
                    value:
                        '${state.numText(w['max_wind_next_6h_kmh'] ?? w['wind_kmh'] ?? w['wind_speed'] ?? w['wind_speed_kmh'])} km/h',
                  ),
                  _MetricTile(
                    icon: Icons.cloud_rounded,
                    label: 'Condition',
                    value: condition,
                  ),
                  _MetricTile(
                    icon: Icons.schedule_rounded,
                    label: 'Rain Next 3h',
                    value: '${state.numText(w['rain_next_3h_mm'])} mm',
                  ),
                ],
              ),
              SizedBox(height: 14),
              Text(
                'Source: $weatherSource • ${state.selectedPlaceName}',
                style: TextStyle(
                  color: WebPortalColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 18),
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Soil & Environmental Indicators',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 8),
              Text(
                'Environmental factors are filled after running an area analysis.',
                style: TextStyle(color: WebPortalColors.muted),
              ),
              SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _MetricTile(
                      compact: true,
                      icon: Icons.water_drop_rounded,
                      label: 'Annual Rainfall (5-year mean)',
                      value:
                          '${state.numText(annualRainfallFactorView({}, d).value)} mm/year',
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _MetricTile(
                      compact: true,
                      icon: Icons.terrain_rounded,
                      label: 'Elevation',
                      value:
                          '${state.numText(d['elevation_m'] ?? d['elevation'])} m',
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _MetricTile(
                      compact: true,
                      icon: Icons.show_chart_rounded,
                      label: 'Slope',
                      value: '${state.numText(d['slope_pct'] ?? d['slope'])}%',
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _MetricTile(
                      compact: true,
                      icon: Icons.eco_rounded,
                      label: 'NDVI',
                      value: (() {
                        final n = d['ndvi'] is num
                            ? (d['ndvi'] as num).toDouble()
                            : double.tryParse('${d['ndvi']}');
                        return n == null ? '--' : n.toStringAsFixed(3);
                      })(),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _MetricTile(
                      compact: true,
                      icon: Icons.science_rounded,
                      label: 'Soil pH',
                      value: '${d['soil_ph'] ?? d['ph'] ?? '--'}',
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _MetricTile(
                      compact: true,
                      icon: Icons.landscape_rounded,
                      label: 'Land Cover',
                      value: '${d['land_cover'] ?? d['land_status'] ?? '--'}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: 18),
        _WebDistributionPanel(state: state),
      ],
    );
  }
}

class WebSettingsScreen extends StatefulWidget {
  final AnalysisState state;
  const WebSettingsScreen({super.key, required this.state});

  @override
  State<WebSettingsScreen> createState() => _WebSettingsScreenState();
}

class _WebSettingsScreenState extends State<WebSettingsScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _locationController;
  bool _saving = false;
  bool _pushEnabled = false;
  bool _pushBusy = false;
  bool _accountBusy = false;
  String? _pushError;

  AnalysisState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: '${state.currentUser?['username'] ?? 'User'}',
    );
    _locationController = TextEditingController(
      text: '${state.currentUser?['location'] ?? state.selectedPlaceName}',
    );
    PushNotifications.enabled().then((value) {
      if (mounted) setState(() => _pushEnabled = value);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      final currentRole =
          '${state.currentUser?['role'] ?? state.currentUser?['account_type'] ?? 'analyst'}';
      final updated = await state.api.updateProfile(
        username: _nameController.text.trim().isEmpty
            ? 'User'
            : _nameController.text.trim(),
        role: currentRole,
        location: _locationController.text.trim(),
      );
      state.updateCurrentProfile(updated);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Profile updated.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update profile: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _accountAction(bool delete) async {
    if (_accountBusy) return;
    final password = TextEditingController();
    bool? google;
    try {
      google = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            delete ? 'Delete your account?' : 'Deactivate your account?',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  delete
                      ? 'This permanently removes your farms, boundaries, coordinates, analyses, photos and reports. Anonymized audit decisions are retained. This cannot be undone.'
                      : 'You will be signed out and lose access until an administrator reactivates the account.',
                ),
                SizedBox(height: 16),
                TextField(
                  controller: password,
                  obscureText: true,
                  autofillHints: [AutofillHints.password],
                  decoration: InputDecoration(labelText: 'Current password'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel'),
            ),
            if (state.currentUser?['google_linked'] == true &&
                FirebaseIdentity.googleConfigured)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text('Confirm with linked Google'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(delete ? 'Confirm deletion' : 'Confirm deactivation'),
            ),
          ],
        ),
      );
      if (google == null || !mounted) return;
      setState(() => _accountBusy = true);
      final proof = google ? await FirebaseIdentity.googleProof() : null;
      await state.api.closeWebAccount(
        delete: delete,
        password: google ? null : password.text,
        googleProof: proof,
      );
      await PushNotifications.stop();
      state.clearUserData();
      PortalRoutes.go('/');
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    } finally {
      password.dispose();
      if (mounted) setState(() => _accountBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _WebCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Settings',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 12),
        Text(
          'Signed in as ${state.currentUser?['email'] ?? '--'}',
          style: TextStyle(color: WebPortalColors.muted),
        ),
        SizedBox(height: 18),
        Text(
          'Edit Profile',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 10),
        TextField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: 'Display Name',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        SizedBox(height: 10),
        TextField(
          controller: _locationController,
          decoration: InputDecoration(
            labelText: 'Location',
            prefixIcon: Icon(Icons.location_on_outlined),
          ),
        ),
        SizedBox(height: 14),
        SizedBox(
          width: 210,
          child: FilledButton.icon(
            onPressed: _saving ? null : _saveProfile,
            icon: _saving
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : 'Save Profile'),
          ),
        ),
        SizedBox(height: 24),
        IdentityProfileSection(
          key: ValueKey('web-identity-${state.currentUser?['id']}'),
          state: state,
        ),
        SizedBox(height: 24),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Analysis and review push alerts'),
          subtitle: Text(
            _pushError ??
                (PushNotifications.configured
                    ? 'Receive analysis and review alerts with browser permission. Weather advisories remain in the app.'
                    : 'Background alerts are currently unavailable. Activity remains available in the app.'),
          ),
          value: _pushEnabled,
          onChanged: !PushNotifications.configured || _pushBusy
              ? null
              : (value) async {
                  setState(() {
                    _pushBusy = true;
                    _pushError = null;
                  });
                  try {
                    await PushNotifications.setEnabled(state.api, value);
                    if (mounted) setState(() => _pushEnabled = value);
                  } catch (error) {
                    if (mounted) {
                      setState(() => _pushError = friendlyErrorMessage(error));
                    }
                  } finally {
                    if (mounted) setState(() => _pushBusy = false);
                  }
                },
        ),
        SizedBox(height: 24),
        Text(
          'Account Actions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _accountBusy ? null : () => _accountAction(false),
                icon: Icon(Icons.pause_circle_outline),
                label: Text('Deactivate Account'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _accountBusy ? null : () => _accountAction(true),
                icon: Icon(Icons.delete_outline),
                label: Text('Delete Account'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool compact;
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: compact ? null : 180,
    padding: EdgeInsets.all(compact ? 10 : 16),
    decoration: BoxDecoration(
      color: WebPortalColors.canvas,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Color(0xFFE4ECE6)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: WebPortalColors.accent, size: compact ? 16 : 24),
        SizedBox(height: compact ? 6 : 10),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: WebPortalColors.muted,
            fontSize: compact ? 11 : 14,
          ),
        ),
        SizedBox(height: compact ? 4 : 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 16 : 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _WebEnvironmentPanel extends StatelessWidget {
  final AnalysisState state;
  final bool compact;
  const _WebEnvironmentPanel({required this.state, this.compact = false});

  String _num3(dynamic value) {
    final n = value is num ? value.toDouble() : double.tryParse('$value');
    return n == null ? '--' : n.toStringAsFixed(3);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final d = state.result ?? {};
    final rainfall = annualRainfallFactorView({}, d).value;
    final slope = d['slope_pct'] ?? d['slope'];
    final elevation = d['elevation_m'] ?? d['elevation'];
    final ndviText = _num3(d['ndvi']);
    final hasData = d.isNotEmpty;
    return _WebCard(
      padding: compact ? EdgeInsets.all(14) : EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Environmental Overview',
            style: TextStyle(
              fontSize: compact ? 16 : 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          Text(
            'Key environmental factors for the selected area',
            style: TextStyle(
              color: WebPortalColors.muted,
              fontSize: compact ? 12 : 14,
            ),
          ),
          SizedBox(height: compact ? 6 : 12),
          _InfoLine(
            icon: Icons.water_drop_rounded,
            title: 'Annual Rainfall (5-year mean)',
            value: hasData ? '${state.numText(rainfall)} mm/year' : '--',
          ),
          _InfoLine(
            icon: Icons.show_chart_rounded,
            title: 'Slope',
            value: hasData ? '${state.numText(slope)}%' : '--',
          ),
          _InfoLine(
            icon: Icons.terrain_rounded,
            title: 'Elevation',
            value: hasData ? '${state.numText(elevation)} m' : '--',
          ),
          _InfoLine(icon: Icons.eco_rounded, title: 'NDVI', value: ndviText),
          if (!compact)
            _InfoLine(
              icon: Icons.landscape_rounded,
              title: 'Land Cover',
              value: '${d['land_cover'] ?? d['land_status'] ?? '--'}',
            ),
        ],
      ),
    );
  }
}

class _WebDistributionPanel extends StatelessWidget {
  final AnalysisState state;
  const _WebDistributionPanel({required this.state});
  @override
  Widget build(BuildContext context) => _WebCard(
    padding: EdgeInsets.all(22),
    child: WebModelScoreDistribution(records: state.historyRecords),
  );
}
