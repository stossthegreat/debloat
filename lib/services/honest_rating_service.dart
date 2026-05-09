import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'local_store_service.dart';

/// The honest-looks score — GPT-4o Vision's candid read of the user's
/// actual photo. This is the *second* of the two-score moat (the first
/// being on-device geometry).
///
/// Pure vision: the backend does NOT pass geometry numbers to GPT, so
/// a great-bones/bad-skin face doesn't get bailed out by number
/// contamination. The two scores are independent by design.
class HonestRating {
  final int score;      // 0..100
  final String tier;    // exceptional|strong|above_average|average|
                        // below_average|weak|struggling
  final String note;    // one-line observation citing what was visible

  const HonestRating({
    required this.score,
    required this.tier,
    required this.note,
  });

  String get tierLabel => switch (tier) {
    'exceptional'   => 'Exceptional',
    'strong'        => 'Strong',
    'above_average' => 'Above average',
    'average'       => 'Average',
    'below_average' => 'Below average',
    'weak'          => 'Weak',
    'struggling'    => 'Struggling',
    _               => 'Read',
  };
}

class HonestRatingService {
  /// POST /rate — returns null if the model refused (rare with the
  /// server-side retry ladder, but handled cleanly so the UI degrades
  /// to geometry-only rather than showing an error).
  ///
  /// Caller passes the base64-encoded selfie (same bytes we send to
  /// /scan — fire them in parallel to keep the perceived latency flat).
  static Future<HonestRating?> rate({required String imageBase64}) async {
    try {
      final gender = await LocalStoreService.userGender();
      final res = await http.post(
        Uri.parse('${ApiConfig.backendBaseUrl}/rate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'imageBase64': imageBase64,
          if (gender != null) 'gender': gender,
        }),
      ).timeout(const Duration(seconds: 60));

      if (res.statusCode != 200) return null;

      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      if (decoded['refused'] == true) return null;

      final score = decoded['score'];
      if (score is! num) return null;

      return HonestRating(
        score: score.round().clamp(0, 100),
        tier:  (decoded['tier'] as String?) ?? 'average',
        note:  (decoded['note'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
