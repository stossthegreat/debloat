import 'package:shared_preferences/shared_preferences.dart';

import 'local_store_service.dart';

/// THE DAILY MISSION ENGINE — quota-aware, rotating, with memory.
///
/// The old Ascend panel showed the SAME five missions every day, which
/// broke against the real allowances: Pro users get 2 scans/week,
/// ~5 roleplay sessions/week (15 voice minutes), 3 mirror renders/week,
/// 30 screenshot reads/week, and unlimited rizz chat + pickup lines.
/// Telling a user to "scan the face" on a day his weekly scan quota is
/// spent is a mission he literally cannot complete — a guaranteed
/// consistency hit through no fault of his own.
///
/// New model:
///   • PROTOCOL is the anchor — it appears EVERY day (the daily log is
///     the product's core habit).
///   • The other four slots are drawn from a candidate pool where each
///     mission type only qualifies while its weekly budget has room:
///         roleplay   → while the voice-minutes cap isn't reached
///         scan       → while scansThisWeek < kScansPerWeek
///         render     → while mirrorRendersThisWeek < kRendersPerWeek
///         rizz_ss    → while the screenshot cap isn't reached
///         pickup     → always (unlimited)
///         rizz_chat  → always (unlimited)
///   • The pool is rotated by calendar day so the mix CHANGES daily
///     instead of repeating.
///   • MEMORY: the set generated for today is persisted, so it stays
///     stable all day (finishing a mission or burning quota mid-day
///     doesn't reshuffle the list under the user) and tomorrow rolls a
///     fresh set.
///
/// Completion is read from the per-feature day stamps each surface
/// already writes (`*_done_ymd`), plus the scan history date.
class DailyMissionService {
  static const _kYmd = 'missions.today.ymd';
  static const _kIds = 'missions.today.ids';

  // Mission type ids — stable strings, persisted.
  static const protocol = 'protocol';
  static const roleplay = 'roleplay';
  static const scan     = 'scan';
  static const render   = 'render';
  static const rizzSs   = 'rizz_ss';
  static const pickup   = 'pickup';
  static const rizzChat = 'rizz_chat';

  static int _ymd(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  /// Today's mission set with completion state. Generates + persists a
  /// new set on the first call of each calendar day; every later call
  /// (including from StreakService's consistency math) returns the SAME
  /// set so all surfaces agree.
  static Future<List<DailyMission>> loadToday() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _ymd(DateTime.now());

    List<String> ids;
    if ((prefs.getInt(_kYmd) ?? 0) == today &&
        (prefs.getStringList(_kIds)?.isNotEmpty ?? false)) {
      ids = prefs.getStringList(_kIds)!;
    } else {
      ids = await _generate(today);
      await prefs.setInt(_kYmd, today);
      await prefs.setStringList(_kIds, ids);
    }

    final done = await _doneMap(prefs, today);
    return [for (final id in ids) DailyMission(id: id, done: done[id] ?? false)];
  }

  /// Build today's set: protocol anchor + 4 rotated quota-aware slots.
  static Future<List<String>> _generate(int today) async {
    // Candidate pool in priority order, each gated on remaining budget.
    final pool = <String>[];
    try {
      if (!await LocalStoreService.voiceCapReached()) pool.add(roleplay);
    } catch (_) { pool.add(roleplay); }
    try {
      if (await LocalStoreService.scansThisWeek() <
          LocalStoreService.kScansPerWeek) {
        pool.add(scan);
      }
    } catch (_) {}
    try {
      if (await LocalStoreService.mirrorRendersThisWeek() <
          LocalStoreService.kRendersPerWeek) {
        pool.add(render);
      }
    } catch (_) {}
    try {
      if (!await LocalStoreService.screenshotRizzCapReached()) pool.add(rizzSs);
    } catch (_) { pool.add(rizzSs); }
    // Unlimited fillers — always eligible.
    pool.add(pickup);
    pool.add(rizzChat);

    // Rotate by calendar day so the daily mix changes. Deterministic
    // within a day (no reshuffling on rebuild).
    final daysSinceEpoch =
        DateTime.now().difference(DateTime(2026)).inDays;
    final offset = pool.isEmpty ? 0 : daysSinceEpoch % pool.length;
    final rotated = [
      ...pool.sublist(offset),
      ...pool.sublist(0, offset),
    ];
    final picked = rotated.take(4).toList();

    return [protocol, ...picked];
  }

  /// Per-mission "done today" reads. Each maps to the day stamp the
  /// feature writes on completion.
  static Future<Map<String, bool>> _doneMap(
      SharedPreferences prefs, int today) async {
    bool stamped(String key) => (prefs.getInt(key) ?? 0) == today;

    bool scanToday = false;
    try {
      final latest = await LocalStoreService.latestScan();
      if (latest != null) scanToday = _ymd(latest.takenAt) == today;
    } catch (_) {}

    return {
      protocol: stamped('looks_done_ymd'),
      roleplay: stamped('game_done_ymd'),
      scan:     scanToday,
      render:   stamped('render_done_ymd'),
      rizzSs:   stamped('rizz_done_ymd'),
      pickup:   stamped('pickup_line_done_ymd'),
      rizzChat: stamped('rizz_chat_done_ymd'),
    };
  }
}

/// One mission in today's set — the stable type id plus whether the
/// user has completed it today. UI copy lives in the Ascend screen.
class DailyMission {
  final String id;
  final bool done;
  const DailyMission({required this.id, required this.done});
}
