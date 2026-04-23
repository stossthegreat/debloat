/// A 60-day aesthetic program targeting a specific weakness surfaced by the
/// user's scan. Generated once by the AI advisor and tracked daily — this is
/// the core retention loop. Check-ins are the habit; the before/after at day
/// 60 is the reward. The streak is the lock-in.
class Protocol {
  final String id;
  final DateTime startedAt;
  final int lengthDays;            // 60 typical
  final String title;              // "Sharpen the Jaw"
  final String targetAxis;         // "Jaw definition"
  final String summary;            // One-paragraph description
  final List<DailyTask> dailyTasks;       // recurring — done per day
  final List<ProtocolMilestone> milestones;
  final Set<int> completedDays;    // day indices marked done

  // ── Streak state ──────────────────────────────────────────────────────────
  /// The last date a day was logged — used to compute streak freshness. A
  /// null value means no check-in yet (brand-new protocol).
  final DateTime? lastCheckIn;
  /// Current consecutive-day streak. Freezes preserve it; a miss past the
  /// freeze budget resets it to 1 on the next check-in.
  final int currentStreak;
  /// Best streak ever run on this protocol — never decreases.
  final int longestStreak;
  /// Days where a freeze was auto-consumed to save the streak. Used to
  /// enforce the rolling 7-day freeze budget and to show "freeze used"
  /// markers in the day grid.
  final Set<int> freezeDays;

  const Protocol({
    required this.id,
    required this.startedAt,
    required this.lengthDays,
    required this.title,
    required this.targetAxis,
    required this.summary,
    required this.dailyTasks,
    required this.milestones,
    required this.completedDays,
    this.lastCheckIn,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.freezeDays = const {},
  });

  int get currentDay {
    final diff = DateTime.now().difference(startedAt).inDays + 1;
    return diff.clamp(1, lengthDays);
  }

  double get progress => completedDays.length / lengthDays;

  bool get completedToday => completedDays.contains(currentDay);

  /// The streak as it should be rendered *right now* — accounts for time
  /// passing since the last check-in. Shown as "0" the moment the streak is
  /// visually broken; the next check-in will either revive it (via a freeze)
  /// or formally reset it.
  int get effectiveStreak {
    if (lastCheckIn == null) return 0;
    final todayKey = _dayKey(DateTime.now());
    final lastKey  = _dayKey(lastCheckIn!);
    final diff = todayKey.difference(lastKey).inDays;
    // Same day or yesterday — streak is still live visually (today just
    // hasn't been logged yet if diff == 1).
    if (diff <= 1) return currentStreak;
    return 0;
  }

  /// Streak display state — drives icon colour + copy ("on fire" / "log today"
  /// / "broken").
  StreakStatus get streakStatus {
    if (lastCheckIn == null) return StreakStatus.fresh;
    final todayKey = _dayKey(DateTime.now());
    final lastKey  = _dayKey(lastCheckIn!);
    final diff = todayKey.difference(lastKey).inDays;
    if (diff == 0) return StreakStatus.live;
    if (diff == 1) return StreakStatus.atRisk;
    return StreakStatus.broken;
  }

  /// Number of freezes available right now in the rolling 7-day window.
  /// Zero in the first week of the protocol (habit has to stick first).
  int get freezesAvailable {
    if (currentDay <= 7) return 0;
    final used = freezeDays.where(
      (d) => d >= currentDay - 7 && d < currentDay).length;
    return (1 - used).clamp(0, 1);
  }

  /// Mark the current day as complete and advance the streak. Handles the
  /// freeze-consumption rule: if the user missed one or more days but has a
  /// freeze available, the streak survives and a freeze is recorded for the
  /// day that was saved. First 7 days have zero freeze budget by design.
  Protocol withTodayChecked() {
    final today = _dayKey(DateTime.now());
    final day   = currentDay;

    // Idempotent: already logged today.
    if (lastCheckIn != null && _dayKey(lastCheckIn!) == today) return this;

    int newStreak;
    Set<int> newFreezes = freezeDays;
    if (lastCheckIn == null) {
      newStreak = 1;
    } else {
      final diff = today.difference(_dayKey(lastCheckIn!)).inDays;
      if (diff == 0) {
        // Same calendar day — idempotent, already handled above but keep
        // for symmetry.
        newStreak = currentStreak;
      } else if (diff == 1) {
        // Yesterday → today, the happy path.
        newStreak = currentStreak + 1;
      } else if (diff == 2) {
        // Exactly one missed day. This is the ONLY gap a freeze covers —
        // anything bigger is a full reset (one freeze per week, one day
        // each). Freezes are unavailable in the first 7 days of the
        // protocol by policy.
        if (freezesAvailable > 0) {
          newStreak  = currentStreak + 1;
          newFreezes = {...freezeDays, day - 1};
        } else {
          newStreak = 1;
        }
      } else {
        // Gap of 3+ days — no single freeze saves that. Fresh start.
        newStreak = 1;
      }
    }

    final newLongest = newStreak > longestStreak ? newStreak : longestStreak;

    return _copyWith(
      completedDays: {...completedDays, day},
      lastCheckIn:   today,
      currentStreak: newStreak,
      longestStreak: newLongest,
      freezeDays:    newFreezes,
    );
  }

