import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'qa_support.dart';

class _FarmerState extends AnalysisState {
  int submissions = 0;
  final submission = Completer<bool>();
  @override
  Future<bool> submitAnalysisRecord(Map<String, dynamic> record) {
    submissions++;
    return submission.future;
  }
}

Map<String, dynamic> _record() => {
  'session_id': 7,
  'farm_id': 3,
  'farm_name': 'Test farm',
  'boundary_version': 1,
  'analysis_status': 'completed',
  'verification_status': 'draft',
  'area_hectares': 1.1,
  'recommendation_basis': 'model_probability',
  'is_crop_recommended': true,
  'top_crop_recommendations': [
    {'crop': 'Rice', 'compatibility_pct': 0.0},
  ],
  'selected_polygon': [
    {'lat': 7.29, 'lng': 125.62},
    {'lat': 7.291, 'lng': 125.62},
    {'lat': 7.291, 'lng': 125.621},
  ],
};

Map<String, dynamic> _fixture(String name) => Map<String, dynamic>.from(
  jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map,
);

Future<void> _pump(
  WidgetTester tester,
  AnalysisState state,
  Map<String, dynamic> record, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool dark = false,
  bool full = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        fontFamily: 'Roboto',
        colorSchemeSeed: green,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          key: const ValueKey('farmer-test-scroll'),
          padding: const EdgeInsets.all(16),
          child: full
              ? ReferenceAnalysisContent(state: state, record: record)
              : MobileAnalysisResult(state: state, record: record),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _show(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).first);
  await tester.tap(find.text(label).first);
  await tester.pumpAndSettle();
}

