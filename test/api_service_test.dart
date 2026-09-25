import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/api_service.dart';

Map<String, dynamic> weatherFixture() => {
  'current': {
    'time': '2026-09-23T23:15',
    'temperature_2m': 28,
    'wind_speed_10m': 36,
    'weather_code': 61,
  },
  'daily': {
    'time': [
      for (var i = 30; i >= -1; i--)
        DateTime(
          2026,
          9,
          23,
        ).subtract(Duration(days: i)).toIso8601String().substring(0, 10),
    ],
    'precipitation_sum': <num?>[...List.filled(30, 1), 7, 90],
  },
  'hourly': {
    'time': [
      '2026-08-24T00:00',
      '2026-09-23T23:00',
      for (var i = 0; i < 6; i++) '2026-09-24T0$i:00',
    ],
    'precipitation': [100, 100, ...List.filled(6, 1)],
    'precipitation_probability': [99, 99, ...List.filled(6, 55)],
    'wind_speed_10m': [100, 100, ...List.filled(6, 36)],
    'temperature_2m': [50, 50, ...List.filled(6, 28)],
    'weather_code': [95, 95, ...List.filled(6, 61)],
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('successful HTTP status with malformed JSON is rejected', () async {
    final api = ApiService(
      client: MockClient(
        (_) async => http.Response('<html>Maintenance</html>', 200),
      ),
    );
    addTearDown(api.close);
    await expectLater(api.getCounts(), throwsFormatException);
  });

  test(
    'missing historical rainfall is not reported as zero rainfall',
    () async {
      final payload = weatherFixture();
      (payload['daily']['precipitation_sum'] as List)[0] = null;
      final api = ApiService(
        client: MockClient(
          (_) async => http.Response(jsonEncode(payload), 200),
        ),
      );
      addTearDown(api.close);
      final weather = await api.getLiveWeather(7.3, 125.6);
      expect(weather['rainfall_30d_mm'], isNull);
      expect(weather['rainfall_today_mm'], 7);
    },
  );

  test(
    'forecast uses provider time, excludes tomorrow from daily totals, converts wind',
    () async {
      final api = ApiService(
        client: MockClient((request) async {
          expect(request.url.queryParameters['forecast_days'], '2');
          return http.Response(jsonEncode(weatherFixture()), 200);
        }),
      );
      addTearDown(api.close);
      final result = await api.getLiveWeather(7.3, 125.6);
      expect(result['rain_next_6h_mm'], 6);
      expect(result['rain_next_3h_mm'], 3);
      expect(result['rainfall_today_mm'], 7);
      expect(result['rainfall_30d_mm'], 30);
      expect(result['wind_speed_kmh'], 36);
      expect(result['wind_speed_ms'], 10);
    },
  );

  test('provider failure falls back to backend once', () async {
    var calls = 0;
    final api = ApiService(
      client: MockClient((request) async {
        calls++;
        if (request.url.host == 'api.open-meteo.com') {
          return http.Response('Unavailable', 503);
        }
        expect(request.url.path, '/api/mobile/weather');
        return http.Response('{"rainfall_today_mm":7,"temperature_c":28}', 200);
      }),
    );
    addTearDown(api.close);
    expect((await api.getLiveWeather(7.3, 125.6))['temperature_c'], 28);
    expect(calls, 2);
  });

  test('login persists only a valid token', () async {
    final api = ApiService(
      client: MockClient(
        (request) async =>
            http.Response('{"token":"test-token","user":{"id":1}}', 200),
      ),
    );
    addTearDown(api.close);
    await api.login('farmer@example.com', 'password');
    expect(await api.getToken(), 'test-token');
  });

  test('login with missing token is rejected', () async {
    final api = ApiService(
      client: MockClient((request) async => http.Response('{}', 200)),
    );
    addTearDown(api.close);
    await expectLater(
      api.login('farmer@example.com', 'password'),
      throwsFormatException,
    );
    expect(await api.getToken(), isNull);
  });

  test(
    'analysis sends polygon, season and farm once without altering backend rainfall',
    () async {
      SharedPreferences.setMockInitialValues({'token': 'test-token'});
      var calls = 0;
      final api = ApiService(
        client: MockClient((request) async {
          calls++;
          expect(request.method, 'POST');
          expect(request.headers['Authorization'], 'Bearer test-token');
          final body = jsonDecode(request.body) as Map;
          expect(body['farm_id'], 4);
          expect(body['intended_planting_month'], 5);
          expect((body['polygon'] as List).length, 3);
          return http.Response('{"session_id":42,"rainfall_mm":123}', 200);
        }),
      );
      addTearDown(api.close);
      final result = await api.analyzePolygon(
        [
          {'lat': 7.30, 'lng': 125.60},
          {'lat': 7.31, 'lng': 125.60},
          {'lat': 7.30, 'lng': 125.61},
        ],
        farmId: 4,
        intendedPlantingMonth: 5,
      );
      expect(result['rainfall_mm'], 123);
      expect(result['session_id'], 42);
      expect(calls, 1);
    },
  );
}
