part of '../../main.dart';

bool _isCropAnalysisRecord(Map<String, dynamic> record) {
  final raw = record['is_crop_recommended'];
  if (raw is bool) return raw;
  final text = '$raw'.trim().toLowerCase();
  if (text == 'true' || text == '1') return true;
  if (text == 'false' || text == '0') return false;
  final landType = '${record['land_type'] ?? ''}'.trim().toLowerCase();
  return landType.isEmpty || landType == 'arable';
}

String _mapRecordPrimaryValue(Map<String, dynamic> record) {
  if (_isCropAnalysisRecord(record)) {
    return '${record['crop_recommendation'] ?? record['recommended_crop'] ?? record['predicted_crop'] ?? record['crop'] ?? 'No crop'}';
  }
  return '${record['land_status'] ?? record['recommendation_title'] ?? record['predicted_crop'] ?? 'Non-arable area'}';
}

double? _recordAreaHectares(Map<String, dynamic> record) {
  final raw = record['area_hectares'] ?? record['area_ha'];
  final stored = raw is num ? raw.toDouble() : double.tryParse('$raw');
  if (stored != null && stored > 0) return stored;

  dynamic polygon = record['selected_polygon'] ?? record['polygon'];
  if (polygon is String && polygon.trim().isNotEmpty) {
    try {
      polygon = jsonDecode(polygon);
    } catch (_) {}
  }
  if (polygon is Map) {
    final type = '${polygon['type'] ?? ''}'.toLowerCase();
    final coordinates = polygon['coordinates'];
    if (type == 'polygon' && coordinates is List && coordinates.isNotEmpty) {
      polygon = coordinates.first;
    } else if (polygon['points'] is List) {
      polygon = polygon['points'];
    }
  }
  if (polygon is! List || polygon.length < 3) return null;

  final points = <LatLng>[];
  for (final item in polygon) {
    try {
      if (item is Map) {
        final latRaw = item['lat'] ?? item['latitude'];
        final lonRaw = item['lng'] ?? item['lon'] ?? item['longitude'];
        final lat = latRaw is num
            ? latRaw.toDouble()
            : double.tryParse('$latRaw');
        final lon = lonRaw is num
            ? lonRaw.toDouble()
            : double.tryParse('$lonRaw');
        if (lat != null && lon != null) points.add(LatLng(lat, lon));
      } else if (item is List && item.length >= 2) {
        final a = item[0] is num
            ? (item[0] as num).toDouble()
            : double.tryParse('${item[0]}');
        final b = item[1] is num
            ? (item[1] as num).toDouble()
            : double.tryParse('${item[1]}');
        if (a == null || b == null) continue;
        // GeoJSON uses [longitude, latitude]; app-native arrays use [latitude, longitude].
        final looksGeoJson = a.abs() > 90 && b.abs() <= 90;
        points.add(looksGeoJson ? LatLng(b, a) : LatLng(a, b));
      }
    } catch (_) {}
  }
  if (points.length < 3) return null;
  const earthRadius = 6378137.0;
  final meanLat =
      points.map((p) => p.latitude).reduce((a, b) => a + b) /
      points.length *
      math.pi /
      180;
  final xy = points
      .map(
        (p) => Offset(
          earthRadius * p.longitude * math.pi / 180 * math.cos(meanLat),
          earthRadius * p.latitude * math.pi / 180,
        ),
      )
      .toList();
  var twiceArea = 0.0;
  for (var i = 0; i < xy.length; i++) {
    final a = xy[i];
    final b = xy[(i + 1) % xy.length];
    twiceArea += a.dx * b.dy - b.dx * a.dy;
  }
  return twiceArea.abs() / 2 / 10000.0;
}

class WebMapScreen extends StatefulWidget {
  final AnalysisState state;
  final bool popupVisible;
  final VoidCallback onClosePopup;
  final VoidCallback onGoToAnalyzeArea;
  const WebMapScreen({
    super.key,
    required this.state,
    required this.popupVisible,
    required this.onClosePopup,
    required this.onGoToAnalyzeArea,
  });

  @override
  State<WebMapScreen> createState() => _WebMapScreenState();
}

