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

  /// Per-domain sub-scores from GPT vision. Optional — present when the
  /// /rate backend has been updated to return them, absent otherwise
  /// (the report page derives fallbacks from geometry so it never
  /// renders empty). Expected keys: skin, hair, jawline, masculinity,
  /// eyes, face. Each value is 0..100.
  final Map<String, int>? subScores;

  /// Per-domain short qualifier from GPT — e.g. "Clear healthy skin",
  /// "Full Hair", "Hunter Eyes", "High Dimorphism". Optional, falls
  /// back to a computed tier word per axis when null.
  final Map<String, String>? subTiers;

  /// AI VERDICT — four blocks rendered as cards under the HeroCard:
  /// biggest strength, biggest weakness, fastest 60-day win, and the
  /// potential gain projection. Null when the backend hasn't been
  /// upgraded yet — the UI hides the panel in that case.
  final HonestVerdict? verdict;

  const HonestRating({
    required this.score,
    required this.tier,
    required this.note,
    this.subScores,
    this.subTiers,
    this.verdict,
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

/// AI verdict block — four short, candid analyses returned by /rate.
/// Each rendered as a card under the HeroCard on the report screen.
class HonestVerdict {
  final VerdictBlock biggestStrength;
  final VerdictBlock biggestWeakness;
  final FastestWin   fastestWin;
  final Potential    potential;

  const HonestVerdict({
    required this.biggestStrength,
    required this.biggestWeakness,
    required this.fastestWin,
    required this.potential,
  });

  static HonestVerdict? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return HonestVerdict(
      biggestStrength: VerdictBlock.fromJson(raw['biggestStrength']),
      biggestWeakness: VerdictBlock.fromJson(raw['biggestWeakness']),
      fastestWin:      FastestWin.fromJson(raw['fastestWin']),
      potential:       Potential.fromJson(raw['potential']),
    );
  }
}

class VerdictBlock {
  final String headline;
  final String body;
  const VerdictBlock({required this.headline, required this.body});
  factory VerdictBlock.fromJson(Object? raw) {
    final m = (raw is Map) ? raw : const {};
    return VerdictBlock(
      headline: (m['headline'] as String?)?.trim() ?? '',
      body:     (m['body']     as String?)?.trim() ?? '',
    );
  }
}

class FastestWin {
  final List<String> axes; // ordered most-impactful first
  final String headline;
  final String body;
  const FastestWin({
    required this.axes,
    required this.headline,
    required this.body,
  });
  factory FastestWin.fromJson(Object? raw) {
    final m = (raw is Map) ? raw : const {};
    final rawAxes = m['axes'];
    final list = (rawAxes is List)
        ? rawAxes.whereType<String>().map((s) => s.toLowerCase()).toList()
        : <String>[];
    return FastestWin(
      axes:     list,
      headline: (m['headline'] as String?)?.trim() ?? '',
      body:     (m['body']     as String?)?.trim() ?? '',
    );
  }
}

class Potential {
  final int current;
  final int projected;
  final String body;
  const Potential({
    required this.current,
    required this.projected,
    required this.body,
  });
  int get gain => (projected - current).clamp(0, 100);
  factory Potential.fromJson(Object? raw) {
    final m = (raw is Map) ? raw : const {};
    int asInt(Object? v) =>
        v is num ? v.round().clamp(0, 100) : 0;
    return Potential(
      current:   asInt(m['current']),
      projected: asInt(m['projected']),
      body:      (m['body'] as String?)?.trim() ?? '',
    );
  }
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

      // Optional sub-scores / sub-tiers from the GPT vision call. Present
      // once the backend rate prompt has been extended to ask for them;
      // null otherwise (the report page falls back to geometry-derived
      // scores so the per-trait panel always renders something honest).
      Map<String, int>? subScores;
      Map<String, String>? subTiers;
      final rawSub = decoded['subScores'];
      if (rawSub is Map) {
        subScores = <String, int>{};
        rawSub.forEach((k, v) {
          if (v is num) subScores![k.toString()] = v.round().clamp(0, 100);
        });
      }
      final rawTiers = decoded['subTiers'];
      if (rawTiers is Map) {
        subTiers = <String, String>{};
        rawTiers.forEach((k, v) {
          if (v is String) subTiers![k.toString()] = v;
        });
      }

      return HonestRating(
        score:     score.round().clamp(0, 100),
        tier:      (decoded['tier'] as String?) ?? 'average',
        note:      (decoded['note'] as String?) ?? '',
        subScores: subScores,
        subTiers:  subTiers,
        verdict:   HonestVerdict.fromJson(decoded['verdict']),
      );
    } catch (_) {
      return null;
    }
  }
}