int _visibleWords() => find
    .byType(Text)
    .evaluate()
    .map((element) {
      final text = element.widget as Text;
      return text.data ?? text.textSpan?.toPlainText() ?? '';
    })
    .join(' ')
    .split(RegExp(r'\s+'))
    .where((s) => s.isNotEmpty)
    .length;

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
    SharedPreferences.setMockInitialValues({});
    HttpOverrides.global = QaHttpOverrides();
  });
  tearDown(() => HttpOverrides.global = null);

  for (final width in [360.0, 390.0, 480.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('farmer summary and crop legend fit $width at scale $scale', (
        tester,
      ) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = _FarmerState()..currentUser = {'id': 1, 'role': 'farmer'};
        final record = _record();
        final before = jsonEncode(record);
        await _pump(
          tester,
          state,
          record,
          size: Size(width, 900),
          scale: scale,
        );
        expect(find.text('Model score: 0.0%'), findsOneWidget);
        expect(find.text('Explainable AI'), findsNothing);
        expect(find.text('Review color guide'), findsOneWidget);
        expect(find.text('Send for review'), findsOneWidget);
        await _show(tester, '1. Rice');
        expect(find.text('Condition color guide'), findsOneWidget);
        expect(find.text('Gray: Not assessed'), findsOneWidget);
        expect(find.text('Green: Fits range'), findsOneWidget);
        expect(find.text('Full explanation and sources'), findsOneWidget);
        expect(jsonEncode(record), before);
        expect(state.submissions, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        state.dispose();
      });
    }
  }

  testWidgets(
    'summary cuts default reading while retaining the full saved explanation',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = _FarmerState()..currentUser = {'role': 'farmer'};
      final record = _fixture('local_analysis');
      final before = jsonEncode(record);
      await _pump(tester, state, record);
      final shortCount = _visibleWords();
      expect(find.text('Explainable AI'), findsNothing);
      await _show(tester, 'Full analysis details');
      expect(find.text('Explainable AI'), findsOneWidget);
      expect(find.text('Key Factors'), findsNothing);
      expect(find.text('Recommended crops'), findsNothing);
      expect(find.text('Analyzed Farm Location'), findsNothing);
      expect(find.text('Top model recommendation'), findsNothing);
      expect(find.byType(AnalysisReviewCard), findsOneWidget);
      expect(find.text('Export analysis report'), findsNothing);
      expect(find.text('Save report (PDF)'), findsOneWidget);
      await _pump(tester, state, record, full: true);
      expect(shortCount, lessThan(_visibleWords() * .7));
      expect(jsonEncode(record), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );

  testWidgets('preliminary and blocked results never promote stale crops', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _FarmerState()..currentUser = {'role': 'farmer'};
    final preliminary = {
      ..._record(),
      'analysis_mode': 'preliminary_environmental',
    };
    await _pump(tester, state, preliminary);
    expect(find.text('More data needed'), findsOneWidget);
    expect(
      find.text('Land check only. Soil data is incomplete.'),
      findsOneWidget,
    );
    expect(find.text('1. Rice'), findsNothing);
    expect(find.text('Model score: 0.0%'), findsNothing);
    final blocked = {
      ..._record(),
      'is_crop_recommended': false,
      'land_cover': {'status': 'water'},
    };
    await _pump(tester, state, blocked);
    expect(find.text('Water area detected'), findsOneWidget);
    expect(find.text('1. Rice'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets(
    'short review retains the guarded submission and original record',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = _FarmerState()..currentUser = {'role': 'farmer'};
      final record = _record();
      await _pump(tester, state, record);
      await tester.ensureVisible(find.text('Send for review'));
      await tester.tap(find.text('Send for review'));
      await tester.pump();
      expect(state.submissions, 1);
      final button = find.widgetWithText(FilledButton, 'Submitting…');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      state.submission.complete(true);
      await tester.pumpAndSettle();
      expect(state.submissions, 1);
      expect(record['session_id'], 7);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );

  testWidgets(
    'saved map color legend remains labelled with actual ranges and no-data meaning',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = _FarmerState()..currentUser = {'role': 'farmer'};
      final record = _fixture('spatial_analysis');
      final before = jsonEncode(record);
      await _pump(tester, state, record);
      await _show(tester, 'Farm map');
      expect(find.text('Map color guide'), findsOneWidget);
      expect(find.text('Gray: No usable reading'), findsOneWidget);
      expect(find.text('Green outline: Analyzed boundary'), findsOneWidget);
      expect(
        find.text(
          'Colors show the amount of the selected reading, not crop suitability.',
        ),
        findsOneWidget,
      );
      expect(jsonEncode(record), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );

  testWidgets(
    'live-map guide hides old reading colors after changing a boundary',
    (tester) async {
      final state = _FarmerState()..currentUser = {'role': 'farmer'};
      final record = _fixture('spatial_analysis');
      state.result = record;
      state.heatmapLayer = 'NDVI';
      final boundary = (record['selected_polygon'] as List)
          .map(
            (p) => LatLng(
              (p['lat'] as num).toDouble(),
              ((p['lng'] ?? p['lon']) as num).toDouble(),
            ),
          )
          .toList();
      state.polygonPoints
        ..clear()
        ..addAll(boundary);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FarmerLiveMapGuide(state: state)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Gray: No usable reading'), findsOneWidget);
      state.polygonPoints
        ..clear()
        ..addAll(boundary.map((p) => LatLng(p.latitude + .01, p.longitude)));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FarmerLiveMapGuide(
              key: const ValueKey('changed'),
              state: state,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Gray: No usable reading'), findsNothing);
      expect(find.text('Pin: Selected place'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );

  testWidgets(
    'farmer-specific summary leaves the analyst evidence interface intact',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = _FarmerState()..currentUser = {'role': 'analyst'};
      await _pump(tester, state, _fixture('local_analysis'));
      expect(find.byType(ReferenceAnalysisContent), findsOneWidget);
      expect(find.byType(FarmerAnalysisContent), findsNothing);
      expect(find.text('Key Factors'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );

  testWidgets('review labels stay readable in dark mode', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _FarmerState()..currentUser = {'role': 'farmer'};
    await _pump(
      tester,
      state,
      {..._record(), 'verification_status': 'verified'},
      dark: true,
      scale: 2,
    );
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Green: Reviewed'), findsOneWidget);
    expect(find.text('Send for review'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
