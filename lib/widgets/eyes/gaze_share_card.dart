import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/gaze/gaze_lesson.dart';
import '../../services/share_service.dart';
import '../../theme/auralay_app_colors.dart';
import '../../theme/auralay_app_typography.dart';

/// THE GAZE — full-screen share card.
///
/// What lands at the end of every Gaze drill. Dark editorial card,
/// designed to read instantly when screen-recorded and posted:
///
///   THE GAZE
///   LESSON 01 · STILLNESS
///   ──────────────────────
///   MAGNETIC SCORE       82
///   ──────────────────────
///   Eye Stability        91
///   Blink Control        88
///   Tension              79
///   Smile Control        72
///   Rhythm                —
///   ──────────────────────
///   Badge: MAGNETIC
///   "Most men cannot hold still."
///   — LUCIEN
///   ──────────────────────
///   +12 this week (if weekly delta available)
///   [ AGAIN ]   [ NEXT LESSON ]
///
/// Built with InkWell+Material on every button so taps register on
/// iOS — same fix that landed everywhere else.
class GazeShareCard extends StatelessWidget {
  final GazeResult result;
  /// The lesson the result is for. Used to decide which dimension
  /// rows to RENDER vs MARK DIMMED on the breakdown — a lesson with
  /// `smileControl: 0` weight shouldn't surface a SMILE CONTROL
  /// score on its card (the dim was never measured for this drill).
  final GazeLesson lesson;
  /// Previous best score on this lesson, if any. Drives the BEST/NEW
  /// chip + delta surfaced next to the headline score.
  final int? previousBest;
  /// "+12 / -3" weekly delta. Null when there isn't enough history.
  final int? weeklyDelta;
  /// One quote Lucien stamps on the card. Drawn from the lesson's
  /// story content so different lessons leave different fingerprints
  /// on the share.
  final String quote;
  /// Practice-gated cap applied to the displayed magnetic score.
  /// 0.40 on the first attempt, ramps to 1.00 at 24 logged attempts.
  /// A perfect rep on session #1 still only surfaces as 4/10 — they
  /// have to drill through the curriculum to earn the 10.
  /// See [GazeProgressStore.progressionCap].
  final double progressionCap;

  final VoidCallback onAgain;
  final VoidCallback onNext;
  final VoidCallback onClose;

  const GazeShareCard({
    super.key,
    required this.result,
    required this.lesson,
    required this.previousBest,
    required this.weeklyDelta,
    required this.quote,
    required this.onAgain,
    required this.onNext,
    required this.onClose,
    this.progressionCap = 1.0,
  });

  /// True when [dim] carries non-zero weight on the active lesson —
  /// i.e. the score actually means something for this drill.
  bool _scored(GazeDimension dim) =>
      (lesson.weights[dim] ?? 0) > 0.0001;

  /// Verdict word for the CAPPED /10 score so the badge tracks what
  /// the apprentice actually sees, not the raw magnetic underneath.
  static String _badgeForCapped(int outOf10) {
    if (outOf10 >= 9) return 'MAGNETIC';
    if (outOf10 >= 7) return 'STEADY';
    if (outOf10 >= 5) return 'EMERGING';
    return 'WORK TO DO';
  }

