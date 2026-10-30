part of '../main.dart';

Color spatialColor(String value) =>
    Color(int.parse(value.replaceFirst('#', 'ff'), radix: 16));

List<Polygon> spatialCellPolygons(Map<String, dynamic> record, String layerId) {
  final layer = spatialLayers(
    record,
  ).where((l) => l['id'] == layerId).firstOrNull;
  if (layer == null) return [];
  return [
    for (final cell in spatialRows(layer['cells']))
      for (final part in analysisListValue(cell['parts']))
        if (FarmGeometry.fromPayload(part).length >= 3)
          Polygon(
            points: FarmGeometry.fromPayload(part),
            color: spatialColor(
              spatialCellColor(layer, cell['value']),
            ).withValues(alpha: .75),
            borderStrokeWidth: 0,
          ),
  ];
}

class SpatialRasterCard extends StatefulWidget {
  final Map<String, dynamic> record;
  const SpatialRasterCard({super.key, required this.record});
  @override
  State<SpatialRasterCard> createState() => _SpatialRasterCardState();
}

class _SpatialRasterCardState extends State<SpatialRasterCard> {
  String selected = 'ndvi';
  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final layers = spatialLayers(record);
    if (layers.isEmpty) {
      return Column(
        children: [
          GeoResultCard(child: Text(spatialAssessmentLines(record).join('\n'))),
          AnalysisBoundaryPreview(record: record),
        ],
      );
    }
    final layer =
        layers.where((l) => l['id'] == selected).firstOrNull ?? layers.first;
    final boundary = FarmGeometry.fromPayload(record['selected_polygon']);
    final stats = spatialObject(layer['statistics']);
    final legend = spatialObject(layer['legend']);
    final cells = spatialCellPolygons(record, '${layer['id']}');
    final scope =
        '${record['session_id'] ?? 'unsaved'}-${spatialObject(record['spatial_assessment'])['captured_at']}';
    return GeoResultCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Polygon raster layers',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('spatial-layer-$scope-${layer['id']}'),
            initialValue: '${layer['id']}',
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Recorded raster layer',
            ),
            items: [
              for (final item in layers)
                DropdownMenuItem(
                  value: '${item['id']}',
                  child: Text('${item['label']} (${item['unit']})'),
                ),
            ],
            onChanged: (value) => setState(() => selected = value!),
          ),
          const SizedBox(height: 10),
          if (boundary.length >= 3)
            SizedBox(
              height: 310,
              child: FlutterMap(
                key: ValueKey('spatial-map-$scope'),
                options: MapOptions(
                  initialCameraFit: CameraFit.coordinates(
                    coordinates: boundary,
                    padding: const EdgeInsets.all(25),
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
                        points: boundary,
                        color: const Color(0xffbdbdbd).withValues(alpha: .65),
                        borderStrokeWidth: 0,
                      ),
                      ...cells,
                    ],
                  ),
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: boundary,
                        color: Colors.transparent,
                        borderColor: darkGreen,
                        borderStrokeWidth: 3,
                      ),
                    ],
                  ),
                  const RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution('OpenStreetMap contributors'),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Text(
            stats.isEmpty
                ? '${layer['reason']}'
                : 'Mean ${spatialValue(stats['mean'])} ${layer['unit']} · valid area ${((analysisNumber(stats['valid_area_fraction']) ?? 0) * 100).toStringAsFixed(1)}%',
          ),
          Text('${legend['interpretation']}'),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final c in spatialRows(legend['classes']))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.square,
                      size: 13,
                      color: spatialColor('${c['color']}'),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '${c['label']}: ${spatialValue(c['minimum'])}–${spatialValue(c['maximum'])}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              const Text(
                'Gray = no data / not evaluated',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
          ExpansionTile(
            key: PageStorageKey('spatial-evidence-$scope-${layer['id']}'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Statistics, sources and limitations'),
            children: [
              for (final line in [
                ...spatialLayerLines(layer),
                '${spatialObject(record['spatial_assessment'])['statistics_method']}',
                '${spatialObject(record['spatial_assessment'])['coverage_method']}',
                ...analysisListValue(
                  spatialObject(record['spatial_assessment'])['limitations'],
                ).map((v) => '$v'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(line),
                  ),
                ),
            ],
          ),
          const Text(
            'Saved raster cells are clipped to the recorded farm. Model samples remain separate. The current basemap is navigation context.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
