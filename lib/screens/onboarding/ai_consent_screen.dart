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

/// Onboarding consent — deliberately MINIMAL (v371).
///
/// Bro: "we say too much there... just two clean things on that screen
/// with links to privacy and terms, one tick box — that's perfect."
///
/// So: wordmark, one disclosure line (App Store 5.1.1(i)/5.1.2(i) —
/// photos are processed by third-party AI), TWO tappable link cards
/// (Terms of Use, Privacy Policy), ONE checkbox, one CTA. Everything
/// detailed lives inside the linked documents.
///
/// Granting persists [LocalStoreService.setAiConsent] once, so no
/// feature screen ever has to prompt again. Auto-skips forward if
/// consent was already granted.
class AiConsentScreen extends StatefulWidget {
  const AiConsentScreen({super.key});

  @override
  State<AiConsentScreen> createState() => _AiConsentScreenState();
}

class _AiConsentScreenState extends State<AiConsentScreen> {
  bool _agreed = false;

  @override
  void initState() {
    super.initState();
    // Already granted (e.g. re-entering the funnel) → don't re-ask.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await LocalStoreService.hasAiConsent() && mounted) {
        context.go('/scan');
      }
    });
    AnalyticsService.consentShown();
  }

  Future<void> _continue() async {
    if (!_agreed) {
      HapticFeedback.heavyImpact();
      return;
    }
    HapticFeedback.mediumImpact();
    await LocalStoreService.setAiConsent(true);
    // ignore: discarded_futures
    AnalyticsService.consentGranted();
    if (mounted) context.go('/scan');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MirrorlyWordmark(fontSize: 34)
                  .animate()
                  .fadeIn(duration: 500.ms),

              const Spacer(),

              Text('Before we start.',
                      style: GoogleFonts.spaceGrotesk(
                        color: AppColors.textPrimary,
                        fontSize: 34, height: 1.05,
                        letterSpacing: -0.8,
                        
                        fontWeight: FontWeight.w800,
                      ))
                  .animate()
                  .fadeIn(delay: 120.ms, duration: 500.ms),
              const SizedBox(height: 12),
              Text(
                'Your photos are analysed by our AI partners (OpenAI · '
                'Replicate) to build your scores, renders and plans. '
                'Nothing is sold. Full details in the documents below.',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 14, height: 1.5,
                ),
              ).animate().fadeIn(delay: 220.ms, duration: 500.ms),

              const SizedBox(height: 26),

              _LinkCard(
                title: 'Terms of Use',
                onTap: () => context.push('/terms'),
              ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
              const SizedBox(height: 10),
              _LinkCard(
                title: 'Privacy Policy',
                onTap: () => context.push('/privacy'),
              ).animate().fadeIn(delay: 360.ms, duration: 400.ms),

              const SizedBox(height: 24),

              // The ONE checkbox.
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _agreed = !_agreed);
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                          color: _agreed ? AppColors.red : Colors.transparent,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: _agreed
                                ? AppColors.red
                                : AppColors.textTertiary,
                            width: 1.4,
                          ),
                        ),
                        child: _agreed
                            ? const Icon(Icons.check_rounded,
                                size: 17, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'I agree to the Terms of Use and Privacy Policy.',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: 13.5, height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn(delay: 420.ms, duration: 400.ms),

              const SizedBox(height: 18),

              // CTA — dim until the box is ticked.
              SizedBox(
                width: double.infinity,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _agreed ? 1.0 : 0.45,
                  child: Material(
                    color: AppColors.red,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _continue,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text('AGREE & CONTINUE',
                            textAlign: TextAlign.center,
                            style: AppTypography.label.copyWith(
                              color: Colors.white,
                              fontSize: 13, letterSpacing: 3.0,
                              fontWeight: FontWeight.w900,
                            )),
                      ),
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 480.ms, duration: 400.ms),

              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  const _LinkCard({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.surface3, width: 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(title,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    )),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: AppColors.red),
            ],
          ),
        ),
      ),
    );
  }
}
