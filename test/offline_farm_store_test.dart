import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geosustain_clean_arranged/offline_farm_store.dart';

void main() {
  const polygon = [
    {'lat': 7.3922, 'lon': 125.6227},
    {'lat': 7.3922, 'lon': 125.6231},
    {'lat': 7.3926, 'lon': 125.6231},
  ];
  Future<Map<String, dynamic>> save(String key) => OfflineFarmStore.save(
    requestId: key,
    name: 'Offline farm $key',
    location: 'Test only',
    polygon: polygon,
    method: 'gps_walk',
    capture: [
      {'timestamp': '2026-10-23T01:02:03Z', 'accuracy_m': 9.0},
    ],
  );
  setUp(() => SharedPreferences.setMockInitialValues({'account_id': '10'}));
  test(
    'separate pending farms and real capture metadata survive reread',
    () async {
      await save('one');
      await save('two');
      final data = await OfflineFarmStore.read();
      final farms = OfflineFarmStore.rows(data['pending']);
      expect(farms, hasLength(2));
      expect(farms.first['capture'][0]['timestamp'], '2026-10-23T01:02:03Z');
      expect(farms.first['capture'][0]['accuracy_m'], 9);
      expect(farms.first['area_hectares'], greaterThan(0));
    },
  );
  test(
    'same request retry keeps one local record; changed inputs are rejected',
    () async {
      await save('same');
      await save('same');
      expect(
        OfflineFarmStore.rows((await OfflineFarmStore.read())['pending']),
        hasLength(1),
      );
      await expectLater(
        OfflineFarmStore.save(
          requestId: 'same',
          name: 'Different farm',
          location: 'Test only',
          polygon: polygon,
          method: 'gps_walk',
        ),
        throwsStateError,
      );
    },
  );
  test(
    'network failure retains exact retry identity and needs-attention state',
    () async {
      await save('retry');
      await expectLater(
        OfflineFarmStore.sync(
          (_) async => throw TimeoutException('offline'),
          (_) => 'Reconnect and retry.',
        ),
        throwsA(isA<TimeoutException>()),
      );
      final farm = OfflineFarmStore.rows(
        (await OfflineFarmStore.read())['pending'],
      ).single;
      expect(farm['request_id'], 'retry');
      expect(farm['sync_state'], 'Needs attention');
      expect(farm['selected_polygon'], polygon);
    },
  );
  test(
    'acknowledged upload removes pending only once and creates one sync event',
    () async {
      await save('upload');
      int posts = 0;
      Future<Map<String, dynamic>> upload(Map<String, dynamic> local) async {
        posts++;
        return {
          'id': 42,
          'farmer_id': 10,
          'farm_name': local['farm_name'],
          'polygon': polygon,
        };
      }

      await OfflineFarmStore.sync(upload, (_) => 'Retry');
      await OfflineFarmStore.sync(upload, (_) => 'Retry');
      final data = await OfflineFarmStore.read();
      expect(posts, 1);
      expect(data['pending'], isEmpty);
      expect(OfflineFarmStore.rows(data['farms']).single['id'], 42);
      expect(OfflineFarmStore.rows(data['events']), hasLength(1));
    },
  );
  test(
    'foreign account sees no queue; returning owner retains pending data',
    () async {
      await save('private');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('account_id', '11');
      expect((await OfflineFarmStore.read())['pending'], isEmpty);
      int posts = 0;
      await OfflineFarmStore.sync((_) async {
        posts++;
        return {};
      }, (_) => 'Retry');
      expect(posts, 0);
      await prefs.setString('account_id', '10');
      expect(
        OfflineFarmStore.rows(
          (await OfflineFarmStore.read())['pending'],
        ).single['request_id'],
        'private',
      );
    },
  );
  test(
    'account switch during upload cannot commit acknowledgement to another owner',
    () async {
      await save('switch');
      final prefs = await SharedPreferences.getInstance();
      final response = Completer<Map<String, dynamic>>(),
          started = Completer<void>();
      final work = OfflineFarmStore.sync((_) {
        started.complete();
        return response.future;
      }, (_) => 'Retry');
      final failure = expectLater(work, throwsStateError);
      await started.future;
      await prefs.setString('account_id', '11');
      response.complete({'id': 42, 'farmer_id': 10});
      await failure;
      expect((await OfflineFarmStore.read())['pending'], isEmpty);
      await prefs.setString('account_id', '10');
      expect((await OfflineFarmStore.read())['pending'], hasLength(1));
    },
  );
  test('foreign server acknowledgement retains pending farm', () async {
    await save('owner');
    await expectLater(
      OfflineFarmStore.sync(
        (_) async => {'id': 42, 'farmer_id': 11},
        (_) => 'Wrong account',
      ),
      throwsStateError,
    );
    expect((await OfflineFarmStore.read())['pending'], hasLength(1));
  });
  test('confirmed account deletion clears its device workspace only', () async {
    await save('delete');
    await OfflineFarmStore.deleteCurrentAccountData();
    expect((await OfflineFarmStore.read())['pending'], isEmpty);
  });
}
