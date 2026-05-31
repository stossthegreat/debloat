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

  /// Display box aspect ratio. The full opaque band in the source
  /// PNG is ~4.5:1 (lashes + eyeshadow + eyes), but the user only
  /// wants the IRISES visible — the surrounding makeup was reading
  /// as a "red square" around the eyes. A tighter 2.8:1 box with
  /// BoxFit.cover crops the makeup wings from both sides; the iris
  /// pair sits in the centre untouched. The vertical transparent
  /// padding is still cropped away by cover so there\'s no box
  /// edges, no gradient, no border — just two eyes.
  static const double _eyeBandAspect = 2.8;

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
          // Compact lock target — 42% of screen width. User feedback:
          // "make them way smaller so user can be closer." Big eyes
          // read as a screensaver; small eyes pull the apprentice's
          // gaze into a tight focal point — that\'s the whole drill.
          final imgW = w * 0.42;
          final imgH = imgW / _eyeBandAspect;
          final y    = h * 0.22;
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
    // Just the asset — no black plate, no warm rim, no border. The
    // PNG is transparent by design; the drill vignette around it
    // handles every bit of mood. cover + center crops the
    // transparent top/bottom of the source PNG so the eye band
    // fills the SizedBox cleanly with no box edges.
    final base = Image.asset(
      FixationDots.assetPath,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      errorBuilder: (_, __, ___) => _MissingAssetFallback(
        isLocked: isLocked,
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
