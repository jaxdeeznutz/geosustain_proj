part of '../main.dart';

class HomePage extends StatelessWidget {
  final AnalysisState state;
  final ValueChanged<int> go;
  final VoidCallback logout;
  final ValueChanged<String> message;
  const HomePage({
    super.key,
    required this.state,
    required this.go,
    required this.logout,
    required this.message,
  });
  Future<void> openRecord(Map<String, dynamic> record) async {
    final error = await state.selectAnalysis(record);
    if (error != null) {
      message(error);
      return;
    }
    go(2);
  }

  void crops(BuildContext context) => showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Supported crops',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const Text(
                'Seven Panabo commodities. New results show which factors could be assessed.',
              ),
              for (final name in supportedCropNames)
                ListTile(leading: CropArtwork(name), title: Text(name)),
            ],
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final pending = state.historyRecords
        .where((r) => r['verification_status'] == 'pending')
        .length;
    final weather = state.liveWeather;
    return GeoSafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            state.refreshFarms(),
            state.refreshHistoryData(),
            state.refreshLiveWeather(),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            GeoSustainHeader(title: 'Home', state: state),
            Container(
              padding: const EdgeInsets.all(21),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                image: const DecorationImage(
                  image: AssetImage('assets/images/dashboard/farm_hero.png'),
                  fit: BoxFit.cover,
                ),
                color: darkGreen,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome, ${state.userName()}!',
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Understand\nyour land.',
                    style: TextStyle(
                      fontSize: 25,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    'Plan your farm.',
                    style: TextStyle(
                      fontSize: 25,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF79F1BE),
                    ),
                  ),
                  const SizedBox(height: 9),
                  const SizedBox(
                    width: 230,
                    child: Text(
                      'Map your boundary, discover suitable crops, and plan with confidence.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 230,
                    child: FilledButton.icon(
                      onPressed: () =>
                          showLandMethodPicker(context, state, () => go(2)),
                      icon: const Icon(Icons.eco),
                      label: const Text('Get Started'),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ReferenceStat(
                    '${state.farms.length}',
                    'Saved Farms',
                    Icons.agriculture_outlined,
                    () => go(1),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: ReferenceStat(
                    '$pending',
                    'Pending Reviews',
                    Icons.description_outlined,
                    () => go(3),
                    tint: const Color(0xFFFFF0CF),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: ReferenceStat(
                    '${supportedCropNames.length}',
                    'Supported Crops',
                    Icons.eco_outlined,
                    () => crops(context),
                    tint: const Color(0xFFDDF2FC),
                  ),
                ),
              ],
            ),
            if (state.historyError != null || state.farmsError != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(state.historyError ?? state.farmsError!),
              ),
            _heading(
              'Quick Actions',
              () => showLandMethodPicker(context, state, () => go(2)),
            ),
            LayoutBuilder(
              builder: (context, c) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in [
                    (
                      'Create a Farm Boundary',
                      'Walk or draw your farm area.',
                      Icons.map_outlined,
                      () => openLandMethod(context, state, true, () => go(2)),
                    ),
                    (
                      'Analyze Land Using a Polygon',
                      'Explore crop suitability.',
                      Icons.bar_chart,
                      () => openLandMethod(context, state, false, () => go(2)),
                    ),
                    (
                      'View My Farms',
                      'Manage your saved areas.',
                      Icons.search,
                      () => go(1),
                    ),
                    (
                      'Analysis History',
                      'Check your previous results.',
                      Icons.history,
                      () => go(3),
                    ),
                  ].indexed)
                    SizedBox(
                      width:
                          c.maxWidth >= 350 &&
                              MediaQuery.textScalerOf(context).scale(1) <= 1.2
                          ? (c.maxWidth - 24) / 4
                          : (c.maxWidth - 8) / 2,
                      child: ReferenceAction(
                        item.$2.$1,
                        item.$2.$2,
                        item.$2.$3,
                        item.$2.$4,
                        blue: item.$1.isOdd,
                        compact:
                            c.maxWidth >= 350 &&
                            c.maxWidth < 600 &&
                            MediaQuery.textScalerOf(context).scale(1) <= 1.2,
                      ),
                    ),
                ],
              ),
            ),
            _heading('Recent Activity', () => go(3)),
            if (state.historyRecords.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Your completed analyses will appear here.'),
                ),
              ),
            for (final row in newestAnalysisRecords(
              state.historyRecords,
            ).take(3))
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(9),
                  leading: BoundaryThumbnail(row, size: 61),
                  title: Text(
                    '${row['farm_name'] ?? row['place_name'] ?? 'Unnamed area'}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    '${analysisDateText(analysisRecordDate(row))}\n${_farmReviewLabel(row['verification_status'])}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openRecord(row),
                ),
              ),
            _heading('Current Weather', () async {
              final error = await state.refreshLiveWeather();
              if (error != null) message(error);
            }),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  colors: [Color(0xFFDFF4FC), Colors.white],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.wb_cloudy_outlined,
                        size: 43,
                        color: Color(0xFF4791B5),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          weather == null
                              ? 'Weather unavailable'
                              : '${state.numText(weather['temperature_c'])} C',
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            color: darkGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    weather == null
                        ? 'Pull to refresh. Live conditions are separate from saved analyses.'
                        : '${weather['weather_description'] ?? 'Conditions unavailable'} | Humidity ${state.numText(weather['live_humidity'])}% | Wind ${state.numText(weather['wind_speed_kmh'])} km/h',
                  ),
                  Text(
                    'Panabo City | ${weather?['updated_at'] ?? weather?['observed_at'] ?? 'Update time unavailable'}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF53636B),
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

  Widget _heading(String title, VoidCallback tap) => Padding(
    padding: const EdgeInsets.fromLTRB(5, 18, 0, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: darkGreen,
            ),
          ),
        ),
        TextButton(
          onPressed: tap,
          child: Text(title == 'Current Weather' ? 'Refresh' : 'See all'),
        ),
      ],
    ),
  );
}

class SmartConditionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color bgColor;

  const SmartConditionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: green, size: 23),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10.5, color: Colors.black87),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class AiRecommendationHomeCard extends StatelessWidget {
  final AnalysisState state;
  final VoidCallback openAnalyze;
  const AiRecommendationHomeCard({
    super.key,
    required this.state,
    required this.openAnalyze,
  });

  @override
  Widget build(BuildContext context) {
    final data = state.result;
    final crop = '${data?['predicted_crop'] ?? '--'}';
    final note = data == null
        ? 'Select a point or draw a boundary on the Map page to generate AI crop recommendation.'
        : 'Recommended crop for ${data['place_name'] ?? 'the selected area'}: $crop';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF08783A), Color(0xFF064E2B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: green.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '✨ AI Recommendation',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton(
                onPressed: openAnalyze,
                child: const Text(
                  'Analyze',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(note, style: const TextStyle(color: Colors.white, height: 1.4)),
          if (data != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Suitability: ${displaySuitability(data)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class InfrastructureHomeOverview extends StatelessWidget {
  final AnalysisState state;
  final VoidCallback openMap;
  const InfrastructureHomeOverview({
    super.key,
    required this.state,
    required this.openMap,
  });

  @override
  Widget build(BuildContext context) {
    final data = state.result;
    final status =
        '${data?['infrastructure_suitability'] ?? 'Not yet analyzed'}';
    final recommendation =
        '${data?['infrastructure_status'] ?? 'Analyze a point or boundary to check infrastructure suitability.'}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Infrastructure Suitability',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                TextButton(
                  onPressed: openMap,
                  child: const Text(
                    'View on Map',
                    style: TextStyle(color: green, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: 92,
                  height: 80,
                  decoration: BoxDecoration(
                    color: softGreen,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.apartment_rounded,
                    color: green,
                    size: 38,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data == null ? '🟡 $status' : '✅ $status',
                        style: TextStyle(
                          color: data == null
                              ? const Color(0xFFE9A829)
                              : infrastructureColor(data),
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        recommendation,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('Slope: ${state.numText(data?['slope_pct'])}%'),
                      Text(
                        'Elevation: ${state.numText(data?['elevation_m'])} m',
                      ),
                      Text.rich(
                        TextSpan(
                          text: 'Risk Level: ',
                          children: [
                            TextSpan(
                              text: data == null
                                  ? '--'
                                  : '${data['risk_level'] ?? data['infrastructure_risk'] ?? 'Low'}',
                              style: const TextStyle(
                                color: green,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class HomeAlertsCard extends StatelessWidget {
  final AnalysisState state;
  const HomeAlertsCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final alerts = WeatherAlertLogic.build(
      state.liveWeather,
      loading: state.weatherLoading,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Alerts & Warnings',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: softGreen,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Live Weather',
                    style: TextStyle(
                      color: green,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              WeatherAlertLogic.summary(
                state.liveWeather,
                loading: state.weatherLoading,
              ),
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 380;
                final singleAlert = alerts.length == 1;

                if (singleAlert) {
                  final a = alerts.first;
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: compact ? constraints.maxWidth * 0.78 : 230,
                      ),
                      child: HomeAlertTile(
                        icon: a.icon,
                        title: a.title,
                        body: a.body,
                        bgColor: a.bgColor,
                      ),
                    ),
                  );
                }

                if (compact) {
                  return Column(
                    children: alerts
                        .map(
                          (a) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SizedBox(
                              width: double.infinity,
                              child: HomeAlertTile(
                                icon: a.icon,
                                title: a.title,
                                body: a.body,
                                bgColor: a.bgColor,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: alerts.asMap().entries.map((entry) {
                    final a = entry.value;
                    final isLast = entry.key == alerts.length - 1;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: isLast ? 0 : 8),
                        child: HomeAlertTile(
                          icon: a.icon,
                          title: a.title,
                          body: a.body,
                          bgColor: a.bgColor,
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class HomeAlertData {
  final IconData icon;
  final String title;
  final String body;
  final Color bgColor;
  const HomeAlertData(this.icon, this.title, this.body, this.bgColor);
}

class WeatherAlertLogic {
  static List<HomeAlertData> build(
    Map<String, dynamic>? weather, {
    bool loading = false,
  }) {
    if (loading && weather == null) {
      return const [
        HomeAlertData(
          Icons.sync_rounded,
          'Updating Forecast',
          'Checking live weather for the next few hours.',
          Color(0xFFEAF8EA),
        ),
      ];
    }
    if (weather == null) {
      return const [
        HomeAlertData(
          Icons.notifications_active_outlined,
          'Live Weather Ready',
          'Tap Refresh to load real-time rainfall, wind, and storm advisories.',
          Color(0xFFEAF8EA),
        ),
      ];
    }

    final next3Rain = _num(weather['rain_next_3h_mm']);
    final next6Rain = _num(weather['rain_next_6h_mm']);
    final prob3 = _num(weather['rain_probability_next_3h']);
    final prob6 = _num(weather['rain_probability_next_6h']);
    final wind = _num(
      weather['max_wind_next_6h_kmh'] ?? weather['wind_speed_kmh'],
    );
    final temp = _num(
      weather['max_temp_next_6h_c'] ?? weather['temperature_c'],
    );
    final currentRain = _num(weather['current_precipitation_mm']);
    final codes = _codes(weather['weather_codes_next_6h']);
    final hasThunder =
        codes.any((c) => c == 95 || c == 96 || c == 99) ||
        '${weather['weather_description']}'.toLowerCase().contains('thunder');

    final alerts = <HomeAlertData>[];
    if (hasThunder) {
      alerts.add(
        const HomeAlertData(
          Icons.thunderstorm_outlined,
          'Thunderstorm Advisory',
          'Thunderstorm conditions may occur within the next few hours.',
          Color(0xFFFFF6DD),
        ),
      );
    }
    if (next3Rain >= 15 || prob3 >= 80) {
      alerts.add(
        const HomeAlertData(
          Icons.water_drop_outlined,
          'Heavy Rainfall Soon',
          'Heavy rainfall is possible within the next 3 hours.',
          Color(0xFFEAF2FF),
        ),
      );
    } else if (next6Rain >= 8 || prob6 >= 60 || currentRain > 0) {
      alerts.add(
        const HomeAlertData(
          Icons.umbrella_outlined,
          'Rain Expected',
          'Light to moderate rain may occur in the next few hours.',
          Color(0xFFEAF2FF),
        ),
      );
    }
    if (next6Rain >= 25) {
      alerts.add(
        const HomeAlertData(
          Icons.flood_outlined,
          'Flooding Caution',
          'Continuous rainfall may increase field flooding risk.',
          Color(0xFFFFE3E0),
        ),
      );
    }
    if (wind >= 39) {
      alerts.add(
        const HomeAlertData(
          Icons.air_rounded,
          'Strong Winds',
          'Secure field materials and check exposed structures.',
          Color(0xFFF4F8FF),
        ),
      );
    }
    if (temp >= 33) {
      alerts.add(
        const HomeAlertData(
          Icons.local_fire_department_outlined,
          'High Heat Index',
          'Avoid prolonged field work during peak heat hours.',
          Color(0xFFFFF1E8),
        ),
      );
    }
    if (alerts.isEmpty) {
      final condition = '${weather['weather_description'] ?? 'stable weather'}';
      alerts.add(
        HomeAlertData(
          Icons.wb_sunny_outlined,
          'Stable Weather',
          '$condition. No major weather warning detected for the next few hours.',
          const Color(0xFFEAF8EA),
        ),
      );
    }
    return alerts.take(3).toList();
  }

  static String summary(Map<String, dynamic>? weather, {bool loading = false}) {
    if (loading && weather == null) {
      return 'Fetching live weather forecast for the selected area.';
    }
    if (weather == null) {
      return 'Alerts are based on live weather forecast, not crop analysis.';
    }
    final place = '${weather['place_name'] ?? 'selected area'}';
    final next3Rain = _num(weather['rain_next_3h_mm']);
    final prob = _num(weather['rain_probability_next_3h']);
    final condition = '${weather['weather_description'] ?? 'Live weather'}';
    return '$condition near $place • ${next3Rain.toStringAsFixed(1)} mm rain possible in 3h • ${prob.toStringAsFixed(0)}% rain chance.';
  }

  static double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0.0;
  }

  static List<int> _codes(dynamic value) {
    if (value is List) {
      return value
          .map((v) => v is num ? v.round() : int.tryParse('$v'))
          .whereType<int>()
          .toList();
    }
    return const [];
  }
}

class HomeAlertTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color bgColor;
  const HomeAlertTile({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: green, size: 20),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.2,
              color: Colors.black54,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class RecentAnalysesHomeCard extends StatelessWidget {
  final AnalysisState state;
  final VoidCallback openHistory;
  const RecentAnalysesHomeCard({
    super.key,
    required this.state,
    required this.openHistory,
  });

  @override
  Widget build(BuildContext context) {
    final rows = state.recentAnalyses;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Recent Activity',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                TextButton(
                  onPressed: openHistory,
                  child: const Text(
                    'View History',
                    style: TextStyle(color: green, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            if (rows.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: softGreen,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'No recent analysis yet. Select a point or draw a boundary on the Map page, then run analysis.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              )
            else
              ...List.generate(rows.take(3).length, (i) {
                final visible = rows.take(3).toList();
                final r = visible[i];
                return Column(
                  children: [
                    HomeRecentItem(
                      title: '${r['title'] ?? 'Unknown location'}',
                      subtitle:
                          '${r['subtitle'] ?? 'Land suitability analysis'}',
                      date: '${r['date'] ?? '--'}',
                    ),
                    if (i != visible.length - 1) const Divider(),
                  ],
                );
              }),
          ],
        ),
      ),
    );
  }
}

class HomeRecentItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final String date;
  const HomeRecentItem({
    super.key,
    required this.title,
    required this.subtitle,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: green, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: Colors.black38,
            size: 20,
          ),
        ],
      ),
    );
  }
}

class QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const QuickTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE7EEE8)),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: green, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Map that rebuilds immediately when points, pin, or layers change.
