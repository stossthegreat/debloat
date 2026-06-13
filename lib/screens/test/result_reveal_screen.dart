import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/aura_verdict_service.dart';
import '../../services/share_service.dart';
import '../../services/test/charisma_test_engine.dart';
import '../../theme/auralay_app_colors.dart';
import '../../theme/auralay_app_typography.dart';

/// Cinematic post-test result reveal.
///
/// Animation timeline:
///
///   t = 0ms     — black screen, "READING YOUR AURA…" pulse
///   t = 700ms   — score counts up 0 → final (1800ms duration)
///   t = 2500ms  — score lands at full size + haptic + glow flash
///   t = 2900ms  — tier stamp slams in (TIER · UNTOUCHABLE)
///   t = 3400ms  — 5 phase bars fill sequentially (200ms each, 100ms stagger)
///   t = 4900ms  — roast line fades in
///   t = 5800ms  — action buttons appear (SHARE / RETAKE)
///
/// User cannot dismiss the reveal until ~6s in — by design. The cinema
/// IS the moment.
class ResultRevealScreen extends StatefulWidget {
  final CharismaTestResult result;
  final Uint8List? photoBytes;
  final double? eyeY;
  /// True when this reveal came from the TRAIN tab free-practice flow
  /// rather than the scripted /charisma-test. Changes the retake button
  /// copy + route ("TRAIN AGAIN" → /train vs "RETAKE TEST" → /charisma-test).
  final bool isFreeTraining;
  /// True when this reveal came from the viral SEDUCTION TEST. Switches
  /// the tier ladder to the dark-charisma names (PHANTOM / APEX /
  /// HEARTBREAKER…) and labels the share card 'SEDUCTION INDEX'.
  final bool isSeductionTest;

  const ResultRevealScreen({
    super.key,
    required this.result,
    required this.photoBytes,
    required this.eyeY,
    this.isFreeTraining = false,
    this.isSeductionTest = false,
  });

  @override
  State<ResultRevealScreen> createState() => _ResultRevealScreenState();
}

