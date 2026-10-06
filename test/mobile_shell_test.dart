import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/api_service.dart';

class _ShellApi extends ApiService {
  @override
  Future<List<dynamic>> getHistory() async => [];
  @override
  Future<List<dynamic>> getSavedAnalyses() async => [];
  @override
  Future<List<dynamic>> getReports() async => [];
  @override
  Future<Map<String, dynamic>> getCounts() async => {
    'analysis_count': 0,
    'saved_count': 0,
    'report_count': 0,
  };
  @override
  Future<List<Map<String, dynamic>>> getFarms({
    bool includeArchived = false,
  }) async => [];
  @override
  Future<Map<String, dynamic>> getLiveWeather(double lat, double lon) async =>
      {};
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
    final fonts = '${root.path}/bin/cache/artifacts/material_fonts';
    for (final entry in {
      'Roboto': 'roboto-regular.ttf',
      'Ahem': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key);
      loader.addFont(
        File(
          '$fonts/${entry.value}',
        ).readAsBytes().then((b) => ByteData.sublistView(b)),
      );
      await loader.load();
    }
  });
  testWidgets(
    'five labelled tabs, method selection, back, role readonly and logout',
    (tester) async {
      SharedPreferences.setMockInitialValues({'token': 'fixture-session'});
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AnalysisState(api: _ShellApi());
      state.currentUser = {
        'id': 1,
        'username': 'Farmer',
        'email': 'farmer@example.com',
        'role': 'farmer',
      };
      state.userLoaded = true;
      final previewKey = GlobalKey();
      Future<void> capture(String name) async {
        await tester.runAsync(() async {
          final boundary =
              previewKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('build/mobile-qa');
          await directory.create(recursive: true);
          await File(
            '${directory.path}/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.pumpWidget(
        RepaintBoundary(
          key: previewKey,
          child: GeoSustainApp(home: ShellPage(analysisState: state)),
        ),
      );
      await tester.pumpAndSettle();
      final destinations = tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((w) => w.label)
          .toList();
      expect(destinations, [
        'Home',
        'My Farms',
        'Analysis',
        'History',
        'Profile',
      ]);
      expect(
        find.text('Understand your land. Plan your farm.'),
        findsOneWidget,
      );
      await capture('home-360');
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();
      expect(find.text('How would you like to map your land?'), findsOneWidget);
      expect(find.text('Create a Farm Boundary').hitTestable(), findsOneWidget);
      expect(
        find.text('Analyze Land Using a Polygon').hitTestable(),
        findsOneWidget,
      );
      await capture('method-picker-360');
      Navigator.of(
        tester.element(find.text('How would you like to map your land?')),
      ).pop();
      await tester.pumpAndSettle();
      for (final label in ['My Farms', 'Analysis', 'History', 'Profile']) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(label.toLowerCase().replaceAll(' ', '-'));
      }
      expect(find.textContaining('farmer@example.com'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Profile'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('Edit Profile').hitTestable(),
        find
            .descendant(
              of: find.byType(ProfilePage),
              matching: find.byType(ListView),
            )
            .first,
        const Offset(0, -200),
      );
      await tester.tap(find.text('Edit Profile'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('Sign Out').hitTestable(),
        find
            .descendant(
              of: find.byType(ProfilePage),
              matching: find.byType(ListView),
            )
            .first,
        const Offset(0, -200),
      );
      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome, Farmer!'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getString('token'),
        isNull,
      );
      expect(state.currentUser, isNull);
      expect(state.result, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
