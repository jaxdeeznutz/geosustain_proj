import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/api_service.dart';

void main() {
  for (final status in [401, 503]) {
    testWidgets(
      'restoration handles HTTP $status without confusing outage with logout',
      (tester) async {
        SharedPreferences.setMockInitialValues({'token': 'saved-session'});
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = ApiService(
          client: MockClient((request) async {
            expect(request.headers['Authorization'], 'Bearer saved-session');
            return http.Response('{"error":"Request unavailable"}', status);
          }),
        );
        addTearDown(api.close);
        await tester.pumpWidget(MaterialApp(home: SessionGate(api: api)));
        await tester.pumpAndSettle();
        if (status == 401) {
          expect(find.byType(LoginPage), findsOneWidget);
          expect(await api.getToken(), isNull);
        } else {
          expect(find.text('Unable to restore your session'), findsOneWidget);
          expect(await api.getToken(), 'saved-session');
          await tester.tap(find.text('Back to login'));
          await tester.pumpAndSettle();
          expect(find.byType(LoginPage), findsOneWidget);
          expect(await api.getToken(), isNull);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
