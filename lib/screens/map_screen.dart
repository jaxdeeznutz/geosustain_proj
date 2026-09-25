part of '../main.dart';

class LiveFieldMap extends StatefulWidget {
  final AnalysisState analysisState;
  final ValueChanged<String> onError;
  const LiveFieldMap({
    super.key,
    required this.analysisState,
    required this.onError,
  });

  @override
  State<LiveFieldMap> createState() => _LiveFieldMapState();
}

class _LiveFieldMapState extends State<LiveFieldMap> {
  @override
  void initState() {
    super.initState();
    widget.analysisState.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.analysisState.removeListener(_refresh);
    super.dispose();
  }

  List<Map<String, dynamic>> _heatmapGrid(AnalysisState s) {
    final raw = s.result?['heatmap_grid'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  double? _num(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value');

  String _heatmapKey(String layer) =>
      const {
        'NDVI': 'ndvi',
        'Suitability': 'crop_suitability',
        'Soil pH': 'soil_ph',
        'Rainfall': 'rainfall',
        'Elevation': 'elevation',
        'Slope': 'slope',
      }[layer] ??
      'ndvi';

  Color? _polygonHeatColor(AnalysisState s) {
    final grid = _heatmapGrid(s);
    if (grid.isEmpty) return null;
    final key = _heatmapKey(s.heatmapLayer);
    final values = grid.map((e) => _num(e[key])).whereType<double>().toList();
    if (values.isEmpty) return null;
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final average = values.reduce((a, b) => a + b) / values.length;
    final t = maxV == minV
        ? .75
        : ((average - minV) / (maxV - minV)).clamp(0.0, 1.0);
    if (t >= .75) return const Color(0xFF16A765);
    if (t >= .50) return const Color(0xFF8BD450);
    if (t >= .25) return const Color(0xFFF0AA20);
    return const Color(0xFFE95B55);
  }

  Color _heatColor(double value, double minV, double maxV) {
    final t = maxV == minV
        ? .65
        : ((value - minV) / (maxV - minV)).clamp(0.0, 1.0);
    if (t >= .75) return const Color(0xFF08783A);
    if (t >= .50) return const Color(0xFF77C66E);
    if (t >= .25) return const Color(0xFFF0B33A);
    return const Color(0xFFE65A4F);
  }

  List<Polygon> _heatCells(AnalysisState s, List<LatLng> boundary) {
    final grid = _heatmapGrid(s);
    if (grid.length < 2 || boundary.length < 3) return const [];
    final key = _heatmapKey(s.heatmapLayer);
    final values = grid.map((e) => _num(e[key])).whereType<double>().toList();
    if (values.isEmpty) return const [];
    final minV = values.reduce(math.min), maxV = values.reduce(math.max);
    final lats = boundary.map((p) => p.latitude).toList(),
        lngs = boundary.map((p) => p.longitude).toList();
    final latStep = ((lats.reduce(math.max) - lats.reduce(math.min)) / 7)
        .clamp(.00008, .0012)
        .toDouble();
    final lngStep = ((lngs.reduce(math.max) - lngs.reduce(math.min)) / 7)
        .clamp(.00008, .0012)
        .toDouble();
    final cells = <Polygon>[];
    for (final item in grid) {
      final lat = _num(item['lat']),
          lng = _num(item['lng']),
          value = _num(item[key]);
      if (lat == null || lng == null || value == null) continue;
      cells.add(
        Polygon(
          points: [
            LatLng(lat - latStep, lng - lngStep),
            LatLng(lat - latStep, lng + lngStep),
            LatLng(lat + latStep, lng + lngStep),
            LatLng(lat + latStep, lng - lngStep),
          ],
          color: _heatColor(value, minV, maxV).withValues(alpha: .62),
          borderColor: Colors.white.withValues(alpha: .45),
          borderStrokeWidth: 1,
        ),
      );
    }
    return cells;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.analysisState;
    final points = List<LatLng>.from(s.polygonPoints);
    final pin = s.selectedPoint;

    return FlutterMap(
      mapController: s.mapController,
      options: MapOptions(
        initialCenter: pin,
        initialZoom: 13,
        minZoom: 12,
        maxZoom: 19,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        cameraConstraint: CameraConstraint.contain(
          bounds: LatLngBounds(
            const LatLng(7.20, 125.50),
            const LatLng(7.41, 125.72),
          ),
        ),
        onTap: (tap, point) {
          final err = s.onMapTap(tap, point);
          if (err != null) widget.onError(err);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: s.tileUrl(),
          userAgentPackageName: 'com.geosustain.mobile',
        ),
        if (points.length >= 2)
          PolylineLayer(
            polylines: [Polyline(points: points, color: green, strokeWidth: 4)],
          ),
        if (_heatCells(s, points).isNotEmpty)
          PolygonLayer(polygons: _heatCells(s, points)),
        if (points.length >= 3)
          PolygonLayer(
            polygons: [
              Polygon(
                points: points,
                color: _heatCells(s, points).isNotEmpty
                    ? Colors.transparent
                    : (_polygonHeatColor(s) ?? green).withValues(
                        alpha: _polygonHeatColor(s) == null ? 0.18 : 0.46,
                      ),
                borderColor: Colors.white,
                borderStrokeWidth: 3,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (!s.drawing)
              Marker(
                point: pin,
                width: 48,
                height: 48,
                alignment: Alignment.bottomCenter,
                child: const Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: 48,
                ),
              ),
            ...points.asMap().entries.map(
              (e) => Marker(
                point: e.value,
                width: 28,
                height: 28,
                alignment: Alignment.center,
                child: CircleAvatar(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  child: Text(
                    '${e.key + 1}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class HeroMapCard extends StatelessWidget {
  final AnalysisState state;
  final bool compact;
  final ValueChanged<String> message;
  const HeroMapCard({
    super.key,
    required this.state,
    required this.message,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 340 : 380,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EEE8)),
      ),
      child: Stack(
        children: [
          LiveFieldMap(analysisState: state, onError: message),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.05),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.70),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 58,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  MiniPill(
                    text: state.satellite ? 'Satellite' : 'Street',
                    icon: Icons.arrow_drop_down,
                    onTap: state.toggleSatellite,
                  ),
                  if (state.result?['heatmap_grid'] is List &&
                      (state.result?['heatmap_grid'] as List).isNotEmpty)
                    ...[
                      'NDVI',
                      'Suitability',
                      'Soil pH',
                      'Rainfall',
                      'Elevation',
                      'Slope',
                    ].map(
                      (layer) => MiniPill(
                        text: layer,
                        icon: state.heatmapLayer == layer
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        onTap: () => state.setHeatmapLayer(layer),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Column(
              children: [
                MapFab(
                  icon: Icons.layers_outlined,
                  onTap: state.toggleSatellite,
                ),
                const SizedBox(height: 10),
                MapFab(
                  icon: Icons.my_location,
                  onTap: () => state.moveMapLocked(state.selectedPoint, 15),
                ),
                const SizedBox(height: 10),
                MapFab(icon: Icons.add, onTap: () => state.zoomMap(1)),
                MapFab(icon: Icons.remove, onTap: () => state.zoomMap(-1)),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.selectedPlaceName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  state.drawing
                      ? 'Drawing boundary • ${state.polygonPoints.length} points'
                      : 'Tap map to move pin or draw field boundary',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                Text(
                  'Last analysis: ${state.result == null ? '--' : 'Updated just now'}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MiniPill extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  const MiniPill({
    super.key,
    required this.text,
    required this.icon,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (icon != Icons.arrow_drop_down) Icon(icon, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MapFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const MapFab({super.key, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: const Color(0xFF15251A)),
        ),
      ),
    );
  }
}

class MapAnalyzePage extends StatefulWidget {
  final AnalysisState state;
  final ValueChanged<String> message;
  final VoidCallback goAnalyze;
  const MapAnalyzePage({
    super.key,
    required this.state,
    required this.message,
    required this.goAnalyze,
  });

  @override
  State<MapAnalyzePage> createState() => _MapAnalyzePageState();
}

class _MapAnalyzePageState extends State<MapAnalyzePage> {
  bool _askedGps = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setupLocation());
  }

  Future<void> _setupLocation() async {
    if (_askedGps) return;
    _askedGps = true;
    await widget.state.requestLocationPermission();
    final err = await widget.state.useCurrentLocation();
    if (err != null && mounted) widget.message(err);
  }

  AnalysisState get state => widget.state;
  void message(String text) => widget.message(text);
  void goAnalyze() => widget.goAnalyze();

  Future<void> _poly() async {
    final err = await state.analyzePolygon();
    if (err != null) {
      message(err);
    } else {
      goAnalyze();
    }
  }

  Future<void> _locate() async {
    final err = await state.useCurrentLocation();
    if (err != null) message(err);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
        children: [
          const MobileHeader(title: 'Map & Area Selection'),
          HeroMapCard(state: state, message: message, compact: true),
          const SizedBox(height: 10),
          if (state.result?['heatmap_grid'] is List &&
              (state.result?['heatmap_grid'] as List).isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: softGreen,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: green.withValues(alpha: .15)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.layers_rounded, color: green, size: 19),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${state.heatmapLayer} heatmap is active. Use the layer chips above the map to switch data.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFFB47800),
                    size: 19,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Heatmaps appear after you finish and analyze a polygon boundary. They do not appear while you are still drawing.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF7A5600),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(child: SectionTitle('SELECT LOCATION')),
                      TextButton.icon(
                        onPressed: state.locating ? null : _locate,
                        icon: state.locating
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location, size: 18),
                        label: Text(
                          state.locating ? 'Locating...' : 'Use My Location',
                        ),
                      ),
                    ],
                  ),
                  Text(
                    state.selectedPlaceName,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: state.latController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: state.lonController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int>(
                    initialValue: state.intendedPlantingMonth,
                    decoration: const InputDecoration(
                      labelText: 'Intended Planting Month',
                      prefixIcon: Icon(Icons.calendar_month_rounded),
                      helperText:
                          'The crop ranking will be adjusted using the local planting calendar.',
                    ),
                    items: List.generate(12, (index) {
                      final month = index + 1;
                      return DropdownMenuItem(
                        value: month,
                        child: Text(AnalysisState.monthNames[month]),
                      );
                    }),
                    onChanged: state.loading
                        ? null
                        : state.setIntendedPlantingMonth,
                  ),
                  const SizedBox(height: 10),
                  _SeasonLegend(),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MyFarmsPage(state: state),
                          ),
                        );
                      },
                      icon: const Icon(Icons.agriculture_rounded),
                      label: const Text('My Farms / Walk Boundary'),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const SectionTitle('DRAW FARM BOUNDARY'),
                  Text(
                    'Tap the map to draw the formal farm parcel boundary. Single-point analysis is not used for farmer submissions. Points: ${state.polygonPoints.length}',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: state.clearSelection,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Clear'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: state.loading
                              ? null
                              : () async {
                                  state.toggleDrawing();
                                  if (!state.drawing) await _poly();
                                },
                          icon: const Icon(Icons.edit),
                          label: Text(
                            state.drawing
                                ? 'Analyze Boundary'
                                : 'Start Drawing',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: softGreen,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Map is now focused on selection only. Detailed crop, soil, weather, and infrastructure results appear in the Analyze tab after running analysis.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeasonLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget item(Color color, String title, String meaning) => Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Colors.black87,
                  height: 1.3,
                ),
                children: [
                  TextSpan(
                    text: '$title — ',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  TextSpan(text: meaning),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE9DF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 17, color: green),
              SizedBox(width: 7),
              Text(
                'SEASON STATUS LEGEND',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          item(
            const Color(0xFF168A4A),
            'In season',
            'month is inside the preferred local planting window.',
          ),
          item(
            const Color(0xFF57A96B),
            'Preferred establishment',
            'best month for establishing a perennial crop.',
          ),
          item(
            const Color(0xFFE6A21A),
            'Year-round with management',
            'crop may be planted, but irrigation or moisture management is important.',
          ),
          item(
            const Color(0xFFD9534F),
            'Outside preferred season',
            'score is reduced; consider the suggested planting window.',
          ),
        ],
      ),
    );
  }
}

class AnalysisLoadingBanner extends StatelessWidget {
  final String message;
  const AnalysisLoadingBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 16,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              message,
              key: ValueKey(message),
              style: const TextStyle(fontWeight: FontWeight.w900, color: green),
            ),
          ),
        ],
      ),
    );
  }
}
