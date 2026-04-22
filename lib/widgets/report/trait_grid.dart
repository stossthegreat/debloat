import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/trait_builder_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Umax's secret sauce, done better. Four badges in a 2x2 grid — each a
/// single "HUNTER EYES · TOP 12% · +3.1° TILT" hit. Strengths lead for
/// ego protection (Alicke BTAE), pulldowns tail for honesty.
///
/// This is the viral screenshot moment Umax built a company on. Ours is
/// backed by REAL mesh measurements, not estimation.
class TraitGrid extends StatelessWidget {
  final List<Trait> traits;
  const TraitGrid({super.key, required this.traits});

  @override
  Widget build(BuildContext context) {
    final show = traits.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('YOUR TRAITS',
          style: AppTypography.label.copyWith(
            color: AppColors.textTertiary, letterSpacing: 3.0, fontSize: 10)),
        const SizedBox(height: 10),
        // 2×2 grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: show.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.35,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          itemBuilder: (_, i) => _TraitBadge(
            trait: show[i],
            delay: Duration(milliseconds: 80 * i),
          ),
        ),
      ],
    );
  }
}

class _TraitBadge extends StatelessWidget {
  final Trait trait;
  final Duration delay;
  const _TraitBadge({required this.trait, required this.delay});

  @override
  Widget build(BuildContext context) {
    final isStrength = trait.kind == TraitKind.strength;
    final color = isStrength ? AppColors.signalGreen : AppColors.signalRed;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.14),
            AppColors.surface1,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: 0.55), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.10),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(trait.emoji,
                style: const TextStyle(fontSize: 20)),
              const Spacer(),
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: color, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                    color: color.withValues(alpha: 0.6), blurRadius: 4)],
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(trait.name,
                style: AppTypography.labelBold.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 13, letterSpacing: 2.2,
                  fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(trait.detail,
                style: AppTypography.measurement.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 10, fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(trait.pct,
                  style: AppTypography.label.copyWith(
                    color: color, fontSize: 8.5, letterSpacing: 1.4,
                    fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ],
      ),
    ).animate()
      .fadeIn(delay: delay, duration: 380.ms)
      .slideY(begin: 0.06, end: 0, delay: delay, duration: 380.ms,
          curve: Curves.easeOut);
  }
}
