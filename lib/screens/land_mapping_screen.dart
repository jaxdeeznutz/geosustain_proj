part of '../main.dart';

Future<void> showLandMethodPicker(
  BuildContext context,
  AnalysisState state,
  VoidCallback onAnalyzed,
) async {
  final method = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'How would you like to map your land?',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            _LandMethodCard(
              gps: true,
              onTap: () => Navigator.pop(context, 'gps'),
            ),
            _LandMethodCard(
              gps: false,
              onTap: () => Navigator.pop(context, 'draw'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
  if (method == null || !context.mounted) return;
  await openLandMethod(context, state, method == 'gps', onAnalyzed);
}

Future<void> openLandMethod(
  BuildContext context,
  AnalysisState state,
  bool gps,
  VoidCallback onAnalyzed,
) async {
  final analyzed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => gps
          ? FarmBoundaryPage(state: state)
          : PolygonDrawingPage(state: state),
    ),
  );
  if (analyzed == true && context.mounted) onAnalyzed();
}

class _LandMethodCard extends StatelessWidget {
  final bool gps;
  final VoidCallback onTap;
  const _LandMethodCard({required this.gps, required this.onTap});
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      leading: Icon(
        gps ? Icons.directions_walk : Icons.draw_outlined,
        color: green,
      ),
      title: Text(
        gps ? 'Create a Farm Boundary' : 'Analyze Land Using a Polygon',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        gps
            ? 'Walk around your farm to record its boundary using GPS.'
            : 'Draw an area on the map to analyze its land suitability.',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class FarmBoundaryPage extends StatefulWidget {
  final AnalysisState state;
  const FarmBoundaryPage({super.key, required this.state});
  @override
  State<FarmBoundaryPage> createState() => _FarmBoundaryPageState();
}

class _FarmBoundaryPageState extends State<FarmBoundaryPage>
    with WidgetsBindingObserver {
  final _controller = MapController();
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _points = <LatLng>[];
  final _times = <DateTime>[];
  final _accuracies = <double>[];
  StreamSubscription<Position>? _subscription;
  Timer? _signalTimer;
  DateTime? _lastFixAt;
  LatLng? _current;
  double? _accuracy;
  bool _recording = false, _starting = false, _review = false, _busy = false;
  String? _notice;
  bool _showAppSettings = false, _showLocationSettings = false;
  Map<String, dynamic>? _saved;
  String? _saveKey;
  String? _saveFingerprint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _signalTimer?.cancel();
    _controller.dispose();
    _name.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _recording) {
      _pause(
        'Recording paused because the app left the foreground. Return to your last point and tap Resume.',
      );
    }
  }

  void _message(String text) {
    if (mounted) setState(() => _notice = text);
  }

  void _pause([String? message]) {
    // Flip the flag before cancelling: queued fixes must not enter the polygon.
    _recording = false;
    _subscription?.cancel();
    _subscription = null;
    _signalTimer?.cancel();
    if (mounted) {
      setState(
        () => _notice =
            message ??
            'Recording paused. Resume near your last recorded point.',
      );
    }
  }

