import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:geosustain_clean_arranged/main.dart';

void main() {
  test(
    'Google exchange stores only the server-issued app session and role',
    () async {
      final api = ApiService(
        client: MockClient((request) async {
          expect(request.url.path, '/api/mobile/auth/google');
          expect(jsonDecode(request.body), {
            'id_token': 'synthetic-provider-proof',
          });
          return http.Response(
            jsonEncode({
              'token': 'synthetic-app-session',
              'user': {'id': 44, 'username': 'Fixture', 'role': 'farmer'},
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      expect(
        (await api.googleLogin('synthetic-provider-proof'))['user']['role'],
        'farmer',
      );
      expect(await api.getToken(), 'synthetic-app-session');
      expect(
        (await SharedPreferences.getInstance()).getString('account_id'),
        '44',
      );
    },
  );

  test(
    'late phone verification response cannot apply to a switched session',
    () async {
      SharedPreferences.setMockInitialValues({
        'token': 'old-session',
        'account_id': '44',
      });
      late ApiService api;
      api = ApiService(
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer old-session');
          await api.saveToken('new-session');
          return http.Response(
            jsonEncode({
              'user': {'id': 44, 'phone_verified': true},
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      await expectLater(
        api.finishPhoneVerification('synthetic-ticket', 'synthetic-proof'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
      );
      expect(await api.getToken(), 'new-session');
    },
  );

  testWidgets(
    'profile phone saves without claiming verification when provider is unavailable',
    (t) async {
      SharedPreferences.setMockInitialValues({
        'token': 'synthetic-session',
        'account_id': '44',
      });
      Map<String, dynamic>? stored;
      final api = ApiService(
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          stored = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'user': {
                'id': 44,
                'username': 'Fixture',
                'role': 'farmer',
                'phone_number': stored!['phone_number'],
                'phone_verified': false,
              },
            }),
            200,
          );
        }),
      );
      final state = AnalysisState(api: api)
        ..currentUser = {'id': 44, 'username': 'Fixture', 'role': 'farmer'};
      addTearDown(state.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(children: [IdentityProfileSection(state: state)]),
          ),
        ),
      );
      await t.enterText(find.byType(TextField).first, '+639171234567');
      await t.tap(find.text('Save phone number'));
      await t.pumpAndSettle();
      expect(stored?['phone_number'], '+639171234567');
      expect(state.currentUser?['phone_verified'], false);
      expect(find.text('Not verified'), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Send SMS code'),
            )
            .onPressed,
        isNull,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'email recovery resets password without creating a login session',
    (t) async {
      final paths = <String>[];
      final api = ApiService(
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('/start')) {
            return http.Response(
              jsonEncode({
                'verification_ticket': 'x' * 43,
                'message': 'If eligible, check your email.',
              }),
              202,
            );
          }
          expect(jsonDecode(request.body), {
            'ticket': 'x' * 43,
            'code': '123456',
            'new_password': 'NewPassword!234',
          });
          return http.Response(
            jsonEncode({'message': 'Password changed.'}),
            200,
          );
        }),
      );
      addTearDown(api.close);
      await t.pumpWidget(MaterialApp(home: PasswordRecoveryPage(api: api)));
      await t.enterText(find.byType(TextField).first, 'fixture@example.com');
      await t.tap(find.text('Send recovery code'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).at(1), '123456');
      await t.enterText(find.byType(TextField).at(2), 'NewPassword!234');
      await t.enterText(find.byType(TextField).at(3), 'NewPassword!234');
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Set new password'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Set new password'));
      await t.pumpAndSettle();
      expect(paths, [
        '/api/mobile/password-reset/start',
        '/api/mobile/password-reset/complete',
      ]);
      expect(await api.getToken(), isNull);
      expect(
        find.textContaining('Password changed. Return to sign in'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );

  test('preliminary data never becomes a complete ranked recommendation', () {
    expect(
      rankedCropRecommendations({
        'analysis_mode': 'preliminary_environmental',
        'scoring_version': 'fixture',
        'crop_assessments': [
          {'crop': 'Rice', 'compatibility_pct': 100},
        ],
      }),
      isEmpty,
    );
  });

  test(
    'preliminary PDF preserves factor comparisons and suppresses stale crop claims',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final record = <String, dynamic>{
        'analysis_mode': 'preliminary_environmental',
        'scoring_version': 'fixture',
        'analysis_schema_version': 'panabo-preliminary-cagro-v2',
        'place_name': 'TEST FIXTURE ONLY',
        'predicted_crop': 'SHOULD_NOT_BE_RECOMMENDED',
        'crop_compatibility_pct': 99,
        'xai_explanation': {'summary': 'SHOULD_NOT_BE_EXPLAINED'},
        'crop_assessments': [
          {
            'crop': 'Rice',
            'factors': [
              {
                'factor': 'temperature',
                'label': 'Climate temperature',
                'unit': 'C',
                'period': 'annual_mean',
                'value': 27,
                'score': 100,
                'measurement': {
                  'value': 27,
                  'unit': 'C',
                  'period': 'annual_mean',
                  'quality': 'modelled',
                },
                'requirement': {
                  'optimal': [20, 30],
                },
              },
            ],
          },
        ],
        'data_quality_warnings': [
          'Synthetic regression artifact, not a real farm or scientific validation.',
        ],
      };
      final bytes = await buildAnalysisPdf(record);
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      final path = File(
        'defense-evidence/readiness-execution/phase-02/preliminary-report-fixture.pdf',
      );
      await path.parent.create(recursive: true);
      await path.writeAsBytes(bytes);
    },
  );
}
