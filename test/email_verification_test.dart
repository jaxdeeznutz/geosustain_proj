import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:geosustain_clean_arranged/main.dart';

void main() {
  tearDown(() => appThemeMode.value = ThemeMode.light);
  test(
    'email code transport uses ticket and does not save a login token',
    () async {
      final requests = <http.Request>[];
      final api = ApiService(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode({'verified': true}), 200);
        }),
      );
      addTearDown(api.close);
      await api.emailVerification('x' * 43, code: '123456');
      await api.emailVerification('x' * 43);
      expect(requests.first.url.path, '/api/mobile/verify-email');
      expect(jsonDecode(requests.first.body), {
        'ticket': 'x' * 43,
        'code': '123456',
      });
      expect(requests.last.url.path, '/api/mobile/resend-verification');
      expect(jsonDecode(requests.last.body), {'ticket': 'x' * 43});
      expect(await api.getToken(), isNull);
    },
  );
  testWidgets('verification validates code and resend cooldown locally', (
    t,
  ) async {
    await t.pumpWidget(
      GeoSustainApp(
        home: EmailVerificationPage(
          email: 'fixture@example.com',
          ticket: 'x' * 43,
        ),
      ),
    );
    await t.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Verify email');
    await t.ensureVisible(button);
    await t.tap(button);
    await t.pumpAndSettle();
    expect(
      find.text('Enter the six-digit code from your email.'),
      findsOneWidget,
    );
    final resend = find.text('Resend code');
    await t.ensureVisible(resend);
    await t.tap(resend);
    await t.pumpAndSettle();
    expect(
      find.text('Wait one minute before requesting another code.'),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('verification screen remains readable in dark mode', (t) async {
    appThemeMode.value = ThemeMode.dark;
    await t.pumpWidget(
      GeoSustainApp(
        home: EmailVerificationPage(
          email: 'fixture@example.com',
          ticket: 'x' * 43,
        ),
      ),
    );
    await t.pumpAndSettle();
    final field = t.widget<TextField>(find.byType(TextField));
    expect(field.autofillHints, contains(AutofillHints.oneTimeCode));
    expect(
      Theme.of(t.element(find.byType(TextField))).brightness,
      Brightness.dark,
    );
    expect(t.takeException(), isNull);
  });
}
