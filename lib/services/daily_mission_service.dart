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
  static const eyes     = 'eyes';
  static const scan     = 'scan';
  static const render   = 'render';
  // v350 — RIZZ folded away. These ids are kept defined (not deleted)
  // so any persisted set from an older build still resolves, and so a
  // one-line restore is possible; the generator no longer emits them.
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

  /// Build today's set — THE MASTER PLAN, every slot completable
  /// within the user's real weekly credits:
  ///
  ///   1. PROTOCOL — every single day, always slot 1. Ticking the
  ///      protocol log on the Looks tab completes it (looks_done_ymd).
  ///   2. ROLEPLAY — while weekly voice minutes remain (5 × 2-min
  ///      "game lessons" = 10 min/week).
  ///   3. EYE CONTACT — while the 3/week eye-contact allowance remains.
  ///      The gaze-training tab that replaced Rizz; folded into the
  ///      ascension plan at 3 lessons per week.
  ///   4. SCAN — max 2/week, SPACED: the first any time, the second
  ///      only once the first is ≥3 days old, so both scans land in
  ///      different halves of the week instead of back-to-back.
  ///   5. MIRROR RENDER — while the 3/week render budget remains.
  ///
  /// v350 — RIZZ removed from the daily plan (the tab was folded away).
  static Future<List<String>> _generate(int today) async {
    final ids = <String>[protocol];

    // v366 — THE LOOKS PIVOT: roleplay + eye-contact missions retired
    // with the Game/Aura tabs. The daily plan is now the looks loop:
    // protocol (anchor) + scan (spaced) + glow-up render.
    //
    // // ── ROLEPLAY — retired.
    // if (!await LocalStoreService.voiceCapReached()) ids.add(roleplay);
    // // ── EYE CONTACT — retired.
    // if (!await LocalStoreService.eyeLessonsCapReached()) ids.add(eyes);

    // ── SCAN — 2/week, spaced ≥3 days apart.
    try {
      final used = await LocalStoreService.scansThisWeek();
      if (used < LocalStoreService.kScansPerWeek) {
        var eligible = used == 0;
        if (!eligible) {
          final latest = await LocalStoreService.latestScan();
          eligible = latest == null ||
              DateTime.now().difference(latest.takenAt).inDays >= 3;
        }
        if (eligible) ids.add(scan);
      }
    } catch (_) {}

    // ── MIRROR RENDER — while the 3/week budget remains.
    try {
      if (await LocalStoreService.mirrorRendersThisWeek() <
          LocalStoreService.kRendersPerWeek) {
        ids.add(render);
      }
    } catch (_) {}

    return ids;
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
      eyes:     stamped('eyes_done_ymd'),
      scan:     scanToday,
      render:   stamped('render_done_ymd'),
      // Legacy rizz stamps kept so an older persisted set still resolves.
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