  Future<void> _start() async {
    if (_starting || _recording || _busy) return;
    setState(() {
      _starting = true;
      _showAppSettings = false;
      _showLocationSettings = false;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        setState(() => _showLocationSettings = true);
        _message(
          'Device location is off. Enable GPS, return here, and tap Start or Resume.',
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!mounted) return;
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _showAppSettings = true);
        _message(
          'Allow location access while using GeoSustain to record a boundary. On the web, also check this site’s browser permissions.',
        );
        return;
      }
      if (WidgetsBinding.instance.lifecycleState != null &&
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        _message('Return to GeoSustain before starting the recording.');
        return;
      }
      final LocationSettings settings =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.best,
              distanceFilter: 3,
              intervalDuration: const Duration(seconds: 1),
              forceLocationManager: true,
            )
          : !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
          ? AppleSettings(
              accuracy: LocationAccuracy.best,
              distanceFilter: 3,
              activityType: ActivityType.fitness,
              pauseLocationUpdatesAutomatically: false,
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.best,
              distanceFilter: 3,
            );
      setState(() {
        _recording = true;
        _review = false;
        _notice = 'Waiting for a stable GPS fix…';
      });
      _lastFixAt = DateTime.now();
      _signalTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_recording &&
            _lastFixAt != null &&
            DateTime.now().difference(_lastFixAt!).inSeconds > 20) {
          _message(
            'No recent GPS update. Stop walking until a fresh fix arrives, or Pause and retry in an open area.',
          );
        }
      });
      _subscription = Geolocator.getPositionStream(locationSettings: settings).listen(
        _onPosition,
        onError: (Object error) => _pause(
          'Location recording stopped: ${friendlyErrorMessage(error)}. Check GPS and Resume.',
        ),
        onDone: () {
          if (_recording) {
            _pause(
              'GPS recording was interrupted. Check location access and Resume.',
            );
          }
        },
      );
    } catch (error) {
      _pause('Unable to start GPS: ${friendlyErrorMessage(error)}');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _onPosition(Position fix) {
    if (!mounted || !_recording) return;
    if (!fix.latitude.isFinite ||
        !fix.longitude.isFinite ||
        fix.latitude.abs() > 90 ||
        fix.longitude.abs() > 180) {
      _message('An invalid GPS coordinate was ignored.');
      return;
    }
    final point = LatLng(fix.latitude, fix.longitude);
    _lastFixAt = DateTime.now();
    final rejection = FarmGpsFilter.rejection(
      point: point,
      accuracy: fix.accuracy,
      timestamp: fix.timestamp,
      previous: _points.lastOrNull,
      previousTimestamp: _times.lastOrNull,
    );
    setState(() {
      _current = point;
      _accuracy = fix.accuracy;
      _notice = rejection;
      if (rejection == null) {
        _points.add(point);
        _times.add(fix.timestamp);
        _accuracies.add(fix.accuracy);
      }
    });
    if (_points.length == 1 && rejection == null) _controller.move(point, 18);
    if (_points.length >= 2000) {
      _pause(
        'The 2,000-point limit was reached. Review this recording before saving.',
      );
    }
  }

  void _finish() {
    _pause();
    final error = FarmGeometry.validate(_points);
    setState(() {
      _review = error == null;
      _notice = error;
    });
    if (error == null) {
      _controller.fitCamera(
        CameraFit.coordinates(
          coordinates: _points,
          padding: const EdgeInsets.all(28),
        ),
      );
    }
  }

  Future<void> _save() async {
    if (_busy || _saved != null) return;
    final error = FarmGeometry.validate(_points);
    if (error != null) {
      _message(error);
      return;
    }
    if (_name.text.trim().isEmpty) {
      _message('Enter a farm name before saving.');
      return;
    }
    final payload = FarmGeometry.payload(_points);
    final fingerprint = jsonEncode([
      payload,
      _name.text.trim(),
      _location.text.trim(),
    ]);
    if (fingerprint != _saveFingerprint) {
      _saveFingerprint = fingerprint;
      _saveKey =
          'farm-gps-${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(1 << 30)}';
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final farm = await widget.state.api.createFarm(
        farmName: _name.text.trim(),
        locationName: _location.text.trim(),
        polygon: payload,
        mappingMethod: 'gps_walk',
        requestId: _saveKey,
        gpsAccuracyM: _accuracies.isEmpty ? null : _accuracies.reduce(math.max),
      );
      widget.state.replaceFarms([
        farm,
        ...widget.state.farms.where((f) => '${f['id']}' != '${farm['id']}'),
      ]);
      if (mounted) {
        setState(() {
          _saved = farm;
          _notice =
              'Farm saved. You can analyze it now or return to My Farms. It has not been submitted for analyst review.';
        });
      }
    } catch (error) {
      _message(friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _analyze() async {
    if (_saved == null || _busy) return;
    setState(() => _busy = true);
    final error = await widget.state.analyzeSavedFarm(_saved!);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      _message(error);
      return;
    }
    Navigator.pop(context, true);
  }

  Future<bool> _mayLeave() async {
    if (_busy) return false;
    _pause();
    if (_saved != null || _points.isEmpty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard this recording?'),
            content: const Text(
              'GPS is paused. This boundary has not been saved. Stay here to review it, or discard and leave.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep recording'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final area = FarmGeometry.areaSquareMetres(_points) / 10000;
    final gap = _points.length < 3
        ? 0.0
        : FarmGeometry.distance(_points.first, _points.last);
    return PopScope<bool>(
      canPop: !_busy && !_recording && (_points.isEmpty || _saved != null),
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && await _mayLeave() && context.mounted) {
          setState(() {
            _points.clear();
            _recording = false;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.pop(context);
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Create a Farm Boundary')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Start at a farm corner, then walk safely around the perimeter and return close to your starting point. Keep the phone outdoors with a clear view of the sky.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Recording pauses when the app is backgrounded. Leaving discards an unsaved recording; saved farms remain available.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              _BoundaryMap(
                controller: _controller,
                points: _points,
                current: _current,
                closed: _review || _saved != null,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Chip(
                    avatar: Icon(
                      _recording
                          ? Icons.fiber_manual_record
                          : Icons.pause_circle_outline,
                      size: 16,
                    ),
                    label: Text(
                      _saved != null
                          ? 'Saved'
                          : _review
                          ? 'Boundary preview'
                          : _recording
                          ? 'Recording'
                          : 'Not recording',
                    ),
                  ),
                  Chip(label: Text('${_points.length} points')),
                  Chip(
                    label: Text(
                      _accuracy == null
                          ? 'GPS accuracy unavailable'
                          : 'GPS ±${_accuracy!.toStringAsFixed(0)} m',
                    ),
                  ),
                  if (_points.length >= 3)
                    Chip(
                      label: Text('${area.toStringAsFixed(3)} ha (estimate)'),
                    ),
                ],
              ),
              if (_notice != null) _MappingNotice(_notice!),
              if (_showAppSettings && !kIsWeb)
                TextButton.icon(
                  onPressed: () async {
                    final opened = await Geolocator.openAppSettings();
                    if (!opened) {
                      _message(
                        'Open device Settings → Apps → GeoSustain → Permissions → Location. On the web, use the site permission controls.',
                      );
                    }
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('Open permission settings'),
                ),
              if (_showLocationSettings && !kIsWeb)
                TextButton.icon(
                  onPressed: () async {
                    final opened = await Geolocator.openLocationSettings();
                    if (!opened) {
                      _message(
                        'Enable Location/GPS from device settings, then return and start recording.',
                      );
                    }
                  },
                  icon: const Icon(Icons.location_on_outlined),
                  label: const Text('Open location settings'),
                ),
              if (_saved == null && !_review) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _starting || _busy
                          ? null
                          : _recording
                          ? () => _pause()
                          : _start,
                      icon: Icon(_recording ? Icons.pause : Icons.play_arrow),
                      label: Text(
                        _starting
                            ? 'Finding GPS…'
                            : _recording
                            ? 'Pause'
                            : _points.isEmpty
                            ? 'Start'
                            : 'Resume',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _points.isEmpty || _busy || _starting
                          ? null
                          : _finish,
                      icon: const Icon(Icons.stop),
                      label: const Text('Finish'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _recording || _points.isEmpty || _busy
                          ? null
                          : () {
                              setState(() {
                                _points.removeLast();
                                _times.removeLast();
                                _accuracies.removeLast();
                                _notice =
                                    'Last point removed. Resume from the new last point.';
                              });
                            },
                      icon: const Icon(Icons.undo),
                      label: const Text('Undo last point'),
                    ),
                  ],
                ),
              ],
              if (_review && _saved == null) ...[
                Text(
                  'Review the closed boundary. The final edge connects your last point back to the start (${gap.toStringAsFixed(0)} m).',
                ),
                if (gap > 40)
                  const _MappingNotice(
                    'The closing gap is more than 40 m. Check that the closing edge follows your actual farm perimeter; Resume to record the missing edge if needed.',
                  ),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _review = false),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Resume or undo points'),
                ),
                TextField(
                  controller: _name,
                  enabled: !_busy,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Farm name',
                    hintText: 'e.g. Riverside farm',
                  ),
                ),
                TextField(
                  controller: _location,
                  enabled: !_busy,
                  maxLength: 240,
                  decoration: const InputDecoration(
                    labelText: 'Location description (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_busy ? 'Saving…' : 'Confirm and Save Farm'),
                ),
              ],
              if (_saved != null) ...[
                FilledButton.icon(
                  onPressed: _busy ? null : _analyze,
                  icon: const Icon(Icons.analytics_outlined),
                  label: Text(_busy ? 'Analyzing…' : 'Analyze This Farm'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
              if (_busy) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              const Text(
                'GPS boundaries and area are agricultural estimates, not legal land surveys. Poor GPS can affect the boundary even when a reading is accepted.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PolygonDrawingPage extends StatefulWidget {
  final AnalysisState state;
  const PolygonDrawingPage({super.key, required this.state});
  @override
  State<PolygonDrawingPage> createState() => _PolygonDrawingPageState();
}

class _PolygonDrawingPageState extends State<PolygonDrawingPage> {
  final _controller = MapController();
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _points = <LatLng>[];
  final _undo = <List<LatLng>>[];
  String _mode = 'draw';
  int? _selectedVertex;
  String? _notice, _saveKey, _saveFingerprint;
  bool _busy = false, _saveAsFarm = true;
  Map<String, dynamic>? _saved;
  @override
  void dispose() {
    _controller.dispose();
    _name.dispose();
    _location.dispose();
    super.dispose();
  }

  void _tap(LatLng point) {
    if (_busy || _saved != null || _mode == 'pan') return;
    if (!FarmGeometry.insideCoverage(point)) {
      setState(
        () => _notice =
            'Choose points within the supported Panabo City map area.',
      );
      return;
    }
    if (_mode == 'edit' && _selectedVertex == null) {
      setState(
        () => _notice = 'Tap a numbered vertex, then tap its new position.',
      );
      return;
    }
    setState(() {
      _undo.add(List.of(_points));
      if (_mode == 'edit') {
        _points[_selectedVertex!] = point;
        _selectedVertex = null;
      } else {
        _points.add(point);
      }
      _notice = null;
    });
  }

  Future<void> _run({required bool analyze}) async {
    if (_busy) return;
    final error = FarmGeometry.validate(_points);
    if (error != null) {
      setState(() => _notice = error);
      return;
    }
    if ((_saveAsFarm || !analyze) && _name.text.trim().isEmpty) {
      setState(() => _notice = 'Enter a farm name to save this area.');
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      if (_saved == null && (_saveAsFarm || !analyze)) {
        final polygon = FarmGeometry.payload(_points);
        final fingerprint = jsonEncode([
          polygon,
          _name.text.trim(),
          _location.text.trim(),
        ]);
        if (fingerprint != _saveFingerprint) {
          _saveFingerprint = fingerprint;
          _saveKey =
              'farm-draw-${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(1 << 30)}';
        }
        _saved = await widget.state.api.createFarm(
          farmName: _name.text.trim(),
          polygon: polygon,
          locationName: _location.text.trim(),
          mappingMethod: 'manual_draw',
          requestId: _saveKey,
        );
        widget.state.replaceFarms([
          _saved!,
          ...widget.state.farms.where(
            (f) => '${f['id']}' != '${_saved!['id']}',
          ),
        ]);
      }
      if (analyze) {
        String? analysisError;
        if (_saved != null) {
          analysisError = await widget.state.analyzeSavedFarm(_saved!);
        } else {
          widget.state.polygonPoints
            ..clear()
            ..addAll(FarmGeometry.fromPayload(FarmGeometry.payload(_points)));
          analysisError = await widget.state.analyzePolygon();
        }
        if (analysisError != null) throw Exception(analysisError);
        if (mounted) {
          setState(() => _busy = false);
          Navigator.pop(context, true);
        }
      } else if (mounted) {
        setState(
          () => _notice =
              'Farm saved. Select Analyze Area when you are ready. Saving does not request analyst review.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _notice = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Analyze Land Using a Polygon')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Tap around your farm to draw its boundary. Use Edit to select a numbered point and tap its new position. Device location access is not needed.',
            ),
            const SizedBox(height: 12),
            _BoundaryMap(
              controller: _controller,
              points: _points,
              onTap: _tap,
              selectedVertex: _selectedVertex,
              onVertex: _mode != 'edit' || _busy || _saved != null
                  ? null
                  : (index) => setState(() {
                      _selectedVertex = index;
                      _notice = 'Tap the new position for point ${index + 1}.';
                    }),
            ),
            const SizedBox(height: 8),
            Text(
              '${_points.length} vertices · ${(FarmGeometry.areaSquareMetres(_points) / 10000).toStringAsFixed(3)} ha (estimate)',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (_saved == null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in {
                    'draw': 'Draw',
                    'edit': 'Edit',
                    'pan': 'Move map',
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _mode == entry.key,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                              _mode = entry.key;
                              _selectedVertex = null;
                            }),
                    ),
                  OutlinedButton.icon(
                    onPressed: _busy || _undo.isEmpty
                        ? null
                        : () => setState(() {
                            _points
                              ..clear()
                              ..addAll(_undo.removeLast());
                            _selectedVertex = null;
                            _notice = null;
                          }),
                    icon: const Icon(Icons.undo),
                    label: const Text('Undo'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy || _points.isEmpty
                        ? null
                        : () => setState(() {
                            _undo.add(List.of(_points));
                            _points.clear();
                            _selectedVertex = null;
                            _notice = null;
                          }),
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear'),
                  ),
                ],
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _saveAsFarm,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _saveAsFarm = value ?? true),
                title: const Text('Save this area as a farm'),
                subtitle: const Text('Reuse its boundary for later analyses.'),
              ),
              if (_saveAsFarm) ...[
                TextField(
                  controller: _name,
                  enabled: !_busy,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Farm name'),
                ),
                TextField(
                  controller: _location,
                  enabled: !_busy,
                  maxLength: 240,
                  decoration: const InputDecoration(
                    labelText: 'Location description (optional)',
                  ),
                ),
              ],
            ],
            const SizedBox(height: 12),
            if (_notice != null) _MappingNotice(_notice!),
            if (_saved != null)
              Text(
                'Saved as ${_saved!['farm_name']}. Future analyses use this saved farm; no duplicate farm will be created.',
              ),
            if (_busy) const LinearProgressIndicator(),
            FilledButton.icon(
              onPressed: _busy ? null : () => _run(analyze: true),
              icon: const Icon(Icons.analytics_outlined),
              label: Text(_busy ? 'Please wait…' : 'Analyze Area'),
            ),
            if (_saveAsFarm && _saved == null)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(analyze: false),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Farm Without Analysis'),
              ),
            const SizedBox(height: 12),
            const Text(
              'Analysis is automated. You can request analyst review from the result after it completes.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MappingNotice extends StatelessWidget {
  final String message;
  const _MappingNotice(this.message);
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: softGreen,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(message, style: const TextStyle(color: darkGreen)),
  );
}

class _BoundaryMap extends StatelessWidget {
  final MapController? controller;
  final List<LatLng> points;
  final LatLng? current;
  final bool closed;
  final ValueChanged<LatLng>? onTap;
  final ValueChanged<int>? onVertex;
  final int? selectedVertex;
  const _BoundaryMap({
    this.controller,
    required this.points,
    this.current,
    this.closed = true,
    this.onTap,
    this.onVertex,
    this.selectedVertex,
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: math.min(350, MediaQuery.sizeOf(context).height * .42),
          child: FlutterMap(
            mapController: controller,
            options: MapOptions(
              initialCenter: points.firstOrNull ?? panaboCenter,
              initialZoom: 15,
              initialCameraFit: points.length >= 3
                  ? CameraFit.coordinates(
                      coordinates: points,
                      padding: const EdgeInsets.all(28),
                    )
                  : null,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onTap: (_, point) => onTap?.call(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.geosustain.mobile',
              ),
              if (points.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(points: points, color: green, strokeWidth: 3),
                  ],
                ),
              if (closed && points.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: points,
                      color: green.withValues(alpha: .18),
                      borderColor: green,
                      borderStrokeWidth: 3,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (final entry in points.asMap().entries)
                    Marker(
                      point: entry.value,
                      width: 30,
                      height: 30,
                      child: GestureDetector(
                        onTap: onVertex == null
                            ? null
                            : () => onVertex!(entry.key),
                        child: CircleAvatar(
                          backgroundColor: selectedVertex == entry.key
                              ? Colors.orange.shade800
                              : green,
                          child: Text(
                            '${entry.key + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (current != null)
                    Marker(
                      point: current!,
                      width: 34,
                      height: 34,
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.blue,
                        size: 30,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      const Align(
        alignment: Alignment.centerRight,
        child: Text(
          '© OpenStreetMap contributors',
          style: TextStyle(fontSize: 10, color: Colors.black54),
        ),
      ),
    ],
  );
}