class _ResultRevealScreenState extends State<ResultRevealScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scoreCounter;
  bool _scoreLanded = false;
  bool _tierLanded  = false;
  bool _showButtons = false;

  @override
  void initState() {
    super.initState();
    _scoreCounter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    // Kick off the choreography.
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      _scoreCounter.forward();
    });

    Future<void>.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() => _scoreLanded = true);
    });

    Future<void>.delayed(const Duration(milliseconds: 3000), () {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _tierLanded = true);
    });

    Future<void>.delayed(const Duration(milliseconds: 6800), () {
      if (!mounted) return;
      setState(() => _showButtons = true);
    });
  }

  @override
  void dispose() {
    _scoreCounter.dispose();
    super.dispose();
  }

  AuraVerdict get _verdict {
    final base = AuraVerdictService.fromSession(
      score:        widget.result.overallScore,
      presencePct:  widget.result.avgPresence,
      composurePct: widget.result.avgComposure,
      warmthPct:    widget.result.avgWarmth,
      rangePct:     widget.result.avgRange,
    );
    // Swap the tier word for the dark-charisma ladder when the reveal is
    // for the SEDUCTION TEST. Same score, different brand register.
    if (widget.isSeductionTest) {
      return AuraVerdict(
        score: base.score,
        tier:  AuraVerdictService.seductionTierFor(base.score),
        roast: base.roast,
        strongestDimension: base.strongestDimension,
        weakestDimension:   base.weakestDimension,
        dimensionPcts:      base.dimensionPcts,
      );
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Subtle radial bleed top — luxury aesthetic
            const _CornerBleed(),

            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),

                  // ─── INTRO — fades out as the score arrives ─────────
                  AnimatedOpacity(
                    duration: 400.ms,
                    opacity: _scoreLanded ? 0.0 : 1.0,
                    child: Column(
                      children: [
                        Text('READING YOUR AURA',
                          style: AppTypography.label.copyWith(
                            color: AppColors.accent,
                            fontSize: 11, letterSpacing: 3.5,
                            fontWeight: FontWeight.w800,
                          )).animate(onPlay: (c) => c.repeat(reverse: true))
                            .fade(begin: 0.5, end: 1.0, duration: 800.ms),
                        const SizedBox(height: 6),
                        Container(
                          width: 32, height: 1,
                          color: AppColors.accent.withValues(alpha: 0.5)),
                      ],
                    ),
                  ),

                  // ─── HERO SCORE COUNT-UP ────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: AnimatedBuilder(
                      animation: _scoreCounter,
                      builder: (_, __) {
                        final v = (_scoreCounter.value *
                                widget.result.overallScore).round();
                        return _HeroScoreNumber(score: v, landed: _scoreLanded);
                      },
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ─── TIER STAMP ────────────────────────────────────
                  AnimatedOpacity(
                    duration: 280.ms,
                    opacity: _tierLanded ? 1.0 : 0.0,
                    child: Column(
                      children: [
                        Text(_verdict.tier,
                          style: AppTypography.label.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: 22, letterSpacing: 8,
                            fontWeight: FontWeight.w900,
                          )),
                        const SizedBox(height: 12),
                        Container(
                          width: 56, height: 1,
                          color: AppColors.accent.withValues(alpha: 0.65)),
                      ],
                    ).animate(target: _tierLanded ? 1 : 0)
                      .scale(begin: const Offset(1.18, 1.18), end: const Offset(1, 1),
                        duration: 360.ms, curve: Curves.easeOutBack),
                  ),

                  const SizedBox(height: 28),

                  // ─── 5 PHASE BARS — sequential reveal ─────────────
                  _PhaseBars(result: widget.result),

                  const SizedBox(height: 26),

                  // ─── ROAST LINE — fades in late ───────────────────
                  Animate(
                    delay: 4900.ms,
                    effects: [FadeEffect(duration: 700.ms)],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '"${_verdict.roast}"',
                        textAlign: TextAlign.center,
                        maxLines: 4,
                        style: GoogleFonts.playfairDisplay(
                          color: AppColors.textPrimary.withValues(alpha: 0.92),
                          fontSize: 18, height: 1.45, letterSpacing: -0.2,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w500,
                        )),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ─── THE READOUT — plain-English WHY lines ───────
                  Animate(
                    delay: 5500.ms,
                    effects: [
                      FadeEffect(duration: 600.ms),
                      SlideEffect(
                        begin: const Offset(0, 0.05), end: Offset.zero,
                        duration: 600.ms, curve: Curves.easeOut),
                    ],
                    child: _ReadoutPanel(result: widget.result),
                  ),

                  const SizedBox(height: 32),

                  // ─── ACTION BUTTONS — appear last ─────────────────
                  AnimatedOpacity(
                    duration: 500.ms,
                    opacity: _showButtons ? 1.0 : 0.0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 60,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                            onPressed: _showButtons ? _share : null,
                            child: const Text('SHARE THE EYES',
                              style: TextStyle(
                                fontSize: 14, letterSpacing: 3,
                                fontWeight: FontWeight.w900,
                              )),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 52,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: AppColors.accent.withValues(alpha: 0.55),
                                width: 1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _showButtons
                                ? () => context.go(
                                    widget.isFreeTraining
                                      ? '/train'
                                      : '/charisma-test')
                                : null,
                            child: Text(
                              widget.isFreeTraining ? 'TRAIN AGAIN' : 'RETAKE TEST',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13, letterSpacing: 2.4,
                                fontWeight: FontWeight.w800,
                              )),
                          ),
                        ),
                        if (!widget.isFreeTraining) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _showButtons
                                ? () => context.go('/train')
                                : null,
                            child: Text('Continue to lessons',
                              style: TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 12, letterSpacing: 0.5,
                              )),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share() async {
    HapticFeedback.mediumImpact();
    // Render whatever phase ids are in the result, in iteration order.
    // Charisma test → LOCK/SMILE/BREAK/RETURN/STILL.
    // Seduction lesson → LOOK UP / SLOW BLINK / SIDE GLANCE / HALF SMILE / FLOW.
    final dimensions = <String, double>{};
    widget.result.phaseScores.forEach((id, value) {
      // Title-case the displayLabel for readability on the card.
      final label = id.displayLabel.split(' ').map((w) =>
          w.isEmpty ? w : '${w[0]}${w.substring(1).toLowerCase()}').join(' ');
      dimensions[label] = value;
    });
    final hasLessonPhases =
        widget.result.phaseScores.containsKey(TestPhaseId.lookUp);
    final hasTestPhases =
        widget.result.phaseScores.containsKey(TestPhaseId.smolder) ||
        widget.isSeductionTest;
    final cardLabel = hasTestPhases
        ? 'PRESENCE INDEX'
        : hasLessonPhases
          ? 'PRESENCE LESSON'
          : 'CHARISMA INDEX';
    await ShareService.shareAuraResult(
      context:        context,
      photoBytes:     widget.photoBytes,
      eyeYNormalized: widget.eyeY,
      score:          _verdict.score,
      tier:           _verdict.tier,
      roast:          _verdict.roast,
      dimensions:     dimensions,
      techniqueName:  cardLabel,
      text: 'My AURA score is ${_verdict.score} — ${_verdict.tier}. Test yours on ImHim: imhim.app',
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Hero score number — italic Playfair with metallic red gradient + glow
// ──────────────────────────────────────────────────────────────────────────

class _HeroScoreNumber extends StatelessWidget {
  final int score;
  final bool landed;
  const _HeroScoreNumber({required this.score, required this.landed});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFF4A52), Color(0xFFE8222A), Color(0xFFB8141A)],
        stops: [0.0, 0.55, 1.0],
      ).createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: AnimatedDefaultTextStyle(
        duration: 280.ms,
        style: GoogleFonts.playfairDisplay(
          fontSize: landed ? 168 : 148,
          height: 0.9, letterSpacing: -8,
          color: Colors.white,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w900,
          shadows: landed ? [
            Shadow(
              color: AppColors.accent.withValues(alpha: 0.55),
              blurRadius: 56),
          ] : [],
        ),
        child: Text('$score'),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Phase bars — 5 hairline bars, fill sequentially after intro
// ──────────────────────────────────────────────────────────────────────────

class _PhaseBars extends StatelessWidget {
  final CharismaTestResult result;
  const _PhaseBars({required this.result});

  @override
  Widget build(BuildContext context) {
    // Render the bars based on whatever TestPhaseIds the result contains.
    // Charisma test → 5 LOCK/SMILE/BREAK/RETURN/STILL bars.
    // Seduction lesson → 5 LOOK UP / SLOW BLINK / SIDE GLANCE / HALF SMILE / FLOW bars.
    // The displayLabel extension picks the right copy per id.
    final entries = result.phaseScores.entries.toList();
    return Column(
      children: [
        for (int i = 0; i < entries.length; i++) ...[
          _PhaseBar(
            label: entries[i].key.displayLabel,
            value: entries[i].value,
            // First bar lands ~3400ms into the reveal, then 220ms stagger.
            revealAt: Duration(milliseconds: 3400 + i * 220),
          ),
          if (i < entries.length - 1) const SizedBox(height: 11),
        ],
      ],
    );
  }
}

class _PhaseBar extends StatelessWidget {
  final String label;
  final double value; // 0..100
  final Duration revealAt;
  const _PhaseBar({
    required this.label,
    required this.value,
    required this.revealAt,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (value / 100.0).clamp(0.0, 1.0);
    return Animate(
      delay: revealAt,
      effects: [
        FadeEffect(duration: 280.ms),
        SlideEffect(
          begin: const Offset(0, 0.4), end: Offset.zero,
          duration: 320.ms, curve: Curves.easeOut),
      ],
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(label,
              style: AppTypography.label.copyWith(
                color: AppColors.textSecondary.withValues(alpha: 0.85),
                fontSize: 10, letterSpacing: 2.4,
                fontWeight: FontWeight.w700,
              )),
          ),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                // The fill itself animates from 0 → pct width.
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: pct),
                  duration: 600.ms,
                  curve: Curves.easeOutCubic,
                  builder: (_, w, __) => FractionallySizedBox(
                    widthFactor: w,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(1),
                        boxShadow: [BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.6),
                          blurRadius: 6),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 38,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: value),
              duration: 700.ms,
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => Text(
                '${v.toStringAsFixed(0)}%',
                textAlign: TextAlign.right,
                style: AppTypography.label.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 11, letterSpacing: 0.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  THE READOUT — 3 plain-English lines explaining the score
//  ("You blinked 12 times — charisma range is 8–15.")
// ──────────────────────────────────────────────────────────────────────────

class _ReadoutPanel extends StatelessWidget {
  final CharismaTestResult result;
  const _ReadoutPanel({required this.result});

  @override
  Widget build(BuildContext context) {
    final lines = _buildLines();
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accentBorder, width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('THE READOUT',
            style: AppTypography.label.copyWith(
              color: AppColors.accent,
              fontSize: 9.5, letterSpacing: 2.6,
              fontWeight: FontWeight.w800,
            )),
          const SizedBox(height: 10),
          for (int i = 0; i < lines.length; i++) ...[
            _ReadoutLine(line: lines[i]),
            if (i < lines.length - 1) const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }

  /// Build the 3 plain-English lines from the test signals. Order:
  ///   1. EYES   — gaze + look-aways
  ///   2. BLINK  — blink count vs ideal
  ///   3. SMILE  — peak Duchenne during smile phase
  ///
  /// Each line is keyed to a "good / off" verdict so the dot in front
  /// of each line colours green/amber/red.
  List<_ReadoutLineData> _buildLines() {
    final lines = <_ReadoutLineData>[];

    // ── EYES ────────────────────────────────────────────────────────────
    final lockScore = result.phaseScores[TestPhaseId.lock] ?? 0;
    if (lockScore >= 75) {
      lines.add(_ReadoutLineData(
        label: 'EYES',
        body:  'Locked. ${result.lookAwayCount == 0 ? 'You did not break once' : 'You broke ${result.lookAwayCount} time${result.lookAwayCount == 1 ? '' : 's'} only'}.',
        verdict: _Verdict.good,
      ));
    } else if (lockScore >= 50) {
      lines.add(_ReadoutLineData(
        label: 'EYES',
        body:  'You held the gaze, then broke ${result.lookAwayCount} time${result.lookAwayCount == 1 ? '' : 's'}. The room reads every break.',
        verdict: _Verdict.amber,
      ));
    } else {
      lines.add(_ReadoutLineData(
        label: 'EYES',
        body:  'You broke contact ${result.lookAwayCount} time${result.lookAwayCount == 1 ? '' : 's'} in 30 seconds. The eyes are the foundation — train this first.',
        verdict: _Verdict.bad,
      ));
    }

    // ── BLINK ───────────────────────────────────────────────────────────
    // Charisma range: 8–18 BPM. In a 30s test that's 4–9 blinks.
    final n = result.blinkCount;
    if (n == 0) {
      lines.add(_ReadoutLineData(
        label: 'BLINK',
        body:  'Zero blinks reads as uncanny, not composed. Let the lids land naturally.',
        verdict: _Verdict.amber,
      ));
    } else if (n >= 4 && n <= 9) {
      lines.add(_ReadoutLineData(
        label: 'BLINK',
        body:  'You blinked $n times. Charisma range is 4–9 in 30 seconds. Dialled.',
        verdict: _Verdict.good,
      ));
    } else if (n < 4) {
      lines.add(_ReadoutLineData(
        label: 'BLINK',
        body:  'You blinked $n times — slightly under-blinking. Aim for 4–9 in 30 seconds so it reads relaxed, not frozen.',
        verdict: _Verdict.amber,
      ));
    } else {
      lines.add(_ReadoutLineData(
        label: 'BLINK',
        body:  'You blinked $n times. The room hears every flutter — calm range is 4–9 in 30 seconds.',
        verdict: _Verdict.bad,
      ));
    }

    // ── SMILE ───────────────────────────────────────────────────────────
    final smile = result.peakSmilePct;
    if (smile >= 60) {
      lines.add(_ReadoutLineData(
        label: 'SMILE',
        body:  'Your smile peaked at ${smile.round()}% — a real Duchenne build, eyes engaged with the mouth.',
        verdict: _Verdict.good,
      ));
    } else if (smile >= 30) {
      lines.add(_ReadoutLineData(
        label: 'SMILE',
        body:  'Smile reached ${smile.round()}%. Let it travel up to the eyes — that is what makes it land.',
        verdict: _Verdict.amber,
      ));
    } else {
      lines.add(_ReadoutLineData(
        label: 'SMILE',
        body:  'You barely smiled — peak ${smile.round()}%. Let it BUILD next time. Slow onset reads more authentic than instant.',
        verdict: _Verdict.bad,
      ));
    }

    return lines;
  }
}

class _ReadoutLineData {
  final String label;
  final String body;
  final _Verdict verdict;
  const _ReadoutLineData({
    required this.label,
    required this.body,
    required this.verdict,
  });
}

enum _Verdict { good, amber, bad }

class _ReadoutLine extends StatelessWidget {
  final _ReadoutLineData line;
  const _ReadoutLine({required this.line});

  @override
  Widget build(BuildContext context) {
    final dotColor = switch (line.verdict) {
      _Verdict.good  => AppColors.signalGreen,
      _Verdict.amber => AppColors.signalAmber,
      _Verdict.bad   => AppColors.accent,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              color: dotColor, shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                color: dotColor.withValues(alpha: 0.65), blurRadius: 4)],
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 52,
          child: Text(line.label,
            style: AppTypography.label.copyWith(
              color: AppColors.textTertiary,
              fontSize: 9.5, letterSpacing: 2.0,
              fontWeight: FontWeight.w800,
            )),
        ),
        Expanded(
          child: Text(line.body,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textPrimary.withValues(alpha: 0.92),
              fontSize: 12.5, height: 1.45,
            )),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Corner bleed — subtle red glow at the top edges
// ──────────────────────────────────────────────────────────────────────────

class _CornerBleed extends StatelessWidget {
  const _CornerBleed();
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -1.0),
            radius: 1.4,
            colors: [
              AppColors.accent.withValues(alpha: 0.10),
              Colors.transparent,
            ],
            stops: const [0.0, 0.6],
          ),
        ),
      ),
    );
  }
}
