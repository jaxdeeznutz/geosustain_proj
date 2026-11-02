import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/api_service.dart';
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/web/portal_routes.dart';

// Synthetic UI fixtures only. These values are never provider observations.
class _AdminFixture {
  final requests = <http.Request>[];
  final users = <Map<String, dynamic>>[
    {
      'id': 1,
      'username': 'Synthetic Administrator',
      'email': 'admin@example.com',
      'role': 'super_admin',
      'is_active': true,
      'auth_provider': 'email',
      'created_at': '2026-10-01T08:00:00Z',
    },
    {
      'id': 2,
      'username': 'Synthetic Farmer',
      'email': 'farmer@example.com',
      'role': 'farmer',
      'is_active': true,
      'auth_provider': 'email',
      'created_at': '2026-10-02T08:00:00Z',
    },
    {
      'id': 3,
      'username': '',
      'email': 'other@example.com',
      'role': 'agricultural_planning_analyst',
      'is_active': false,
      'auth_provider': 'google',
    },
  ];
  final crops = <Map<String, dynamic>>[
    {
      'crop_key': 'rice',
      'label': 'Rice',
      'growth_cycle': 'Synthetic 4 months',
      'est_yield': 'Synthetic yield',
      'suitability_note': 'Fixture reference only.',
      'is_active': true,
    },
    {'crop_key': 'mango', 'label': 'Mango', 'is_active': false},
  ];
  final analyses = <Map<String, dynamic>>[
    {
      'session_id': 11,
      'username': 'Synthetic Farmer',
      'email': 'farmer@example.com',
      'role': 'farmer',
      'place_name': 'Synthetic North',
      'predicted_crop': 'Rice',
      'crop_compatibility_pct': 0,
      'area_hectares': 1.25,
      'verification_status': 'verified',
      'analyzed_at': '2026-10-03T08:00:00Z',
    },
    {
      'session_id': 12,
      'username': 'Synthetic Farmer',
      'role': 'farmer',
      'place_name': 'Synthetic South',
      'analysis_mode': 'preliminary_environmental',
      'predicted_crop': 'Stale crop claim',
      'area_hectares': 0.5,
      'verification_status': 'pending',
      'analyzed_at': '2026-10-04T08:00:00Z',
    },
  ];
  final logs = <Map<String, dynamic>>[
    {
      'id': 21,
      'actor_username': 'Synthetic Administrator',
      'actor_role': 'super_admin',
      'action': 'user_update',
      'created_at': '2026-10-05T08:00:00Z',
      'details': {
        'role': {'from': 'farmer', 'to': 'agricultural_planning_analyst'},
        'is_active': {'from': false, 'to': true},
        'token': 'private-secret-never-render',
      },
    },
    {
      'id': 22,
      'actor_reference': 'Synthetic reviewer',
      'actor_role': 'analyst',
      'action': 'verification_decision',
      'created_at': '2026-10-06T08:00:00Z',
      'details': {'decision': 'verified'},
    },
    {
      'id': 23,
      'actor_username': 'Synthetic Administrator',
      'actor_role': 'super_admin',
      'action': 'controlled_record_activation',
      'created_at': '2026-10-07T08:00:00Z',
      'details': {
        'kind': 'supporting_reference',
        'record_key': 'synthetic_reference',
        'before_record_id': 1,
        'after_record_id': 2,
        'generation': 4,
      },
    },
  ];
  late final api = ApiService(
    client: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (request.method == 'PATCH' && path.contains('/users/')) {
        final user = users.firstWhere(
          (u) => '${u['id']}' == path.split('/').last,
        );
        user.addAll(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
        return http.Response(jsonEncode({'user': user}), 200);
      }
      if (request.method == 'PATCH' && path.contains('/crops/')) {
        final row = crops.firstWhere(
          (c) => c['crop_key'] == path.split('/').last,
        );
        row.addAll(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
        return http.Response(jsonEncode({'crop': row}), 200);
      }
      if (path.endsWith('/dashboard')) {
        return http.Response(
          jsonEncode({
            'stats': {
              'farmers': 1,
              'planning_analysts': 1,
              'super_admins': 1,
              'active_users': 2,
              'inactive_users': 1,
              'registered_parcels': 3,
              'total_area_hectares': 1.75,
              'total_analyses': 2,
              'pending': 1,
              'verified': 1,
            },
          }),
          200,
        );
      }
      if (path.endsWith('/catalog')) {
        return http.Response(
          File('test/fixtures/controlled_catalog.json').readAsStringSync(),
          200,
        );
      }
      if (path.endsWith('/controlled-records')) {
        return http.Response(
          jsonEncode({'records': [], 'has_more': false}),
          200,
        );
      }
      final key = path.endsWith('/users')
          ? 'users'
          : path.endsWith('/analyses')
          ? 'analyses'
          : path.endsWith('/crops')
          ? 'crops'
          : 'logs';
      final data = switch (key) {
        'users' => users,
        'analyses' => analyses,
        'crops' => crops,
        _ => logs,
      };
      final query = request.url.queryParameters['q'] ?? '';
      return http.Response(
        jsonEncode({
          key: data
              .where(
                (r) =>
                    jsonEncode(r).toLowerCase().contains(query.toLowerCase()),
              )
              .toList(),
          'has_more': false,
        }),
        200,
      );
    }),
  );
}

