import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/debloat_report_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  AI VERDICT — GPT-vision read of what's puffing the face up.
// ═══════════════════════════════════════════════════════════════════════════
class AiVerdictCard extends StatelessWidget {
  final String holding;
  final String effect;
  final int projectedPoints;
  const AiVerdictCard({
    super.key,
    required this.holding,
    required this.effect,
    required this.projectedPoints,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(color: AppColors.surface3, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                color: AppColors.brand, size: 16),
              const SizedBox(width: 8),
              Text('AI VERDICT',
                style: AppTypography.label.copyWith(
                  color: AppColors.brand,
                  fontSize: 11, letterSpacing: 2.6,
                  fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 14),
          Text(holding,
            style: GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontSize: 17, height: 1.4, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(effect,
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 15, height: 1.45, fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
          Container(height: 1, color: AppColors.divider),
          const SizedBox(height: 14),
          Text('ESTIMATED IMPROVEMENT AFTER FULL PROTOCOL',
            style: AppTypography.label.copyWith(
              color: AppColors.textTertiary,
              fontSize: 9.5, letterSpacing: 1.6, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('+$projectedPoints',
                style: GoogleFonts.spaceGrotesk(
                  color: AppColors.signalGreen,
                  fontSize: 40, height: 1,
                  fontWeight: FontWeight.w900, letterSpacing: -1.5,
                  shadows: [Shadow(
                    color: AppColors.signalGreen.withValues(alpha: 0.4),
                    blurRadius: 18)])),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('Points',
                  style: GoogleFonts.inter(
                    color: AppColors.signalGreen,
                    fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  BIGGEST WIN — one card, rocket, the highest-leverage move.
// ═══════════════════════════════════════════════════════════════════════════
class BiggestWinCard extends StatelessWidget {
  const BiggestWinCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [
            AppColors.brand.withValues(alpha: 0.14),
            AppColors.surface1,
          ]),
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54, height: 54,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(15)),
                alignment: Alignment.center,
                child: const Text('🚀', style: TextStyle(fontSize: 28))
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .moveY(begin: 2, end: -3, duration: 1400.ms, curve: Curves.easeInOut),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('YOUR BIGGEST WIN',
                      style: AppTypography.label.copyWith(
                        color: AppColors.brand,
                        fontSize: 10.5, letterSpacing: 2.2,
                        fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text('Debloating',
                      style: GoogleFonts.spaceGrotesk(
                        color: AppColors.textPrimary,
                        fontSize: 26, height: 1,
                        fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('Reducing facial water retention will create the biggest '
              'visible improvement to your appearance.',
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 14.5, height: 1.45, fontWeight: FontWeight.w500)),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: AppColors.signalGreen, size: 18),
              const SizedBox(width: 6),
              Text('Expected improvement: ',
                style: GoogleFonts.inter(
                  color: AppColors.textTertiary,
                  fontSize: 13.5, fontWeight: FontWeight.w500)),
              Text('24–48 hours',
                style: GoogleFonts.inter(
                  color: AppColors.signalGreen,
                  fontSize: 13.5, fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  WHAT'S CAUSING IT — animated bars.
// ═══════════════════════════════════════════════════════════════════════════
class CausesCard extends StatelessWidget {
  final List<BloatCause> causes;
  const CausesCard({super.key, required this.causes});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(color: AppColors.surface3, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("WHAT'S CAUSING IT",
            style: AppTypography.label.copyWith(
              color: AppColors.brand,
              fontSize: 11, letterSpacing: 2.6, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          for (var i = 0; i < causes.length; i++) ...[
            _CauseBar(cause: causes[i], delayMs: 120 * i),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _CauseBar extends StatelessWidget {
  final BloatCause cause;
  final int delayMs;
  const _CauseBar({required this.cause, required this.delayMs});

  Color get _color {
    if (cause.pct >= 75) return AppColors.signalRed;
    if (cause.pct >= 55) return AppColors.signalAmber;
    return AppColors.signalGreen;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(cause.emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(cause.label,
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 14.5, fontWeight: FontWeight.w700)),
            ),
            Text('${cause.pct}%',
              style: GoogleFonts.spaceGrotesk(
                color: _color,
                fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: Stack(
            children: [
              Container(height: 8, color: AppColors.surface3),
              FractionallySizedBox(
                widthFactor: (cause.pct / 100).clamp(0.0, 1.0),
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: _color,
                    borderRadius: BorderRadius.circular(100)),
                ),
              ).animate().scaleX(
                begin: 0, end: 1, alignment: Alignment.centerLeft,
                duration: 700.ms, delay: delayMs.ms, curve: Curves.easeOutCubic),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  FASTEST WINS — checklist.
// ═══════════════════════════════════════════════════════════════════════════
class FastestWinsCard extends StatelessWidget {
  const FastestWinsCard({super.key});

  static const _wins = <String>[
    'Lower sodium tonight',
    'Increase water intake',
    'Morning cold exposure',
    'Sleep before 11pm',
    '15 minute walk after dinner',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(color: AppColors.surface3, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('YOUR FASTEST WINS',
            style: AppTypography.label.copyWith(
              color: AppColors.brand,
              fontSize: 11, letterSpacing: 2.6, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          for (var i = 0; i < _wins.length; i++) ...[
            Row(
              children: [
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.signalGreen.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: AppColors.signalGreen.withValues(alpha: 0.5), width: 1)),
                  alignment: Alignment.center,
                  child: const Icon(Icons.check_rounded,
                    color: AppColors.signalGreen, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(_wins[i],
                    style: GoogleFonts.inter(
                      color: AppColors.textPrimary,
                      fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ],
            ).animate().fadeIn(delay: (100 * i).ms, duration: 300.ms)
              .slideX(begin: 0.05, end: 0),
            if (i != _wins.length - 1) const SizedBox(height: 12),
          ],
          const SizedBox(height: 16),
          Container(height: 1, color: AppColors.divider),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.wb_twilight_rounded,
                color: AppColors.signalGreen, size: 18),
              const SizedBox(width: 8),
              Text('Estimated improvement: ',
                style: GoogleFonts.inter(
                  color: AppColors.textTertiary,
                  fontSize: 13.5, fontWeight: FontWeight.w500)),
              Flexible(
                child: Text('Visible tomorrow morning.',
                  style: GoogleFonts.inter(
                    color: AppColors.signalGreen,
                    fontSize: 13.5, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
