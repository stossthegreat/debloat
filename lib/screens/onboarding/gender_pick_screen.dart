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

/// ── Onboarding manifesto + profile screen ──────────────────────────────
///
/// Opens the funnel with the Debloat OS promise, then asks the one
/// question the AI needs before it can render the drained version of
/// the user's face: MALE or FEMALE. The choice feeds every render
/// prompt downstream (Nano Banana needs it to reconstruct the face
/// correctly), so Continue stays locked until one is picked.
///
/// Class name kept so the existing `/onboarding/gender` route + the
/// Settings deep link don't break — both land here.
class GenderPickScreen extends StatefulWidget {
  /// Reuse mode: when true (opened from Settings), shows a back arrow
  /// and pops on Continue instead of pushing the consent screen.
  final bool fromSettings;

  const GenderPickScreen({super.key, this.fromSettings = false});

  @override
  State<GenderPickScreen> createState() => _GenderPickScreenState();
}

class _GenderPickScreenState extends State<GenderPickScreen> {
  String? _gender; // 'm' | 'f'

  @override
  void initState() {
    super.initState();
    // Pre-select the stored value when re-opened from Settings.
    // ignore: discarded_futures
    LocalStoreService.userGender().then((g) {
      if (mounted && g != null) setState(() => _gender = g);
    });
  }

  Future<void> _continue(BuildContext context) async {
    final g = _gender;
    if (g == null) return;
    HapticFeedback.mediumImpact();
    await LocalStoreService.setUserGender(g);
    await LocalStoreService.setOnboarded(true);
    AnalyticsService.tabOpened('onboarding_gender_$g');
    if (!context.mounted) return;
    if (widget.fromSettings) {
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
          // Cyan glow wash from the top — depth without competing
          // with the copy.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -1.1),
                    radius: 1.2,
                    colors: [
                      AppColors.brand.withValues(alpha: 0.16),
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
                  if (widget.fromSettings)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 16, color: AppColors.textSecondary),
                      ),
                    )
                  else
                    const SizedBox(height: 10),

                  const SizedBox(height: 16),
                  const Center(
                    child: DebloatWordmark(fontSize: 50, letterSpacing: -1.6),
                  ),

                  const SizedBox(height: 30),

                  Text('Under the bloat\nis your real face.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                      color: AppColors.textPrimary,
                      fontSize: 34, height: 1.12,
                      letterSpacing: -0.8,
                      fontWeight: FontWeight.w700,
                    ))
                    .animate().fadeIn(duration: 460.ms)
                    .slideY(begin: 0.04, end: 0,
                        duration: 460.ms, curve: Curves.easeOut),

                  const Spacer(),

                  const _Pillar(
                    eyebrow: 'SCAN',
                    line: 'See how much bloat\nis hiding your face.',
                    delayMs: 220,
                  ),
                  const SizedBox(height: 24),
                  const _Pillar(
                    eyebrow: 'SYSTEM',
                    line: 'The daily checklist\nthat drains it.',
                    delayMs: 400,
                  ),
                  const SizedBox(height: 24),
                  const _Pillar(
                    eyebrow: 'MIRROR',
                    line: 'The AI shows you\nthe drained you.',
                    delayMs: 580,
                  ),

                  const Spacer(),

                  // ── The one question the AI needs ──
                  Text('SO THE AI RENDERS YOU RIGHT',
                    textAlign: TextAlign.center,
                    style: AppTypography.label.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 9.5, letterSpacing: 2.8,
                      fontWeight: FontWeight.w900,
                    )).animate().fadeIn(delay: 700.ms, duration: 460.ms),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _GenderCard(
                        label: 'MALE',
                        icon: Icons.male_rounded,
                        selected: _gender == 'm',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _gender = 'm');
                        },
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: _GenderCard(
                        label: 'FEMALE',
                        icon: Icons.female_rounded,
                        selected: _gender == 'f',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _gender = 'f');
                        },
                      )),
                    ],
                  ).animate().fadeIn(delay: 760.ms, duration: 460.ms),

                  const SizedBox(height: 18),

                  // Continue CTA — locked until a profile is picked.
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: _gender == null ? 0.35 : 1.0,
                    child: Material(
                      color: AppColors.brand,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: _gender == null
                            ? null
                            : () => _continue(context),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          alignment: Alignment.center,
                          child: Text('BOOT THE SYSTEM',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF03181C),
                              fontSize: 14.5, letterSpacing: 3.4,
                              fontWeight: FontWeight.w900,
                            )),
                        ),
                      ),
                    ),
                  ).animate().fadeIn(delay: 860.ms, duration: 460.ms),

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

/// One selectable profile card — brand-bordered when active.
class _GenderCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _GenderCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.brand.withValues(alpha: 0.14)
                : AppColors.surface1,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.brand : AppColors.surface3,
              width: selected ? 1.4 : 0.8),
            boxShadow: selected
                ? [BoxShadow(
                    color: AppColors.brand.withValues(alpha: 0.25),
                    blurRadius: 18)]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                size: 26,
                color: selected ? AppColors.brand : AppColors.textTertiary),
              const SizedBox(height: 6),
              Text(label,
                style: AppTypography.label.copyWith(
                  color: selected
                      ? AppColors.brand
                      : AppColors.textSecondary,
                  fontSize: 11, letterSpacing: 2.8,
                  fontWeight: FontWeight.w900,
                )),
            ],
          ),
        ),
      ),
    );
  }
}

/// One pillar row — cyan eyebrow above a grotesk line.
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
              color: AppColors.brand,
              fontSize: 12, letterSpacing: 3.6,
              fontWeight: FontWeight.w900,
            )),
          const SizedBox(height: 6),
          Text(line,
            style: GoogleFonts.spaceGrotesk(
              color: AppColors.textPrimary,
              fontSize: 23, height: 1.2,
              letterSpacing: -0.4,
              fontWeight: FontWeight.w700,
            )),
        ],
      ),
    );
  }
}
