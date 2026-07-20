import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/auralay_app_state.dart';
import '../services/daily_nudge_service.dart';

/// Auralay-side global state — bridged into ImHim's main `ChangeNotifierProvider`.
///
/// Tracks training progress for the Eyes + Game tabs:
///   - **auraScore**   — accumulator across all sessions (0..100, clamped)
///   - **currentDay**  — synthetic protocol day (advances once per calendar day)
///   - **streakDays**  — consecutive calendar days with a session logged
///
/// Streak rules (post-graft hardening, replaces Auralay's naive
/// "+1 per session" loop):
///   - Same calendar day as last session  → no streak change
///   - Next calendar day                  → streak +1, currentDay +1
///   - 2+ day gap                         → streak resets to 1, currentDay +1
/// This is what the Progress tab + notification scheduler both read.
class AuralayAppProvider extends ChangeNotifier {
  AuralayAppState _state = const AuralayAppState();
  AuralayAppState get state => _state;

  static const _keyOnboarding   = 'has_seen_onboarding';
  static const _keySubscribed   = 'is_subscribed';
  static const _keyStreak       = 'streak_days';
  static const _keyDay          = 'current_day';
  static const _keyAura         = 'aura_score';
  // Calendar-day stamp (yyyymmdd int) of the last session — used to
  // decide whether to count today as a streak day.
  static const _keyLastSession  = 'last_session_ymd';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _state = AuralayAppState(
      hasSeenOnboarding: prefs.getBool(_keyOnboarding) ?? false,
      isSubscribed:      prefs.getBool(_keySubscribed) ?? false,
      streakDays:        prefs.getInt(_keyStreak)       ?? 0,
      currentDay:        prefs.getInt(_keyDay)          ?? 1,
      auraScore:         prefs.getInt(_keyAura)         ?? 0,
    );
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboarding, true);
    _state = _state.copyWith(hasSeenOnboarding: true);
    notifyListeners();
  }

  /// Stub for IAP — mark the user as subscribed locally. Wire to real
  /// `in_app_purchase` flow when StoreKit / Play Billing IDs are live.
  Future<void> setSubscribed(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySubscribed, v);
    _state = _state.copyWith(isSubscribed: v);
    notifyListeners();
  }

  /// Log a training session. Adjusts streak based on the calendar gap since
  /// the previous session (NOT per-session increment, which would inflate
  /// streaks if the user trained twice in one afternoon).
  Future<void> recordSession({required int scoreGain}) async {
    final prefs = await SharedPreferences.getInstance();

    final today    = _todayYmd();
    final lastYmd  = prefs.getInt(_keyLastSession);
    final newScore = (_state.auraScore + scoreGain).clamp(0, 100);

    int newStreak = _state.streakDays;
    int newDay    = _state.currentDay;

    if (lastYmd == null) {
      // First session ever. Streak starts at 1, day stays at 1.
      newStreak = 1;
    } else if (lastYmd == today) {
      // Already logged today — score still accumulates, streak/day untouched.
    } else {
      // Different calendar day.
      final gap = _ymdDayDelta(lastYmd, today);
      newStreak = (gap == 1) ? newStreak + 1 : 1;  // consecutive vs reset
      newDay    = newDay + 1;
    }

    await prefs.setInt(_keyAura,        newScore);
    await prefs.setInt(_keyDay,         newDay);
    await prefs.setInt(_keyStreak,      newStreak);
    await prefs.setInt(_keyLastSession, today);

    _state = _state.copyWith(
      auraScore:  newScore,
      currentDay: newDay,
      streakDays: newStreak,
    );
    notifyListeners();

    // Rebuild the retention horizon with the new state. Fire-and-forget —
    // DailyNudgeService catches its own errors so a permission-denied
    // state never blocks the session log.
    // ignore: discarded_futures
    DailyNudgeService.reschedule();
  }

  // ──────────────────────────────────────────────────────────────────────
  //  Streak helpers — used by ProgressScreen + NotificationService
  // ──────────────────────────────────────────────────────────────────────

  /// True if the user has trained today (any Auralay session).
  bool get trainedToday {
    // Cheap proxy: when streakDays > 0 AND lastSessionDay matches today
    // we know they trained today. We need prefs to confirm, but the
    // synchronous flag is enough for UI tinting; notification scheduling
    // reads prefs directly via [readTrainedToday].
    return false; // synchronous default; ProgressScreen reads readTrainedToday
  }

  /// Async-correct version for the notification scheduler.
  static Future<bool> readTrainedToday() async {
    final prefs = await SharedPreferences.getInstance();
    final last  = prefs.getInt(_keyLastSession);
    return last == _todayYmd();
  }

  /// "At risk" — streak alive but no session yet today. The streak
  /// nudge copy goes urgent when this is true.
  static Future<bool> readStreakAtRisk() async {
    final prefs = await SharedPreferences.getInstance();
    final streak = prefs.getInt(_keyStreak) ?? 0;
    if (streak <= 0) return false;
    return !(await readTrainedToday());
  }

  static int _todayYmd() {
    final n = DateTime.now();
    return n.year * 10000 + n.month * 100 + n.day;
  }

  /// Day delta between two yyyymmdd ints. Used to detect "next day" vs
  /// "2+ day gap" without parsing calendar arithmetic ourselves.
  static int _ymdDayDelta(int from, int to) {
    final f = _ymdToDate(from);
    final t = _ymdToDate(to);
    return t.difference(f).inDays;
  }

  static DateTime _ymdToDate(int ymd) =>
      DateTime(ymd ~/ 10000, (ymd ~/ 100) % 100, ymd % 100);
}
