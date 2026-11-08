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
        '2026 update precedes collapsed historical guidance dark=$dark scale=$scale',
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
          expect(find.text('2026 seasonal update'), findsNothing);
          expect(find.text('November: Wet conditions'), findsOneWidget);
          expect(find.text('Banana'), findsOneWidget);
          final latest = find.text('Latest weather & sources');
          await tester.ensureVisible(latest);
          await tester.tap(latest);
          await tester.pumpAndSettle();
          expect(find.text('2026 seasonal update'), findsOneWidget);
          expect(find.text('September 2026 weather estimates'), findsOneWidget);
          expect(
            find.text('November 2026 rainfall outlook - Tagum'),
            findsOneWidget,
          );
          expect(
            find.text(
              'November 2026: complete monthly estimates are not yet available.',
            ),
            findsOneWidget,
          );
          expect(
            find.text('Below normal: 38%\nNear normal: 30%\nAbove normal: 32%'),
            findsOneWidget,
          );
          expect(
            find.text('Banana'),
            findsOneWidget,
          ); // no historical result presented as 2026
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
          await tester.ensureVisible(
            find.text('Current-year sources and coverage'),
          );
          await tester.tap(find.text('Current-year sources and coverage'));
          await tester.pumpAndSettle();
          expect(find.text('Current-year climate sources'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.textContaining('not a forecast for the analyzed parcel'),
            250,
            scrollable: find
                .descendant(
                  of: find.byType(BottomSheet),
                  matching: find.byType(Scrollable),
                )
                .last,
          );
          expect(
            find.textContaining('not a forecast for the analyzed parcel'),
            findsOneWidget,
          );
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
          expect(jsonEncode(record), saved);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
