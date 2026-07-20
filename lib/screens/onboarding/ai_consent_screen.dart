import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/analytics_service.dart';
import '../../services/local_store_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/mirrorly_wordmark.dart';

/// Onboarding AI-data consent — the single, up-front permission gate
/// required by App Store guidelines 5.1.1(i) / 5.1.2(i). It sits between
/// the gender pick and the first scan, so every new user reads exactly
/// what data is sent, to whom, and must tick to agree BEFORE any data
/// reaches a third-party AI service.
///
/// Granting persists [LocalStoreService.setAiConsent] once, so no feature
/// screen ever has to prompt again (the per-feature checks read this flag
/// and stay silent). Revocable later in Settings.
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
    if (!_agreed) return;
    HapticFeedback.mediumImpact();
    await LocalStoreService.setAiConsent(true);
    AnalyticsService.consentGranted();
    if (!mounted) return;
    context.go('/scan');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
              child: Row(
                children: [
                  const MirrorlyWordmark(fontSize: 28, letterSpacing: -0.7),
                  const SizedBox(width: 8),
                  Container(
                    width: 4, height: 4,
                    margin: const EdgeInsets.only(top: 11),
                    decoration: const BoxDecoration(
                        color: AppColors.red, shape: BoxShape.circle),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI & YOUR PRIVACY',
                        style: GoogleFonts.inter(
                          color: AppColors.red,
                          fontSize: 11, letterSpacing: 2.6,
                          fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    Text('ImHim Looks uses AI to power your scans, live voice '
                        'roleplay, and Rizz replies.',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 24, height: 1.2,
                          letterSpacing: -0.4,
                          fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text('The data each feature needs is sent over an '
                        'encrypted connection to our AI providers. Face '
                        'geometry is computed on your device first, and '
                        'dating-app screenshots are read on your device '
                        '(OCR) first.',
                        style: GoogleFonts.inter(
                          color: AppColors.textSecondary,
                          fontSize: 14, height: 1.5,
                          fontWeight: FontWeight.w500)),
                    const SizedBox(height: 22),

                    const _Row(
                      head: 'WHAT IS SENT',
                      body: 'Your selfie photo (scans), your voice during '
                          'live roleplay and voice drills, and the '
                          'screenshots or text you submit in Rizz. Nothing '
                          'else — no name, email, contacts, location, or '
                          'tracking IDs.'),
                    const _Row(
                      head: 'WHO RECEIVES IT',
                      body: 'OpenAI (analysis, ratings, voice roleplay, '
                          'Rizz replies) and Replicate (rendered "after" '
                          'previews). Each processes your data for one '
                          'request only and excludes it from training '
                          'under their standard API terms.'),
                    const _Row(
                      head: 'EQUAL PROTECTION',
                      body: 'Both providers contractually guarantee the '
                          'same or equal privacy protection: encrypted in '
                          'transit, no long-term retention, no training, '
                          'no advertising, no resale.'),
                    const _Row(
                      head: 'YOU\'RE IN CONTROL',
                      body: 'You can revoke this permission any time in '
                          'Settings → Revoke AI permission, and delete all '
                          'on-device data. Nothing is tied to an account — '
                          'there is no account.'),

                    const SizedBox(height: 6),
                    // Functional links to the full documents.
                    Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Read the full',
                            style: GoogleFonts.inter(
                              color: AppColors.textTertiary,
                              fontSize: 13, fontWeight: FontWeight.w500)),
                        _LinkText(
                            label: 'Privacy Policy',
                            onTap: () => context.push('/privacy')),
                        Text('and',
                            style: GoogleFonts.inter(
                              color: AppColors.textTertiary,
                              fontSize: 13, fontWeight: FontWeight.w500)),
                        _LinkText(
                            label: 'Terms of Use',
                            onTap: () => context.push('/terms')),
                        Text('.',
                            style: GoogleFonts.inter(
                              color: AppColors.textTertiary,
                              fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Tick-to-agree + continue, pinned to the bottom.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _agreed = !_agreed);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            width: 24, height: 24,
                            margin: const EdgeInsets.only(top: 1),
                            decoration: BoxDecoration(
                              color: _agreed
                                  ? AppColors.red
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: _agreed
                                    ? AppColors.red
                                    : Colors.white.withValues(alpha: 0.35),
                                width: 1.4),
                            ),
                            child: _agreed
                                ? const Icon(Icons.check_rounded,
                                    size: 16, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'I agree to the Privacy Policy and Terms of '
                              'Use, and I consent to ImHim Looks sharing the data '
                              'described above with its AI providers '
                              '(OpenAI and Replicate).',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 12.5, height: 1.4,
                                fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _agreed ? _continue : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        disabledBackgroundColor:
                            AppColors.red.withValues(alpha: 0.25),
                        foregroundColor: Colors.white,
                        disabledForegroundColor:
                            Colors.white.withValues(alpha: 0.5),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text('AGREE & CONTINUE',
                          style: GoogleFonts.inter(
                            fontSize: 15, letterSpacing: 2,
                            fontWeight: FontWeight.w900)),
                    ),
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

class _Row extends StatelessWidget {
  final String head, body;
  const _Row({required this.head, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(head,
              style: GoogleFonts.inter(
                color: AppColors.red,
                fontSize: 9.5, letterSpacing: 2.0,
                fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(body,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13, height: 1.45,
                fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _LinkText extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _LinkText({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(label,
          style: GoogleFonts.inter(
            color: AppColors.red,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
            decorationColor: AppColors.red,
          )),
    );
  }
}
