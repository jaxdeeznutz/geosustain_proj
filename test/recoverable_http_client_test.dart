import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:geosustain_clean_arranged/recoverable_http_client.dart';

class _TrackedClient extends http.BaseClient {
  final http.Client delegate;
  bool closed = false;
  _TrackedClient(this.delegate);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      delegate.send(request);
  @override
  void close() {
    closed = true;
    delegate.close();
  }
}

void main() {
  test(
    'renewal preserves an in-flight write and uses a fresh pool for reads',
    () async {
      final write = Completer<http.Response>();
      var posts = 0;
      final old = _TrackedClient(
        MockClient((request) {
          posts++;
          expect(request.method, 'POST');
          return write.future;
        }),
      );
      final fresh = _TrackedClient(
        MockClient((request) async => http.Response('connected', 200)),
      );
      final pools = [old, fresh].iterator;
      final client = RecoverableHttpClient(
        factory: () {
          pools.moveNext();
          return pools.current;
        },
      );
      addTearDown(client.close);
      final pending = client.post(Uri.parse('https://test.invalid/analysis'));
      await Future<void>.delayed(Duration.zero);
      client.renew();
      expect(old.closed, isFalse);
      expect(
        (await client.get(Uri.parse('https://test.invalid/history'))).body,
        'connected',
      );
      write.complete(http.Response('saved', 201));
      expect((await pending).statusCode, 201);
      expect(old.closed, isTrue);
      expect(posts, 1);
      expect(fresh.closed, isFalse);
    },
  );

  test(
    'failed request is not silently replayed and closed clients reject sends',
    () async {
      var calls = 0;
      final client = RecoverableHttpClient(
        factory: () => MockClient((request) async {
          calls++;
          throw http.ClientException('connection failed');
        }),
      );
      await expectLater(
        client.post(Uri.parse('https://test.invalid/analysis')),
        throwsA(isA<http.ClientException>()),
      );
      expect(calls, 1);
      client.close();
      await expectLater(
        client.get(Uri.parse('https://test.invalid/history')),
        throwsA(isA<http.ClientException>()),
      );
    },
  );
}