class _WebMapScreenState extends State<WebMapScreen> {
  final MapController _mapController = MapController();
  Map<String, dynamic>? _selected;

  AnalysisState get state => widget.state;

  List<Map<String, dynamic>> get _allMapRecords {
    final merged = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final raw in [...state.historyRecords, ...state.plannerQueue]) {
      final record = state.normalizeRecord(Map<String, dynamic>.from(raw));
      final key = '${record['session_id'] ?? record['id'] ?? ''}';
      final fallback =
          '${record['center_lat']}:${record['center_lon']}:${record['analyzed_at']}';
      final dedupeKey = key.isNotEmpty ? key : fallback;
      if (seen.add(dedupeKey)) merged.add(record);
    }
    return merged;
  }

  Future<void> _loadFarmerSubmissionsForMap() async {
    if (!state.isPlanner) return;
    await state.loadPlannerQueue(status: 'all');
    if (!mounted) return;
    setState(() {
      if (_selected == null && _allMapRecords.isNotEmpty) {
        _selected = Map<String, dynamic>.from(_allMapRecords.first);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (state.historyRecords.isNotEmpty) {
      _selected = Map<String, dynamic>.from(state.historyRecords.first);
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadFarmerSubmissionsForMap(),
    );
  }

  LatLng? _pointFromRecord(Map<String, dynamic> record) {
    final latRaw = record['center_lat'] ?? record['lat'] ?? record['latitude'];
    final lonRaw =
        record['center_lon'] ??
        record['lon'] ??
        record['lng'] ??
        record['longitude'];
    final lat = latRaw is num ? latRaw.toDouble() : double.tryParse('$latRaw');
    final lon = lonRaw is num ? lonRaw.toDouble() : double.tryParse('$lonRaw');
    if (lat == null || lon == null) return null;
    return LatLng(lat, lon);
  }

  List<LatLng> _polygonFromRecord(Map<String, dynamic> record) {
    dynamic raw = record['selected_polygon'] ?? record['polygon'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {}
    }
    if (raw is Map) {
      final coordinates = raw['coordinates'];
      if ('${raw['type'] ?? ''}'.toLowerCase() == 'polygon' &&
          coordinates is List &&
          coordinates.isNotEmpty) {
        raw = coordinates.first;
      } else if (raw['points'] is List) {
        raw = raw['points'];
      }
    }
    if (raw is! List) return const [];
    final result = <LatLng>[];
    for (final item in raw) {
      if (item is Map) {
        final latRaw = item['lat'] ?? item['latitude'];
        final lngRaw = item['lng'] ?? item['lon'] ?? item['longitude'];
        final lat = latRaw is num
            ? latRaw.toDouble()
            : double.tryParse('$latRaw');
        final lng = lngRaw is num
            ? lngRaw.toDouble()
            : double.tryParse('$lngRaw');
        if (lat != null && lng != null) result.add(LatLng(lat, lng));
      } else if (item is List && item.length >= 2) {
        final a = item[0] is num
            ? (item[0] as num).toDouble()
            : double.tryParse('${item[0]}');
        final b = item[1] is num
            ? (item[1] as num).toDouble()
            : double.tryParse('${item[1]}');
        if (a == null || b == null) continue;
        result.add(a.abs() > 90 && b.abs() <= 90 ? LatLng(b, a) : LatLng(a, b));
      }
    }
    return result;
  }

  double? _suitability(Map<String, dynamic> record) {
    final raw =
        record['crop_compatibility_pct'] ??
        record['compatibility_pct'] ??
        record['suitability'];
    return raw is num ? raw.toDouble() : double.tryParse('$raw');
  }

  String _crop(Map<String, dynamic> record) => _mapRecordPrimaryValue(record);

  String _place(Map<String, dynamic> record) =>
      '${record['place_name'] ?? record['location'] ?? record['address'] ?? 'Analyzed Area'}';

  Color _markerColor(double? value) {
    if (value == null) return const Color(0xFF8B97A3);
    if (value >= 75) return const Color(0xFF087A47);
    if (value >= 50) return const Color(0xFF7CCF55);
    if (value >= 25) return const Color(0xFFF0A51A);
    return const Color(0xFFE84F4F);
  }

  String _label(double? value) {
    if (value == null) return 'No data';
    if (value >= 75) return 'Highly Suitable';
    if (value >= 50) return 'Suitable';
    if (value >= 25) return 'Moderately Suitable';
    return 'Low Suitability';
  }

  void _select(Map<String, dynamic> record) {
    // Selecting a marker should not recenter the map; it only highlights the
    // saved coordinate and opens the anchored information card.
    setState(
      () =>
          _selected = record.isEmpty ? null : Map<String, dynamic>.from(record),
    );
  }

  Future<void> _openDetails(
    BuildContext context,
    Map<String, dynamic> record,
  ) async {
    final rawId = record['session_id'] ?? record['id'];
    final sessionId = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
    if (state.isPlanner && sessionId != null) {
      await openPlannerAnalysisReview(context, state, sessionId);
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => _WebHistoryDetailDialog(
        record: state.normalizeRecord(Map<String, dynamic>.from(record)),
        state: state,
        topCrop: _crop(record),
        suitabilityPct: _suitability(record),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mapRecords = _allMapRecords;
    final rows = mapRecords.take(5).toList();
    final validSuitability = mapRecords
        .map(_suitability)
        .whereType<double>()
        .toList();
    final average = validSuitability.isEmpty
        ? null
        : validSuitability.reduce((a, b) => a + b) / validSuitability.length;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 8,
          child: _WebCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Interactive Review Map',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      _ToolbarChip(
                        icon: Icons.layers_rounded,
                        label: state.satellite ? 'Satellite' : 'Street',
                        onTap: state.toggleSatellite,
                      ),
                      const SizedBox(width: 8),
                      _ToolbarChip(
                        icon: Icons.filter_alt_outlined,
                        label: 'All Markers  ${mapRecords.length}',
                        onTap: () {},
                      ),
                    ],
                  ),
                ),
                _InteractiveReviewMap(
                  state: state,
                  records: mapRecords,
                  mapController: _mapController,
                  selected: _selected,
                  onSelect: _select,
                  onOpenDetails: (r) => _openDetails(context, r),
                  pointFromRecord: _pointFromRecord,
                  polygonFromRecord: _polygonFromRecord,
                  suitability: _suitability,
                  crop: _crop,
                  place: _place,
                  markerColor: _markerColor,
                  suitabilityLabel: _label,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 18),
        SizedBox(
          width: 370,
          child: Column(
            children: [
              _WebCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'GIS Review Summary',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SummaryMetric(
                      icon: Icons.location_on_rounded,
                      label: 'Total Analyzed Lands',
                      value: '${mapRecords.length}',
                      caption: 'Across all saved analyses',
                    ),
                    const Divider(height: 24),
                    _SummaryMetric(
                      icon: Icons.eco_rounded,
                      label: 'Average Suitability',
                      value: average == null
                          ? '--'
                          : '${average.toStringAsFixed(1)}%',
                      caption: 'Across all analyzed lands',
                    ),
                    const Divider(height: 24),
                    _SummaryMetric(
                      icon: Icons.trending_up_rounded,
                      label: 'Infrastructure Overlays',
                      value: 'Ready',
                      caption: 'Available during land review',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _WebCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Recent Analyzed Lands',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          '${rows.length} shown',
                          style: const TextStyle(
                            color: Colors.black45,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: Text(
                            'No analyzed areas yet.',
                            style: TextStyle(color: Colors.black45),
                          ),
                        ),
                      )
                    else
                      ...rows.map(
                        (r) => _RecentLandRow(
                          record: r,
                          selected:
                              identical(r, _selected) ||
                              (r['session_id'] != null &&
                                  r['session_id'] == _selected?['session_id']),
                          place: _place(r),
                          crop: _crop(r),
                          suitability: _suitability(r),
                          color: _markerColor(_suitability(r)),
                          onTap: () => _select(r),
                        ),
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: widget.onGoToAnalyzeArea,
                        icon: const Icon(Icons.center_focus_strong_rounded),
                        label: const Text('Go to Analyze Area'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: green,
                          padding: const EdgeInsets.symmetric(vertical: 15),
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
    );
  }
}

class _ToolbarChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ToolbarChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 18),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFF26352C),
      side: const BorderSide(color: Color(0xFFDCE6DE)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );
}

class _SummaryMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String caption;
  const _SummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: softGreen,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: green),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: green,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              caption,
              style: const TextStyle(color: Colors.black45, fontSize: 11),
            ),
          ],
        ),
      ),
    ],
  );
}

