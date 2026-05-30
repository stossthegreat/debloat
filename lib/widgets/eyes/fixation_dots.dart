import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../theme/auralay_app_colors.dart';

/// Two red fixation dots, positioned in the upper third of the
/// screen, spaced like an imagined partner's eyes. Drawn OUTSIDE the
/// camera transform stack so they sit at absolute screen coords
/// regardless of the camera preview's mirror / rotation / scale.
///
/// Used by the Gaze + Presence session screens. Brightens slightly
/// when the gaze engine reports lock — confirmation cue.
///
/// User spec (verbatim): "add something on the screen for the user
/// to concentrate on like maybe two red dots a bit up the screen be
/// smart about positioning."
class FixationDots extends StatelessWidget {
  /// True when the gaze engine has locked on — dots glow brighter.
  final bool isLocked;
  const FixationDots({super.key, required this.isLocked});

  @override
  Widget build(BuildContext context) {
    // CRITICAL: IgnorePointer wraps the WHOLE widget so the
    // Positioned.fill we sit inside doesn't absorb taps. Without
    // this, every button on the session screens (X, pause, mic, the
    // share-card pills) became unresponsive — the fill consumed
    // their gestures.
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (_, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final y = h * 0.28;
          return Stack(
            children: [
              Positioned(
                left: w * 0.34 - 9, top: y - 9,
                child: _Dot(isLocked: isLocked),
              ),
              Positioned(
                left: w * 0.66 - 9, top: y - 9,
                child: _Dot(isLocked: isLocked),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool isLocked;
  const _Dot({required this.isLocked});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        width: 18, height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.accent.withValues(
              alpha: isLocked ? 0.95 : 0.78),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(
                  alpha: isLocked ? 0.55 : 0.30),
              blurRadius: 12,
              spreadRadius: -1,
            ),
          ],
        ),
      ).animate(onPlay: (c) => c.repeat(reverse: true))
        .fadeIn(duration: 1400.ms)
        .then().fadeOut(duration: 1400.ms),
    );
  }
}
