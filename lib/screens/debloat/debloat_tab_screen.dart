import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/analytics_service.dart';
import '../../services/debloat_checklist_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/common/mirrorly_wordmark.dart';

/// THE DEBLOAT TAB — the daily system. Twelve evidence-anchored
/// protocols in three time blocks (MORNING FLUSH / INTAKE CONTROL /
/// NIGHT DRAIN), rendered as a checklist that resets every calendar
/// day. The progress ring at the top is the day's "system integrity"
/// readout; every tick feeds the same streak engine the Ascend tab
/// reads.
class DebloatTabScreen extends StatefulWidget {
  /// Day-streak count for the masthead flame chip.
  final int dayStreak;
  /// Called after any toggle so the parent hub can refresh streak /
  /// mission state without a tab switch.
  final Future<void> Function()? onChanged;
  const DebloatTabScreen({super.key, this.dayStreak = 0, this.onChanged});

  @override
  State<DebloatTabScreen> createState() => _DebloatTabScreenState();
}

class _DebloatTabScreenState extends State<DebloatTabScreen>
    with AutomaticKeepAliveClientMixin {
  Set<String> _done = {};
  bool _loading = true;
  /// The ymd the current done-set belongs to — re-checked on every
  /// build-adjacent load so the list visibly resets at midnight.
  int _loadedYmd = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final done = await DebloatChecklistService.loadToday();
    if (!mounted) return;
    setState(() {
      _done      = done;
      _loading   = false;
      _loadedYmd = DebloatChecklistService.todayYmd();
    });
  }

  Future<void> _toggle(String id) async {
    HapticFeedback.selectionClick();
    final done = await DebloatChecklistService.toggle(id);
    if (!mounted) return;
    setState(() => _done = done);
    // ignore: discarded_futures
    AnalyticsService.tabOpened('debloat_toggle_$id');
    // Let the hub re-read streak + mission state.
    // ignore: discarded_futures
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Midnight rollover — if the loaded day is stale, reload.
    if (!_loading && _loadedYmd != DebloatChecklistService.todayYmd()) {
      _loading = true;
      // ignore: discarded_futures
      _load();
    }
    final total = DebloatChecklistService.items.length;
    final done  = _done.length;
    final pct   = total == 0 ? 0.0 : done / total;

    return SafeArea(
      child: _loading
          ? const Center(
              child: SizedBox(
                width: 28, height: 28,
                child: CircularProgressIndicator(
                    color: AppColors.textSecondary, strokeWidth: 2),
              ))
          : RefreshIndicator(
              onRefresh: () async => _load(),
              color: AppColors.brand,
              backgroundColor: AppColors.surface1,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: Sp.xl),
                children: [
                  // ── Masthead ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                    child: Row(
                      children: [
                        const DebloatWordmark(fontSize: 34),
                        const Spacer(),
                        if (widget.dayStreak > 0) ...[
                          _StreakChip(days: widget.dayStreak),
                          const SizedBox(width: 8),
                        ],
                        _CircleIcon(
                          icon: Icons.tune,
                          onTap: () => context.push('/settings'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Text(
                      'The daily system. Run it every day.',
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 15, height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  const SizedBox(height: Sp.lg),

                  // ── System integrity ring ──
                  Center(
                    child: _SystemRing(pct: pct, done: done, total: total),
                  ).animate().fadeIn(duration: 400.ms),

                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      pct >= 1.0
                          ? 'SYSTEM COMPLETE — SEE IT TOMORROW MORNING'
                          : pct > 0
                              ? 'SYSTEM RUNNING'
                              : 'SYSTEM IDLE — START WITH THE DUNK',
                      style: AppTypography.label.copyWith(
                        color: pct >= 1.0
                            ? AppColors.signalGreen
                            : pct > 0
                                ? AppColors.brand
                                : AppColors.textTertiary,
                        fontSize: 9.5, letterSpacing: 2.6,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),

                  const SizedBox(height: Sp.md),

                  _Block(
                    label:  'MORNING FLUSH',
                    icon:   Icons.ac_unit_rounded,
                    items:  DebloatChecklistService.itemsFor(DebloatBlock.morning),
                    done:   _done,
                    onTap:  _toggle,
                  ),
                  _Block(
                    label:  'INTAKE CONTROL',
                    icon:   Icons.water_drop_outlined,
                    items:  DebloatChecklistService.itemsFor(DebloatBlock.day),
                    done:   _done,
                    onTap:  _toggle,
                  ),
                  _Block(
                    label:  'NIGHT DRAIN',
                    icon:   Icons.bedtime_outlined,
                    items:  DebloatChecklistService.itemsFor(DebloatBlock.night),
                    done:   _done,
                    onTap:  _toggle,
                  ),

                  const SizedBox(height: Sp.md),

                  // ── Footer line — the promise ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                    child: Text(
                      'Water retention clears in 24–72 hours once the cause '
                      'is gone. Run the system daily and the face you see in '
                      'the mirror is the drained one — every morning.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textTertiary, fontSize: 12,
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ── System ring — the day's integrity readout ───────────────────────────────
class _SystemRing extends StatelessWidget {
  final double pct;
  final int done;
  final int total;
  const _SystemRing({required this.pct, required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148, height: 148,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(148, 148),
            painter: _RingPainter(pct: pct),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$done/$total',
                style: GoogleFonts.spaceGrotesk(
                  color: AppColors.textPrimary,
                  fontSize: 34, height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.2,
                )),
              const SizedBox(height: 3),
              Text('TODAY',
                style: AppTypography.label.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 9, letterSpacing: 3.0,
                  fontWeight: FontWeight.w800,
                )),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double pct;
  _RingPainter({required this.pct});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 6;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..color = AppColors.surface3;
    canvas.drawCircle(c, r, track);
    if (pct <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: const [AppColors.brandDim, AppColors.brand],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2, 2 * math.pi * pct.clamp(0.0, 1.0), false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct;
}

// ── One time-block section ──────────────────────────────────────────────────
class _Block extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<DebloatItem> items;
  final Set<String> done;
  final ValueChanged<String> onTap;
  const _Block({
    required this.label,
    required this.icon,
    required this.items,
    required this.done,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final blockDone = items.where((i) => done.contains(i.id)).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.brand),
              const SizedBox(width: 7),
              Text(label,
                style: AppTypography.label.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 10.5, letterSpacing: 2.8,
                  fontWeight: FontWeight.w900,
                )),
              const Spacer(),
              Text('$blockDone/${items.length}',
                style: GoogleFonts.spaceGrotesk(
                  color: blockDone == items.length
                      ? AppColors.signalGreen
                      : AppColors.textTertiary,
                  fontSize: 12, fontWeight: FontWeight.w700,
                )),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(Rd.xl),
              border: Border.all(color: AppColors.divider, width: 0.8),
            ),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  _Row(
                    item:   items[i],
                    isDone: done.contains(items[i].id),
                    onTap:  () => onTap(items[i].id),
                  ),
                  if (i < items.length - 1)
                    const Divider(
                      height: 1, thickness: 0.6,
                      color: AppColors.divider,
                      indent: 54,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── One checklist row ───────────────────────────────────────────────────────
class _Row extends StatelessWidget {
  final DebloatItem item;
  final bool isDone;
  final VoidCallback onTap;
  const _Row({required this.item, required this.isDone, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Check square — brand-filled when done.
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: 26, height: 26,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: isDone ? AppColors.brand : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDone ? AppColors.brand : AppColors.surface3,
                    width: 1.4),
                  boxShadow: isDone
                      ? [BoxShadow(
                          color: AppColors.brand.withValues(alpha: 0.4),
                          blurRadius: 12)]
                      : null,
                ),
                child: isDone
                    ? const Icon(Icons.check_rounded,
                        size: 18, color: Color(0xFF03181C))
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                      style: GoogleFonts.inter(
                        color: isDone
                            ? AppColors.textTertiary
                            : AppColors.textPrimary,
                        fontSize: 14.5, height: 1.3,
                        fontWeight: FontWeight.w700,
                        decoration: isDone
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        decorationColor: AppColors.textTertiary,
                      )),
                    const SizedBox(height: 3),
                    Text(item.why,
                      style: AppTypography.bodySmall.copyWith(
                        color: isDone
                            ? AppColors.textMuted
                            : AppColors.textSecondary,
                        fontSize: 11.5, height: 1.45,
                      )),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Target chip.
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                      color: AppColors.surface3, width: 0.7),
                ),
                child: Text(item.metric,
                  style: GoogleFonts.spaceGrotesk(
                    color: isDone
                        ? AppColors.textMuted
                        : AppColors.brand,
                    fontSize: 10.5, height: 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Small chrome ────────────────────────────────────────────────────────────
class _StreakChip extends StatelessWidget {
  final int days;
  const _StreakChip({required this.days});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.brand,
        borderRadius: BorderRadius.circular(99),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.45),
            blurRadius: 14),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded,
              color: Color(0xFF03181C), size: 18),
          const SizedBox(width: 5),
          Text('$days',
            style: GoogleFonts.inter(
              color: const Color(0xFF03181C),
              fontSize: 14, height: 1,
              fontWeight: FontWeight.w900,
            )),
        ],
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        customBorder: const CircleBorder(),
        child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: AppColors.surface1,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.surface3, width: 0.6),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