class _RecentLandRow extends StatelessWidget {
  final Map<String, dynamic> record;
  final bool selected;
  final String place;
  final String crop;
  final double? suitability;
  final Color color;
  final VoidCallback onTap;
  const _RecentLandRow({
    required this.record,
    required this.selected,
    required this.place,
    required this.crop,
    required this.suitability,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final date = '${record['date'] ?? record['analyzed_at'] ?? ''}'
        .split('T')
        .first;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: selected ? softGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? green.withValues(alpha: .28) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 39,
              height: 39,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .13),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.eco_rounded, color: color, size: 21),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$crop${date.isEmpty ? '' : ' • $date'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black45, fontSize: 11),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                suitability == null
                    ? '--'
                    : '${suitability!.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InteractiveReviewMap extends StatelessWidget {
  final AnalysisState state;
  final List<Map<String, dynamic>> records;
  final MapController mapController;
  final Map<String, dynamic>? selected;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final ValueChanged<Map<String, dynamic>> onOpenDetails;
  final LatLng? Function(Map<String, dynamic>) pointFromRecord;
  final List<LatLng> Function(Map<String, dynamic>) polygonFromRecord;
  final double? Function(Map<String, dynamic>) suitability;
  final String Function(Map<String, dynamic>) crop;
  final String Function(Map<String, dynamic>) place;
  final Color Function(double?) markerColor;
  final String Function(double?) suitabilityLabel;

