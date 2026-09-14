part of geosustain_mobile;

class DashboardPage extends StatelessWidget {
  final AnalysisState state;
  final VoidCallback goMap;
  final ValueChanged<String> message;
  const DashboardPage(
      {super.key,
      required this.state,
      required this.goMap,
      required this.message});


  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
          children: [
            MobileHeader(
                title: 'Dashboard',
                trailing: IconButton(
                    onPressed: goMap, icon: const Icon(Icons.refresh))),
            ContextCard(state: state),
            if (state.isAnalystRole) PlannerRiskToolsCard(state: state),
            SoilCard(state: state),
            ResultSummaryCard(state: state),
            AnalysisMapCard(state: state),
            if (state.isAnalystRole) InfrastructureSuitabilityCard(state: state),
            GeeListCard(state: state),
            SuitabilityLegendCard(state: state),
            AnalyticsChartsCard(state: state),
            ReportPreviewCard(state: state),
          ]),
    );
  }
}

class AnalysisMapCard extends StatelessWidget {
  final AnalysisState state;
  const AnalysisMapCard({super.key, required this.state});
  @override
  Widget build(BuildContext context) {
    final points = state.polygonPoints;
    if (points.length < 3) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(top: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.map_rounded, color: green, size: 18),
            SizedBox(width: 6),
            Text('Your Farm Boundary', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ]),
          const SizedBox(height: 4),
          const Text('This is the exact area that was analyzed.', style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 220,
              child: FlutterMap(
                options: MapOptions(
                  initialCameraFit: CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(28)),
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                ),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.geosustain.mobile'),
                  PolygonLayer(polygons: [Polygon(points: points, color: green.withOpacity(0.22), borderColor: green, borderStrokeWidth: 3)]),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class ContextCard extends StatelessWidget {
  final AnalysisState state;
  const ContextCard({super.key, required this.state});

  bool _isEstimated(Map<String, dynamic>? data, String key) {
    final dq = data?['data_quality'];
    if (dq is! Map) return false;
    final entry = dq[key];
    if (entry is! Map) return false;
    final q = '${entry['overall_quality'] ?? entry['quality'] ?? ''}';
    return q != 'measured' && q.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final data = state.result;
    final weather = state.liveWeather ?? data;
    final tempEstimated = _isEstimated(data, 'temperature');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle('PANABO CONTEXT'),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${state.numText(weather?['temperature_c'])} °C',
                style:
                    const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
            if (tempEstimated) ...[
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('(estimated)', style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic)),
              ),
            ],
          ]),
          const SizedBox(height: 4),
          Text('${data?['weather_description'] ?? 'Loading weather...'}'),
          const SizedBox(height: 10),
          InfoProgress(label: 'Humidity', value: weather?['live_humidity']),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: cream,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEED8BF))),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('SEASONAL ADVICE',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF754E1A))),
              const SizedBox(height: 6),
              Text(
                  '${data?['season_advice'] ?? 'Fetching seasonal recommendation...'}',
                  style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class SoilCard extends StatelessWidget {
  final AnalysisState state;
  const SoilCard({super.key, required this.state});

  bool _isEstimated(Map<String, dynamic>? data, String key) {
    final dq = data?['data_quality'];
    if (dq is! Map) return false;
    final entry = dq[key];
    if (entry is! Map) return false;
    final q = '${entry['overall_quality'] ?? entry['quality'] ?? ''}';
    return q != 'measured' && q.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final data = state.result;
    final phEstimated = _isEstimated(data, 'soil_ph');
    final ndviEstimated = _isEstimated(data, 'ndvi');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: SectionTitle('SOIL NUTRIENT ANALYSIS')),
            Text('pH ${state.numText(data?['soil_ph'])}${phEstimated ? ' (est.)' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700))
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: Column(children: [
              InfoProgress(label: 'Nitrogen', value: data?['nitrogen']),
              InfoProgress(label: 'Phosphorus (estimated)', value: data?['phosphorus']),
              InfoProgress(label: 'Potassium (estimated)', value: data?['potassium']),
            ])),
            const SizedBox(width: 16),
            SoilDonut(label: state.numText(data?['soil_ph'])),
          ]),
          const SizedBox(height: 10),
          Text('NDVI: ${state.numText(data?['ndvi'])}${ndviEstimated ? ' (est.)' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class InfoProgress extends StatelessWidget {
  final String label;
  final dynamic value;
  const InfoProgress({super.key, required this.label, this.value});
  @override
  Widget build(BuildContext context) {
    final num? n = value is num ? value : num.tryParse('$value');
    final double p = n == null ? 0 : (n.clamp(0, 100) / 100).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(children: [
        SizedBox(
            width: 82,
            child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(
            child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                    value: p,
                    minHeight: 7,
                    backgroundColor: const Color(0xFFE9EEE9),
                    color: green))),
        const SizedBox(width: 10),
        Text(n == null ? '--' : n.toStringAsFixed(0),
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class SoilDonut extends StatelessWidget {
  final String label;
  const SoilDonut({super.key, required this.label});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      height: 86,
      child: Stack(alignment: Alignment.center, children: [
        CircularProgressIndicator(
            value: 0.72,
            strokeWidth: 12,
            backgroundColor: const Color(0xFFA87B1F),
            color: const Color(0xFF18A768)),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
          const Text('SOIL PH',
              style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700))
        ]),
      ]),
    );
  }
}

