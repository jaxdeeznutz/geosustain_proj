import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('analysis progress can be minimized without a layout error', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var minimized = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FullscreenAnalysisOverlay(
            message: 'Analyzing your land',
            onMinimize: () => minimized = true,
          ),
        ),
      ),
    );
    expect(find.text('Analyzing your farm'), findsOneWidget);
    expect(find.text('Preparing results'), findsOneWidget);
    await tester.tap(find.text('Minimize'));
    expect(minimized, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification settings and appearance have separate controls', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsPage(section: SettingsSection.notifications),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Analysis and review push alerts'), findsOneWidget);
    expect(find.text('Dark mode'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsPage(section: SettingsSection.appearance),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dark mode'), findsOneWidget);
    expect(find.text('Analysis and review push alerts'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
