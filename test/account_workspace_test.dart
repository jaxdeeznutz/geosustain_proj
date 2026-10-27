import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:geosustain_clean_arranged/main.dart';

class _WorkspaceState extends AnalysisState {
  int workspaceLoads = 0;
  @override
  Future<void> refreshFarms() async => workspaceLoads++;
  @override
  Future<String?> refreshLiveWeather({double? lat, double? lon}) async {
    workspaceLoads++;
    return null;
  }

  @override
  void startWeatherAutoRefresh() => workspaceLoads++;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appThemeMode.value = ThemeMode.light;
  });

  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('login keeps its account surface at $size', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const GeoSustainApp(home: LoginPage()));
      await t.pumpAndSettle();
      expect(find.text('Create Farmer Account'), findsNothing);
      if (kIsWeb) {
        expect(find.byType(WebAuthLoginShell), findsOneWidget);
        expect(find.textContaining('Register here'), findsNothing);
        expect(
          find.textContaining('Analyst access is assigned'),
          findsOneWidget,
        );
      } else {
        expect(find.text('Welcome, Farmer!'), findsOneWidget);
        expect(find.byType(WebAuthLoginShell), findsNothing);
        final register = find.textContaining('Register here');
        await t.ensureVisible(register);
        await t.tap(register);
        await t.pumpAndSettle();
        expect(find.text('Create Account'), findsOneWidget);
      }
      expect(t.takeException(), isNull);
    });

    testWidgets('verified signup returns to the correct sign-in at $size', (
      t,
    ) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final api = ApiService(
        client: MockClient((request) async {
          expect(request.url.path, '/api/mobile/verify-email');
          return http.Response(jsonEncode({'verified': true}), 200);
        }),
      );
      addTearDown(api.close);
      await t.pumpWidget(
        GeoSustainApp(
          home: EmailVerificationPage(
            email: 'fixture@example.com',
            ticket: 'x' * 43,
            api: api,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '123456');
      final verify = find.widgetWithText(FilledButton, 'Verify email');
      await t.ensureVisible(verify);
      await t.tap(verify);
      await t.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(
        find.byType(WebAuthLoginShell),
        kIsWeb ? findsOneWidget : findsNothing,
      );
      expect(await api.getToken(), isNull);
      if (kIsWeb) {
        expect(find.textContaining('Farmer account verified.'), findsOneWidget);
      } else {
        expect(find.text('Welcome, Farmer!'), findsOneWidget);
      }
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('web cannot reopen farmer registration through an old route', (
    t,
  ) async {
    await t.pumpWidget(const GeoSustainApp(home: RegisterPage()));
    await t.pumpAndSettle();
    if (kIsWeb) {
      expect(find.text('Register in the mobile app'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await t.tap(find.text('Back to login'));
      await t.pumpAndSettle();
      expect(find.byType(WebAuthLoginShell), findsOneWidget);
    } else {
      expect(find.text('Create Account'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(4));
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('wrong-surface accounts cannot open or load a workspace', (
    t,
  ) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final state = _WorkspaceState()
      ..currentUser = {'id': 1, 'role': kIsWeb ? 'farmer' : 'analyst'}
      ..userLoaded = true;
    await t.pumpWidget(GeoSustainApp(home: ShellPage(analysisState: state)));
    await t.pumpAndSettle();
    expect(find.byType(AccessDeniedPage), findsOneWidget);
    expect(find.byType(WebAnalystDashboard), findsNothing);
    expect(find.byType(GeoBottomNav), findsNothing);
    expect(state.workspaceLoads, 0);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  test('workspace access uses exact server roles and the client platform', () {
    final state = AnalysisState();
    addTearDown(state.dispose);
    for (final role in [
      'analyst',
      'planner',
      'agricultural_planning_analyst',
      'admin',
      'super_admin',
    ]) {
      state.currentUser = {'role': role};
      expect(state.hasWorkspaceAccess, kIsWeb, reason: role);
    }
    state.currentUser = {'role': 'farmer'};
    expect(state.hasWorkspaceAccess, !kIsWeb);
    for (final role in ['unknown', 'not_an_analyst', 'planner_pending']) {
      state.currentUser = {'role': role};
      expect(state.hasWorkspaceAccess, isFalse, reason: role);
    }
  });
}
