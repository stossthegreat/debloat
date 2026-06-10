import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/analytics_service.dart';
import '../../services/local_store_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/common/imhim_wordmark.dart';

/// ── Onboarding manifesto screen ────────────────────────────────────────
///
/// Was the men's/women's gender picker. Bro: "this is a men's app, we
/// need to stay on task — take that off and put the manifesto." The
/// screen now opens the funnel with the three-pillar promise the user
/// is buying into.
///
/// Class name kept so the existing `/onboarding/gender` route + the
/// Settings → "Glow-up style" deep link don't break — both just land
/// here now. The userGender default is forced to 'm' on first show
/// so every downstream surface (analysis tone, render prompts, voice
/// persona) keeps reading the user as male.
class GenderPickScreen extends StatelessWidget {
  /// Reuse mode: when true (opened from Settings), shows a back arrow
  /// and pops on Continue instead of pushing /scan.
  final bool fromSettings;

  const GenderPickScreen({super.key, this.fromSettings = false});

  Future<void> _continue(BuildContext context) async {
    HapticFeedback.mediumImpact();
    // Pin gender to 'm' so the downstream pipeline (render prompts,
    // voice partners, advice prose) keeps its male coding. The picker
    // is gone but the persisted flag still drives every gendered
    // branch the app makes.
    await LocalStoreService.setUserGender('m');
    await LocalStoreService.setOnboarded(true);
    AnalyticsService.tabOpened('onboarding_manifesto_continue');
    if (!context.mounted) return;
    if (fromSettings) {
      context.pop();
    } else {
      context.go('/scan');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
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
                const SizedBox(height: 28),

              const SizedBox(height: 8),
              const Center(child: ImHimWordmark(fontSize: 38)),

              const SizedBox(height: 28),

              Text('So you want to be him?',
                textAlign: TextAlign.center,
                style: GoogleFonts.playfairDisplay(
                  color: AppColors.textPrimary,
                  fontSize: 30, height: 1.2,
                  letterSpacing: -0.4,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w800,
                ))
                .animate().fadeIn(duration: 420.ms)
                .slideY(begin: 0.04, end: 0,
                    duration: 420.ms, curve: Curves.easeOut),

              const SizedBox(height: 34),

              const _Pillar(
                eyebrow: 'LOOKS',
                line: 'We show you exactly what to fix.',
                delayMs: 200,
              ),
              const SizedBox(height: 22),
              const _Pillar(
                eyebrow: 'GAME',
                line: 'Live roleplay until everything you say lands.',
                delayMs: 360,
              ),
              const SizedBox(height: 22),
              const _Pillar(
                eyebrow: 'RIZZ',
                line: 'Never run out of things to say.',
                delayMs: 520,
              ),

              const Spacer(),

              // Continue CTA.
              Material(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: () => _continue(context),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    alignment: Alignment.center,
                    child: Text('CONTINUE',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13.5, letterSpacing: 3.0,
                        fontWeight: FontWeight.w900,
                      )),
                  ),
                ),
              ).animate().fadeIn(delay: 720.ms, duration: 420.ms),

              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }
}

/// One pillar row — small red eyebrow above an italic Playfair line.
/// Matches the editorial voice used elsewhere (paywall pitch, intro
/// reel, looks tab subhead) so the screen reads as part of one brand.
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
        FadeEffect(duration: 420.ms, delay: Duration(milliseconds: delayMs)),
        SlideEffect(
          duration: 420.ms,
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
              fontSize: 11.5, letterSpacing: 3.2,
              fontWeight: FontWeight.w900,
            )),
          const SizedBox(height: 6),
          Text(line,
            style: GoogleFonts.playfairDisplay(
              color: AppColors.textPrimary,
              fontSize: 20, height: 1.3,
              letterSpacing: -0.3,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w700,
            )),
        ],
      ),
    );
  }
}
