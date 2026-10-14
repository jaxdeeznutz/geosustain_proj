import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';

void main() {
  test(
    'recommendations show only five descending scores, ignoring old rank',
    () {
      final record = <String, dynamic>{
        'scoring_version': 'old-reference-version',
        'crop_assessments': [
          for (var i = 0; i < 7; i++)
            {'crop': 'Crop $i', 'compatibility_pct': i * 10, 'rank': 7 - i},
          {'crop': 'Missing', 'compatibility_pct': null},
        ],
      };
      final crops = rankedCropRecommendations(record);
      expect(crops.map((c) => c['compatibility_pct']), [60, 50, 40, 30, 20]);
      expect(crops.map((c) => c['rank']), [1, 2, 3, 4, 5]);
      expect((record['crop_assessments'] as List).first['rank'], 7);
    },
  );

  test(
    'legacy primary cannot displace a higher score; zero is not missing',
    () {
      final crops = rankedCropRecommendations({
        'predicted_crop': 'Rice',
        'top_crop_recommendations': [
          {'crop': 'Rice', 'compatibility_pct': 10},
          {'crop': 'Banana', 'compatibility_pct': 60},
          {'crop': 'Cacao', 'compatibility_pct': 0},
        ],
      });
      expect(crops.map((c) => c['crop']), ['Banana', 'Rice', 'Cacao']);
    },
  );
}
