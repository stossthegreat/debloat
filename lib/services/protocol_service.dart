import 'package:shared_preferences/shared_preferences.dart';

import '../models/face_geometry.dart';
import '../models/mirror_analysis.dart';
import '../models/protocol.dart';
import '../models/scan_record.dart';
import 'daily_nudge_service.dart';
import 'local_store_service.dart';
import 'notification_service.dart';

// Canonical axis key. Debloat OS runs exactly ONE protocol axis — the
// Debloat Protocol. The multi-axis engine (per-axis slots, streaks,
// milestones) is kept intact underneath so the axis roster can grow
// again later without a rewrite.
const _axisDebloat     = 'Debloat';
/// Public canonical axis — screens that need to name the axis
/// (aspect cards, deep links) read this instead of hardcoding.
const kDebloatAxis     = _axisDebloat;

/// Creates, loads, and advances the user's active 60-day Debloat
/// Protocol. One axis, one template — time-banded daily tasks and
/// milestones at day 14 / 30 / 60. Content is evidence-aware: sodium /
/// potassium balance, hydration, alcohol, glycogen water-binding, sleep
/// elevation, cold exposure, and lymphatic drainage.
class ProtocolService {
  /// Load THE active protocol — legacy single-active API. Returns
  /// the first active protocol found across all per-axis slots so
  /// pre-multi-protocol call sites keep working unchanged. New
  /// code should call [loadAllActive] or [loadActiveFor].
  static Future<Protocol?> loadActive() async {
    final all = await loadAllActive();
    if (all.isEmpty) return null;
    return all.values.first;
  }

  /// Load every active protocol the user has committed to, keyed by
  /// canonical axis. Empty when nothing is running. The Looks tab
  /// surfaces each one as its own compact tile so SKIN / JAW /
  /// DEBLOAT / HAIR can all run in parallel.
  static Future<Map<String, Protocol>> loadAllActive() async {
    final raw = await LocalStoreService.loadAllProtocols();
    final out = <String, Protocol>{};
    raw.forEach((axis, j) {
      try { out[axis] = Protocol.fromJson(j); } catch (_) {}
    });
    return out;
  }

  /// Load the active protocol for a specific axis (e.g. 'Skin',
  /// 'Jaw definition', 'Hair', 'Puffiness'). Returns null when the
  /// axis has no run.
  static Future<Protocol?> loadActiveFor(String axis) async {
    final j = await LocalStoreService.loadProtocolJsonFor(axis);
    if (j == null) return null;
    try { return Protocol.fromJson(j); } catch (_) { return null; }
  }

  /// Save the legacy single-active slot. Kept so existing call sites
  /// compile; new code should call [saveFor].
  static Future<void> save(Protocol? p) async {
    if (p == null) {
      // Nuke ALL per-axis runs in addition to the legacy slot. This
      // is the "end everything" semantic the old API had.
      await LocalStoreService.saveProtocolJson(null);
      final all = await LocalStoreService.loadAllProtocols();
      for (final axis in all.keys) {
        await LocalStoreService.saveProtocolJsonFor(axis, null);
      }
      await NotificationService.cancelAllProtocolNotifications();
      return;
    }
    await saveFor(p.targetAxis, p);
  }

  /// Save the active protocol for one specific axis without touching
  /// the others. End by passing null. This is what the multi-commit
  /// flow uses — committing SKIN doesn\'t blow away the active JAW
  /// protocol.
  static Future<void> saveFor(String axis, Protocol? p) async {
    await LocalStoreService.saveProtocolJsonFor(axis, p?.toJson());
    if (p == null) {
      // Notifications are global today; tearing them down on any
      // end is the safest move so a stale nudge doesn\'t fire for
      // a protocol that no longer exists. The next markDayComplete
      // on any remaining run re-schedules.
      await NotificationService.cancelAllProtocolNotifications();
    }
  }

  /// End the active protocol for one specific axis (without touching
  /// the others). Convenience over [saveFor].
  static Future<void> endFor(String axis) async {
    await saveFor(axis, null);
  }

