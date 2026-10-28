import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/web/portal_routes.dart';
import 'qa_support.dart';

void main() {
  setUp(() {
    PortalRoutes.go('/operator/settings');
    HttpOverrides.global = QaHttpOverrides();
  });
  tearDown(() => HttpOverrides.global = null);

  testWidgets('analyst navigation keeps existing URLs and area selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <http.Request>[];
    final api = ApiService(
      client: MockClient((r) async {
        requests.add(r);
        return http.Response(
          '{"queue":[],"history":[],"reports":[],"has_more":false}',
          200,
        );
      }),
    );
    await api.saveToken('synthetic-token');
    final state = AnalysisState(api: api)
      ..currentUser = {'id': 1, 'role': 'analyst', 'username': 'Synthetic'}
      ..userLoaded = true;
    await tester.pumpWidget(
      GeoSustainApp(
        home: WebAnalystDashboard(state: state, logout: () {}, message: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Review Inbox')).dy,
      lessThan(tester.getTopLeft(find.text('Planning Map')).dy),
    );
    expect(find.text('Recommendation Patterns'), findsNothing);

    await tester.tap(find.text('Review Inbox'));
    await tester.pumpAndSettle();
    expect(PortalRoutes.current.value.path, '/operator/queue');
    expect(find.byType(WebOperatorInbox), findsOneWidget);

    await tester.tap(find.text('Planning Map'));
    await tester.pumpAndSettle();
    expect(PortalRoutes.current.value.path, '/operator/map');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Select an area'));
    await tester.pumpAndSettle();
    state.polygonPoints.addAll(const [
      LatLng(7.30, 125.65),
      LatLng(7.301, 125.65),
      LatLng(7.301, 125.651),
    ]);
    final selection = List<LatLng>.of(state.polygonPoints);
    await tester.ensureVisible(find.text('Continue to analysis'));
    await tester.tap(find.text('Continue to analysis'));
    await tester.pumpAndSettle();
    expect(PortalRoutes.current.value.path, '/operator/analyze');
    expect(find.byType(WebAnalyzeScreen), findsOneWidget);
    expect(state.polygonPoints, selection);
    expect(requests.where((r) => r.method == 'POST'), isEmpty);

    PortalRoutes.go('/operator/trends');
    await tester.pumpAndSettle();
    expect(find.byType(WebCropTrendsScreen), findsOneWidget);
    PortalRoutes.go('/operator/reports');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Recommendation Patterns'));
    await tester.tap(find.text('Recommendation Patterns'));
    await tester.pumpAndSettle();
    expect(PortalRoutes.current.value.path, '/operator/trends');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('own submission is visible but review decisions are disabled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var writes = 0;
    final api = ApiService(
      client: MockClient((r) async {
        if (r.method == 'POST') writes++;
        return http.Response(
          jsonEncode({
            'case': {
              'id': 7,
              'owner_id': 1,
              'current_session_id': 42,
              'status': 'pending',
              'version': 1,
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
          }),
          200,
        );
      }),
    );
    await api.saveToken('synthetic-token');
    final state = AnalysisState(api: api)
      ..currentUser = {'id': 1, 'role': 'analyst'};
    await tester.pumpWidget(
      GeoSustainApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WebReviewWorkbench(state: state, reference: '7'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'You cannot verify or reject your own submission. Another analyst must review it.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Verify assessment'),
          )
          .onPressed,
      isNull,
    );
    for (final label in ['Request information', 'Reject submission']) {
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label))
            .onPressed,
        isNull,
      );
    }
    expect(writes, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
