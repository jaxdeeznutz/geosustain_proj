import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:geosustain_clean_arranged/seasonal_context.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'qa_support.dart';

class SeasonalFixtureApi extends ApiService {
  final months = <int?>[];
  @override
  Future<String> reverseGeocodePlace(double lat, double lon) async => 'Fixture';
  @override
  Future<List<dynamic>> getHistory() async => [];
  @override
  Future<List<Map<String, dynamic>>> getFarms({
    bool includeArchived = false,
  }) async => [];
  @override
  Future<Map<String, dynamic>> analyzePolygon(
    List<Map<String, double>> polygon, {
    String? placeName,
    int? intendedPlantingMonth,
    int? farmId,
    int? boundaryVersion,
    bool independentAnalyst = false,
  }) async {
    expect(independentAnalyst, isFalse);
    months.add(intendedPlantingMonth);
    return {
      'session_id': months.length,
      'owner_id': 10,
      'analysis_status': 'completed',
      'intended_planting_month': intendedPlantingMonth,
    };
  }
}

Map<String, dynamic> savedSeasonalRecord() => {
  'intended_planting_month': 2,
  'seasonal_assessment': {
    'version': 'seasonal-context-v1',
    'selected_month_name': 'February',
    'captured_at': '2026-10-29T05:03:00Z',
    'summary': 'February historical context; not a forecast.',
    'calendar': {'reason': 'No reviewed local calendar.'},
    'monthly_climate': {
      'source_name': 'Fixture NASA POWER',
      'baseline_start_year': 2005,
      'baseline_end_year': 2024,
      'spatial_method': 'Representative point, not parcel average',
      'metrics': {
        'rainfall': {
          'value': 56.5,
          'unit': 'mm/month',
          'valid_observations': 20,
          'expected_observations': 20,
          'status': 'available',
        },
      },
    },
    'limitations': ['Annual and monthly totals are separate.'],
  },
};

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({'token': 'fixture-token'}),
  );

  testWidgets('seasonal details survive saved scroll offset and record switching', (
    tester,
  ) async {
    final bucket = PageStorageBucket();
    final february = savedSeasonalRecord()..['session_id'] = 1;
    final august = savedSeasonalRecord()..['session_id'] = 2;
    august['intended_planting_month'] = 8;
    final augustSnapshot =
        august['seasonal_assessment'] as Map<String, dynamic>;
    augustSnapshot['selected_month_name'] = 'August';
    augustSnapshot['captured_at'] = '2026-10-29T05:04:00Z';
    augustSnapshot['summary'] = 'August historical context; not a forecast.';
    final originalFebruary = jsonEncode(february);
    const listKey = PageStorageKey<String>('mobile-analysis-scroll');

    Widget page(
      Map<String, dynamic> record, {
      bool seedScrollOffset = false,
    }) => MaterialApp(
      home: Scaffold(
        body: PageStorage(
          bucket: bucket,
          child: ListView(
            key: listKey,
            children: [
              Builder(
                builder: (context) {
                  // Reproduce an existing list's saved numeric scroll offset before
                  // mounting details. An unkeyed ExpansionTile reads this as bool.
                  if (seedScrollOffset) bucket.writeState(context, 180.0);
                  return SeasonalContextCard(
                    key: ValueKey(record['session_id']),
                    record: record,
                  );
                },
              ),
              const SizedBox(height: 1600),
            ],
          ),
        ),
      ),
    );

    await tester.pumpWidget(page(february, seedScrollOffset: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Monthly climate evidence and limitations'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Source: Fixture NASA POWER'), findsOneWidget);
    final scroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(listKey),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    scroll.position.jumpTo(400);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());

    await tester.pumpWidget(page(august));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await revealInList(
      tester,
      find.text('Monthly climate evidence and limitations'),
      list: find.byKey(listKey),
    );
    expect(find.text('Selected planting month: August'), findsOneWidget);
    expect(find.textContaining('Source: Fixture NASA POWER'), findsNothing);
    await tester.tap(find.text('Monthly climate evidence and limitations'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Source: Fixture NASA POWER'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());

    await tester.pumpWidget(page(february));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await revealInList(
      tester,
      find.text('Monthly climate evidence and limitations'),
      list: find.byKey(listKey),
    );
    expect(find.text('Selected planting month: February'), findsOneWidget);
    expect(find.textContaining('Source: Fixture NASA POWER'), findsOneWidget);
    expect(jsonEncode(february), originalFebruary);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'month picker updates selection while saved evidence stays unchanged',
    (tester) async {
      final state = AnalysisState()..setIntendedPlantingMonth(1);
      addTearDown(state.dispose);
      final record = savedSeasonalRecord();
      final before = jsonEncode(record);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PlantingMonthPicker(state: state),
                SeasonalContextCard(record: record),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('June').last);
      await tester.pumpAndSettle();
      expect(state.intendedPlantingMonth, 6);
      expect(find.text('Selected planting month: February'), findsOneWidget);
      expect(jsonEncode(record), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'API request contains selected month and returns saved snapshot unchanged',
    () async {
      final requests = <Map<String, dynamic>>[];
      final api = ApiService(
        client: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path.startsWith('/api/mobile/analysis-requests/')) {
            return http.Response(
              jsonEncode({'status': 'not_found'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          expect(request.method, 'POST');
          expect(request.url.path, '/api/mobile/analysis');
          requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              ...savedSeasonalRecord(),
              'session_id': 42,
              'farm_id': 1,
              'analysis_status': 'completed',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(api.close);
      final result = await api.analyzePolygon(
        [
          {'lat': 7.29, 'lng': 125.62},
          {'lat': 7.29, 'lng': 125.621},
          {'lat': 7.291, 'lng': 125.621},
        ],
        farmId: 1,
        boundaryVersion: 1,
        intendedPlantingMonth: 2,
      );
      expect(requests.single['intended_planting_month'], 2);
      expect(
        result['seasonal_assessment'],
        savedSeasonalRecord()['seasonal_assessment'],
      );
    },
  );

  test(
    'changing month permits a new polygon analysis during duplicate cooldown',
    () async {
      final api = SeasonalFixtureApi();
      final state = AnalysisState(api: api)
        ..currentUser = {'id': 10, 'role': 'farmer'};
      addTearDown(state.dispose);
      state.polygonPoints.addAll([
        const LatLng(7.29, 125.62),
        const LatLng(7.29, 125.621),
        const LatLng(7.291, 125.621),
      ]);
      state.setIntendedPlantingMonth(2);
      expect(await state.analyzePolygon(), isNull);
      expect(await state.analyzePolygon(), contains('already analyzed'));
      state.setIntendedPlantingMonth(8);
      expect(await state.analyzePolygon(), isNull);
      expect(api.months, [2, 8]);
      expect(state.result?['intended_planting_month'], 8);
    },
  );

  test(
    'shared report text includes saved units/counts and explicit missing evidence',
    () {
      final record = savedSeasonalRecord();
      final lines = seasonalAssessmentLines(record);
      expect(lines.join('\n'), contains('56.5 mm/month; 20/20 valid years'));
      expect(
        lines.join('\n'),
        contains('Historical selected-month mean temperature: Unavailable'),
      );
      expect(lines.join('\n'), contains('No reviewed local calendar.'));
      expect(cagroAnalysisReportLines(record), containsAllInOrder(lines));
      expect(
        seasonalAssessmentLines({}),
        contains('Seasonal context was not recorded for this older analysis.'),
      );
    },
  );
}
