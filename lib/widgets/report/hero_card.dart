import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// The hero moment on the report — the screenshot people post.
///
/// Structure (locked):
///   1.  CURRENT  →  PROJECTED   (huge, dominant, the "wait, I could go up?")
///   2.  Tagline                  (one sentence, sharp, emotional)
///   3.  Before / After           (full width, gold-framed)
///   4.  "X CHANGES. SAME FACE."  (centered)
///   5.  Three micro-proof lines  (top % strengths, diamond glyph)
///
/// Counter animates 0 → current → arrow → projected over ~2.2s. The arrow +
/// projected number are the dopamine — the user sees themselves go up before
/// they read a single word of the report.
class HeroCard extends StatefulWidget {
  final int currentScore;       // e.g. 57
  final int projectedScore;     // e.g. 74
  final String tagline;         // e.g. "You're hiding your structure."
  final Uint8List? beforeBytes;
  final String? afterUrl;
  final int correctionsCount;   // e.g. 3 → "3 CHANGES. SAME FACE."
  final List<String> microProofs; // 3 short uppercase lines

  const HeroCard({
    super.key,
    required this.currentScore,
    required this.projectedScore,
    required this.tagline,
    required this.beforeBytes,
    required this.afterUrl,
    required this.correctionsCount,
    required this.microProofs,
  });

  @override
  State<HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<HeroCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _counter;

  @override
  void initState() {
    super.initState();
    _counter = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
      ..forward();
  }

  @override
  void dispose() {
    _counter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final proofs = widget.microProofs.take(3).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, 32, Sp.lg, 26),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.3),
          radius: 1.2,
          colors: [
            AppColors.gold.withValues(alpha: 0.18),
            const Color(0xFF080808),
          ],
        ),
        borderRadius: BorderRadius.circular(Rd.xxl),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.4), width: 0.9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 1 · SCORE TRANSITION (the dominant message) ────────────────
          // Current animates up first, arrow + projected pop in after.
          _ScoreTransition(
            controller: _counter,
            currentScore: widget.currentScore,
            projectedScore: widget.projectedScore,
          ),

          const SizedBox(height: 12),
          // Tiny labels under each number.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 96, child: Text('CURRENT',
                textAlign: TextAlign.center,
                style: AppTypography.label.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 9, letterSpacing: 2.6,
                  fontWeight: FontWeight.w800))),
              const SizedBox(width: 40),
              SizedBox(width: 96, child: Text('PROJECTED',
                textAlign: TextAlign.center,
                style: AppTypography.label.copyWith(
                  color: AppColors.gold,
                  fontSize: 9, letterSpacing: 2.6,
                  fontWeight: FontWeight.w800))),
            ],
          ).animate().fadeIn(delay: 1500.ms, duration: 400.ms),

          const SizedBox(height: 20),

          // ── 2 · TAGLINE ──────────────────────────────────────────────
          // Italic serif, max 2 lines. Sharp + emotional, not marketing copy.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(widget.tagline,
              textAlign: TextAlign.center,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: AppTypography.h1Italic.copyWith(
                color: AppColors.textPrimary,
                fontSize: 22, height: 1.25, letterSpacing: -0.2,
              )),
          ).animate().fadeIn(delay: 1700.ms, duration: 500.ms)
            .slideY(begin: 0.2, end: 0,
              delay: 1700.ms, duration: 500.ms, curve: Curves.easeOut),

          const SizedBox(height: 22),

          // ── 3 · BEFORE / AFTER (full width inside the card) ─────────
          AspectRatio(
            aspectRatio: 4 / 3, // wide, both faces tall enough to read
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Rd.lg),
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.55), width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gold.withValues(alpha: 0.18),
                    blurRadius: 18, spreadRadius: 1),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Rd.lg),
                child: Row(
                  children: [
                    Expanded(child: _half(widget.beforeBytes, null)),
                    Container(width: 1.2, color: AppColors.gold),
                    Expanded(child: _half(null, widget.afterUrl)),
                  ],
                ),
              ),
            ),
          ).animate().fadeIn(delay: 1900.ms, duration: 500.ms),

          const SizedBox(height: 16),

          // ── 4 · "X CHANGES. SAME FACE." ──────────────────────────────
          Center(
            child: Text(
              '${widget.correctionsCount} CHANGES.  SAME FACE.',
              style: AppTypography.label.copyWith(
                color: AppColors.textPrimary,
                fontSize: 13, letterSpacing: 3.4,
                fontWeight: FontWeight.w900,
              ),
            ),
          ).animate().fadeIn(delay: 2100.ms, duration: 400.ms),

          if (proofs.isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(height: 1,
              color: AppColors.gold.withValues(alpha: 0.18)),
            const SizedBox(height: 16),

            // ── 5 · MICRO PROOFS ──────────────────────────────────────
            for (var i = 0; i < proofs.length; i++) ...[
              Row(
                children: [
                  Text('◇',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 13, height: 1,
                      fontWeight: FontWeight.w800)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(proofs[i],
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppTypography.label.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 12, letterSpacing: 2.2,
                        fontWeight: FontWeight.w800,
                      )),
                  ),
                ],
              ).animate().fadeIn(
                delay: Duration(milliseconds: 2300 + i * 140),
                duration: 350.ms,
              ).slideX(begin: -0.05, end: 0,
                delay: Duration(milliseconds: 2300 + i * 140),
                duration: 350.ms, curve: Curves.easeOut),
              if (i != proofs.length - 1) const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }

  Widget _half(Uint8List? bytes, String? url) {
    if (bytes != null) {
      return Image.memory(bytes, fit: BoxFit.cover);
    }
    if (url != null && url.isNotEmpty) {
      return Image.network(url, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.surface1));
    }
    return const ColoredBox(color: AppColors.surface1);
  }
}

