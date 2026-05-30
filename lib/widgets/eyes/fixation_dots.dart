import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../theme/auralay_app_colors.dart';

/// Cinematic eyes overlay on the eye-contact session screen.
///
/// Loads a single horizontal asset — a tight close-up of a real
/// woman's eyes (cheekbone to brow, no full face) — and positions it
/// in the upper third of the screen as the gaze target. Same coords
/// the old painted eyes / red dots used.
///
/// Drop your render at:  assets/eyes/lesson_eyes.jpg
/// Format: JPEG, 16:6 horizontal letterbox (e.g. 1600 × 600), tight
/// crop on the EYES only (cheekbone to brow line — DO NOT include
/// nose / mouth / hair), photoreal, dark background, soft red rim
/// light on one side, lashes visible. Eyes should be DEAD-CENTRE
/// and STARING INTO THE CAMERA — that's the entire intensity.
///
/// When the gaze engine reports lock the asset stays the same but a
/// subtle red glow blooms around it + a soft scale pulse — the eye
/// "responds" to the user holding gaze.
///
/// Falls back to a black band with a single red gleam if the asset
/// hasn't been dropped in yet — never blocks the build.
class FixationDots extends StatelessWidget {
  /// True when the gaze engine has locked on — eyes "wake up."
  final bool isLocked;
  const FixationDots({super.key, required this.isLocked});

  /// Asset path the lesson-eyes image is loaded from. Single source
  /// of truth — change here, every gaze lesson updates.
  static const String assetPath = 'assets/eyes/lesson_eyes.jpg';

  @override
  Widget build(BuildContext context) {
    // CRITICAL: IgnorePointer wraps the WHOLE widget so the
    // Positioned.fill we sit inside doesn't absorb taps. Without
    // this every button on the session screens becomes dead.
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (_, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          // Letterbox crop sized large — these ARE the screen.
          final imgW = w * 0.92;
          final imgH = imgW * 0.36; // matches the 16:6 asset aspect
          final y    = h * 0.18;
          return Stack(
            children: [
              Positioned(
                left: (w - imgW) / 2,
                top:  y,
                child: SizedBox(
                  width: imgW, height: imgH,
                  child: _CinematicEyes(
                    isLocked: isLocked,
                    width: imgW, height: imgH,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CinematicEyes extends StatelessWidget {
  final bool isLocked;
  final double width;
  final double height;
  const _CinematicEyes({
    required this.isLocked,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final base = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── The eyes asset itself. Drop a real render at
          //    assets/eyes/lesson_eyes.jpg and it appears.
          Image.asset(
            FixationDots.assetPath,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _MissingAssetFallback(
              isLocked: isLocked,
            ),
          ),
          // ── Red glow bloom behind when locked — pulled to the
          //    edges so the eyes themselves stay clear.
          if (isLocked)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.95,
                    colors: [
                      Colors.transparent,
                      AppColors.accent.withValues(alpha: 0.30),
                    ],
                    stops: const [0.55, 1.0],
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    // Subtle breathing pulse — slower when locked (eye "settles in").
    return base
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scale(
          begin: const Offset(1.0, 1.0),
          end: Offset(isLocked ? 1.025 : 1.012,
                      isLocked ? 1.025 : 1.012),
          duration: (isLocked ? 3600 : 2400).ms,
          curve: Curves.easeInOut,
        );
  }
}

/// Tasteful fallback when the lesson_eyes.jpg asset hasn't been
/// dropped in yet. Black band + a single soft red gleam dead-centre
/// so the screen still has a gaze target instead of an error icon.
class _MissingAssetFallback extends StatelessWidget {
  final bool isLocked;
  const _MissingAssetFallback({required this.isLocked});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.black),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent.withValues(
                alpha: isLocked ? 0.95 : 0.65),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(
                    alpha: isLocked ? 0.55 : 0.30),
                blurRadius: isLocked ? 22 : 14,
                spreadRadius: isLocked ? 2 : -1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
