import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:geosustain_clean_arranged/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appThemeMode.value = ThemeMode.light;
  });
  for (final spec in [
    (const Size(360, 800), 1.0),
    (const Size(1280, 800), 1.0),
    (const Size(1440, 900), 1.0),
    (const Size(1000, 700), 2.0),
  ]) {
    testWidgets(
      'landscape login retains controls and callbacks at ${spec.$1} scale ${spec.$2}',
      (tester) async {
        tester.view.physicalSize = spec.$1;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final email = TextEditingController(),
            password = TextEditingController();
        addTearDown(email.dispose);
        addTearDown(password.dispose);
        var calls = 0;
        await tester.pumpWidget(
          GeoSustainApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: spec.$1,
                textScaler: TextScaler.linear(spec.$2),
              ),
              child: RepaintBoundary(
                key: const ValueKey('login-preview'),
                child: WebAuthLoginShell(
                  emailController: email,
                  passwordController: password,
                  loading: false,
                  onLogin: () {
                    calls++;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Welcome Back!'), findsOneWidget);
        expect(
          find.textContaining('Google sign-in is currently unavailable'),
          findsOneWidget,
        );
        expect(find.text('Create Farmer Account'), findsNothing);
        expect(tester.takeException(), isNull);
        if (spec.$2 == 1.0) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('login-preview')),
            );
            final picture = await boundary.toImage();
            final bytes = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final directory = Directory('build/phase-07/web-design-qa')
              ..createSync(recursive: true);
            await File(
              '${directory.path}/login-${spec.$1.width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            picture.dispose();
          });
        }
        await tester.enterText(
          find.widgetWithText(TextField, 'Email Address'),
          'analyst@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Password'),
          'test-password',
        );
        final submit = find.text('Sign In to Dashboard');
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pump();
        expect(calls, 1);
        expect(email.text, 'analyst@example.com');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final analyst in [false, true]) {
    test(
      'analysis transport selects the correct protected route and idempotent retry scope: analyst=$analyst',
      () async {
        final requests = <http.Request>[];
        final api = ApiService(
          client: MockClient((request) async {
            requests.add(request);
            return http.Response(
              jsonEncode(
                request.method == 'GET'
                    ? {'status': 'not_found'}
                    : {'session_id': 71, 'analysis_status': 'completed'},
              ),
              200,
            );
          }),
        );
        await api.saveToken('synthetic-token');
        final result = await api.analyzePoint(
          7.29,
          125.62,
          intendedPlantingMonth: 2,
          independentAnalyst: analyst,
        );
        expect(result['session_id'], 71);
        final post = requests.singleWhere(
          (request) => request.method == 'POST',
        );
        expect(
          post.url.path,
          analyst ? '/api/web/analysis' : '/api/mobile/analysis',
        );
        expect(post.headers['Idempotency-Key'], isNotEmpty);
        expect(jsonDecode(post.body)['intended_planting_month'], 2);
        expect(jsonDecode(post.body).containsKey('farm_id'), isFalse);
        api.close();
      },
    );
  }
  test(
    'interrupted independent analysis retries with the same request key',
    () async {
      final posts = <http.Request>[];
      final api = ApiService(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response('{"status":"not_found"}', 200);
          }
          posts.add(request);
          if (posts.length == 1) {
            throw http.ClientException('Synthetic connection interruption');
          }
          return http.Response(
            '{"session_id":71,"analysis_status":"completed"}',
            200,
          );
        }),
      );
      await api.saveToken('synthetic-token');
      await expectLater(
        api.analyzePoint(7.29, 125.62, independentAnalyst: true),
        throwsA(isA<http.ClientException>()),
      );
      await api.analyzePoint(7.29, 125.62, independentAnalyst: true);
      expect(posts.length, 2);
      expect(
        posts.last.headers['Idempotency-Key'],
        posts.first.headers['Idempotency-Key'],
      );
      expect(
        posts.every((request) => request.url.path == '/api/web/analysis'),
        isTrue,
      );
      api.close();
    },
  );
}
