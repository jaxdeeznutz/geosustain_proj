import 'dart:async';
import 'dart:io';
import 'qa_support.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const boundary = [
  {'lat': 7.3, 'lng': 125.6},
  {'lat': 7.3, 'lng': 125.600045},
  {'lat': 7.300036, 'lng': 125.600045},
  {'lat': 7.300036, 'lng': 125.6},
];
Map<String, dynamic> farm(int id) => {
  'id': id,
  'farmer_id': 10,
  'owner_display_name': 'Test Farmer',
  'farm_name': 'Farm $id',
  'location_name': 'New Visayas, Panabo',
  'polygon': boundary,
  'area_hectares': .002,
  'mapping_method': 'gps_walk',
};
Map<String, dynamic> analysis(int id, int? farmId) => {
  'session_id': id,
  'farm_id': farmId,
  'owner_id': 10,
  'owner_display_name': 'Test Farmer',
  'farm_name': farmId == null ? null : 'Farm $farmId',
  'analysis_status': 'completed',
  'verification_status': 'draft',
  'analyzed_at': '2026-10-06T12:00:00Z',
  'place_name': 'New Visayas, Panabo',
  'area_hectares': .002,
  'selected_polygon': boundary,
};

class ScopeApi extends ApiService {
  List<dynamic> rows = [];
  Completer<List<dynamic>>? history;
  Completer<Map<String, dynamic>>? detail, calculation;
  bool failHistory = false;
  int posts = 0;
  @override
  Future<Map<String, dynamic>> getMe() async => {
    'id': 10,
    'username': 'Test Farmer',
    'role': 'farmer',
  };
  @override
  Future<List<dynamic>> getHistory() async {
    if (failHistory) throw const ApiException(503, 'History unavailable');
    return history?.future ?? rows;
  }

  @override
  Future<List<dynamic>> getFarmHistory(int farmId) async {
    if (failHistory) throw const ApiException(503, 'History unavailable');
    return rows.where((r) => r['farm_id'] == farmId).toList();
  }

