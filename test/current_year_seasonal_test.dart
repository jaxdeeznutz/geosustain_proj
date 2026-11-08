import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/seasonal_context.dart';

Map<String, dynamic> currentYearFixture() =>
    jsonDecode(
          File(
            'test/fixtures/current_year_seasonal_2026.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test(
    'report text distinguishes selected month, latest estimates and station forecast',
    () {
      final record = currentYearFixture();
      final lines = seasonalAssessmentLines(record).join('\n');
      expect(lines, contains('2026 climate update'));
      expect(
        lines,
        contains('November 2026: complete monthly estimates unavailable'),
      );
      expect(
        lines,
        contains(
          'September 2026 latest available month: rainfall 197.7 mm/month',
        ),
      );
      expect(lines, contains('below normal 38%'));
      expect(lines, contains('Tagum station'));
      expect(lines, contains('not a forecast for the analyzed parcel'));
      expect(lines, contains('do not replace annual model inputs'));
    },
  );

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'seasonal summary omits crop rows and latest-weather block dark=$dark scale=$scale',
        (tester) async {
          tester.view.physicalSize = const Size(390, 950);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final record = currentYearFixture();
          final saved = jsonEncode(record);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('current-year-preview'),
              child: MaterialApp(
                theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light,
                  fontFamily: 'Roboto',
                  colorSchemeSeed: green,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: SeasonalContextCard(record: record, simple: true),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('November: Wet conditions'), findsOneWidget);
          expect(
            find.text('Historical monthly pattern; not a forecast.'),
            findsOneWidget,
          );
          for (final removed in [
            '2026 seasonal update',
            'Latest weather & sources',
            'Banana',
            'Rice',
            'September 2026 weather estimates',
          ]) {
            expect(find.text(removed), findsNothing);
          }
          expect(find.byType(ExpansionTile), findsNothing);
          expect(tester.takeException(), isNull);
          if (scale == 1) {
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('current-year-preview')),
              );
              final picture = await boundary.toImage();
              final bytes = await picture.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final folder = Directory('build/current-year-seasonal-previews')
                ..createSync(recursive: true);
              await File(
                '${folder.path}/${dark ? 'dark' : 'light'}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              picture.dispose();
            });
          }
          expect(jsonEncode(record), saved);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
