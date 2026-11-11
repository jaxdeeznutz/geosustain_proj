import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'recommendation_summary.dart';
import 'seasonal_context.dart';
import 'spatial_context.dart';

dynamic _decoded(dynamic value) {
  if (value is String) {
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }
  return value;
}

Map<String, dynamic> _object(dynamic v) =>
    _decoded(v) is Map ? Map<String, dynamic>.from(_decoded(v) as Map) : {};
List<Map<String, dynamic>> _rows(dynamic v) => _decoded(v) is List
    ? (_decoded(v) as List)
          .whereType<Map>()
          .map((v) => Map<String, dynamic>.from(v))
          .toList()
    : [];
String _text(dynamic value, [int limit = 220]) {
  final s = '${value ?? 'Not recorded'}'
      .replaceAll(
        RegExp(r'[\u{1F000}-\u{1FAFF}\uFE0F\u200D]', unicode: true),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return s.length <= limit ? s : '${s.substring(0, limit - 3)}...';
}

String _number(dynamic v, [int digits = 1]) {
  final n = v is num ? v.toDouble() : double.tryParse('$v');
  return n == null || !n.isFinite ? 'Unavailable' : n.toStringAsFixed(digits);
}

/// The default export is a two-page decision summary. Detailed saved evidence
/// remains accessible in the application, rather than repeated for all crops.
Future<Uint8List> buildCompactAnalysisPdf(
  Map<String, dynamic> record, {
  Map<String, dynamic>? reviewCase,
  List<Map<String, dynamic>> events = const [],
}) async {
  final regular = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(
      base: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
    ),
  );
  final green = PdfColor.fromHex('#086B42');
  final pale = PdfColor.fromHex('#EDF6F0');
  final crop = '${record['predicted_crop'] ?? 'No crop ranking available'}';
  final blocked =
      record['analysis_mode'] == 'preliminary_environmental' ||
      record['recommendations_blocked'] == true ||
      record['predicted_crop'] == null;
  final season = _object(record['seasonal_assessment']);
  final planting = _object(season['planting_assessment']);
  final seasonalCrop = _rows(planting['crops'])
      .where((r) => '${r['crop']}'.toLowerCase() == crop.toLowerCase())
      .firstOrNull;
  final features =
      record['model_input_features'] ??
      _object(record['local_model_explanation'])['feature_order'];
  final usesNpk =
      features is List && features.any((f) => ['N', 'P', 'K'].contains(f));
  final measures = _object(record['environmental_measurements']);
  final checks = savedReferenceFit(record, crop);
  final explanation = blocked
      ? <String, dynamic>{}
      : recommendationSummary(record, crop);
  final calendarSeason = _object(season['calendar_season']);
  final farmer =
      record['farmer_name'] ??
      record['owner_display_name'] ??
      record['owner_name'] ??
      reviewCase?['farmer_name'];
  final allRanks = <Map<String, dynamic>>[
    if (!blocked)
      {
        'crop': crop,
        'score':
            record['crop_compatibility_pct'] ?? record['compatibility_pct'],
      },
    ..._rows(record['alternative_crops']).isNotEmpty
        ? _rows(record['alternative_crops'])
        : _rows(record['top_crop_recommendations']),
  ];
  final seen = <String>{};
  final ranks = allRanks
      .where((r) => seen.add('${r['crop']}'))
      .take(7)
      .toList();
  pw.Widget heading(String s) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 7, bottom: 4),
    child: pw.Text(
      s,
      style: pw.TextStyle(
        fontSize: 13,
        fontWeight: pw.FontWeight.bold,
        color: green,
      ),
    ),
  );
  pw.Widget line(String label, dynamic value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 5),
    child: pw.Text(
      '$label: ${_text(value)}',
      style: const pw.TextStyle(fontSize: 10),
    ),
  );
  pw.Widget box(String text) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      color: pale,
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Text(
      text,
      style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 3),
    ),
  );
  pw.Widget footer(int page) => pw.Column(
    children: [
      pw.Divider(color: PdfColors.grey400),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'GeoSustain | Saved analysis summary',
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.Text('$page / 2', style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    ],
  );
  pw.Page page(int index, List<pw.Widget> children) => pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [...children, pw.Spacer(), footer(index)],
    ),
  );
  final environment = [
    ('temperature', 'Climate temperature', 'temperature_c', '°C', 1),
    (
      'rainfall',
      'Annual rain (5-year mean)',
      'annual_rainfall_mm',
      'mm/year',
      1,
    ),
    ('humidity_current', 'Current humidity', 'live_humidity', '%', 0),
    ('ndvi', 'Vegetation (NDVI)', 'ndvi', '', 2),
    ('soil_ph', 'Surface soil pH', 'soil_ph', 'pH', 2),
    ('elevation', 'Elevation', 'elevation_m', 'm', 1),
    ('slope', 'Slope', 'slope_pct', '%', 1),
  ];
  doc.addPage(
    page(1, [
      pw.Text(
        'GeoSustain',
        style: pw.TextStyle(
          fontSize: 22,
          fontWeight: pw.FontWeight.bold,
          color: green,
        ),
      ),
      pw.Text(
        'Farm analysis report',
        style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 12),
      if (record['summary_origin'] != null)
        pw.Text(
          _text(record['summary_origin'], 120),
          style: const pw.TextStyle(fontSize: 8),
        ),
      line('Farm', _text(record['farm_name'] ?? record['title'], 110)),
      line('Farmer', farmer),
      line('Location', _text(record['place_name'], 140)),
      line('Analyzed', record['analyzed_at'] ?? record['created_at']),
      line('Area', '${_number(record['area_hectares'], 3)} ha'),
      line(
        'Center',
        '${_number(record['center_lat'] ?? record['lat'], 5)}, ${_number(record['center_lon'] ?? record['lon'], 5)}',
      ),
      if (reviewCase != null)
        line(
          'Case',
          '${reviewCase['id']} | ${reviewCase['status'] ?? 'Not reviewed'}',
        ),
      heading(blocked ? 'Assessment status' : 'Crop ranking'),
      if (blocked)
        box(
          'Crop recommendations are unavailable for this saved assessment. Review land coverage and missing inputs in the application.',
        )
      else ...[
        pw.TableHelper.fromTextArray(
          headers: ['Rank', 'Crop', 'Ranking score'],
          data: [
            for (final (i, r) in ranks.indexed)
              [
                '${i + 1}',
                _text(r['crop'], 65),
                '${_number(r['score'] ?? r['compatibility_pct'] ?? r['crop_compatibility_pct'] ?? r['probability_pct'])}%',
              ],
          ],
          headerDecoration: pw.BoxDecoration(color: pale),
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 10,
          ),
          cellStyle: const pw.TextStyle(fontSize: 10),
          cellPadding: const pw.EdgeInsets.all(6),
          border: null,
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerRight,
          },
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          'Scores rank the approved crops; they are not harvest-success probabilities.',
          style: const pw.TextStyle(fontSize: 9),
        ),
        heading('Growing conditions for $crop'),
        box(_text(conciseCropFit(record, crop), 650)),
        heading('Why this crop ranked first'),
        box(
          explanation['status'] == 'available'
              ? '${_text(explanation['ranking'], 210)} ${_text(explanation['model_summary'], 190)} The model score and growing-condition checks answer different questions.'
              : 'A matching saved model explanation is unavailable. The ranking above remains the recorded model output; no reasons are inferred.',
        ),
      ],
      heading('Planting month'),
      box(
        season.isEmpty
            ? 'No seasonal assessment saved.'
            : [
                if (calendarSeason['selected_month_label'] != null)
                  'PAGASA calendar season: ${calendarSeason['selected_month_label']}.',
                if (calendarSeason['current_label'] != null)
                  'On ${calendarSeason['current_date']}: ${calendarSeason['current_label']}.',
                '${season['selected_month_name'] ?? 'Selected month'}: ${seasonalMoistureLabel(record)}.',
                if (seasonalCrop != null)
                  '$crop: ${_text(seasonalCrop['label'], 100)}.',
                'The calendar season is national; the moisture class is a historical local estimate, not a forecast. Confirm irrigation and drainage before planting.',
              ].join(' '),
      ),
    ]),
  );
  final layers = spatialLayers(record);
  final mapLayer =
      layers
          .where((l) => '${l['id'] ?? l['layer_id']}' == 'ndvi')
          .firstOrNull ??
      layers.firstOrNull;
  final sources = <String>{};
  for (final check in checks) {
    final source = _object(check['source']);
    if (source['title'] != null) sources.add(_text(source['title'], 95));
  }
  final notes =
      record['planner_notes'] ?? (events.isEmpty ? null : events.last['notes']);
  doc.addPage(
    page(2, [
      pw.Text(
        'Conditions & review',
        style: pw.TextStyle(
          fontSize: 18,
          fontWeight: pw.FontWeight.bold,
          color: green,
        ),
      ),
      heading('Recorded environmental inputs'),
      pw.TableHelper.fromTextArray(
        headers: ['Factor', 'Reading', 'Reference fit'],
        data: [
          for (final e in environment)
            [
              e.$2,
              '${_number(_object(measures[e.$1])['value'] ?? record[e.$3], e.$5)} ${e.$4}'
                  .trim(),
              switch (checks
                  .where((f) => f['factor'] == e.$1)
                  .firstOrNull?['status']) {
                'fits' => 'Fits range',
                'limited' => 'Partial fit',
                'outside' => 'Outside range',
                _ => 'Not assessed',
              },
            ],
        ],
        headerDecoration: pw.BoxDecoration(color: pale),
        headerStyle: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          fontSize: 9.5,
        ),
        cellStyle: const pw.TextStyle(fontSize: 9.5),
        cellPadding: const pw.EdgeInsets.all(3),
        border: null,
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.centerLeft,
          2: pw.Alignment.centerLeft,
        },
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        'Not assessed means no compatible reading or cited crop-specific range is saved. Current humidity and NDVI are observations, not proof of crop fit.',
        style: const pw.TextStyle(fontSize: 9),
      ),
      if (usesNpk)
        pw.Text(
          'Estimated model inputs (legacy scale): N ${_number(record['nitrogen'], 2)}; P ${_number(record['phosphorus'], 2)}; K ${_number(record['potassium'], 2)}. These are not laboratory units or fertilizer rates.',
          style: const pw.TextStyle(fontSize: 9),
        ),
      pw.SizedBox(height: 4),
      pw.Text(
        'These are saved readings from one assessment. They do not establish whether nitrogen, rainfall, or other factors are stable or trending over time. ${usesNpk ? 'Model N/P/K values are estimates, not laboratory results.' : 'NPK is excluded from this model.'}',
        style: const pw.TextStyle(fontSize: 9),
      ),
      if (mapLayer != null &&
          spatialRows(record['selected_polygon']).length >= 3) ...[
        heading('Saved parcel evidence'),
        pw.SizedBox(
          height: 65,
          child: pw.SvgImage(svg: spatialLayerSvg(record, mapLayer)),
        ),
        pw.Text(
          '${_text(mapLayer['label'], 55)} | North up; outline = saved parcel; gray = missing. Raster colors show relative values, not crop suitability.',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ],
      heading('Analyst review'),
      line(
        'Status',
        reviewCase?['status'] ??
            record['verification_status'] ??
            'Not reviewed',
      ),
      if (record['verified_at'] != null)
        line('Reviewed', record['verified_at']),
      if (notes != null && '$notes'.trim().isNotEmpty) ...[
        line('Notes', _text(notes, 160)),
        if ('$notes'.length > 160)
          pw.Text(
            'Full review notes remain in the saved record.',
            style: const pw.TextStyle(fontSize: 8),
          ),
      ],
      heading('Evidence & limitations'),
      if (record['land_cover_notice'] != null)
        line('Land coverage', _text(record['land_cover_notice'], 110))
      else if (record['data_quality_warnings'] is List &&
          (record['data_quality_warnings'] as List).isNotEmpty)
        pw.Text(
          _text(
            '${(record['data_quality_warnings'] as List).first}'.replaceAll(
              RegExp(r'\bmodel\b', caseSensitive: false),
              'AI',
            ),
            150,
          ),
          style: const pw.TextStyle(fontSize: 9),
        ),
      pw.SizedBox(height: 5),
      box(
        '${usesNpk ? 'Saved nutrient inputs are estimates; confirm with a soil test.' : 'NPK is excluded pending verified soil data.'} Annual-input predictions have not been validated against Panabo field outcomes. Confirm crop choice with local agricultural advice and a field inspection.',
      ),
      pw.SizedBox(height: 7),
      pw.Text(
        _text(
          'Sources: Sentinel-2; CHIRPS; ERA5-Land; OpenLandMap; SRTM; NASA POWER (seasonal history); PAGASA (calendar season)${usesNpk ? '; SoilGrids nitrogen when available, with a labelled backup or default' : ''}${sources.isEmpty ? '' : '; ${sources.take(3).join('; ')}'}.',
          280,
        ),
        style: const pw.TextStyle(fontSize: 8.5),
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        'Full source links, dated weather updates, maps, quality warnings and AI calculation details remain in the saved analysis. This summary is not a soil test, legal survey or guarantee of crop performance.',
        style: const pw.TextStyle(fontSize: 8.5),
      ),
      line(
        'Record',
        record['session_id'] ??
            record['id'] ??
            record['prediction_context_id'] ??
            'Unsaved analysis',
      ),
    ]),
  );
  return doc.save();
}
