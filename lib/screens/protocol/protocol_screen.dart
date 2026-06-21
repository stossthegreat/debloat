import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../models/protocol.dart';
import '../../models/scan_record.dart';
import '../../services/local_store_service.dart';
import '../../services/protocol_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

class ProtocolScreen extends StatefulWidget {
  /// Optional axis to start a brand-new protocol on if none is active
  /// when the screen opens. Pass the pulldown string ("Skin", "Jaw
  /// definition", "Hair", "Puffiness", ...) and ProtocolService picks
  /// the matching template. Without this the screen falls back to the
  /// latest scan\'s pulldown to derive an axis, or — if that also
  /// fails — the Foundations axis (safe default) so the user never
  /// lands on "No active protocol."
  final String? startPulldown;
  const ProtocolScreen({super.key, this.startPulldown});
  @override
  State<ProtocolScreen> createState() => _ProtocolScreenState();
}

class _ProtocolScreenState extends State<ProtocolScreen> {
  Protocol? _p;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Resolve / auto-start the active protocol.
  /// Bro: "all these protocols you created none of them are
  /// commitable. Need to be able to commit them all." Previous
  /// behaviour: if ANY protocol was active, tapping a different
  /// aspect tile (SKIN / JAW / DEBLOAT / HAIR) just showed the
  /// existing active one instead of starting the new one. Now,
  /// when [startPulldown] is passed AND it maps to a different
  /// axis than the currently-active protocol, we silently end
  /// the old and start the requested one. The user\'s tap on
  /// the new tile IS the commit.
  /// Multi-protocol resolver. The user can have SKIN + JAW + DEBLOAT
  /// + HAIR all running in parallel — each one lives in its own
  /// per-axis slot. This screen always shows the SPECIFIC axis the
  /// user tapped (via startPulldown), never some other active run.
  Future<void> _load() async {
    Protocol? p;

    // Resolve the requested axis from the pulldown string if the
    // user came in via an aspect tile.
    String? requestedAxis;
    ScanRecord? scan;
    if (widget.startPulldown != null &&
        widget.startPulldown!.trim().isNotEmpty) {
      try {
        scan = await LocalStoreService.latestScan();
        if (scan != null) {
          requestedAxis = ProtocolService.resolveAxis(
            pulldown: widget.startPulldown!,
            geometry: scan.geometry,
          );
        }
      } catch (_) {/* fall through */}
    }

    if (requestedAxis != null) {
      // Specific axis requested → load THAT axis. If it doesn\'t
      // exist yet, start it without touching any other active run.
      p = await ProtocolService.loadActiveFor(requestedAxis);
      if (p == null && scan != null) {
        try {
          p = await ProtocolService.startForScan(
            scan,
            pulldown: widget.startPulldown!,
            geometry: scan.geometry,
          );
        } catch (_) {/* fall through */}
      }
    } else {
      // No specific axis (e.g. opened from the Looks tab\'s active
      // tile via the masthead protocol icon). Fall back to whatever
      // active protocol exists, or auto-start Foundations.
      p = await ProtocolService.loadActive();
      if (p == null) {
        try {
          scan ??= await LocalStoreService.latestScan();
          if (scan != null) {
            p = await ProtocolService.startForScan(
              scan,
              pulldown: 'Foundations',
              geometry: scan.geometry,
            );
          }
        } catch (_) {/* fall through to empty state */}
      }
    }

    if (!mounted) return;
    setState(() { _p = p; _loading = false; });
  }

