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

  static const _dreamPreScanPool = <(String, String)>[
    ('Meet the version she chooses',
     'It starts with one 30-second scan. Find your starting line.'),
    ('Become impossible to overlook',
     'Scan tonight. Get the plan. Build the man.'),
    ('Your face has a ceiling you\'ve never seen',
     'You haven\'t even scanned yet. Start today.'),
    ('The guy she notices is one scan away',
     '30 seconds. Then we build him together.'),
  ];

  static const _dreamPool = <(String, String)>[
    ('Become the guy she notices',
     'Bones are not the ceiling. Execution is. Put in today\'s reps.'),
    ('The room turns for the prepared',
     'Two minutes today on the face it turns for.'),
    ('Any room. Any first impression. Handled',
     'That\'s the goal. One rep a day gets you there.'),
    ('Be the hardest man to ignore',
     'Built daily — scan, log, repeat. Today counts.'),
    ('You weren\'t born optimised. You build it',
     'Today is a rep. Don\'t skip the man you\'re building.'),
    ('Walk in like the room is yours',
     'Because you did the reps they didn\'t. Begin today.'),
    ('Magnetic isn\'t luck',
     'It\'s a face dialed in, one protocol day at a time. Today.'),
    ('The version she chooses',
     'is the one who showed up every day. Be him today.'),
    ('Confidence is a trained skill',
     'Not a gift. Two minutes today. Compounds for life.'),
  ];

  // ── EVENING: streak / loss nudge ────────────────────────────────────
  // The daily-ritual beat. Loss-framed, identity-anchored. Picked per
  // horizon day, salted by state + offset so consecutive days never land
  // the same line.

  static (String, String) _streakCopy(_NudgeState s, int dayOffset) {
    final pool = _streakPool[s] ?? _streakPool[_NudgeState.defaultState]!;
    final i = (s.index * 7 + dayOffset) % pool.length;
    return pool[i];
  }

  static const _streakPool = <_NudgeState, List<(String, String)>>{
    _NudgeState.noScan: [
      ('Still unscanned',
       '30 seconds tells you what she actually sees.'),
      ('She decides in 8 seconds',
       'You don\'t even know your starting number.'),
      ('Scared of the score?',
       'It\'s not the number. It\'s not knowing.'),
      ('Open the app',
       'Scan once. Then we work on the version she chooses.'),
      ('Other men know theirs',
       'They\'ve been improving for weeks. Where are you?'),
      ('Scan. Get instant glow-up wins',
       '30 seconds in. A protocol out. The version she stares at.'),
      ('Unlock your face',
       'One scan. Five fixes. The version of you the room remembers.'),
      ('Your blueprint is one tap away',
       'Scan tonight. Start becoming the guy who owns the room.'),
      ('Become impossible to overlook',
       '30-second scan. Personal glow-up plan. Tonight.'),
    ],
    _NudgeState.protocolActive: [
      ('Don\'t break the chain',
       'Log today before midnight. Two minutes.'),
      ('You\'re mid-streak',
       'Keep going. The version of you it builds is worth it.'),
      ('She\'s starting to notice',
       'Don\'t go quiet now.'),
      ('Streak alive',
       'Two-minute check-in. Then you can rest.'),
      ('You\'ve done harder things',
       'Two minutes. Today. Lock it in.'),
      ('Stack one more day',
       'Every check-in compounds. You\'re becoming him.'),
      ('Streak is your edge',
       'Log tonight. Wake up sharper than yesterday.'),
      ('Two minutes. Lock the version she chooses',
       'The man at the end of this streak is the one rooms remember.'),
      ('You\'re building him in real time',
       'Tonight\'s log is tomorrow\'s confidence. Tap in.'),
    ],
    _NudgeState.protocolBroken: [
      ('Don\'t fold on yourself',
       'You can still save the streak. Restart tonight.'),
      ('You broke',
       'Get back. Today. One day off is a slip — two becomes the story.'),
      ('He didn\'t break his streak',
       'You did. Decide which guy you want to be by midnight.'),
      ('The version she liked',
       'Is fading. You stopped showing up. Come back.'),
      ('One bad day',
       'Doesn\'t end it. Two does. Open the app.'),
      ('Restart tonight',
       'The version she falls for is one streak away. Begin.'),
      ('Comeback streak hits different',
       'Day one again. Two minutes. Be the guy who returns.'),
      ('The man rooms remember',
       'Is the one who restarted. Log tonight.'),
    ],
    _NudgeState.dormant7d: [
      ('You went quiet',
       'She didn\'t.'),
      ('A week away',
       'The version you were building is rusting. Two minutes back.'),
      ('Other men didn\'t pause',
       'You did. Open the app before it stops mattering.'),
      ('Where did you go',
       'The work you started doesn\'t finish on its own.'),
      ('Come back to the version that owns rooms',
       'Two minutes. Right back where you left off.'),
      ('The guy who owns the room',
       'Is still inside. Open the app. Two minutes tonight.'),
      ('Welcome back, future sharpest',
       'Log one rep. Tomorrow you\'re sharp again.'),
    ],
    _NudgeState.dormant14d: [
      ('Two weeks. He didn\'t pause',
       'Open the app. Last call to keep what you built.'),
      ('You almost made it',
       'Then you stopped. Come back. The reps are still here.'),
      ('She moved on',
       'You didn\'t have to. Open the app.'),
      ('Two weeks dark',
       'Whatever stopped you stops here. Reopen. Two minutes.'),
      ('Restart the glow-up',
       'A scan. A rep. Two minutes. The guy the room remembers, again.'),
      ('The man she chases',
       'Is two minutes back. Open the app. Reload.'),
      ('Come back sharper',
       'Two minutes tonight. Pick up where the streak left you.'),
    ],
    _NudgeState.defaultState: [
      ('Tonight, log the rep',
       'Two minutes keeps the glow-up compounding.'),
      ('Stay sharp',
       'Two minutes. Then sleep.'),
      ('Don\'t go cold',
       'Two-minute rep. Tomorrow\'s mirror stays honest.'),
      ('Commit a protocol',
       'Skin, jaw, hair — pick the axis. The 60 days start there.'),
      ('Build the man she can\'t ignore',
       'One rep. Every night. The compounding is silent.'),
      ('Rescan and see the delta',
       'The number moves when you do. Check tonight.'),
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
