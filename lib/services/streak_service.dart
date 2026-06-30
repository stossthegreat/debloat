import 'package:shared_preferences/shared_preferences.dart';

import 'local_store_service.dart';
import 'protocol_service.dart';

/// THE DAILY STREAK — single source of truth for the flame the user
/// protects.
///
/// Design (v2): instead of a fragile running counter that only knew
/// about "today", we keep an **activity-day log** — the set of calendar
/// days on which the user did anything that counts. The streak is then
/// the consecutive run of days ending today (or yesterday, if today is
/// still pending). This is robust:
///   • It is SEEDED from the user's real history (scan dates + game-rep
///     dates) the first time it runs, so an existing user who's been
///     active for days doesn't suddenly read 0.
///   • It records every day a mission is completed going forward (the
///     `*_done_ymd` flags every mission screen stamps).
///   • A missed day breaks the run on its own — no manual reset needed.
///
/// A day counts when ANY of these happened on it:
///   • a scan was captured            (LOOKS — also a protocol check-in)
///   • a Free Flow / roleplay rep      (GAME)
///   • a rizz reply was generated      (RIZZ)
///   • a pickup line was copied        (PICKUP)
///
/// [refresh] is safe to call from any surface load — it rebuilds the log
/// from the live signals and returns the `(current, longest)` pair so
/// every masthead + the Ascend panel read the same number.
class StreakService {
  static const _kActiveDays = 'streak_active_days'; // List<String> of YMD
  static const _kLongest    = 'daily_streak_longest';

  /// Pillar flags each mission screen stamps with today's YMD.
  static const _doneFlags = <String>[
    'looks_done_ymd',
    'game_done_ymd',
    'rizz_done_ymd',
    'pickup_line_done_ymd',
  ];

  static int _ymd(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
  static int _todayYmd() => _ymd(DateTime.now());
  static DateTime _fromYmd(int ymd) =>
      DateTime(ymd ~/ 10000, (ymd % 10000) ~/ 100, ymd % 100);

  /// Rebuild the activity-day log from every live signal, persist it,
  /// and return the live `(current, longest)` streak.
  static Future<(int current, int longest)> refresh() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayYmd();
    final yesterday = _ymd(DateTime.now().subtract(const Duration(days: 1)));

    // Start from whatever we've already recorded.
    final days = <int>{};
    for (final s in prefs.getStringList(_kActiveDays) ?? const <String>[]) {
      final v = int.tryParse(s);
      if (v != null) days.add(v);
    }

    // Record the latest activity day stamped by each mission flag.
    for (final k in _doneFlags) {
      final v = prefs.getInt(k) ?? 0;
      if (v > 0) days.add(v);
    }

    // Seed from real history so an existing user isn't starting at 0 the
    // first time this runs. Best-effort — a read failure just means we
    // fall back to the flags above.
    try {
      for (final s in await LocalStoreService.loadScans()) {
        days.add(_ymd(s.takenAt));
      }
    } catch (_) {}
    try {
      for (final g in await LocalStoreService.loadGameScores()) {
        days.add(_ymd(g.takenAt));
      }
    } catch (_) {}

    // Trim to a sane window and persist.
    final cutoff = _ymd(DateTime.now().subtract(const Duration(days: 200)));
    final kept = days.where((d) => d >= cutoff).toList()..sort();
    await prefs.setStringList(
        _kActiveDays, kept.map((e) => e.toString()).toList());

    final set = kept.toSet();
    final activityRun = _runEndingAt(set, today, yesterday);

    // The PROTOCOL is the everyday anchor — it's the one action designed
    // for daily use (scans + roleplay are weekly-capped, so they can't
    // carry a daily streak on their own). Its own check-in streak (with
    // the freeze budget) is the streak the product is built around, so we
    // take the better of the activity-day run and the protocol streak. A
    // daily protocol logger always sees their real number.
    int protocolStreak = 0, protocolLongest = 0;
    try {
      final p = await ProtocolService.loadActive();
      protocolStreak  = p?.effectiveStreak ?? 0;
      protocolLongest = p?.longestStreak  ?? 0;
    } catch (_) {}

    final current = activityRun > protocolStreak ? activityRun : protocolStreak;

    final longest = prefs.getInt(_kLongest) ?? 0;
    final maxRun = _longestRun(set);
    final best = [longest, current, maxRun, protocolLongest]
        .reduce((a, b) => a > b ? a : b);
    if (best != longest) await prefs.setInt(_kLongest, best);

    return (current, best);
  }

  /// Consecutive run ending today, or yesterday if today is still
  /// pending (chain alive). 0 if neither day is active.
  static int _runEndingAt(Set<int> days, int today, int yesterday) {
    int anchor;
    if (days.contains(today)) {
      anchor = today;
    } else if (days.contains(yesterday)) {
      anchor = yesterday;
    } else {
      return 0;
    }
    int count = 0;
    var d = _fromYmd(anchor);
    while (days.contains(_ymd(d))) {
      count++;
      d = d.subtract(const Duration(days: 1));
    }
    return count;
  }

  /// Longest consecutive run anywhere in the log — preserves a record
  /// streak even after it ends.
  static int _longestRun(Set<int> days) {
    if (days.isEmpty) return 0;
    final sorted = days.toList()..sort();
    int best = 1, run = 1;
    for (var i = 1; i < sorted.length; i++) {
      final gap = _fromYmd(sorted[i]).difference(_fromYmd(sorted[i - 1])).inDays;
      run = (gap == 1) ? run + 1 : 1;
      if (run > best) best = run;
    }
    return best;
  }

  /// Read-only current streak (still rebuilds the log as a side effect).
  static Future<int> current() async {
    final (cur, _) = await refresh();
    return cur;
  }
}
