import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/feature_analysis_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// The addictive part of the report. Each feature is a card with:
///  - Status dot (green/amber/red) + status label ("Standout", "Hidden")
///  - One-line vanity-tuned story that cites the measurement
///  - Specific fix + expected +point lift
///  - Per-feature "See it on my face" tap that fires tryon
///
/// Designed to feel like a diagnostic read-out from a private clinic, not
/// a spreadsheet. Status colours hit the eye before the text does.
class FeatureGrid extends StatelessWidget {
  final List<FeatureRead> reads;
  final void Function(FeatureRead)? onSeeIt;

  const FeatureGrid({super.key, required this.reads, this.onSeeIt});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('YOUR FACE · FEATURE BY FEATURE',
              style: AppTypography.label.copyWith(
                color: AppColors.textTertiary, letterSpacing: 2.8, fontSize: 9)),
            const Spacer(),
            Container(
              width: 4, height: 4,
              decoration: const BoxDecoration(
                color: AppColors.textTertiary, shape: BoxShape.circle),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('The read, ranked by leverage.',
          style: AppTypography.h1Italic.copyWith(
            fontSize: 15, color: AppColors.textSecondary)),
        const SizedBox(height: Sp.md),
        for (var i = 0; i < reads.length; i++) ...[
          _FeatureCard(
            read:   reads[i],
            delay:  Duration(milliseconds: 80 * i),
            onSeeIt: onSeeIt == null ? null : () => onSeeIt!(reads[i]),
          ),
          if (i != reads.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final FeatureRead read;
  final Duration delay;
  final VoidCallback? onSeeIt;
  const _FeatureCard({required this.read, required this.delay, this.onSeeIt});

  @override
  Widget build(BuildContext context) {
    final color = switch (read.status) {
      FeatureStatus.strong  => AppColors.signalGreen,
      FeatureStatus.neutral => AppColors.signalAmber,
      FeatureStatus.weak    => AppColors.signalRed,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(
          color: color.withValues(alpha: 0.35), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.05),
            blurRadius: 18,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: icon dot + title + status pill
          Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: color, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                    color: color.withValues(alpha: 0.55), blurRadius: 5)],
                ),
              ),
              const SizedBox(width: 10),
              Text(read.title,
                style: AppTypography.label.copyWith(
                  color: AppColors.textPrimary,
                  letterSpacing: 2.6, fontSize: 11,
                  fontWeight: FontWeight.w800)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: color.withValues(alpha: 0.55), width: 0.7),
                ),
                child: Text(read.statusLabel.toUpperCase(),
                  style: AppTypography.label.copyWith(
                    color: color, letterSpacing: 2.0, fontSize: 9,
                    fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Story
          Text(read.story,
            style: AppTypography.body.copyWith(
              color: AppColors.textPrimary, fontSize: 13.5, height: 1.5)),

          const SizedBox(height: 10),
          Container(height: 1, color: AppColors.divider),
          const SizedBox(height: 10),

          // Fix block
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('THE EXIT',
                      style: AppTypography.label.copyWith(
                        color: AppColors.textTertiary,
                        letterSpacing: 2.2, fontSize: 8.5,
                        fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(read.fix,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12.5, height: 1.5)),
                  ],
                ),
              ),
              if (read.pointLift > 0) ...[
                const SizedBox(width: 12),
                // Unboxed — only the NUMBER pops in red. Pill removed so
                // the page stops reading as alert-heavy.
                Column(
                  children: [
                    Text('+${read.pointLift}',
                      style: AppTypography.measurement.copyWith(
                        color: AppColors.red, fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        fontStyle: FontStyle.italic)),
                    Text('POINTS',
                      style: AppTypography.label.copyWith(
                        color: AppColors.textTertiary, fontSize: 7.5,
                        letterSpacing: 1.6)),
                  ],
                ),
              ],
            ],
          ),

          // "See it on my face" CTA removed per user feedback (too many
          // generate-image buttons in the Advanced panel). The hero
          // "GENERATE IMAGE" CTAs on the three main fix cards on the
          // primary report screen remain — those are the product moment.
          // The Advanced panel is now advice-only, no render buttons.
        ],
      ),
    ).animate()
      .fadeIn(delay: delay, duration: 350.ms)
      .slideX(begin: -0.02, end: 0, delay: delay, duration: 350.ms,
          curve: Curves.easeOut);
  }
}