  @override
  Widget build(BuildContext context) {
    // Scored out of 10 (internally 0–100). Floor so 95 reads as 9,
    // not 10 — the apprentice has to actually earn the perfect
    // round-up. THEN multiply by the progression cap so the headline
    // number is gated on PRACTICE, not just one good rep. A magnetic
    // 100 with a 0.40 cap surfaces as 4/10; same magnetic 100 after
    // 24 sessions surfaces as 10/10. Real teaching reflects time
    // invested, not luck.
    final score =
        (result.gazeScore * progressionCap / 10).floor().clamp(0, 10).toInt();
    final prev10 = previousBest == null
        ? null
        : (previousBest! * progressionCap / 10).floor();
    final isNewBest = prev10 == null || score > prev10;
    final delta = prev10 == null ? null : (score - prev10);

    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: Stack(
          children: [
            // Atmospheric halo behind the score.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.35),
                      radius: 0.95,
                      colors: [
                        AppColors.accent.withValues(alpha: 0.22),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Top chrome — close.
            Positioned(
              top: 6, right: 10,
              child: _IconButton(icon: Icons.close_rounded, onTap: onClose),
            ),

            // Body.
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 56, 22, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('THE GAZE',
                      style: AppTypography.label.copyWith(
                        color: AppColors.accent,
                        fontSize: 11,
                        letterSpacing: 3.6,
                        fontWeight: FontWeight.w900,
                      )),
                  const SizedBox(height: 8),
                  Text(
                    'LESSON ${result.lessonNumber.toString().padLeft(2, "0")}  ·  ${result.lessonName}',
                    style: AppTypography.label.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      letterSpacing: 2.6,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Headline score ───────────────────────────
                  Center(
                    child: _ScoreHero(
                      score:      score,
                      isNewBest:  isNewBest,
                      delta:      delta,
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Badge — derived from the CAPPED score (not the raw
                  // magnetic) so the apprentice never sees "MAGNETIC"
                  // while the headline reads 4/10. Until they've
                  // drilled enough sessions to lift the cap, the badge
                  // honestly reflects what their practice level means.
                  Center(
                    child: _BadgePill(badge: _badgeForCapped(score)),
                  ),

                  const SizedBox(height: 26),

                  // ── Dimension breakdown ──────────────────────
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          if (_scored(GazeDimension.eyeStability))
                            _DimRow(
                              label: 'EYE STABILITY',
                              pct: result.dimPct(GazeDimension.eyeStability),
                            ),
                          if (_scored(GazeDimension.blinkControl))
                            _DimRow(
                              label: 'BLINK CONTROL',
                              pct: result.dimPct(GazeDimension.blinkControl),
                              note: '${result.blinks} blinks in ${result.drillSeconds}s',
                            ),
                          if (_scored(GazeDimension.tension))
                            _DimRow(
                              label: 'TENSION',
                              pct: result.dimPct(GazeDimension.tension),
                            ),
                          if (_scored(GazeDimension.smileControl))
                            _DimRow(
                              label: 'SMILE CONTROL',
                              pct: result.dimPct(GazeDimension.smileControl),
                            ),
                          if (_scored(GazeDimension.rhythm))
                            _DimRow(
                              label: 'RHYTHM',
                              pct: result.dimPct(GazeDimension.rhythm),
                            ),

                          const SizedBox(height: 18),
                          Container(height: 0.5, color: AppColors.divider),
                          const SizedBox(height: 18),

                          // ── Quote ─────────────────────────────
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6),
                            child: Text('"$quote"',
                                textAlign: TextAlign.center,
                                style: AppTypography.h1Italic.copyWith(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                  height: 1.45,
                                  fontStyle: FontStyle.italic,
                                )),
                          ),
                          const SizedBox(height: 8),
                          Text('— LUCIEN',
                              style: AppTypography.label.copyWith(
                                color: AppColors.accent,
                                fontSize: 10,
                                letterSpacing: 3,
                                fontWeight: FontWeight.w900,
                              )),

                          if (weeklyDelta != null) ...[
                            const SizedBox(height: 22),
                            _WeeklyChip(delta: weeklyDelta!),
                          ],

                          const SizedBox(height: 22),
                        ],
                      ),
                    ),
                  ),

                  // ── CTAs ─────────────────────────────────────
                  _PillButton(
                    label: 'SHARE',
                    filled: true,
                    onTap: () => ShareService.shareScore(
                      context:   context,
                      kindLabel: 'THE GAZE',
                      subLabel:  result.lessonName,
                      score:     score,
                      badge:     _badgeForCapped(score),
                      verdict:   quote,
                      stats: [
                        (label: 'EYE STABILITY', score: (result.dimPct(GazeDimension.eyeStability) / 10).round()),
                        (label: 'TENSION',       score: (result.dimPct(GazeDimension.tension) / 10).round()),
                        (label: 'BLINK CONTROL', score: (result.dimPct(GazeDimension.blinkControl) / 10).round()),
                        (label: 'SMILE',         score: (result.dimPct(GazeDimension.smileControl) / 10).round()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _PillButton(
                          label: 'AGAIN',
                          filled: false,
                          onTap: onAgain,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PillButton(
                          label: 'NEXT',
                          filled: false,
                          onTap: onNext,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _ScoreHero extends StatelessWidget {
  final int score;
  final bool isNewBest;
  final int? delta;
  const _ScoreHero({
    required this.score,
    required this.isNewBest,
    required this.delta,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('MAGNETIC SCORE',
            style: AppTypography.label.copyWith(
              color: AppColors.textTertiary,
              fontSize: 10,
              letterSpacing: 3,
              fontWeight: FontWeight.w900,
            )),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(score.toString(),
                style: AppTypography.display.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 110,
                  height: 1.0,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -4,
                )),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Text('/ 10',
                  style: AppTypography.label.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 14,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w900,
                  )),
            ),
          ],
        ),
        if (delta != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              delta! > 0
                  ? '+$delta vs last attempt'
                  : (delta! < 0
                      ? '$delta vs last attempt'
                      : 'matched your last attempt'),
              style: AppTypography.label.copyWith(
                color: delta! > 0
                    ? AppColors.signalGreen
                    : (delta! < 0
                        ? AppColors.accent
                        : AppColors.textSecondary),
                fontSize: 11,
                letterSpacing: 1.8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        if (isNewBest && delta != null && delta! > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('NEW BEST',
                style: AppTypography.label.copyWith(
                  color: AppColors.signalGreen,
                  fontSize: 10.5,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w900,
                )),
          ),
      ],
    );
  }
}

class _BadgePill extends StatelessWidget {
  final String badge;
  const _BadgePill({required this.badge});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.accentBorder, width: 0.8),
      ),
      child: Text(badge,
          style: AppTypography.label.copyWith(
            color: AppColors.accent,
            fontSize: 13,
            letterSpacing: 3.6,
            fontWeight: FontWeight.w900,
          )),
    );
  }
}

class _DimRow extends StatelessWidget {
  final String label;
  final int    pct;
  final String? note;
  final bool   dimmed;
  const _DimRow({
    required this.label,
    required this.pct,
    this.note,
    this.dimmed = false,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: AppTypography.label.copyWith(
                  color: dimmed
                      ? AppColors.textTertiary
                      : AppColors.textPrimary,
                  fontSize: 10.5,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w900,
                )),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: dimmed ? 0 : (pct / 100.0).clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: AppColors.surface3,
                valueColor: const AlwaysStoppedAnimation(AppColors.accent),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 42,
            child: Text(
              dimmed ? '—' : '${(pct / 10).round()}',
              textAlign: TextAlign.right,
              style: AppTypography.label.copyWith(
                color: dimmed
                    ? AppColors.textTertiary
                    : AppColors.textPrimary,
                fontSize: 13,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(note!,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 9.5,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                  )),
            ),
        ],
      ),
    );
  }
}

