import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';

Map<String, dynamic> formalRecord() => {
  'session_id': 42,
  'farm_id': 7,
  'boundary_version': 2,
  'verification_status': 'draft',
  'analysis_status': 'completed',
  'selected_polygon': [
    {'lat': 7.29, 'lng': 125.62},
    {'lat': 7.29, 'lng': 125.621},
    {'lat': 7.291, 'lng': 125.621},
  ],
};

void main() {
  test('only a saved boundary result is a formal review candidate', () {
    expect(formalReviewCandidate(formalRecord()), isTrue);
    for (final field in ['farm_id', 'boundary_version', 'selected_polygon']) {
      expect(formalReviewCandidate(formalRecord()..remove(field)), isFalse);
    }
    expect(
      formalReviewCandidate(
        formalRecord()..['formal_submission_eligible'] = false,
      ),
      isFalse,
    );
  });

  test(
    'submission state blocks an inspection before any API request',
    () async {
      final state = AnalysisState()..currentUser = {'id': 10, 'role': 'farmer'};
      addTearDown(state.dispose);
      await expectLater(
        state.submitAnalysisRecord({'session_id': 42}),
        throwsStateError,
      );
    },
  );

  testWidgets('inspection has a clear notice and no formal submit action', (
    tester,
  ) async {
    final state = AnalysisState()..currentUser = {'id': 10, 'role': 'farmer'};
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnalysisReviewCard(
            state: state,
            record: {
              'session_id': 42,
              'verification_status': 'draft',
              'analysis_status': 'completed',
              'formal_submission_eligible': false,
            },
          ),
        ),
      ),
    );
    expect(find.text('Submit for Analyst Review'), findsNothing);
    expect(find.textContaining('Preliminary inspection only.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
