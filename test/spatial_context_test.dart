import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/spatial_context.dart';
import 'package:geosustain_clean_arranged/web/operator_report.dart';
import 'qa_support.dart';

Map<String, dynamic> spatialRecord() => Map<String, dynamic>.from(
  jsonDecode(File('test/fixtures/spatial_analysis.json').readAsStringSync())
      as Map,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final original = HttpOverrides.current;
    HttpOverrides.global = QaHttpOverrides();
    addTearDown(() => HttpOverrides.global = original);
  });

  test(
    'saved raster statistics expose coverage, coarse pixels and unavailable source',
    () {
      final record = spatialRecord();
      final layers = spatialLayers(record);
      expect(layers.length, 7);
      final ph = layers.firstWhere((l) => l['id'] == 'soil_ph');
      final stats = spatialObject(ph['statistics']);
      expect(stats['mean'], 6);
      expect(stats['standard_deviation'], 0);
      expect(spatialLayerLines(ph).join('\n'), contains('250.000 m'));
      expect(
        spatialLayerLines(ph).join('\n'),
        contains('not independent field samples'),
      );
      final rain = layers.firstWhere((l) => l['id'] == 'rainfall_30d');
      expect(spatialRows(rain['cells']), isEmpty);
      expect(
        spatialLayerLines(rain).join('\n'),
        contains('UNAVAILABLE RASTER FIXTURE'),
      );
      expect(spatialCellColor(ph, 6), '#6baed6');
      expect(spatialCellColor(ph, null), '#bdbdbd');
      expect(
        spatialAssessmentLines({}).single,
        contains('not full-polygon statistics'),
      );
    },
  );

  test('export SVG uses saved clipped fragments and a stable projection', () {
    final record = spatialRecord();
    final layer = spatialLayers(record).firstWhere((l) => l['id'] == 'ndvi');
    final svg = spatialLayerSvg(record, layer);
    final parts = spatialRows(
      layer['cells'],
    ).fold<int>(0, (n, c) => n + (c['parts'] as List).length);
    expect(RegExp('<polygon ').allMatches(svg).length, parts + 2);
    expect(svg, contains('#bdbdbd'));
    expect(svg, isNot(contains('https:')));
    for (final match in RegExp('points="([^"]*)"').allMatches(svg)) {
      for (final point in match.group(1)!.split(' ')) {
        final xy = point.split(',').map(double.parse).toList();
        expect(xy[0], inInclusiveRange(0, 480));
        expect(xy[1], inInclusiveRange(0, 180));
      }
    }
  });

  for (final width in [360.0, 1280.0]) {
    testWidgets(
      'raster map legend and source details remain usable at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final bucket = PageStorageBucket();
        final record = spatialRecord();
        const listKey = PageStorageKey('spatial-test-scroll');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PageStorage(
                bucket: bucket,
                child: ListView(
                  key: listKey,
                  children: [
                    Builder(
                      builder: (context) {
                        bucket.writeState(context, 120.0);
                        return SpatialRasterCard(record: record);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Polygon raster layers'), findsOneWidget);
        expect(
          tester
              .widgetList<PolygonLayer>(find.byType(PolygonLayer))
              .expand((l) => l.polygons)
              .length,
          greaterThan(2),
        );
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Soil pH in water (0 cm) (pH)').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await revealInList(
          tester,
          find.text('Statistics, sources and limitations'),
          list: find.byKey(listKey),
        );
        await tester.tap(find.text('Statistics, sources and limitations'));
        await tester.pumpAndSettle();
        expect(find.textContaining('area-weighted mean 6.000'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test(
    'farmer and analyst report builders export saved clipped raster maps',
    () async {
      final record = spatialRecord();
      final directory = Directory('build/phase-03/export-qa');
      await directory.create(recursive: true);
      final farmer = await buildAnalysisPdf(record);
      final analyst = await buildOperatorReport({
        'case': {'id': 303, 'version': 1, 'status': 'pending'},
        'analysis': record,
        'revisions': [],
        'events': [],
      });
      expect(farmer.length, greaterThan(1000));
      expect(analyst.length, greaterThan(1000));
      await File(
        '${directory.path}/farmer-spatial-report.pdf',
      ).writeAsBytes(farmer);
      await File(
        '${directory.path}/analyst-spatial-report.pdf',
      ).writeAsBytes(analyst);
    },
  );
}
