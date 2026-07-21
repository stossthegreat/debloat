import 'package:shared_preferences/shared_preferences.dart';

import 'daily_mission_service.dart';
import 'local_store_service.dart';

/// THE ASCENSION ENGINE — one source of truth for the three numbers the
/// whole app reconciles around: the daily STREAK (the flame), the
/// ASCENSION DAY (how far up the Observer → ImHim Looks ladder you've climbed),
/// and the CONSISTENCY score (how fully you're doing each day's missions).
///
/// The model (locked with bro):
///
///   • STREAK — consecutive calendar days you showed up. "Showing up" =
///     completing AT LEAST ONE of the five daily missions. Do 1 of 5 and
///     the flame is safe; only a full ZERO-day breaks it. There is no
///     freeze/grace — miss a whole day and it resets. It is the same
///     number on every masthead (Looks / Rizz / Ascend).
///
///   • ASCENSION DAY — the TOTAL number of distinct days you've ever
///     shown up. It is earned, never free: it only climbs on days you do
///     the work, and it NEVER goes backward (a broken streak doesn't cost
///     you your day). Day thresholds drive the rank ladder (Observer 1,
///     Initiate 10, Contender 20, Dangerous 30, Magnetic 45, ImHim Looks 60).
///     Clamped to 1..60 for display.
///
///   • CONSISTENCY — a rolling 7-day mission-completion rate. Each day
///     records how many of the 5 missions you finished; consistency is
///     the average of (done ÷ 5) over the last 7 days, ×100. Do all 5
///     daily and it climbs to 100; half-ass 3/5 and it settles ~60 —
///     the honest "you're only part-showing-up" signal. Missing missions
///     never breaks the streak, it just drags this down.
///
/// The five daily missions (mirrors the Ascend tab exactly):
///   1. PROTOCOL  — `looks_done_ymd` (scan / protocol check-in)
///   2. ROLEPLAY  — `game_done_ymd`
///   3. SCAN      — a scan captured today (derived from scan history)
///   4. PICKUP    — `pickup_line_done_ymd`
///   5. READ      — `rizz_done_ymd`
///
/// [refresh] returns just the `(streak, longest)` pair for the mastheads.
/// [progress] returns the full [AscensionSnapshot] the Ascend tab needs.
class StreakService {
  static const _kActiveDays = 'streak_active_days'; // List<String> of YMD
  static const _kLongest    = 'daily_streak_longest';
  // List<String> "ymd:done:offered" ("ymd:done" legacy = offered 5).
  static const _kMissionLog = 'mission_daily_log';

  /// Total length of the ascension ladder, in earned days.
  static const int ascensionTotalDays = 60;

  /// Mission flags stamped with today's YMD by each mission screen.
  /// Any ONE of these landing today keeps the flame alive.
  static const _doneFlags = <String>[
    'looks_done_ymd',
    'game_done_ymd',
    'rizz_done_ymd',
    'pickup_line_done_ymd',
    'render_done_ymd',
    'rizz_chat_done_ymd',
  ];

