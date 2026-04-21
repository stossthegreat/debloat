import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../services/local_store_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // Minimum splash duration so the brand moment registers.
    final onboarded = await LocalStoreService.isOnboarded();
    await Future.delayed(const Duration(milliseconds: 2400));
    if (!mounted) return;
    // First-run → onboarding (which leads to paywall). Returning → home.
    context.go(onboarded ? '/home' : '/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.base,
      body: Stack(
        children: [
          // ── Editorial gradient wash ────────────────────────────────────
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.4),
                  radius: 1.1,
                  colors: [
                    AppColors.accentGlow,
                    AppColors.base,
                  ],
                ),
              ),
            ),
          ),

          // ── Subtle grid (like a reference coordinate system) ───────────
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(),
            ),
          ),

          // ── Top hairline + META label ─────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 1,
                      color: AppColors.surface3,
                    ).animate().fadeIn(delay: 100.ms, duration: 600.ms)
                      .scaleX(begin: 0, end: 1,
                          delay: 100.ms, duration: 800.ms, curve: Curves.easeOut),
                    const SizedBox(height: Sp.sm),
                    Text('ANALYSIS · MEASUREMENT · RECALIBRATION',
                      style: AppTypography.label.copyWith(
                        color: AppColors.textTertiary, fontSize: 9, letterSpacing: 2.8))
                      .animate().fadeIn(delay: 300.ms, duration: 600.ms),
                  ],
                ),
              ),
            ),
          ),

          // ── Center mark ───────────────────────────────────────────────
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Gold ring mark
                SizedBox(
                  width: 92, height: 92,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer ring
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.red.withValues(alpha: 0.35),
                            width: 1,
                          ),
                        ),
                      ).animate().fadeIn(delay: 300.ms, duration: 700.ms)
                        .scale(begin: const Offset(0.9, 0.9),
                            delay: 300.ms, duration: 700.ms, curve: Curves.easeOut),
                      // Inner dot
                      Container(
                        width: 6, height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.red,
                          shape: BoxShape.circle,
                        ),
                      ).animate().fadeIn(delay: 600.ms, duration: 500.ms),
                      // Crosshair
                      Container(
                        width: 92, height: 1,
                        color: AppColors.red.withValues(alpha: 0.22),
                      ).animate().fadeIn(delay: 700.ms, duration: 500.ms)
                        .scaleX(begin: 0, end: 1,
                            delay: 700.ms, duration: 600.ms, curve: Curves.easeOut),
                      Container(
                        width: 1, height: 92,
                        color: AppColors.red.withValues(alpha: 0.22),
                      ).animate().fadeIn(delay: 700.ms, duration: 500.ms)
                        .scaleY(begin: 0, end: 1,
                            delay: 700.ms, duration: 600.ms, curve: Curves.easeOut),
                    ],
                  ),
                ),

                const SizedBox(height: Sp.xl),

                // Brand — editorial serif
                Text('Mirrorly',
                  style: AppTypography.display.copyWith(
                    color: AppColors.textPrimary, fontSize: 56, letterSpacing: -2))
                  .animate().fadeIn(delay: 900.ms, duration: 800.ms)
                  .slideY(begin: 0.15, end: 0,
                      delay: 900.ms, duration: 800.ms, curve: Curves.easeOut),

                const SizedBox(height: Sp.sm),

                // Italic undertagline — luxury fragrance energy
                Text('the face, measured.',
                  style: AppTypography.h1Italic.copyWith(
                    fontSize: 18,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.2))
                  .animate().fadeIn(delay: 1300.ms, duration: 700.ms),
              ],
            ),
          ),

          // ── Bottom progress hairline ─────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Loading bar
                    SizedBox(
                      width: size.width,
                      child: const LinearProgressIndicator(
                        backgroundColor: AppColors.surface2,
                        valueColor: AlwaysStoppedAnimation(AppColors.red),
                        minHeight: 1,
                      ),
                    ).animate().fadeIn(delay: 1600.ms, duration: 500.ms),

                    const SizedBox(height: Sp.sm),

                    Row(
                      children: [
                        Text('BOOTING SYSTEM',
                          style: AppTypography.label.copyWith(
                            color: AppColors.textMuted, fontSize: 9, letterSpacing: 2.8)),
                        const Spacer(),
                        Text('v1.0',
                          style: AppTypography.label.copyWith(
                            color: AppColors.textMuted, fontSize: 9, letterSpacing: 2.8)),
                      ],
                    ).animate().fadeIn(delay: 1800.ms, duration: 500.ms),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.surface3.withValues(alpha: 0.12)
      ..strokeWidth = 0.5;

    // Vertical lines
    for (double x = 0; x < size.width; x += 60) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // Horizontal lines
    for (double y = 0; y < size.height; y += 60) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
