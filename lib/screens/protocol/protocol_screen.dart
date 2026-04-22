import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../models/protocol.dart';
import '../../services/protocol_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

class ProtocolScreen extends StatefulWidget {
  const ProtocolScreen({super.key});
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

  Future<void> _load() async {
    final p = await ProtocolService.loadActive();
    if (!mounted) return;
    setState(() { _p = p; _loading = false; });
  }

  Future<void> _markTodayComplete() async {
    if (_p == null) return;
    HapticFeedback.mediumImpact();
    final updated = await ProtocolService.markDayComplete(_p!, _p!.currentDay);
    if (!mounted) return;
    setState(() => _p = updated);
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
          Text('Your advisor will recommend one after the next scan — '
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

            // Title block
            Text('PROTOCOL · DAY ${p.currentDay} / ${p.lengthDays}',
              style: AppTypography.label.copyWith(
                color: AppColors.textTertiary, letterSpacing: 2.8, fontSize: 9)),
            const SizedBox(height: 6),
            Text(p.title,
              style: AppTypography.h1.copyWith(fontSize: 36, letterSpacing: -1.0)),
            const SizedBox(height: 4),
            Text('Targeting ${p.targetAxis.toLowerCase()}.',
              style: AppTypography.h1Italic.copyWith(
                fontSize: 15, color: AppColors.textSecondary)),

            const SizedBox(height: Sp.xl),

            // Progress
            _ProgressBlock(protocol: p)
              .animate().fadeIn(duration: 400.ms),

            const SizedBox(height: Sp.xl),

            Text('TODAY',
              style: AppTypography.label.copyWith(
                color: AppColors.textPrimary, letterSpacing: 2.5, fontSize: 10)),
            const SizedBox(height: Sp.sm),
            for (var i = 0; i < p.dailyTasks.length; i++) ...[
              _TaskCard(task: p.dailyTasks[i], delay: 160 + i * 80),
              const SizedBox(height: Sp.sm),
            ],

            const SizedBox(height: Sp.xl),

            if (p.milestones.isNotEmpty) ...[
              Text('MILESTONES',
                style: AppTypography.label.copyWith(
                  color: AppColors.textPrimary, letterSpacing: 2.5, fontSize: 10)),
              const SizedBox(height: Sp.sm),
              for (final m in p.milestones)
                _MilestoneRow(milestone: m, currentDay: p.currentDay),
            ],

            const SizedBox(height: Sp.xl),
            Text(p.summary,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary, fontSize: 12.5, height: 1.6,
                fontStyle: FontStyle.italic)),
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

          // Per-day dots — shows completed days as filled, current as pulsing
          Wrap(
            spacing: 4, runSpacing: 4,
            children: [
              for (var d = 1; d <= protocol.lengthDays; d++)
                _DayDot(
                  day: d,
                  isDone: protocol.completedDays.contains(d),
                  isCurrent: d == protocol.currentDay,
                  isPast: d < protocol.currentDay,
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
  final bool isDone, isCurrent, isPast;
  const _DayDot({
    required this.day, required this.isDone,
    required this.isCurrent, required this.isPast,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10, height: 10,
      decoration: BoxDecoration(
        color: isDone
            ? AppColors.red
            : isCurrent
                ? Colors.transparent
                : isPast
                    ? AppColors.signalRed.withValues(alpha: 0.3)
                    : AppColors.surface3,
        shape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(2),
        border: isCurrent
            ? Border.all(color: AppColors.red, width: 1.2)
            : null,
        boxShadow: isDone ? [
          BoxShadow(
            color: AppColors.divider,
            blurRadius: 4),
        ] : null,
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final DailyTask task;
  final int delay;
  const _TaskCard({required this.task, required this.delay});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36, margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: _catColor(task.category).withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: _catColor(task.category).withValues(alpha: 0.5), width: 0.8),
            ),
            child: Icon(_catIcon(task.category),
              size: 15, color: _catColor(task.category)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(task.title,
                        style: AppTypography.h3.copyWith(fontSize: 14.5)),
                    ),
                    if (task.duration != null)
                      Text(task.duration!,
                        style: AppTypography.label.copyWith(
                          color: _catColor(task.category),
                          fontSize: 9, letterSpacing: 1.8)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(task.detail,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary, fontSize: 12.5, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(
      delay: Duration(milliseconds: delay), duration: 350.ms);
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

  IconData _catIcon(TaskCategory c) {
    switch (c) {
      case TaskCategory.habit:     return Icons.all_inclusive;
      case TaskCategory.exercise:  return Icons.fitness_center;
      case TaskCategory.skin:      return Icons.water_drop_outlined;
      case TaskCategory.nutrition: return Icons.restaurant;
      case TaskCategory.grooming:  return Icons.content_cut;
    }
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
