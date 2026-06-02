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
  /// True only during the 12-second drill phase. When false the entire
  /// eye-target overlay is hidden so the apprentice\'s own face is
  /// clean during intro / theory / debrief / close beats — no more
  /// "whose face is on screen?" confusion. Selene\'s eyes only appear
  /// when she\'s actually calling the lock.
  final bool active;
  const FixationDots({
    super.key,
    required this.isLocked,
    this.active = true,
  });

  /// Asset path the lesson-eyes image is loaded from. Single source
  /// of truth — change here, every gaze lesson updates.
  static const String assetPath = 'assets/eyes/lesson_eyes.jpg';

  /// Display box aspect ratio. The full opaque band in the source
  /// PNG is ~4.5:1 (lashes + eyeshadow + eyes). 3.4:1 is the sweet
  /// spot — wide enough that BoxFit.cover crops most of the outer
  /// eyeshadow wings (no "red square" effect) yet still wider than
  /// the eyes themselves so they read as a horizontal lock target.
  static const double _eyeBandAspect = 3.4;

  @override
  Widget build(BuildContext context) {
    // Hidden outside the drill phase — clean camera view for intro,
    // theory, debrief, close. Only the lock itself surfaces Selene\'s eyes.
    if (!active) return const SizedBox.shrink();
    // CRITICAL: IgnorePointer wraps the WHOLE widget so the
    // Positioned.fill we sit inside doesn't absorb taps. Without
    // this every button on the session screens becomes dead.
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (_, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          // 55% of screen width — bumped from 42% so the eyes have
          // real presence as a lock target without going back to the
          // poster-size 96% that was reading as a screensaver. With
          // the 3.4:1 aspect this lands a wide, compact band that
          // sits cleanly above the apprentice\'s own camera face.
          final imgW = w * 0.55;
          final imgH = imgW / _eyeBandAspect;
          // Vertical offset bumped 0.22 → 0.32 so the eye band sits
          // a touch lower on the screen — the previous position was
          // hugging the top chrome and reading as a logo more than
          // a face-to-face lock target.
          final y    = h * 0.32;
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