  Future<void> _markTodayComplete() async {
    if (_p == null) return;
    HapticFeedback.mediumImpact();
    final prevStreak = _p!.effectiveStreak;
    final dayJustCompleted = _p!.currentDay;
    final updated = await ProtocolService.markDayComplete(_p!, dayJustCompleted);
    if (!mounted) return;
    setState(() => _p = updated);

    // Milestone celebration — day 7, 14, 30, 60. Big haptic pulse + modal.
    // Feels like a reward for showing up, not a ping when they didn't.
    if (_isMilestone(dayJustCompleted)) {
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 200));
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      await _showMilestoneCelebration(
        day: dayJustCompleted,
        streak: updated.effectiveStreak,
      );
    } else if (updated.effectiveStreak > prevStreak &&
               (updated.effectiveStreak == 3 ||
                updated.effectiveStreak == 10 ||
                updated.effectiveStreak == 21)) {
      // Small streak-number celebrations — the "3-day rule" sticks a habit,
      // 10 is a psychological threshold, 21 is the old "habit complete"
      // number. Quick toast-style haptic, no modal.
      HapticFeedback.heavyImpact();
    }
  }

  bool _isMilestone(int day) => day == 7 || day == 14 || day == 30 || day == 60;

  Future<void> _showMilestoneCelebration({
    required int day, required int streak,
  }) async {
    final (title, body, action) = _milestoneCopy(day);
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.86),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(Sp.lg),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(Rd.xl),
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.5), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: AppColors.red.withValues(alpha: 0.25),
                blurRadius: 28, spreadRadius: 1),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DAY $day · CHECKPOINT',
                style: AppTypography.label.copyWith(
                  color: AppColors.red,
                  letterSpacing: 3.0, fontSize: 10,
                  fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(title,
                style: AppTypography.h1.copyWith(
                  fontSize: 30, letterSpacing: -0.8, height: 1.1)),
              const SizedBox(height: 10),
              Text(body,
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 14, height: 1.55)),
              const SizedBox(height: Sp.md),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.red.withValues(alpha: 0.4), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_fire_department,
                      size: 14, color: AppColors.red),
                    const SizedBox(width: 4),
                    Text('$streak DAY STREAK',
                      style: AppTypography.label.copyWith(
                        color: AppColors.red,
                        letterSpacing: 2.0, fontSize: 10,
                        fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const SizedBox(height: Sp.lg),
              SizedBox(
                width: double.infinity, height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: AppColors.base,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Rd.lg)),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(action,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14, letterSpacing: 0.4)),
                ),
              ),
            ],
          ),
        ).animate().scale(
          begin: const Offset(0.86, 0.86), end: const Offset(1, 1),
          duration: 380.ms, curve: Curves.easeOutBack)
          .fadeIn(duration: 280.ms),
      ),
    );
  }

  /// Copy scales with the milestone. Day 7 is habit-formed. Day 14 is the
  /// first rescan moment. Day 30 is mid-protocol. Day 60 is completion.
  (String title, String body, String action) _milestoneCopy(int day) {
    switch (day) {
      case 7:
        return (
          'One week in.',
          'Seven days of showing up. The habit is starting to stick — most '
          'people quit before this. Keep going.',
          'Keep the run',
        );
      case 14:
        return (
          'Rescan day.',
          'Two weeks. Take a new scan today and compare to baseline — even '
          'small deltas mean the protocol is working. This is the first '
          'proof moment.',
          'Got it',
        );
      case 30:
        return (
          'Midpoint.',
          'Thirty days. If an axis has stalled, The Mirror can switch the '
          'focus — tap the protocol menu to review. Halfway to the full '
          'before / after.',
          'Midpoint logged',
        );
      case 60:
        return (
          'Protocol complete.',
          'Sixty days. Take your final scan and compare side-by-side with '
          'day one. Share the before / after if you want — this is the '
          'receipt.',
          'Final rescan',
        );
      default:
        return ('Checkpoint', 'Day $day logged.', 'Continue');
    }
  }

  Future<void> _endProtocol() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface1,
        title: Text('End protocol?',
          style: AppTypography.h3.copyWith(color: AppColors.textPrimary)),
        content: Text('You\'ll lose all check-in history for this program.',
          style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
              style: TextStyle(color: AppColors.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(context, true),
            child: Text('End',
              style: TextStyle(color: AppColors.signalRed))),
        ],
      ),
    );
    if (confirm != true) return;
    await ProtocolService.save(null);
    if (!mounted) return;
    setState(() => _p = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(
                color: AppColors.red, strokeWidth: 2))
            : _p == null ? _noProtocol() : _activeProtocol(_p!),
      ),
    );
  }

  Widget _noProtocol() {
    return Padding(
      padding: const EdgeInsets.all(Sp.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome,
            size: 42, color: AppColors.divider),
          const SizedBox(height: Sp.md),
          Text('No active protocol.',
            style: AppTypography.h1.copyWith(fontSize: 26)),
          const SizedBox(height: 6),
          Text('The Mirror will recommend one after the next scan — '
               'tuned to your pulldown axis.',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: Sp.xl),
          TextButton(
            onPressed: () => context.pop(),
            child: Text('Back',
              style: AppTypography.label.copyWith(
                color: AppColors.textSecondary, letterSpacing: 2.0)),
          ),
        ],
      ),
    );
  }

  Widget _activeProtocol(Protocol p) {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 120),
          children: [
            // Header with close
            Row(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => context.pop(),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.surface1, shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.divider, width: 0.8),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                        size: 14, color: AppColors.textSecondary),
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.more_horiz, color: AppColors.textTertiary),
                  onPressed: _endProtocol,
                ),
              ],
            ),

            const SizedBox(height: Sp.md),

            // v283 — hero block: program label, title, goal in one breathing
            // unit. Clean, white-text-on-black, no heavy borders.
            Text('PROTOCOL · DAY ${p.currentDay} / ${p.lengthDays}',
              style: AppTypography.label.copyWith(
                color: AppColors.red, letterSpacing: 2.8, fontSize: 9,
                fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(p.title,
              style: AppTypography.h1.copyWith(
                fontSize: 38, letterSpacing: -1.2, height: 1.05)),
            const SizedBox(height: 6),
            Text(p.summary,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
                fontSize: 14, height: 1.55)),

            const SizedBox(height: Sp.lg),

            // Progress
            _ProgressBlock(protocol: p)
              .animate().fadeIn(duration: 400.ms),

            const SizedBox(height: Sp.md),

            // Streak strip — flame + current + longest + freezes available
            _StreakStrip(protocol: p)
              .animate().fadeIn(delay: 120.ms, duration: 400.ms),

            const SizedBox(height: Sp.xl),

            // v283 — DOs section header. Strong, clean, no flame icons.
            _SectionTitle(label: 'DO', accent: AppColors.signalGreen),
            const SizedBox(height: Sp.sm),

            // Group tasks by time-of-day so the daily flow reads as a schedule
            // (morning → midday → evening → night → all-day habits) rather
            // than a flat checklist. Sections render only when they have
            // tasks, so protocols with a thinner band just skip it.
            for (final band in const [
              TimeBand.am, TimeBand.midday, TimeBand.pm,
              TimeBand.night, TimeBand.ongoing,
            ])
              if (p.dailyTasks.any((t) => t.timeBand == band)) ...[
                const SizedBox(height: Sp.md),
                _TimeBandHeader(band: band),
                const SizedBox(height: 10),
                for (var i = 0; i < p.dailyTasks.length; i++)
                  if (p.dailyTasks[i].timeBand == band) ...[
                    _TaskCard(task: p.dailyTasks[i], delay: 160 + i * 40),
                    const SizedBox(height: 8),
                  ],
              ],

            // v283 — DON'T block. Only renders when the template ships one.
            if (p.donts.isNotEmpty) ...[
              const SizedBox(height: Sp.xl),
              _SectionTitle(label: "DON'T", accent: AppColors.red),
              const SizedBox(height: Sp.sm),
              _DontBlock(items: p.donts)
                .animate().fadeIn(delay: 200.ms, duration: 400.ms),
            ],

            // v283 — Success Metrics block. The "you'll feel this at day 60"
            // payoff. Renders only when populated.
            if (p.successMetrics.isNotEmpty) ...[
              const SizedBox(height: Sp.xl),
              _SectionTitle(label: 'SUCCESS METRICS',
                accent: AppColors.signalGreen),
              const SizedBox(height: Sp.sm),
              _SuccessBlock(items: p.successMetrics)
                .animate().fadeIn(delay: 240.ms, duration: 400.ms),
            ],

            if (p.milestones.isNotEmpty) ...[
              const SizedBox(height: Sp.xl),
              _SectionTitle(label: 'MILESTONES', accent: AppColors.accent),
              const SizedBox(height: Sp.sm),
              for (final m in p.milestones)
                _MilestoneRow(milestone: m, currentDay: p.currentDay),
            ],

            const SizedBox(height: Sp.lg),
          ],
        ),

        // Sticky check-in button
        Positioned(
          left: Sp.lg, right: Sp.lg, bottom: Sp.md,
          child: SizedBox(
            width: double.infinity, height: 56,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: p.completedToday
                    ? AppColors.signalGreen.withValues(alpha: 0.25)
                    : AppColors.red,
                foregroundColor: p.completedToday
                    ? AppColors.signalGreen
                    : AppColors.base,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Rd.lg)),
                elevation: 0,
                side: p.completedToday
                    ? BorderSide(color: AppColors.signalGreen, width: 1)
                    : null,
              ),
              onPressed: p.completedToday ? null : _markTodayComplete,
              child: Text(
                p.completedToday
                    ? '✓ Today logged'
                    : 'Complete day ${p.currentDay}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.4)),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressBlock extends StatelessWidget {
  final Protocol protocol;
  const _ProgressBlock({required this.protocol});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${protocol.completedDays.length}',
                style: AppTypography.display.copyWith(
                  fontSize: 46, color: AppColors.red,
                  letterSpacing: -2.4, height: 1)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('/ ${protocol.lengthDays}',
                  style: AppTypography.label.copyWith(
                    color: AppColors.textTertiary, fontSize: 11)),
              ),
              const Spacer(),
              Text('${(protocol.progress * 100).toStringAsFixed(0)}%',
                style: AppTypography.measurement.copyWith(
                  color: AppColors.red, fontSize: 14,
                  fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 2),
          Text('DAYS LOGGED',
            style: AppTypography.label.copyWith(
              color: AppColors.textTertiary, letterSpacing: 2.4, fontSize: 8.5)),
          const SizedBox(height: Sp.md),

          // Per-day dots — completed (red) / frozen (accent indigo) / current
          // (red outline) / past-not-done (faded red) / future (surface).
          Wrap(
            spacing: 4, runSpacing: 4,
            children: [
              for (var d = 1; d <= protocol.lengthDays; d++)
                _DayDot(
                  day: d,
                  isDone:    protocol.completedDays.contains(d),
                  isCurrent: d == protocol.currentDay,
                  isPast:    d <  protocol.currentDay,
                  isFrozen:  protocol.freezeDays.contains(d),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  final int day;
  final bool isDone, isCurrent, isPast, isFrozen;
  const _DayDot({
    required this.day, required this.isDone,
    required this.isCurrent, required this.isPast,
    this.isFrozen = false,
  });

  @override
  Widget build(BuildContext context) {
    // Frozen takes priority over past-not-done — the user saved that day
    // with a freeze, so don't render it as a miss.
    final color = isDone
        ? AppColors.red
        : isFrozen
            ? AppColors.accent
            : isCurrent
                ? Colors.transparent
                : isPast
                    ? AppColors.signalRed.withValues(alpha: 0.3)
                    : AppColors.surface3;

    return Container(
      width: 10, height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(2),
        border: isCurrent
            ? Border.all(color: AppColors.red, width: 1.2)
            : null,
        boxShadow: isDone
            ? [const BoxShadow(color: AppColors.divider, blurRadius: 4)]
            : isFrozen
                ? [BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.4),
                    blurRadius: 4)]
                : null,
      ),
    );
  }
}

