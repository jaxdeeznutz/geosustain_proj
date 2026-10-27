import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:geosustain_clean_arranged/web/web_record_controller.dart';
import 'package:geosustain_clean_arranged/web/operator_metrics.dart';
import 'package:geosustain_clean_arranged/web/operator_report.dart';
import 'package:geosustain_clean_arranged/web/portal_routes.dart';
import 'package:geosustain_clean_arranged/web/route_location.dart';
import 'qa_support.dart';

Map<String, dynamic> fixture() => {
  'case': {
    'id': 7,
    'owner_id': 2,
    'current_session_id': 42,
    'farm_id': 3,
    'version': 1,
    'status': 'pending',
    'submitted_at': '2026-10-26T00:00:00Z',
  },
  'analysis': {
    'session_id': 42,
    'analysis_mode': 'preliminary_environmental',
    'selected_polygon': [],
    'verification_status': 'pending',
  },
  'events': [],
  'revisions': [],
  'followups': [],
  'geometry_matches_current': true,
  'current_farm_version': 1,
};
void main() {
  test(
    'browser history is acknowledged instead of undoing a case navigation',
    () async {
      final observer = PortalBrowserHistory(() => '/operator/queue?case=7');
      expect(
        await observer.didPushRouteInformation(
          RouteInformation(uri: Uri(path: '/')),
        ),
        isTrue,
      );
      expect(PortalRoutes.current.value.queryParameters['case'], '7');
    },
  );
  test('direct routes and legacy hash routes preserve case references', () {
    expect(
      portalLocation('', '/operator/queue', '?case=7'),
      '/operator/queue?case=7',
    );
    expect(
      portalLocation('#/operator/map', '/operator/queue', '?case=7'),
      '/operator/map',
    );
    expect(portalLocation('', '/', ''), '/');
  });
  setUp(() => PortalRoutes.go('/'));
  test(
    'constant recorded layer is neutral, missing is unknown, and zero is retained',
    () {
      expect(observedPosition(3, [3, 3, 3]), .5);
      expect(observedPosition(null, [0, 5]), isNull);
      expect(observedPosition(double.nan, [0, 5]), isNull);
      expect(observedPosition(0, [0, 5]), 0);
    },
  );
  test(
    'inbox and map filters are independent and stale filtered responses cannot overwrite',
    () async {
      final slow = Completer<http.Response>();
      final requests = <Uri>[];
      final api = ApiService(
        client: MockClient((r) async {
          requests.add(r.url);
          if (r.url.queryParameters['status'] == 'pending') return slow.future;
          return http.Response(
            '{"queue":[{"case_id":2}],"has_more":false}',
            200,
          );
        }),
      );
      final inbox = WebRecordController(api, '/api/operator/inbox', 'queue'),
          map = WebRecordController(
            api,
            '/api/operator/map',
            'queue',
            limit: 50,
          );
      final first = inbox.filter({'status': 'pending'});
      await Future<void>.delayed(Duration.zero);
      await map.filter({'status': 'all'});
      await inbox.filter({'status': 'needs_information'});
      slow.complete(
        http.Response('{"queue":[{"case_id":1}],"has_more":true}', 200),
      );
      await first;
      expect(inbox.rows.single['case_id'], 2);
      expect(inbox.appliedParameters['status'], 'needs_information');
      expect(map.appliedParameters['status'], 'all');
      expect(requests.length, 3);
      expect(requests[0].queryParameters['limit'], '20');
      expect(requests[1].queryParameters['limit'], '50');
      inbox.dispose();
      map.dispose();
      api.close();
    },
  );
  testWidgets(
    'review opens with loading and retains notes after stale decision; cancel sends no write',
    (tester) async {
      HttpOverrides.global = QaHttpOverrides();
      addTearDown(() => HttpOverrides.global = null);
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final initial = Completer<http.Response>();
      var writes = 0;
      final api = ApiService(
        client: MockClient((r) async {
          if (r.method == 'POST') {
            writes++;
            return http.Response('{"detail":"Changed"}', 409);
          }
          return initial.future;
        }),
      );
      await api.saveToken('synthetic-token');
      final state = AnalysisState(api: api)
        ..currentUser = {'id': 1, 'role': 'agricultural_planning_analyst'};
      await tester.pumpWidget(
        GeoSustainApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WebReviewWorkbench(state: state, reference: '7'),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      initial.complete(http.Response(jsonEncode(fixture()), 200));
      await tester.pumpAndSettle();
      final explanation = find.widgetWithText(
        TextField,
        'Decision explanation / advisory note',
      );
      await tester.ensureVisible(explanation);
      await tester.enterText(explanation, 'Confirm the outline.');
      await tester.ensureVisible(find.text('Request information'));
      await tester.tap(find.text('Request information'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      await tester.tap(find.text('Request information'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm decision'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.textContaining('Your notes are retained'), findsOneWidget);
      expect(
        tester.widget<TextField>(explanation).controller!.text,
        'Confirm the outline.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  for (final width in [390.0, 768.0]) {
    testWidgets('inbox reflows at $width without downloading all pages', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var count = 0;
      final api = ApiService(
        client: MockClient((r) async {
          count++;
          return http.Response(
            '{"queue":[{"case_id":1,"farmer_name":"Test farmer","farm_name":"Synthetic farm","verification_status":"pending","submitted_at":"2026-10-26"}],"has_more":true}',
            200,
          );
        }),
      );
      final c = WebRecordController(api, '/api/operator/inbox', 'queue');
      await c.filter({'status': 'pending'});
      await tester.pumpWidget(
        GeoSustainApp(
          home: Scaffold(
            body: SingleChildScrollView(child: WebOperatorInbox(controller: c)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(count, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      api.close();
    });
  }
  test(
    'case and planning PDFs retain decision timeline and scoped totals',
    () async {
      final out = Directory('defense-evidence/operator-workflow-execution')
        ..createSync(recursive: true);
      final data = Map<String, dynamic>.from(
        jsonDecode(
          File('test/fixtures/operator_review.json').readAsStringSync(),
        ),
      );
      data['analysis']['farm_name'] = 'Peñafrancia synthetic parcel';
      data['events'] = [
        ...data['events'],
        for (var i = 0; i < 14; i++)
          {
            'kind': 'advisory_note',
            'notes':
                'SYNTHETIC PAGINATION CHECK $i. ${List.filled(5, 'Review the recorded boundary and unavailable measurements.').join(' ')}',
            'created_at': '2026-10-27',
            'actor_name': 'Synthetic reviewer',
            'session_id': 42,
          },
      ];
      final pdf = await buildOperatorReport(
        data,
        generated: DateTime.utc(2026, 10, 27),
      );
      expect(ascii.decode(pdf.take(5).toList()), '%PDF-');
      expect(pdf.length, greaterThan(10000));
      File('${out.path}/synthetic-case-report.pdf').writeAsBytesSync(pdf);
      final planning = await buildOperatorReport(
        {
          'cases': 501,
          'pending_count': 500,
          'distinct_farms': 1,
          'parcel_area_sum_ha': 1,
          'scope':
              'SYNTHETIC TEST ONLY. Submitted cases in the isolated fixture.',
        },
        planning: true,
        scope: 'Synthetic place',
      );
      File(
        '${out.path}/synthetic-planning-report.pdf',
      ).writeAsBytesSync(planning);
    },
  );
}
