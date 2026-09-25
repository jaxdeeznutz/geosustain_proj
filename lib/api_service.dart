import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // API base URL is injected when needed:
  // flutter build apk --release --dart-define=API_BASE_URL=https://your-render-url.onrender.com
  // Default is the Render backend so Edge/Web/Android use the same source of truth.
  static const String _definedBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl =>
      (_definedBaseUrl.isNotEmpty
              ? _definedBaseUrl
              : 'https://geosustain.onrender.com')
          .replaceFirst(RegExp(r'/+$'), '');

  // Injectable transport permits API contract tests without a live account.
  ApiService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  void close() => _client.close();

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
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
        return await request().timeout(timeout);
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
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw Exception(_errorMessage(data, 'Login failed'));
    }
    final token = data['token'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('The server did not return a login token.');
    }
    await saveToken(token);
    return data;
  }

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
            'email': email,
            'password': password,
            'role': role,
          }),
        )
        .timeout(const Duration(seconds: 90));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw Exception(_errorMessage(data, 'Registration failed'));
    }
    return data;
  }

  Future<Map<String, dynamic>> verifyEmail({
    required String email,
    required String code,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/mobile/verify-email'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'code': code}),
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw Exception(_errorMessage(data, 'Verification failed'));
    }
    final token = data['token'];
    if (token != null) await saveToken('$token');
    return data;
  }

  Future<Map<String, dynamic>> resendVerificationCode(String email) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/mobile/resend-verification'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email}),
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw Exception(_errorMessage(data, 'Could not resend the code'));
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
      throw Exception(_errorMessage(data, 'Could not look up place name'));
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

  Future<Map<String, dynamic>> _postAnalysis(
    Map<String, dynamic> payload,
  ) async {
    final token = await getToken();
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/mobile/analysis'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(minutes: 5));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw Exception(_errorMessage(data, 'Analysis failed'));
    }

    // Analysis rainfall now comes from the backend CHIRPS/GEE 30-day source.
    // Do not override it here with Open-Meteo, because Open-Meteo can return
    // the same coarse-grid value (for example 314.2 mm) across nearby Panabo
    // points. The backend remains the source of truth for Analyze rainfall.
    return data;
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
      throw Exception(_errorMessage(data, 'Could not load farms'));
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
  }) async {
    final token = await getToken();
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/mobile/farms'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'farm_name': farmName,
            'polygon': polygon,
            'location_name': ?locationName,
            'mapping_method': mappingMethod,
            'gps_accuracy_m': ?gpsAccuracyM,
          }),
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw Exception(_errorMessage(data, 'Could not save farm'));
    }
    return Map<String, dynamic>.from(data['farm'] as Map);
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
      throw Exception(_errorMessage(data, 'Could not update farm'));
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
      throw Exception(_errorMessage(data, 'Live weather failed'));
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
      timeout: const Duration(seconds: 20),
    ).timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw Exception(_errorMessage(data, 'Profile failed'));
    }
    return data['user'] is Map<String, dynamic> ? data['user'] : data;
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
      throw Exception(_errorMessage(data, 'Counts failed'));
    }
    return data;
  }

  Future<List<dynamic>> getHistory() async {
    final token = await getToken();
    final response = await _client
        .get(
          Uri.parse('$baseUrl/api/mobile/history'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw Exception(_errorMessage(data, 'History failed'));
    }
    return data['history'] as List<dynamic>;
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
      throw Exception(_errorMessage(data, 'Submission failed'));
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
      throw Exception(_errorMessage(data, 'Save failed'));
    }
    return data;
  }

  Future<List<dynamic>> getSavedAnalyses() async {
    final token = await getToken();
    final response = await _client
        .get(
          Uri.parse('$baseUrl/api/mobile/saved'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw Exception(_errorMessage(data, 'Saved analyses failed'));
    }
    return data['saved'] as List<dynamic>;
  }

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
      throw Exception(_errorMessage(data, 'Report failed'));
    }
    return data;
  }

  Future<List<dynamic>> getReports() async {
    final token = await getToken();
    final response = await _client
        .get(
          Uri.parse('$baseUrl/api/mobile/reports'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw Exception(_errorMessage(data, 'Reports failed'));
    }
    return data['reports'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> updateProfile({
    required String username,
    required String role,
    String? location,
    String? profilePhotoBase64,
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
            'role': role,
            'location': ?location,
            'profile_photo': ?profilePhotoBase64,
          }),
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw Exception(_errorMessage(data, 'Profile update failed'));
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
      throw Exception(_errorMessage(data, 'Deactivate failed'));
    }
    await logout();
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
      throw Exception(_errorMessage(data, 'Delete account failed'));
    }
    await logout();
  }

  // ---------------------------------------------------------------------
  // Planner verification workflow
  // ---------------------------------------------------------------------
  Future<List<dynamic>> getPlannerQueue({String status = 'pending'}) async {
    final token = await getToken();
    final response = await _client
        .get(
          Uri.parse('$baseUrl/api/planner/queue?status=$status'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw Exception(_errorMessage(data, 'Could not load verification queue'));
    }
    return data['queue'] as List<dynamic>;
  }

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
      throw Exception(_errorMessage(data, 'Could not load analysis details'));
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
      throw Exception(_errorMessage(data, 'Could not load queue counts'));
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
      throw Exception(_errorMessage(data, 'Admin dashboard failed'));
    }
    return Map<String, dynamic>.from(data['stats'] ?? const {});
  }

  Future<List<dynamic>> getAdminUsers() async {
    final token = await getToken();
    final response = await _client
        .get(
          Uri.parse('$baseUrl/api/admin/users'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw Exception(_errorMessage(data, 'Could not load users'));
    }
    return List<dynamic>.from(data['users'] ?? const []);
  }

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
      throw Exception(_errorMessage(data, 'Could not update user'));
    }
    return Map<String, dynamic>.from(data['user'] ?? const {});
  }

  Future<List<dynamic>> getAdminAnalyses() async {
    final token = await getToken();
    final response = await _client
        .get(
          Uri.parse('$baseUrl/api/admin/analyses'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw Exception(_errorMessage(data, 'Could not load analyses'));
    }
    return List<dynamic>.from(data['analyses'] ?? const []);
  }

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
      throw Exception(_errorMessage(data, 'Could not load crop reference'));
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
      throw Exception(_errorMessage(data, 'Could not update crop'));
    }
    return Map<String, dynamic>.from(data['crop'] ?? const {});
  }

  Future<List<dynamic>> getAdminAuditLogs() async {
    final token = await getToken();
    final response = await _client
        .get(
          Uri.parse('$baseUrl/api/admin/audit-logs'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw Exception(_errorMessage(data, 'Could not load audit logs'));
    }
    return List<dynamic>.from(data['logs'] ?? const []);
  }
}
