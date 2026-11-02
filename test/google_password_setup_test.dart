import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/offline_farm_store.dart';
import 'package:geosustain_clean_arranged/session_token_store.dart';

const password = 'FixturePass!234';
Map<String, dynamic> account({bool pending = true}) => {
  'id': 81,
  'username': 'Fixture Farmer',
  'email': 'fixture@example.com',
  'role': 'farmer',
  'email_verified': true,
  'google_linked': true,
  'auth_provider': 'google',
  'password_setup_required': pending,
};

http.Response accepted() => http.Response(
  jsonEncode({'token': 'normal-session', 'user': account(pending: false)}),
  200,
);

Future<void> screen(
  WidgetTester tester,
  ApiService api, {
  Size size = const Size(390, 844),
  double scale = 1,
  Future<void> Function()? completed,
  Future<void> Function()? signedOut,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorSchemeSeed: green, fontFamily: 'Roboto'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: GooglePasswordSetupPage(
        api: api,
        user: account(),
        onCompleted: completed ?? () async {},
        onSignOut: signedOut ?? () async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> fill(
  WidgetTester tester, {
  String first = password,
  String? second,
}) async {
  await tester.ensureVisible(
    find.byKey(const ValueKey('google-setup-password')),
  );
  await tester.enterText(
    find.byKey(const ValueKey('google-setup-password')),
    first,
  );
  await tester.ensureVisible(
    find.byKey(const ValueKey('google-setup-confirmation')),
  );
  await tester.enterText(
    find.byKey(const ValueKey('google-setup-confirmation')),
    second ?? first,
  );
  await tester.ensureVisible(find.text('Save and continue'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Roboto', 'Ahem']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'token': 'setup-session',
      'account_id': '81',
    });
    OfflineFarmStore.resetTestState();
    String? nativeToken;
    final workspaces = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SessionTokenStore.channel, (call) async {
          switch (call.method) {
            case 'read':
              return nativeToken;
            case 'write':
              nativeToken = call.arguments as String;
              return null;
            case 'delete':
              nativeToken = null;
              return null;
            case 'workspaceRead':
              return workspaces[(call.arguments as Map)['owner']];
            case 'workspaceWrite':
              final data = call.arguments as Map;
              workspaces['${data['owner']}'] = data['value'] as String;
              return null;
            case 'workspaceDelete':
              workspaces.remove((call.arguments as Map)['owner']);
              return null;
            default:
              throw StateError(
                'Unexpected session storage method: ${call.method}',
              );
          }
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SessionTokenStore.channel, null),
  );

  for (final size in [
    const Size(360, 800),
    const Size(480, 700),
    const Size(1440, 900),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('setup form and validation fit $size at $scale', (
        tester,
      ) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final requests = <http.Request>[];
        final api = ApiService(
          client: MockClient((request) async {
            requests.add(request);
            return accepted();
          }),
        );
        await screen(tester, api, size: size, scale: scale);
        expect(find.text('Create your GeoSustain password'), findsOneWidget);
        expect(find.text('fixture@example.com'), findsOneWidget);
        await fill(tester, first: 'nosymbolpassword', second: 'different!234');
        await tester.tap(find.text('Save and continue'));
        await tester.pumpAndSettle();
        expect(find.text('Passwords do not match.'), findsOneWidget);
        expect(requests, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        api.close();
      });
    }
  }

  testWidgets(
    'save binds password to current session and keeps plaintext out of preferences',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <http.Request>[];
      var finished = 0;
      final api = ApiService(
        client: MockClient((request) async {
          requests.add(request);
          return accepted();
        }),
      );
      await screen(
        tester,
        api,
        completed: () async {
          finished++;
        },
      );
      await fill(tester);
      await tester.tap(find.text('Save and continue'));
      await tester.pumpAndSettle();
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/api/mobile/auth/password-setup');
      expect(requests.single.headers['Authorization'], 'Bearer setup-session');
      expect(jsonDecode(requests.single.body), {'new_password': password});
      expect(await api.getToken(), 'normal-session');
      expect(finished, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('account_id'), '81');
      expect(
        prefs.getKeys().map((key) => '${prefs.get(key)}').join(' '),
        isNot(contains(password)),
      );
      expect(
        (await OfflineFarmStore.read())['identity']['password_setup_required'],
        isNot(true),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );

  testWidgets('pending save disables repeat actions and continues once', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final response = Completer<http.Response>();
    var requests = 0, finished = 0;
    final api = ApiService(
      client: MockClient((request) {
        requests++;
        return response.future;
      }),
    );
    await screen(
      tester,
      api,
      completed: () async {
        finished++;
      },
    );
    await fill(tester);
    await tester.tap(find.text('Save and continue'));
    await tester.pump();
    expect(requests, 1);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Saving…'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Sign out'))
          .onPressed,
      isNull,
    );
    response.complete(accepted());
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(finished, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    api.close();
  });

  testWidgets(
    'setup cannot be dismissed with Back and sign-out does not save a password',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <http.Request>[];
      var exited = false;
      final api = ApiService(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 200);
        }),
      );
      await screen(
        tester,
        api,
        signedOut: () async {
          await api.logout();
          exited = true;
        },
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(GooglePasswordSetupPage), findsOneWidget);
      await fill(tester);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(exited, isTrue);
      expect(await api.getToken(), isNull);
      expect(
        requests.where((r) => r.url.path.endsWith('/password-setup')),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );

  testWidgets('restoring a setup token opens setup instead of a workspace', (
    tester,
  ) async {
    final paths = <String>[];
    final api = ApiService(
      client: MockClient((request) async {
        paths.add(request.url.path);
        return http.Response(jsonEncode({'user': account()}), 200);
      }),
    );
    await tester.pumpWidget(MaterialApp(home: SessionGate(api: api)));
    await tester.pumpAndSettle();
    expect(find.byType(GooglePasswordSetupPage), findsOneWidget);
    expect(find.byType(ShellPage), findsNothing);
    expect(paths, ['/api/mobile/me']);
    expect(
      (await OfflineFarmStore.read())['identity']['password_setup_required'],
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    api.close();
  });

  testWidgets(
    'cached setup identity cannot enter the offline workspace during an outage',
    (tester) async {
      await OfflineFarmStore.cacheIdentity(account());
      final api = ApiService(
        client: MockClient((request) async => http.Response('{}', 503)),
      );
      await tester.pumpWidget(MaterialApp(home: SessionGate(api: api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open saved farms offline'));
      await tester.pumpAndSettle();
      expect(find.byType(ShellPage), findsNothing);
      expect(
        find.textContaining('Offline farms are unavailable.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );

  test('late setup response cannot replace another account session', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final api = ApiService(
      client: MockClient((request) {
        started.complete();
        return response.future;
      }),
    );
    final result = api.completeGooglePasswordSetup(password);
    final failed = expectLater(
      result,
      throwsA(
        isA<ApiException>().having((error) => error.statusCode, 'status', 409),
      ),
    );
    await started.future;
    await api.saveToken('another-account-session');
    response.complete(accepted());
    await failed;
    expect(await api.getToken(), 'another-account-session');
    api.close();
  });

  test(
    'existing linked accounts keep their normal login and offline eligibility',
    () async {
      final requests = <http.Request>[];
      final api = ApiService(
        client: MockClient((request) async {
          requests.add(request);
          return accepted();
        }),
      );
      final data = await api.googleLogin('synthetic-google-proof');
      expect(data['user']['password_setup_required'], isFalse);
      expect(data['user']['id'], 81);
      expect(requests.single.url.path, '/api/mobile/auth/google');
      final state = AnalysisState(api: api)
        ..currentUser = account(pending: false);
      expect(state.hasWorkspaceAccess, isTrue);
      state.currentUser = account();
      expect(state.hasWorkspaceAccess, isFalse);
      state.dispose();
    },
  );
}
