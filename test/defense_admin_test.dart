import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/api_service.dart';

void main() {
  testWidgets(
    'one failed admin panel preserves valid totals and names the failure',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ApiService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/analyses')) {
            return http.Response('{}', 503);
          }
          if (request.url.path.endsWith('/dashboard')) {
            return http.Response(
              jsonEncode({
                'stats': {
                  'farmers': 17,
                  'registered_parcels': 12,
                  'total_analyses': 29,
                },
              }),
              200,
            );
          }
          final key = request.url.path.endsWith('/users')
              ? 'users'
              : request.url.path.endsWith('/crops')
              ? 'crops'
              : 'logs';
          return http.Response(jsonEncode({key: [], 'has_more': false}), 200);
        }),
      );
      final messages = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: WebAdminDashboard(
            api: api,
            logout: () {},
            message: messages.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('17'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(messages.single, contains('Analyses'));
      expect(
        find.textContaining('Could not refresh: Analyses'),
        findsOneWidget,
      );
    },
  );
}
