import 'package:shared_preferences/shared_preferences.dart';

/// v281 — ASCENSION SERVICE.
///
/// Pure-functional layer that maps "raw protocol day + cap usage +
/// scan history" → the things the Ascension home tab needs to
/// render: current rank, days remaining, daily missions, identity
/// progression, achievement timeline, unlock state of the Day-60
/// final form.
///
/// The Ascension tab is a RETENTION SCREEN. It does not measure;
/// it motivates. Every computation here is in service of the
/// psychology bro spec'd:
///
///   - "Who do I become if I finish?"
///   - The flame stays alive as long as you keep showing up.
///   - Rank is a public status (Observer → Initiate → … → Mirrorly)
///     that compounds; users protect status, not percentages.
///   - The cost of quitting is named explicitly (rotating fear
///     reminder).
///   - The Day-60 unlock is a locked premium card today; the
///     anticipation IS the retention.
class AscensionService {
  AscensionService._();

  static const int _totalDays = 60;

  // ── Rank progression — the identity ladder ─────────────────────────────
  //
  // Six tiers, gated by day. Each is a STATUS label first, copy second.
  // Bro: "People care about status. Not percentages."
  static const List<AscendRank> _ranks = [
    AscendRank(
      minDay: 1,
      label: 'OBSERVER',
      tagline: 'You\'re watching. That\'s the first move.',
    ),
    AscendRank(
      minDay: 10,
      label: 'INITIATE',
      tagline: 'The work has started. The mirror reflects it.',
    ),
    AscendRank(
      minDay: 20,
      label: 'CONTENDER',
      tagline: 'People who knew you before don\'t recognize this version.',
    ),
    AscendRank(
      minDay: 30,
      label: 'DANGEROUS',
      tagline: 'You walk into rooms differently now.',
    ),
    AscendRank(
      minDay: 45,
      label: 'MAGNETIC',
      tagline: 'You stopped chasing. The room finds you.',
    ),
    AscendRank(
      minDay: 60,
      label: 'MIRRORLY',
      tagline: 'Identity locked. The man who walks in owning every room.',
    ),
  ];

  static AscendRank rankFor(int day) {
    AscendRank current = _ranks.first;
    for (final r in _ranks) {
      if (day >= r.minDay) {
        current = r;
      } else {
        break;
      }
    }
    return current;
  }

  /// Next rank after the current one, for the progression preview.
  /// Returns null when the user is already at MIRRORLY (final tier).
  static AscendRank? nextRankFor(int day) {
    for (final r in _ranks) {
      if (r.minDay > day) return r;
    }
    return null;
  }

  /// The whole ladder — used by the rank progression widget so each
  /// tier can be rendered with its label, day threshold, and "passed
  /// / current / locked" state.
  static List<AscendRank> ranks() => List.unmodifiable(_ranks);

  // ── Days remaining + progress ──────────────────────────────────────────

  /// Total Ascension length in days. Kept as a static constant so the
  /// flame ring widget can read it without a Protocol instance (covers
  /// the case where the user is pre-protocol).
  static int get totalDays => _totalDays;

  // The ascension DAY is now the earned active-day count from
  // StreakService (days you actually showed up), NOT the protocol's
  // calendar day. These helpers take that already-computed day so the
  // rank ladder, days-remaining, ring fill, and final-form unlock all
  // read the same earned number.

  static int daysRemainingFor(int day) {
    return (_totalDays - day).clamp(0, _totalDays);
  }

  static double progressFor(int day) {
    return (day / _totalDays).clamp(0.0, 1.0);
  }

  static bool finalFormUnlockedFor(int day) {
    return day >= _totalDays;
  }

