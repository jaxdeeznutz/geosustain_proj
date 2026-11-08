import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/offline_farm_store.dart';
import 'package:geosustain_clean_arranged/web/portal_routes.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'account_id': '1'});
    OfflineFarmStore.resetTestState();
  });

  testWidgets(
    'farm menu requires confirmation; deletion clears selection and offline cache',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final farms = <Map<String, dynamic>>[
        {
          'id': 12,
          'farmer_id': 1,
          'farm_name': 'Delete fixture',
          'analysis_count': 0,
        },
      ];
      var deletes = 0;
      final state = AnalysisState(
        api: ApiService(
          client: MockClient((request) async {
            if (request.method == 'DELETE') {
              expect(request.url.path, '/api/mobile/farms/12');
              deletes++;
              farms.clear();
              return http.Response('{"deleted":true,"farm_id":12}', 200);
            }
            return http.Response(jsonEncode({'farms': farms}), 200);
          }),
        ),
      )..currentUser = {'id': 1, 'role': 'farmer'};
      addTearDown(state.dispose);
      await tester.pumpWidget(MaterialApp(home: MyFarmsPage(state: state)));
      await tester.pumpAndSettle();
      state.focusFarm(farms.single);
      await tester.tap(find.byTooltip('Farm actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete farm'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Past analyses and analyst reviews'),
        findsOneWidget,
      );
      expect(deletes, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(state.farms, hasLength(1));
      await tester.tap(find.byTooltip('Farm actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete farm'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete farm'));
      await tester.pumpAndSettle();
      expect(deletes, 1);
      expect(state.farms, isEmpty);
      expect(state.selectedFarm, isNull);
      expect(
        OfflineFarmStore.rows((await OfflineFarmStore.read())['farms']),
        isEmpty,
      );
      expect(find.text('Farm deleted.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('failed deletion keeps saved farm and its offline copy', () async {
    final farm = <String, dynamic>{'id': 3, 'farm_name': 'Keep fixture'};
    await OfflineFarmStore.cacheFarms([farm]);
    final state =
        AnalysisState(
            api: ApiService(
              client: MockClient(
                (_) async => http.Response('{"detail":"Not Found"}', 404),
              ),
            ),
          )
          ..currentUser = {'id': 1}
          ..replaceFarms([farm]);
    addTearDown(state.dispose);
    await expectLater(state.deleteFarm(farm), throwsA(isA<ApiException>()));
    expect(state.farms, hasLength(1));
    expect(
      OfflineFarmStore.rows((await OfflineFarmStore.read())['farms']),
      hasLength(1),
    );
  });

  test(
    'pending local deletion never sends a server request or removes other farms',
    () async {
      final pending = await OfflineFarmStore.save(
        requestId: 'delete-local',
        name: 'Pending',
        location: '',
        polygon: const [
          {'lat': 7.29, 'lng': 125.62},
          {'lat': 7.291, 'lng': 125.62},
          {'lat': 7.29, 'lng': 125.621},
        ],
        method: 'manual_draw',
      );
      final saved = <String, dynamic>{'id': 4, 'farm_name': 'Keep remote'};
      await OfflineFarmStore.cacheFarms([saved]);
      final state =
          AnalysisState(
              api: ApiService(
                client: MockClient(
                  (_) async => throw StateError('Unexpected network request'),
                ),
              ),
            )
            ..currentUser = {'id': 1}
            ..replaceFarms([pending, saved]);
      addTearDown(state.dispose);
      await state.deleteFarm(pending);
      expect(state.farms.single['id'], 4);
      final stored = await OfflineFarmStore.read();
      expect(OfflineFarmStore.rows(stored['pending']), isEmpty);
      expect(OfflineFarmStore.rows(stored['farms']), hasLength(1));
    },
  );

  testWidgets(
    'admin analyses request six rows and navigate with six-row offsets',
    (tester) async {
      tester.view.physicalSize = const Size(1700, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <Uri>[];
      final api = ApiService(
        client: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/analyses')) {
            requests.add(request.url);
            expect(request.url.queryParameters['limit'], '6');
            final offset = int.parse(request.url.queryParameters['offset']!);
            final rows = List.generate(
              7,
              (i) => <String, dynamic>{
                'session_id': i + 1,
                'username': 'Page Farmer ${i + 1}',
                'role': 'farmer',
                'predicted_crop': 'Rice',
                'place_name': 'Fixture',
                'verification_status': 'draft',
                'area_hectares': 1,
              },
            );
            return http.Response(
              jsonEncode({
                'analyses': rows.skip(offset).take(6).toList(),
                'has_more': offset == 0,
              }),
              200,
            );
          }
          if (path.endsWith('/system-status')) {
            return http.Response(
              jsonEncode({
                'status': 'healthy',
                'checked_at': '2026-11-09T00:00:00Z',
                'checks': [
                  {
                    'key': 'api',
                    'label': 'Backend API',
                    'status': 'healthy',
                    'message': 'Fixture read passed.',
                  },
                ],
              }),
              200,
            );
          }
          if (path.endsWith('/dashboard')) {
            return http.Response('{"stats":{}}', 200);
          }
          if (path.endsWith('/users')) {
            expect(request.url.queryParameters['limit'], '50');
          }
          return http.Response(
            jsonEncode({
              path.endsWith('/users')
                      ? 'users'
                      : path.endsWith('/crops')
                      ? 'crops'
                      : 'logs':
                  [],
              'has_more': false,
            }),
            200,
          );
        }),
      );
      PortalRoutes.go('/admin/analyses');
      await tester.pumpWidget(
        MaterialApp(
          home: WebAdminDashboard(api: api, logout: () {}, message: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Page Farmer 6'), findsOneWidget);
      expect(find.text('Page Farmer 7'), findsNothing);
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Next'));
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      expect(requests.last.queryParameters['offset'], '6');
      expect(find.text('1 displayed · Page 2'), findsOneWidget);
      expect(find.text('Page Farmer 7'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Previous'));
      await tester.pumpAndSettle();
      expect(requests.last.queryParameters['offset'], '0');
      expect(find.text('6 displayed · Page 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