/// Number-arrow-number block. The current number animates 0→current first
/// (dopamine of seeing your score), then the arrow + projected number pop
/// in with elastic scale (dopamine of seeing it go UP).
class _ScoreTransition extends StatelessWidget {
  final AnimationController controller;
  final int currentScore;
  final int projectedScore;

  const _ScoreTransition({
    required this.controller,
    required this.currentScore,
    required this.projectedScore,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = Curves.easeOutExpo.transform(controller.value);
        final shownCurrent = (t * currentScore).round();
        // Projected reveals after current finishes (last 30% of timeline).
        final revealT = ((controller.value - 0.7) / 0.3).clamp(0.0, 1.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Current — neutral white-gold tone
            SizedBox(
              width: 96,
              child: Text('$shownCurrent',
                textAlign: TextAlign.center,
                style: AppTypography.display.copyWith(
                  fontSize: 86, height: 0.95, letterSpacing: -3,
                  color: AppColors.textPrimary,
                  fontStyle: FontStyle.italic,
                )),
            ),

            // Arrow — gold, scales in with the projection
            const SizedBox(width: 16),
            Transform.scale(
              scale: 0.6 + revealT * 0.6,
              child: Opacity(
                opacity: revealT,
                child: Text('→',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 50,
                    height: 0.95,
                    fontWeight: FontWeight.w300,
                    shadows: [
                      Shadow(color: AppColors.gold.withValues(alpha: 0.55),
                        blurRadius: 14),
                    ],
                  )),
              ),
            ),
            const SizedBox(width: 16),

            // Projected — gold + glow, slight elastic pop
            SizedBox(
              width: 96,
              child: Transform.scale(
                scale: 0.85 + revealT * 0.15,
                child: Opacity(
                  opacity: revealT,
                  child: Text('$projectedScore',
                    textAlign: TextAlign.center,
                    style: AppTypography.display.copyWith(
                      fontSize: 102, height: 0.95, letterSpacing: -3.5,
                      color: AppColors.gold,
                      fontStyle: FontStyle.italic,
                      shadows: [
                        Shadow(color: AppColors.gold.withValues(alpha: 0.6),
                          blurRadius: 28),
                      ],
                    )),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