Future<void> _pumpAdmin(
  WidgetTester tester,
  _AdminFixture fixture,
  String route, {
  Size size = const Size(1440, 1000),
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  appThemeMode.value = dark ? ThemeMode.dark : ThemeMode.light;
  PortalRoutes.go('/admin/$route');
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: green,
          brightness: dark ? Brightness.dark : Brightness.light,
        ),
        fontFamily: 'Roboto',
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: RepaintBoundary(
        key: const ValueKey('superadmin-preview'),
        child: WebAdminDashboard(
          api: fixture.api,
          logout: () {},
          message: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _preview(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('superadmin-preview')),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/superadmin-redesign-previews')
      ..createSync(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Custom body styles deliberately inherit the platform's default family.
    // Widget tests use Ahem for that default; load readable glyphs for PNG QA.
    for (final family in ['Roboto', 'Ahem']) {
      final fonts = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
      await fonts.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    appThemeMode.value = ThemeMode.light;
    PortalRoutes.go('/');
  });
  const pages = {
    'dashboard': 'Super Administrator Dashboard',
    'users': 'User List',
    'analyses': 'Farm & Analysis Records',
    'crops': 'Approved crop reference',
    'audit': 'Recent Activity Logs',
  };
  for (final entry in pages.entries) {
    for (final size in [
      const Size(360, 800),
      const Size(480, 700),
      const Size(1440, 1000),
      const Size(1920, 1080),
    ]) {
      testWidgets('admin ${entry.key} fits $size', (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = _AdminFixture();
        await _pumpAdmin(tester, fixture, entry.key, size: size);
        expect(find.text(entry.value), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(fixture.requests.where((r) => r.method != 'GET'), isEmpty);
        expect(
          find.textContaining('private-secret-never-render'),
          findsNothing,
        );
        if (size.width == 1440) {
          await _preview(tester, entry.key);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.api.close();
      });
    }
    testWidgets('admin ${entry.key} supports dark mode and enlarged text', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = _AdminFixture();
      await _pumpAdmin(
        tester,
        fixture,
        entry.key,
        size: const Size(480, 900),
        scale: 2,
        dark: true,
      );
      expect(find.text(entry.value), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.api.close();
    });
  }

  testWidgets('dashboard metric rows and lower panels have matching edges', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = _AdminFixture();
    await _pumpAdmin(
      tester,
      fixture,
      'dashboard',
      size: const Size(1920, 1200),
    );
    Rect metric(String name) =>
        tester.getRect(find.byKey(ValueKey('metric-$name')));
    for (final label in [
      'Planning Analysts',
      'Pending Submissions',
      'Registered Parcels',
    ]) {
      expect(metric(label).top, closeTo(metric('Total Farmers').top, .1));
      expect(metric(label).bottom, closeTo(metric('Total Farmers').bottom, .1));
    }
    for (final label in [
      'Verified Analyses',
      'Inactive Accounts',
      'Mapped Area',
    ]) {
      expect(metric(label).top, closeTo(metric('Total Analyses').top, .1));
      expect(
        metric(label).bottom,
        closeTo(metric('Total Analyses').bottom, .1),
      );
    }
    expect(find.text('98%'), findsNothing);
    final recent = tester.getRect(
      find.byKey(const ValueKey('admin-recent-activity')),
    );
    final overview = tester.getRect(
      find.byKey(const ValueKey('admin-system-overview')),
    );
    expect(recent.top, closeTo(overview.top, .1));
    expect(recent.bottom, closeTo(overview.bottom, .1));
    expect(find.text('All Systems Operational'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.api.close();
  });

  testWidgets(
    'user role status and recovery cancellation retain their request semantics',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = _AdminFixture();
      await _pumpAdmin(tester, fixture, 'users', size: const Size(1920, 1200));
      await tester.tap(find.byKey(const ValueKey('admin-role-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Planning Analyst').last);
      await tester.pumpAndSettle();
      final rolePatch = fixture.requests.lastWhere((r) => r.method == 'PATCH');
      expect(rolePatch.url.path, endsWith('/users/2'));
      expect(jsonDecode(rolePatch.body), {
        'role': 'agricultural_planning_analyst',
      });
      await tester.tap(find.byKey(const ValueKey('admin-active-2')));
      await tester.pumpAndSettle();
      expect(
        jsonDecode(fixture.requests.lastWhere((r) => r.method == 'PATCH').body),
        {'is_active': false},
      );
      await tester.tap(
        find.byTooltip('Recover account for Synthetic Administrator'),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Use the project identity-verification procedure'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        fixture.requests.where((r) => r.url.path.endsWith('/recovery')),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.api.close();
    },
  );

  testWidgets(
    'search remains server scoped and local role filter changes displayed rows',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = _AdminFixture();
      await _pumpAdmin(tester, fixture, 'users');
      final roleFilter = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Role',
      );
      await tester.tap(roleFilter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Farmer').last);
      await tester.pumpAndSettle();
      expect(find.text('Synthetic Farmer'), findsOneWidget);
      expect(find.text('Synthetic Administrator'), findsNothing);
      final search = find.byKey(const ValueKey('admin-search-1-'));
      await tester.enterText(search, 'Synthetic Farmer');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        fixture.requests
            .lastWhere((r) => r.url.path.endsWith('/users'))
            .url
            .queryParameters['q'],
        'Synthetic Farmer',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.api.close();
    },
  );

  testWidgets(
    'monitoring suppresses preliminary crop claims and inspects the selected saved record',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = _AdminFixture();
      await _pumpAdmin(
        tester,
        fixture,
        'analyses',
        size: const Size(1920, 1200),
      );
      expect(find.text('Stale crop claim'), findsNothing);
      expect(find.text('Suitable'), findsNothing);
      await tester.ensureVisible(find.byTooltip('View analysis 12'));
      await tester.tap(find.byTooltip('View analysis 12'));
      await tester.pumpAndSettle();
      expect(find.text('Saved analysis #12'), findsOneWidget);
      expect(find.text('Recorded result: Land assessment'), findsOneWidget);
      expect(fixture.requests.where((r) => r.method != 'GET'), isEmpty);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.api.close();
    },
  );

  testWidgets('crop search and activation keep the existing patch contract', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = _AdminFixture();
    await _pumpAdmin(tester, fixture, 'crops');
    await tester.ensureVisible(find.byKey(const ValueKey('admin-crop-search')));
    await tester.enterText(
      find.byKey(const ValueKey('admin-crop-search')),
      'rice',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('admin-crop-mango')), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('admin-crop-rice')));
    await tester.tap(find.byKey(const ValueKey('admin-crop-rice')));
    await tester.pumpAndSettle();
    final patch = fixture.requests.lastWhere((r) => r.method == 'PATCH');
    expect(patch.url.path, endsWith('/crops/rice'));
    expect(jsonDecode(patch.body), {'is_active': false});
    expect(fixture.requests.where((r) => r.method == 'POST'), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.api.close();
  });

  testWidgets(
    'audit filter details and monitoring use real records without inventing health',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = _AdminFixture();
      await _pumpAdmin(tester, fixture, 'audit', size: const Size(1920, 1200));
      final action = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Action',
      );
      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.tap(find.text('controlled record activation').last);
      await tester.pumpAndSettle();
      final details = find.textContaining('generation: 4');
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.text('Recorded change details'), findsOneWidget);
      expect(find.textContaining('before record id: 1'), findsWidgets);
      expect(find.textContaining('private-secret-never-render'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('System Monitoring').first);
      await tester.tap(find.text('System Monitoring').first);
      await tester.pumpAndSettle();
      expect(find.text('Health not reported'), findsOneWidget);
      expect(find.text('All Systems Operational'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.api.close();
    },
  );

  testWidgets('narrow navigation opens and closes its drawer after selection', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = _AdminFixture();
    await _pumpAdmin(tester, fixture, 'dashboard', size: const Size(480, 800));
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-nav-users')));
    await tester.pumpAndSettle();
    expect(PortalRoutes.current.value.path, '/admin/users');
    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
    expect(scaffold.isDrawerOpen, isFalse);
    expect(find.text('User List'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.api.close();
  });
}
