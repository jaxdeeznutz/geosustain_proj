import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';

class _ResultState extends AnalysisState {
  int submissions = 0;
  Completer<bool>? submission;

  @override
  Future<void> refreshHistoryData() async {}

  @override
  Future<bool> submitAnalysisRecord(Map<String, dynamic> record) async {
    submissions++;
    return submission?.future ?? true;
  }
}

void main() {
  test(
    'history is newest first without merging repeated analyses of one farm',
    () {
      final records = newestAnalysisRecords([
        {'session_id': 1, 'farm_id': 9, 'analyzed_at': '2026-08-01T12:00:00Z'},
        {'session_id': 3, 'farm_id': 9, 'analyzed_at': '2026-09-01T12:00:00Z'},
        {'session_id': 2, 'farm_id': 9, 'analyzed_at': '2026-08-10T12:00:00Z'},
      ]);
      expect(records.map((r) => r['session_id']), [3, 2, 1]);
    },
  );

  test('completed processing never implies an approved analyst review', () {
    expect(analysisProcessingLabel({'session_id': 1}), 'Completed');
    expect(analysisReviewLabel('draft'), 'Not Submitted');
    expect(analysisReviewLabel('pending'), 'Pending Review');
    expect(analysisReviewLabel('verified'), 'Approved');
    expect(analysisReviewLabel('unsupported'), 'Review status unavailable');
    expect(analysisProcessingLabel({}), 'Status unavailable');
  });

  test('missing, invalid and zero values remain distinct', () {
    expect(analysisNumber('NaN'), isNull);
    expect(analysisNumber('Infinity'), isNull);
    expect(analysisNumber(null), isNull);
    expect(analysisNumber(0), 0);
    expect(analysisAreaText({}), 'Area unavailable');
    expect(analysisAreaText({'area_m2': 10000}), '1.000 ha');
  });

  testWidgets(
    'indicator card has no invented readings or progress percentages',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnalysisIndicatorsCard(
                record: {'soil_ph': 6.4, 'ndvi': 0},
              ),
            ),
          ),
        ),
      );
      expect(find.text('6.4'), findsOneWidget);
      expect(find.text('0.000'), findsOneWidget);
      expect(find.text('Temperature'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'crop score bars and reasons come from supplied analysis outputs',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnalysisCropsCard(
                record: {
                  'top_crop_recommendations': [
                    {
                      'crop': 'Cacao',
                      'compatibility_pct': 82.4,
                      'reason': 'Recorded soil pH matches the crop profile.',
                    },
                    {'crop': 'Corn', 'compatibility_pct': 64.2},
                  ],
                },
              ),
            ),
          ),
        ),
      );
      expect(find.text('1. Cacao'), findsOneWidget);
      expect(
        find.text('Recorded soil pH matches the crop profile.'),
        findsOneWidget,
      );
      expect(
        find.text('No crop-specific explanation was returned.'),
        findsOneWidget,
      );
      final bars = tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .toList();
      expect(bars[0].value, closeTo(.824, .0001));
      expect(bars[1].value, closeTo(.642, .0001));
    },
  );

  testWidgets('history opens the exact analysis and displays actual feedback', (
    tester,
  ) async {
    final state = _ResultState();
    addTearDown(state.dispose);
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    state.historyRecords.addAll([
      {
        'session_id': 1,
        'farm_id': 4,
        'owner_display_name': 'Fixture Farmer',
        'farm_name': 'Older analysis',
        'analyzed_at': '2026-08-01T12:00:00Z',
        'area_hectares': 1.2,
        'verification_status': 'verified',
      },
      {
        'session_id': 2,
        'farm_id': 4,
        'owner_display_name': 'Fixture Farmer',
        'farm_name': 'Latest analysis',
        'analyzed_at': '2026-09-01T12:00:00Z',
        'area_hectares': 1.2,
        'verification_status': 'rejected',
        'planner_notes': 'Check the eastern boundary.',
        'verified_at': '2026-09-03T12:00:00Z',
      },
    ]);
    Map<String, dynamic>? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryPage(
            api: state.api,
            state: state,
            onOpenAnalysis: (record) {
              selected = record;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Latest analysis')).dy,
      lessThan(tester.getTopLeft(find.text('Older analysis')).dy),
    );
    expect(find.text('Owner: Fixture Farmer'), findsNWidgets(2));
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    await tester.tap(find.text('Latest analysis'));
    await tester.pumpAndSettle();
    expect(selected?['session_id'], 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'review submission prevents double taps while request is pending',
    (tester) async {
      final state = _ResultState()..currentUser = {'role': 'farmer'};
      state.submission = Completer<bool>();
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnalysisReviewCard(
              state: state,
              record: const {
                'session_id': 7,
                'verification_status': 'draft',
                'analysis_status': 'completed',
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Submit for Analyst Review'));
      await tester.pump();
      expect(state.submissions, 1);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      state.submission!.complete(true);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('pending and approved analyses cannot be submitted again', (
    tester,
  ) async {
    final state = _ResultState()..currentUser = {'role': 'farmer'};
    addTearDown(state.dispose);
    for (final status in ['pending', 'verified']) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnalysisReviewCard(
              state: state,
              record: {'session_id': 7, 'verification_status': status},
            ),
          ),
        ),
      );
      expect(find.byType(FilledButton), findsNothing);
    }
  });
}
