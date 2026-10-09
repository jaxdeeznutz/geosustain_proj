library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'farm_geometry.dart';

part 'screens/mobile_visuals.dart';
part 'screens/home_screen.dart';
part 'screens/map_screen.dart';
part 'screens/my_farms_screen.dart';
part 'screens/land_mapping_screen.dart';
part 'screens/session_gate.dart';
part 'screens/analyze_screen.dart';
part 'screens/mobile_results.dart';
part 'screens/history_screen.dart';
part 'screens/profile_screen.dart';
part 'screens/insights_report_admin_screen.dart';
part 'screens/settings_screen.dart';
part 'web/auth/web_auth_login.dart';
part 'web/web_analyst_shell.dart';
part 'web/web_admin_shell.dart';
part 'web/widgets/web_common.dart';
part 'web/screens/web_dashboard_screen.dart';
part 'web/screens/web_map_screen.dart';
part 'web/screens/web_analyze_screen.dart';
part 'web/screens/web_history_reports_screen.dart';
part 'web/screens/web_trends_weather_soil_settings_screen.dart';
part 'web/screens/web_planner_queue_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GeoSustainApp());
}

const green = Color(0xFF08733F);
const darkGreen = Color(0xFF055C34);
const softGreen = Color(0xFFEAF6EF);
const bg = Color(0xFFF8FAF4);
const cream = Color(0xFFFFF6EB);
const panaboCenter = LatLng(7.2915, 125.6255);

class AuthBackground extends StatelessWidget {
  final Widget child;
  const AuthBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF7FAF7), Color(0xFFEAF6EF)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -70,
            top: -70,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                color: green.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -70,
            bottom: -70,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                color: green.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class AuthCard extends StatelessWidget {
  final Widget child;
  const AuthCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class GeoSustainApp extends StatelessWidget {
  final Widget? home;
  const GeoSustainApp({super.key, this.home});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GeoSustain Mobile',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: green).copyWith(
          primary: green,
          secondary: darkGreen,
          surface: const Color(0xFFF8FAF4),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: softGreen,
          side: const BorderSide(color: Color(0xFFD6E6DA)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          labelStyle: const TextStyle(
            fontFamily: 'Roboto',
            color: darkGreen,
            fontWeight: FontWeight.w600,
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: Color(0xFFD5EDDD),
        ),
        scaffoldBackgroundColor: bg,
        useMaterial3: true,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: bg,
          foregroundColor: Color(0xFF102018),
          centerTitle: true,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: green,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE1E8E2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE1E8E2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: green, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: green,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE7EEE8)),
          ),
        ),
      ),
      home: home ?? const SessionGate(),
    );
  }
}