  // ── The Cost of Quitting — rotating fear reminder ──────────────────────
  //
  // Bro: "Hit fear. This changes every few days." The reminders are
  // anchored in the user's stated reasons for installing — they cycle
  // on a per-day basis so the line that hits is fresh each time.
  //
  // v289 — PARKED. Replaced by [todayMessageFor] (rotating identity
  // line, not fear) on the Ascension surface. Kept here in case we
  // want to surface it elsewhere; the array is unreferenced for now.
  static const List<String> _costLines = [
    'You started because:\n'
    '• You hated photos\n'
    '• You hesitated approaching\n'
    '• You overthought messages\n'
    '• You knew you were capable of more\n\n'
    'Don\'t return there.',
    'The version of you that quit before quit because:\n'
    '• It was easier to scroll than to scan\n'
    '• It was easier to say "next week" than to act today\n\n'
    'You already did the hard part. Showed up.',
    'Three months ago, you would have killed for this clarity.\n\n'
    'Don\'t let the man you used to be talk you out of becoming\n'
    'the man you\'re becoming.',
    'Quitting now costs:\n'
    '• Every photo you avoid for the next 12 months\n'
    '• Every hesitation in every conversation\n'
    '• Every "I should\'ve" 5 years from now\n\n'
    'Stay.',
    'The streak isn\'t a number.\n'
    'It\'s a contract you made with the version of you\n'
    'who decided to be different.\n\n'
    'Honor it.',
  ];

  /// Cycles through cost-of-quitting reminders so the page doesn't
  /// feel static. Day N picks message N % count — every ~5 days the
  /// user sees a new fear-prompt without us having to write 60 unique
  /// strings. PARKED in v289 — Ascend surface now uses
  /// [todayMessageFor]. Helper kept for any caller still on the old
  /// fear-line model.
  static String costOfQuittingLine(int day) {
    if (_costLines.isEmpty) return '';
    return _costLines[(day - 1) % _costLines.length];
  }

  // ── Today's Message — rotating identity line (v289) ────────────────────
  //
  // Replaces the Cost of Quitting fear-card on the Ascend tab. The
  // consultant: "[Cost of Quitting] feels manufactured. Most users
  // skip reading it after Day 3."  An identity line is stickier —
  // it's about who the user IS becoming, not what they LOSE if they
  // quit. The day axis primes a new line every visit so the surface
  // never goes stale, and four streak-milestone overrides reward
  // the lock-in moments without us writing 60 unique strings.
  static const List<String> _dailyMessages = [
    // 1
    'Day 1. The version of you that quits doesn\'t exist yet.',
    'Two days in. Most installs are already dormant.',
    'Three days. The habit is starting to bite.',
    'Most users quit before Day 7. Not you.',
    'Five days. You\'re running.',
    'Six days. The protocol is starting to feel like the floor.',
    'One week. The man who started this is already gone.',
    // 8
    'Day 8. You\'re past the average drop-off.',
    'Nine days. Your face hasn\'t changed yet. Your habits have.',
    'Day 10. Initiate territory.',
    'Eleven days. Strangers will notice before friends do.',
    'Your streak is becoming valuable.',
    'Day 13. The mirror is no longer the enemy.',
    'Two weeks. Take the mid-protocol scan today.',
    // 15
    'Fifteen days. Halfway to Contender.',
    'Day 16. The work is compounding.',
    'Seventeen days. The discipline IS the look.',
    'Day 18. The before-photo is no longer who you are.',
    'Nineteen days. Stay loud, stay quiet, stay on it.',
    'Day 20. Contender. Welcome.',
    'Twenty-one days. Old habit dead. New habit installed.',
    // 22
    'You are closer to Contender than Observer.',
    'Day 23. The reps are paying out.',
    'Twenty-four days. The man you used to be can\'t reach you here.',
    'Day 25. Five days from Dangerous.',
    'Twenty-six days. Lock in.',
    'Day 27. Tomorrow you mark the delta.',
    'Day 28. Mid-protocol scan. Capture the change.',
    // 29
    'Twenty-nine days. The proof is in the new photo.',
    'Day 30. Dangerous.',
    'Thirty-one days. The room re-orients when you walk in.',
    'Day 32. People are starting to notice before you do.',
    'Day 33. The protocol is your baseline now.',
    'Thirty-four days. You\'re building inventory.',
    'Day 35. Two-thirds in. Don\'t lose the form.',
    // 36
    'Day 36. The version of you that quits doesn\'t exist anymore.',
    'People are starting to notice before you do.',
    'Day 38. Discipline reads as confidence.',
    'Thirty-nine days. The mirror is on your side now.',
    'Day 40. The final stretch.',
    'Forty-one days. You\'ve earned the next 60.',
    'Day 42. Six weeks. You\'re different.',
    // 43
    'Forty-three days. Don\'t fumble it.',
    'Day 44. Two days from Magnetic.',
    'Day 45. Magnetic. The room finds you.',
    'Forty-six days. Walk like the man you are.',
    'Day 47. Approach. The fear is small now.',
    'Forty-eight days. The streak protects you.',
    'Day 49. Stay on it.',
    // 50
    'Fifty days. Ten left.',
    'Day 51. The certificate is in sight.',
    'Fifty-two days. Don\'t stop now.',
    'Day 53. Stay loud, stay sharp.',
    'Fifty-four days. Six days from Mirrorly.',
    'Day 55. The final form is taking shape.',
    'Five days remain.',
    // 57
    'Four days remain.',
    'Three days remain.',
    'Two days. Final scan tomorrow.',
    'One day remains.',
  ];