class _SummaryBadge extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final bool bold;
  const _SummaryBadge({required this.text, required this.color, this.icon, this.bold = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, color: Colors.white, size: 14), const SizedBox(width: 5)],
        Text(text, style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: bold ? FontWeight.w900 : FontWeight.w600)),
      ]),
    );
  }
}

class ResultSummaryCard extends StatelessWidget {
  final AnalysisState state;
  const ResultSummaryCard({super.key, required this.state});

  List<dynamic> _cropAlternatives(Map<String, dynamic>? data) {
    if (data == null) return [];
    dynamic rawAlternatives = data['alternative_crops'];
    dynamic rawTop = data['top_crop_recommendations'];
    if (rawAlternatives is String && rawAlternatives.trim().isNotEmpty) {
      try { rawAlternatives = jsonDecode(rawAlternatives); } catch (_) {}
    }
    if (rawTop is String && rawTop.trim().isNotEmpty) {
      try { rawTop = jsonDecode(rawTop); } catch (_) {}
    }
    if (rawAlternatives is List && rawAlternatives.isNotEmpty) {
      return rawAlternatives;
    }
    if (rawTop is List && rawTop.length > 1) {
      return rawTop.skip(1).toList();
    }
    return [];
  }

  double? _displayPct(dynamic value, int rank) {
    final n = value is num ? value.toDouble() : double.tryParse('$value');
    if (n == null) return null;
    return n;
  }

  String _pctText(dynamic value, int rank) {
    final display = _displayPct(value, rank);
    if (display == null) return '--';
    return display.toStringAsFixed(display % 1 == 0 ? 0 : 1);
  }


