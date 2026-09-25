part of '../../main.dart';

class WebCropTrendsScreen extends StatelessWidget {
  final AnalysisState state;
  const WebCropTrendsScreen({super.key, required this.state});

  String _topCropFromRecord(Map<String, dynamic> r) {
    final direct =
        r['crop_recommendation'] ??
        r['recommended_crop'] ??
        r['predicted_crop'] ??
        r['crop'];
    if (direct != null && '$direct'.trim().isNotEmpty && '$direct' != '--') {
      return '$direct';
    }
    final top = r['top_crop_recommendations'];
    if (top is List && top.isNotEmpty && top.first is Map) {
      final first = top.first as Map;
      final name = first['crop'] ?? first['name'];
      if (name != null && '$name'.trim().isNotEmpty) return '$name';
    }
    return 'Unknown';
  }

  double _scoreFromRecord(Map<String, dynamic> r) {
    final raw =
        r['suitability_score'] ??
        r['crop_compatibility_pct'] ??
        r['compatibility_pct'] ??
        r['suitability'] ??
        r['score'];
    if (raw is num) return raw.toDouble();
    return double.tryParse('$raw'.replaceAll('%', '')) ?? 0;
  }

  DateTime? _dateFromRecord(Map<String, dynamic> r) {
    final raw =
        r['date'] ??
        r['analyzed_at'] ??
        r['saved_at'] ??
        r['report_created_at'] ??
        r['created_at'] ??
        r['analysis_date'] ??
        r['timestamp'];
    return raw == null ? null : DateTime.tryParse('$raw');
  }

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    final monthly = <DateTime, int>{};
    double totalScore = 0;
    int scored = 0;
    int high = 0, medium = 0, low = 0, veryLow = 0;