  @override
  Future<Map<String, dynamic>> getFarm(int id) async => farm(id);
  @override
  Future<Map<String, dynamic>> getAnalysis(int id) async =>
      detail?.future ?? analysis(id, 1);
  @override
  Future<List<Map<String, dynamic>>> getFarms({
    bool includeArchived = false,
  }) async => [farm(1), farm(2)];
  @override
  Future<List<dynamic>> getSavedAnalyses() async => [];
  @override
  Future<List<dynamic>> getReports() async => [];
  @override
  Future<Map<String, dynamic>> getCounts() async => {};
  @override
  Future<Map<String, dynamic>> analyzePolygon(
    List<Map<String, double>> polygon, {
    String? placeName,
    int? intendedPlantingMonth,
    int? farmId,
  }) async {
    posts++;
    expect(farmId, 1);
    expect(polygon.first, boundary.first);
    return calculation?.future ?? analysis(9, 1);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final previous = HttpOverrides.current;
    HttpOverrides.global = QaHttpOverrides();
    addTearDown(() => HttpOverrides.global = previous);
  });
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'token': 'test-session',
      'account_id': '10',
    }),
  );
  AnalysisState stateWith(ScopeApi api) =>
      AnalysisState(api: api)..currentUser = {'id': 10, 'role': 'farmer'};

  test(
    'profile load preserves history without globally selecting a result',
    () async {
      final api = ScopeApi()..rows = [analysis(8, 2), analysis(7, null)];
      final state = stateWith(api);
      addTearDown(state.dispose);
      await state.loadUserData();
      expect(state.result, isNull);
      expect(state.historyRecords.length, 2);
      expect(analysisRecordName(state.historyRecords.last), 'Unnamed area');
    },
  );

  test('late history after logout cannot populate the next account', () async {
    final api = ScopeApi()..history = Completer<List<dynamic>>();
    final state = stateWith(api);
    addTearDown(state.dispose);
    final request = state.refreshHistoryData();
    state.clearUserData();
    state.currentUser = {'id': 20, 'role': 'farmer'};
    api.history!.complete([analysis(8, 1)]);
    await request;
    expect(state.historyRecords, isEmpty);
    expect(state.result, isNull);
  });

  test('late selection cannot replace a newly focused farm', () async {
    final api = ScopeApi()..detail = Completer<Map<String, dynamic>>();
    final state = stateWith(api);
    addTearDown(state.dispose);
    state.focusFarm(farm(1));
    final selected = state.selectAnalysis(analysis(9, 1));
    state.focusFarm(farm(2));
    api.detail!.complete(analysis(9, 1));
    expect(await selected, isNotNull);
    expect(state.selectedFarmId, 2);
    expect(state.result, isNull);
  });

  test(
    'analysis double tap is blocked and failure keeps farm without result',
    () async {
      final api = ScopeApi()..calculation = Completer<Map<String, dynamic>>();
      final state = stateWith(api);
      addTearDown(state.dispose);
      state.result = analysis(8, 2);
      final request = state.analyzeSavedFarm(farm(1));
      expect(
        await state.analyzeSavedFarm(farm(1)),
        contains('already running'),
      );
      expect(api.posts, 1);
      api.calculation!.completeError(
        http.ClientException('Failed to fetch, uri=https://private.test'),
      );
      final error = await request;
      expect(error, isNot(contains('https://')));
      expect(state.result, isNull);
      expect(state.historyRecords, isEmpty);
      expect(state.selectedFarmId, 1);
      expect(state.loading, isFalse);
    },
  );

  test('successful saved result keeps actual identity', () async {
    final api = ScopeApi()..rows = [analysis(9, 1)];
    final state = stateWith(api);
    addTearDown(state.dispose);
    expect(await state.analyzeSavedFarm(farm(1)), isNull);
    expect(state.result!['farm_id'], 1);
    expect(state.result!['owner_id'], 10);
    expect(state.historyRecords.single['session_id'], 9);
  });

  test(
    'lost POST response recovers saved analysis with no duplicate POST',
    () async {
      int gets = 0, posts = 0;
      final api = ApiService(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            posts++;
            throw http.ClientException('connection closed');
          }
          gets++;
          return http.Response(
            jsonEncode(
              gets == 1
                  ? {'status': 'not_found'}
                  : {'status': 'completed', 'analysis': analysis(9, 1)},
            ),
            200,
          );
        }),
      );
      addTearDown(api.close);
      final result = await api.analyzePolygon(boundary, farmId: 1);
      expect(result['session_id'], 9);
      expect(posts, 1);
      expect(gets, 2);
    },
  );

  test(
    'retry key survives switching farms and restarting the client',
    () async {
      final keys = <int, List<String>>{};
      ApiService service() => ApiService(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response('{"status":"not_found"}', 200);
          }
          final id = jsonDecode(request.body)['farm_id'] as int;
          keys
              .putIfAbsent(id, () => [])
              .add(request.headers['Idempotency-Key']!);
          return http.Response('{"detail":"temporarily unavailable"}', 503);
        }),
      );
      for (final id in [1, 2, 1]) {
        final api = service();
        await expectLater(
          api.analyzePolygon(boundary, farmId: id),
          throwsA(isA<ApiException>()),
        );
        api.close();
      }
      expect(keys[1]!.first, keys[1]!.last);
      expect(keys[1]!.first, isNot(keys[2]!.first));
    },
  );

  test('wrong-farm response and malformed status are never accepted', () async {
    final api = ApiService(
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({'status': 'completed', 'analysis': analysis(9, 2)}),
          200,
        ),
      ),
    );
    addTearDown(api.close);
    await expectLater(
      api.analyzePolygon(boundary, farmId: 1),
      throwsFormatException,
    );
  });

  for (final width in [402.0, 360.0]) {
    testWidgets('unanalyzed farm hides old results at $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ScopeApi()..rows = [analysis(9, 2)];
      final state = stateWith(api);
      addTearDown(state.dispose);
      state.historyRecords.add(analysis(9, 2));
      state.result = analysis(9, 2);
      state.focusFarm(farm(1));
      await tester.pumpWidget(
        GeoSustainApp(
          home: FarmDetailsPage(state: state, farm: farm(1)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not analyzed yet'), findsOneWidget);
      expect(find.text('Previous analyses'), findsNothing);
      expect(find.text('Latest results'), findsNothing);
      expect(find.text('Farm 2'), findsNothing);
      expect(find.text('Analyze This Farm').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('failed farm history fetch does not imply no analysis', (
    tester,
  ) async {
    final api = ScopeApi()..failHistory = true;
    final state = stateWith(api);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      GeoSustainApp(
        home: FarmDetailsPage(state: state, farm: farm(1)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Not analyzed yet'), findsNothing);
    expect(find.textContaining('unavailable'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('empty account has honest Analysis and History empty states', (
    tester,
  ) async {
    final state = stateWith(ScopeApi());
    addTearDown(state.dispose);
    await state.refreshHistoryData();
    await tester.pumpWidget(
      GeoSustainApp(
        home: Scaffold(
          body: MobileAnalysisPage(state: state, goFarms: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No analyses yet'), findsOneWidget);
    expect(find.text('Analyze a farm to see its results.'), findsOneWidget);
    await tester.pumpWidget(
      GeoSustainApp(
        home: Scaffold(
          body: HistoryPage(state: state, api: state.api),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No analyses yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
