import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/analytics_service.dart';
import '../../services/local_store_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/common/mirrorly_wordmark.dart';

/// ── Onboarding manifesto screen ────────────────────────────────────────
///
/// Was the men's/women's gender picker. Bro: "this is a men's app, we
/// need to stay on task — take that off and put the manifesto." Now
/// the screen opens the funnel with the three-pillar promise the user
/// is buying into.
///
/// Class name kept so the existing `/onboarding/gender` route + the
/// Settings → "Glow-up style" deep link don't break — both just land
/// here now. userGender pinned to 'm' on Continue so every downstream
/// surface (analysis tone, render prompts, voice persona) keeps its
/// male coding.
///
/// v170 update — bro: "fill it up more, make the writing a bit bigger,
/// follow dark black background." Wordmark → 52, headline → 38, pillar
/// eyebrow → 13, pillar body → 26. Subtle red glow wash from the top.
/// Same continue button at the bottom.
class GenderPickScreen extends StatelessWidget {
  /// Reuse mode: when true (opened from Settings), shows a back arrow
  /// and pops on Continue instead of pushing /scan.
  final bool fromSettings;

  const GenderPickScreen({super.key, this.fromSettings = false});

  Future<void> _continue(BuildContext context) async {
    HapticFeedback.mediumImpact();
    await LocalStoreService.setUserGender('m');
    await LocalStoreService.setOnboarded(true);
    AnalyticsService.tabOpened('onboarding_manifesto_continue');
    if (!context.mounted) return;
    if (fromSettings) {
      context.pop();
    } else {
      // New users pass through the AI-data consent screen before the
      // first scan; it forwards to /scan on agree (or immediately if
      // consent was already granted).
      context.go('/onboarding/consent');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Subtle red glow wash from the top to give the dark black
          // background a sense of depth without competing with the
          // copy. Sits behind the Scaffold's normal body.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -1.1),
                    radius: 1.2,
                    colors: [
                      AppColors.red.withValues(alpha: 0.18),
                      Colors.black,
                    ],
                    stops: const [0.0, 0.6],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (fromSettings)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 16, color: AppColors.textSecondary),
                      ),
                    )
                  else
                    const SizedBox(height: 18),

                  // Wordmark — bigger, breathes.
                  const SizedBox(height: 22),
                  const Center(
                    child: MirrorlyWordmark(fontSize: 56, letterSpacing: -1.6),
                  ),

                  const SizedBox(height: 38),

                  // Headline — italic Playfair, scaled up so it owns
                  // the upper third of the screen.
                  Text('So you want\nto be him?',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.playfairDisplay(
                      color: AppColors.textPrimary,
                      fontSize: 38, height: 1.1,
                      letterSpacing: -0.6,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w800,
                    ))
                    .animate().fadeIn(duration: 460.ms)
                    .slideY(begin: 0.04, end: 0,
                        duration: 460.ms, curve: Curves.easeOut),

                  const Spacer(),

                  const _Pillar(
                    eyebrow: 'LOOKS',
                    line: 'We show you exactly\nwhat to fix.',
                    delayMs: 220,
                  ),
                  const SizedBox(height: 30),
                  const _Pillar(
                    eyebrow: 'GAME',
                    line: 'Live roleplay until\neverything you say lands.',
                    delayMs: 400,
                  ),
                  const SizedBox(height: 30),
                  const _Pillar(
                    eyebrow: 'RIZZ',
                    line: 'Never run out of\nthings to say.',
                    delayMs: 580,
                  ),

                  const Spacer(flex: 2),

                  // Continue CTA — same red button, bigger touch target.
                  Material(
                    color: AppColors.red,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: () => _continue(context),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        alignment: Alignment.center,
                        child: Text('CONTINUE',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 14.5, letterSpacing: 3.4,
                            fontWeight: FontWeight.w900,
                          )),
                      ),
                    ),
                  ).animate().fadeIn(delay: 780.ms, duration: 460.ms),

                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One pillar row — red eyebrow above an italic Playfair line. v170
/// scales it up: 13pt eyebrow + 26pt body so the three lines own the
/// middle of the screen instead of disappearing at the edges.
class _Pillar extends StatelessWidget {
  final String eyebrow;
  final String line;
  final int delayMs;
  const _Pillar({
    required this.eyebrow,
    required this.line,
    required this.delayMs,
  });

  @override
  Widget build(BuildContext context) {
    return Animate(
      effects: [
        FadeEffect(duration: 460.ms, delay: Duration(milliseconds: delayMs)),
        SlideEffect(
          duration: 460.ms,
          delay:    Duration(milliseconds: delayMs),
          begin:    const Offset(0, 0.04),
          end:      Offset.zero,
          curve:    Curves.easeOut,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eyebrow,
            style: AppTypography.label.copyWith(
              color: AppColors.red,
              fontSize: 13, letterSpacing: 3.6,
              fontWeight: FontWeight.w900,
            )),
          const SizedBox(height: 8),
          Text(line,
            style: GoogleFonts.playfairDisplay(
              color: AppColors.textPrimary,
              fontSize: 26, height: 1.2,
              letterSpacing: -0.4,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w700,
            )),
        ],
      ),
    );
  }
}
