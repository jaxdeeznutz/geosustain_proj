import 'dart:typed_data';
import '../seasonal_context.dart';
import '../spatial_pdf.dart';
import '../local_explanation_pdf.dart';
import '../controlled_references.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;

/// Exports only the requested case or aggregate, never a hidden all-record query.
Future<Uint8List> buildOperatorReport(
  Map<String, dynamic> data, {
  bool planning = false,
  String scope = '',
  DateTime? generated,
}) async {
  String clean(dynamic v) => '${v ?? 'Unavailable'}';
  Map<String, dynamic> object(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : {};
  List<Map<String, dynamic>> rows(dynamic v) =>
      v is List ? v.map(object).toList() : [];
  final regular = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
  final symbols = await rootBundle.load(
    'assets/fonts/NotoSansSymbols2-Regular.ttf',
  );
  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(
      base: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
      fontFallback: [pw.Font.ttf(symbols)],
    ),
  );
  final c = object(data['case']), a = object(data['analysis']);
  pw.Widget text(String label, dynamic value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 7),
    child: pw.Text(
      '$label: ${clean(value)}',
      style: const pw.TextStyle(fontSize: 10),
    ),
  );
  pw.Widget heading(String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 8),
    child: pw.Text(
      value,
      style: pw.TextStyle(
        fontSize: 14,
        fontWeight: pw.FontWeight.bold,
        color: PdfColor.fromHex('#166346'),
      ),
    ),
  );
  pdf.addPage(
    pw.MultiPage(
      maxPages: 50,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      header: (_) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Text(
          'GeoSustain | ${planning ? 'Planning summary' : 'Review case report'}',
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('#166346'),
          ),
        ),
      ),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Project records - not a soil test or citywide inventory',
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.Text(
            '${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
      build: (_) => [
        text(
          'Generated UTC',
          (generated ?? DateTime.now()).toUtc().toIso8601String(),
        ),
        if (planning) ...[
          text(
            'Applied place filter',
            scope.isEmpty ? 'All submitted project places' : scope,
          ),
          text('Record scope', data['scope']),
          heading('Operational totals'),
          for (final field in {
            'cases': 'Submitted cases',
            'pending_count': 'Pending review',
            'information_count': 'Information requested',
            'verified_count': 'Accepted',
            'rejected_count': 'Rejected',
            'reviewed_week': 'Reviewed in the last 7 days',
            'preliminary_count': 'Preliminary cases',
            'followups_due': 'Due follow-up tasks',
            'distinct_farms': 'Distinct farms',
            'oldest_pending': 'Oldest pending submission',
            'parcel_area_sum_ha': 'Latest parcel area sum (ha; may overlap)',
            'farms_with_area': 'Farms with recorded area',
            'farms_without_area': 'Farms without recorded area',
          }.entries)
            text(field.value, data[field.key]),
          heading('Interpretation'),
          pw.Text(
            'Counts describe submitted project cases and review activity. Repeated analyses are not additional farms. Parcel area sums may overlap and are not the union of farm boundaries. Recommendation frequencies do not measure actual planting, crop production or yield.',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ] else ...[
          text('Case', c['id']),
          text('Case version', c['version']),
          text('Review status', c['status']),
          text('Current analysis', c['current_session_id']),
          text('Submitted', c['submitted_at']),
          text('Updated', c['updated_at']),
          heading('Recorded evidence reference'),
          text('Farm', a['farm_name'] ?? a['farm_name_snapshot']),
          text('Place', a['place_name']),
          text('Analyzed', a['analyzed_at']),
          text('Analysis mode', a['analysis_mode']),
          text('Recorded boundary version', a['boundary_version']),
          text('Current farm version', data['current_farm_version']),
          text(
            'Geometry matches current farm',
            data['geometry_matches_current'],
          ),
          text('Recorded geometry SHA-256', data['recorded_geometry_hash']),
          pw.Text(
            'This report records review decisions and evidence references. Open the linked analysis in GeoSustain for the full saved measurements, data provenance and limitations. An accepted review does not certify missing measurements. NPK and soil pH methods are outside this workflow change.',
            style: const pw.TextStyle(fontSize: 10),
          ),
          heading('Saved seasonal context'),
          for (final line in seasonalAssessmentLines(a))
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(line, style: const pw.TextStyle(fontSize: 10)),
            ),
          ...buildSpatialPdfWidgets(a),
          ...buildLocalExplanationPdfWidgets(a),
          if (controlledReferenceLines(a).isNotEmpty) ...[
            pw.NewPage(),
            pw.Text(
              'Saved reference versions',
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            for (final line in controlledReferenceLines(a))
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 6),
                child: pw.Text(line, style: const pw.TextStyle(fontSize: 9)),
              ),
          ],
          heading('Linked analysis revisions'),
          for (final r in rows(data['revisions']))
            text(
              'Revision ${r['revision']}',
              'Analysis ${r['session_id']} | ${r['analyzed_at']} | boundary version ${r['boundary_version']}',
            ),
          heading('Decision and advisory timeline'),
          for (final e in rows(data['events']))
            pw.Inseparable(
              child: pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    text(
                      '${clean(e['kind']).replaceAll('_', ' ')} | ${e['created_at']}',
                      e['actor_name'] ?? 'Recorded system event',
                    ),
                    text('Analysis', e['session_id']),
                    if ('${e['reason'] ?? ''}'.trim().isNotEmpty)
                      text('Reason', e['reason']),
                    if (e['notes'] != null) text('Explanation', e['notes']),
                    if (object(e['checklist']).isNotEmpty)
                      text(
                        'Evidence checklist',
                        object(
                          e['checklist'],
                        ).entries.map((v) => '${v.key}=${v.value}').join('; '),
                      ),
                  ],
                ),
              ),
            ),
          heading('Follow-up tasks'),
          if (rows(data['followups']).isEmpty) text('Tasks', 'None recorded'),
          for (final f in rows(data['followups']))
            text(
              clean(f['title']),
              'Due ${f['due_on']} | ${f['assigned_name']} | ${f['completed_at'] == null ? 'Open' : 'Completed ${f['completed_at']}'}',
            ),
        ],
      ],
    ),
  );
  return pdf.save();
}
