import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:geosustain_clean_arranged/main.dart';
import 'package:geosustain_clean_arranged/api_service.dart';

void main() {
  test('transport failures never assert offline without evidence', () {
    final message = friendlyErrorMessage(
      http.ClientException(
        'Failed to fetch',
        Uri.parse('https://private.example'),
      ),
    );
    expect(message, "Couldn't reach the analysis service. Try again.");
    expect(message, isNot(contains('private')));
  });
  test('HTTP status wins over misleading body text', () {
    expect(
      friendlyErrorMessage(const ApiException(503, 'connection refused 401')),
      contains('service is unavailable'),
    );
    expect(
      friendlyErrorMessage(const ApiException(401, 'Invalid token')),
      contains('session has expired'),
    );
    expect(
      friendlyErrorMessage(const ApiException(422, 'Boundary crosses itself')),
      'Boundary crosses itself',
    );
    expect(
      friendlyErrorMessage(
        const ApiException(202, 'Analysis is still running'),
      ),
      'Analysis is still running',
    );
    expect(
      friendlyErrorMessage(TimeoutException('private URL')),
      contains('existing analysis'),
    );
    expect(
      friendlyErrorMessage(StateError('secret internal detail')),
      isNot(contains('secret')),
    );
  });
}
