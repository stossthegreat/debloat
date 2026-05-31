import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../theme/auralay_app_colors.dart';

/// Cinematic eyes overlay on the eye-contact session screen.
///
/// Loads a single PNG of a woman's eyes (transparent background, eyes
/// + lashes only — no full face) and positions it in the upper-third
/// of the screen as the gaze target. Same coords the old painted eyes
/// / red dots used.
///
/// Drop your render at:  assets/eyes/lesson_eyes.jpg
/// Format: PNG, transparent background, eyes-only (no face, no
/// forehead, no nose, no mouth, no hair), photoreal, dead-centre gaze
/// into the camera. The widget paints a solid black plate UNDER the
/// PNG so the apprentice's own camera feed (visible elsewhere on the
/// screen) doesn't bleed through the eye area — the woman's eyes are
/// the only thing in that band, period.
///
/// On gaze lock the asset stays the same but a soft red bloom blooms
/// from the edges — the eye "responds" to the user holding gaze.
///
/// Falls back to a black plate + single red gleam if the asset hasn't
/// been dropped in yet — never blocks the build.
class FixationDots extends StatelessWidget {
  /// True when the gaze engine has locked on — eyes "wake up."
  final bool isLocked;
  const FixationDots({super.key, required this.isLocked});

  /// Asset path the lesson-eyes image is loaded from. Single source
  /// of truth — change here, every gaze lesson updates.
  static const String assetPath = 'assets/eyes/lesson_eyes.jpg';

  /// Aspect ratio of the lesson_eyes asset (width / height). Matches
  /// the 1536×1024 source PNG — wider than the 16:6 letterbox the
  /// widget used to assume, so the eyes display un-cropped.
  static const double _assetAspect = 1536.0 / 1024.0;

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
          // Big — the eyes ARE the screen. 92% of width.
          final imgW = w * 0.92;
          final imgH = imgW / _assetAspect;
          final y    = h * 0.10;
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
    // Solid black plate UNDER the PNG so the apprentice's own face in
    // the camera feed doesn't show through the band of pixels where
    // the eyes live. The PNG is transparent — the black gives it a
    // backdrop without painting a visible rectangle (the surrounding
    // session vignette already darkens the edges so the plate blends
    // into the scene).
    final base = Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(decoration: BoxDecoration(color: Colors.black)),
        // The eyes asset itself — contain so we keep the full crop.
        Image.asset(
          FixationDots.assetPath,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          errorBuilder: (_, __, ___) => _MissingAssetFallback(
            isLocked: isLocked,
          ),
        ),
        // WARM RIM TINT on lock — soft red bloom from the edges that
        // brings the eyes into the warm "she's here" space.
        AnimatedOpacity(
          duration: const Duration(milliseconds: 320),
          opacity: isLocked ? 0.55 : 0.0,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 1.0,
                colors: [
                  Colors.transparent,
                  AppColors.accent,
                ],
                stops: [0.55, 1.0],
              ),
            ),
          ),
        ),
      ],
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
