import 'package:http/http.dart' as http;

/// Replaces a failed connection pool without cancelling unrelated requests.
/// Requests are never replayed here; ApiService controls safe read retries and
/// retrieves interrupted writes by their existing idempotency key.
class RecoverableHttpClient extends http.BaseClient {
  final http.Client Function() _factory;
  final Set<_TransportLease> _leases = {};
  late _TransportLease _current;
  bool _closed = false;

  RecoverableHttpClient({http.Client Function()? factory})
    : _factory = factory ?? http.Client.new {
    _current = _TransportLease(_factory());
    _leases.add(_current);
  }

  void renew() {
    if (_closed) return;
    final old = _current;
    old.retired = true;
    _current = _TransportLease(_factory());
    _leases.add(_current);
    _releaseIfIdle(old);
  }

  void _releaseIfIdle(_TransportLease lease) {
    if (lease.retired && lease.active == 0 && _leases.remove(lease)) {
      lease.client.close();
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('Client is closed.', request.url);
    final lease = _current;
    lease.active++;
    try {
      final response = await lease.client.send(request);
      Stream<List<int>> body() async* {
        try {
          yield* response.stream;
        } finally {
          lease.active--;
          _releaseIfIdle(lease);
        }
      }

      return http.StreamedResponse(
        body(),
        response.statusCode,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (_) {
      lease.active--;
      _releaseIfIdle(lease);
      rethrow;
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    for (final lease in _leases) {
      lease.client.close();
    }
    _leases.clear();
  }
}

class _TransportLease {
  final http.Client client;
  int active = 0;
  bool retired = false;
  _TransportLease(this.client);
}