  Map<String, dynamic>? _xai(Map<String, dynamic>? data) {
    if (data == null) return null;
    dynamic raw = data['xai_explanation'];
    if (raw is String && raw.trim().isNotEmpty) {
      try { raw = jsonDecode(raw); } catch (_) { return null; }
    }
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  String? _plainSummary(Map<String, dynamic>? data) {
    final xai = _xai(data);
    final plain = xai?['plain_summary'];
    if (plain != null && '$plain'.trim().isNotEmpty) return '$plain';
    return null;
  }

  /// Plain-language version of the backend's technical land_status code, for
  /// farmers who may not know terms like "arable" or "infrastructure."
  String friendlyLandStatus(Map<String, dynamic>? data) {
    final raw = '${data?['land_status'] ?? ''}'.toUpperCase();
    if (raw.contains('WATER') || raw.contains('FLOOD')) return 'This spot is water or flooded';
    if (raw.contains('INFRASTRUCTURE') || raw.contains('BARE')) return 'This looks like bare or built-up land';
    if (raw.contains('DEGRADED') || raw.contains('LOW VEGETATION')) return 'This soil could use some improvement';
    if (raw.contains('ARABLE') || raw.contains('VEGETATED')) return 'Good land for farming';
    return data?['land_status'] != null ? 'Land condition analyzed' : 'No land analyzed yet.';
  }

  List<String> _recommendationReasons(Map<String, dynamic>? data) {
    final xai = _xai(data);
    if (xai != null) {
      final reasons = <String>[];
      final summary = '${xai['summary'] ?? ''}'.trim();
      if (summary.isNotEmpty) reasons.add(summary);
      final supporting = xai['supporting_factors'];
      if (supporting is List) {
        reasons.addAll(supporting.map((e) => '$e').where((e) => e.trim().isNotEmpty));
      }
      final limiting = xai['limiting_factors'];
      if (limiting is List) {
        reasons.addAll(limiting.map((e) => 'Limiting factor: $e').where((e) => e.trim().isNotEmpty));
      }
      final comparison = '${xai['comparison'] ?? ''}'.trim();
      if (comparison.isNotEmpty) reasons.add(comparison);
      final planningAdvice = '${xai['planning_advice'] ?? ''}'.trim();
      if (planningAdvice.isNotEmpty) reasons.add(planningAdvice);
      if (reasons.isNotEmpty) return reasons;
    }
    return ['Run a new analysis to generate a parcel-specific Explainable AI result.'];
  }

  List<String> _dataQualityWarnings(Map<String, dynamic>? data) {
    if (data == null) return const [];
    final raw = data['data_quality_warnings'];
    if (raw is List) return raw.map((e) => '$e').where((e) => e.trim().isNotEmpty).toList();
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final data = state.result;
    final cropFlag = data?['is_crop_recommended'];
    final isCrop = cropFlag is bool
        ? cropFlag
        : !['false', '0'].contains('$cropFlag'.trim().toLowerCase()) &&
            '${data?['land_type'] ?? 'arable'}'.trim().toLowerCase() == 'arable';
    final alternatives = isCrop ? _cropAlternatives(data) : <dynamic>[];
    final cropRainfall = data == null ? null : (data['rainfall_monthly_mm'] ?? data['monthly_rainfall_mm'] ?? data['rainfall_30d_mm'] ?? data['rainfall_mm']);
    final reasons = _recommendationReasons(data);
    final dataWarnings = _dataQualityWarnings(data);
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
            colors: [Color(0xFF0B7D49), Color(0xFF075F38)]),
        boxShadow: [
          BoxShadow(
              color: green.withOpacity(0.16),
              blurRadius: 18,
              offset: const Offset(0, 8))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            data == null
                ? 'RECOMMENDED CROP MATCH'
                : '${data['recommendation_title'] ?? 'LAND SUITABILITY SUMMARY'}'
                    .toUpperCase(),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          _SummaryBadge(
              text: isCrop ? 'Match: ${_pctText(data?['crop_compatibility_pct'], 0)}%' : 'Not ideal for farming',
              color: Colors.white.withOpacity(0.20)),
          _SummaryBadge(
              text: displaySuitability(data),
              color: suitabilityBadgeColor(data),
              bold: true),
          if (isCrop && data?['season_label'] != null)
            _SummaryBadge(
              icon: Icons.calendar_month_rounded,
              text: '${data?['season_label']}',
              color: Colors.white.withOpacity(0.20),
              bold: true,
            ),
        ]),
        if (dataWarnings.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.14), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: const [
                Icon(Icons.info_outline_rounded, size: 16, color: Colors.white),
                SizedBox(width: 6),
                Text('Some values below are estimates', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
              ]),
              const SizedBox(height: 4),
              for (final w in dataWarnings)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('• $w', style: TextStyle(color: Colors.white.withOpacity(0.92), fontSize: 11.5, height: 1.3)),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 8),
        Text('${data?['predicted_crop'] ?? data?['crop_recommendation'] ?? data?['recommended_crop'] ?? '--'}'.toUpperCase(),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(friendlyLandStatus(data),
            style: const TextStyle(color: Colors.white)),
        if ('${data?['analysis_summary'] ?? ''}'.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white.withOpacity(.13), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('ANALYSIS SUMMARY', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Text('${data?['analysis_summary']}', style: const TextStyle(color: Colors.white, height: 1.4, fontSize: 12.5)),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: GreenMetric(
                  label: 'Environmental',
                  value: isCrop ? '${state.numText(data?['environmental_suitability_pct'] ?? data?['crop_compatibility_pct'])}%' : '--')),
          const SizedBox(width: 10),
          Expanded(
              child: GreenMetric(
                  label: 'Season-adjusted',
                  value: isCrop ? '${state.numText(data?['season_adjusted_score'] ?? data?['crop_compatibility_pct'])}%' : '--')),
        ]),
        if (isCrop) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white.withOpacity(.12), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(.25))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('PLANTING CALENDAR — ${data?['intended_planting_month_name'] ?? state.intendedPlantingMonthName}'.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Text('${data?['season_note'] ?? data?['season_advice'] ?? '--'}', style: const TextStyle(color: Colors.white, fontSize: 12)),
              const SizedBox(height: 4),
              Text('Suggested window: ${data?['recommended_planting_window'] ?? '--'}', style: TextStyle(color: Colors.white.withOpacity(.85), fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            border: Border.all(color: Colors.white.withOpacity(0.28)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.psychology_alt_rounded, color: Colors.white, size: 17),
              const SizedBox(width: 6),
              Expanded(child: Text(isCrop ? 'WHY THIS CROP?' : 'WHY NO CROP YET?', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900))),
            ]),
            const SizedBox(height: 8),
            Text(_plainSummary(data) ?? (reasons.isNotEmpty ? reasons.first : 'Analysis in progress.'),
                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
            if (reasons.isNotEmpty)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 4),
                  iconColor: Colors.white,
                  collapsedIconColor: Colors.white70,
                  title: const Text('See more detail', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
                  children: [
                    ...reasons.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('• ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                        Expanded(child: Text(r, style: const TextStyle(color: Colors.white, fontSize: 12))),
                      ]),
                    )),
                  ],
                ),
              ),
          ]),
        ),
        if (alternatives.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              border: Border.all(color: Colors.white.withOpacity(0.28)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.eco_rounded, color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text('OTHER SUITABLE CROPS',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 10),
              ...alternatives.take(5).toList().asMap().entries.map((entry) {
                final item = entry.value;
                final rank = entry.key + 1;
                final crop = item is Map ? (item['crop'] ?? item['name'] ?? '--') : '$item';
                final pct = item is Map ? _pctText(item['compatibility_pct'] ?? item['score'] ?? item['compatibility'], rank) : '--';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Expanded(
                      child: Text('$crop'.toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w800)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('$pct%',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900)),
                    ),
                  ]),
                );
              }),
            ]),
          ),
        ],
      ]),
    );
  }
}

