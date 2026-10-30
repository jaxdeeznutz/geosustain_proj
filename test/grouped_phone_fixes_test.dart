import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'analysis_scope_test.dart' as fixture;
import 'qa_support.dart';

double ratio(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
}

class _SubmitApi extends fixture.ScopeApi {
  String status = 'pending';
  int returnedId = 12;
  @override
  Future<Map<String, dynamic>> submitAnalysisToPlanner(int id) async => {
    'submission': {'id': returnedId, 'verification_status': status},
  };
}

void main() {
  setUp(() {
    HttpOverrides.global = QaHttpOverrides();
  });
  tearDown(() {
    HttpOverrides.global = null;
    appThemeMode.value = ThemeMode.light;
  });
  Map<String, dynamic> record(int id, {bool unavailable = false}) => {
    'session_id': id,
    'cagro_soil': {
      'status': unavailable ? 'unavailable' : 'matched',
      'message': 'Historical contrast probe',
      'observations': [
        for (var i = 0; i < 4; i++)
          {
            'id': i,
            'source_row': i,
            'location_name': 'Row $i',
            'source': 'Rendering fixture',
          },
      ],
    },
  };
  testWidgets(
    'CAGRO scroll remount and unavailable expansion use independent storage',
    (tester) async {
      final bucket = PageStorageBucket();
      Widget page() => GeoSustainApp(
        home: Scaffold(
          body: PageStorage(
            bucket: bucket,
            child: ListView(
              key: const PageStorageKey('mobile-analysis-scroll'),
              children: [
                const SizedBox(height: 600),
                CagroSoilObservationsCard(record: record(1)),
                CagroSoilObservationsCard(record: record(2, unavailable: true)),
                const SizedBox(height: 900),
              ],
            ),
          ),
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -650));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      final keys = tester
          .widgetList<ExpansionTile>(find.byType(ExpansionTile))
          .map((w) => w.key)
          .toList();
      expect(keys.toSet().length, keys.length);
      expect(keys.every((k) => k is PageStorageKey), isTrue);
    },
  );
  for (final dark in [false, true]) {
    testWidgets('CAGRO actual painted surface has readable text dark=$dark', (
      tester,
    ) async {
      appThemeMode.value = dark ? ThemeMode.dark : ThemeMode.light;
      await tester.pumpWidget(
        GeoSustainApp(
          home: Scaffold(body: CagroSoilObservationsCard(record: record(1))),
        ),
      );
      await tester.pumpAndSettle();
      final text = find.text('Historical contrast probe');
      final foreground =
          (tester.renderObject<RenderParagraph>(text).text as TextSpan)
              .style!
              .color!;
      final card = find
          .ancestor(of: text, matching: find.byType(GeoResultCard))
          .first;
      final container = tester.widget<Container>(
        find.descendant(of: card, matching: find.byType(Container)).first,
      );
      expect(
        ratio(foreground, (container.decoration as BoxDecoration).color!),
        greaterThanOrEqualTo(4.5),
      );
    });
    testWidgets('auth labels and input are readable after logout dark=$dark', (
      tester,
    ) async {
      appThemeMode.value = dark ? ThemeMode.dark : ThemeMode.light;
      await tester.pumpWidget(const GeoSustainApp(home: LoginPage()));
      await tester.pumpAndSettle();
      final text = find.text('Email Address');
      final foreground =
          (tester.renderObject<RenderParagraph>(text).text as TextSpan)
              .style!
              .color!;
      final panel = tester.widget<Container>(
        find
            .ancestor(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        ratio(foreground, (panel.decoration as BoxDecoration).color!),
        greaterThanOrEqualTo(4.5),
      );
      final register =
          tester.widget<Text>(find.textContaining('First time?')).textSpan!
              as TextSpan;
      final link = register.children!.last as TextSpan;
      expect(
        ratio(link.style!.color!, (panel.decoration as BoxDecoration).color!),
        greaterThanOrEqualTo(4.5),
      );
    });
  }
  testWidgets('farm search explains no match and clear restores rows', (
    tester,
  ) async {
    final state = AnalysisState(api: fixture.ScopeApi())
      ..currentUser = {'id': 10, 'role': 'farmer'};
    addTearDown(state.dispose);
    await tester.pumpWidget(GeoSustainApp(home: MyFarmsPage(state: state)));
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextField, 'Search farms');
    await revealInList(
      tester,
      field,
      list: find
          .descendant(
            of: find.byType(MyFarmsPage),
            matching: find.byType(ListView),
          )
          .first,
    );
    await tester.enterText(field, 'not-found-xyz');
    await tester.pumpAndSettle();
    expect(find.textContaining('No matching farms'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Farm 1'), findsOneWidget);
    expect(find.textContaining('No matching farms'), findsNothing);
  });
  for (final target in ['name', 'thumbnail']) {
    testWidgets('unanalyzed farm $target opens exact details', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AnalysisState(api: fixture.ScopeApi())
        ..currentUser = {'id': 10, 'role': 'farmer'};
      addTearDown(state.dispose);
      await tester.pumpWidget(GeoSustainApp(home: MyFarmsPage(state: state)));
      await tester.pumpAndSettle();
      final name = find.text('Farm 1');
      await revealInList(
        tester,
        name,
        list: find
            .descendant(
              of: find.byType(MyFarmsPage),
              matching: find.byType(ListView),
            )
            .first,
      );
      await tester.scrollUntilVisible(
        name,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      final card = find.ancestor(of: name, matching: find.byType(GeoFarmCard));
      final finder = target == 'name'
          ? name
          : find.descendant(
              of: card,
              matching: find.byKey(const ValueKey('farm-thumbnail-1')),
            );
      await Scrollable.ensureVisible(tester.element(finder), alignment: .4);
      await tester.pumpAndSettle();
      expect(finder.hitTestable(), findsOneWidget);
      await tester.tap(finder.hitTestable());
      await tester.pumpAndSettle();
      expect(
        tester.widget<FarmDetailsPage>(find.byType(FarmDetailsPage)).farm['id'],
        1,
      );
    });
  }
  test(
    'wrong credentials and authenticated expiry have different messages',
    () {
      expect(
        friendlyErrorMessage(
          const ApiException(401, 'Invalid email or password'),
        ),
        contains('password'),
      );
      expect(
        friendlyErrorMessage(const ApiException(401, 'Session expired')),
        contains('session'),
      );
    },
  );
  test(
    'photo data URL follows PNG and JPEG signatures; invalid bytes rejected',
    () {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGN4+e7lfwAJRAPAWkyUCAAAAABJRU5ErkJggg==',
      );
      expect(profilePhotoDataUrl(png), startsWith('data:image/png;base64,'));
      expect(
        profilePhotoDataUrl(Uint8List.fromList([255, 216, 255, 0])),
        startsWith('data:image/jpeg;base64,'),
      );
      expect(
        () => profilePhotoDataUrl(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'registration uses inline errors, strength feedback and no role banner',
    (tester) async {
      await tester.pumpWidget(const GeoSustainApp(home: RegisterPage()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Create a Farmer account.'), findsNothing);
      final button = find.widgetWithText(FilledButton, 'Register');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byType(TextField).first)
            .decoration!
            .errorText,
        contains('Username'),
      );
      final password = find.byType(TextField).at(2);
      await tester.ensureVisible(password);
      await tester.enterText(password, 'Abc123!Longer');
      await tester.pumpAndSettle();
      expect(find.text('Password strength: Strong'), findsOneWidget);
      expect(tester.widget<TextField>(password).decoration!.errorText, isNull);
      expect(tester.widget<TextField>(password).decoration!.errorMaxLines, 3);
    },
  );
  testWidgets(
    'confirmed partial submission updates badge and removes submit action',
    (tester) async {
      final api = _SubmitApi();
      final state = AnalysisState(api: api)
        ..currentUser = {'id': 10, 'role': 'farmer'};
      final record = fixture.analysis(12, 1)
        ..addAll({
          'farm_id': 7,
          'boundary_version': 1,
          'selected_polygon': [
            {'lat': 7.29, 'lng': 125.62},
            {'lat': 7.29, 'lng': 125.621},
            {'lat': 7.291, 'lng': 125.621},
          ],
        })
        ..['is_crop_recommended'] = false;
      addTearDown(state.dispose);
      await tester.pumpWidget(
        GeoSustainApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnalysisReviewCard(state: state, record: record),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit for Analyst Review'));
      await tester.pumpAndSettle();
      expect(record['verification_status'], 'pending');
      expect(record['is_crop_recommended'], false);
      expect(find.text('Submit for Analyst Review'), findsNothing);
      expect(find.textContaining('awaiting an analyst'), findsOneWidget);
    },
  );
  test(
    'submission rejects a response for another assessment before changing UI',
    () async {
      final state = AnalysisState(api: _SubmitApi()..returnedId = 13)
        ..currentUser = {'id': 10, 'role': 'farmer'};
      addTearDown(state.dispose);
      final record = fixture.analysis(12, 1)
        ..addAll({
          'farm_id': 7,
          'boundary_version': 1,
          'selected_polygon': [
            {'lat': 7.29, 'lng': 125.62},
            {'lat': 7.29, 'lng': 125.621},
            {'lat': 7.291, 'lng': 125.621},
          ],
        });
      await expectLater(
        state.submitAnalysisRecord(record),
        throwsFormatException,
      );
      expect(record['verification_status'], 'draft');
    },
  );
  test(
    'submission retry preserves an existing analyst decision in the UI',
    () async {
      final state = AnalysisState(api: _SubmitApi()..status = 'verified')
        ..currentUser = {'id': 10, 'role': 'farmer'};
      addTearDown(state.dispose);
      final record = fixture.analysis(12, 1)
        ..addAll({
          'farm_id': 7,
          'boundary_version': 1,
          'selected_polygon': [
            {'lat': 7.29, 'lng': 125.62},
            {'lat': 7.29, 'lng': 125.621},
            {'lat': 7.291, 'lng': 125.621},
          ],
        });
      expect(await state.submitAnalysisRecord(record), isTrue);
      expect(record['verification_status'], 'verified');
    },
  );
}
