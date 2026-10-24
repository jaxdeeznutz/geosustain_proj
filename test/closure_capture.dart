// Synthetic Flutter-rendered evidence, not browser/physical-device screenshots.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/api_service.dart';

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
  for (final width in [360.0, 1280.0]) {
    testWidgets('capture login validation $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: const GeoSustainApp(home: LoginPage()),
        ),
      );
      final submit = find.widgetWithText(
        FilledButton,
        width < 900 ? 'Sign In' : 'Sign In to Dashboard',
      );
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'login-${width.toInt()}');
    });
  }
  for (final dark in [false, true]) {
    testWidgets('capture review inbox dark=$dark', (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      appThemeMode.value = dark ? ThemeMode.dark : ThemeMode.light;
      addTearDown(() => appThemeMode.value = ThemeMode.light);
      final api = ApiService(
        client: MockClient(
          (request) async => http.Response(
            '{"notifications":[{"id":7,"session_id":8,"decision":"verified","created_at":"2026-10-23","read_at":null}],"unread_count":1,"has_more":false}',
            200,
          ),
        ),
      );
      addTearDown(api.close);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: GeoSustainApp(home: NotificationsPage(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'inbox-${dark ? 'dark' : 'light'}');
    });
  }
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/closure-evidence');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