  /// Legacy entry point — kept so existing call sites compile. Routes
  /// through the streak-aware path.
  Protocol withDayCompleted(int day) => withTodayChecked();

  Protocol _copyWith({
    Set<int>? completedDays,
    DateTime? lastCheckIn,
    int? currentStreak,
    int? longestStreak,
    Set<int>? freezeDays,
  }) => Protocol(
    id: id, startedAt: startedAt, lengthDays: lengthDays, title: title,
    targetAxis: targetAxis, summary: summary, dailyTasks: dailyTasks,
    milestones: milestones,
    completedDays: completedDays ?? this.completedDays,
    lastCheckIn:   lastCheckIn   ?? this.lastCheckIn,
    currentStreak: currentStreak ?? this.currentStreak,
    longestStreak: longestStreak ?? this.longestStreak,
    freezeDays:    freezeDays    ?? this.freezeDays,
  );

  Map<String, dynamic> toJson() => {
    'id':             id,
    'startedAt':      startedAt.toIso8601String(),
    'lengthDays':     lengthDays,
    'title':          title,
    'targetAxis':     targetAxis,
    'summary':        summary,
    'dailyTasks':     dailyTasks.map((t) => t.toJson()).toList(),
    'milestones':     milestones.map((m) => m.toJson()).toList(),
    'completedDays':  completedDays.toList(),
    'lastCheckIn':    lastCheckIn?.toIso8601String(),
    'currentStreak':  currentStreak,
    'longestStreak':  longestStreak,
    'freezeDays':     freezeDays.toList(),
  };

  factory Protocol.fromJson(Map<String, dynamic> j) => Protocol(
    id:          j['id']         as String,
    startedAt:   DateTime.parse(j['startedAt'] as String),
    lengthDays:  (j['lengthDays'] as num).toInt(),
    title:       j['title']      as String? ?? '',
    targetAxis:  j['targetAxis'] as String? ?? '',
    summary:     j['summary']    as String? ?? '',
    dailyTasks:  ((j['dailyTasks'] as List?) ?? [])
                     .map((e) => DailyTask.fromJson(e as Map<String, dynamic>))
                     .toList(),
    milestones:  ((j['milestones'] as List?) ?? [])
                     .map((e) => ProtocolMilestone.fromJson(e as Map<String, dynamic>))
                     .toList(),
    completedDays: Set<int>.from(j['completedDays'] as List? ?? []),
    lastCheckIn: j['lastCheckIn'] == null
        ? null : DateTime.tryParse(j['lastCheckIn'] as String),
    currentStreak: (j['currentStreak'] as num?)?.toInt() ?? 0,
    longestStreak: (j['longestStreak'] as num?)?.toInt() ?? 0,
    freezeDays:    Set<int>.from(j['freezeDays'] as List? ?? []),
  );
}

DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

/// Visual state of the streak — drives icon, colour, and the copy that sits
/// next to the flame.
enum StreakStatus {
  /// No check-ins yet. Show a muted "start the run today" prompt.
  fresh,
  /// Checked in today. Live flame.
  live,
  /// Last check-in was yesterday. Today pending — amber, "log today".
  atRisk,
  /// Two or more days since last check-in. Streak is visually dead; the
  /// next check-in will either revive (freeze) or reset it.
  broken,
}

class DailyTask {
  final String title;
  final String detail;
  final String? duration;  // e.g. "10 min"
  final TaskCategory category;
  final TimeBand timeBand;

  const DailyTask({
    required this.title,
    required this.detail,
    required this.category,
    this.duration,
    this.timeBand = TimeBand.ongoing,
  });

  Map<String, dynamic> toJson() => {
    'title':    title,
    'detail':   detail,
    'duration': duration,
    'category': category.name,
    'timeBand': timeBand.name,
  };

  factory DailyTask.fromJson(Map<String, dynamic> j) => DailyTask(
    title:    j['title']    as String,
    detail:   j['detail']   as String? ?? '',
    duration: j['duration'] as String?,
    category: TaskCategory.values.firstWhere(
      (e) => e.name == j['category'], orElse: () => TaskCategory.habit),
    timeBand: TimeBand.values.firstWhere(
      (e) => e.name == j['timeBand'], orElse: () => TimeBand.ongoing),
  );
}

class ProtocolMilestone {
  final int day;
  final String title;
  final String action; // "Re-scan. Compare to baseline."
  const ProtocolMilestone({
    required this.day, required this.title, required this.action,
  });

  Map<String, dynamic> toJson() => {
    'day': day, 'title': title, 'action': action,
  };

  factory ProtocolMilestone.fromJson(Map<String, dynamic> j) => ProtocolMilestone(
    day:    (j['day'] as num).toInt(),
    title:  j['title']  as String? ?? '',
    action: j['action'] as String? ?? '',
  );
}

enum TaskCategory { habit, exercise, skin, nutrition, grooming }

/// When in the day a task fires. Tasks grouped by band in the protocol screen
/// so the daily flow reads as a schedule, not a checklist. `ongoing` = no
/// specific time (all-day habits, reminders, posture).
enum TimeBand { am, midday, pm, night, ongoing }