class _WeeklyChip extends StatelessWidget {
  final int delta;
  const _WeeklyChip({required this.delta});
  @override
  Widget build(BuildContext context) {
    final positive = delta > 0;
    final color = positive ? AppColors.signalGreen : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 0.8),
      ),
      child: Text(
        positive ? '+$delta this week' : '$delta this week',
        style: AppTypography.label.copyWith(
          color: color,
          fontSize: 11,
          letterSpacing: 2.2,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final bool   filled;
  final VoidCallback onTap;
  const _PillButton({
    required this.label, required this.filled, required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () { HapticFeedback.lightImpact(); onTap(); },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? AppColors.accent : AppColors.surface1,
            borderRadius: BorderRadius.circular(12),
            border: filled
                ? null
                : Border.all(color: AppColors.accentBorder, width: 0.8),
          ),
          child: Text(label,
              style: AppTypography.label.copyWith(
                color: filled ? Colors.white : AppColors.accent,
                fontSize: 12,
                letterSpacing: 3,
                fontWeight: FontWeight.w900,
              )),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () { HapticFeedback.lightImpact(); onTap(); },
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44, height: 44,
          child: Center(
            child: Icon(icon, color: AppColors.textPrimary, size: 22),
          ),
        ),
      ),
    );
  }
}
