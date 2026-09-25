part of '../main.dart';

class MyFarmsPage extends StatefulWidget {
  final AnalysisState state;
  const MyFarmsPage({super.key, required this.state});
  @override
  State<MyFarmsPage> createState() => _MyFarmsPageState();
}

class _MyFarmsPageState extends State<MyFarmsPage> {
  List<Map<String, dynamic>> farms = [];
  bool loading = true;

  // --- GPS-assisted boundary walking state ---
  bool walking = false;
  StreamSubscription<Position>? walkSub;
  Timer? _tickTimer;
  final List<LatLng> walkPoints = [];
  LatLng? liveRaw; // most recent GPS fix, even if not accepted as a path point
  double? lastAccuracy;
  double distanceM = 0;
  String? liveStatusNote;
  int rawFixCount = 0;
  DateTime? lastRawFixAt;
  final MapController _walkMapController = MapController();

  // --- Review-before-save state (shared by GPS walk and manual draw) ---
  List<LatLng>? reviewPoints;
  String? reviewMethod;
  double? reviewAccuracy;
  int? reviewRawPointCount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    walkSub?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      farms = await widget.state.api.getFarms();
      // Keep the shared AnalysisState farm list (used for Home screen stats)
      // in sync too, rather than duplicating the fetch there.
      widget.state.replaceFarms(farms);
    } catch (e) {
      if (mounted) _snack(friendlyErrorMessage(e));
    }
    if (mounted) setState(() => loading = false);
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  // ---------------------------------------------------------------------
  // Geometry helpers (client-side preview only — the backend recalculates
  // authoritative area/validity from the saved polygon on save).
  // ---------------------------------------------------------------------

  /// Geodesic polygon area in hectares, using the same equirectangular
  /// projection (centered on the mean latitude) as the backend's
  /// `_polygon_area_m2`, so the preview shown here roughly matches what
  /// gets saved.
  double _areaHectares(List<LatLng> pts) {
    if (pts.length < 3) return 0;
    const r = 6378137.0;
    final lat0 =
        (pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length) *
        math.pi /
        180;
    final xy = pts
        .map(
          (p) => Offset(
            r * (p.longitude * math.pi / 180) * math.cos(lat0),
            r * (p.latitude * math.pi / 180),
          ),
        )
        .toList();
    double area = 0;
    for (var i = 0; i < xy.length; i++) {
      final a = xy[i];
      final b = xy[(i + 1) % xy.length];
      area += a.dx * b.dy - b.dx * a.dy;
    }
    return (area.abs() / 2.0) / 10000.0;
  }

  double _perimeterMeters(List<LatLng> pts) {
    if (pts.length < 2) return 0;
    double total = 0;
    for (var i = 0; i < pts.length - 1; i++) {
      total += Geolocator.distanceBetween(
        pts[i].latitude,
        pts[i].longitude,
        pts[i + 1].latitude,
        pts[i + 1].longitude,
      );
    }
    return total;
  }

  /// Distance between the walk/draw's first and last point — a large gap
  /// suggests the farmer didn't close the loop back near the starting point.
  double _closureGapMeters(List<LatLng> pts) {
    if (pts.length < 3) return 0;
    return Geolocator.distanceBetween(
      pts.first.latitude,
      pts.first.longitude,
      pts.last.latitude,
      pts.last.longitude,
    );
  }

  double _cross(LatLng o, LatLng a, LatLng b) =>
      (a.longitude - o.longitude) * (b.latitude - o.latitude) -
      (a.latitude - o.latitude) * (b.longitude - o.longitude);

  bool _segmentsIntersect(LatLng p1, LatLng p2, LatLng p3, LatLng p4) {
    final d1 = _cross(p3, p4, p1);
    final d2 = _cross(p3, p4, p2);
    final d3 = _cross(p1, p2, p3);
    final d4 = _cross(p1, p2, p4);
    return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
  }

  /// Flags an obviously self-intersecting (bowtie-shaped) polygon. Skipped
  /// for very large point counts (long GPS walks) to keep this instant —
  /// self-intersection there is rare and the backend still validates on save.
  bool _hasSelfIntersection(List<LatLng> pts) {
    final n = pts.length;
    if (n < 4 || n > 500) return false;
    for (var i = 0; i < n; i++) {
      final a1 = pts[i], a2 = pts[(i + 1) % n];
      for (var j = i + 1; j < n; j++) {
        if (j == i || (j + 1) % n == i || i == (j + 1) % n) continue;
        if (_segmentsIntersect(a1, a2, pts[j], pts[(j + 1) % n])) return true;
      }
    }
    return false;
  }

  List<String> _boundaryWarnings(List<LatLng> pts) {
    final warnings = <String>[];
    final perimeter = _perimeterMeters(pts);
    final gap = _closureGapMeters(pts);
    if (gap > 40 && gap > perimeter * 0.15) {
      warnings.add(
        'The end of your boundary is ${gap.toStringAsFixed(0)} m from where you started — walk back closer to your starting point for a more accurate shape.',
      );
    }
    if (_hasSelfIntersection(pts)) {
      warnings.add(
        'This boundary crosses over itself. Review the shape below — it may not represent your actual farm outline.',
      );
    }
    return warnings;
  }

  /// Simplifies a walked GPS path using the Douglas-Peucker algorithm,
  /// operating on points projected to local planar meters (same
  /// equirectangular projection as _areaHectares) so `toleranceMeters` is a
  /// real distance rather than a degree offset. This is applied once, to
  /// the full recorded path, right before it's shown for review — it does
  /// NOT touch the live accuracy/jump-distance acceptance logic used while
  /// walking (that stays exactly as already fixed for real-device tracking).
  ///
  /// Why this fixes the "too many dots / tangled shape" problem: a person
  /// walking at normal pace with a phone rarely moves in a perfectly
  /// straight line, and consumer GPS drifts a few meters even when
  /// standing still. Both produce long runs of nearly-collinear or
  /// tightly-clustered points. Douglas-Peucker keeps only the points that
  /// are actually necessary to represent the shape within `toleranceMeters`
  /// — collapsing that jitter into clean, nearly-straight edges — while
  /// preserving real corners of the field. 2.5m was chosen as a middle
  /// ground: small enough to keep genuine corners of a small farm plot,
  /// large enough to absorb typical handheld-GPS jitter (which is often
  /// larger than the 3m distance filter itself).
  List<LatLng> _simplifyPath(
    List<LatLng> points, {
    double toleranceMeters = 2.5,
  }) {
    if (points.length < 3) return points;
    const r = 6378137.0;
    final lat0 =
        (points.map((p) => p.latitude).reduce((a, b) => a + b) /
            points.length) *
        math.pi /
        180;
    final xy = points
        .map(
          (p) => Offset(
            r * (p.longitude * math.pi / 180) * math.cos(lat0),
            r * (p.latitude * math.pi / 180),
          ),
        )
        .toList();

    final keep = <int>{};
    void recurse(int start, int end) {
      keep.add(start);
      keep.add(end);
      if (end - start < 2) return;
      final a = xy[start], b = xy[end];
      final abLen = (b - a).distance;
      double maxDist = -1;
      int maxIdx = start;
      for (var i = start + 1; i < end; i++) {
        final p = xy[i];
        double dist;
        if (abLen == 0) {
          dist = (p - a).distance;
        } else {
          final t =
              (((p.dx - a.dx) * (b.dx - a.dx)) +
                  ((p.dy - a.dy) * (b.dy - a.dy))) /
              (abLen * abLen);
          final tt = t.clamp(0.0, 1.0);
          final proj = Offset(
            a.dx + tt * (b.dx - a.dx),
            a.dy + tt * (b.dy - a.dy),
          );
          dist = (p - proj).distance;
        }
        if (dist > maxDist) {
          maxDist = dist;
          maxIdx = i;
        }
      }
      if (maxDist > toleranceMeters) {
        recurse(start, maxIdx);
        recurse(maxIdx, end);
      }
    }

    recurse(0, xy.length - 1);
    final sortedIndices = keep.toList()..sort();
    return sortedIndices.map((i) => points[i]).toList();
  }

  // ---------------------------------------------------------------------
  // GPS-assisted boundary walking
  // ---------------------------------------------------------------------

  Future<void> _testLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _snack('Location permission not granted.');
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      _snack('Location/GPS is turned off on this device.');
      return;
    }
    _snack('Getting your location...');
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 20),
        ),
      );
      _snack(
        'Got a fix: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)} (±${pos.accuracy.toStringAsFixed(0)}m)',
      );
    } catch (e) {
      _snack('Could not get a location fix: $e');
    }
  }

  Future<void> _startWalk() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _snack(
        'Location permission is required to walk your farm boundary. Please allow it in your device settings.',
      );
      return;
    }
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      _snack('Turn on device location/GPS before walking the boundary.');
      return;
    }
    walkPoints.clear();
    distanceM = 0;
    lastAccuracy = null;
    liveRaw = null;
    liveStatusNote = null;
    rawFixCount = 0;
    lastRawFixAt = null;
    setState(() => walking = true);
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {}); // keeps the "last update Xs ago" readout live
      }
    });
    await walkSub?.cancel();
    // Platform-specific settings, not the generic cross-platform
    // LocationSettings: on Android, the generic settings object does not
    // set an explicit update interval, and Android can then throttle
    // continuous updates unpredictably (works fine on iOS, silently stalls
    // or lags heavily on many Android devices/OEMs) — this is what made
    // walking "not move" on a real phone even though the same code path
    // works in principle. Requesting updates at a fixed 2-second interval
    // in addition to the 3m distance filter fixes that on Android.
    final LocationSettings walkLocationSettings;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      walkLocationSettings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 3,
        intervalDuration: const Duration(seconds: 1),
        // Bypasses Google Play Services' fused location provider and talks
        // to the platform LocationManager (and GPS chip) directly. Several
        // common Android OEM skins (MIUI, ColorOS, Realme UI — all common
        // on budget/mid-range phones) are known to aggressively throttle or
        // stall the fused provider's continuous updates even in the
        // foreground; forceLocationManager sidesteps that layer entirely.
        forceLocationManager: true,
      );
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      walkLocationSettings = AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 3,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: false,
      );
    } else {
      walkLocationSettings = const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 3,
      );
    }
    walkSub =
        Geolocator.getPositionStream(
          locationSettings: walkLocationSettings,
        ).listen((p) {
          if (!mounted || !walking) return;
          final next = LatLng(p.latitude, p.longitude);
          setState(() {
            liveRaw = next;
            rawFixCount++;
            lastRawFixAt = DateTime.now();
          });
          try {
            _walkMapController.move(next, 17);
          } catch (_) {
            // Map may not be laid out yet on the very first fix — safe to ignore.
          }
          // 20m, not a stricter value — real phone GPS on farmland (often under
          // partial tree canopy) commonly reports 15-25m accuracy; a tighter
          // cutoff silently rejected nearly every fix on real devices, which
          // looked identical to the walk simply not tracking movement at all.
          if (p.accuracy > 20) {
            setState(
              () => liveStatusNote =
                  'Waiting for a more accurate GPS fix (±${p.accuracy.toStringAsFixed(0)}m) — point not recorded yet.',
            );
            return;
          }
          if (walkPoints.isNotEmpty) {
            final prev = walkPoints.last;
            final jump = Geolocator.distanceBetween(
              prev.latitude,
              prev.longitude,
              next.latitude,
              next.longitude,
            );
            // Raised from 2m to 4m: consumer GPS jitter while walking slowly or
            // pausing is often larger than 2m, and each jittery fix that clears
            // only a 2m bar still gets recorded as a "new" point — producing
            // the dense, tangled clusters of points seen on real device tests.
            // 4m gives more breathing room before a point counts as new, and
            // works together with the Douglas-Peucker simplification pass
            // applied when the walk finishes (see _simplifyPath).
            if (jump < 4) {
              setState(() => liveStatusNote = null);
              return; // too close to the last point to be a new one
            }
            if (jump > 80) {
              setState(
                () => liveStatusNote =
                    'Ignored a GPS jump of ${jump.toStringAsFixed(0)}m — that looked like a bad reading, not a real step.',
              );
              return;
            }
            distanceM += jump;
          }
          setState(() {
            walkPoints.add(next);
            lastAccuracy = p.accuracy;
            liveStatusNote = null;
          });
        }, onError: (e) => _snack('GPS error: $e'));
  }

  Future<void> _cancelWalk() async {
    await walkSub?.cancel();
    _tickTimer?.cancel();
    setState(() {
      walking = false;
      walkPoints.clear();
      distanceM = 0;
      lastAccuracy = null;
      liveRaw = null;
      liveStatusNote = null;
    });
  }

  Future<void> _finishWalk() async {
    await walkSub?.cancel();
    _tickTimer?.cancel();
    if (walkPoints.length < 3) {
      _snack(
        'Walk farther around the parcel. At least three valid GPS points are required.',
      );
      return;
    }
    // Simplify the raw walked path before showing it for review — this is
    // what turns a dense, jittery, self-crossing trace into a clean shape
    // that actually matches the field's real outline. Falls back to the
    // raw points if simplification would leave fewer than 3 (shouldn't
    // normally happen, but never show an unusable 0/1/2-point "polygon").
    final simplified = _simplifyPath(List<LatLng>.from(walkPoints));
    final finalPoints = simplified.length >= 3
        ? simplified
        : List<LatLng>.from(walkPoints);
    setState(() {
      walking = false;
      reviewPoints = finalPoints;
      reviewMethod = 'gps_walk';
      reviewAccuracy = lastAccuracy;
      reviewRawPointCount = walkPoints.length;
    });
  }

  void _saveManual() {
    final points = List<LatLng>.from(widget.state.polygonPoints);
    if (points.length < 3) {
      _snack(
        'Draw a polygon on the Map page first, then return here to save it.',
      );
      return;
    }
    setState(() {
      reviewPoints = points;
      reviewMethod = 'manual_draw';
      reviewAccuracy = null;
      reviewRawPointCount = null;
    });
  }

  void _discardReview() {
    setState(() {
      reviewPoints = null;
      reviewMethod = null;
      reviewAccuracy = null;
      reviewRawPointCount = null;
    });
  }

  Future<void> _confirmReview() async {
    final points = reviewPoints;
    final method = reviewMethod;
    if (points == null || method == null) return;
    await _saveFarm(points, method, reviewAccuracy);
  }

  Future<void> _saveFarm(
    List<LatLng> points,
    String method,
    double? accuracy,
  ) async {
    final name = TextEditingController();
    final location = TextEditingController(
      text: widget.state.selectedPlaceName,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Save Farm Parcel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(
                labelText: 'Farm name',
                hintText: 'e.g., Riverside Rice Field',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: location,
              decoration: const InputDecoration(
                labelText: 'Location description',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Estimated area: ${_areaHectares(points).toStringAsFixed(3)} ha',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'This is an agricultural estimate, not a legal cadastral survey.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save Farm'),
          ),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await widget.state.api.createFarm(
        farmName: name.text.trim(),
        locationName: location.text.trim(),
        mappingMethod: method,
        gpsAccuracyM: accuracy,
        polygon: points
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
      );
      _snack(
        'Farm parcel saved. You can reuse this boundary for future wet- or dry-season analyses.',
      );
      _discardReview();
      await _load();
    } catch (e) {
      _snack(friendlyErrorMessage(e));
    }
  }

  Future<void> _analyze(Map<String, dynamic> farm) async {
    final err = await widget.state.analyzeSavedFarm(farm);
    if (err != null) {
      _snack(err);
    } else if (mounted) {
      Navigator.pop(context, true);
    }
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  Widget _buildWalkingMap() {
    final center =
        liveRaw ??
        (walkPoints.isNotEmpty ? walkPoints.last : const LatLng(7.30, 125.65));
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 240,
        child: FlutterMap(
          mapController: _walkMapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 17,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.geosustain.mobile',
            ),
            if (walkPoints.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(points: walkPoints, color: green, strokeWidth: 4),
                ],
              ),
            if (walkPoints.length >= 3)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: walkPoints,
                    color: green.withValues(alpha: 0.18),
                    borderColor: green,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                ...walkPoints.asMap().entries.map(
                  (e) => Marker(
                    point: e.value,
                    width: 10,
                    height: 10,
                    child: Container(
                      decoration: BoxDecoration(
                        color: green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                ),
                if (liveRaw != null)
                  Marker(
                    point: liveRaw!,
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.my_location_rounded,
                      color: Colors.blueAccent,
                      size: 30,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalkingCard() {
    final approxArea = walkPoints.length >= 3
        ? _areaHectares(walkPoints)
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: const [
                Icon(Icons.directions_walk_rounded, color: green),
                SizedBox(width: 8),
                Text(
                  'Walking Boundary',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: green,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildWalkingMap(),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('${walkPoints.length} points recorded')),
                Chip(label: Text('${distanceM.toStringAsFixed(0)} m walked')),
                Chip(
                  label: Text(
                    lastAccuracy == null
                        ? 'GPS accuracy: --'
                        : 'GPS accuracy: ±${lastAccuracy!.toStringAsFixed(1)} m',
                  ),
                ),
                if (approxArea != null)
                  Chip(
                    label: Text('~${approxArea.toStringAsFixed(3)} ha so far'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  rawFixCount > 0
                      ? Icons.sensors_rounded
                      : Icons.sensors_off_rounded,
                  size: 14,
                  color: rawFixCount > 0 ? green : Colors.redAccent,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    rawFixCount == 0
                        ? 'No GPS signal received yet — waiting for your phone\'s location...'
                        : 'GPS signal: $rawFixCount update${rawFixCount == 1 ? '' : 's'} received'
                              '${lastRawFixAt == null ? '' : ' (last ${DateTime.now().difference(lastRawFixAt!).inSeconds}s ago)'}',
                    style: TextStyle(
                      fontSize: 11,
                      color: rawFixCount == 0
                          ? Colors.redAccent
                          : Colors.black45,
                      fontWeight: rawFixCount == 0
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
            if (liveStatusNote != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.gps_not_fixed_rounded,
                    size: 16,
                    color: Colors.black45,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      liveStatusNote!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _cancelWalk,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _finishWalk,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Finish Walking'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewCard() {
    final points = reviewPoints!;
    final warnings = _boundaryWarnings(points);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Review Boundary',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              reviewMethod == 'gps_walk'
                  ? 'Recorded by walking the parcel with GPS.'
                  : 'Drawn manually on the map.',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 240,
                child: FlutterMap(
                  options: MapOptions(
                    initialCameraFit: CameraFit.coordinates(
                      coordinates: points,
                      padding: const EdgeInsets.all(32),
                    ),
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.geosustain.mobile',
                    ),
                    PolygonLayer(
                      polygons: [
                        Polygon(
                          points: points,
                          color: green.withValues(alpha: 0.22),
                          borderColor: green,
                          borderStrokeWidth: 3,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: points
                          .asMap()
                          .entries
                          .map(
                            (e) => Marker(
                              point: e.value,
                              width: 22,
                              height: 22,
                              child: CircleAvatar(
                                backgroundColor: green,
                                radius: 9,
                                child: Text(
                                  '${e.key + 1}',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    reviewRawPointCount != null &&
                            reviewRawPointCount! > points.length
                        ? '${points.length} vertices (simplified from $reviewRawPointCount walked points)'
                        : '${points.length} vertices',
                  ),
                ),
                Chip(
                  label: Text(
                    'Estimated area: ${_areaHectares(points).toStringAsFixed(3)} ha',
                  ),
                ),
              ],
            ),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final w in warnings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: Color(0xFFB26A00),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                w,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF7A4A00),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
            const Text(
              'This boundary is an agricultural estimate, not a legal cadastral survey.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _discardReview,
                    icon: const Icon(Icons.undo_rounded),
                    label: const Text('Discard & Redraw'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _confirmReview,
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text('Looks Good — Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Farms'),
        backgroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          if (reviewPoints != null)
            _buildReviewCard()
          else if (walking)
            _buildWalkingCard()
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Register a Farm Parcel',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Walk the boundary using GPS or save the polygon drawn on the map. Each farm is stored separately and can be analyzed many times.',
                      style: TextStyle(color: Colors.black54, height: 1.35),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _startWalk,
                      icon: const Icon(Icons.directions_walk_rounded),
                      label: const Text('Walk My Farm Boundary'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _saveManual,
                      icon: const Icon(Icons.draw_rounded),
                      label: const Text('Save Boundary Drawn on Map'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _testLocation,
                      icon: const Icon(Icons.gps_fixed_rounded, size: 16),
                      label: const Text(
                        'Test my GPS location',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Saved Farm Parcels',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (farms.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No farms saved yet. Walk or draw your first parcel boundary above.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ...farms.map(
              (farm) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.landscape_rounded, color: green),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${farm['farm_name']}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'archive') {
                                await widget.state.api.updateFarm(
                                  int.parse('${farm['id']}'),
                                  {'is_archived': true},
                                );
                                _load();
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'archive',
                                child: Text('Archive farm'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${farm['location_name'] ?? 'Location not named'}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            label: Text(
                              '${(double.tryParse('${farm['area_hectares']}') ?? 0).toStringAsFixed(3)} ha',
                            ),
                          ),
                          Chip(
                            label: Text(
                              farm['mapping_method'] == 'gps_walk'
                                  ? 'GPS walked'
                                  : 'Map drawn',
                            ),
                          ),
                          Chip(
                            label: Text(
                              '${farm['analysis_count'] ?? 0} analyses',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _analyze(farm),
                          icon: const Icon(Icons.analytics_outlined),
                          label: const Text('Analyze This Farm'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
