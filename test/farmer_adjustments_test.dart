import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/local_explanation.dart';
import 'qa_support.dart';

void main() {
  test(
    'annual seven-crop explanation survives SQL summary rounding and JSON transport',
    () {
      final record =
          jsonDecode(
                File(
                  'test/fixtures/annual_history_roundtrip.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final explanation = verifiedLocalExplanation(record);
      expect(explanation['status'], 'available');
      expect(explanation['class_order'], hasLength(7));
      final score = record['crop_compatibility_pct'] as num;
      final changed = {...record, 'crop_compatibility_pct': score + .01};
      expect(verifiedLocalExplanation(changed), isEmpty);
      expect(localExplanationDiagnostics(changed)['check'], 'context_mismatch');
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('navigation labels and sheet text keep contrast in $mode', (
      tester,
    ) async {
      final old = appThemeMode.value;
      addTearDown(() => appThemeMode.value = old);
      appThemeMode.value = mode;
      await tester.pumpWidget(
        GeoSustainApp(
          home: Scaffold(
            bottomNavigationBar: GeoBottomNav(index: 2, onTap: (_) {}),
            body: const CropSheetFrame(
              header: Text('Crop header'),
              children: [Text('Crop details')],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final navContext = tester.element(find.byType(NavigationBar));
      final style = NavigationBarTheme.of(navContext).labelTextStyle!;
      final scheme = Theme.of(navContext).colorScheme;
      for (final states in [
        <WidgetState>{},
        {WidgetState.selected},
      ]) {
        final ink = style.resolve(states)!.color!;
        final a = ink.computeLuminance(),
            b = scheme.surfaceContainer.computeLuminance();
        final contrast =
            (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
        expect(contrast, greaterThanOrEqualTo(4.5));
      }
      final sheetContext = tester.element(find.text('Crop details'));
      expect(Theme.of(sheetContext).brightness, Brightness.light);
      expect(DefaultTextStyle.of(sheetContext).style.color, CropSheetStyle.ink);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('farmer has one ranking and review follows map and details', (
    tester,
  ) async {
    final original = HttpOverrides.current;
    HttpOverrides.global = QaHttpOverrides();
    addTearDown(() => HttpOverrides.global = original);
    final state = AnalysisState()..currentUser = {'id': 2, 'role': 'farmer'};
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FarmerAnalysisContent(
              state: state,
              record: {
                'session_id': 7,
                'farm_id': 4,
                'analysis_status': 'completed',
                'recommendation_basis': 'model_probability',
                'top_crop_recommendations': [
                  {'crop': 'Rice', 'compatibility_pct': 31.7},
                ],
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1. Rice'), findsOneWidget);
    expect(find.text('Top model recommendation'), findsNothing);
    expect(find.text('Analyzed Farm Location'), findsNothing);
    final reviewY = tester.getTopLeft(find.byType(AnalysisReviewCard)).dy;
    expect(
      reviewY,
      greaterThan(tester.getTopLeft(find.text('Full analysis details')).dy),
    );
    expect(
      reviewY,
      lessThan(tester.getTopLeft(find.text('Save report (PDF)')).dy),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
