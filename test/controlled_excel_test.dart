import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:geosustain_clean_arranged/web/excel_files.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final bytes = File(
    'backend/assets/crop_requirements_template.xlsx',
  ).readAsBytesSync();
  final expected = {
    'record_key': 'rice_rainfall',
    'revision': 3,
    'generation': 2,
  };
  Map<String, dynamic> preview({bool invalid = false}) => {
    'upload_id': 'saved-upload-id',
    'valid_rows': invalid ? 0 : 1,
    'total_rows': 1,
    'rows': [
      {
        'row': 2,
        'crop': 'rice',
        'factor': 'rainfall',
        'payload': {
          'preferred_min': 1000,
          'preferred_max': 2000,
          'absolute_min': 500,
          'absolute_max': 3000,
          'unit': 'mm/year',
          'period': 'annual_mean_total',
        },
        'source': 'Synthetic software test only',
        'valid_from': '2020-01-01',
        'valid_until': '9999-12-31',
        'expected': expected,
        'errors': invalid ? ['preferred minimum exceeds maximum'] : [],
      },
    ],
  };
  for (final width in [360.0, 1280.0]) {
    testWidgets('Excel preview fits $width and activates only after review', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1050);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final writes = <Map<String, dynamic>>[];
      final paths = <String>[];
      final api = ApiService(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            paths.add(request.url.path);
            writes.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response(
              jsonEncode(
                request.url.path.endsWith('/preview')
                    ? preview()
                    : {'imported': 1, 'activated': true},
              ),
              200,
            );
          }
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('/catalog')
                  ? jsonDecode(
                      File(
                        'test/fixtures/controlled_catalog.json',
                      ).readAsStringSync(),
                    )
                  : {'records': [], 'has_more': false},
            ),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: width == 360 ? ThemeData.dark() : ThemeData.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(width == 360 ? 2 : 1)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ControlledRecordsPanel(
                api: api,
                excelPicker: () async =>
                    ExcelUpload('requirements.xlsx', bytes),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Import Excel'));
      await tester.tap(find.text('Import Excel'));
      await tester.pumpAndSettle();
      expect(paths, ['/api/admin/controlled-records/excel/preview']);
      expect(writes.single['content_base64'], base64Encode(bytes));
      expect(find.text('1 of 1 rows ready'), findsOneWidget);
      expect(
        find.textContaining('Preferred: 1000 to 2000 mm/year'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save and activate'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('excel-import-reviewed')),
      );
      await tester.tap(find.byKey(const ValueKey('excel-import-reviewed')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save and activate'));
      await tester.tap(find.text('Save and activate'));
      await tester.pumpAndSettle();
      expect(writes.last['activate'], true);
      expect(writes.last['expected'], [expected]);
      expect(writes.last.containsKey('payload'), false);
      expect(
        find.text('1 reference rows saved and activated.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final action in ['invalid', 'cancel', 'draft']) {
    testWidgets('Excel $action preserves the intended save boundary', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1050);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final applies = <Map<String, dynamic>>[];
      final api = ApiService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/preview')) {
            return http.Response(
              jsonEncode(preview(invalid: action == 'invalid')),
              200,
            );
          }
          if (request.url.path.endsWith('/apply')) {
            applies.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response(
              jsonEncode({'imported': 1, 'activated': false}),
              200,
            );
          }
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('/catalog')
                  ? jsonDecode(
                      File(
                        'test/fixtures/controlled_catalog.json',
                      ).readAsStringSync(),
                    )
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
              child: ControlledRecordsPanel(
                api: api,
                excelPicker: () async =>
                    ExcelUpload('requirements.xlsx', bytes),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import Excel'));
      await tester.pumpAndSettle();
      if (action == 'invalid') {
        expect(find.text('preferred minimum exceeds maximum'), findsOneWidget);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Save drafts'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save and activate'),
              )
              .onPressed,
          isNull,
        );
      }
      await tester.tap(find.text(action == 'draft' ? 'Save drafts' : 'Cancel'));
      await tester.pumpAndSettle();
      if (action == 'draft') {
        expect(applies.single['activate'], false);
        expect(applies.single['review_note'], '');
      } else {
        expect(applies, isEmpty);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'Template download retains workbook bytes; cancelled picker writes nothing',
    (tester) async {
      var posts = 0;
      final saved = <String>[];
      final api = ApiService(
        client: MockClient((request) async {
          if (request.method == 'POST') posts++;
          if (request.url.path.endsWith('/template')) {
            return http.Response.bytes(bytes, 200);
          }
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('/catalog')
                  ? jsonDecode(
                      File(
                        'test/fixtures/controlled_catalog.json',
                      ).readAsStringSync(),
                    )
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
              child: ControlledRecordsPanel(
                api: api,
                excelPicker: () async => null,
                excelSaver: (actual, name) async {
                  expect(actual, bytes);
                  saved.add(name);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download template'));
      await tester.pumpAndSettle();
      expect(saved.single, endsWith('.xlsx'));
      await tester.tap(find.text('Import Excel'));
      await tester.pumpAndSettle();
      expect(posts, 0);
      expect(find.text('Import crop requirements'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
