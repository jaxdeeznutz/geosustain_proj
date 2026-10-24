import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'analysis_scope_test.dart' as fixtures;
import 'qa_support.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
}

void main() {
  setUpAll(() async {
    final config = File('.dart_tool/package_config.json').absolute;
    final packages =
        jsonDecode(await config.readAsString())['packages'] as List;
    final flutter = packages.firstWhere((p) => p['name'] == 'flutter');
    final root = Directory.fromUri(
      config.uri.resolve(flutter['rootUri']),
    ).parent.parent;
    for (final entry in {
      'Roboto': 'roboto-regular.ttf',
      'Ahem': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key);
      loader.addFont(
        File(
          '${root.path}/bin/cache/artifacts/material_fonts/${entry.value}',
        ).readAsBytes().then(ByteData.sublistView),
      );
      await loader.load();
    }
  });
  for (final dark in [false, true]) {
    for (final size in [
      const Size(402, 874),
      const Size(874, 402),
      const Size(360, 812),
      const Size(812, 360),
    ]) {
      testWidgets(
        'reported surfaces retain readable contrast dark=$dark size=$size',
        (tester) async {
          HttpOverrides.global = QaHttpOverrides();
          addTearDown(() => HttpOverrides.global = null);
          appThemeMode.value = dark ? ThemeMode.dark : ThemeMode.light;
          addTearDown(() => appThemeMode.value = ThemeMode.light);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          if (size.width == 360 || size.width == 812) {
            tester.platformDispatcher.textScaleFactorTestValue = .85;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
          }
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final state = AnalysisState(api: fixtures.ScopeApi())
            ..currentUser = {
              'id': 10,
              'role': 'farmer',
              'username': 'QA Farmer',
            }
            ..userLoaded = true
            ..liveWeather = {
              'temperature_c': 31,
              'weather_description': 'Partly cloudy',
              'live_humidity': 64,
              'wind_speed_kmh': 12,
            };
          addTearDown(state.dispose);
          final key = GlobalKey();
          Future<void> mount(Widget screen) async {
            await tester.pumpWidget(
              RepaintBoundary(
                key: key,
                child: GeoSustainApp(home: screen),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }

          Color foreground(Finder f) =>
              (tester.renderObject<RenderParagraph>(f).text as TextSpan)
                  .style!
                  .color!;
          Future<void> capture(String name) async {
            if (!const bool.fromEnvironment('CAPTURE_DEVICE_THEME')) return;
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = Directory('build/device-theme-evidence');
              await directory.create(recursive: true);
              await File(
                '${directory.path}/$name-${dark ? 'dark' : 'light'}-${size.width.toInt()}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }

          await mount(
            Scaffold(
              body: HomePage(
                state: state,
                go: (_) {},
                logout: () {},
                message: (_) {},
              ),
              bottomNavigationBar: GeoBottomNav(index: 0, onTap: (_) {}),
            ),
          );
          final action = find.text('Create a Farm Boundary');
          await tester.scrollUntilVisible(
            action,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          final card = tester.widget<Card>(
            find.ancestor(of: action, matching: find.byType(Card)).first,
          );
          expect(
            contrast(foreground(action), card.color!),
            greaterThanOrEqualTo(4.5),
          );
          final subtitle = find.text('Walk or draw your farm area.');
          expect(
            contrast(foreground(subtitle), card.color!),
            greaterThanOrEqualTo(4.5),
          );
          await capture('quick-actions');
          final weather = find.textContaining('Partly cloudy | Humidity');
          await tester.scrollUntilVisible(
            weather,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          final surface = tester.widget<Container>(
            find
                .ancestor(
                  of: weather,
                  matching: find.byWidgetPredicate(
                    (w) =>
                        w is Container &&
                        w.decoration is BoxDecoration &&
                        (w.decoration as BoxDecoration).gradient != null,
                  ),
                )
                .first,
          );
          final colors =
              ((surface.decoration as BoxDecoration).gradient!
                      as LinearGradient)
                  .colors;
          for (final color in colors) {
            expect(
              contrast(foreground(weather), color),
              greaterThanOrEqualTo(4.5),
            );
          }
          final heading = find.text('Current Weather');
          expect(
            contrast(
              foreground(heading),
              Theme.of(tester.element(heading)).scaffoldBackgroundColor,
            ),
            greaterThanOrEqualTo(4.5),
          );
          final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
          final frame = tester.widget<Container>(
            find
                .ancestor(
                  of: find.byType(NavigationBar),
                  matching: find.byType(Container),
                )
                .first,
          );
          expect(
            (frame.decoration as BoxDecoration).color,
            nav.backgroundColor,
          );
          if (dark) {
            expect(
              ((frame.decoration as BoxDecoration).border! as Border).top.color
                  .computeLuminance(),
              lessThan(.3),
            );
          }
          await capture('weather-and-navigation');
          await mount(
            Scaffold(
              body: ListView(
                children: [AnalysisHistoryRow(record: fixtures.analysis(9, 1))],
              ),
            ),
          );
          final farm = find.text('Farm 1');
          final historyCard = tester.widget<Card>(find.byType(Card).first);
          expect(
            contrast(foreground(farm), historyCard.color!),
            greaterThanOrEqualTo(4.5),
          );
          final owner = find.text('Owner: Test Farmer');
          expect(
            contrast(foreground(owner), historyCard.color!),
            greaterThanOrEqualTo(4.5),
          );
          for (final pill in tester.widgetList<GeoStatusPill>(
            find.byType(GeoStatusPill),
          )) {
            final label = find.text(pill.label);
            final box = tester.widget<Container>(
              find.ancestor(of: label, matching: find.byType(Container)).first,
            );
            final background = (box.decoration as BoxDecoration).color!;
            expect(
              contrast(foreground(label), background),
              greaterThanOrEqualTo(4.5),
            );
          }
          await capture('analysis-card');
          for (final screen in [
            SavedAnalysesPage(state: state),
            ReportsListPage(state: state),
          ]) {
            await mount(screen);
            final empty = find.textContaining(
              screen is SavedAnalysesPage
                  ? 'No saved analysis'
                  : 'No generated reports',
            );
            final scaffold = tester.widget<Scaffold>(
              find.byType(Scaffold).first,
            );
            expect(
              contrast(foreground(empty), scaffold.backgroundColor!),
              greaterThanOrEqualTo(4.5),
            );
            await capture(
              screen is SavedAnalysesPage ? 'saved-empty' : 'reports-empty',
            );
          }
          await mount(EditProfilePage(state: state));
          final profileScaffold = tester.widget<Scaffold>(
            find.byType(Scaffold).first,
          );
          expect(
            profileScaffold.backgroundColor,
            Theme.of(
              tester.element(find.byType(Scaffold)),
            ).scaffoldBackgroundColor,
          );
          final name = find.widgetWithText(TextField, 'QA Farmer');
          expect(name, findsOneWidget);
          await capture('account-settings');
        },
      );
    }
  }
  testWidgets('landscape header is compact and controls respect side insets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(874, 402);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(left: 44);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(
      GeoSustainApp(
        home: Scaffold(
          body: GeoSafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                GeoSustainHeader(title: 'Account Settings', back: () {}),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(GeoSustainHeader)).height, 72);
    for (final tooltip in ['Back', 'Notifications']) {
      final rect = tester.getRect(find.byTooltip(tooltip));
      expect(rect.left, greaterThanOrEqualTo(44));
      expect(rect.right, lessThanOrEqualTo(874));
      expect(rect.height, greaterThanOrEqualTo(48));
    }
    expect(tester.takeException(), isNull);
  });
}
