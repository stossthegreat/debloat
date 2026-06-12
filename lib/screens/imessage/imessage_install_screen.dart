import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/common/imhim_wordmark.dart';

/// "Use ImHim inside iMessage" onboarding. Walks the user through the
/// three taps Apple needs them to make to enable the iMessage extension:
/// open a chat → tap the + button → pick ImHim from the app drawer.
class ImessageInstallScreen extends StatefulWidget {
  const ImessageInstallScreen({super.key});

  @override
  State<ImessageInstallScreen> createState() =>
      _ImessageInstallScreenState();
}

class _ImessageInstallScreenState extends State<ImessageInstallScreen> {
  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    AnalyticsService.keyboardInstallViewed();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Chrome row: close X + wordmark.
              Row(
                children: [
                  _CloseButton(onTap: () {
                    HapticFeedback.selectionClick();
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/home');
                    }
                  }),
                  const SizedBox(width: 14),
                  const ImHimWordmark(fontSize: 26, letterSpacing: -0.7),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 28),

              Text(
                'Rizz inside iMessage.',
                style: GoogleFonts.playfairDisplay(
                  color: Colors.white,
                  fontSize: 34, height: 1.06,
                  letterSpacing: -1.0,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w800,
                ),
              ).animate().fadeIn(duration: 420.ms)
                  .slideY(begin: 0.04, end: 0,
                      duration: 420.ms, curve: Curves.easeOut),
              const SizedBox(height: 10),
              Text(
                'Take a screenshot of any chat. Open Messages, tap the '
                'plus button, pick ImHim. Three replies appear — drop one '
                'into the message box and send.',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 14.5, height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ).animate().fadeIn(delay: 120.ms, duration: 420.ms),

              const SizedBox(height: 28),

              _Step(
                index: 1,
                title: 'Open Messages',
                body: 'Open any chat — iMessage, group chat, Hinge link.',
                delay: 200,
              ),
              _Step(
                index: 2,
                title: 'Tap the + button',
                body: 'Next to the message box. The iMessage app drawer slides up.',
                delay: 300,
              ),
              _Step(
                index: 3,
                title: 'Pick ImHim',
                body: 'Our icon sits with the rest of your iMessage apps. '
                      'Tap it, screenshot the chat, three replies arrive in seconds.',
                delay: 400,
              ),

              const SizedBox(height: 24),

              _ReassureRow(
                icon: Icons.lock_outline,
                text: 'Reads only the screenshot you took. No keystrokes.',
              ),
              _ReassureRow(
                icon: Icons.photo_camera_back_outlined,
                text: 'Screenshots are sent once, never stored.',
              ),
              _ReassureRow(
                icon: Icons.bolt_rounded,
                text: 'Replies arrive in under five seconds.',
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int index;
  final String title;
  final String body;
  final int delay;
  const _Step({
    required this.index,
    required this.title,
    required this.body,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider, width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.red.withValues(alpha: 0.18),
              border: Border.all(
                color: AppColors.red.withValues(alpha: 0.6), width: 0.8),
            ),
            alignment: Alignment.center,
            child: Text(
              '$index',
              style: GoogleFonts.inter(
                color: AppColors.red,
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 13, height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(
            delay: Duration(milliseconds: delay), duration: 380.ms)
        .slideY(begin: 0.04, end: 0,
            delay: Duration(milliseconds: delay),
            duration: 380.ms, curve: Curves.easeOut);
  }
}

class _ReassureRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ReassureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: AppColors.surface1,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.surface3, width: 0.6),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.close_rounded,
              size: 20, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
