import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/boundary_draft_store.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/session_token_store.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'qa_support.dart';

void main() {
  for (final resume in [true, false]) {
    testWidgets(
      'polygon draft offers ${resume ? 'resume' : 'discard'} without creating a duplicate farm',
      (tester) async {
        HttpOverrides.global = QaHttpOverrides();
        addTearDown(() => HttpOverrides.global = null);
        SharedPreferences.setMockInitialValues({'account_id': 'owner'});
        await BoundaryDraftStore.write('polygon', {
          'name': 'Restored draft farm',
          'points': [
            {'lat': 7.29, 'lng': 125.62},
            {'lat': 7.291, 'lng': 125.62},
            {'lat': 7.291, 'lng': 125.621},
          ],
          'request_key': 'persisted-request-key',
        });
        var farmWrites = 0;
        final api = ApiService(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/farms') &&
                request.method == 'POST') {
              farmWrites++;
            }
            return http.Response(
              '{"boundaries":[],"reference_locations":[],"analysis_coverage":{"supported":false}}',
              200,
            );
          }),
        );
        final state = AnalysisState(api: api);
        addTearDown(state.dispose);
        await tester.pumpWidget(
          GeoSustainApp(home: PolygonDrawingPage(state: state)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Resume boundary draft?'), findsOneWidget);
        await tester.tap(find.text(resume ? 'Resume' : 'Discard'));
        await tester.pumpAndSettle();
        if (resume) {
          final scroll = tester.state<ScrollableState>(
            find.byType(Scrollable).first,
          );
          scroll.position.jumpTo(scroll.position.maxScrollExtent);
          await tester.pumpAndSettle();
          final nameField = tester.widget<TextField>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  widget.decoration?.labelText == 'Farm name',
            ),
          );
          expect(nameField.controller!.text, 'Restored draft farm');
          expect(
            (await BoundaryDraftStore.read('polygon'))!['request_key'],
            'persisted-request-key',
          );
        } else {
          expect(await BoundaryDraftStore.read('polygon'), isNull);
        }
        expect(farmWrites, 0);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  test(
    'drafts preserve retry identity and never cross account switches',
    () async {
      SharedPreferences.setMockInitialValues({'account_id': 'one'});
      final prefs = await SharedPreferences.getInstance();
      await BoundaryDraftStore.write('polygon', {
        'name': 'My draft',
        'points': [
          {'lat': 7.3, 'lng': 125.6},
        ],
        'request_key': 'same-retry-key',
      });
      expect(
        (await BoundaryDraftStore.read('polygon'))!['request_key'],
        'same-retry-key',
      );
      await prefs.setString('account_id', 'two');
      expect(await BoundaryDraftStore.read('polygon'), isNull);
      await prefs.setString('account_id', 'one');
      expect((await BoundaryDraftStore.read('polygon'))!['name'], 'My draft');
      await BoundaryDraftStore.clearForSignOut();
      await prefs.setString('account_id', 'one');
      expect(await BoundaryDraftStore.read('polygon'), isNull);
    },
  );

  test(
    'Android migrates the token to protected storage and removes plaintext',
    () async {
      SharedPreferences.setMockInitialValues({'token': 'legacy-token'});
      final store = SessionTokenStore();
      expect(await store.read(), 'legacy-token');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('token'), isNull);
      await store.clear();
      expect(await store.read(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'farm text follows ${dark ? 'dark' : 'light'} theme with readable contrast',
      (tester) async {
        final theme = dark
            ? ThemeData.dark(useMaterial3: true)
            : ThemeData.light(useMaterial3: true);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: SingleChildScrollView(
                child: GeoFarmCard(
                  farm: const {
                    'farm_name': 'Contrast farm',
                    'analysis_count': 0,
                  },
                  busy: false,
                  onOpen: () {},
                  onAnalyze: () {},
                  onResults: () {},
                  onEdit: () {},
                  onArchive: () {},
                ),
              ),
            ),
          ),
        );
        final text = tester.widget<Text>(find.text('Contrast farm'));
        final foreground = text.style!.color!;
        expect(foreground, theme.colorScheme.onSurface);
        final bg = theme.cardTheme.color ?? theme.colorScheme.surface;
        final a = foreground.computeLuminance(), b = bg.computeLuminance();
        final contrast = (a > b
            ? (a + .05) / (b + .05)
            : (b + .05) / (a + .05));
        expect(contrast, greaterThanOrEqualTo(4.5));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