  const _InteractiveReviewMap({
    required this.state,
    required this.records,
    required this.mapController,
    required this.selected,
    required this.onSelect,
    required this.onOpenDetails,
    required this.pointFromRecord,
    required this.polygonFromRecord,
    required this.suitability,
    required this.crop,
    required this.place,
    required this.markerColor,
    required this.suitabilityLabel,
  });

  @override
  Widget build(BuildContext context) {
    final selectedPoint = selected == null ? null : pointFromRecord(selected!);
    final markers = <Marker>[];
    final parcelPolygons = <Polygon>[];

    for (final record in records.take(60)) {
      final point = pointFromRecord(record);
      if (point == null) continue;
      final isSelected =
          selected != null &&
          record['session_id'] != null &&
          record['session_id'] == selected!['session_id'];
      final value = suitability(record);
      final color = markerColor(value);
      final boundary = polygonFromRecord(record);
      if (boundary.length >= 3) {
        parcelPolygons.add(
          Polygon(
            points: boundary,
            color: color.withValues(alpha: isSelected ? .28 : .10),
            borderColor: isSelected ? color : color.withValues(alpha: .65),
            borderStrokeWidth: isSelected ? 3.5 : 1.8,
          ),
        );
      }

      if (isSelected) {
        // One anchored marker contains both the original pin and its popup.
        // The pin remains at the saved coordinate and the card is positioned
        // directly above it, matching standard map callout behavior.
        markers.add(
          Marker(
            point: point,
            width: 350,
            height: 305,
            alignment: Alignment.bottomCenter,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                Positioned(
                  bottom: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(record),
                    child: Icon(
                      Icons.location_on_rounded,
                      color: color,
                      size: 48,
                      shadows: const [
                        Shadow(color: Colors.black26, blurRadius: 5),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 5,
                  right: 5,
                  bottom: 58,
                  child: _MarkerInfoCard(
                    record: record,
                    place: place(record),
                    crop: crop(record),
                    suitability: value,
                    suitabilityLabel: suitabilityLabel(value),
                    markerColor: color,
                    onClose: () => onSelect(<String, dynamic>{}),
                    onOpenDetails: () => onOpenDetails(record),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        markers.add(
          Marker(
            point: point,
            width: 48,
            height: 54,
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(record),
              child: Icon(
                Icons.location_on_rounded,
                color: color,
                size: 43,
                shadows: const [Shadow(color: Colors.black26, blurRadius: 5)],
              ),
            ),
          ),
        );
      }
    }
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(20),
        bottomRight: Radius.circular(20),
      ),
      child: SizedBox(
        height: 650,
        child: Stack(
          children: [
            FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: selectedPoint ?? state.selectedPoint,
                initialZoom: 12.8,
                minZoom: 10,
                maxZoom: 18,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: state.satellite
                      ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.geosustain.mobile',
                ),
                if (parcelPolygons.isNotEmpty)
                  PolygonLayer(polygons: parcelPolygons),
                MarkerLayer(markers: markers),
              ],
            ),
            Positioned(left: 18, bottom: 18, child: _SuitabilityLegend()),
            Positioned(
              right: 18,
              bottom: 18,
              child: Column(
                children: [
                  _MapControl(
                    icon: Icons.add_rounded,
                    onTap: () {
                      try {
                        mapController.move(
                          mapController.camera.center,
                          mapController.camera.zoom + 1,
                        );
                      } catch (_) {}
                    },
                  ),
                  const SizedBox(height: 6),
                  _MapControl(
                    icon: Icons.remove_rounded,
                    onTap: () {
                      try {
                        mapController.move(
                          mapController.camera.center,
                          mapController.camera.zoom - 1,
                        );
                      } catch (_) {}
                    },
                  ),
                  const SizedBox(height: 6),
                  _MapControl(
                    icon: Icons.my_location_rounded,
                    onTap: () {
                      try {
                        mapController.move(
                          selectedPoint ?? state.selectedPoint,
                          13.2,
                        );
                      } catch (_) {}
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapControl extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MapControl({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    elevation: 2,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 43,
        height: 43,
        child: Icon(icon, color: const Color(0xFF26352C)),
      ),
    ),
  );
}

class _MarkerInfoCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final String place;
  final String crop;
  final double? suitability;
  final String suitabilityLabel;
  final Color markerColor;
  final VoidCallback onClose;
  final VoidCallback onOpenDetails;
  const _MarkerInfoCard({
    required this.record,
    required this.place,
    required this.crop,
    required this.suitability,
    required this.suitabilityLabel,
    required this.markerColor,
    required this.onClose,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    final date = '${record['date'] ?? record['analyzed_at'] ?? ''}'
        .split('T')
        .first;
    final areaHa = _recordAreaHectares(record);
    final area = areaHa == null
        ? '--'
        : '${areaHa.toStringAsFixed(areaHa < 1 ? 3 : 2)} ha';
    final isCrop = _isCropAnalysisRecord(record);
    final primaryLabel = isCrop ? 'Recommended Crop' : 'Land Assessment';
    final scoreLabel = isCrop ? 'Suitability' : 'Agricultural Use';
    final scoreValue = isCrop && suitability != null
        ? '${suitability!.toStringAsFixed(1)}%'
        : 'Not recommended';
    final badgeText = isCrop ? suitabilityLabel : 'Non-arable';
    return Material(
      color: Colors.transparent,
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 306,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE0E9E2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: markerColor.withValues(alpha: .13),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.eco_rounded, color: markerColor, size: 21),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$primaryLabel: $crop',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: onClose,
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(Icons.close_rounded, size: 18),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scoreLabel,
                        style: const TextStyle(
                          color: Colors.black45,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        scoreValue,
                        style: TextStyle(
                          color: markerColor,
                          fontSize: isCrop ? 24 : 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: markerColor.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      color: markerColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _MiniInfo(
                    icon: Icons.calendar_month_rounded,
                    label: 'Date',
                    value: date.isEmpty ? '--' : date,
                  ),
                ),
                Expanded(
                  child: _MiniInfo(
                    icon: Icons.crop_square_rounded,
                    label: 'Area',
                    value: area,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onOpenDetails,
                style: OutlinedButton.styleFrom(
                  foregroundColor: green,
                  backgroundColor: softGreen,
                  side: BorderSide.none,
                ),
                child: const Text('View Details'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _MiniInfo({
    required this.icon,
    required this.label,
    required this.value,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 17, color: Colors.black54),
      const SizedBox(width: 6),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.black45, fontSize: 9),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ],
  );
}
