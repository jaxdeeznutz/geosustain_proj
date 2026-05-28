import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // API base URL is injected when needed:
  // flutter build apk --release --dart-define=API_BASE_URL=https://your-render-url.onrender.com
  // Default is the Render backend so Edge/Web/Android use the same source of truth.
  static const String _definedBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_definedBaseUrl.isNotEmpty) return _definedBaseUrl;

    // Render is the single online backend for Web, Edge, Android, and APK builds.
    if (kIsWeb) return 'https://geosustain.onrender.com';
    if (defaultTargetPlatform == TargetPlatform.android) return 'https://geosustain.onrender.com';
    return 'https://geosustain.onrender.com';
  }

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
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{'data': decoded};
    } catch (_) {
      return <String, dynamic>{'error': response.body.isEmpty ? 'No response from server.' : response.body};
    }
  }

  String _errorMessage(Map<String, dynamic> data, String fallback) {
    if (data['detail'] != null) return data['detail'].toString();
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
    throw lastError ?? TimeoutException('Request timed out after $attempts attempts');
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/mobile/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = _decodeJson(response);
    if (response.statusCode >= 400) throw Exception(_errorMessage(data, 'Login failed'));
    await saveToken(data['token']);
    return data;
  }

  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    String role = 'farmer',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/mobile/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'email': email, 'password': password, 'role': role}),
    );
    final data = _decodeJson(response);
    if (response.statusCode >= 400) throw Exception(_errorMessage(data, 'Register failed'));
    // Legacy backend register is kept only for compatibility.
    return data;
  }

  Future<Map<String, dynamic>> completeFirebaseEmailRegistration({
    required String username,
    required String email,
    required String password,
    String role = 'farmer',
  }) async {
    final response = await _withRenderWarmupRetry(
      () => http.post(
        Uri.parse('$baseUrl/api/mobile/firebase-email-register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'email': email,
          'password': password,
          'role': role,
        }),
      ),
    );
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw Exception(_errorMessage(data, 'Could not complete registration'));
    }
    final token = data['token'];
    if (token != null) await saveToken('$token');
    return data;
  }

  Future<Map<String, dynamic>> googleLoginWithFirebaseIdToken(String idToken, {String role = 'farmer'}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/mobile/google-login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id_token': idToken, 'role': role}),
    );
    final data = _decodeJson(response);
    if (response.statusCode >= 400) throw Exception(_errorMessage(data, 'Google login failed'));
    final token = data['token'];
    if (token != null) await saveToken('$token');
    return data;
  }

  Future<String> reverseGeocodePlace(double lat, double lon) async {
    final token = await getToken();
    final uri = Uri.parse('$baseUrl/api/mobile/reverse-geocode?lat=$lat&lon=$lon');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw Exception(_errorMessage(data, 'Could not look up place name'));
    }
    return '${data['place_name'] ?? ''}'.trim();
  }

  Future<Map<String, dynamic>> analyzePoint(double lat, double lon, {String? placeName}) async {
    return _postAnalysis({
      'lat': lat,
      'lon': lon,
      if (placeName != null && placeName.isNotEmpty) 'place_name': placeName,
    });
  }

  Future<Map<String, dynamic>> analyzePolygon(
    List<Map<String, double>> polygon, {
    String? placeName,
  }) async {
    return _postAnalysis({
      'polygon': polygon,
      if (placeName != null && placeName.isNotEmpty) 'place_name': placeName,
    });
  }

  Future<Map<String, dynamic>> _postAnalysis(Map<String, dynamic> payload) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/api/mobile/analysis'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode(payload),
    );
    final data = _decodeJson(response);
    if (response.statusCode >= 400) throw Exception(_errorMessage(data, 'Analysis failed'));

    // Analysis rainfall now comes from the backend CHIRPS/GEE 30-day source.
    // Do not override it here with Open-Meteo, because Open-Meteo can return
    // the same coarse-grid value (for example 314.2 mm) across nearby Panabo
    // points. The backend remains the source of truth for Analyze rainfall.
    return data;
  }


  Future<Map<String, dynamic>> getLiveWeather(double lat, double lon) async {
    // Home live weather should not depend on Render being awake. Try Open-Meteo
    // directly first, then use the backend as backup. This keeps the Home cards
    // from staying blank when Render returns 502 during free-tier cold starts.
    final directFirst = await _fetchOpenMeteoWeatherDirect(lat, lon);
    if (directFirst != null) return directFirst;

    final token = await getToken();
    final uri = Uri.parse('$baseUrl/api/mobile/weather?lat=$lat&lon=$lon');
    final response = await http
        .get(
          uri,
          headers: {if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));
    final data = _decodeJson(response);
    if (response.statusCode >= 400) {
      final directRetry = await _fetchOpenMeteoWeatherDirect(lat, lon);
      if (directRetry != null) return directRetry;
      throw Exception(_errorMessage(data, 'Live weather failed'));
    }

    // Keep the Home screen live even if the deployed backend has cached or
    // older weather values. Direct Open-Meteo data overrides weather fields.
    final direct = await _fetchOpenMeteoWeatherDirect(lat, lon);
    if (direct != null) data.addAll(direct);

    final hasDailyRain = data['rainfall_today_mm'] != null ||
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

  Future<Map<String, dynamic>?> _fetchOpenMeteoWeatherDirect(double lat, double lon) async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon'
        '&current=temperature_2m,relative_humidity_2m,precipitation,rain,weather_code,cloud_cover,wind_speed_10m'
        '&hourly=temperature_2m,precipitation,precipitation_probability,weather_code,wind_speed_10m'
        '&daily=precipitation_sum&past_days=30&forecast_days=1&timezone=Asia%2FManila',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode >= 400) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final current = decoded['current'] is Map<String, dynamic> ? decoded['current'] as Map<String, dynamic> : <String, dynamic>{};
      final daily = decoded['daily'] is Map<String, dynamic> ? decoded['daily'] as Map<String, dynamic> : <String, dynamic>{};
      final hourly = decoded['hourly'] is Map<String, dynamic> ? decoded['hourly'] as Map<String, dynamic> : <String, dynamic>{};
      final dailyVals = daily['precipitation_sum'] is List ? daily['precipitation_sum'] as List : const [];
      final todayRain = dailyVals.isNotEmpty ? _toDouble(dailyVals.last) ?? 0.0 : 0.0;
      final monthly = dailyVals.isNotEmpty
          ? dailyVals.take(30).fold<double>(0.0, (sum, v) => sum + (_toDouble(v) ?? 0.0))
          : 0.0;
      final hTime = hourly['time'] is List ? hourly['time'] as List : const [];
      final hRain = hourly['precipitation'] is List ? hourly['precipitation'] as List : const [];
      final hProb = hourly['precipitation_probability'] is List ? hourly['precipitation_probability'] as List : const [];
      final hCode = hourly['weather_code'] is List ? hourly['weather_code'] as List : const [];
      final hWind = hourly['wind_speed_10m'] is List ? hourly['wind_speed_10m'] as List : const [];
      final hTemp = hourly['temperature_2m'] is List ? hourly['temperature_2m'] as List : const [];
      final startIndex = _startHourlyIndex(hTime);
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
        'rainfall_today_mm': double.parse(todayRain.toStringAsFixed(2)),
        'today_rainfall_mm': double.parse(todayRain.toStringAsFixed(2)),
        'daily_rainfall_mm': double.parse(todayRain.toStringAsFixed(2)),
        'rainfall_mm': double.parse(monthly.toStringAsFixed(2)),
        'rainfall_monthly_mm': double.parse(monthly.toStringAsFixed(2)),
        'monthly_rainfall_mm': double.parse(monthly.toStringAsFixed(2)),
        'rainfall_30d_mm': double.parse(monthly.toStringAsFixed(2)),
        'current_precipitation_mm': current['precipitation'] ?? current['rain'],
        'rain_next_6h_mm': double.parse(next6.toStringAsFixed(2)),
        'rain_probability_next_6h': double.parse(prob6.toStringAsFixed(1)),
        'wind_speed_ms': current['wind_speed_10m'],
        'cloud_cover_pct': current['cloud_cover'],
        'weather_code': current['weather_code'],
        'weather_description': _weatherCodeLabel(_toDouble(current['weather_code'])?.round()),
        'rain_next_3h_mm': double.parse(next3Rain.toStringAsFixed(2)),
        'rain_probability_next_3h': double.parse(prob3.toStringAsFixed(1)),
        'rain_probability_next_6h': double.parse(prob6.toStringAsFixed(1)),
        'max_wind_next_6h_kmh': double.parse(wind6.toStringAsFixed(1)),
        'max_temp_next_6h_c': double.parse(temp6.toStringAsFixed(1)),
        'weather_codes_next_6h': codes6,
        'weather_source': 'Open-Meteo direct',
        'weather_is_realtime': true,
      };
    } catch (_) {
      return null;
    }
  }


  int _startHourlyIndex(List times) {
    if (times.isEmpty) return 0;
    final now = DateTime.now();
    for (var i = 0; i < times.length; i++) {
      final parsed = DateTime.tryParse('${times[i]}');
      if (parsed != null && !parsed.isBefore(now)) return i;
    }
    return 0;
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

  Future<double?> _fetchLast30DaysRainfall(double? lat, double? lon, {List? polygon}) async {
    try {
      double? useLat = lat;
      double? useLon = lon;
      if ((useLat == null || useLon == null) && polygon != null && polygon.isNotEmpty) {
        double latSum = 0;
        double lonSum = 0;
        int count = 0;
        for (final p in polygon) {
          if (p is Map) {
            final a = _toDouble(p['lat']);
            final b = _toDouble(p['lng'] ?? p['lon']);
            if (a != null && b != null) {
              latSum += a;
              lonSum += b;
              count++;
            }
          }
        }
        if (count > 0) {
          useLat = latSum / count;
          useLon = lonSum / count;
        }
      }
      if (useLat == null || useLon == null) return null;
      final end = DateTime.now().toUtc().subtract(const Duration(days: 1));
      final start = end.subtract(const Duration(days: 29));
      String fmt(DateTime d) => d.toIso8601String().substring(0, 10);
      final uri = Uri.parse(
        'https://archive-api.open-meteo.com/v1/archive?latitude=$useLat&longitude=$useLon'
        '&start_date=${fmt(start)}&end_date=${fmt(end)}&daily=precipitation_sum&timezone=Asia%2FManila',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode >= 400) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final daily = decoded['daily'];
      if (daily is! Map<String, dynamic>) return null;
      final values = daily['precipitation_sum'];
      if (values is! List || values.isEmpty) return null;
      final total = values.fold<double>(0.0, (sum, v) => sum + (_toDouble(v) ?? 0.0));
      return double.parse(total.toStringAsFixed(2));
    } catch (_) {
      return null;
    }
  }

  Future<double?> _fetchTodayRainfall(double lat, double lon) async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&daily=precipitation_sum&timezone=Asia%2FManila',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
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
      () => http.get(
        Uri.parse('$baseUrl/api/mobile/me'),
        headers: {'Authorization': 'Bearer $token'},
      ),
      timeout: const Duration(seconds: 20),
    );
    final data = _decodeJson(response);
    if (response.statusCode >= 400) throw Exception(_errorMessage(data, 'Profile failed'));
    return data['user'] is Map<String, dynamic> ? data['user'] : data;
  }

  Future<Map<String, dynamic>> getCounts() async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/api/mobile/counts'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _decodeJson(response);
    if (response.statusCode >= 400) throw Exception(_errorMessage(data, 'Counts failed'));
    return data;
  }

  Future<List<dynamic>> getHistory() async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/api/mobile/history'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _decodeJson(response);
    if (response.statusCode >= 400) throw Exception(_errorMessage(data, 'History failed'));
    return data['history'] as List<dynamic>;
  }


  Future<Map<String, dynamic>> saveAnalysis(int sessionId) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/api/mobile/save-analysis'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'session_id': sessionId}),
    );
    final data = _decodeJson(response);
    if (response.statusCode >= 400) throw Exception(_errorMessage(data, 'Save failed'));
    return data;
  }

  Future<List<dynamic>> getSavedAnalyses() async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/api/mobile/saved'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _decodeJson(response);
    if (response.statusCode >= 400) throw Exception(_errorMessage(data, 'Saved analyses failed'));
    return data['saved'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> createReport(int sessionId, {String? title}) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/api/mobile/report'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'session_id': sessionId, 'title': title}),
    );
    final data = _decodeJson(response);
    if (response.statusCode >= 400) throw Exception(_errorMessage(data, 'Report failed'));
    return data;
  }

  Future<List<dynamic>> getReports() async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/api/mobile/reports'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _decodeJson(response);
    if (response.statusCode >= 400) throw Exception(_errorMessage(data, 'Reports failed'));
    return data['reports'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> updateProfile({
    required String username,
    required String role,
    String? location,
    String? profilePhotoBase64,
  }) async {
    final token = await getToken();
    final response = await http.put(
      Uri.parse('$baseUrl/api/mobile/me'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({
        'username': username,
        'role': role,
        if (location != null) 'location': location,
        if (profilePhotoBase64 != null) 'profile_photo': profilePhotoBase64,
      }),
    );
    final data = _decodeJson(response);
    if (response.statusCode >= 400) throw Exception(_errorMessage(data, 'Profile update failed'));
    return data['user'] is Map<String, dynamic> ? data['user'] : data;
  }

  Future<void> deactivateAccount() async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/api/mobile/me/deactivate'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _decodeJson(response);
    if (response.statusCode >= 400) throw Exception(_errorMessage(data, 'Deactivate failed'));
    await logout();
  }

  Future<void> deleteAccount() async {
    final token = await getToken();
    final response = await http.delete(
      Uri.parse('$baseUrl/api/mobile/me'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _decodeJson(response);
    if (response.statusCode >= 400) throw Exception(_errorMessage(data, 'Delete account failed'));
    await logout();
  }

}
