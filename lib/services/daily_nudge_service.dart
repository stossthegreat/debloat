import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'local_store_service.dart';
import 'notification_service.dart';
import 'protocol_service.dart';

/// THE RETENTION ENGINE — a rolling 14-day notification horizon, two
/// beats a day, refreshed on every app open.
///
/// WHY A HORIZON (and not one repeating notification):
/// The old build scheduled ONE nudge with `matchDateTimeComponents.time`,
/// so the OS replayed the SAME frozen line every night until the app was
/// reopened. Two fatal consequences:
///   1. The copy never changed — the user saw one line on loop.
///   2. The STATE never changed — a user who stopped opening the app kept
///      getting the "you're active" line forever and NEVER escalated into
///      the win-back ladder. The comeback system was dead for exactly the
///      users it existed to recover.
///
/// THE FIX: schedule a distinct one-shot notification for every slot over
/// the next [_horizonDays] days. Each day's copy is computed for that day's
/// PROJECTED state (days-since-open keeps growing across the horizon), so
/// the ladder escalates on its own — Active → at-risk → dormant-7d →
/// dormant-14d — even if the user never reopens. Every app open resets the
/// clock and rebuilds the whole horizon from the current state, so the
/// ladder only ever fires when the user actually goes quiet.
///
/// TWO BEATS A DAY:
///   • MORNING (09:00) — the DREAM pump. Aspirational, identity-forward.
///     "Become the guy she notices." Pulls the user toward the version of
///     himself the app builds.
///   • EVENING (19:30) — the STREAK / loss nudge. Powerful, loss-framed,
///     state-aware. "Don't fold on yourself." Drives the daily ritual.
///
/// THE STATE MACHINE — one read, projected forward per day:
///   NO_SCAN            — never scanned
///   PROTOCOL_ACTIVE    — currently checked in on at least one axis
///   PROTOCOL_BROKEN    — at least one protocol's streak just broke
///   DORMANT_7D         — 7-13 days since last app open
///   DORMANT_14D        — 14+ days since last app open
///   DEFAULT            — active user, no specific signal
///
/// THE COPY — friend-warning + every-man's-dream voice. No emojis. No
/// "Hey [name]!". Specific, identity-anchored, never corporate cheer.
class DailyNudgeService {
  // ── Horizon shape ───────────────────────────────────────────────────
  /// How many days ahead we keep notifications queued. Refreshed on every
  /// app open, so this is a worst-case "if you stop now" win-back ladder.
  /// 14 days × 2 slots = 28 pending notifications — comfortably under the
  /// iOS 64-pending cap (rescan reminders add at most 2 more).
  static const _horizonDays = 14;

  /// Morning DREAM pump fires at 09:00; evening STREAK nudge at 19:30.
  static const _morningHour   = 9;
  static const _eveningHour   = 19;
  static const _eveningMinute = 30;

  /// ID blocks — one stable id per horizon day per slot so a refresh
  /// overwrites the previous horizon cleanly.
  static const _morningBase = 9100; // 9100 .. 9100+_horizonDays-1
  static const _eveningBase = 9200; // 9200 .. 9200+_horizonDays-1
  /// Legacy single-nudge id (pre-horizon). Cancelled on migrate.
  static const _legacyDailyId = 9001;

  static const _kLastAppOpenKey  = 'nudge.last_app_open_ms';

  static FlutterLocalNotificationsPlugin get _plugin =>
      NotificationService.plugin;

  // ── Event marks — call these wherever the user does the thing. ───────