/// v283 — clean DO card. Thin coloured left-bar replaces the heavy circle
/// icon so the type-set reads first. Elevated surface (not surface1) keeps
/// the card lighter than the page background so the schedule feels lifted,
/// not dingy.
class _TaskCard extends StatelessWidget {
  final DailyTask task;
  final int delay;
  const _TaskCard({required this.task, required this.delay});

  @override
  Widget build(BuildContext context) {
    final color = _catColor(task.category);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(Rd.lg),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left accent bar — colour codes the category without an icon
            // taking up half the card.
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(Rd.lg),
                  bottomLeft: Radius.circular(Rd.lg),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(task.title,
                            style: AppTypography.h3.copyWith(
                              fontSize: 14.5,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700)),
                        ),
                        if (task.duration != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(task.duration!.toUpperCase(),
                              style: AppTypography.label.copyWith(
                                color: color, fontSize: 8.5,
                                letterSpacing: 1.4,
                                fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(task.detail,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12.5, height: 1.45)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(
      delay: Duration(milliseconds: delay), duration: 320.ms);
  }

  Color _catColor(TaskCategory c) {
    switch (c) {
      case TaskCategory.habit:     return AppColors.red;
      case TaskCategory.exercise:  return AppColors.accent;
      case TaskCategory.skin:      return AppColors.measure;
      case TaskCategory.nutrition: return AppColors.signalGreen;
      case TaskCategory.grooming:  return AppColors.signalAmber;
    }
  }
}

/// v283 — section heading with a coloured caps label. Used for DO / DON'T
/// / SUCCESS METRICS / MILESTONES blocks so the page reads as a structured
/// brief, not a flat checklist.
class _SectionTitle extends StatelessWidget {
  final String label;
  final Color accent;
  const _SectionTitle({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 14, height: 2,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(1)),
        ),
        const SizedBox(width: 10),
        Text(label,
          style: AppTypography.label.copyWith(
            color: accent, letterSpacing: 3.2, fontSize: 10.5,
            fontWeight: FontWeight.w800)),
      ],
    );
  }
}

