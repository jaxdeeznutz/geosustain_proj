part of '../main.dart';

String rainfallLayerForRecord(Map<String, dynamic> record) => 'rainfall_annual';

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
  final bool simple;
  final bool lockMap;
  const SpatialRasterCard({
    super.key,
    required this.record,
    this.simple = false,
    this.lockMap = false,
  });
  @override
  State<SpatialRasterCard> createState() => _SpatialRasterCardState();
}

class _SpatialRasterCardState extends State<SpatialRasterCard> {
  String selected = 'ndvi';
  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final layers = spatialLayers(
      record,
    ).where((layer) => layer['id'] != 'rainfall_30d').toList();
    if (layers.isEmpty) {
      return Column(
        children: [
          GeoResultCard(
            child: Text(
              widget.simple
                  ? 'Map readings are unavailable. You can still check the saved boundary.'
                  : spatialAssessmentLines(record).join('\n'),
            ),
          ),
          AnalysisBoundaryPreview(record: record, lockMap: widget.lockMap),
          if (widget.simple &&
              FarmGeometry.fromPayload(record['selected_polygon']).length >= 3)
            const FarmerLegend(
              title: 'Boundary guide',
              items: [
                FarmerLegendItem(
                  Icons.crop_free,
                  green,
                  'Green outline: Saved farm boundary',
                ),
              ],
            ),
        ],
      );
    }
    final layer =
        layers.where((l) => l['id'] == selected).firstOrNull ?? layers.first;
    final showOverlay = selected != 'none';
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
          Text(
            widget.simple ? 'Land readings' : 'Polygon raster layers',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('spatial-layer-$scope-$selected'),
            initialValue: showOverlay ? '${layer['id']}' : 'none',
            isExpanded: true,
            decoration: InputDecoration(
              labelText: widget.simple
                  ? 'Show on map'
                  : 'Recorded raster layer',
            ),
            items: [
              const DropdownMenuItem(
                value: 'none',
                child: Text('Boundary only (no heatmap)'),
              ),
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
              child: ContextMap(
                key: ValueKey(
                  'spatial-map-$scope-${widget.lockMap}-${jsonEncode(record['selected_polygon'])}',
                ),
                options: MapOptions(
                  interactionOptions: InteractionOptions(
                    flags: widget.lockMap
                        ? InteractiveFlag.none
                        : InteractiveFlag.all,
                  ),
                  initialCameraFit: CameraFit.coordinates(
                    coordinates: boundary,
                    padding: const EdgeInsets.all(25),
                  ),
                ),
                children: [
                  PolygonLayer(
                    polygons: [
                      if (showOverlay)
                        Polygon(
                          points: boundary,
                          color: const Color(0xffbdbdbd).withValues(alpha: .65),
                          borderStrokeWidth: 0,
                        ),
                      if (showOverlay) ...cells,
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
                ],
              ),
            ),
          if (showOverlay) ...[
            const SizedBox(height: 10),
            Text(
              widget.simple
                  ? (stats.isEmpty
                        ? 'No usable readings were saved.'
                        : 'Average: ${spatialValue(stats['mean'])} ${layer['unit']} · ${analysisNumber(stats['valid_area_fraction']) == null ? 'Coverage unavailable' : 'Data covers ${((analysisNumber(stats['valid_area_fraction'])!) * 100).toStringAsFixed(1)}% of the farm'}')
                  : stats.isEmpty
                  ? '${layer['reason']}'
                  : 'Mean ${spatialValue(stats['mean'])} ${layer['unit']} · valid area ${((analysisNumber(stats['valid_area_fraction']) ?? 0) * 100).toStringAsFixed(1)}%',
            ),
            if (widget.simple) ...[
              const Text(
                'Colors show the amount of the selected reading, not crop suitability.',
                style: TextStyle(fontSize: 12),
              ),
              if (layer['id'] == 'ndvi')
                const Text(
                  'NDVI shows vegetation greenness.',
                  style: TextStyle(fontSize: 12),
                ),
              const SizedBox(height: 8),
              const Text(
                'Map color guide',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ] else
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
                if (widget.simple)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.help_outline,
                        size: 16,
                        color: spatialColor(spatialCellColor(layer, null)),
                      ),
                      const SizedBox(width: 4),
                      const Flexible(
                        child: Text(
                          'Gray: No usable reading',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  )
                else
                  const Text(
                    'Gray = no data / not evaluated',
                    style: TextStyle(fontSize: 11),
                  ),
                if (widget.simple)
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.crop_free, size: 16, color: darkGreen),
                      SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Green outline: Analyzed boundary',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            ExpansionTile(
              key: PageStorageKey('spatial-evidence-$scope-${layer['id']}'),
              tilePadding: EdgeInsets.zero,
              title: Text(
                widget.simple
                    ? 'Map details and sources'
                    : 'Statistics, sources and limitations',
              ),
              children: [
                if (widget.simple) Text('${legend['interpretation']}'),
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
          ],
          Text(
            widget.simple
                ? 'The background map is for navigation.'
                : 'Saved raster cells are clipped to the recorded farm. Model samples remain separate. The current basemap is navigation context.',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