  static int _ymd(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
  static int _todayYmd() => _ymd(DateTime.now());
  static DateTime _fromYmd(int ymd) =>
      DateTime(ymd ~/ 10000, (ymd % 10000) ~/ 100, ymd % 100);

  /// Rebuild the activity-day log + today's mission count from every
  /// live signal and persist both. Returns the active-day set and how
  /// many of the five missions are done today. Shared by [refresh] and
  /// [progress] so both stay in lock-step.
  static Future<(Set<int> days, int missionsToday)> _rebuild(
      SharedPreferences prefs) async {
    final today = _todayYmd();

    // Start from whatever we've already recorded, plus each mission flag.
    final days = <int>{};
    for (final s in prefs.getStringList(_kActiveDays) ?? const <String>[]) {
      final v = int.tryParse(s);
      if (v != null) days.add(v);
    }
    for (final k in _doneFlags) {
      final v = prefs.getInt(k) ?? 0;
      if (v > 0) days.add(v);
    }

    // Seed from real history so an existing user isn't starting at 0.
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

    // Trim active-days to a sane window and persist.
    final cutoff = _ymd(DateTime.now().subtract(const Duration(days: 200)));
    final kept = days.where((d) => d >= cutoff).toList()..sort();
    await prefs.setStringList(
        _kActiveDays, kept.map((e) => e.toString()).toList());

    // Today's mission count — from the DAILY MISSION ENGINE, which is
    // quota-aware and rotates the set each day. done/offered are logged
    // together so consistency judges the user against what was actually
    // asked of them today, not a fixed five.
    int missionsToday = 0;
    int offeredToday = 5;
    try {
      final missions = await DailyMissionService.loadToday();
      missionsToday = missions.where((m) => m.done).length;
      offeredToday = missions.isEmpty ? 5 : missions.length;
    } catch (_) {}

    // Upsert today's done/offered into the mission log; trim to 60 days.
    final logCutoff = _ymd(DateTime.now().subtract(const Duration(days: 60)));
    final Map<int, (int, int)> log = _readMissionLog(prefs, logCutoff);
    log[today] = (missionsToday, offeredToday);
    await prefs.setStringList(
        _kMissionLog,
        log.entries
            .map((e) => '${e.key}:${e.value.$1}:${e.value.$2}')
            .toList());

    return (kept.toSet(), missionsToday);
  }

  /// Parse the mission log. New entries are "ymd:done:offered"; legacy
  /// two-part entries ("ymd:done") predate the dynamic engine and are
  /// read with offered = 5.
  static Map<int, (int done, int offered)> _readMissionLog(
      SharedPreferences prefs, int cutoff) {
    final Map<int, (int, int)> log = {};
    for (final e in prefs.getStringList(_kMissionLog) ?? const <String>[]) {
      final parts = e.split(':');
      if (parts.length < 2) continue;
      final y = int.tryParse(parts[0]);
      final d = int.tryParse(parts[1]);
      final o = parts.length >= 3 ? (int.tryParse(parts[2]) ?? 5) : 5;
      if (y != null && d != null && y >= cutoff) log[y] = (d, o <= 0 ? 5 : o);
    }
    return log;
  }

  /// Streak `(current, longest)` from the active-day set. Pure activity
  /// run — no protocol freeze/grace — so ≥1 mission holds the flame and a
  /// full zero-day resets it, identical on every surface.
  static Future<(int current, int longest)> _streakPair(
      SharedPreferences prefs, Set<int> set) async {
    final today = _todayYmd();
    final yesterday = _ymd(DateTime.now().subtract(const Duration(days: 1)));
    final current = _runEndingAt(set, today, yesterday);
    final longest = prefs.getInt(_kLongest) ?? 0;
    final maxRun = _longestRun(set);
    final best = [longest, current, maxRun].reduce((a, b) => a > b ? a : b);
    if (best != longest) await prefs.setInt(_kLongest, best);
    return (current, best);
  }

  /// Rebuild the log and return the live `(current, longest)` streak.
  /// Safe to call from any masthead load.
  static Future<(int current, int longest)> refresh() async {
    final prefs = await SharedPreferences.getInstance();
    final (set, _) = await _rebuild(prefs);
    return _streakPair(prefs, set);
  }

  /// The full ascension snapshot — streak, longest, earned ascension day,
  /// rolling-7-day consistency, and today's mission count. One call the
  /// Ascend tab reads so every number agrees.
  static Future<AscensionSnapshot> progress() async {
    final prefs = await SharedPreferences.getInstance();
    final (set, missionsToday) = await _rebuild(prefs);
    final (current, longest) = await _streakPair(prefs, set);
    // v374 — Ascension day IS the streak. Bro: "streak says day 2,
    // ascension says day 6 — no, it has to match. They break the
    // streak, we stop the days in the ascension." One number drives
    // both surfaces: the flame and DAY N/60 always agree, and a broken
    // streak knocks the ascension day back with it. (The old model
    // counted total-days-shown-up, which let the two drift apart.)
    final ascensionDay = current.clamp(1, ascensionTotalDays);
    final consistency = _consistency7d(prefs);
    return AscensionSnapshot(
      streak: current,
      longest: longest,
      ascensionDay: ascensionDay,
      consistency: consistency,
      missionsToday: missionsToday,
    );
  }

  /// Rolling 7-day mission-completion rate (0..100). Averages
  /// (missions done ÷ 5) over the last 7 calendar days. The window is
  /// capped by how long the mission log has existed, so a brand-new
  /// user isn't punished for days before they started.
  static int _consistency7d(SharedPreferences prefs) {
    final today = _todayYmd();
    final log = _readMissionLog(prefs, 0);
    if (log.isEmpty) return 0;
    final firstDay = log.keys.reduce((a, b) => a < b ? a : b);
    final elapsed =
        _fromYmd(today).difference(_fromYmd(firstDay)).inDays + 1;
    final window = elapsed < 1 ? 1 : (elapsed > 7 ? 7 : elapsed);
    // Judge each day against what was actually OFFERED that day (the
    // dynamic mission set can be smaller than 5 when weekly quotas are
    // spent). A day with no log entry = the user never showed up = 0/5.
    int done = 0, offered = 0;
    var d = _fromYmd(today);
    for (var i = 0; i < window; i++) {
      final entry = log[_ymd(d)];
      done += entry?.$1 ?? 0;
      offered += entry?.$2 ?? 5;
      d = d.subtract(const Duration(days: 1));
    }
    if (offered <= 0) return 0;
    return ((done / offered) * 100).round().clamp(0, 100);
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

/// The unified ascension state — one struct every surface reads so the
/// streak, the earned ascension day, and the consistency score never
/// disagree across tabs.
class AscensionSnapshot {
  /// Consecutive active days ending today/yesterday (the flame).
  final int streak;

  /// Longest streak ever reached.
  final int longest;

  /// Total distinct days shown up, earned + permanent, clamped 1..60.
  final int ascensionDay;

  /// Rolling 7-day mission-completion rate, 0..100.
  final int consistency;

  /// How many of the five daily missions are done today (0..5).
  final int missionsToday;

  const AscensionSnapshot({
    required this.streak,
    required this.longest,
    required this.ascensionDay,
    required this.consistency,
    required this.missionsToday,
  });
}
