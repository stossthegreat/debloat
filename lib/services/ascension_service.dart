import '../models/protocol.dart';

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
///   - Rank is a public status (Observer → Initiate → … → ImHim)
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
      label: 'IMHIM',
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
  /// Returns null when the user is already at IMHIM (final tier).
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

  /// Day N out of 60. Falls back to day 1 when no protocol is active so
  /// the screen always renders something meaningful.
  static int dayFor(Protocol? p) {
    if (p == null) return 1;
    return p.currentDay.clamp(1, _totalDays);
  }

  static int daysRemainingFor(Protocol? p) {
    final n = dayFor(p);
    return (_totalDays - n).clamp(0, _totalDays);
  }

  static double progressFor(Protocol? p) {
    return dayFor(p) / _totalDays;
  }

  static bool finalFormUnlockedFor(Protocol? p) {
    return dayFor(p) >= _totalDays;
  }

  // ── The Cost of Quitting — rotating fear reminder ──────────────────────
  //
  // Bro: "Hit fear. This changes every few days." The reminders are
  // anchored in the user's stated reasons for installing — they cycle
  // on a per-day basis so the line that hits is fresh each time.
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
  /// strings.
  static String costOfQuittingLine(int day) {
    if (_costLines.isEmpty) return '';
    return _costLines[(day - 1) % _costLines.length];
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
