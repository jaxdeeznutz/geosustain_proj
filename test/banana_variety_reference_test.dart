import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';

void main() {
  setUpAll(() async {
    for (final name in ['Roboto', 'Ahem']) {
      await (FontLoader(
        name,
      )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'banana reference is readable at 360px, dark=$dark scale=$scale without modifying the result',
        (tester) async {
          tester.view.physicalSize = const Size(360, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final record = {
            'predicted_crop': 'Banana',
            'crop_compatibility_pct': 31.77,
          };
          final before = jsonEncode(record);
          final key = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
                fontFamily: 'Roboto',
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: RepaintBoundary(
                  key: key,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: CropVarietyReference(
                        crop: '${record['predicted_crop']}',
                        initiallyExpanded: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (final name in ['Cavendish', 'Lakatan', 'Saba']) {
            expect(find.text(name), findsOneWidget);
          }
          expect(
            find.textContaining(
              'separate variety predictions are not available',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('%'), findsNothing);
          expect(find.textContaining('1,524 mm/year'), findsOneWidget);
          expect(find.textContaining('1.5-1,000 m'), findsOneWidget);
          expect(jsonEncode(record), before);
          expect(tester.takeException(), isNull);
          if (scale == 1) {
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              final picture = await boundary.toImage();
              final bytes = await picture.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final dir = Directory('build/banana-variety-previews')
                ..createSync(recursive: true);
              File(
                '${dir.path}/${dark ? 'dark' : 'light'}.png',
              ).writeAsBytesSync(bytes!.buffer.asUint8List());
              picture.dispose();
            });
          }
          await tester.ensureVisible(find.text('Variety sources'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Variety sources'));
          await tester.pumpAndSettle();
          expect(find.text('Banana variety sources'), findsOneWidget);
          expect(
            find.textContaining('https://www.anflocor.com/tadeco'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('other crops have no banana variety panel', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CropVarietyReference(crop: 'Rice')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Banana varieties'), findsNothing);
  });

  testWidgets(
    'banana expansion survives a saved page scroll offset and remount',
    (tester) async {
      final bucket = PageStorageBucket();
      const scrollKey = PageStorageKey<String>('admin-page-3');
      Widget page({bool seed = false}) => MaterialApp(
        home: Scaffold(
          body: PageStorage(
            bucket: bucket,
            child: SingleChildScrollView(
              key: scrollKey,
              child: Builder(
                builder: (context) {
                  if (seed) bucket.writeState(context, 420.0);
                  return const CropVarietyReference(crop: 'banana');
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(page(seed: true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Banana varieties'));
      await tester.pumpAndSettle();
      expect(find.text('Cavendish').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Cavendish').hitTestable(), findsOneWidget);
    },
  );
}
