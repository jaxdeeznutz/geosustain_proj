import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'qa_support.dart';
import 'seasonal_planting_test.dart' show seasonalPlantingFixture;

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'direct crop details and seasonal evidence at dark=$dark scale=$scale',
        (tester) async {
          tester.view.physicalSize = const Size(390, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          SharedPreferences.setMockInitialValues({});
          HttpOverrides.global = QaHttpOverrides();
          addTearDown(() => HttpOverrides.global = null);
          final state = AnalysisState()
            ..currentUser = {'id': 2, 'role': 'farmer'};
          addTearDown(state.dispose);
          final record =
              jsonDecode(
                    File(
                      'test/fixtures/no_npk_model_explanation.json',
                    ).readAsStringSync(),
                  )
                  as Map<String, dynamic>;
          record.addAll({
            'session_id': 7,
            'farm_id': 3,
            'owner_id': 2,
            'analysis_status': 'completed',
            'verification_status': 'draft',
            'seasonal_assessment':
                seasonalPlantingFixture()['seasonal_assessment'],
          });
          final climate =
              (record['seasonal_assessment'] as Map)['monthly_climate'] as Map;
          climate['monthly_cycle'] = [
            {'month': 6, 'moisture_status': 'humid'},
          ];
          final saved = jsonEncode(record);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('crop-preview'),
              child: MaterialApp(
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
                  body: SingleChildScrollView(
                    child: FarmerAnalysisContent(state: state, record: record),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Experimental model'), findsNothing);
          await tester.ensureVisible(find.text('1. Rice'));
          await tester.tap(find.text('1. Rice'));
          await tester.pumpAndSettle();
          expect(find.byType(RecommendedCropDetailsSheet), findsOneWidget);
          expect(find.byType(BottomSheet), findsOneWidget);
          expect(find.text('Full explanation and sources'), findsNothing);
          expect(find.text('June: Wet conditions'), findsOneWidget);
          expect(
            find.text('Check irrigation and planting schedule'),
            findsNothing,
          );
          expect(find.text('Latest weather & sources'), findsNothing);
          expect(find.text('Compare with another crop'), findsNothing);
          expect(
            find.textContaining('percentage points above Coconut'),
            findsNothing,
          );
          expect(tester.takeException(), isNull);

          Future<void> capture(String name) async {
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('crop-preview')),
              );
              final picture = await boundary.toImage();
              final bytes = await picture.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final folder = Directory('build/crop-season-previews')
                ..createSync(recursive: true);
              await File(
                '${folder.path}/$name-${dark ? 'dark' : 'light'}-$scale.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              picture.dispose();
            });
          }

          await capture('crop');
          await tester.ensureVisible(find.text('Explainable AI'));
          await tester.pumpAndSettle();
          await capture('explanation');
          expect(jsonEncode(record), saved);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
