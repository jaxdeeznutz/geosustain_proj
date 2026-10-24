import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/session_token_store.dart';
import 'package:geosustain_clean_arranged/offline_farm_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OfflineFarmStore.resetTestState();
    String? protectedToken;
    final workspace = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SessionTokenStore.channel, (call) async {
          switch (call.method) {
            case 'workspaceRead':
              return workspace[(call.arguments as Map)['owner']];
            case 'workspaceWrite':
              final args = call.arguments as Map;
              workspace[args['owner'] as String] = args['value'] as String;
              return null;
            case 'workspaceDelete':
              workspace.remove((call.arguments as Map)['owner']);
              return null;
            case 'read':
              return protectedToken;
            case 'write':
              protectedToken = call.arguments as String;
              return null;
            case 'delete':
              protectedToken = null;
              return null;
          }
          throw StateError('Unexpected session storage operation');
        });
  });
  await testMain();
}
