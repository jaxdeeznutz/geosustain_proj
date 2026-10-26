import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/web/analysis_metrics.dart';

void main() {
  test(
    'zero is assessed, missing/preliminary are not, sessions are deduplicated',
    () {
      final rows = <Map<String, dynamic>>[
        {'session_id': 1, 'predicted_crop': 'Rice', 'compatibility_pct': 0},
        {'session_id': 1, 'predicted_crop': 'Rice', 'compatibility_pct': 0},
        {'session_id': 2, 'predicted_crop': 'Maize', 'compatibility_pct': 100},
        {'session_id': 3, 'predicted_crop': 'Rice'},
        {
          'session_id': 4,
          'predicted_crop': 'Rice',
          'compatibility_pct': 99,
          'analysis_mode': 'preliminary_environmental',
        },
        {
          'session_id': 5,
          'predicted_crop': 'Water',
          'compatibility_pct': 90,
          'is_crop_recommended': false,
        },
      ];
      final result = WebAnalysisMetrics(rows);
      expect(result.records.length, 5);
      expect(result.average, 50);
      expect(result.scores.length, 2);
      expect(result.scoreBands, [1, 0, 0, 1]);
      expect(result.frequencies, {'Rice': 2, 'Maize': 1});
      expect(result.mostFrequent, 'Rice');
      expect(WebAnalysisMetrics([]).average, isNull);
      expect(
        WebAnalysisMetrics([
          {'predicted_crop': 'Rice', 'compatibility_pct': double.nan},
        ]).average,
        isNull,
      );
    },
  );
}