  static Future<Protocol> markDayComplete(Protocol p, int day) async {
    final updated = p.withDayCompleted(day);
    // Save under the protocol\'s own axis so a multi-protocol user
    // doesn\'t accidentally blow away a different running plan.
    await saveFor(updated.targetAxis, updated);
    // Stamp today as the LOOKS pillar completion day so the Ascend
    // tab\'s Today\'s Ascension card ticks LOOKS off when a protocol
    // task is logged.
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setInt(
        'looks_done_ymd',
        now.year * 10000 + now.month * 100 + now.day,
      );
    } catch (_) {}
    // Rebuild the retention horizon against the NEW state — a check-in
    // flips PROTOCOL_BROKEN back to PROTOCOL_ACTIVE, so the queued
    // evening copy needs to switch. DailyNudgeService owns all retention
    // notifications now (the legacy 8pm streak scheduler is retired).
    await DailyNudgeService.reschedule();
    return updated;
  }

  /// Start a protocol. Caller supplies the scan, the backend's pulldown
  /// prose, and the geometry — we resolve these into a canonical axis key
  /// before building the protocol. The stored targetAxis is always one of
  /// the canonical names above, never the raw pulldown sentence.
  static Future<Protocol> startForScan(
    ScanRecord scan, {
    required String pulldown,
    required FaceGeometry geometry,
  }) async {
    final axis = resolveAxis(pulldown: pulldown, geometry: geometry);
    final template = _templateFor(axis);
    final protocol = Protocol(
      id:         'proto-${DateTime.now().millisecondsSinceEpoch}',
      startedAt:  DateTime.now(),
      lengthDays: 60,
      title:      template.title,
      targetAxis: axis,
      summary:    template.summary,
      dailyTasks: template.dailyTasks,
      donts:      template.donts,
      successMetrics: template.successMetrics,
      milestones: template.milestones,
      completedDays: const {},
    );
    // saveFor (not save) so committing a NEW axis doesn\'t kill any
    // other active protocol the user already has running.
    await saveFor(axis, protocol);

    // First protocol start is the right moment to ask for notification
    // permission — the user has just committed to a 60-day run, so the
    // "we'll remind you at 8pm" value prop lands. Silent if already
    // granted or declined.
    await NotificationService.requestPermissionIfNeeded();
    // DailyNudgeService owns the streak/dream horizon; just rebuild it so
    // the new protocol immediately shows up in tonight's evening copy.
    await DailyNudgeService.reschedule();
    await NotificationService.scheduleRescanReminders(protocol);

    return protocol;
  }

  /// Resolve any pulldown / geometry to the canonical axis. Debloat OS
  /// has exactly one: every scan, every fix, every commit lands on the
  /// Debloat Protocol.
  static String resolveAxis({
    required String pulldown,
    required FaceGeometry geometry,
  }) {
    return _axisDebloat;
  }

  static bool _anyOf(String haystack, List<String> needles) {
    for (final n in needles) {
      if (haystack.contains(n)) return true;
    }
    return false;
  }

  /// Commit a single Fix from the report to the user's streak. If no
  /// protocol is active yet, auto-start one keyed to the fix's axis so
  /// the user has a streak surface to land on. Then append the fix as a
  /// daily task they can tick off. Returns the resulting Protocol.
  ///
  /// Idempotent on fix title — committing the same fix twice does not
  /// duplicate the row.
  static Future<Protocol?> commitFix({
    required Fix fix,
    required FaceGeometry geometry,
    required String pulldown,
  }) async {
    Protocol? p = await loadActive();
    if (p == null) {
      final scan = await LocalStoreService.latestScan();
      if (scan == null) return null;
      p = await startForScan(scan, pulldown: pulldown, geometry: geometry);
    }
    final next = p.withAddedTask(_fixToTask(fix));
    if (!identical(next, p)) await save(next);
    return next;
  }

  /// Convert a Fix card from the report into a DailyTask the user can
  /// tick off in the protocol screen. Picks a time band + category from
  /// the prose so the task lands in the right section of the schedule.
  static DailyTask _fixToTask(Fix fix) {
    final t = '${fix.action.toLowerCase()} ${fix.timeline.toLowerCase()}';
    TimeBand band = TimeBand.ongoing;
    if (_anyOf(t, ['morning', 'wake', 'breakfast'])) {
      band = TimeBand.am;
    } else if (_anyOf(t, ['midday', 'lunch', 'noon'])) {
      band = TimeBand.midday;
    } else if (_anyOf(t, ['evening', 'after work', 'dinner'])) {
      band = TimeBand.pm;
    } else if (_anyOf(t, ['bed', 'night', 'sleep'])) {
      band = TimeBand.night;
    }
    TaskCategory cat = TaskCategory.habit;
    final h = '${fix.title.toLowerCase()} ${fix.action.toLowerCase()}';
    if (_anyOf(h, ['skin', 'tret', 'cera', 'serum', 'moistur', 'spf',
                   'acne', 'cleanse'])) {
      cat = TaskCategory.skin;
    } else if (_anyOf(h, ['gum', 'chew', 'mew', 'masseter', 'jaw',
                          'press', 'lift'])) {
      cat = TaskCategory.exercise;
    } else if (_anyOf(h, ['protein', 'creatine', 'cut ', 'body fat',
                          'sodium', 'meal'])) {
      cat = TaskCategory.nutrition;
    } else if (_anyOf(h, ['hair', 'barber', 'beard', 'brow', 'lash',
                          'shave', 'trim'])) {
      cat = TaskCategory.grooming;
    }
    return DailyTask(
      title: fix.title,
      detail: fix.action,
      duration: fix.timeline.isNotEmpty ? fix.timeline : null,
      category: cat,
      timeBand: band,
    );
  }

  /// Every axis resolves to the one template Debloat OS ships.
  static _Template _templateFor(String axis) => _debloat;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Content library — THE Debloat Protocol. Time-banded daily tasks.
