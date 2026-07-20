import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/protocol.dart';
import '../providers/auralay_app_provider.dart';

/// Local-notification retention engine.
///
/// Three notification classes, all scheduled on-device (zero backend):
///
///   1. **Daily streak nudge** (id [_streakNudgeId]) — 8pm local time,
///      every day the protocol is active. Copy morphs by streak state:
///      live → celebratory; at-risk → urgent; broken → re-engage.
///      Re-scheduled each time the user checks in so the next nudge
///      speaks to the *new* state.
///
///   2. **Rescan reminders** (ids [_rescanDay14Id], [_rescanDay30Id]) —
///      fire at 10am local on milestone days. Prompts the user to take a
///      new scan and compare to baseline.
///
///   3. **Milestone celebrations** — currently fired in-app on check-in
///      (see [ProtocolScreen]); not scheduled via notifications because
///      they should feel like a reward when the user acts, not a ping
///      when they don't.
///
/// No permissions pester: we call the platform-permission API exactly
/// once, the first time a protocol is started. Users who decline silently
/// lose retention features — the rest of the app still works.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Exposed for DailyNudgeService — which schedules its own
  /// id alongside the legacy IDs this service still manages.
  static FlutterLocalNotificationsPlugin get plugin => _plugin;
  static bool _initialized = false;
  static bool _permissionRequested = false;

  // Stable integer IDs so later schedules overwrite earlier ones cleanly.
  // 1xxx = ImHim Looks protocol; 2xxx = Auralay training (Eyes + Game tabs).
  static const _streakNudgeId        = 1001;
  static const _rescanDay14Id        = 1014;
  static const _rescanDay30Id        = 1030;
  // Auralay graft — fires at 9pm local if the user hasn't trained today.
  // Independent of the protocol streak (1001) so each can speak to its
  // own state without contaminating the other.
  static const _trainingNudgeId      = 2001;

  // ─────────────────────────────────────────────────────────────────────────
  //  INIT
  // ─────────────────────────────────────────────────────────────────────────

  /// Initialise plugin + timezone database. Safe to call on every app
  /// launch; guarded by [_initialized]. Does NOT request notification
  /// permission — that's deferred to the first protocol start so users
  /// aren't asked before the feature exists in their mental model.
  static Future<void> init() async {
    if (_initialized) return;
    try {
      tz_data.initializeTimeZones();

      const init = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _plugin.initialize(init);
      _initialized = true;
    } catch (e) {
      // Plugin init can fail on web/desktop or in restricted test
      // environments. Never fatal — retention degrades to in-app only.
      debugPrint('NotificationService.init failed: $e');
    }
  }

  /// Request notification permission from the user. Called lazily the
  /// first time a protocol is started so the prompt has a clear context
  /// ("your daily streak reminder").
  static Future<void> requestPermissionIfNeeded() async {
    if (_permissionRequested) return;
    _permissionRequested = true;
    try {
      // iOS
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      // Android 13+
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('NotificationService.requestPermission failed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  STREAK NUDGE — 8pm daily
  // ─────────────────────────────────────────────────────────────────────────

  /// Schedule the next 8pm streak nudge. Called when a protocol is
  /// created, after a check-in, and whenever the streak state changes.
  /// If the user has already checked in today, schedules for tomorrow
  /// instead.
  static Future<void> scheduleStreakNudge(Protocol p) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(_streakNudgeId);

      final now  = tz.TZDateTime.now(tz.local);
      var target = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, 20, 0); // 8pm today
      if (now.isAfter(target) || p.completedToday) {
        target = target.add(const Duration(days: 1));
      }

      final (title, body) = _streakCopy(p);

      await _plugin.zonedSchedule(
        _streakNudgeId,
        title,
        body,
        target,
        _streakDetails(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('scheduleStreakNudge failed: $e');
    }
  }

  /// v303 — daily streak nudge copy. Bro: "powerful notifications
  /// that hit hard psychology — think what sells, what retains."
  /// Four state lanes (fresh / live / at-risk / broken) × multiple
  /// rotating lines per lane so the user never sees the same
  /// nudge twice in a row. Rotation key is the protocol day —
  /// deterministic, no RNG, so a given day always gets the same
  /// line (predictable QA, retains identity-coherent voice across
  /// the user's run).
  ///
  /// Milestone overrides (day 3 / 7 / 14 / 30 / 60) trump the lane
  /// pool on the day they hit so the big moments get the loudest
  /// copy. The aim is the friend-who-pulls voice from the rizz
  /// prompts, applied to retention: brutal, identity-anchored,
  /// no corporate cheer.
  static (String title, String body) _streakCopy(Protocol p) {
    // ── Milestone overrides — fire on the exact day, regardless
    //    of streak state. These are the lines the user will read
    //    to friends. Hit them hard.
    final milestone = _milestoneCopy(p.effectiveStreak);
    if (milestone != null) return milestone;

    final lane = _laneFor(p);
    final i = (p.currentDay - 1).clamp(0, 9999) % lane.length;
    return lane[i];
  }

  /// Hard-stop copy on the day a streak milestone lands. Fires only
  /// when [effectiveStreak] matches one of the milestone numbers
  /// exactly — bumping past resumes the lane rotation.
  static (String, String)? _milestoneCopy(int streak) {
    switch (streak) {
      case 3:  return ('3 days in', 'The habit just got real. Don\'t blink now.');
      case 7:  return ('One week', 'Most quit before this. You didn\'t. Don\'t break it.');
      case 14: return ('Two weeks', 'This is who you are now. Lock it.');
      case 21: return ('21 days', 'Old habit dead. New man installed. Keep building.');
      case 30: return ('30 days', 'The version of you that quit can\'t reach you here.');
      case 45: return ('45 days', 'Magnetic territory. The room finds you. Stay on it.');
      case 60: return ('60 days', 'Final form. Today is your IMHIM-certified day.');
    }
    return null;
  }

  /// Pick the rotating line pool for the user's current state.
  static List<(String, String)> _laneFor(Protocol p) {
    switch (p.streakStatus) {
      case StreakStatus.fresh:    return _freshLines(p);
      case StreakStatus.live:     return _liveLines(p);
      case StreakStatus.atRisk:   return _atRiskLines(p);
      case StreakStatus.broken:   return _brokenLines(p);
    }
  }

  /// Brand-new: no check-in yet. Identity-gain framing — the man
  /// they're becoming starts here, not next week.
  static List<(String, String)> _freshLines(Protocol p) {
    final n = p.currentDay;
    return [
      ('Day $n. Start the run.',
       'The version of you that quits doesn\'t exist yet. Two minutes.'),
      ('Don\'t install. Begin.',
       'Day $n is the only day that ever matters. Log it.'),
      ('First rep, day $n.',
       'Strangers will see the man who started. Make today him.'),
      ('Open the door.',
       'You downloaded an app to become Him. Press start.'),
    ];
  }

  /// Live streak — identity-anchored, pride-of-build framing. Each
  /// day is a brick in the man.
  static List<(String, String)> _liveLines(Protocol p) {
    final s = p.effectiveStreak;
    final n = p.currentDay;
    return [
      ('$s days locked in', 'Log day $n. The reps are the work.'),
      ('Don\'t skip the man', 'Day $n. The version of you you\'re building is watching.'),
      ('Keep the chain', '$s days clean. One log away from $s+1.'),
      ('You\'re different now', 'Day $n. Everyone you used to be lost. Keep it that way.'),
      ('No off days', '$s days = $s days. Today doesn\'t get a pass.'),
      ('Strangers notice first', 'Friends notice last. Stack day $n.'),
      ('The man you\'re becoming',
       'is built one log at a time. Day $n is on the table.'),
    ];
  }

  /// At risk — yesterday was the last log, today is the cliff.
  /// Loss framing, brutal but not mean.
  static List<(String, String)> _atRiskLines(Protocol p) {
    final s = p.currentStreak;
    return [
      ('Don\'t fold on yourself',
       '24h to keep $s. Quitters always think tomorrow.'),
      ('$s days on the line',
       'The Him you\'re becoming is watching. Don\'t embarrass him.'),
      ('One log saves the run',
       '$s days. Two minutes. Nobody respects "almost did it."'),
      ('You\'re one tap from $s+1',
       'or one no-show from zero. Pick.'),
      ('Streak at risk',
       '$s days. Don\'t be the guy who folded on himself.'),
    ];
  }

  /// Broken — gap past the freeze budget. Identity-rebuild, no
  /// shame. The man who pulls picks himself up.
  static List<(String, String)> _brokenLines(Protocol p) {
    final l = p.longestStreak;
    return [
      ('Start again', 'Longest was $l. The man who pulls comes back.'),
      ('Day one again',
       'Quitting is a habit too. Break it. Log today.'),
      ('You missed. Don\'t miss twice',
       'The work still compounds when you fall. Stand up.'),
      ('Rebuild the chain',
       'Your $l-day record is the proof you can. Go again.'),
    ];
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  RESCAN REMINDERS — day 14 and day 30, 10am local
  // ─────────────────────────────────────────────────────────────────────────

  /// Schedule both rescan reminders when a new protocol starts. Fires at
  /// 10am local on the respective start+14 and start+30 dates. If those
  /// dates are already in the past (e.g. user re-opens an old protocol),
  /// the specific reminder is skipped.
  static Future<void> scheduleRescanReminders(Protocol p) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(_rescanDay14Id);
      await _plugin.cancel(_rescanDay30Id);

      final start = p.startedAt;
      final day14 = _tzAt(start.add(const Duration(days: 14)), 10);
      final day30 = _tzAt(start.add(const Duration(days: 30)), 10);
      final now   = tz.TZDateTime.now(tz.local);

      if (day14.isAfter(now)) {
        await _plugin.zonedSchedule(
          _rescanDay14Id,
          'Day 14 · the delta',
          'Two weeks of reps. Rescan and watch your number move.',
          day14,
          _rescanDetails(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
      if (day30.isAfter(now)) {
        await _plugin.zonedSchedule(
          _rescanDay30Id,
          'Day 30 · halfway',
          'Halfway up. Rescan — see how far the face has climbed.',
          day30,
          _rescanDetails(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (e) {
      debugPrint('scheduleRescanReminders failed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  CANCEL — called on protocol end
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> cancelAllProtocolNotifications() async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(_streakNudgeId);
      await _plugin.cancel(_rescanDay14Id);
      await _plugin.cancel(_rescanDay30Id);
    } catch (e) {
      debugPrint('cancelAllProtocolNotifications failed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  internal helpers
  // ─────────────────────────────────────────────────────────────────────────

  static tz.TZDateTime _tzAt(DateTime d, int hour) =>
      tz.TZDateTime(tz.local, d.year, d.month, d.day, hour);

  static NotificationDetails _streakDetails() => const NotificationDetails(
    android: AndroidNotificationDetails(
      'mirrorly.streak', 'Streak reminders',
      channelDescription: 'Daily nudge to log your protocol before midnight.',
      importance: Importance.high, priority: Priority.high,
    ),
    // v280 — badgeNumber: 1 makes iOS render the red unread-count
    // dot on the app icon when this notification fires. Cleared on
    // app foreground via the lifecycle hook in main.dart. Retention
    // play: the red dot is the strongest re-open prompt iOS offers.
    iOS: DarwinNotificationDetails(badgeNumber: 1),
  );

  static NotificationDetails _rescanDetails() => const NotificationDetails(
    android: AndroidNotificationDetails(
      'mirrorly.rescan', 'Rescan reminders',
      channelDescription: 'Milestone prompts to rescan and check your deltas.',
      importance: Importance.defaultImportance, priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(badgeNumber: 1),
  );

  // ─────────────────────────────────────────────────────────────────────────
  //  TRAINING NUDGE — 9pm daily, gaze + presence streak (Auralay graft)
  //
  //  Distinct from the protocol streak (1001) because they map to different
  //  rituals: protocol = log today's face routine; training = run a 30-second
  //  drill. Each survives the other's misses, and the copy speaks to its own
  //  state so they don't blur into one another.
  // ─────────────────────────────────────────────────────────────────────────

  /// Schedule (or re-schedule) the daily 9pm training nudge. Called after
  /// every training session via [AuralayAppProvider.recordSession]
  /// completes, and on app boot. Reads streak/lastSession state directly
  /// from prefs so it doesn't need a Provider context.
  static Future<void> scheduleTrainingNudge({
    required int streakDays,
  }) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(_trainingNudgeId);

      final trainedToday = await AuralayAppProvider.readTrainedToday();
      final atRisk       = await AuralayAppProvider.readStreakAtRisk();

      final now    = tz.TZDateTime.now(tz.local);
      var target   = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, 21, 0); // 9pm today
      // If 9pm has already passed today (or user already trained), push it
      // to tomorrow so the nudge speaks to a meaningful state.
      if (now.isAfter(target) || trainedToday) {
        target = target.add(const Duration(days: 1));
      }

      final (title, body) = _trainingCopy(
        streakDays:   streakDays,
        trainedToday: trainedToday,
        atRisk:       atRisk,
      );

      await _plugin.zonedSchedule(
        _trainingNudgeId,
        title,
        body,
        target,
        _trainingDetails(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('scheduleTrainingNudge failed: $e');
    }
  }

  /// Cancel the training nudge — call this when the user has trained
  /// today AND we don't want a pre-emptive evening ping until tomorrow.
  /// Generally the next [scheduleTrainingNudge] takes care of this by
  /// cancelling and rescheduling, but the explicit cancel is exposed for
  /// settings → mute / data deletion flows.
  static Future<void> cancelTrainingNudge() async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(_trainingNudgeId);
    } catch (e) {
      debugPrint('cancelTrainingNudge failed: $e');
    }
  }

  /// Copy lanes — fresh (no streak yet), live, at-risk (streak alive but
  /// nothing today), trained-today (celebratory; the cancel-and-reschedule
  /// dance means this fires the next day, not today).
  static (String title, String body) _trainingCopy({
    required int streakDays,
    required bool trainedToday,
    required bool atRisk,
  }) {
    if (streakDays <= 0) {
      return (
        'Take today\'s test',
        'One round with Lucien or one aura lock. The climb starts now.',
      );
    }
    if (atRisk) {
      return (
        'Don\'t fold on $streakDays',
        'The man you\'re building is watching. One rep keeps the run alive.',
      );
    }
    if (trainedToday) {
      return (
        '$streakDays-day climb',
        'Today\'s reps are in. Come back tomorrow — the ascension continues.',
      );
    }
    return (
      'Your reps are waiting',
      'Test your game or lock your aura. Keep the $streakDays-day climb.',
    );
  }

  static NotificationDetails _trainingDetails() => const NotificationDetails(
    android: AndroidNotificationDetails(
      'mirrorly.training', 'Training streak',
      channelDescription:
          'Daily nudge to run an Eyes / Game drill and keep the streak alive.',
      importance: Importance.high, priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(badgeNumber: 1),
  );

  // ─────────────────────────────────────────────────────────────────────────
  //  BADGE — clear the red unread-count dot on app icon
  // ─────────────────────────────────────────────────────────────────────────

  /// v280 — clear the iOS app-icon badge (the red number). Called from
  /// the lifecycle observer in main.dart whenever the app foregrounds,
  /// so the user opening the app counts as "I saw the notification".
  ///
  /// v298 — the v280 implementation only walked active notifications +
  /// called cancel(id). That clears the delivered tray but does NOT
  /// reset the iOS `applicationIconBadgeNumber` — flutter_local_
  /// notifications 17.x has no badge setter. Result: badge stayed at
  /// "1" forever after the first notification fired. Now we ALSO
  /// invoke a native AppDelegate MethodChannel ("clearAppBadge")
  /// that calls UNUserNotificationCenter.setBadgeCount(0). Channel
  /// name + handler live in ios/Runner/AppDelegate.swift.
  ///
  /// On Android the per-icon dot is system-managed and clears
  /// automatically when the user opens / dismisses; no code path
  /// needed there.
  static const _kBadgeChannel = MethodChannel('com.imhim.app/share_intake');

  static Future<void> clearIconBadge() async {
    if (!_initialized) return;
    try {
      final active = await _plugin.getActiveNotifications();
      for (final n in active) {
        final id = n.id;
        if (id != null) await _plugin.cancel(id);
      }
    } catch (e) {
      debugPrint('clearIconBadge cancel-active failed: $e');
    }
    try {
      // Hard reset via native — the only way to clear the badge
      // number on iOS without flutter_local_notifications native
      // support. No-op on Android (the channel only handles this
      // on the iOS side; Android handler returns
      // FlutterMethodNotImplemented, which we swallow).
      await _kBadgeChannel.invokeMethod<void>('clearAppBadge');
    } catch (e) {
      debugPrint('clearIconBadge native failed: $e');
    }
  }
}