  /// One-line identity message keyed to the user's current day in the
  /// protocol. Streak milestones (3 / 7 / 14 / 30 / 60) override the
  /// day line on the day they're hit so the lock-in moments aren't
  /// drowned out by generic copy. Falls back to a starter line when
  /// no protocol is active so the surface always reads as live.
  static String todayMessageFor({
    required int day,
    required int streak,
  }) {
    switch (streak) {
      case 3:  return '3 days locked in. The habit is forming.';
      case 7:  return 'One week. Most quit before this. You didn\'t.';
      case 14: return 'Two weeks. This is who you are now.';
      case 30: return '30-day streak. The man you were is gone.';
      case 60: return '60 days. Final form.';
    }
    if (_dailyMessages.isEmpty) return '';
    final i = ((day - 1).clamp(0, _dailyMessages.length - 1));
    return _dailyMessages[i];
  }

  // ── MIRRORLY Score — the composite (v289) ─────────────────────────────────
  //
  // Bro + consultant: ONE number that unifies the four surfaces so
  // the user is levelling one character, not managing four systems.
  // Built from the three signals we can score honestly today:
  //
  //   LOOKS       (35 %)  — latest scan score, 0-100
  //   GAME        (35 %)  — best Free Flow score, 0-100
  //   CONSISTENCY (30 %)  — completedDays / max(currentDay, 1) × 100
  //
  // Rizz is intentionally dropped from the score because we have no
  // honest server-side judge for it (bro: "rizz score is hard we
  // don't really matter that"). It still surfaces as a soft "wins"
  // signal in the missions panel.
  //
  // The user-facing label is MIRRORLY SCORE everywhere — never
  // "attraction score" (App Store 3.1.5 / 5.2 risk on attractiveness
  // claims).
  static int imhimScoreFromComponents({
    required int looks,
    required int game,
    required int consistency,
  }) {
    final l = looks.clamp(0, 100);
    final g = game.clamp(0, 100);
    final c = consistency.clamp(0, 100);
    final raw = 0.35 * l + 0.35 * g + 0.30 * c;
    return raw.round().clamp(0, 100);
  }

  // CONSISTENCY is now computed by StreakService as a rolling 7-day
  // mission-completion rate (see StreakService.progress /
  // AscensionSnapshot.consistency). The old protocol-ratio / streak-proxy
  // formula was replaced so that doing 3-of-5 missions visibly drops the
  // score while never breaking the streak — exactly the "half-showing-up"
  // signal bro asked for. Callers read the snapshot value and feed it
  // straight into [imhimScoreFromComponents].

  /// Snapshot the current MIRRORLY score against TODAY so the weekly
  /// delta can be computed without storing a history table. Stamps
  /// `imhim_score_snapshot_<n>` + `imhim_score_snapshot_<n>_ymd` in
  /// SharedPreferences. Idempotent per calendar day — re-calling on
  /// the same day overwrites, so the user gets one canonical record
  /// per day regardless of how many times they open the tab.
  static const _kSnapshotKey      = 'imhim_score_snapshot';
  static const _kSnapshotYmdKey   = 'imhim_score_snapshot_ymd';
  static const _kPriorSnapshot    = 'imhim_score_snapshot_prior';
  static const _kPriorSnapshotYmd = 'imhim_score_snapshot_prior_ymd';