// ═══════════════════════════════════════════════════════════════════════════

const _debloat = _Template(
  title: 'The Debloat Protocol',
  summary: 'Water retention reads as softness, weakness, and age. '
           'Vasoconstriction + lymph + sodium audit drops the whole '
           'face one visual grade in two weeks.',
  dailyTasks: [
    // ── MORNING ──
    DailyTask(
      title: 'Ice-water face dunk — 30 s',
      detail: 'Bowl + ice + water, face to the hairline. Vasoconstriction '
              'drops overnight fluid. The 30 seconds that set the day.',
      duration: '30 s', category: TaskCategory.skin,
      timeBand: TimeBand.am),
    DailyTask(
      title: 'Gua sha — lymph drain',
      detail: 'Facial oil, stone. Upward + outward strokes: jaw → ear, '
              'cheek → temple, brow → hairline.',
      duration: '5 min', category: TaskCategory.skin,
      timeBand: TimeBand.am),
    // ── MIDDAY ──
    DailyTask(
      title: 'Sodium audit — under 2 g/day',
      detail: 'Restaurants, sauces, bread hide 80 % of it. Read labels '
              'for 14 days.',
      duration: 'all day', category: TaskCategory.nutrition,
      timeBand: TimeBand.midday),
    DailyTask(
      title: 'Hydrate — 3 L water',
      detail: 'Counter-intuitive: dehydration drives retention. 3 L signals '
              'the body to flush.',
      duration: 'all day', category: TaskCategory.nutrition,
      timeBand: TimeBand.midday),
    // ── EVENING ──
    DailyTask(
      title: 'Cold shower — 2 min finish',
      detail: 'Last 2 min cold. Whole-body vasoconstriction, inflammation '
              'drops, tonic skin shift.',
      duration: '2 min', category: TaskCategory.habit,
      timeBand: TimeBand.pm),
    DailyTask(
      title: 'Cut alcohol + dairy — 14 days',
      detail: 'Both inflammatory for most. Drop for two weeks, rescan, '
              'reintroduce one at a time.',
      duration: '14 days', category: TaskCategory.nutrition,
      timeBand: TimeBand.pm),
    // ── NIGHT ──
    DailyTask(
      title: 'Back-sleep, head elevated 15°',
      detail: 'Small wedge under the pillow. Face drains into the neck '
              'instead of pooling in cheeks and under-eyes.',
      duration: 'all night', category: TaskCategory.habit,
      timeBand: TimeBand.night),
    DailyTask(
      title: 'No late-night salt',
      detail: 'Last meal low-sodium. Your morning face starts at dinner.',
      duration: 'all night', category: TaskCategory.nutrition,
      timeBand: TimeBand.night),
    // ── ALL DAY ──
    DailyTask(
      title: 'Nose-breathing only',
      detail: 'Mouth-breathing pools fluid in the lower face. Lips sealed, '
              'breathe through the nose.',
      duration: 'all day', category: TaskCategory.habit,
      timeBand: TimeBand.ongoing),
    DailyTask(
      title: 'Walk 10k steps',
      detail: 'Circulation and lymph are pumped by movement. Sitting all '
              'day puffs the face.',
      duration: 'all day', category: TaskCategory.habit,
      timeBand: TimeBand.ongoing),
  ],
  donts: [
    'Salty restaurant meals + sauces',
    'Late-night sodium or alcohol',
    'Side-sleep face-down',
    'Skip water for coffee',
    'Stress + caffeine binges',
  ],
  successMetrics: [
    'Visibly sharper cheekbones',
    'Less morning puff',
    'Tighter jaw outline',
    'Whole face one grade sharper',
  ],
);

// ═══════════════════════════════════════════════════════════════════════════
//  Template scaffolding
// ═══════════════════════════════════════════════════════════════════════════

class _Template {
  final String title;
  final String summary;
  final List<DailyTask> dailyTasks;
  /// v283 — what to AVOID. Empty for legacy axes (Hunter Eyes,
  /// Symmetry, Chin, Posture, Foundations) that pre-date the spec.
  final List<String> donts;
  /// v283 — what success looks like at day 60. Empty for legacy.
  final List<String> successMetrics;
  List<ProtocolMilestone> get milestones => const [
    ProtocolMilestone(day: 7,  title: 'Week 1',    action: 'First photo log entry. No rescan — you\'re still warming up.'),
    ProtocolMilestone(day: 14, title: 'Check-in',  action: 'Re-scan. Compare to baseline. Small deltas expected.'),
    ProtocolMilestone(day: 30, title: 'Midpoint',  action: 'Re-scan. Adjust the axis if one has stalled.'),
    ProtocolMilestone(day: 60, title: 'Completion', action: 'Final scan. Before / after reveal.'),
  ];
  const _Template({
    required this.title, required this.summary, required this.dailyTasks,
    this.donts = const [],
    this.successMetrics = const [],
  });
}


