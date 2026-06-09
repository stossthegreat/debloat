import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/honest_rating_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// AI VERDICT — four-card analytical panel that sits under the
/// HeroCard on the report screen. Renders GPT-4o vision's candid
/// read of the user's photo across the four questions that actually
/// drive subscription value:
///
///   1. Biggest Strength   — what's working in his favour
///   2. Biggest Weakness   — what's dragging the score down
///   3. Fastest Win        — which protocols deliver the biggest lift
///   4. Potential          — current → projected, why it's realistic
///
/// Tapping the FASTEST WIN axis chips routes the user straight into
/// the corresponding aspect protocol on /protocol, so the verdict is
/// an action funnel, not just commentary.
class AiVerdictPanel extends StatelessWidget {
  final HonestVerdict verdict;
  const AiVerdictPanel({super.key, required this.verdict});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  color: AppColors.red, size: 14),
              const SizedBox(width: 6),
              Text('AI VERDICT',
                style: AppTypography.label.copyWith(
                  color: AppColors.red,
                  fontSize: 11, letterSpacing: 3.0,
                  fontWeight: FontWeight.w800,
                )),
              const SizedBox(width: 8),
              Text('honest read · on photo',
                style: AppTypography.label.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 10, letterSpacing: 1.6,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600,
                )),
            ],
          ),
        ),
        const SizedBox(height: Sp.md),

        if (verdict.biggestStrength.body.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
            child: _VerdictTile(
              eyebrow:   'YOUR BIGGEST STRENGTH',
              headline:  verdict.biggestStrength.headline,
              body:      verdict.biggestStrength.body,
              tint:      AppColors.signalGreen,
              icon:      Icons.bolt_rounded,
            ),
          ),
          const SizedBox(height: Sp.sm),
        ],

        if (verdict.biggestWeakness.body.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
            child: _VerdictTile(
              eyebrow:   'WHAT\'S HOLDING YOU BACK',
              headline:  verdict.biggestWeakness.headline,
              body:      verdict.biggestWeakness.body,
              tint:      AppColors.signalAmber,
              icon:      Icons.warning_rounded,
            ),
          ),
          const SizedBox(height: Sp.sm),
        ],

        if (verdict.fastestWin.axes.isNotEmpty ||
            verdict.fastestWin.body.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
            child: _FastestWinTile(win: verdict.fastestWin),
          ),
          const SizedBox(height: Sp.sm),
        ],

        if (verdict.potential.projected > verdict.potential.current) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
            child: _PotentialTile(p: verdict.potential),
          ),
        ],
      ],
    );
  }
}

class _VerdictTile extends StatelessWidget {
  final String eyebrow;
  final String headline;
  final String body;
  final Color  tint;
  final IconData icon;
  const _VerdictTile({
    required this.eyebrow,
    required this.headline,
    required this.body,
    required this.tint,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(
          color: tint.withValues(alpha: 0.42), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: tint, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(eyebrow,
                  style: AppTypography.label.copyWith(
                    color: tint,
                    fontSize: 10.5, letterSpacing: 2.4,
                    fontWeight: FontWeight.w800,
                  )),
              ),
            ],
          ),
          if (headline.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(headline,
              style: AppTypography.h1.copyWith(
                color: AppColors.textPrimary,
                fontSize: 18, height: 1.2,
                letterSpacing: -0.3,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w800,
              )),
          ],
          if (body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(body,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 13.5, height: 1.45,
                fontWeight: FontWeight.w500,
              )),
          ],
        ],
      ),
    );
  }
}

class _FastestWinTile extends StatelessWidget {
  final FastestWin win;
  const _FastestWinTile({required this.win});

  // Axis → display label + colour + protocol pulldown key (must match
  // ProtocolService.resolveAxis).
  static const Map<String, ({String label, Color color, String pulldown})> _axisMeta = {
    'skin':    (label: 'Skin',        color: AppColors.signalGreen,  pulldown: 'Skin'),
    'jaw':     (label: 'Jaw',         color: AppColors.red,           pulldown: 'Jaw definition'),
    'debloat': (label: 'Debloat',     color: AppColors.signalAmber,   pulldown: 'Puffiness'),
    'hair':    (label: 'Hair',        color: AppColors.measure,       pulldown: 'Hair'),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(
          color: AppColors.red.withValues(alpha: 0.55), width: 0.9),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withValues(alpha: 0.16),
            blurRadius: 24, offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rocket_launch_rounded,
                  color: AppColors.red, size: 14),
              const SizedBox(width: 6),
              Text('YOUR FASTEST WIN',
                style: AppTypography.label.copyWith(
                  color: AppColors.red,
                  fontSize: 10.5, letterSpacing: 2.4,
                  fontWeight: FontWeight.w800,
                )),
            ],
          ),
          if (win.headline.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(win.headline,
              style: AppTypography.h1.copyWith(
                color: AppColors.textPrimary,
                fontSize: 18, height: 1.2,
                letterSpacing: -0.3,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w800,
              )),
          ],
          if (win.body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(win.body,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 13.5, height: 1.45,
                fontWeight: FontWeight.w500,
              )),
          ],
          if (win.axes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: win.axes.map((axis) {
                final meta = _axisMeta[axis];
                if (meta == null) return const SizedBox.shrink();
                return _AxisChip(
                  label:    meta.label,
                  color:    meta.color,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.push('/protocol',
                        extra: {'pulldown': meta.pulldown});
                  },
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _AxisChip extends StatelessWidget {
  final String label;
  final Color  color;
  final VoidCallback onTap;
  const _AxisChip({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: color.withValues(alpha: 0.55), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label.toUpperCase(),
                style: AppTypography.label.copyWith(
                  color: color,
                  fontSize: 11, letterSpacing: 2.0,
                  fontWeight: FontWeight.w900,
                )),
              const SizedBox(width: 5),
              Icon(Icons.arrow_forward_rounded,
                  color: color, size: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _PotentialTile extends StatelessWidget {
  final Potential p;
  const _PotentialTile({required this.p});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up_rounded,
                  color: AppColors.accent, size: 14),
              const SizedBox(width: 6),
              Text('YOUR POTENTIAL',
                style: AppTypography.label.copyWith(
                  color: AppColors.accent,
                  fontSize: 10.5, letterSpacing: 2.4,
                  fontWeight: FontWeight.w800,
                )),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _stat('Current',   p.current,   AppColors.textSecondary),
              const SizedBox(width: 18),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Icon(Icons.arrow_forward_rounded,
                    color: AppColors.textTertiary, size: 18),
              ),
              const SizedBox(width: 18),
              _stat('Projected', p.projected, AppColors.accent),
              const Spacer(),
              _gainBadge(p.gain),
            ],
          ),
          if (p.body.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(p.body,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 13.5, height: 1.45,
                fontWeight: FontWeight.w500,
              )),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, int value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
          style: AppTypography.label.copyWith(
            color: AppColors.textTertiary,
            fontSize: 9.5, letterSpacing: 1.8,
            fontWeight: FontWeight.w800,
          )),
        const SizedBox(height: 2),
        Text('$value',
          style: GoogleFonts.playfairDisplay(
            color: color,
            fontSize: 32, height: 1.0,
            letterSpacing: -1.4,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w800,
          )),
      ],
    );
  }

  Widget _gainBadge(int gain) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Text('+$gain pts',
        style: AppTypography.label.copyWith(
          color: AppColors.accent,
          fontSize: 12, letterSpacing: 1.2,
          fontWeight: FontWeight.w800,
        )),
    );
  }
}
