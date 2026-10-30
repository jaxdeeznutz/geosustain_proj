import 'dart:math' as math;

Map<String, dynamic> spatialObject(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Map<String, dynamic>> spatialRows(dynamic value) =>
    value is List ? value.map(spatialObject).toList() : [];
List<Map<String, dynamic>> spatialLayers(Map<String, dynamic> record) =>
    spatialRows(spatialObject(record['spatial_assessment'])['layers']);
String spatialValue(dynamic value) =>
    value is num && value.isFinite ? value.toStringAsFixed(3) : 'Unavailable';

(double, double)? spatialXY(dynamic raw) {
  final p = spatialObject(raw);
  final lat = p['lat'], lon = p['lng'];
  if (lat is! num ||
      lon is! num ||
      !lat.isFinite ||
      !lon.isFinite ||
      lat.abs() >= 85) {
    return null;
  }
  return (
    6378137 * lon * math.pi / 180,
    6378137 * math.log(math.tan(math.pi / 4 + lat * math.pi / 360)),
  );
}

List<String> spatialLayerLines(Map<String, dynamic> layer) {
  final grid = spatialObject(layer['grid']);
  final stats = spatialObject(layer['statistics']);
  final period = spatialObject(grid['source_period']);
  final native = spatialObject(grid['native_projection']);
  final coverage = stats['valid_area_fraction'];
  return [
    '${layer['label']} (${layer['unit']}): ${layer['status']}',
    'Quality: ${layer['quality'] ?? 'Not recorded'}',
    if (stats.isEmpty)
      '${layer['reason'] ?? 'Raster observations unavailable.'}'
    else ...[
      'Minimum ${spatialValue(stats['minimum'])}; maximum ${spatialValue(stats['maximum'])}; area-weighted mean ${spatialValue(stats['mean'])}; median ${spatialValue(stats['median'])}; population standard deviation ${spatialValue(stats['standard_deviation'])} ${layer['unit']}.',
      'Valid analysis-grid cells: ${stats['valid_pixel_count']}/${stats['intersecting_pixel_count']}; valid projected-area coverage: ${coverage is num ? (coverage * 100).toStringAsFixed(1) : 'Unavailable'}%. Missing values are not filled.',
      'Native nominal resolution: ${spatialValue(native['nominal_scale_m'] ?? layer['native_resolution_m'])} m; analysis grid: ${spatialValue(grid['effective_resolution_projected_m'])} projected m; CRS: ${grid['crs']}. Counts are not independent field samples.',
    ],
    'Source: ${layer['source']}; period: ${period.isEmpty ? 'Not retrieved' : '${period['period']}; ${period['start']} to ${period['end_exclusive']} (end exclusive)'}',
    if (layer['controlled_source_reference'] is Map)
      'Reviewed source reference: ${spatialObject(spatialObject(layer['controlled_source_reference'])['document'])['reference']}; revision ${spatialObject(layer['controlled_source_reference'])['revision']}; ${spatialObject(spatialObject(layer['controlled_source_reference'])['document'])['evidence_url']}. This metadata does not replace the provider observations.',
    if (period['observation_date'] != null)
      'Observed scene: ${period['observation_date']}; scene ID: ${period['scene_id']}',
    if (grid['retrieved_at'] != null)
      'Raster retrieved: ${grid['retrieved_at']}; resampling: ${grid['resampling']}',
    if (period['method'] != null) 'Processing: ${period['method']}',
    if (grid['mask_method'] != null) '${grid['mask_method']}',
    '${spatialObject(layer['legend'])['interpretation'] ?? 'Colors describe observations, not crop suitability.'}',
    if (layer['limitation'] != null) '${layer['limitation']}',
  ];
}

List<String> spatialAssessmentLines(Map<String, dynamic> record) {
  final saved = spatialObject(record['spatial_assessment']);
  if (saved.isEmpty) {
    return [
      'Polygon raster context was not recorded for this older analysis. Model samples are not full-polygon statistics.',
    ];
  }
  return [
    'Saved polygon raster context: ${saved['version']}; ${saved['captured_at']}; ${saved['status']}',
    if (saved['reason'] != null) '${saved['reason']}',
    if (saved['statistics_method'] != null) '${saved['statistics_method']}',
    if (saved['coverage_method'] != null) '${saved['coverage_method']}',
    for (final layer in spatialLayers(record)) ...spatialLayerLines(layer),
    for (final limitation
        in saved['limitations'] is List ? saved['limitations'] as List : [])
      '$limitation',
  ];
}

String spatialCellColor(Map<String, dynamic> layer, dynamic raw) {
  final legend = spatialObject(layer['legend']);
  if (raw is! num || !raw.isFinite) {
    return '${legend['nodata_color'] ?? '#bdbdbd'}';
  }
  final classes = spatialRows(legend['classes']);
  for (var i = 0; i < classes.length; i++) {
    final c = classes[i];
    if (c['minimum'] is num &&
        c['maximum'] is num &&
        raw >= c['minimum'] &&
        (raw < c['maximum'] || i == classes.length - 1)) {
      return '${c['color']}';
    }
  }
  return '${legend['nodata_color'] ?? '#bdbdbd'}';
}

/// Export the persisted clipped geometries, without an expiring tile URL.
String spatialLayerSvg(
  Map<String, dynamic> record,
  Map<String, dynamic> layer,
) {
  final boundary = spatialRows(
    record['selected_polygon'],
  ).map(spatialXY).whereType<(double, double)>().toList();
  if (boundary.length < 3) {
    return '<svg xmlns="http://www.w3.org/2000/svg" width="480" height="180"/>';
  }
  final xs = boundary.map((p) => p.$1), ys = boundary.map((p) => p.$2);
  final lowX = xs.reduce(math.min),
      highX = xs.reduce(math.max),
      lowY = ys.reduce(math.min),
      highY = ys.reduce(math.max);
  final scale = math.min(
    460 / math.max(highX - lowX, .001),
    160 / math.max(highY - lowY, .001),
  );
  final dx = (480 - (highX - lowX) * scale) / 2,
      dy = (180 - (highY - lowY) * scale) / 2;
  String points(dynamic ring) => spatialRows(ring)
      .map(spatialXY)
      .whereType<(double, double)>()
      .map(
        (p) =>
            '${((p.$1 - lowX) * scale + dx).toStringAsFixed(6)},${((highY - p.$2) * scale + dy).toStringAsFixed(6)}',
      )
      .join(' ');
  final buffer = StringBuffer(
    '<svg xmlns="http://www.w3.org/2000/svg" width="480" height="180" viewBox="0 0 480 180">',
  );
  buffer.write(
    '<polygon points="${points(record['selected_polygon'])}" fill="#bdbdbd"/>',
  );
  for (final cell in spatialRows(layer['cells'])) {
    for (final part in cell['parts'] is List ? cell['parts'] as List : []) {
      buffer.write(
        '<polygon points="${points(part)}" fill="${spatialCellColor(layer, cell['value'])}"/>',
      );
    }
  }
  buffer.write(
    '<polygon points="${points(record['selected_polygon'])}" fill="none" stroke="#173d30" stroke-width="1.5"/></svg>',
  );
  return buffer.toString();
}
