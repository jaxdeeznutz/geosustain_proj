import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:geosustain_clean_arranged/controlled_references.dart';
import 'package:geosustain_clean_arranged/local_explanation.dart';
import 'package:geosustain_clean_arranged/seasonal_context.dart';
import 'package:geosustain_clean_arranged/spatial_context.dart';
import 'package:geosustain_clean_arranged/web/operator_report.dart';
import 'qa_support.dart';

Map<String, dynamic> fixture(String name) => Map<String, dynamic>.from(
  jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map,
);

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Finder choice(String label) => find.byWidgetPredicate(
  (w) =>
      w is DropdownButtonFormField<String> && w.decoration.labelText == label,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'saved configuration consumers retain criteria, calendar, source and local explanation parity',
    () {
      final record = fixture('controlled_analysis');
      expect(savedControlledRecords(record).length, 6);
      expect(verifiedLocalExplanation(record), isNotEmpty);
      expect(
        controlledReferenceLines(record).join('\n'),
        contains('Software test only'),
      );
      expect(
        controlledReferenceLines(record).join('\n'),
        contains('Parcel sample limit: 5'),
      );
      expect(
        seasonalAssessmentLines(record).join('\n'),
        contains('Rice: selected month listed'),
      );
      final ndvi = spatialLayers(record).firstWhere((v) => v['id'] == 'ndvi');
      expect(
        spatialLayerLines(ndvi).join('\n'),
        contains('Reviewed source reference:'),
      );
      expect(controlledReferenceLines({}), isEmpty);
    },
  );
  for (final width in [360.0, 1280.0]) {
    testWidgets('record list and revision details fit at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final catalog = fixture('controlled_catalog');
      final rows =
          jsonDecode(
                File(
                  'test/fixtures/controlled_records.json',
                ).readAsStringSync(),
              )
              as List;
      final api = ApiService(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode(
              request.url.path.endsWith('/catalog')
                  ? catalog
                  : {'records': rows, 'has_more': false},
            ),
            200,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ControlledRecordsPanel(api: api),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Controlled reference records'), findsOneWidget);
      expect(find.text('View revision'), findsWidgets);
      await tester.ensureVisible(find.text('View revision').first);
      await tester.tap(find.text('View revision').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Evidence URL: https://example.org'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'server rejection retains the entered revision; saving never auto-activates',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final writes = <String>[], bodies = <Map<String, dynamic>>[];
      final api = ApiService(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            writes.add(request.url.path);
            bodies.add(
              Map<String, dynamic>.from(jsonDecode(request.body) as Map),
            );
            return http.Response(
              jsonEncode({
                'detail': 'Reviewed records require an explicit review note.',
              }),
              422,
            );
          }
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('/catalog')
                  ? fixture('controlled_catalog')
                  : {'records': [], 'has_more': false},
            ),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ControlledRecordsPanel(api: api),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('New record'));
      await tester.pumpAndSettle();
      await tester.tap(choice('Record type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Planting calendars').last);
      await tester.pumpAndSettle();
      for (final entry in {
        'Title': 'Retain this calendar draft',
        'Planting months (1-12, separated by commas)': '2, 8',
        'Public evidence URL (HTTPS)': 'https://example.org/test',
        'Source section / reference': 'Software test',
        'Method and limitations': 'Controlled fixture only',
        'Valid until (YYYY-MM-DD)': '2030-12-31',
      }.entries) {
        await tester.ensureVisible(field(entry.key));
        await tester.enterText(field(entry.key), entry.value);
      }
      await tester.tap(find.text('Save revision'));
      await tester.pumpAndSettle();
      expect(
        find.text('Reviewed records require an explicit review note.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(field('Title')).controller!.text,
        'Retain this calendar draft',
      );
      expect(writes, ['/api/admin/controlled-records']);
      expect(bodies.single['payload'], {
        'crop': 'banana',
        'months': [2, 8],
      });
      expect(bodies.single['expected_revision'], 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'saved references survive scroll restoration and analysis switching',
    (tester) async {
      final bucket = PageStorageBucket();
      const listKey = PageStorageKey<String>('mobile-analysis-scroll');
      final first = fixture('controlled_analysis')..['session_id'] = 101;
      final second = fixture('controlled_analysis')..['session_id'] = 102;
      final original = jsonEncode(first);
      Widget page(Map<String, dynamic> record, {bool seedOffset = false}) =>
          MaterialApp(
            home: Scaffold(
              body: PageStorage(
                bucket: bucket,
                child: ListView(
                  key: listKey,
                  children: [
                    Builder(
                      builder: (context) {
                        if (seedOffset) bucket.writeState(context, 180.0);
                        return SavedReferenceVersions(record: record);
                      },
                    ),
                    const SizedBox(height: 1600),
                  ],
                ),
              ),
            ),
          );
      await tester.pumpWidget(page(first, seedOffset: true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Saved reference versions'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Saved reference configuration:'),
        findsOneWidget,
      );
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
      await tester.pumpWidget(page(second));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await revealInList(
        tester,
        find.text('Saved reference versions'),
        list: find.byKey(listKey),
      );
      expect(
        find.textContaining('Saved reference configuration:'),
        findsNothing,
      );
      await tester.tap(find.text('Saved reference versions'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Saved reference configuration:'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page(first));
      await tester.pumpAndSettle();
      await revealInList(
        tester,
        find.text('Saved reference versions'),
        list: find.byKey(listKey),
      );
      expect(
        find.textContaining('Saved reference configuration:'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(jsonEncode(first), original);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('cancelled activation sends no mutation', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final writes = <String>[];
    final rows =
        jsonDecode(
              File('test/fixtures/controlled_records.json').readAsStringSync(),
            )
            as List;
    final api = ApiService(
      client: MockClient((request) async {
        if (request.method == 'POST') writes.add(request.url.path);
        return http.Response(
          jsonEncode(
            request.url.path.endsWith('/catalog')
                ? fixture('controlled_catalog')
                : {'records': rows, 'has_more': false},
          ),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ControlledRecordsPanel(api: api)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Activate').first);
    await tester.tap(find.text('Activate').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
  test(
    'both reports export preserved reference versions alongside local explanations',
    () async {
      final record = fixture('controlled_analysis');
      final directory = Directory('build/phase-06/export-qa');
      await directory.create(recursive: true);
      final farmer = await buildAnalysisPdf(record);
      final analyst = await buildOperatorReport({
        'case': {'id': 606, 'version': 1, 'status': 'pending'},
        'analysis': record,
        'revisions': [],
        'events': [],
      });
      expect(farmer.length, greaterThan(1000));
      expect(analyst.length, greaterThan(1000));
      await File(
        '${directory.path}/farmer-controlled-report.pdf',
      ).writeAsBytes(farmer);
      await File(
        '${directory.path}/analyst-controlled-report.pdf',
      ).writeAsBytes(analyst);
    },
  );
}