class GreenMetric extends StatelessWidget {
  final String label;
  final String value;
  const GreenMetric({super.key, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          border: Border.all(color: Colors.white.withOpacity(0.28)),
          borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900)),
      ]),
    );
  }
}

class InfrastructureSuitabilityCard extends StatelessWidget {
  final AnalysisState state;
  const InfrastructureSuitabilityCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final d = state.result;
    return Card(
      margin: const EdgeInsets.only(top: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: const [
            Icon(Icons.apartment_rounded, color: green),
            SizedBox(width: 8),
            Expanded(child: SectionTitle('INFRASTRUCTURE SUITABILITY')),
          ]),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: infrastructureColor(d).withOpacity(0.16),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: infrastructureColor(d).withOpacity(0.45)),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${d?['infrastructure_suitability'] ?? 'NOT YET ANALYZED'}',
                  style: TextStyle(
                      color: infrastructureColor(d),
                      fontWeight: FontWeight.w900,
                      fontSize: 18)),
              const SizedBox(height: 4),
              Text(
                  '${d?['infrastructure_status'] ?? 'Analyze a point or boundary to check infrastructure suitability.'}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                  '${d?['infrastructure_recommendation'] ?? 'Based on slope, elevation, NDVI, rainfall, and land condition.'}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: MiniInfo(
                    label: 'Slope',
                    value: '${state.numText(d?['slope_pct'])}%')),
            const SizedBox(width: 8),
            Expanded(
                child: MiniInfo(
                    label: 'Elevation',
                    value: '${state.numText(d?['elevation_m'])} m')),
            const SizedBox(width: 8),
            Expanded(
                child: MiniInfo(
                    label: 'Score',
                    value: '${d?['infrastructure_score'] ?? '--'}')),
          ]),
        ]),
      ),
    );
  }
}

class MiniInfo extends StatelessWidget {
  final String label;
  final String value;
  const MiniInfo({super.key, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: const Color(0xFFF5F8F5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE7EEE8))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ]),
      );
}

class GeeGridCard extends StatelessWidget {
  final AnalysisState state;
  const GeeGridCard({super.key, required this.state});
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: const [
            Expanded(child: SectionTitle('LIVE EARTH OBSERVATION (GEE)')),
            Text('View All',
                style: TextStyle(
                    color: green, fontWeight: FontWeight.w800, fontSize: 12))
          ]),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 2.2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: geeItems(state).map((x) => MetricTile(item: x)).toList(),
          ),
        ]),
      ),
    );
  }
}

