import 'package:flutter_test/flutter_test.dart';
import 'recommendation_summary_cases.dart';

void main() {
  for (final entry in summaryCases.entries) {
    test(entry.key, entry.value);
  }
}
