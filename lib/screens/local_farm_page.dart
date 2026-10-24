part of '../main.dart';

class LocalFarmPage extends StatefulWidget {
  final AnalysisState state;
  final Map<String, dynamic> farm;
  const LocalFarmPage({super.key, required this.state, required this.farm});
  @override
  State<LocalFarmPage> createState() => _LocalFarmPageState();
}

class _LocalFarmPageState extends State<LocalFarmPage> {
  bool busy = false;
  String? error;
  Future<void> sync() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.state.syncPendingFarms();
      if (mounted) Navigator.pop(context);
    } catch (failure) {
      if (mounted) setState(() => error = friendlyErrorMessage(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from this device?'),
        content: const Text(
          'Discard the pending local boundary? This does not delete a farm already saved on the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await OfflineFarmStore.remove('${widget.farm['request_id']}');
      final local = await OfflineFarmStore.read();
      widget.state.replaceFarms([
        ...OfflineFarmStore.rows(local['pending']),
        ...OfflineFarmStore.rows(local['farms']),
      ]);
      if (mounted) Navigator.pop(context);
    } catch (failure) {
      if (mounted) setState(() => error = friendlyErrorMessage(failure));
    }
  }

  @override
  Widget build(BuildContext context) {
    final farm = widget.farm,
        points = FarmGeometry.fromPayload(widget.farm['selected_polygon']);
    return Scaffold(
      appBar: GeoSustainHeader(
        title: 'Saved on device',
        embedded: false,
        state: widget.state,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${farm['farm_name']}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            '${farm['sync_state']} · ${points.length} vertices · ${(FarmGeometry.areaSquareMetres(points) / 10000).toStringAsFixed(3)} ha estimated',
          ),
          const SizedBox(height: 16),
          Semantics(
            label: 'Saved farm outline; available without map tiles',
            child: SizedBox(
              height: 220,
              child: CustomPaint(
                painter: _LocalBoundaryPainter(
                  points,
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
          const Text(
            'This boundary is saved on this device for your account. Reconnect and sync before analyzing online. GPS readings are estimates, not a land survey.',
          ),
          if (farm['sync_error'] != null) Text('${farm['sync_error']}'),
          if (error != null) Text(error!),
          FilledButton.icon(
            onPressed: busy ? null : sync,
            icon: const Icon(Icons.sync),
            label: Text(busy ? 'Syncing…' : 'Sync now'),
          ),
          TextButton(
            onPressed: busy ? null : remove,
            child: const Text('Remove pending farm'),
          ),
          if (farm['capture'] is List)
            ExpansionTile(
              title: const Text('Recorded GPS quality'),
              children: [
                for (final fix in farm['capture'] as List)
                  ListTile(
                    title: Text(
                      'Accuracy: ${fix['accuracy_m'] ?? 'Unknown'} m',
                    ),
                    subtitle: Text(
                      'Captured: ${fix['timestamp'] ?? 'Not recorded in this older draft'}',
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _LocalBoundaryPainter extends CustomPainter {
  final List<LatLng> points;
  final Color color;
  _LocalBoundaryPainter(this.points, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final minX = points.map((p) => p.longitude).reduce(math.min),
        maxX = points.map((p) => p.longitude).reduce(math.max);
    final minY = points.map((p) => p.latitude).reduce(math.min),
        maxY = points.map((p) => p.latitude).reduce(math.max);
    final scale = math.min(
      (size.width - 32) / math.max(maxX - minX, .000001),
      (size.height - 32) / math.max(maxY - minY, .000001),
    );
    final path = Path();
    for (final entry in points.indexed) {
      final x = 16 + (entry.$2.longitude - minX) * scale,
          y = size.height - 16 - (entry.$2.latitude - minY) * scale;
      if (entry.$1 == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: .2));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_LocalBoundaryPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}