  static Future<void> markAppOpened() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastAppOpenKey, DateTime.now().millisecondsSinceEpoch);
    await reschedule();
  }

  /// Wipe every legacy + prior-horizon notification, then queue a fresh
  /// 14-day, two-beats-a-day horizon picked from the current state. Safe
  /// to call repeatedly — every call is a clean rebuild.
  static Future<void> reschedule() async {
    try {
      // 1) Clear legacy schedulers (streak/training/rescan) + the old
      // single daily nudge + any previous horizon we laid down.
      await NotificationService.cancelAllProtocolNotifications();
      await NotificationService.cancelTrainingNudge();
      await _plugin.cancel(_legacyDailyId);
      for (var d = 0; d < _horizonDays; d++) {
        await _plugin.cancel(_morningBase + d);
        await _plugin.cancel(_eveningBase + d);
      }

      // 2) One state read; projected forward per day inside the loop.
      final sig = await _readSignals();
      final now = tz.TZDateTime.now(tz.local);

      // 3) Lay down the horizon. Each slot is a distinct one-shot with its
      // own fireDate + its own pre-baked copy — NO matchDateTimeComponents,
      // because we WANT a different line every day, not a daily clone.
      for (var d = 0; d < _horizonDays; d++) {
        // MORNING — dream / identity pump.
        final morningAt = _slot(now, d, _morningHour, 0);
        if (morningAt.isAfter(now)) {
          final (t, b) = _dreamCopy(sig, d);
          await _schedule(_morningBase + d, t, b, morningAt, morning: true);
        }
        // EVENING — streak / loss, escalating with projected dormancy.
        final eveningAt = _slot(now, d, _eveningHour, _eveningMinute);
        if (eveningAt.isAfter(now)) {
          final state = _stateFor(sig, d);
          final (t, b) = _streakCopy(state, d);
          await _schedule(_eveningBase + d, t, b, eveningAt, morning: false);
        }
      }
    } catch (e) {
      debugPrint('DailyNudgeService.reschedule failed: $e');
    }
  }

  // ── Scheduling helpers ──────────────────────────────────────────────

  static tz.TZDateTime _slot(
      tz.TZDateTime now, int dayOffset, int hour, int minute) {
    final base = now.add(Duration(days: dayOffset));
    return tz.TZDateTime(tz.local, base.year, base.month, base.day, hour, minute);
  }

  static Future<void> _schedule(
    int id,
    String title,
    String body,
    tz.TZDateTime at, {
    required bool morning,
  }) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      at,
      NotificationDetails(
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          // Red app-icon dot until the user opens the app; cleared by
          // NotificationService.clearIconBadge on foreground.
          badgeNumber: 1,
        ),
        android: AndroidNotificationDetails(
          morning ? 'daily_dream' : 'daily_streak',
          morning ? 'Daily motivation' : 'Streak reminders',
          channelDescription: morning
              ? 'Morning push toward the man you\'re building.'
              : 'Evening nudge to keep your streak alive.',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  // ── State read + projection ─────────────────────────────────────────

  static Future<_Signals> _readSignals() async {
    final prefs    = await SharedPreferences.getInstance();
    final scan     = await LocalStoreService.latestScan();
    final actives  = await ProtocolService.loadAllActive();

    final now = DateTime.now();
    final lastOpenMs =
        prefs.getInt(_kLastAppOpenKey) ?? now.millisecondsSinceEpoch;

    final daysSinceOpen = now
        .difference(DateTime.fromMillisecondsSinceEpoch(lastOpenMs))
        .inDays;

    final broken = actives.values.any(
        (p) => p.completedDays.isNotEmpty && p.effectiveStreak == 0);

    return _Signals(
      hasScan:           scan != null,
      hasActiveProtocol: actives.isNotEmpty,
      hasBrokenProtocol: broken,
      daysSinceOpen:     daysSinceOpen,
    );
  }

  /// Project the state [dayOffset] days into the future, assuming the user
  /// does NOT reopen (every real open rebuilds the horizon from scratch).
  /// days-since-open grows with the offset, so the dormancy ladder
  /// escalates on its own across the queued horizon.
  static _NudgeState _stateFor(_Signals s, int dayOffset) {
    final dso  = s.daysSinceOpen + dayOffset;

    if (!s.hasScan)            return _NudgeState.noScan;
    if (dso >= 14)            return _NudgeState.dormant14d;
    if (dso >= 7)             return _NudgeState.dormant7d;
    if (s.hasBrokenProtocol)  return _NudgeState.protocolBroken;
    if (s.hasActiveProtocol)  return _NudgeState.protocolActive;
    return _NudgeState.defaultState;
  }

  // ── MORNING: dream / identity pump ──────────────────────────────────
  // The aspirational beat. Pulls the user toward the man the app builds —
  // the face the room remembers. Pre-scan users get the "start the build"
  // variant; everyone else gets the full identity pump. Varied by day so
  // the week never repeats.

  static (String, String) _dreamCopy(_Signals s, int dayOffset) {
    final pool = s.hasScan ? _dreamPool : _dreamPreScanPool;
    return pool[(dayOffset) % pool.length];
  }

  // MORNING pool — your face is puffiest right after waking, so morning
  // is the scan + food-planning beat. Debloat-framed, no dating/looksmax.
  static const _dreamPreScanPool = <(String, String)>[
    ('See what\'s puffing you up',
     'One 30-second face scan reads your bloat. Start today.'),
    ('Your face holds the most water at dawn',
     'Scan now to catch your baseline before it drains.'),
    ('How bloated are you really?',
     'Scan once and find out. It takes 30 seconds.'),
    ('Meet the face under the bloat',
     'One scan shows you what\'s hiding your jawline.'),
  ];

  static const _dreamPool = <(String, String)>[
    ('Morning face check',
     'You\'re puffiest right now. Scan to see today\'s bloat level.'),
    ('Scan before you eat',
     'Photograph your breakfast first — see the sodium hit before it lands.'),
    ('Drain today',
     'Water, low sodium, cold splash. Tick them off in Debloat.'),
    ('Two scans a day beats one',
     'Morning + night shows how fast your face drains.'),
    ('Your jawline is under there',
     'Every low-sodium day brings it out. Log today.'),
    ('Check your meal first',
     'Scan lunch before the first bite — dodge the puffiness.'),
    ('Yesterday\'s sodium shows now',
     'Scan your face and see it. Then flush it today.'),
    ('Beat the bloat before it starts',
     'Scan your food, hit your water, drain the day.'),
    ('Lean face, on purpose',
     'It\'s built daily — scan, eat clean, flush, repeat.'),
  ];

  // ── EVENING: streak / don't-break-the-drain nudge ────────────────────
  // Debloat-framed. Loss-framed on the streak, food-scan on dinner. Picked
  // per horizon day, salted by state + offset so days never repeat.

  static (String, String) _streakCopy(_NudgeState s, int dayOffset) {
    final pool = _streakPool[s] ?? _streakPool[_NudgeState.defaultState]!;
    final i = (s.index * 7 + dayOffset) % pool.length;
    return pool[i];
  }

  static const _streakPool = <_NudgeState, List<(String, String)>>{
    _NudgeState.noScan: [
      ('Still unscanned',
       '30 seconds tells you how much water your face is holding.'),
      ('You don\'t know your bloat level',
       'One scan and you will. Open the app.'),
      ('Scan your dinner first',
       'See the sodium before you eat it. Then scan your face.'),
      ('Find the face under the bloat',
       'Scan once. Get your debloat plan tonight.'),
      ('Your baseline is one tap away',
       'Scan tonight so tomorrow\'s drain is measurable.'),
      ('How puffy are you, really?',
       '30 seconds answers it. Scan now.'),
      ('Start the drain',
       'One scan. Five wins. Wake up leaner.'),
    ],
    _NudgeState.protocolActive: [
      ('Don\'t break the drain streak',
       'Log tonight before midnight or the streak resets. Two minutes.'),
      ('Come back before you break your streak',
       'Tick tonight\'s debloat list and keep it alive.'),
      ('Scan dinner before you eat it',
       'Catch the sodium now — wake up less puffy tomorrow.'),
      ('You\'re mid-streak',
       'Water, sodium, cold splash. Log them before bed.'),
      ('Flush before you sleep',
       'Last water of the day + tonight\'s log. Two minutes.'),
      ('Stack one more drained day',
       'Every logged day shows in the mirror. Tick it off.'),
      ('Streak alive',
       'Two-minute check-in, then rest. Keep the chain.'),
    ],
    _NudgeState.protocolBroken: [
      ('Come back before you break your streak',
       'You can still save it. Tick tonight\'s list.'),
      ('Streak slipped',
       'One day off is a slip — two is a habit. Restart tonight.'),
      ('The bloat creeps back fast',
       'Miss a day and it shows. Log now and hold the line.'),
      ('Restart the drain tonight',
       'Water, low sodium, sleep. Two minutes. Back on.'),
      ('Don\'t let it puff back up',
       'Reopen and log — the jawline you found is worth keeping.'),
      ('Comeback day',
       'Day one again. Tick tonight\'s debloat list.'),
    ],
    _NudgeState.dormant7d: [
      ('A week off = a week of bloat',
       'Two minutes back on plan. Reopen the app.'),
      ('Your face missed you',
       'Scan again and see where the drain left off.'),
      ('Scan your food again',
       'One meal scan tonight restarts the habit.'),
      ('Come back to the lean face',
       'A scan and a logged day. Right where you left off.'),
      ('Still puffy? Let\'s fix that',
       'Reopen, scan, drain. Two minutes tonight.'),
    ],
    _NudgeState.dormant14d: [
      ('Two weeks of water weight',
       'Open the app. One scan restarts the drain.'),
      ('The bloat won',
       'For now. Reopen and take it back tonight.'),
      ('Your jawline is still under there',
       'A scan and a clean day brings it back. Two minutes.'),
      ('Restart the debloat',
       'A scan. A logged day. Wake up leaner tomorrow.'),
      ('Come back leaner',
       'Two minutes tonight. Pick up where you left off.'),
    ],
    _NudgeState.defaultState: [
      ('Log tonight\'s drain',
       'Water, sodium, sleep. Two minutes keeps the streak.'),
      ('Scan your dinner',
       'See the sodium before you eat it.'),
      ('Don\'t go puffy',
       'A two-minute log tonight = a leaner face tomorrow.'),
      ('Flush before bed',
       'Last water + tonight\'s check-in. Lock it in.'),
      ('Rescan and see the change',
       'Your face drains when you do. Check tonight.'),
    ],
  };
}

class _Signals {
  final bool hasScan;
  final bool hasActiveProtocol;
  final bool hasBrokenProtocol;
  final int  daysSinceOpen;
  const _Signals({
    required this.hasScan,
    required this.hasActiveProtocol,
    required this.hasBrokenProtocol,
    required this.daysSinceOpen,
  });
}

enum _NudgeState {
  noScan,
  protocolActive,
  protocolBroken,
  dormant7d,
  dormant14d,
  defaultState,
}
