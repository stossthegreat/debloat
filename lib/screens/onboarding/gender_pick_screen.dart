import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/analytics_service.dart';
import '../../services/local_store_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// One-screen pre-scan gate that lets the user pick whether the app
/// tunes its analysis prose, rendered previews, and Mirror-tab
/// thumbnails for men's grooming or women's beauty.
///
/// Why it exists: the analysis + render pipeline downstream is
/// male-coded by default — a woman who scans without setting this
/// gets a male-rendered "maximised" preview, which is brand-killing
/// on first impression. Asking up-front (one tap, three buttons)
/// adds one screen to the funnel but means the very first scan a
/// woman sees comes back tuned to her.
///
/// Persisted in [LocalStoreService.userGender] as 'm' / 'f' / null.
/// Re-openable from Settings → Glow-up style. Skipping defaults to
/// null which the backend treats as the legacy unspecified case.
class GenderPickScreen extends StatelessWidget {
  /// Reuse mode: when true (opened from Settings to change selection),
  /// the appbar shows a back arrow and tapping a choice pops back
  /// instead of routing forward to /scan.
  final bool fromSettings;

  const GenderPickScreen({super.key, this.fromSettings = false});

  Future<void> _pick(BuildContext context, String? code) async {
    HapticFeedback.mediumImpact();
    await LocalStoreService.setUserGender(code);
    // First-pass users get marked onboarded the moment they answer,
    // so a re-launch goes to /home instead of dragging them back here.
    await LocalStoreService.setOnboarded(true);
    AnalyticsService.tabOpened('gender_pick_${code ?? "skip"}');
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
              if (fromSettings) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      size: 16, color: AppColors.textSecondary),
                  ),
                ),
              ] else
                const SizedBox(height: 32),

              const Spacer(),

              // Headline.
              Text('Whose look should we tune for?',
                style: GoogleFonts.playfairDisplay(
                  color: AppColors.textPrimary,
                  fontSize: 30, height: 1.15,
                  letterSpacing: -0.6,
                  fontWeight: FontWeight.w700,
                ))
                .animate().fadeIn(duration: 420.ms)
                .slideY(begin: 0.04, end: 0, duration: 420.ms,
                  curve: Curves.easeOut),

              const SizedBox(height: 10),

              Text('Mirrorly tunes its measurements, advice, and rendered '
                   'previews to your selection. You can change this later '
                   'in Settings.',
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 14, height: 1.5))
                .animate().fadeIn(delay: 120.ms, duration: 360.ms),

              const SizedBox(height: 36),

              _ChoiceCard(
                label: 'MEN\'S GROOMING',
                quote: '"Sharper. Squarer. Cleaner."',
                onTap: () => _pick(context, 'm'),
                delay: 240,
              ),
              const SizedBox(height: 12),
              _ChoiceCard(
                label: 'WOMEN\'S BEAUTY',
                quote: '"Softer. Brighter. Refined."',
                onTap: () => _pick(context, 'f'),
                delay: 320,
              ),

              const SizedBox(height: 18),

              Center(
                child: TextButton(
                  onPressed: () => _pick(context, null),
                  child: Text('Skip — general advice',
                    style: AppTypography.label.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 11, letterSpacing: 1.8,
                      fontWeight: FontWeight.w600)),
                ),
              ).animate().fadeIn(delay: 400.ms, duration: 360.ms),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final String label;
  final String quote;
  final VoidCallback onTap;
  final int delay;

  const _ChoiceCard({
    required this.label,
    required this.quote,
    required this.onTap,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.45), width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                style: AppTypography.label.copyWith(
                  color: AppColors.red,
                  fontSize: 11, letterSpacing: 2.6,
                  fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(quote,
                style: AppTypography.h1.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 18, height: 1.25,
                  letterSpacing: -0.3,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(
        delay: Duration(milliseconds: delay), duration: 380.ms)
      .slideY(begin: 0.06, end: 0,
        delay: Duration(milliseconds: delay),
        duration: 380.ms, curve: Curves.easeOut);
  }
}
