part of geosustain_mobile;

class LiveFieldMap extends StatefulWidget {
  final AnalysisState analysisState;
  final ValueChanged<String> onError;
  const LiveFieldMap({super.key, required this.analysisState, required this.onError});

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
            polylines: [
              Polyline(
                points: points,
                color: green,
                strokeWidth: 4,
              ),
            ],
          ),
        if (points.length >= 3)
          PolygonLayer(
            polygons: [
              Polygon(
                points: points,
                color: green.withOpacity(0.35),
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
                child: const Icon(Icons.location_on, color: Colors.red, size: 48),
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
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
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
  const HeroMapCard(
      {super.key,
      required this.state,
      required this.message,
      this.compact = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 340 : 380,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE7EEE8))),
      child: Stack(children: [
        LiveFieldMap(analysisState: state, onError: message),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.05),
                      Colors.transparent,
                      Colors.black.withOpacity(0.70)
                    ]),
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
            child: Row(children: [
              MiniPill(
                  text: state.satellite ? 'Satellite' : 'Street',
                  icon: Icons.arrow_drop_down,
                  onTap: state.toggleSatellite),
            ]),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Column(children: [
            MapFab(icon: Icons.layers_outlined, onTap: state.toggleSatellite),
            const SizedBox(height: 10),
            MapFab(
                icon: Icons.my_location,
                onTap: () => state.moveMapLocked(state.selectedPoint, 15)),
            const SizedBox(height: 10),
            MapFab(
                icon: Icons.add,
                onTap: () => state.zoomMap(1)),
            MapFab(
                icon: Icons.remove,
                onTap: () => state.zoomMap(-1)),
          ]),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(state.selectedPlaceName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(
                state.drawing
                    ? 'Drawing boundary • ${state.polygonPoints.length} points'
                    : 'Tap map to move pin or draw field boundary',
                style: const TextStyle(color: Colors.white, fontSize: 13)),
            Text(
                'Last analysis: ${state.result == null ? '--' : 'Updated just now'}',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}

class MiniPill extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  const MiniPill(
      {super.key, required this.text, required this.icon, required this.onTap});
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
            child: Row(children: [
              Text(text,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700)),
              if (icon != Icons.arrow_drop_down) Icon(icon, size: 16)
            ]),
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
            child: Icon(icon, color: const Color(0xFF15251A))),
      ),
    );
  }
}

class MapAnalyzePage extends StatefulWidget {
  final AnalysisState state;
  final ValueChanged<String> message;
  final VoidCallback goAnalyze;
  const MapAnalyzePage({super.key, required this.state, required this.message, required this.goAnalyze});

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

  Future<void> _point() async {
    final err = await state.analyzePoint();
    if (err != null) {
      message(err);
    } else {
      goAnalyze();
    }
  }

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
    final analysisCount = state.profileCounts['analysis_count'] ?? state.historyRecords.length;
    final savedCount = state.profileCounts['saved_count'] ?? state.savedAnalyses.length;
    final reportCount = state.profileCounts['report_count'] ?? state.generatedReports.length;
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 18), children: [
        const MobileHeader(title: 'Map & Area Selection'),
        HeroMapCard(state: state, message: message, compact: true),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Expanded(child: SectionTitle('SELECT LOCATION')),
                TextButton.icon(
                  onPressed: state.locating ? null : _locate,
                  icon: state.locating
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location, size: 18),
                  label: Text(state.locating ? 'Locating...' : 'Use My Location'),
                ),
              ]),
              Text(state.selectedPlaceName, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: state.latController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Latitude'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: state.lonController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Longitude'))),
              ]),
              const SizedBox(height: 14),
              FilledButton.icon(onPressed: state.loading ? null : _point, icon: const Icon(Icons.analytics_outlined), label: const Text('Analyze Selected Point')),
              const SizedBox(height: 18),
              const SectionTitle('DRAW FIELD BOUNDARY'),
              Text('Tap the map to draw a polygon around your field. Points: ${state.polygonPoints.length}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: state.clearSelection, style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: const Text('Clear'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton.icon(onPressed: state.loading ? null : () async { state.toggleDrawing(); if (!state.drawing) await _poly(); }, icon: const Icon(Icons.edit), label: Text(state.drawing ? 'Analyze Boundary' : 'Start Drawing'))),
              ]),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: softGreen, borderRadius: BorderRadius.circular(12)),
                child: const Text('Map is now focused on selection only. Detailed crop, soil, weather, and infrastructure results appear in the Analyze tab after running analysis.', style: TextStyle(fontSize: 12, color: Colors.black54)),
              ),
            ]),
          ),
        ),

      ]),
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
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 16)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4)),
          const SizedBox(width: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(message, key: ValueKey(message), style: const TextStyle(fontWeight: FontWeight.w900, color: green)),
          ),
        ],
      ),
    );
  }
}