    final trendRecords = state.officialTrendRecords;
    for (final r in trendRecords) {
      final crop = _topCropFromRecord(r);
      counts[crop] = (counts[crop] ?? 0) + 1;
      final score = _scoreFromRecord(r);
      if (score > 0) {
        totalScore += score;
        scored++;
        if (score >= 75) {
          high++;
        } else if (score >= 50) {
          medium++;
        } else if (score >= 25) {
          low++;
        } else {
          veryLow++;
        }
      }
      final date = _dateFromRecord(r);
      if (date != null) {
        final key = DateTime(date.year, date.month);
        monthly[key] = (monthly[key] ?? 0) + 1;
      }
    }

    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCrop = entries.isEmpty ? 'No data' : entries.first.key;
    final topCount = entries.isEmpty ? 0 : entries.first.value;
    final average = scored == 0 ? 0.0 : totalScore / scored;
    final distribution = [high, medium, low, veryLow];
    final total = trendRecords.length;
    final monthEntries = monthly.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final recentMonths = monthEntries.length <= 6
        ? monthEntries
        : monthEntries.sublist(monthEntries.length - 6);

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 1050;
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 18,
                runSpacing: 18,
                children: [
                  _TrendSummaryCard(
                    icon: Icons.article_rounded,
                    label: 'Total Saved Analyses',
                    value: '$total',
                    caption: 'Across all analyzed areas',
                    width: narrow
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 36) / 3,
                  ),
                  _TrendSummaryCard(
                    icon: Icons.emoji_events_rounded,
                    label: 'Most Recommended Crop',
                    value: topCrop,
                    caption: topCount == 0
                        ? 'No recommendations yet'
                        : 'Recommended $topCount ${topCount == 1 ? 'time' : 'times'}',
                    width: narrow
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 36) / 3,
                  ),
                  _TrendSummaryCard(
                    icon: Icons.speed_rounded,
                    label: 'Average Suitability',
                    value: '${average.toStringAsFixed(average == 0 ? 0 : 1)}%',
                    caption: 'Across all crop recommendations',
                    width: narrow
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 36) / 3,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (narrow) ...[
                _CropFrequencyCard(entries: entries),
                const SizedBox(height: 18),
                _SuitabilityDistributionCard(
                  values: distribution,
                  total: scored,
                ),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _CropFrequencyCard(entries: entries),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      flex: 2,
                      child: _SuitabilityDistributionCard(
                        values: distribution,
                        total: scored,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 18),
              if (narrow) ...[
                _RecentTrendCard(entries: recentMonths),
                const SizedBox(height: 18),
                _TrendInsightsCard(
                  topCrop: topCrop,
                  topCount: topCount,
                  high: high,
                  total: scored,
                  monthly: recentMonths,
                ),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _RecentTrendCard(entries: recentMonths),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      flex: 2,
                      child: _TrendInsightsCard(
                        topCrop: topCrop,
                        topCount: topCount,
                        high: high,
                        total: scored,
                        monthly: recentMonths,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TrendSummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String caption;
  final double width;
  const _TrendSummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    required this.width,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: _WebCard(
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: softGreen,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: green, size: 31),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 25,
                    color: green,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CropFrequencyCard extends StatelessWidget {
  final List<MapEntry<String, int>> entries;
  const _CropFrequencyCard({required this.entries});
  @override
  Widget build(BuildContext context) {
    final shown = entries.take(6).toList();
    final maxValue = shown.isEmpty ? 1 : shown.first.value;
    return _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recommendation Frequency by Crop',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Frequency of recommended crops from saved analyses',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFDCE7DF)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today_outlined, color: green, size: 16),
                    SizedBox(width: 7),
                    Text(
                      'All Time',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (shown.isEmpty)
            const SizedBox(
              height: 210,
              child: Center(
                child: Text(
                  'Run analyses to populate crop trends.',
                  style: TextStyle(color: Colors.black45),
                ),
              ),
            )
          else
            ...shown.asMap().entries.map((row) {
              final e = row.value;
              final opacity = (1.0 - (row.key * 0.1).clamp(0.0, 0.45))
                  .toDouble();
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 190,
                      child: Text(
                        e.key,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: e.value / maxValue,
                          minHeight: 15,
                          color: green.withValues(alpha: opacity),
                          backgroundColor: softGreen,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${e.value}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              );
            }),
          if (shown.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 202, top: 2),
              child: Text(
                'Number of Recommendations',
                style: TextStyle(fontSize: 12, color: Colors.black45),
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
    const labels = [
      'High (75% - 100%)',
      'Medium (50% - 75%)',
      'Low (25% - 50%)',
      'Very Low (0% - 25%)',
    ];
    const colors = [
      Color(0xFF067A3C),
      Color(0xFF36A65C),
      Color(0xFF79BF8D),
      Color(0xFFC7E6D0),
    ];
    return _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Suitability Distribution',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          const Text(
            'Distribution of suitability levels',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, box) {
              final stack = box.maxWidth < 470;
              final chart = SizedBox(
                width: 195,
                height: 195,
                child: CustomPaint(
                  painter: _DonutPainter(values: values, colors: colors),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$total',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Text(
                          'Total',
                          style: TextStyle(
                            color: Colors.black54,
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
                    padding: const EdgeInsets.symmetric(vertical: 8),
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
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            labels[i],
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$pct% (${values[i]})',
                          style: const TextStyle(fontWeight: FontWeight.w900),
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
                    const SizedBox(height: 14),
                    legend,
                  ],
                );
              }
              return Row(
                children: [
                  chart,
                  const SizedBox(width: 18),
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recent Trend',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Number of recommendations over time',
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFDCE7DF)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.date_range_rounded, color: green, size: 16),
                  SizedBox(width: 7),
                  Text(
                    'Last 6 Months',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 190,
          child: entries.isEmpty
              ? const Center(
                  child: Text(
                    'No dated analyses yet.',
                    style: TextStyle(color: Colors.black45),
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
    final highPct = total == 0 ? 0 : (high * 100 / total).round();
    final increasing =
        monthly.length >= 2 && monthly.last.value >= monthly.first.value;
    return _WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Key Insights',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 18),
          _InsightRow(
            icon: Icons.eco_rounded,
            title: topCount == 0
                ? 'No recommendation leader yet.'
                : '$topCrop is the most frequently recommended crop,',
            subtitle: topCount == 0
                ? 'Run analyses to generate insights.'
                : 'appearing in $topCount ${topCount == 1 ? 'analysis' : 'analyses'}.',
          ),
          const SizedBox(height: 16),
          _InsightRow(
            icon: Icons.bar_chart_rounded,
            title: 'High suitability areas account for $highPct%',
            subtitle: 'of all scored recommendations.',
          ),
          const SizedBox(height: 16),
          _InsightRow(
            icon: Icons.trending_up_rounded,
            title: increasing
                ? 'Recommendation activity is stable or increasing.'
                : 'Recommendation activity has recently slowed.',
            subtitle: 'Based on the latest available monthly records.',
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
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: softGreen, shape: BoxShape.circle),
        child: Icon(icon, color: green, size: 24),
      ),
      const SizedBox(width: 13),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.black54, height: 1.35),
            ),
          ],
        ),
      ),
    ],
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
      paint.color = const Color(0xFFE7EFE9);
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
    const names = [
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
    const left = 34.0, right = 12.0, top = 10.0, bottom = 30.0;
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
      ..color = const Color(0xFFE6ECE8)
      ..strokeWidth = 1;
    final label = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i <= maxY; i++) {
      final y = chart.bottom - chart.height * i / maxY;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
      label.text = TextSpan(
        text: '$i',
        style: const TextStyle(fontSize: 10, color: Colors.black45),
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
        style: const TextStyle(fontSize: 10, color: Colors.black54),
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
                  const Expanded(
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
                          style: TextStyle(color: Colors.black54),
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
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(
                      state.weatherLoading
                          ? 'Refreshing...'
                          : 'Refresh Live Weather',
                    ),
                    style: OutlinedButton.styleFrom(foregroundColor: green),
                  ),
                ],
              ),
              const SizedBox(height: 18),
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
              const SizedBox(height: 14),
              Text(
                'Source: $weatherSource • ${state.selectedPlaceName}',
                style: const TextStyle(
                  color: Colors.black45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Soil & Environmental Indicators',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'Environmental factors are filled after running an area analysis.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _MetricTile(
                      compact: true,
                      icon: Icons.water_drop_rounded,
                      label: 'Rainfall (30d)',
                      value:
                          '${state.numText(d['rainfall_30d'] ?? d['rainfall_mm'] ?? w['rainfall_mm'])} mm',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricTile(
                      compact: true,
                      icon: Icons.terrain_rounded,
                      label: 'Elevation',
                      value:
                          '${state.numText(d['elevation_m'] ?? d['elevation'])} m',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricTile(
                      compact: true,
                      icon: Icons.show_chart_rounded,
                      label: 'Slope',
                      value: '${state.numText(d['slope_pct'] ?? d['slope'])}%',
                    ),
                  ),
                  const SizedBox(width: 10),
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricTile(
                      compact: true,
                      icon: Icons.science_rounded,
                      label: 'Soil pH',
                      value: '${d['soil_ph'] ?? d['ph'] ?? '--'}',
                    ),
                  ),
                  const SizedBox(width: 10),
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
        const SizedBox(height: 18),
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
        ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
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

  Future<void> _deactivate() async {
    await state.api.deactivateAccount();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Account deactivated. Please sign in again when reactivated.',
          ),
        ),
      );
    }
  }

  Future<void> _deleteAccount() async {
    await state.api.deleteAccount();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account deleted. Please reload the app.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => _WebCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Settings',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        Text(
          'Signed in as ${state.currentUser?['email'] ?? '--'}',
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 18),
        const Text(
          'Edit Profile',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Display Name',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _locationController,
          decoration: const InputDecoration(
            labelText: 'Location',
            prefixIcon: Icon(Icons.location_on_outlined),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: 210,
          child: FilledButton.icon(
            onPressed: _saving ? null : _saveProfile,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : 'Save Profile'),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Account Actions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _deactivate,
                icon: const Icon(Icons.pause_circle_outline),
                label: const Text('Deactivate Account'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _deleteAccount,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete Account'),
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
      color: const Color(0xFFF7FAF7),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE4ECE6)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: green, size: compact ? 16 : 24),
        SizedBox(height: compact ? 6 : 10),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.black54, fontSize: compact ? 11 : 14),
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
    final d = state.result ?? {};
    final rainfall =
        d['rainfall_monthly_mm'] ??
        d['monthly_rainfall_mm'] ??
        d['rainfall_30d_mm'] ??
        d['rainfall_30d'] ??
        d['rainfall_mm'];
    final slope = d['slope_pct'] ?? d['slope'];
    final elevation = d['elevation_m'] ?? d['elevation'];
    final ndviText = _num3(d['ndvi']);
    final hasData = d.isNotEmpty;
    return _WebCard(
      padding: compact ? const EdgeInsets.all(14) : const EdgeInsets.all(22),
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
              color: Colors.black54,
              fontSize: compact ? 12 : 14,
            ),
          ),
          SizedBox(height: compact ? 6 : 12),
          _InfoLine(
            icon: Icons.water_drop_rounded,
            title: 'Rainfall (30d)',
            value: hasData ? '${state.numText(rainfall)} mm' : '--',
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
  final bool compact;
  const _WebDistributionPanel({required this.state, this.compact = false});
  @override
  Widget build(BuildContext context) => _WebCard(
    padding: compact ? const EdgeInsets.all(14) : const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Suitability Distribution',
          style: TextStyle(
            fontSize: compact ? 16 : 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: compact ? 8 : 10),
        Text(
          'Distribution of suitability levels based on history records.',
          style: TextStyle(color: Colors.black54, fontSize: compact ? 12 : 14),
        ),
        SizedBox(height: compact ? 8 : 12),
        Center(
          child: SizedBox(
            width: compact ? 108 : 148,
            height: compact ? 108 : 148,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: state.historyRecords.isEmpty ? .05 : .72,
                  strokeWidth: compact ? 11 : 16,
                  color: green,
                  backgroundColor: softGreen,
                ),
                Text(
                  '${state.historyRecords.length}\nTotal',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: compact ? 14 : 22,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: compact ? 6 : 10),
        const _LegendDot(color: Color(0xFF1FA463), label: 'Highly Suitable'),
        const _LegendDot(
          color: Color(0xFF8BDD75),
          label: 'Moderately Suitable',
        ),
        const _LegendDot(
          color: Color(0xFFE9A829),
          label: 'Marginally Suitable',
        ),
      ],
    ),
  );
}