/// v283 — DON'T block. Single elevated card with red × markers. Frames
/// the rules of the game so the user sees what to avoid alongside the
/// daily DOs.
class _DontBlock extends StatelessWidget {
  final List<String> items;
  const _DontBlock({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(
          color: AppColors.red.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 18, height: 18, margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: AppColors.red.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close_rounded,
                    size: 12, color: AppColors.red),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(items[i],
                    style: AppTypography.body.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 14, height: 1.4,
                      fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// v283 — Success Metric block. Green check list. The "what success
/// looks like" anchor that gives the daily grind a visible outcome.
class _SuccessBlock extends StatelessWidget {
  final List<String> items;
  const _SuccessBlock({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(
          color: AppColors.signalGreen.withValues(alpha: 0.28), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 18, height: 18, margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: AppColors.signalGreen.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_rounded,
                    size: 12, color: AppColors.signalGreen),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(items[i],
                    style: AppTypography.body.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 14, height: 1.4,
                      fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Streak strip — the lock-in mechanic. Flame colour + copy follow the
// effective status so the user always knows whether they're live, at-risk,
// or broken.
class _StreakStrip extends StatelessWidget {
  final Protocol protocol;
  const _StreakStrip({required this.protocol});

  @override
  Widget build(BuildContext context) {
    final status  = protocol.streakStatus;
    final streak  = protocol.effectiveStreak;
    final (flame, label) = _state(status);

    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(color: flame.withValues(alpha: 0.32), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.local_fire_department,
            size: 34, color: flame),
          const SizedBox(width: Sp.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$streak',
                    style: AppTypography.display.copyWith(
                      fontSize: 32, color: flame,
                      letterSpacing: -1.2, height: 1)),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text('DAY',
                      style: AppTypography.label.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 9, letterSpacing: 1.8)),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(label,
                style: AppTypography.label.copyWith(
                  color: flame, letterSpacing: 2.4, fontSize: 9)),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('LONGEST',
                style: AppTypography.label.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 8, letterSpacing: 1.8)),
              Text('${protocol.longestStreak}',
                style: AppTypography.measurement.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.ac_unit,
                    size: 9, color: AppColors.accent),
                  const SizedBox(width: 3),
                  Text('${protocol.freezesAvailable} FREEZE',
                    style: AppTypography.label.copyWith(
                      color: AppColors.accent,
                      fontSize: 8.5, letterSpacing: 1.6)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  (Color, String) _state(StreakStatus s) {
    switch (s) {
      case StreakStatus.fresh:
        return (AppColors.textTertiary, 'BEGIN THE RUN');
      case StreakStatus.live:
        return (AppColors.red, 'ON FIRE');
      case StreakStatus.atRisk:
        return (AppColors.signalAmber, 'LOG TODAY');
      case StreakStatus.broken:
        return (AppColors.textMuted, 'STREAK BROKEN');
    }
  }
}

// ── Time-band section header (morning / midday / evening / night / all-day) ─
class _TimeBandHeader extends StatelessWidget {
  final TimeBand band;
  const _TimeBandHeader({required this.band});

  String get _label {
    switch (band) {
      case TimeBand.am:      return 'MORNING';
      case TimeBand.midday:  return 'MIDDAY';
      case TimeBand.pm:      return 'EVENING';
      case TimeBand.night:   return 'NIGHT';
      case TimeBand.ongoing: return 'ALL DAY';
    }
  }

  IconData get _icon {
    switch (band) {
      case TimeBand.am:      return Icons.wb_twilight_outlined;
      case TimeBand.midday:  return Icons.wb_sunny_outlined;
      case TimeBand.pm:      return Icons.wb_iridescent_outlined;
      case TimeBand.night:   return Icons.nightlight_round;
      case TimeBand.ongoing: return Icons.all_inclusive;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(_icon, size: 12, color: AppColors.textTertiary),
        const SizedBox(width: 8),
        Text(_label,
          style: AppTypography.label.copyWith(
            color: AppColors.textTertiary,
            letterSpacing: 2.8, fontSize: 9)),
        const SizedBox(width: 10),
        Expanded(child: Container(
          height: 0.6, color: AppColors.divider)),
      ],
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  final ProtocolMilestone milestone;
  final int currentDay;
  const _MilestoneRow({required this.milestone, required this.currentDay});

  @override
  Widget build(BuildContext context) {
    final reached = currentDay >= milestone.day;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.md),
        border: Border.all(
          color: reached
              ? AppColors.divider
              : AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: reached
                  ? AppColors.divider
                  : AppColors.surface2,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('${milestone.day}',
                style: AppTypography.measurement.copyWith(
                  color: reached ? AppColors.red : AppColors.textTertiary,
                  fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(milestone.title,
                  style: AppTypography.label.copyWith(
                    color: reached ? AppColors.red : AppColors.textSecondary,
                    fontSize: 10, letterSpacing: 2.0)),
                Text(milestone.action,
                  style: AppTypography.bodySmall.copyWith(
                    fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