class GeeListCard extends StatelessWidget {
  final AnalysisState state;
  const GeeListCard({super.key, required this.state});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle('LIVE EARTH OBSERVATION (GEE)'),
          ...geeItems(state).map((x) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(children: [
                  CircleAvatar(
                      radius: 16,
                      backgroundColor: x.color.withOpacity(0.12),
                      child: Icon(x.icon, color: x.color, size: 18)),
                  const SizedBox(width: 12),
                  Expanded(
                      child:
                          Text(x.label, style: const TextStyle(fontSize: 13))),
                  Text(x.value,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ]),
              )),
        ]),
      ),
    );
  }
}

class MetricItem {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  MetricItem(this.icon, this.color, this.label, this.value);
}

List<MetricItem> geeItems(AnalysisState state) {
  final d = state.result;
  return [
    MetricItem(Icons.water_drop_outlined, Colors.blue, 'Rainfall (monthly)',
        '${state.numText(d?['rainfall_monthly_mm'] ?? d?['monthly_rainfall_mm'] ?? d?['rainfall_30d_mm'] ?? d?['rainfall_mm'])} mm'),
    MetricItem(Icons.thermostat, Colors.orange, 'Surface Temp',
        '${state.numText(d?['surface_temp_c'] ?? d?['temperature_c'])} °C'),
    MetricItem(Icons.opacity, Colors.blueAccent, 'Humidity',
        '${state.numText(d?['live_humidity'])} %'),
    MetricItem(Icons.air, Colors.lightBlue, 'Wind Speed',
        '${state.numText(d?['wind_speed_ms'])} m/s'),
    MetricItem(Icons.cloud_outlined, Colors.green, 'Cloud Cover',
        '${state.numText(d?['cloud_cover_pct'])} %'),
    MetricItem(Icons.eco_outlined, Colors.lightGreen, 'NDVI',
        state.numText(d?['ndvi'])),
  ];
}

class MetricTile extends StatelessWidget {
  final MetricItem item;
  const MetricTile({super.key, required this.item});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8EEE8))),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(children: [
              Icon(item.icon, color: item.color, size: 18),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(item.label,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.black54)))
            ]),
            const SizedBox(height: 8),
            Text(item.value,
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ]),
    );
  }
}


/// Single satellite snapshot (no interactive map) for history thumbnails and dialogs.
String locationSatelliteImageUrl(
  double lat,
  double lon, {
  int width = 256,
  int height = 256,
  double spanDegrees = 0.0016,
}) {
  final west = lon - spanDegrees;
  final south = lat - spanDegrees;
  final east = lon + spanDegrees;
  final north = lat + spanDegrees;
  return Uri.https(
    'server.arcgisonline.com',
    '/ArcGIS/rest/services/World_Imagery/MapServer/export',
    {
      'bbox': '$west,$south,$east,$north',
      'bboxSR': '4326',
      'imageSR': '4326',
      'size': '$width,$height',
      'format': 'jpg',
      'f': 'image',
    },
  ).toString();
}

class LocationHistoryThumb extends StatelessWidget {
  final dynamic lat;
  final dynamic lon;
  final bool expanded;
  const LocationHistoryThumb({super.key, required this.lat, required this.lon, this.expanded = false});

  @override
  Widget build(BuildContext context) {
    final latitude = lat is num ? (lat as num).toDouble() : double.tryParse('$lat');
    final longitude = lon is num ? (lon as num).toDouble() : double.tryParse('$lon');
    final width = expanded ? double.infinity : 76.0;
    final height = expanded ? double.infinity : 76.0;
    if (latitude == null || longitude == null) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: softGreen, borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.map, color: green, size: 34),
      );
    }
    final imageUrl = locationSatelliteImageUrl(
      latitude,
      longitude,
      width: expanded ? 640 : 152,
      height: expanded ? 320 : 152,
      spanDegrees: expanded ? 0.0024 : 0.0016,
    );
    final pinSize = expanded ? 36.0 : 24.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: softGreen,
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: green),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                color: softGreen,
                alignment: Alignment.center,
                child: const Icon(Icons.map, color: green, size: 34),
              ),
            ),
            Center(
              child: Icon(Icons.location_pin, color: Colors.red, size: pinSize),
            ),
          ],
        ),
      ),
    );
  }
}