class FarmerAuthScaffold extends StatelessWidget {
  final Widget child;
  final VoidCallback? onBack;
  const FarmerAuthScaffold({super.key, required this.child, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: green,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 40,
              child: onBack != null
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: onBack,
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 26),
              child: Column(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.eco_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'GeoSustain',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Sustainable Farming, Guided by AI',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFFBF8F2),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final api = ApiService();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool loading = false;
  bool obscurePassword = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    api.close();
    super.dispose();
  }

  Future<void> login() async {
    if (loading) return;
    setState(() => loading = true);

    final email = emailController.text.trim();
    final password = passwordController.text;
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
        password.isEmpty) {
      setState(() => loading = false);
      showMessage('Enter your email address and password.');
      return;
    }

    try {
      await api.login(email, password);
      // The authenticated role selects the appropriate shell.

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ShellPage()),
      );
    } catch (e) {
      showMessage(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void showMessage(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).size.width >= 900) {
      return WebAuthLoginShell(
        emailController: emailController,
        passwordController: passwordController,
        loading: loading,
        onLogin: login,
        onCreate: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RegisterPage()),
        ),
      );
    }
    return FarmerAuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Welcome, Farmer!',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1F2A22),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Sign in to access your farms',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 26),
          const Text(
            'Email Address',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'you@example.com',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Password',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: passwordController,
            obscureText: obscurePassword,
            onSubmitted: (_) => loading ? null : login(),
            decoration: InputDecoration(
              hintText: '••••••••',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => obscurePassword = !obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: loading ? null : login,
            style: FilledButton.styleFrom(
              backgroundColor: green,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Sign In',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
          ),
          const SizedBox(height: 18),
          Center(
            child: TextButton(
              onPressed: loading
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RegisterPage()),
                    ),
              child: RichText(
                text: const TextSpan(
                  style: TextStyle(color: Colors.black54, fontSize: 13.5),
                  children: [
                    TextSpan(text: "First time? "),
                    TextSpan(
                      text: 'Register here',
                      style: TextStyle(
                        color: green,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final api = ApiService();
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  bool loading = false;
  bool obscurePassword = true;
  bool obscureConfirm = true;

  Future<void> register() async {
    if (loading) return;
    final username = usernameController.text.trim();
    final email = emailController.text.trim().toLowerCase();
    final password = passwordController.text;

    if (username.length < 3) {
      return showMessage('Username must be at least 3 characters.');
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return showMessage('Enter a valid email address.');
    }
    if (utf8.encode(password).length > 72) {
      return showMessage('Password is too long (maximum 72 UTF-8 bytes).');
    }
    if (password.length < 6) {
      return showMessage('Password must be at least 6 characters.');
    }
    if (password != confirmPasswordController.text) {
      return showMessage('Passwords do not match.');
    }
    setState(() => loading = true);
    try {
      const assignedRole = 'farmer';
      await api.register(
        username: username,
        email: email,
        password: password,
        role: assignedRole,
      );
      if (!mounted) return;
      showMessage('Account created. Sign in with your email and password.');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    } catch (e) {
      showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    api.close();
    super.dispose();
  }

  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return FarmerAuthScaffold(
      onBack: () => Navigator.pop(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Create Account',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1F2A22),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Join GeoSustain for field analysis, recommendations, and saved reports.',
            style: TextStyle(color: Colors.black54, height: 1.35),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: softGreen,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: green.withValues(alpha: .14)),
            ),
            child: Row(
              children: [
                const Icon(Icons.agriculture_rounded, color: green, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Create a Farmer account. Analyst access is assigned by your administrator.',
                    style: const TextStyle(
                      color: darkGreen,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Username',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: usernameController,
            decoration: _fieldDecoration(),
          ),
          const SizedBox(height: 14),
          const Text(
            'Email Address',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: _fieldDecoration(hint: 'you@example.com'),
          ),
          const SizedBox(height: 14),
          const Text(
            'Password',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: passwordController,
            obscureText: obscurePassword,
            decoration: _fieldDecoration().copyWith(
              suffixIcon: IconButton(
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => obscurePassword = !obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Confirm Password',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: confirmPasswordController,
            obscureText: obscureConfirm,
            decoration: _fieldDecoration().copyWith(
              suffixIcon: IconButton(
                icon: Icon(
                  obscureConfirm
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => obscureConfirm = !obscureConfirm),
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: loading ? null : register,
            style: FilledButton.styleFrom(
              backgroundColor: green,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Register',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _fieldDecoration({String? hint}) => InputDecoration(
  hintText: hint,
  filled: true,
  fillColor: Colors.white,
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide.none,
  ),
);

/// Converts a raw exception (network failure, timeout, or a server error
/// message already wrapped in an Exception) into a short, non-technical
/// message safe to show a Farmer or Analyst. Without this, a dropped
/// connection surfaces as something like "ClientException: Failed to
/// fetch, uri=https://..." — accurate, but meaningless and alarming to a
/// non-technical user (Section 26).
String friendlyErrorMessage(Object error) {
  // HTTP status is authoritative; transport text cannot establish offline state.
  if (error is ApiException) {
    if (error.statusCode == 401) {
      return 'Your session has expired. Please log in again.';
    }
    if (error.statusCode >= 500) {
      return 'The analysis service is unavailable. Try again shortly.';
    }
    if (error.statusCode == 403) {
      return 'You do not have access to this action.';
    }
    final message = error.message;
    if (!RegExp(
      r'https?://|uri=|traceback|exception',
      caseSensitive: false,
    ).hasMatch(message)) {
      return message;
    }
    return 'The request could not be completed. Please try again.';
  }
  if (error is TimeoutException) {
    return 'The request took too long. Try again to check for an existing analysis.';
  }
  final lower = error.toString().toLowerCase();
  if (error is http.ClientException ||
      lower.contains('socketexception') ||
      lower.contains('failed to fetch') ||
      lower.contains('connection') ||
      lower.contains('network is unreachable')) {
    return "Couldn't reach the analysis service. Try again.";
  }
  if (error is FormatException) {
    return 'The service returned an unexpected response. Please try again.';
  }
  return 'Unable to complete this action. Please try again.';
}

class AnalysisState extends ChangeNotifier {
  bool _disposed = false;
  int _sessionEpoch = 0, _selectionEpoch = 0;
  bool historyLoading = false, historyLoaded = false;
  Future<void>? _historyRefresh;
  Future<void>? _farmsRefresh;
  Map<String, dynamic>? selectedFarm;
  String? analysisError;
  bool analysisPending = false;
  int? get selectedFarmId => int.tryParse('${selectedFarm?['id']}');
  bool _active(int epoch, dynamic owner) =>
      !_disposed && epoch == _sessionEpoch && currentUser?['id'] == owner;
  bool _ownsRecord(Map<String, dynamic> row) =>
      row['owner_id'] == null ||
      '${row['owner_id']}' == '${currentUser?['id']}';

  void focusFarm(Map<String, dynamic> farm) {
    if (selectedFarmId != int.tryParse('${farm['id']}')) {
      _selectionEpoch++;
      result = null;
      analysisError = null;
      analysisPending = false;
    }
    selectedFarm = Map.of(farm);
    notifyListeners();
  }

  String? historyError;
  String? farmsError;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<String?> selectAnalysis(Map<String, dynamic> record) async {
    final id = int.tryParse('${record['session_id'] ?? record['id']}');
    if (id == null) return 'This analysis has no saved record.';
    final epoch = _sessionEpoch, selection = ++_selectionEpoch;
    final owner = currentUser?['id'];
    result = null;
    notifyListeners();
    try {
      final selected = await api.getAnalysis(id);
      if (!_active(epoch, owner) || selection != _selectionEpoch) {
        return 'The selected farm or account changed.';
      }
      if ('${selected['session_id']}' != '$id' ||
          !_ownsRecord(selected) ||
          (record['farm_id'] != null &&
              '${selected['farm_id']}' != '${record['farm_id']}')) {
        return 'This result does not match the selected farm. Refresh and try again.';
      }
      if (!analysisIsCompleted(selected)) {
        return 'This analysis is not complete yet.';
      }
      selectedFarm = selected['farm_id'] == null
          ? null
          : {
              'id': selected['farm_id'],
              'farm_name': selected['farm_name'],
              'owner_display_name': selected['owner_display_name'],
            };
      result = selected;
      analysisError = null;
      analysisPending = false;
      notifyListeners();
      return null;
    } catch (error) {
      return friendlyErrorMessage(error);
    }
  }

  void clearUserData() {
    _sessionEpoch++;
    _selectionEpoch++;
    _historyRefresh = null;
    _farmsRefresh = null;
    selectedFarm = null;
    analysisError = null;
    analysisPending = false;
    historyError = null;
    farmsError = null;
    historyLoaded = false;
    historyLoading = false;
    userLoaded = false;
    _weatherRefreshTimer?.cancel();
    _loadingTimer?.cancel();
    result = null;
    currentUser = null;
    liveWeather = null;
    profilePhotoBytes = null;
    for (final list in [
      farms,
      historyRecords,
      recentAnalyses,
      savedAnalyses,
      generatedReports,
      verifiedTrendRecords,
      plannerQueue,
    ]) {
      list.clear();
    }
    polygonPoints.clear();
    _placeCache.clear();
    profileCounts.clear();
    plannerCounts.clear();
    _lastAnalysisKey = null;
    _lastAnalysisAt = null;
    selectedPoint = panaboCenter;
    selectedPlaceName = 'Panabo City, Davao del Norte';
    latController.text = panaboCenter.latitude.toStringAsFixed(5);
    lonController.text = panaboCenter.longitude.toStringAsFixed(5);
    drawing = false;
    farmsLoading = false;
    weatherLoading = false;
    plannerQueueLoading = false;
    loading = false;
    notifyListeners();
  }

  void replaceFarms(List<Map<String, dynamic>> values) {
    if (_disposed) return;
    farms
      ..clear()
      ..addAll(values);
    notifyListeners();
  }

  void updateCurrentProfile(Map<String, dynamic> user, {Uint8List? photo}) {
    currentUser = user;
    if (photo != null) profilePhotoBytes = photo;
    notifyListeners();
  }

  AnalysisState({ApiService? api}) : api = api ?? ApiService();
  final ApiService api;
  final mapController = MapController();
  final latController = TextEditingController(text: '7.2915');
  final lonController = TextEditingController(text: '125.6255');
  Map<String, dynamic>? result;
  Map<String, dynamic>? liveWeather;
  Map<String, dynamic>? currentUser;
  bool userLoaded = false;
  Uint8List? profilePhotoBytes;
  Map<String, dynamic> profileCounts = {
    'analysis_count': 0,
    'saved_count': 0,
    'report_count': 0,
  };
  bool loading = false;
  bool weatherLoading = false;
  String loadingMessage = 'Preparing analysis...';
  Timer? _loadingTimer;
  Timer? _weatherRefreshTimer;
  bool satellite = true;
  bool drawing = false;
  bool locating = false;
  String? _lastAnalysisKey;
  DateTime? _lastAnalysisAt;
  LatLng selectedPoint = panaboCenter;
  String selectedPlaceName = 'Panabo City, Davao del Norte';
  final List<LatLng> polygonPoints = [];
  final List<Map<String, dynamic>> recentAnalyses = [];
  final List<Map<String, dynamic>> historyRecords = [];
  final List<Map<String, dynamic>> savedAnalyses = [];
  final List<Map<String, dynamic>> generatedReports = [];
  final List<Map<String, dynamic>> verifiedTrendRecords = [];
  final List<Map<String, dynamic>> farms = [];
  bool farmsLoading = false;
  int mapEpoch = 0;
  final Map<String, String> _placeCache = {};
  double _lastMapZoom = 12.5;

  // Planner verification workflow state
  final List<Map<String, dynamic>> plannerQueue = [];
  Map<String, dynamic> plannerCounts = {
    'pending_count': 0,
    'verified_count': 0,
    'rejected_count': 0,
  };
  bool plannerQueueLoading = false;
  String plannerQueueStatus = 'pending';
  String heatmapLayer = 'NDVI';
  int intendedPlantingMonth = DateTime.now().month;

  static const List<String> monthNames = [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String get intendedPlantingMonthName => monthNames[intendedPlantingMonth];

  void setIntendedPlantingMonth(int? value) {
    if (value == null || value < 1 || value > 12) return;
    intendedPlantingMonth = value;
    notifyListeners();
  }

  void setHeatmapLayer(String value) {
    heatmapLayer = value;
    notifyListeners();
  }

  double get safeMapZoom {
    try {
      _lastMapZoom = mapController.camera.zoom;
      return _lastMapZoom;
    } catch (_) {
      return _lastMapZoom;
    }
  }

  String _placeKey(double lat, double lon) =>
      '${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}';

  final List<String> loadingSteps = const [
    'Checking selected location...',
    'Analyzing soil suitability...',
    'Fetching rainfall and weather...',
    'Reading elevation and slope...',
    'Generating crop recommendations...',
    'Preparing explanation and report...',
  ];

  void _startLoadingFlow() {
    _loadingTimer?.cancel();
    loading = true;
    analysisError = null;
    loadingMessage = 'Analyzing your land. This may take a few minutes…';
    notifyListeners();
  }

  void _stopLoadingFlow() {
    _loadingTimer?.cancel();
    _loadingTimer = null;
    loading = false;
    loadingMessage = 'Preparing analysis...';
    notifyListeners();
  }

  void bumpMapVisual() {
    mapEpoch++;
    notifyListeners();
  }

  void moveMapLocked(LatLng point, double zoom) {
    _lastMapZoom = zoom.clamp(12.0, 19.0);
    try {
      mapController.move(point, _lastMapZoom);
    } catch (_) {}
  }

  void zoomMap(double delta) {
    moveMapLocked(selectedPoint, safeMapZoom + delta);
  }

  static bool looksLikeCoordinates(String? text) {
    if (text == null) return true;
    final t = text.trim();
    if (t.isEmpty) return true;
    return t.startsWith('Lat ') ||
        t.contains('Lon ') ||
        t.contains('• Lon') ||
        t == 'Analyzed Area' ||
        t == 'Unknown location' ||
        t == 'Panabo City area';
  }

  Future<void> requestLocationPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    notifyListeners();
  }

  Future<void> updatePlaceForSelection(double lat, double lon) async {
    selectedPlaceName = 'Looking up address...';
    notifyListeners();
    selectedPlaceName = await reverseGeocode(lat, lon);
    notifyListeners();
  }

  String recommendationText(Map<String, dynamic> record) {
    final title = record['recommendation_title'];
    if (title != null && '$title'.trim().isNotEmpty) return '$title';
    final crop = record['predicted_crop'] ?? record['crop'];
    if (crop != null && '$crop'.trim().isNotEmpty && '$crop' != '--') {
      return 'Recommended crop: $crop';
    }
    final land = record['land_status'];
    if (land != null && '$land'.trim().isNotEmpty) return '$land';
    return 'Land suitability analysis';
  }

  Future<String> resolvePlaceForRecord(Map<String, dynamic> record) async {
    final cached =
        record['place_name'] ??
        record['location_name'] ??
        record['title'] ??
        record['barangay'] ??
        record['address'];
    if (cached != null) {
      final text = '$cached'.trim();
      if (text.isNotEmpty && !looksLikeCoordinates(text)) {
        return text;
      }
    }
    final lat = record['center_lat'] ?? record['lat'];
    final lon = record['center_lon'] ?? record['lon'];
    final latNum = lat is num ? lat.toDouble() : double.tryParse('$lat');
    final lonNum = lon is num ? lon.toDouble() : double.tryParse('$lon');
    if (latNum == null || lonNum == null) return 'Analyzed Area';
    final key = _placeKey(latNum, lonNum);
    if (_placeCache.containsKey(key)) return _placeCache[key]!;
    final place = await reverseGeocode(latNum, lonNum);
    _placeCache[key] = place;
    record['place_name'] = place;
    record['title'] = place;
    return place;
  }

  Future<void> enrichRecordsWithPlaces(
    List<Map<String, dynamic>> records, {
    int maxLookups = 15,
  }) async {
    var lookups = 0;
    for (final record in records) {
      if (lookups >= maxLookups) break;
      final lat = record['center_lat'] ?? record['lat'];
      final lon = record['center_lon'] ?? record['lon'];
      final latNum = lat is num ? lat.toDouble() : double.tryParse('$lat');
      final lonNum = lon is num ? lon.toDouble() : double.tryParse('$lon');
      if (latNum == null || lonNum == null) continue;
      final existing = record['place_name'] ?? record['title'];
      if (existing != null &&
          '$existing'.trim().isNotEmpty &&
          !looksLikeCoordinates('$existing')) {
        continue;
      }
      final key = _placeKey(latNum, lonNum);
      if (_placeCache.containsKey(key)) {
        record['place_name'] = _placeCache[key];
        record['title'] = _placeCache[key];
        continue;
      }
      lookups++;
      final place = await reverseGeocode(latNum, lonNum);
      _placeCache[key] = place;
      record['place_name'] = place;
      record['title'] = place;
      await Future.delayed(const Duration(milliseconds: 350));
    }
    notifyListeners();
  }

  List<Map<String, dynamic>> get officialTrendRecords {
    final merged = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final row in [...historyRecords, ...verifiedTrendRecords]) {
      final id =
          '${row['session_id'] ?? row['id'] ?? row['analyzed_at'] ?? row.hashCode}';
      if (seen.add(id)) merged.add(row);
    }
    return merged;
  }

  Future<void> loadUserData() async {
    final epoch = _sessionEpoch;
    userLoaded = false;
    notifyListeners();
    try {
      final user = await api.getMe();
      if (_disposed || epoch != _sessionEpoch) return;
      if (currentUser?['id'] != null && currentUser?['id'] != user['id']) {
        clearUserData();
      }
      currentUser = user;
      final photo = user['profile_photo'];
      if (photo != null && '$photo'.isNotEmpty) {
        try {
          profilePhotoBytes = base64Decode('$photo');
        } catch (_) {}
      }
    } catch (error) {
      if (_disposed || epoch != _sessionEpoch) return;
      currentUser = {
        'username': 'Unknown user',
        'role': 'unknown',
        'profile_load_error': friendlyErrorMessage(error),
      };
    }
    if (_disposed) return;
    userLoaded = true;
    notifyListeners();
    await refreshHistoryData();
    // Selection is explicit. Account-wide history must not become a farm result.
  }

  Future<void> refreshHistoryData() {
    if (currentUser == null) return Future.value();
    final epoch = _sessionEpoch;
    return _historyRefresh ??= _refreshHistory().whenComplete(() {
      if (epoch == _sessionEpoch) _historyRefresh = null;
    });
  }

  Future<void> _refreshHistory() async {
    final epoch = _sessionEpoch;
    final owner = currentUser?['id'];
    historyLoading = true;
    historyError = null;
    notifyListeners();
    try {
      final rows = await api.getHistory();
      if (!_active(epoch, owner)) return;
      historyRecords
        ..clear()
        ..addAll(
          rows
              .map((r) => Map<String, dynamic>.from(r as Map))
              .where(_ownsRecord),
        );
      historyLoaded = true;
      recentAnalyses
        ..clear()
        ..addAll(
          historyRecords
              .where(analysisIsCompleted)
              .take(3)
              .map(normalizeRecord),
        );
      final id = result?['session_id'];
      for (final row in historyRecords) {
        if (id != null && '${row['session_id']}' == '$id') {
          for (final key in [
            'verification_status',
            'planner_notes',
            'verified_at',
            'submitted_at',
          ]) {
            result![key] = row[key];
          }
        }
      }
    } catch (error) {
      if (_active(epoch, owner)) historyError = friendlyErrorMessage(error);
    } finally {
      if (_active(epoch, owner)) {
        historyLoading = false;
        notifyListeners();
      }
    }
    if (!_active(epoch, owner)) return;
    // Coalesce simultaneous tab refreshes and fetch each account resource once.
    await Future.wait([
      () async {
        try {
          final rows = await api.getSavedAnalyses();
          if (_active(epoch, owner)) {
            savedAnalyses
              ..clear()
              ..addAll(rows.map((r) => Map<String, dynamic>.from(r as Map)));
          }
        } catch (_) {}
      }(),
      () async {
        try {
          final rows = await api.getReports();
          if (_active(epoch, owner)) {
            generatedReports
              ..clear()
              ..addAll(rows.map((r) => Map<String, dynamic>.from(r as Map)));
          }
        } catch (_) {}
      }(),
      () async {
        try {
          final counts = await api.getCounts();
          if (_active(epoch, owner)) profileCounts = counts;
        } catch (_) {}
      }(),
      if (isPlanner)
        () async {
          try {
            final rows = await api.getPlannerQueue(status: 'verified');
            if (_active(epoch, owner)) {
              verifiedTrendRecords
                ..clear()
                ..addAll(rows.map((r) => Map<String, dynamic>.from(r as Map)));
            }
          } catch (_) {}
        }(),
    ]);
    if (_active(epoch, owner)) notifyListeners();
  }

  Future<void> refreshFarms() {
    if (currentUser == null) return Future.value();
    final epoch = _sessionEpoch;
    return _farmsRefresh ??= _refreshFarms().whenComplete(() {
      if (epoch == _sessionEpoch) _farmsRefresh = null;
    });
  }

  Future<void> _refreshFarms() async {
    final epoch = _sessionEpoch, owner = currentUser?['id'];
    farmsLoading = true;
    farmsError = null;
    notifyListeners();
    try {
      final rows = await api.getFarms();
      if (!_active(epoch, owner)) return;
      farms
        ..clear()
        ..addAll(
          rows.where(
            (r) => r['farmer_id'] == null || '${r['farmer_id']}' == '$owner',
          ),
        );
    } catch (error) {
      if (_active(epoch, owner)) farmsError = friendlyErrorMessage(error);
    } finally {
      if (_active(epoch, owner)) {
        farmsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<String?> loadPlannerQueue({String? status}) async {
    if (status != null) plannerQueueStatus = status;
    plannerQueueLoading = true;
    notifyListeners();
    String? error;
    try {
      final rows = await api.getPlannerQueue(status: plannerQueueStatus);
      plannerQueue
        ..clear()
        ..addAll(rows.map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (e) {
      error = friendlyErrorMessage(e);
    }
    try {
      plannerCounts = await api.getPlannerCounts();
    } catch (_) {}
    plannerQueueLoading = false;
    notifyListeners();
    return error;
  }

  Future<Map<String, dynamic>> loadPlannerSessionDetail(int sessionId) async {
    return api.getPlannerSessionDetail(sessionId);
  }

  Future<String?> verifyPlannerSubmission(
    int sessionId,
    String status, {
    String? notes,
  }) async {
    try {
      await api.verifySubmission(sessionId, status, notes: notes);
      // Remove it from the current queue view since it no longer matches
      // whatever status filter the planner is currently looking at.
      plannerQueue.removeWhere((row) {
        final rawId = row['session_id'] ?? row['id'];
        final parsedId = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
        return parsedId == sessionId;
      });
      try {
        plannerCounts = await api.getPlannerCounts();
      } catch (_) {}
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  String userName() => '${currentUser?['username'] ?? 'User'}';
  String userLocation() {
    final location = '${currentUser?['location'] ?? ''}'.trim();
    return location.isEmpty ? 'Location not set' : location;
  }

  String userProfilePhotoBase64() => '${currentUser?['profile_photo'] ?? ''}';
  String get accountRole =>
      '${currentUser?['role'] ?? currentUser?['account_type'] ?? 'unknown'}'
          .toLowerCase();
  String userRole() =>
      isAnalystRole ? 'Agricultural Planning Analyst' : 'Farmer Account';

  bool get isSuperAdmin =>
      accountRole == 'super_admin' || accountRole == 'admin';
  bool get isAnalystRole =>
      accountRole.contains('analyst') || accountRole.contains('planner');
  // In GeoSustain, the Analyst also performs the Planner verification role.
  bool get isPlanner =>
      accountRole.contains('analyst') || accountRole.contains('planner');

  String get roleDashboardTitle =>
      isAnalystRole ? 'Planning Workspace' : 'Farmer Tools';

  List<String> get roleCapabilities => isAnalystRole
      ? const [
          'Compare multiple field areas',
          'Review environmental and infrastructure risk',
          'Generate planning-ready summaries',
          'Monitor crop and land suitability trends',
        ]
      : const [
          'Analyze your selected farm field',
          'Get crop recommendation explanations',
          'Track live weather and advisories',
          'Save history and download reports',
        ];

  Map<String, dynamic> normalizeRecord(Map<String, dynamic> record) {
    final lat = record['center_lat'] ?? record['lat'];
    final lon = record['center_lon'] ?? record['lon'];
    final crop = record['predicted_crop'] ?? record['crop'] ?? 'Land Analysis';
    final place =
        record['place_name'] ??
        record['location_name'] ??
        record['barangay'] ??
        record['address'] ??
        record['title'];
    final latNum = lat is num ? lat.toDouble() : double.tryParse('$lat');
    final lonNum = lon is num ? lon.toDouble() : double.tryParse('$lon');
    String resolvedPlace = 'Looking up location...';
    if (place != null && !looksLikeCoordinates('$place')) {
      resolvedPlace = '$place';
    } else if (record['place_name'] != null &&
        !looksLikeCoordinates('${record['place_name']}')) {
      resolvedPlace = '${record['place_name']}';
    } else if (latNum != null && lonNum != null) {
      final key = _placeKey(latNum, lonNum);
      if (_placeCache.containsKey(key)) {
        resolvedPlace = _placeCache[key]!;
      }
    }
    final compatibility =
        record['crop_compatibility_pct'] ?? record['compatibility_pct'];
    return {
      ...record,
      'compatibility_pct': compatibility,
      'crop_compatibility_pct': compatibility,
      'suitability_level': suitabilityLabel(compatibility),
      'title': resolvedPlace,
      'place_name': record['place_name'] ?? resolvedPlace,
      'subtitle': record['subtitle'] ?? recommendationText(record),
      'date':
          record['date'] ??
          record['analyzed_at'] ??
          record['saved_at'] ??
          record['report_created_at'] ??
          record['created_at'] ??
          'Recent analysis',
      'lat': lat,
      'lon': lon,
      'center_lat': lat,
      'center_lon': lon,
      'predicted_crop': crop,
    };
  }

  Future<bool> submitAnalysisRecord(Map<String, dynamic> record) async {
    final item = normalizeRecord(record);
    final sessionRaw = item['session_id'];
    final sessionId = sessionRaw is int
        ? sessionRaw
        : int.tryParse('$sessionRaw');
    if (sessionId == null) return false;
    try {
      await api.submitAnalysisToPlanner(sessionId);
    } catch (e) {
      // A duplicate/rapid resubmit (or a resubmit that lands after the
      // Analyst already acted) surfaces as "already pending/verified" —
      // the Farmer's desired end state (submitted) is already true, so
      // this isn't a real failure worth alarming them with.
      if ('$e'.toLowerCase().contains('already pending') ||
          '$e'.toLowerCase().contains('already verified')) {
        await refreshHistoryData();
        return true;
      }
      rethrow;
    }
    await refreshHistoryData();
    return true;
  }

  Future<bool> saveAnalysisRecord(Map<String, dynamic> record) async {
    final item = normalizeRecord(record);
    final sessionRaw = item['session_id'];
    final sessionId = sessionRaw is int
        ? sessionRaw
        : int.tryParse('$sessionRaw');
    if (sessionId != null) {
      await api.saveAnalysis(sessionId);
      await refreshHistoryData();
      return true;
    }
    final exists = savedAnalyses.any(
      (r) =>
          '${r['center_lat']}-${r['center_lon']}-${r['predicted_crop']}' ==
          '${item['center_lat']}-${item['center_lon']}-${item['predicted_crop']}',
    );
    if (!exists) savedAnalyses.insert(0, item);
    notifyListeners();
    return !exists;
  }

  Future<bool> createReportRecord(Map<String, dynamic> record) async {
    final item = normalizeRecord(record);
    final sessionRaw = item['session_id'];
    final sessionId = sessionRaw is int
        ? sessionRaw
        : int.tryParse('$sessionRaw');
    if (sessionId != null) {
      final res = await api.createReport(
        sessionId,
        title: 'GeoSustain Report - ${item['predicted_crop']}',
      );
      await refreshHistoryData();
      if (res['report'] is Map && res['report']['already_reported'] == true) {
        return false;
      }
      return true;
    }
    final exists = generatedReports.any(
      (r) =>
          '${r['center_lat']}-${r['center_lon']}-${r['predicted_crop']}' ==
          '${item['center_lat']}-${item['center_lon']}-${item['predicted_crop']}',
    );
    if (!exists) generatedReports.insert(0, item);
    notifyListeners();
    return !exists;
  }

  bool _insidePanabo(LatLng point) {
    return point.latitude >= 7.20 &&
        point.latitude <= 7.41 &&
        point.longitude >= 125.50 &&
        point.longitude <= 125.72;
  }

  String _prettyAddress(Map<String, dynamic> address) {
    final barangay =
        address['suburb'] ??
        address['village'] ??
        address['neighbourhood'] ??
        address['quarter'] ??
        address['hamlet'] ??
        address['barangay'];
    final city =
        address['city'] ??
        address['town'] ??
        address['municipality'] ??
        address['county'] ??
        'Panabo City';
    final province = address['state'] ?? address['region'] ?? 'Davao del Norte';

    if (barangay != null && '$barangay'.trim().isNotEmpty) {
      return 'Brgy. $barangay, $city';
    }
    return '$city, $province';
  }

  Future<String> reverseGeocode(double lat, double lon) async {
    final key = _placeKey(lat, lon);
    if (_placeCache.containsKey(key)) return _placeCache[key]!;

    try {
      final fromApi = await api.reverseGeocodePlace(lat, lon);
      if (fromApi.isNotEmpty && !looksLikeCoordinates(fromApi)) {
        _placeCache[key] = fromApi;
        return fromApi;
      }
    } catch (_) {}

    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lon&addressdetails=1&zoom=18&accept-language=en',
      );
      final response = await http
          .get(
            uri,
            headers: {
              'User-Agent': 'GeoSustainCapstone/1.0 (student capstone project)',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 400) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final address = decoded['address'];
          if (address is Map<String, dynamic>) {
            final place = _prettyAddress(address);
            _placeCache[key] = place;
            return place;
          }
          final name = decoded['display_name'];
          if (name != null) {
            final place = '$name'.split(',').take(2).join(', ');
            _placeCache[key] = place;
            return place;
          }
        }
      }
    } catch (_) {}

    final fallback = 'Panabo City area';
    _placeCache[key] = fallback;
    return fallback;
  }

  Future<String?> refreshLiveWeather({double? lat, double? lon}) async {
    weatherLoading = true;
    notifyListeners();
    final epoch = _sessionEpoch;
    final targetLat = lat ?? selectedPoint.latitude;
    final targetLon = lon ?? selectedPoint.longitude;
    try {
      final weather = await api.getLiveWeather(targetLat, targetLon);
      if (_disposed || epoch != _sessionEpoch) return null;
      liveWeather = {...weather, 'place_name': selectedPlaceName};
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (!_disposed && epoch == _sessionEpoch) {
        weatherLoading = false;
        notifyListeners();
      }
    }
  }

  void startWeatherAutoRefresh() {
    _weatherRefreshTimer?.cancel();
    _weatherRefreshTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      refreshLiveWeather();
    });
  }

  Future<String?> useCurrentLocation() async {
    locating = true;
    notifyListeners();
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return 'Location service is disabled. Please enable GPS/location.';
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return 'Location permission was denied.';
      }
      if (permission == LocationPermission.deniedForever) {
        return 'Location permission is permanently denied. Enable it in browser/app settings.';
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final point = LatLng(pos.latitude, pos.longitude);
      if (!_insidePanabo(point)) {
        return 'Your current location is outside the Panabo City study boundary. You can still manually pick a Panabo field on the map.';
      }

      selectedPoint = point;
      latController.text = point.latitude.toStringAsFixed(5);
      lonController.text = point.longitude.toStringAsFixed(5);
      selectedPlaceName = await reverseGeocode(point.latitude, point.longitude);
      moveMapLocked(point, 16);
      bumpMapVisual();
      await refreshLiveWeather(lat: point.latitude, lon: point.longitude);
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    } finally {
      locating = false;
      notifyListeners();
    }
  }

  String _analysisKey(String type, double lat, double lon) {
    return '$type:${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';
  }

  bool _isRecentDuplicate(String key) {
    if (_lastAnalysisKey != key || _lastAnalysisAt == null) return false;
    return DateTime.now().difference(_lastAnalysisAt!).inSeconds < 30;
  }

  Future<String?> analyzePoint() async {
    if (loading) return 'Analysis is already running. Please wait.';
    final lat = double.tryParse(latController.text);
    final lon = double.tryParse(lonController.text);
    if (lat == null || lon == null) {
      return 'Enter valid latitude and longitude.';
    }
    final point = LatLng(lat, lon);
    if (!_insidePanabo(point)) {
      return 'Selected point is outside Panabo City bounds.';
    }

    final key = _analysisKey('point', lat, lon);
    if (_isRecentDuplicate(key)) {
      return 'This exact location was already analyzed recently. Move the pin or wait a few seconds before analyzing again.';
    }

    selectedFarm = null;
    _selectionEpoch++;
    selectedPoint = point;
    _startLoadingFlow();
    moveMapLocked(point, 15);
    bumpMapVisual();
    selectedPlaceName = await reverseGeocode(lat, lon);
    return run(
      () => api.analyzePoint(
        lat,
        lon,
        placeName: selectedPlaceName,
        intendedPlantingMonth: intendedPlantingMonth,
      ),
      lat: lat,
      lon: lon,
      locationType: 'Point',
      analysisKey: key,
    );
  }

  Future<String?> analyzePolygon() async {
    if (loading) return 'Analysis is already running. Please wait.';
    final invalid = FarmGeometry.validate(polygonPoints);
    if (invalid != null) return invalid;
    final payload = FarmGeometry.payload(polygonPoints);
    final centerLat =
        polygonPoints.map((p) => p.latitude).reduce((a, b) => a + b) /
        polygonPoints.length;
    final centerLon =
        polygonPoints.map((p) => p.longitude).reduce((a, b) => a + b) /
        polygonPoints.length;
    final key =
        '${_analysisKey('boundary-area', centerLat, centerLon)}:${polygonPoints.length}:${jsonEncode(payload).hashCode}';
    if (_isRecentDuplicate(key)) {
      return 'This boundary was already analyzed recently. Edit the boundary or wait a few seconds before analyzing again.';
    }
    selectedFarm = null;
    _selectionEpoch++;
    selectedPoint = LatLng(centerLat, centerLon);
    latController.text = centerLat.toStringAsFixed(5);
    lonController.text = centerLon.toStringAsFixed(5);
    _startLoadingFlow();
    selectedPlaceName = await reverseGeocode(centerLat, centerLon);
    final err = await run(
      () => api.analyzePolygon(
        payload,
        placeName: selectedPlaceName,
        intendedPlantingMonth: intendedPlantingMonth,
      ),
      lat: centerLat,
      lon: centerLon,
      locationType: 'Boundary Area',
      analysisKey: key,
    );
    if (err == null && result != null) {
      result!['selection_type'] = 'Polygon boundary';
      result!['polygon_point_count'] = polygonPoints.length;
      result!['center_lat'] = centerLat;
      result!['center_lon'] = centerLon;
    }
    return err;
  }

  Future<String?> analyzeSavedFarm(Map<String, dynamic> farm) async {
    if (loading) return 'Analysis is already running. Please wait.';
    focusFarm(farm);
    final farmId = int.tryParse('${farm['id']}');
    if (farmId == null) return 'Refresh this farm before analyzing it.';
    final raw = farm['polygon'];
    if (raw is! List) return 'This farm has no valid saved boundary.';
    final points = <LatLng>[];
    for (final item in raw) {
      if (item is Map) {
        final lat = double.tryParse('${item['lat'] ?? item['latitude']}');
        final lng = double.tryParse(
          '${item['lng'] ?? item['lon'] ?? item['longitude']}',
        );
        if (lat != null && lng != null) points.add(LatLng(lat, lng));
      }
    }
    final invalid = FarmGeometry.validate(points);
    if (invalid != null) return invalid;
    polygonPoints
      ..clear()
      ..addAll(points);
    drawing = false;
    selectedPlaceName =
        '${farm['location_name'] ?? farm['farm_name'] ?? 'Saved farm'}';
    final centerLat =
        points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    final centerLon =
        points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;
    selectedPoint = LatLng(centerLat, centerLon);
    _startLoadingFlow();
    final payload = FarmGeometry.payload(points);
    final err = await run(
      () => api.analyzePolygon(
        payload,
        placeName: selectedPlaceName,
        intendedPlantingMonth: intendedPlantingMonth,
        farmId: farmId,
      ),
      lat: centerLat,
      lon: centerLon,
      locationType: 'Saved Farm Boundary',
      analysisKey:
          'farm:${farm['id']}:${DateTime.now().millisecondsSinceEpoch ~/ 10000}',
    );
    notifyListeners();
    return err;
  }

  Future<String?> run(
    Future<Map<String, dynamic>> Function() job, {
    double? lat,
    double? lon,
    String locationType = 'Point',
    String? analysisKey,
  }) async {
    final epoch = _sessionEpoch, selection = _selectionEpoch;
    result = null;
    analysisError = null;
    final owner = currentUser?['id'];
    if (!loading) _startLoadingFlow();
    try {
      final data = await job();
      if (!_active(epoch, owner)) {
        return 'Your session has changed. Sign in again.';
      }
      if (!_ownsRecord(data) || !analysisIsCompleted(data)) {
        return 'The server has not returned a completed analysis for this account.';
      }
      if (selection != _selectionEpoch) {
        return 'Analysis saved. Open its result from History.';
      }
      final compatibility =
          data['crop_compatibility_pct'] ?? data['compatibility_pct'];
      result = {
        ...data,
        'compatibility_pct': compatibility,
        'crop_compatibility_pct': compatibility,
        'suitability_level': suitabilityLabel(compatibility),
        'location_type': locationType,
      };
      analysisError = null;
      analysisPending = false;
      _addRecentAnalysis(result!, lat: lat, lon: lon);
      if (analysisKey != null) {
        _lastAnalysisKey = analysisKey;
        _lastAnalysisAt = DateTime.now();
      }
      await Future.wait([refreshHistoryData(), refreshFarms()]);
      return null;
    } catch (error) {
      if (_active(epoch, owner) && selection == _selectionEpoch) {
        analysisError = friendlyErrorMessage(error);
        analysisPending = error is ApiException && error.statusCode == 202;
      }
      if (kDebugMode) debugPrint('Land analysis failed: ${error.runtimeType}');
      return friendlyErrorMessage(error);
    } finally {
      if (_active(epoch, owner)) _stopLoadingFlow();
    }
  }

  void _addRecentAnalysis(
    Map<String, dynamic> data, {
    double? lat,
    double? lon,
  }) {
    final item = normalizeRecord({
      ...data,
      'place_name': data['place_name'] ?? selectedPlaceName,
      'center_lat': data['center_lat'] ?? lat,
      'center_lon': data['center_lon'] ?? lon,
      'lat': data['lat'] ?? lat,
      'lon': data['lon'] ?? lon,
    });

    historyRecords.removeWhere((r) => r['session_id'] == item['session_id']);
    historyRecords.insert(0, item);

    recentAnalyses
      ..clear()
      ..addAll(historyRecords.take(3).map(normalizeRecord));
    notifyListeners();
  }

  String? onMapTap(TapPosition tap, LatLng point) {
    if (!_insidePanabo(point)) {
      return 'Selected point is outside Panabo City bounds.';
    }
    if (drawing) {
      polygonPoints.add(point);
      notifyListeners();
    } else {
      selectedPoint = point;
      latController.text = point.latitude.toStringAsFixed(5);
      lonController.text = point.longitude.toStringAsFixed(5);
      moveMapLocked(point, safeMapZoom);
      notifyListeners();
      updatePlaceForSelection(point.latitude, point.longitude);
      refreshLiveWeather(lat: point.latitude, lon: point.longitude);
    }
    return null;
  }

  void clearSelection() {
    polygonPoints.clear();
    drawing = false;
    result = null;
    bumpMapVisual();
  }

  void toggleSatellite() {
    satellite = !satellite;
    bumpMapVisual();
  }

  void toggleDrawing() {
    drawing = !drawing;
    bumpMapVisual();
  }

  @override
  void dispose() {
    _sessionEpoch++;
    _disposed = true;
    _loadingTimer?.cancel();
    _weatherRefreshTimer?.cancel();
    mapController.dispose();
    api.close();
    latController.dispose();
    lonController.dispose();
    super.dispose();
  }

  String tileUrl() => satellite
      ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  String numText(dynamic value) {
    final n = value is num ? value : num.tryParse('$value');
    return n == null ? '--' : n.toStringAsFixed(3);
  }
}

class ShellPage extends StatefulWidget {
  final AnalysisState? analysisState;
  const ShellPage({super.key, this.analysisState});
  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> with WidgetsBindingObserver {
  late final AnalysisState state;
  int index = 0;

  @override
  void initState() {
    super.initState();
    state = widget.analysisState ?? AnalysisState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!state.userLoaded) {
        state.loadUserData().then((_) {
          if (mounted) state.refreshFarms();
        });
      }
      state.refreshLiveWeather();
      state.startWeatherAutoRefresh();
      if (state.userLoaded) state.refreshFarms();
    });
  }

  Future<void> logout() async {
    await state.api.logout();
    state.clearUserData();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  void message(String text) {
    if (!mounted || text.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) {
      state.refreshHistoryData();
      state.refreshFarms();
    }
  }

  void selectTab(int i) {
    setState(() => index = i);
    if (i == 1) state.refreshFarms();
    if (i == 2 || i == 3) state.refreshHistoryData();
  }

  Future<void> openAnalysis(Map<String, dynamic> record) async {
    final error = await state.selectAnalysis(record);
    if (!mounted) return;
    if (error != null) {
      message(error);
      return;
    }
    selectTab(2);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => _buildShell(context),
    );
  }

  Widget _buildShell(BuildContext context) {
    Widget tab(Widget Function() builder) =>
        ListenableBuilder(listenable: state, builder: (_, _) => builder());

    final isDesktopWeb = MediaQuery.of(context).size.width >= 900;

    if (!state.userLoaded) {
      return const Scaffold(
        backgroundColor: bg,
        body: Center(child: CircularProgressIndicator(color: green)),
      );
    }

    if (state.accountRole.contains('unknown')) {
      return AccessDeniedPage(
        desktopAttempt: isDesktopWeb,
        logout: logout,
        customTitle: 'Unable to verify account access',
        customMessage:
            'GeoSustain could not load this account role from the server. Please log out, sign in again, and make sure the backend is live.',
      );
    }

    if (!isDesktopWeb && (state.isAnalystRole || state.isSuperAdmin)) {
      return AccessDeniedPage(desktopAttempt: false, logout: logout);
    }

    if (isDesktopWeb && state.isSuperAdmin) {
      return WebAdminDashboard(logout: logout, message: message);
    }

    if (isDesktopWeb && state.isAnalystRole) {
      return Scaffold(
        body: Stack(
          children: [
            WebAnalystDashboard(state: state, logout: logout, message: message),
            ListenableBuilder(
              listenable: state,
              builder: (_, _) => state.loading
                  ? FullscreenAnalysisOverlay(message: state.loadingMessage)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
    }

    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && index != 0) selectTab(0);
      },
      child: Scaffold(
        body: Stack(
          children: [
            IndexedStack(
              index: index,
              children: [
                tab(
                  () => HomePage(
                    state: state,
                    go: selectTab,
                    logout: logout,
                    message: message,
                  ),
                ),
                tab(
                  () =>
                      MyFarmsPage(state: state, onAnalyzed: () => selectTab(2)),
                ),
                tab(
                  () => MobileAnalysisPage(
                    state: state,
                    goFarms: () => selectTab(1),
                  ),
                ),
                tab(
                  () => HistoryPage(
                    api: state.api,
                    state: state,
                    onOpenAnalysis: openAnalysis,
                    goFarms: () => selectTab(1),
                  ),
                ),
                tab(() => ProfilePage(state: state, logout: logout)),
              ],
            ),
            ListenableBuilder(
              listenable: state,
              builder: (_, _) => state.loading
                  ? FullscreenAnalysisOverlay(message: state.loadingMessage)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          height: 76,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          indicatorColor: softGreen,
          onDestinationSelected: selectTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home, color: green),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map, color: green),
              label: 'My Farms',
            ),
            NavigationDestination(
              icon: Icon(Icons.center_focus_strong_outlined),
              selectedIcon: Icon(Icons.center_focus_strong, color: green),
              label: 'Analysis',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history, color: green),
              label: 'History',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person, color: green),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

class AccessDeniedPage extends StatelessWidget {
  final bool desktopAttempt;
  final Future<void> Function() logout;
  final String? customTitle;
  final String? customMessage;

  const AccessDeniedPage({
    super.key,
    required this.desktopAttempt,
    required this.logout,
    this.customTitle,
    this.customMessage,
  });

  @override
  Widget build(BuildContext context) {
    final title =
        customTitle ??
        (desktopAttempt
            ? 'Farmer account detected'
            : 'Analyst account detected');
    final message =
        customMessage ??
        (desktopAttempt
            ? 'This account is registered as a Farmer account and cannot access the web analyst dashboard. Please use the mobile farmer app for field analysis, crop recommendations, weather alerts, and farm reports.'
            : 'This account is registered as an Analyst account and is intended for the web dashboard. Please open GeoSustain on a desktop browser to access analyst tools, GIS monitoring, trends, and reports.');

    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 28,
                offset: Offset(0, 12),
              ),
            ],
            border: Border.all(color: const Color(0xFFE3EEE7)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 72,
                width: 72,
                decoration: BoxDecoration(
                  color: softGreen,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  desktopAttempt
                      ? Icons.agriculture_rounded
                      : Icons.dashboard_customize_rounded,
                  color: green,
                  size: 38,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () async => logout(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Back to login'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FullscreenAnalysisOverlay extends StatelessWidget {
  final String message;
  const FullscreenAnalysisOverlay({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final steps = const [
      'Checking selected field',
      'Fetching rainfall and weather',
      'Reading elevation and slope',
      'Generating recommendation',
    ];
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.42),
        child: Center(
          child: Container(
            width: 310,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: .75, end: 1.0),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeInOut,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: const BoxDecoration(
                      color: softGreen,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 34,
                        height: 34,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: green,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Analyzing selected area',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: green,
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    message,
                    key: ValueKey(message),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF29352E),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...steps.map(
                  (step) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 17,
                          color: green,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            step,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Please wait. This may take a few seconds on Render free tier.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RoleFeatureCard extends StatelessWidget {
  final AnalysisState state;
  const RoleFeatureCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final analyst = state.isAnalystRole;
    final capabilities = state.roleCapabilities;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: analyst ? const Color(0xFFEAF2FF) : softGreen,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    analyst
                        ? Icons.insights_rounded
                        : Icons.agriculture_rounded,
                    color: green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.roleDashboardTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        analyst
                            ? 'Independent analyst/planner tools for risk, trends, and area review.'
                            : 'Farmer tools for crop decisions, alerts, and farm records.',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...capabilities.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 16, color: green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: analyst
                  ? const [
                      RolePill(
                        icon: Icons.compare_arrows_rounded,
                        label: 'Area Compare',
                      ),
                      RolePill(
                        icon: Icons.warning_amber_rounded,
                        label: 'Risk Review',
                      ),
                      RolePill(
                        icon: Icons.query_stats_rounded,
                        label: 'Trend Summary',
                      ),
                      RolePill(
                        icon: Icons.description_rounded,
                        label: 'Planning Report',
                      ),
                    ]
                  : const [
                      RolePill(icon: Icons.eco_rounded, label: 'Crop Decision'),
                      RolePill(
                        icon: Icons.cloud_rounded,
                        label: 'Weather Watch',
                      ),
                      RolePill(
                        icon: Icons.bookmark_rounded,
                        label: 'Saved Fields',
                      ),
                      RolePill(
                        icon: Icons.picture_as_pdf_rounded,
                        label: 'Farm Report',
                      ),
                    ],
            ),
            if (analyst) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F8FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Analyst mode prioritizes summaries, risk indicators, polygon sample count, and planning reports. Farmer mode prioritizes crop choice, weather alerts, and farm records.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.black54,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class RolePill extends StatelessWidget {
  final IconData icon;
  final String label;
  const RolePill({super.key, required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: const Color(0xFFDCEBE2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: green),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: green,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class PlannerRiskToolsCard extends StatelessWidget {
  final AnalysisState state;
  const PlannerRiskToolsCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final r = state.result;
    final risk =
        r?['flood_risk'] ??
        r?['risk_level'] ??
        r?['infrastructure_risk'] ??
        '--';
    final slope = state.numText(r?['slope_deg'] ?? r?['slope']);
    final elevation = state.numText(r?['elevation_m']);
    final ndvi = state.numText(r?['ndvi']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('PLANNER / ANALYST TOOLS'),
            const SizedBox(height: 10),
            const Text(
              'Use this view for independent environmental planning, area comparison, and risk interpretation. This is not tied to any government agency.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                InfoChip(label: 'Risk', value: '$risk'),
                InfoChip(label: 'Slope', value: '$slope°'),
                InfoChip(label: 'Elevation', value: '$elevation m'),
                InfoChip(label: 'NDVI', value: ndvi),
                InfoChip(
                  label: 'Samples',
                  value: '${r?['polygon_area_sample_count'] ?? '--'}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const InfoChip({super.key, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: softGreen,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFDCEBE2)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.black54,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w900, color: green),
        ),
      ],
    ),
  );
}

class MobileHeader extends StatelessWidget {
  final String title;
  final bool showMenu;
  final Widget? trailing;
  final VoidCallback? back;
  const MobileHeader({
    super.key,
    required this.title,
    this.showMenu = true,
    this.trailing,
    this.back,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      child: Row(
        children: [
          back != null
              ? IconButton(onPressed: back, icon: const Icon(Icons.arrow_back))
              : const _FieldIcon(Icons.eco_outlined),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: green,
              ),
            ),
          ),
          trailing ??
              IconButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationsPage()),
                ),
                icon: const Icon(Icons.notifications_none_rounded),
              ),
        ],
      ),
    );
  }
}
