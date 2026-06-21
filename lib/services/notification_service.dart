import 'package:flutter/foundation.dart';
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
  // 1xxx = Mirrorly protocol; 2xxx = Auralay training (Eyes + Game tabs).
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

  /// Copy for the daily streak nudge, tuned by the protocol's current
  /// state. Four lanes: brand-new (no streak yet), live, at-risk, broken.
  static (String title, String body) _streakCopy(Protocol p) {
    switch (p.streakStatus) {
      case StreakStatus.fresh:
        return (
          'Day ${p.currentDay} of ${p.lengthDays}',
          'Your protocol is waiting. Two minutes locks in day one.',
        );
      case StreakStatus.live:
        return (
          '${p.effectiveStreak} days · on fire',
          'Log day ${p.currentDay} before midnight. Streak stays alive.',
        );
      case StreakStatus.atRisk:
        return (
          'Don\'t break ${p.currentStreak}',
          'Log today. One freeze available if you miss.',
        );
      case StreakStatus.broken:
        return (
          'Start a new run',
          'Streak reset. Longest was ${p.longestStreak}. Go again.',
        );
    }
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
          'Day 14 · rescan',
          'Two weeks in. Take a new scan and compare to baseline.',
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
          'Day 30 · midpoint',
          'Rescan time. Check which axis moved.',
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
        'Run a drill',
        'Eyes or Game — 30 seconds locks in day one.',
      );
    }
    if (atRisk) {
      return (
        'Don\'t break $streakDays',
        'You\'re on a $streakDays-day run. One drill keeps it alive.',
      );
    }
    if (trainedToday) {
      return (
        '$streakDays days · on fire',
        'See you tomorrow. Keep the streak.',
      );
    }
    return (
      '$streakDays days',
      'One drill. 30 seconds. Streak stays alive.',
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
  /// Implementation: removeAllDeliveredNotifications also resets the
  /// application icon badge on iOS — that's the documented side-effect.
  /// On Android the per-icon dot is system-managed and clears
  /// automatically when the notification is tapped or dismissed; no
  /// code path needed.
  static Future<void> clearIconBadge() async {
    if (!_initialized) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.removeAllDeliveredNotifications();
    } catch (e) {
      debugPrint('clearIconBadge failed: $e');
    }
  }
}