  static int _ymdOf(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  /// Persist today's MIRRORLY score so a 7-days-ago lookup has data to
  /// diff against. Pushes the previous snapshot into the `prior`
  /// slot on day-change so we always have two reference points: the
  /// freshest snapshot and the one before it. That's enough to
  /// compute "↑ +4 This Week" without a row-per-day table.
  static Future<void> snapshotTodayScore(int score) async {
    try {
      final prefs    = await SharedPreferences.getInstance();
      final todayYmd = _ymdOf(DateTime.now());
      final lastYmd  = prefs.getInt(_kSnapshotYmdKey) ?? 0;
      if (lastYmd == todayYmd) {
        // Same calendar day — refresh the value, keep prior slot.
        await prefs.setInt(_kSnapshotKey, score);
        return;
      }
      // Day rolled — move the existing snapshot into the prior slot.
      final lastScore = prefs.getInt(_kSnapshotKey);
      if (lastScore != null && lastYmd > 0) {
        await prefs.setInt(_kPriorSnapshot,    lastScore);
        await prefs.setInt(_kPriorSnapshotYmd, lastYmd);
      }
      await prefs.setInt(_kSnapshotKey,    score);
      await prefs.setInt(_kSnapshotYmdKey, todayYmd);
    } catch (_) {/* surface stays at +0 if prefs are unhappy */}
  }

  /// Weekly delta — current score MINUS whatever snapshot is closest
  /// to 7 days ago. Returns 0 (not the score itself) when no prior
  /// snapshot exists, so a freshly-installed user sees a clean "+0"
  /// rather than a misleading "+67".
  static Future<int> weeklyDeltaFor(int currentScore) async {
    try {
      final prefs    = await SharedPreferences.getInstance();
      final priorScore = prefs.getInt(_kPriorSnapshot);
      final priorYmd   = prefs.getInt(_kPriorSnapshotYmd) ?? 0;
      if (priorScore == null || priorYmd == 0) return 0;
      // Use whichever stored snapshot is older than 4 days — that
      // gives us a "this week" delta even when the user hasn't
      // opened the tab for several days running. Fall back to the
      // freshest one when we only have today.
      final todayYmd = _ymdOf(DateTime.now());
      // Coarse age check via the difference in YMD ints — close
      // enough for a weekly window without parsing dates back out.
      final ageDays = (todayYmd ~/ 100 - priorYmd ~/ 100);
      // If the prior is too recent (same day) we can't reliably
      // diff "this week" — return 0 instead of a same-day spike.
      if (ageDays < 1) return 0;
      return currentScore - priorScore;
    } catch (_) {
      return 0;
    }
  }
}

/// One rank tier in the identity progression. Immutable, const-able.
class AscendRank {
  final int minDay;
  final String label;
  final String tagline;
  const AscendRank({
    required this.minDay,
    required this.label,
    required this.tagline,
  });
}

/// A single mission the user can tick off today. The Ascension home
/// tab renders 5 of these every day. Bro: "Not tasks. Missions."
class AscendMission {
  /// Short title shown in the row. ≤ 32 chars.
  final String title;
  /// Optional one-line hint shown muted underneath the title.
  final String hint;
  /// Whether the user has completed this mission today.
  final bool done;
  /// Optional onTap — null means the mission is informational.
  final void Function()? onTap;

  const AscendMission({
    required this.title,
    required this.done,
    this.hint = '',
    this.onTap,
  });
}

/// One milestone in the user's ascension record (the timeline).
/// Bro: "Not charts. Not graphs. Timeline. This becomes their story."
class AscendMilestone {
  final int day;
  final String title;
  final String detail;
  const AscendMilestone({
    required this.day,
    required this.title,
    this.detail = '',
  });
}
