import 'package:pdf/widgets.dart' as pw;
import 'local_explanation.dart';
import 'recommendation_summary.dart';

List<pw.Widget> buildLocalExplanationPdfWidgets(Map<String, dynamic> record) {
  final body = verifiedLocalExplanation(record);
  if (body.isEmpty) {
    return [
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10),
        child: pw.Text(
          localExplanationLines(record).first,
          style: const pw.TextStyle(fontSize: 9),
        ),
      ),
    ];
  }
  pw.Widget text(String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
  );
  final bindings = localRows(body['crop_classes']);
  return [
    pw.NewPage(),
    pw.Text(
      'Explainable AI - saved local model contributions',
      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 10),
    text('Method: ${body['method_label']} / ${body['method_version']}'),
    text('${body['baseline_definition']}. ${body['aggregation']}'),
    text('Model SHA-256: ${body['model_version']}'),
    text('Analysis context: ${body['prediction_context_id']}'),
    text('Input snapshot hash: ${body['input_snapshot_hash']}'),
    text('Attribution checksum: ${body['snapshot_hash']}'),
    text(
      'Saved feature input summaries below describe the original samples. No model was run on these means.',
    ),
    pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 8),
      headers: ['Feature', 'Mean', 'Minimum', 'Maximum', 'Unit'],
      data: [
        for (var i = 0; i < localRows(body['feature_definitions']).length; i++)
          [
            localRows(body['feature_definitions'])[i]['label'],
            for (final key in ['mean', 'minimum', 'maximum'])
              (localRows(body['feature_inputs'])[i][key] as num)
                  .toStringAsPrecision(7),
            localRows(body['feature_definitions'])[i]['unit'],
          ],
      ],
    ),
    pw.SizedBox(height: 10),
    for (final limit in body['limitations'] as List) text('$limit'),
    for (final binding in bindings) ...[
      pw.NewPage(),
      pw.Text(
        'Explainable AI - ${binding['crop']}',
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 10),
      for (final line in recommendationSummaryLines(
        record,
        '${binding['crop']}',
      ))
        text(line),
      pw.SizedBox(height: 10),
      text(
        'Saved model class: ${binding['class_label']}; class index ${binding['class_index']}; ${body['sample_count']} recorded sample(s).',
      ),
      text(
        'Baseline: ${(localCropView(body, '${binding['crop']}')['base_pct'] as num).toStringAsFixed(6)}%. '
        'Net feature contribution: ${localSigned(localCropView(body, '${binding['crop']}')['net_pp'] as num, decimals: 6)} pp. '
        'Model score: ${(localCropView(body, '${binding['crop']}')['score_pct'] as num).toStringAsFixed(6)}%.',
      ),
      text(
        'Positive contributions raise this class score relative to the model baseline; negative contributions lower it. These are percentage points, not percent changes or causal effects.',
      ),
      pw.TableHelper.fromTextArray(
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headers: [
          'Feature',
          'Signed contribution (pp)',
          'Saved mean input',
          'Unit',
        ],
        data: [
          for (final feature in localRows(
            localCropView(body, '${binding['crop']}')['features'],
          ))
            [
              feature['label'],
              localSigned(feature['contribution_pp'] as num, decimals: 6),
              (feature['mean'] as num).toStringAsPrecision(7),
              feature['unit'],
            ],
        ],
      ),
      pw.SizedBox(height: 12),
      text(
        'All signed contributions plus the baseline reconstruct the class score within 0.0000001 percentage points. Printed values are rounded. The crop ranking has not been adjusted.',
      ),
      if (bindings.length > 1)
        ..._localComparisonPdf(
          body,
          '${binding['crop']}',
          '${bindings.first['crop'] == binding['crop'] ? bindings[1]['crop'] : bindings.first['crop']}',
          text,
        ),
      text(
        'Nutrient inputs remain model estimates/proxies with unresolved unit compatibility. These explanations are not soil measurements, fertilizer advice or harvest probabilities.',
      ),
      text(
        'Method/version: ${body['method_version']}; attribution checksum: ${body['snapshot_hash']}',
      ),
    ],
  ];
}

List<pw.Widget> _localComparisonPdf(
  Map<String, dynamic> body,
  String crop,
  String other,
  pw.Widget Function(String) text,
) {
  final comparison = localCropComparison(body, crop, other);
  final features = localRows(comparison['features'])
    ..sort(
      (a, b) => (b['contribution_pp'] as num).abs().compareTo(
        (a['contribution_pp'] as num).abs(),
      ),
    );
  return [
    text(
      '$crop minus $other: ${localSigned(comparison['score_gap_pp'] as num, decimals: 6)} pp in model score; '
      'baseline difference ${localSigned(comparison['baseline_gap_pp'] as num, decimals: 6)} pp.',
    ),
    text(
      'Largest allocations toward that score difference: ${features.take(3).map((f) => '${f['label']} ${localSigned(f['contribution_pp'] as num, decimals: 6)} pp').join('; ')}. Comparison uses the same saved model and samples.',
    ),
  ];
}
