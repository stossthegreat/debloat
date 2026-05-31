import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/gaze/gaze_lesson.dart';

/// Persists [GazeResult]s — the user can see "+12 this week" on the
/// share card. Best-score-per-lesson is what gates the curriculum
/// progress band on the Eyes tab landing; the full attempt history
/// drives the improvement deltas.
///
/// Storage layout:
///   - `gaze_best_<lessonId>`     — JSON {score, ts} for the best attempt
///   - `gaze_history`              — JSON List of full GazeResult
///                                   blobs across all lessons, capped
///                                   at the most recent 100 entries
abstract final class GazeProgressStore {
  static const _historyKey = 'gaze_history';
  static const int _historyCap = 100;

  /// Append the result to the history and update the per-lesson best
  /// if this beats the previous best. Returns the previous best score
  /// (0..100) for delta surfacing — null if this is the first attempt.
  static Future<int?> record(GazeResult r) async {
    final sp = await SharedPreferences.getInstance();

    final prevBestRaw = sp.getString(_bestKey(r.lessonId));
    int? prevBest;
    if (prevBestRaw != null) {
      try {
        final m = jsonDecode(prevBestRaw) as Map<String, dynamic>;
        prevBest = (m['score'] as num?)?.toInt();
      } catch (_) {}
    }

    if (prevBest == null || r.gazeScore > prevBest) {
      await sp.setString(_bestKey(r.lessonId), jsonEncode({
        'score': r.gazeScore,
        'ts':    r.timestampMs,
      }));
    }

    final hist = await _readHistory();
    hist.insert(0, r);
    if (hist.length > _historyCap) {
      hist.removeRange(_historyCap, hist.length);
    }
    await sp.setString(
        _historyKey, jsonEncode(hist.map((h) => h.toJson()).toList()));

    return prevBest;
  }

  /// Best score (0..100) for a given lesson, or null if untouched.
  static Future<int?> bestFor(String lessonId) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_bestKey(lessonId));
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return (m['score'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  /// Total attempts logged in history. Caps at the history-cap
  /// (currently 100), which is fine because the progression cap below
  /// already saturates at 24.
  static Future<int> attemptCount() async {
    final hist = await _readHistory();
    return hist.length;
  }

  /// Progression multiplier applied to every shown / persisted gaze
  /// score. Floors at 0.40 (a perfect rep on session #1 caps at 4/10)
  /// and ramps linearly to 1.00 at 24 sessions. The point is that the
  /// apprentice can\'t hit a 10/10 by getting lucky once — they have
  /// to actually drill through the curriculum first.
  ///
  /// Curve:
  ///   0 attempts   → 0.40    (4/10 ceiling)
  ///   8 attempts   → 0.60    (6/10 ceiling)
  ///   16 attempts  → 0.80    (8/10 ceiling)
  ///   24 attempts  → 1.00    (uncapped — real score surfaces)
  static Future<double> progressionCap() async {
    final n = await attemptCount();
    return (0.40 + n * 0.025).clamp(0.40, 1.00);
  }

  /// How many Gaze lessons the apprentice has scored above zero on.
  static Future<int> completedCount() async {
    int n = 0;
    final sp = await SharedPreferences.getInstance();
    for (final k in sp.getKeys()) {
      if (k.startsWith('gaze_best_')) {
        final raw = sp.getString(k);
        if (raw == null) continue;
        try {
          final m = jsonDecode(raw) as Map<String, dynamic>;
          if (((m['score'] as num?) ?? 0) > 0) n++;
        } catch (_) {}
      }
    }
    return n;
  }

  /// "This week vs the previous week" delta in average magnetic score
  /// across all completed Gaze drills. Surfaced on the share card as
  /// "+12 this week". Returns null when there isn't enough history.
  static Future<int?> weeklyImprovement() async {
    final hist = await _readHistory();
    if (hist.isEmpty) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final weekMs = 7 * 24 * 60 * 60 * 1000;
    final thisWeek = hist
        .where((r) => now - r.timestampMs < weekMs)
        .map((r) => r.gazeScore)
        .toList();
    final lastWeek = hist
        .where((r) {
          final age = now - r.timestampMs;
          return age >= weekMs && age < 2 * weekMs;
        })
        .map((r) => r.gazeScore)
        .toList();
    if (thisWeek.isEmpty || lastWeek.isEmpty) return null;
    final thisAvg = thisWeek.reduce((a, b) => a + b) / thisWeek.length;
    final lastAvg = lastWeek.reduce((a, b) => a + b) / lastWeek.length;
    return (thisAvg - lastAvg).round();
  }

  static Future<List<GazeResult>> _readHistory() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_historyKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => GazeResult.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String _bestKey(String lessonId) => 'gaze_best_$lessonId';
}
