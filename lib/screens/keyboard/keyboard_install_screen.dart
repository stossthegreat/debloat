import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/analytics_service.dart';
import '../../services/keyboard_install_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/common/imhim_wordmark.dart';

/// "Install the ImHim Keyboard" onboarding. Three-step explainer with a
/// hero CTA that deep-links to iOS Settings → ImHim. The keyboard itself
/// is a separate iOS target; this screen is the conversion surface that
/// walks the user through Apple's "Allow Full Access" gauntlet.
class KeyboardInstallScreen extends StatefulWidget {
  const KeyboardInstallScreen({super.key});

  @override
  State<KeyboardInstallScreen> createState() =>
      _KeyboardInstallScreenState();
}

class _KeyboardInstallScreenState extends State<KeyboardInstallScreen> {
  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    AnalyticsService.keyboardInstallViewed();
  }

  Future<void> _openSettings() async {
    HapticFeedback.mediumImpact();
    // ignore: discarded_futures
    AnalyticsService.keyboardInstallSettingsTapped();
    await KeyboardInstallService.openSystemKeyboardSettings();
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
              // ── Chrome row: close X + ImHim wordmark ─────────────
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

              // ── Hero block ──────────────────────────────────────
              Text(
                'Rizz from anywhere.',
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
                'Install the ImHim keyboard. Screenshot any '
                'chat — three replies appear straight inside iMessage, '
                'Hinge, Tinder. Zero app switching.',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 14.5, height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ).animate().fadeIn(delay: 120.ms, duration: 420.ms),

              const SizedBox(height: 28),

              // ── Step pack ───────────────────────────────────────
              _Step(
                index: 1,
                title: 'Open Settings',
                body: 'Tap the button below — drops you straight into the '
                      'ImHim row in iOS Settings.',
                delay: 200,
              ),
              _Step(
                index: 2,
                title: 'Keyboards → Add New Keyboard',
                body: 'Pick "ImHim Keyboard" from the list. It joins your '
                      'system keyboards.',
                delay: 300,
              ),
              _Step(
                index: 3,
                title: 'Toggle "Allow Full Access"',
                body: 'Required so we can read your latest screenshot + reach '
                      'our backend. We never log keystrokes. Ever.',
                delay: 400,
              ),

              const SizedBox(height: 24),

              // ── Primary CTA ─────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _openSettings,
                  child: Text(
                    'OPEN SETTINGS',
                    style: AppTypography.label.copyWith(
                      color: Colors.white,
                      fontSize: 13,
                      letterSpacing: 3.6,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleXY(begin: 1.0, end: 1.015,
                      duration: 1400.ms, curve: Curves.easeInOut),
              const SizedBox(height: 14),

              // ── Quiet reassurance row ───────────────────────────
              _ReassureRow(
                icon: Icons.lock_outline,
                text: 'No keystrokes ever leave your phone.',
              ),
              _ReassureRow(
                icon: Icons.photo_camera_back_outlined,
                text: 'Screenshots are read once and dropped — never stored.',
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
