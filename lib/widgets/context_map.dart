part of '../main.dart';

const _contextStreetTiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _contextSatelliteTiles =
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

/// Navigation imagery only. Changing basemaps never changes saved analysis layers.
class ContextMap extends StatefulWidget {
  final MapController? mapController;
  final MapOptions options;
  final List<Widget> children;
  final bool? satellite;
  final ValueChanged<bool>? onSatelliteChanged;
  final bool basemapVisible;
  const ContextMap({
    super.key,
    this.mapController,
    required this.options,
    this.children = const [],
    this.satellite,
    this.onSatelliteChanged,
    this.basemapVisible = true,
  });
  @override
  State<ContextMap> createState() => _ContextMapState();
}

class _ContextMapState extends State<ContextMap> {
  bool _satellite = !lowBandwidthMode.value;
  @override
  Widget build(BuildContext context) {
    final satellite = widget.satellite ?? _satellite;
    return FlutterMap(
      mapController: widget.mapController,
      options: widget.options,
      children: [
        if (widget.basemapVisible)
          TileLayer(
            key: ValueKey(
              satellite ? 'satellite-basemap-tiles' : 'street-basemap-tiles',
            ),
            urlTemplate: satellite
                ? _contextSatelliteTiles
                : _contextStreetTiles,
            userAgentPackageName: 'com.geosustain.mobile',
            maxNativeZoom: 19,
          ),
        ...widget.children,
        if (widget.basemapVisible)
          RichAttributionWidget(
            attributions: [
              TextSourceAttribution(
                satellite ? 'Esri World Imagery' : 'OpenStreetMap contributors',
              ),
            ],
          ),
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: WebBasemapSwitch(
              satellite: satellite,
              onChanged: (value) {
                setState(() => _satellite = value);
                widget.onSatelliteChanged?.call(value);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class WebBasemapSwitch extends StatelessWidget {
  final bool satellite;
  final ValueChanged<bool> onChanged;
  const WebBasemapSwitch({
    super.key,
    required this.satellite,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: MediaQuery.textScalerOf(context).scale(12) > 18
            ? PopupMenuButton<bool>(
                tooltip: 'Choose Map or Satellite',
                initialValue: satellite,
                onSelected: onChanged,
                icon: const Icon(Icons.layers_outlined),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: false, child: Text('Map')),
                  PopupMenuItem(value: true, child: Text('Satellite')),
                ],
              )
            : SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Map'),
                    icon: Icon(Icons.map_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Satellite'),
                    icon: Icon(Icons.satellite_alt_outlined, size: 16),
                  ),
                ],
                selected: {satellite},
                onSelectionChanged: (values) => onChanged(values.first),
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 34),
                  textStyle: const TextStyle(fontSize: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
      ),
    );
  }
}
