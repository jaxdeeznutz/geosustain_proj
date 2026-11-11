import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'analysis_scope_test.dart' as scope;
import 'qa_support.dart';

class RecoveryFixtureApi extends scope.ScopeApi {
  bool failAnalysis = true;
  String failureMessage = 'Synthetic temporary outage';
  @override
  Future<Map<String, dynamic>> analyzePolygon(
    List<Map<String, double>> polygon, {
    String? placeName,
    int? intendedPlantingMonth,
    int? farmId,
    int? boundaryVersion,
    bool independentAnalyst = false,
  }) async {
    if (failAnalysis) {
      throw ApiException(503, failureMessage);
    }
    return super.analyzePolygon(
      polygon,
      placeName: placeName,
      intendedPlantingMonth: intendedPlantingMonth,
      farmId: farmId,
      boundaryVersion: boundaryVersion,
      independentAnalyst: independentAnalyst,
    );
  }
}

Future<ApiService> apiFor(
  Future<http.Response> Function(http.Request) handler,
) async {
  final api = ApiService(client: MockClient(handler));
  await api.saveToken('synthetic-mobile-session');
  return api;
}

Map<String, dynamic> farmerRecord() => {
  ...scope.analysis(9, 1),
  'boundary_version': 1,
  'recommendation_basis': 'model_probability',
  'is_crop_recommended': true,
  'top_crop_recommendations': [
    {'crop': 'Rice', 'compatibility_pct': 47.0},
    {'crop': 'Banana', 'compatibility_pct': 24.0},
    {'crop': 'Cacao', 'compatibility_pct': 4.9},
    {'crop': 'Corn', 'compatibility_pct': 4.0},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({'account_id': '10'});
    final previous = HttpOverrides.current;
    HttpOverrides.global = QaHttpOverrides();
    addTearDown(() => HttpOverrides.global = previous);
  });

  test('farm reads recover from 503 without replacing the session', () async {
    var calls = 0;
    final api = await apiFor((request) async {
      calls++;
      expect(
        request.headers['Authorization'],
        'Bearer synthetic-mobile-session',
      );
      return calls == 1
          ? http.Response('<html>Starting</html>', 503)
          : http.Response(
              jsonEncode({
                'farms': [scope.farm(1)],
              }),
              200,
            );
    });
    addTearDown(api.close);
    expect((await api.getFarms()).single['id'], 1);
    expect(calls, 2);
    expect(await api.getToken(), 'synthetic-mobile-session');
  });

  test(
    'bounded failure can recover on the same API instance without reopening',
    () async {
      var calls = 0;
      var available = false;
      final api = await apiFor((request) async {
        calls++;
        return available
            ? http.Response('{"farms":[]}', 200)
            : http.Response('{"detail":"Temporary outage"}', 503);
      });
      addTearDown(api.close);
      await expectLater(
        api.getFarms(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 503)),
      );
      expect(calls, 2);
      available = true;
      expect(await api.getFarms(), isEmpty);
      expect(calls, 3);
      expect(await api.getToken(), 'synthetic-mobile-session');
    },
  );

  test(
    '401 is not retried and delayed retries stop when the account changes',
    () async {
      var calls = 0;
      final unauthorized = await apiFor((request) async {
        calls++;
        return http.Response('{"detail":"Expired"}', 401);
      });
      addTearDown(unauthorized.close);
      await expectLater(
        unauthorized.getFarms(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
      expect(calls, 1);
      calls = 0;
      late ApiService switching;
      switching = await apiFor((request) async {
        calls++;
        await switching.saveToken('synthetic-other-account');
        return http.Response('{}', 503);
      });
      addTearDown(switching.close);
      await expectLater(
        switching.getFarms(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
      expect(calls, 1);
      expect(await switching.getToken(), 'synthetic-other-account');
    },
  );

  test(
    'analysis status recovers before sending a single owner-bound POST',
    () async {
      final posts = <http.Request>[];
      var reads = 0;
      final api = await apiFor((request) async {
        if (request.method == 'GET') {
          reads++;
          return reads == 1
              ? http.Response('{}', 503)
              : http.Response('{"status":"not_found"}', 200);
        }
        posts.add(request);
        return http.Response(
          '{"session_id":91,"analysis_status":"completed"}',
          200,
        );
      });
      addTearDown(api.close);
      expect((await api.analyzePoint(7.3, 125.6))['session_id'], 91);
      expect(reads, 2);
      expect(posts.length, 1);
      expect(posts.single.headers['Idempotency-Key'], isNotEmpty);
      expect(
        posts.single.headers['Authorization'],
        'Bearer synthetic-mobile-session',
      );
    },
  );

  test(
    'proxy failure after an accepted analysis retrieves the result without replaying its POST',
    () async {
      final posts = <http.Request>[];
      final readKeys = <String>[];
      final api = await apiFor((request) async {
        if (request.method == 'POST') {
          posts.add(request);
          return http.Response('{}', 503);
        }
        readKeys.add(request.url.pathSegments.last);
        return http.Response(
          jsonEncode(
            posts.isEmpty
                ? {'status': 'not_found'}
                : {
                    'status': 'completed',
                    'analysis': {
                      'session_id': 92,
                      'analysis_status': 'completed',
                    },
                  },
          ),
          200,
        );
      });
      addTearDown(api.close);
      expect((await api.analyzePoint(7.3, 125.6))['session_id'], 92);
      expect(posts.length, 1);
      expect(readKeys, everyElement(posts.single.headers['Idempotency-Key']));
    },
  );

  test(
    'explicit online analysis recovers a cached offline workspace and clears a failed attempt',
    () async {
      final api = RecoveryFixtureApi();
      await api.saveToken('synthetic-mobile-session');
      final state = AnalysisState(api: api)
        ..currentUser = {'id': 10, 'role': 'farmer'};
      addTearDown(state.dispose);
      expect(await state.analyzeSavedFarm(scope.farm(1)), isNotNull);
      expect(state.analysisPending, isTrue);
      expect(state.loading, isFalse);
      state.offlineWorkspace = true;
      api.failAnalysis = false;
      expect(await state.analyzeSavedFarm(scope.farm(1)), isNull);
      expect(state.offlineWorkspace, isFalse);
      expect(state.analysisError, isNull);
      expect(state.analysisPending, isFalse);
      expect(state.result?['farm_id'], 1);
    },
  );

  test(
    'missing model inputs remain a failed analysis with a specific farmer message',
    () async {
      final api = RecoveryFixtureApi()
        ..failureMessage =
            'Required climate input unavailable or incompatible unit/time period: humidity.';
      final state = AnalysisState(api: api)
        ..currentUser = {'id': 10, 'role': 'farmer'};
      addTearDown(state.dispose);
      final error = await state.analyzeSavedFarm(scope.farm(1));
      expect(
        error,
        'Weather or land readings are unavailable. Try again later.',
      );
      expect(state.analysisPending, isFalse);
      expect(state.result, isNull);
    },
  );

  testWidgets(
    'farmer disclosures isolate Boolean expansion from saved double scroll state',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AnalysisState(api: scope.ScopeApi())
        ..currentUser = {'id': 10, 'role': 'farmer'};
      addTearDown(state.dispose);
      final bucket = PageStorageBucket();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageStorage(
              bucket: bucket,
              child: SingleChildScrollView(
                key: const PageStorageKey<String>('mobile-analysis-scroll'),
                child: Builder(
                  builder: (context) {
                    bucket.writeState(context, 144.0);
                    return FarmerAnalysisContent(
                      state: state,
                      record: farmerRecord(),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final title in ['Farm map', 'Full analysis details']) {
        final disclosure = find.text(title);
        await tester.ensureVisible(disclosure);
        await tester.tap(disclosure);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(find.text('1. Rice'), findsOneWidget);
      expect(find.text('4. Corn'), findsOneWidget);
    },
  );

  testWidgets(
    'Analysis has a functional back button and no Switch analysis control',
    (tester) async {
      final state = AnalysisState(api: scope.ScopeApi())
        ..currentUser = {'id': 10, 'role': 'farmer'}
        ..result = farmerRecord();
      state.historyRecords.addAll([farmerRecord(), scope.analysis(8, 1)]);
      addTearDown(state.dispose);
      var backs = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileAnalysisPage(state: state, goFarms: () => backs++),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Switch analysis'), findsNothing);
      await tester.tap(find.byTooltip('Back'));
      expect(backs, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Farm Details shows the boundary without duplicate coverage paragraphs',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AnalysisState(api: scope.ScopeApi())
        ..currentUser = {'id': 10, 'role': 'farmer'};
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: FarmDetailsPage(state: state, farm: scope.farm(1)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(CoverageExplorer), findsNothing);
      expect(find.byType(AnalysisCoverageCard), findsNothing);
      expect(find.text('Analyze This Farm'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final option in [
    GoogleAccountConflictChoice.password,
    GoogleAccountConflictChoice.anotherAccount,
  ]) {
    testWidgets('Google account conflict offers the explicit $option action', (
      tester,
    ) async {
      GoogleAccountConflictChoice? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  selected = await showDialog<GoogleAccountConflictChoice>(
                    context: context,
                    builder: (_) => const GoogleAccountConflictDialog(
                      email: 'synthetic@example.com',
                    ),
                  );
                },
                child: const Text('Open account options'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open account options'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(
          option == GoogleAccountConflictChoice.password
              ? 'Use my password'
              : 'Choose another Google account',
        ),
      );
      await tester.pumpAndSettle();
      expect(selected, option);
      expect(tester.takeException(), isNull);
    });
  }
}
