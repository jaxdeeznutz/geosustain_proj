import 'package:pdf/pdf.dart' show PdfColor;
import 'package:pdf/widgets.dart' as pw;
import 'spatial_context.dart';

List<pw.Widget> buildSpatialPdfWidgets(Map<String, dynamic> record) {
  final saved = spatialObject(record['spatial_assessment']);
  final layers = spatialLayers(record);
  return [
    pw.SizedBox(height: 12),
    pw.Text(
      'Saved polygon raster statistics and maps',
      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
    ),
    if (saved.isEmpty)
      pw.Text(
        spatialAssessmentLines(record).single,
        style: const pw.TextStyle(fontSize: 9),
      )
    else ...[
      pw.Text(
        'Snapshot: ${saved['version']} / ${saved['captured_at']}; geometry SHA-256: ${saved['geometry_hash']}',
        style: const pw.TextStyle(fontSize: 9),
      ),
      if (saved['reason'] != null)
        pw.Text('${saved['reason']}', style: const pw.TextStyle(fontSize: 9)),
      for (final key in ['statistics_method', 'coverage_method'])
        if (saved[key] != null)
          pw.Text('${saved[key]}', style: const pw.TextStyle(fontSize: 9)),
      for (final layer in layers) ...[
        pw.NewPage(),
        pw.Container(
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '${layer['label']} (${layer['unit']})',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (spatialRows(layer['cells']).isNotEmpty)
                pw.SizedBox(
                  height: 180,
                  child: pw.SvgImage(svg: spatialLayerSvg(record, layer)),
                ),
              for (final line in spatialLayerLines(layer))
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text(line, style: const pw.TextStyle(fontSize: 9)),
                ),
              pw.Text(
                'Map: north up; dark outline = saved parcel; gray = missing or unevaluated. Blue classes describe lower to higher values, not crop suitability.',
                style: const pw.TextStyle(fontSize: 9),
              ),
              for (final c in spatialRows(
                spatialObject(layer['legend'])['classes'],
              ))
                pw.Row(
                  children: [
                    pw.Container(
                      width: 9,
                      height: 9,
                      color: PdfColor.fromHex('${c['color']}'),
                    ),
                    pw.SizedBox(width: 5),
                    pw.Expanded(
                      child: pw.Text(
                        '${c['label']}: ${spatialValue(c['minimum'])}-${spatialValue(c['maximum'])} ${layer['unit']}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
      for (final line
          in saved['limitations'] is List ? saved['limitations'] as List : [])
        pw.Text('$line', style: const pw.TextStyle(fontSize: 9)),
    ],
  ];
}
