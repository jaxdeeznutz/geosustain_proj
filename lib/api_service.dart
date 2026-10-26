import 'dart:async';
import 'session_token_store.dart';
import 'boundary_draft_store.dart';
import 'offline_farm_store.dart';
import 'federated_identity.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

class ApiService {
  // API base URL is injected when needed:
  // flutter build apk --release --dart-define=API_BASE_URL=https://your-render-url.onrender.com
  // Default is the Render backend so Edge/Web/Android use the same source of truth.
  static const String _definedBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    final selected =
        (_definedBaseUrl.isNotEmpty
                ? _definedBaseUrl
                : 'https://geosustain.onrender.com')
            .replaceFirst(RegExp(r'/+$'), '');
    final url = Uri.tryParse(selected);
    if (kReleaseMode &&
        (url == null ||
            url.scheme != 'https' ||
            url.host.isEmpty ||
            url.userInfo.isNotEmpty)) {
      throw StateError('The release requires a secure HTTPS service address.');
    }
    return selected;
  }

  // Injectable transport permits API contract tests without a live account.
  ApiService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  void close() => _client.close();

  final _tokenStore = SessionTokenStore();
  Future<String?> getToken() => _tokenStore.read();
  Future<void> saveToken(String token) => _tokenStore.write(token);

  Future<void> logout() async {
    final token = await getToken();
    if (token != null) {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/mobile/logout'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode >= 400 && response.statusCode != 401) {
        throw ApiException(
          response.statusCode,
          'Sign-out could not be confirmed. Reconnect and try again.',
        );
      }
    }
    await clearLocalSession();
  }

  /// Use after server-confirmed account closure or an already rejected session.
  Future<void> clearLocalSession() async {
    await _tokenStore.clear();
    await FirebaseIdentity.signOut();
    await BoundaryDraftStore.clearForSignOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('account_id');
    for (final key
        in prefs
            .getKeys()
            .where(
              (k) =>
                  k.startsWith('geosustain_pending_') ||
                  k.startsWith('geosustain_draft_'),
            )
            .toList()) {
      await prefs.remove(key);
    }
  }

  Map<String, dynamic> _decodeJson(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unexpected server response.');
      }
      return decoded;
    } on FormatException {
      if (response.statusCode < 400) {
        throw const FormatException(
          'The server returned an invalid response. Please try again.',
        );
      }
      return <String, dynamic>{
        'error':
            'Server request failed (HTTP ${response.statusCode}). Please try again.',
      };
    }
  }

  String _errorMessage(Map<String, dynamic> data, String fallback) {
    final detail = data['detail'];
    if (detail is Map && detail['message'] != null) {
      return '${detail['message']}';
    }
    if (detail is List) {
      return detail.map((e) => e is Map ? e['msg'] ?? fallback : e).join('\n');
    }
    if (detail != null) return detail.toString();
    if (data['error'] != null) return data['error'].toString();
    final errors = data['errors'];
    if (errors is List) return errors.join('\n');
    return fallback;
  }

  /// Render free tier can cold-start for 30–60s; retry instead of failing immediately.
  Future<T> _withRenderWarmupRetry<T>(
    Future<T> Function() request, {
    int attempts = 3,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final value = await request().timeout(timeout);
        if (value is http.Response &&
            attempt < attempts - 1 &&
            ([502, 503, 504].contains(value.statusCode) ||
                (value.statusCode == 200 &&
                    (value.headers['content-type'] ?? '').contains(
                      'text/html',
                    )))) {
          await Future<void>.delayed(Duration(seconds: 2 + attempt * 2));
          continue;
        }
        return value;
      } on http.ClientException catch (e) {
        lastError = e;
        if (attempt < attempts - 1) {
          await Future<void>.delayed(Duration(seconds: 2 + attempt * 2));
        }
      } on TimeoutException catch (e) {
        lastError = e;
        if (attempt < attempts - 1) {
          await Future<void>.delayed(Duration(seconds: 2 + attempt * 2));
        }
      }
    }
    throw lastError ??
        TimeoutException('Request timed out after $attempts attempts');
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/mobile/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email.trim().toLowerCase(),
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        response.statusCode == 401
            ? 'Invalid email or password'
            : _errorMessage(data, 'Login failed'),
      );
    }
    return _acceptLogin(data);
  }

  Future<Map<String, dynamic>> _acceptLogin(Map<String, dynamic> data) async {
    final token = data['token'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('The server did not return a login token.');
    }
    await saveToken(token);
    final prefs = await SharedPreferences.getInstance();
    if (data['user'] is Map && data['user']['id'] != null) {
      await prefs.setString('account_id', '${data['user']['id']}');
      try {
        await OfflineFarmStore.cacheIdentity(
          Map<String, dynamic>.from(data['user']),
        );
      } catch (_) {
        /* Offline entry will report unavailable storage. */
      }
    }
    return data;
  }

  Future<Map<String, dynamic>> _identityPost(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) async {
    final token = authenticated ? await getToken() : null;
    if (authenticated && token == null) {
      throw const ApiException(401, 'Sign in again to continue.');
    }
    final response = await _client
        .post(
          Uri.parse('$baseUrl$path'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 45));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Unable to complete verification.'),
      );
    }
    if (authenticated && await getToken() != token) {
      throw const ApiException(
        409,
        'Account changed. Sign in again before continuing.',
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> googleLogin(String idToken) async =>
      _acceptLogin(
        await _identityPost('/api/mobile/auth/google', {
          'id_token': idToken,
        }, authenticated: false),
      );
  Future<Map<String, dynamic>> linkGoogle(
    String idToken,
    String password,
  ) async =>
      (await _identityPost('/api/mobile/auth/link-google', {
            'id_token': idToken,
            'current_password': password,
          }))['user']
          as Map<String, dynamic>;
  Future<Map<String, dynamic>> startPhoneVerification(String phone) =>
      _identityPost('/api/mobile/phone-verification/start', {
        'phone_number': phone,
      });
  Future<Map<String, dynamic>> finishPhoneVerification(
    String ticket,
    String idToken,
  ) async =>
      (await _identityPost('/api/mobile/phone-verification/complete', {
            'ticket': ticket,
            'id_token': idToken,
          }))['user']
          as Map<String, dynamic>;
  Future<Map<String, dynamic>> startPasswordReset(String email) =>
      _identityPost('/api/mobile/password-reset/start', {
        'email': email.trim().toLowerCase(),
      }, authenticated: false);
  Future<Map<String, dynamic>> finishPasswordReset(
    String ticket,
    String code,
    String password,
  ) => _identityPost('/api/mobile/password-reset/complete', {
    'ticket': ticket,
    'code': code,
    'new_password': password,
  }, authenticated: false);

  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    String role = 'farmer',
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/mobile/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': username,
            'email': email.trim().toLowerCase(),
            'password': password,
            'role': role,
          }),
        )
        .timeout(const Duration(seconds: 90));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Registration failed'),
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> emailVerification(
    String ticket, {
    String? code,
  }) async {
    final response = await _client
        .post(
          Uri.parse(
            '$baseUrl/api/mobile/${code == null ? 'resend-verification' : 'verify-email'}',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'ticket': ticket, 'code': ?code}),
        )
        .timeout(const Duration(seconds: 30));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Email verification failed'),
      );
    }
    return data;
  }

  Future<String> reverseGeocodePlace(double lat, double lon) async {
    final token = await getToken();
    final uri = Uri.parse(
      '$baseUrl/api/mobile/reverse-geocode?lat=$lat&lon=$lon',
    );
    final response = await _client
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Could not look up place name'),
      );
    }
    return '${data['place_name'] ?? ''}'.trim();
  }

  Future<Map<String, dynamic>> analyzePoint(
    double lat,
    double lon, {
    String? placeName,
    int? intendedPlantingMonth,
  }) async {
    return _postAnalysis({
      'lat': lat,
      'lon': lon,
      if (placeName != null && placeName.isNotEmpty) 'place_name': placeName,
      'intended_planting_month': ?intendedPlantingMonth,
    });
  }

  Future<Map<String, dynamic>> analyzePolygon(
    List<Map<String, double>> polygon, {
    String? placeName,
    int? intendedPlantingMonth,
    int? farmId,
  }) async {
    return _postAnalysis({
      'polygon': polygon,
      if (placeName != null && placeName.isNotEmpty) 'place_name': placeName,
      'intended_planting_month': ?intendedPlantingMonth,
      'farm_id': ?farmId,
    });
  }

  static String newRequestId() {
    final random = math.Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<String> _requestKey(
    String operation,
    Map<String, dynamic> payload, {
    String? preferredKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key =
        'geosustain_pending_${prefs.getString('account_id') ?? 'session'}_$operation';
    final body = jsonEncode(payload);
    final pending = _pendingRequests(prefs.getString(key));
    for (final request in pending) {
      if (request['body'] == body) return request['key'] as String;
    }
    final id = preferredKey ?? newRequestId();
    pending.add({'body': body, 'key': id});
    await prefs.setString(key, jsonEncode({'requests': pending}));
    return id;
  }

  List<Map<String, dynamic>> _pendingRequests(String? value) {
    if (value == null) return [];
    try {
      final decoded = jsonDecode(value) as Map;
      final rows = decoded['requests'] ?? [decoded];
      return (rows as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .where((r) => r['key'] is String && r['body'] is String)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _completeRequest(
    String operation,
    String requestId,
    String? token,
  ) async {
    if (await getToken() != token) return;
    final prefs = await SharedPreferences.getInstance();
    final key =
        'geosustain_pending_${prefs.getString('account_id') ?? 'session'}_$operation';
    final pending = _pendingRequests(prefs.getString(key))
      ..removeWhere((r) => r['key'] == requestId);
    if (pending.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, jsonEncode({'requests': pending}));
    }
  }

  Future<Map<String, dynamic>> _analysisStatus(
    String requestId,
    String? token,
  ) async {
    final response = await _client
        .get(
          Uri.parse(
            '$baseUrl/api/mobile/analysis-requests/${Uri.encodeComponent(requestId)}',
          ),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 30));
    final data = _decodeJson(response);
    if (response.statusCode == 404) {
      throw const ApiException(
        503,
        'The analysis service needs an update. Please contact the project team.',
      );
    }
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Could not check the analysis. Try again shortly.'),
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> _waitForAnalysis(
    String key,
    String? token,
    Map<String, dynamic> status,
  ) async {
    for (var attempt = 0; attempt < 60; attempt++) {
      if (await getToken() != token) {
        throw const ApiException(
          401,
          'Your session has changed. Sign in again.',
        );
      }
      if (status['status'] == 'completed' && status['analysis'] is Map) {
        return Map<String, dynamic>.from(status['analysis']);
      }
      if (status['status'] != 'processing') {
        throw const ApiException(
          503,
          'The analysis stopped before saving. Try again.',
        );
      }
      await Future<void>.delayed(const Duration(seconds: 5));
      status = await _analysisStatus(key, token);
    }
    throw const ApiException(
      202,
      'Analysis is still running. Tap Check analysis to retrieve its result.',
    );
  }

  Future<Map<String, dynamic>> _postAnalysis(
    Map<String, dynamic> payload,
  ) async {
    final timer = Stopwatch()..start();
    try {
      final result = await _performAnalysisRequest(payload);
      if (kDebugMode) {
        debugPrint(
          'Analysis completed elapsed_ms=${timer.elapsedMilliseconds}',
        );
      }
      return result;
    } catch (error) {
      // Never log tokens, request bodies, farm coordinates, or raw exceptions.
      if (kDebugMode) {
        debugPrint(
          'Analysis failed type=${error.runtimeType} status=${error is ApiException ? error.statusCode : 'transport_or_parse'} elapsed_ms=${timer.elapsedMilliseconds}',
        );
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _performAnalysisRequest(
    Map<String, dynamic> payload,
  ) async {
    final token = await getToken();
    final key = await _requestKey('analysis', payload);
    // Recover a completed/in-flight request before attempting any new POST.
    final prior = await _analysisStatus(key, token);
    Map<String, dynamic> data;
    if (prior['status'] == 'completed' || prior['status'] == 'processing') {
      data = await _waitForAnalysis(key, token, prior);
    } else if (prior['status'] == 'not_found' || prior['status'] == 'failed') {
      try {
        final response = await _client
            .post(
              Uri.parse('$baseUrl/api/mobile/analysis'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
                'Idempotency-Key': key,
              },
              body: jsonEncode(payload),
            )
            .timeout(const Duration(minutes: 5));
        data = _decodeJson(response);
        if (response.statusCode >= 400) {
          throw ApiException(
            response.statusCode,
            _errorMessage(data, 'Analysis failed. Please try again.'),
          );
        }
        if (response.statusCode == 202) {
          data = await _waitForAnalysis(key, token, data);
        }
      } on http.ClientException {
        final status = await _analysisStatus(key, token);
        if (status['status'] == 'not_found') rethrow;
        data = await _waitForAnalysis(key, token, status);
      } on TimeoutException {
        final status = await _analysisStatus(key, token);
        if (status['status'] == 'not_found') rethrow;
        data = await _waitForAnalysis(key, token, status);
      }
    } else {
      throw const FormatException(
        'Unable to confirm the analysis status. Try again shortly.',
      );
    }
    if (await getToken() != token) {
      throw const ApiException(401, 'Your session has changed. Sign in again.');
    }
    if (data['session_id'] == null ||
        (data['analysis_status'] != null &&
            data['analysis_status'] != 'completed')) {
      throw const FormatException(
        'The analysis has not been saved. Try again shortly.',
      );
    }
    if (payload['farm_id'] != null && data['farm_id'] != payload['farm_id']) {
      throw const FormatException(
        'The server returned a different farm. Refresh your farm and try again.',
      );
    }
    await _completeRequest('analysis', key, token);
    return data;
  }

  Future<Map<String, dynamic>> getFarm(int farmId) async {
    final response = await _client
        .get(
          Uri.parse('$baseUrl/api/mobile/farms/$farmId'),
          headers: {'Authorization': 'Bearer ${await getToken()}'},
        )
        .timeout(const Duration(seconds: 30));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Could not load this farm.'),
      );
    }
    return Map<String, dynamic>.from(data['farm']);
  }

  Future<List<Map<String, dynamic>>> getFarms({
    bool includeArchived = false,
  }) async {
    final token = await getToken();
    final response = await _client
        .get(
          Uri.parse(
            '$baseUrl/api/mobile/farms?include_archived=$includeArchived',
          ),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Could not load farms'),
      );
    }
    final raw = data['farms'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> createFarm({
    required String farmName,
    required List<Map<String, double>> polygon,
    String? locationName,
    String mappingMethod = 'manual_draw',
    double? gpsAccuracyM,
    String? requestId,
  }) async {
    final token = await getToken();
    final payload = <String, dynamic>{
      'farm_name': farmName,
      'polygon': polygon,
      'location_name': ?locationName,
      'mapping_method': mappingMethod,
      'gps_accuracy_m': ?gpsAccuracyM,
    };
    final key = await _requestKey('farm', payload, preferredKey: requestId);
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/mobile/farms'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
            'Idempotency-Key': key,
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Could not save farm'),
      );
    }
    if (await getToken() != token) {
      throw const ApiException(401, 'Your session has changed. Sign in again.');
    }
    await _completeRequest('farm', key, token);
    return Map<String, dynamic>.from(data['farm'] as Map);
  }

  Future<Map<String, dynamic>> analysisCoverage(
    List<Map<String, double>> polygon,
  ) async {
    final token = await getToken();
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/mobile/analysis-coverage'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'polygon': polygon}),
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Coverage check unavailable.'),
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> analysisCoverageCatalog() async {
    final token = await getToken();
    final response = await _client
        .get(
          Uri.parse('$baseUrl/api/mobile/analysis-coverage/catalog'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Coverage map unavailable.'),
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> updateFarm(
    int farmId,
    Map<String, dynamic> changes,
  ) async {
    final token = await getToken();
    final response = await _client
        .patch(
          Uri.parse('$baseUrl/api/mobile/farms/$farmId'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(changes),
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Could not update farm'),
      );
    }
    if (await getToken() != token) {
      throw const ApiException(401, 'Your session has changed. Sign in again.');
    }
    return Map<String, dynamic>.from(data['farm'] as Map);
  }

  Future<Map<String, dynamic>> getLiveWeather(double lat, double lon) async {
    // Home live weather should not depend on Render being awake. Try Open-Meteo
    // directly first, then use the backend as backup. This keeps the Home cards
    // from staying blank when Render returns 502 during free-tier cold starts.
    final directFirst = await _fetchOpenMeteoWeatherDirect(lat, lon);
    if (directFirst != null) return directFirst;

    final token = await getToken();
    final uri = Uri.parse('$baseUrl/api/mobile/weather?lat=$lat&lon=$lon');
    final response = await _client
        .get(
          uri,
          headers: {
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 15));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Live weather failed'),
      );
    }

    final hasDailyRain =
        data['rainfall_today_mm'] != null ||
        data['today_rainfall_mm'] != null ||
        data['daily_rainfall_mm'] != null;
    if (!hasDailyRain) {
      final dailyRain = await _fetchTodayRainfall(lat, lon);
      if (dailyRain != null) {
        data['rainfall_today_mm'] = dailyRain;
        data['today_rainfall_mm'] = dailyRain;
        data['daily_rainfall_mm'] = dailyRain;
      }
    }
    return data;
  }

  Future<Map<String, dynamic>?> _fetchOpenMeteoWeatherDirect(
    double lat,
    double lon,
  ) async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon'
        '&current=temperature_2m,relative_humidity_2m,precipitation,rain,weather_code,cloud_cover,wind_speed_10m'
        '&hourly=temperature_2m,precipitation,precipitation_probability,weather_code,wind_speed_10m'
        '&daily=precipitation_sum&past_days=30&forecast_days=2&wind_speed_unit=kmh&timezone=Asia%2FManila',
      );
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode >= 400) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final current = decoded['current'] is Map<String, dynamic>
          ? decoded['current'] as Map<String, dynamic>
          : <String, dynamic>{};
      final daily = decoded['daily'] is Map<String, dynamic>
          ? decoded['daily'] as Map<String, dynamic>
          : <String, dynamic>{};
      final hourly = decoded['hourly'] is Map<String, dynamic>
          ? decoded['hourly'] as Map<String, dynamic>
          : <String, dynamic>{};
      final dailyVals = daily['precipitation_sum'] is List
          ? daily['precipitation_sum'] as List
          : const [];
      final dailyTimes = daily['time'] is List
          ? daily['time'] as List
          : const [];
      final currentTime = current['time']?.toString();
      if (currentTime == null ||
          currentTime.length < 10 ||
          current['temperature_2m'] == null) {
        return null;
      }
      final todayIndex = dailyTimes.indexOf(currentTime.substring(0, 10));
      final todayRain = todayIndex >= 0 && todayIndex < dailyVals.length
          ? _toDouble(dailyVals[todayIndex])
          : null;
      final pastRain = todayIndex >= 30 && todayIndex <= dailyVals.length
          ? dailyVals
                .take(todayIndex)
                .skip(todayIndex - 30)
                .map(_toDouble)
                .toList()
          : <double?>[];
      final monthly = pastRain.length == 30 && pastRain.every((v) => v != null)
          ? pastRain.fold<double>(0, (sum, v) => sum + v!)
          : null;
      final hTime = hourly['time'] is List ? hourly['time'] as List : const [];
      final hRain = hourly['precipitation'] is List
          ? hourly['precipitation'] as List
          : const [];
      final hProb = hourly['precipitation_probability'] is List
          ? hourly['precipitation_probability'] as List
          : const [];
      final hCode = hourly['weather_code'] is List
          ? hourly['weather_code'] as List
          : const [];
      final hWind = hourly['wind_speed_10m'] is List
          ? hourly['wind_speed_10m'] as List
          : const [];
      final hTemp = hourly['temperature_2m'] is List
          ? hourly['temperature_2m'] as List
          : const [];
      final startIndex = _startHourlyIndex(hTime, currentTime);
      final next3Rain = _sumWindow(hRain, startIndex, 3);
      final next6 = _sumWindow(hRain, startIndex, 6);
      final prob3 = _maxWindow(hProb, startIndex, 3);
      final prob6 = _maxWindow(hProb, startIndex, 6);
      final wind6 = _maxWindow(hWind, startIndex, 6);
      final temp6 = _maxWindow(hTemp, startIndex, 6);
      final codes6 = _listWindow(hCode, startIndex, 6);
      return {
        'latitude': lat,
        'longitude': lon,
        'temperature_c': current['temperature_2m'],
        'live_humidity': current['relative_humidity_2m'],
        'rainfall_today_mm': todayRain == null
            ? null
            : double.parse(todayRain.toStringAsFixed(2)),
        'today_rainfall_mm': todayRain == null
            ? null
            : double.parse(todayRain.toStringAsFixed(2)),
        'daily_rainfall_mm': todayRain == null
            ? null
            : double.parse(todayRain.toStringAsFixed(2)),
        'rainfall_mm': monthly == null
            ? null
            : double.parse(monthly.toStringAsFixed(2)),
        'rainfall_monthly_mm': monthly == null
            ? null
            : double.parse(monthly.toStringAsFixed(2)),
        'monthly_rainfall_mm': monthly == null
            ? null
            : double.parse(monthly.toStringAsFixed(2)),
        'rainfall_30d_mm': monthly == null
            ? null
            : double.parse(monthly.toStringAsFixed(2)),
        'current_precipitation_mm': current['precipitation'] ?? current['rain'],
        'rain_next_6h_mm': double.parse(next6.toStringAsFixed(2)),
        'wind_speed_kmh': current['wind_speed_10m'],
        'wind_speed_ms': (_toDouble(current['wind_speed_10m']) ?? 0) / 3.6,
        'cloud_cover_pct': current['cloud_cover'],
        'weather_code': current['weather_code'],
        'weather_description': _weatherCodeLabel(
          _toDouble(current['weather_code'])?.round(),
        ),
        'rain_next_3h_mm': double.parse(next3Rain.toStringAsFixed(2)),
        'rain_probability_next_3h': double.parse(prob3.toStringAsFixed(1)),
        'rain_probability_next_6h': double.parse(prob6.toStringAsFixed(1)),
        'max_wind_next_6h_kmh': double.parse(wind6.toStringAsFixed(1)),
        'max_temp_next_6h_c': double.parse(temp6.toStringAsFixed(1)),
        'weather_codes_next_6h': codes6,
        'weather_updated_at': currentTime,
        'weather_source': 'Open-Meteo direct',
        'weather_is_realtime': true,
      };
    } catch (_) {
      return null;
    }
  }

  int _startHourlyIndex(List times, String currentTime) {
    final now = DateTime.tryParse(currentTime);
    if (now == null) return times.length;
    for (var i = 0; i < times.length; i++) {
      final parsed = DateTime.tryParse('${times[i]}');
      if (parsed != null && !parsed.isBefore(now)) return i;
    }
    return times.length;
  }

  double _sumWindow(List values, int start, int hours) {
    var total = 0.0;
    for (var i = start; i < values.length && i < start + hours; i++) {
      total += _toDouble(values[i]) ?? 0.0;
    }
    return total;
  }

  double _maxWindow(List values, int start, int hours) {
    var maxValue = 0.0;
    for (var i = start; i < values.length && i < start + hours; i++) {
      final n = _toDouble(values[i]) ?? 0.0;
      if (n > maxValue) maxValue = n;
    }
    return maxValue;
  }

  List<int> _listWindow(List values, int start, int hours) {
    final out = <int>[];
    for (var i = start; i < values.length && i < start + hours; i++) {
      final n = _toDouble(values[i]);
      if (n != null) out.add(n.round());
    }
    return out;
  }

  String _weatherCodeLabel(int? code) {
    if (code == null) return 'Live weather';
    if (code == 0) return 'Clear sky';
    if ([1, 2, 3].contains(code)) return 'Partly cloudy';
    if ([45, 48].contains(code)) return 'Foggy';
    if ([51, 53, 55, 56, 57].contains(code)) return 'Drizzle';
    if ([61, 63, 65, 66, 67].contains(code)) return 'Rainy';
    if ([80, 81, 82].contains(code)) return 'Rain showers';
    if ([95, 96, 99].contains(code)) return 'Thunderstorm';
    return 'Live weather';
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  Future<double?> _fetchTodayRainfall(double lat, double lon) async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&daily=precipitation_sum&timezone=Asia%2FManila',
      );
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode >= 400) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final daily = decoded['daily'];
      if (daily is! Map<String, dynamic>) return null;
      final values = daily['precipitation_sum'];
      if (values is List && values.isNotEmpty) {
        final first = values.first;
        return first is num ? first.toDouble() : double.tryParse('$first');
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> getMe() async {
    final token = await getToken();
    final response = await _withRenderWarmupRetry(
      () => _client.get(
        Uri.parse('$baseUrl/api/mobile/me'),
        headers: {'Authorization': 'Bearer $token'},
      ),
      timeout: const Duration(seconds: 45),
    ).timeout(const Duration(seconds: 150));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Profile failed'),
      );
    }
    if (await getToken() != token) {
      throw const ApiException(401, 'Your session has changed. Sign in again.');
    }
    final user = data['user'] is Map<String, dynamic> ? data['user'] : data;
    if (user['id'] != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('account_id', '${user['id']}');
      try {
        await OfflineFarmStore.cacheIdentity(Map<String, dynamic>.from(user));
      } catch (_) {
        /* Online access remains available. */
      }
    }
    return user;
  }

  Future<Map<String, dynamic>> getAnalysis(int sessionId) async {
    final token = await getToken();
    final response = await _client
        .get(
          Uri.parse('$baseUrl/api/mobile/analyses/$sessionId'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Could not load this analysis.'),
      );
    }
    if (await getToken() != token) {
      throw const ApiException(401, 'Your session changed. Sign in again.');
    }
    return Map<String, dynamic>.from(data['analysis'] as Map);
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final token = await getToken();
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/mobile/change-password'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'current_password': currentPassword,
            'new_password': newPassword,
          }),
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Could not change password.'),
      );
    }
    final fresh = data['token'];
    if (fresh is! String || fresh.isEmpty) {
      throw const FormatException('Sign in again using your new password.');
    }
    await saveToken(fresh);
  }

  Future<Map<String, dynamic>> getCounts() async {
    final token = await getToken();
    final response = await _client
        .get(
          Uri.parse('$baseUrl/api/mobile/counts'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Counts failed'),
      );
    }
    return data;
  }

  Future<List<dynamic>> getHistory() => _history();

  Future<Map<String, dynamic>> getWebSummary() =>
      getRecordPage('/api/web/summary');

  Future<List<dynamic>> getFarmHistory(int farmId) => _history(farmId: farmId);

  Future<List<dynamic>> _history({int? farmId}) async {
    final token = await getToken();
    final rows = <dynamic>[];
    bool more = true;
    while (more) {
      final response = await _client
          .get(
            Uri.parse(
              '$baseUrl/api/mobile/history?offset=${rows.length}&limit=50${farmId == null ? '' : '&farm_id=$farmId'}',
            ),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 60));
      final data = _decodeJson(response);
      if (response.statusCode >= 400) {
        throw ApiException(
          response.statusCode,
          _errorMessage(data, 'History failed'),
        );
      }
      final page = data['history'] as List<dynamic>;
      rows.addAll(page);
      more = data['has_more'] == true && page.isNotEmpty;
    }
    return rows;
  }

  Future<Map<String, dynamic>> submitAnalysisToPlanner(int sessionId) async {
    final token = await getToken();
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/mobile/submit-to-planner'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'session_id': sessionId}),
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Submission failed'),
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> saveAnalysis(int sessionId) async {
    final token = await getToken();
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/mobile/save-analysis'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'session_id': sessionId}),
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Save failed'),
      );
    }
    return data;
  }

  Future<List<dynamic>> _pagedList(
    String path,
    String key, {
    Map<String, String> parameters = const {},
  }) async {
    final token = await getToken();
    final rows = <dynamic>[];
    var offset = 0;
    while (true) {
      final uri = Uri.parse('$baseUrl$path').replace(
        queryParameters: {...parameters, 'offset': '$offset', 'limit': '50'},
      );
      final response = await _client
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 60));
      final data = _decodeJson(response);
      if (response.statusCode >= 400) {
        throw ApiException(
          response.statusCode,
          _errorMessage(data, 'Could not load records'),
        );
      }
      if (await getToken() != token) {
        throw const ApiException(401, 'Your session changed. Sign in again.');
      }
      final batch = data[key] as List;
      rows.addAll(batch);
      if (data['has_more'] != true) break;
      if (batch.isEmpty) {
        throw const FormatException('Invalid empty continuation page.');
      }
      offset += batch.length;
    }
    return rows;
  }

  Future<Map<String, dynamic>> getRecordPage(
    String path, {
    int offset = 0,
    String search = '',
    Map<String, String> parameters = const {},
  }) async {
    final token = await getToken();
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: {
        'offset': '$offset',
        'limit': '50',
        'q': search,
        ...parameters,
      },
    );
    final response = await _client
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Could not load records'),
      );
    }
    if (await getToken() != token) {
      throw const ApiException(401, 'Your session changed. Sign in again.');
    }
    return data;
  }

  Future<void> markNotificationRead(
    int id, {
    bool bySession = false,
    bool activity = false,
  }) async {
    final token = await getToken();
    final response = await _client
        .post(
          Uri.parse(
            '$baseUrl/api/mobile/${activity
                ? 'activity'
                : bySession
                ? 'reviews'
                : 'notifications'}/$id/read',
          ),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(
          _decodeJson(response),
          'Could not mark this notification read.',
        ),
      );
    }
    if (await getToken() != token) {
      throw const ApiException(401, 'Your session changed. Sign in again.');
    }
  }

  Future<void> markAllActivityRead() async {
    final token = await getToken();
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/mobile/activity/read-all'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(_decodeJson(response), 'Could not update notifications.'),
      );
    }
    if (await getToken() != token) {
      throw const ApiException(401, 'Your session changed. Sign in again.');
    }
  }

  Future<void> recoverPassword(String token, String password) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/mobile/recover-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'recovery_token': token, 'new_password': password}),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(_decodeJson(response), 'Recovery failed'),
      );
    }
  }

  Future<void> setPushSubscription(
    String deviceToken,
    bool enabled, {
    String? expectedToken,
  }) async {
    final token = await getToken();
    if (expectedToken != null && token != expectedToken) {
      throw const ApiException(401, 'Your session changed. Sign in again.');
    }
    final response = await _client
        .put(
          Uri.parse('$baseUrl/api/mobile/push-subscription'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'token': deviceToken,
            'enabled': enabled,
            'platform': kIsWeb ? 'web' : 'android',
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(_decodeJson(response), 'Push registration failed'),
      );
    }
  }

  Future<String> issuePasswordRecovery(int userId) async {
    final token = await getToken();
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/admin/users/$userId/recovery'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'identity_verified': true}),
        )
        .timeout(const Duration(seconds: 30));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Could not issue recovery'),
      );
    }
    return data['recovery_token'] as String;
  }

  Future<List<dynamic>> getSavedAnalyses() =>
      _pagedList('/api/mobile/saved', 'saved');

  Future<Map<String, dynamic>> createReport(
    int sessionId, {
    String? title,
  }) async {
    final token = await getToken();
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/mobile/report'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'session_id': sessionId, 'title': title}),
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Report failed'),
      );
    }
    return data;
  }

  Future<List<dynamic>> getReports() =>
      _pagedList('/api/mobile/reports', 'reports');

  Future<Map<String, dynamic>> updateProfile({
    required String username,
    String? role,
    String? location,
    String? profilePhotoBase64,
    String? phoneNumber,
  }) async {
    final token = await getToken();
    final response = await _client
        .put(
          Uri.parse('$baseUrl/api/mobile/me'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'username': username,
            'location': ?location,
            'profile_photo': ?profilePhotoBase64,
            'phone_number': ?phoneNumber,
          }),
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Profile update failed'),
      );
    }
    return data['user'] is Map<String, dynamic> ? data['user'] : data;
  }

  Future<void> deactivateAccount() async {
    final token = await getToken();
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/mobile/me/deactivate'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Deactivate failed'),
      );
    }
    await logout();
  }

  Future<void> closeWebAccount({
    required bool delete,
    String? password,
    String? googleProof,
  }) async {
    final token = await getToken();
    await _identityPost('/api/web/account-action', {
      'action': delete ? 'delete' : 'deactivate',
      'current_password': ?password,
      'firebase_id_token': ?googleProof,
    });
    if (await getToken() != token) {
      throw const ApiException(
        409,
        'The session changed. Refresh before continuing.',
      );
    }
    if (delete) await OfflineFarmStore.deleteCurrentAccountData();
    await clearLocalSession();
  }

  Future<void> deleteAccount() async {
    final token = await getToken();
    final response = await _client
        .delete(
          Uri.parse('$baseUrl/api/mobile/me'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Delete account failed'),
      );
    }
    await OfflineFarmStore.deleteCurrentAccountData();
    await logout();
  }

  // ---------------------------------------------------------------------
  // Planner verification workflow
  // ---------------------------------------------------------------------
  Future<List<dynamic>> getPlannerQueue({String status = 'pending'}) =>
      _pagedList('/api/planner/queue', 'queue', parameters: {'status': status});

  Future<Map<String, dynamic>> getPlannerSessionDetail(int sessionId) async {
    final token = await getToken();
    final response = await _client
        .get(
          Uri.parse('$baseUrl/api/planner/session/$sessionId'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Could not load analysis details'),
      );
    }
    final session = data['session'];
    return session is Map
        ? Map<String, dynamic>.from(session)
        : Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> getPlannerCounts() async {
    final token = await getToken();
    final response = await _client
        .get(
          Uri.parse('$baseUrl/api/planner/counts'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Could not load queue counts'),
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> verifySubmission(
    int sessionId,
    String status, {
    String? notes,
  }) async {
    final token = await getToken();
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/planner/verify'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'session_id': sessionId,
            'status': status,
            'notes': ?notes,
          }),
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw Exception(
        _errorMessage(data, 'Could not update verification status'),
      );
    }
    return data['session'] is Map<String, dynamic> ? data['session'] : data;
  }

  Future<Map<String, dynamic>> getAdminDashboard() async {
    final token = await getToken();
    final response = await _client
        .get(
          Uri.parse('$baseUrl/api/admin/dashboard'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Admin dashboard failed'),
      );
    }
    return Map<String, dynamic>.from(data['stats'] ?? const {});
  }

  Future<List<dynamic>> getAdminUsers() =>
      _pagedList('/api/admin/users', 'users');

  Future<Map<String, dynamic>> updateAdminUser(
    int userId, {
    String? role,
    bool? isActive,
  }) async {
    final token = await getToken();
    final response = await _client
        .patch(
          Uri.parse('$baseUrl/api/admin/users/$userId'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'role': ?role, 'is_active': ?isActive}),
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Could not update user'),
      );
    }
    return Map<String, dynamic>.from(data['user'] ?? const {});
  }

  Future<List<dynamic>> getAdminAnalyses() =>
      _pagedList('/api/admin/analyses', 'analyses');

  Future<List<dynamic>> getAdminCrops() async {
    final token = await getToken();
    final response = await _client
        .get(
          Uri.parse('$baseUrl/api/admin/crops'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Could not load crop reference'),
      );
    }
    return List<dynamic>.from(data['crops'] ?? const []);
  }

  Future<Map<String, dynamic>> updateAdminCrop(
    String cropKey, {
    String? label,
    String? growthCycle,
    String? estYield,
    String? suitabilityNote,
    bool? isActive,
  }) async {
    final token = await getToken();
    final response = await _client
        .patch(
          Uri.parse('$baseUrl/api/admin/crops/${Uri.encodeComponent(cropKey)}'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'label': ?label,
            'growth_cycle': ?growthCycle,
            'est_yield': ?estYield,
            'suitability_note': ?suitabilityNote,
            'is_active': ?isActive,
          }),
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessage(data, 'Could not update crop'),
      );
    }
    return Map<String, dynamic>.from(data['crop'] ?? const {});
  }

  Future<List<dynamic>> getAdminAuditLogs() =>
      _pagedList('/api/admin/audit-logs', 'logs');
}
