import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../theme/auralay_app_colors.dart';

/// Two cinematic eye drawings, positioned in the upper third of the
/// screen, spaced like an imagined partner's eyes. Replaces the
/// abstract red dots — same coordinates, same gaze-target role, but
/// the user now locks onto eyes with lashes / iris / pupil / catchlight
/// instead of stylised circles. The eye is the entire point of this
/// app; the target should LOOK like an eye.
///
/// Drawn OUTSIDE the camera transform stack so they sit at absolute
/// screen coords regardless of the camera preview's mirror / rotation
/// / scale.
///
/// When the gaze engine reports lock the iris brightens, a red rim
/// glow blooms around it, and the pupil dilates slightly — the user
/// feels the eye RESPOND to their lock.
class FixationDots extends StatelessWidget {
  /// True when the gaze engine has locked on — eyes "wake up."
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
          const eyeW = 96.0;
          const eyeH = 60.0;
          return Stack(
            children: [
              Positioned(
                left: w * 0.34 - eyeW / 2,
                top:  y - eyeH / 2,
                child: SizedBox(
                  width: eyeW, height: eyeH,
                  child: _PaintedEye(isLocked: isLocked),
                ),
              ),
              Positioned(
                left: w * 0.66 - eyeW / 2,
                top:  y - eyeH / 2,
                child: SizedBox(
                  width: eyeW, height: eyeH,
                  child: _PaintedEye(isLocked: isLocked),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PaintedEye extends StatelessWidget {
  final bool isLocked;
  const _PaintedEye({required this.isLocked});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _EyePainter(isLocked: isLocked),
    ).animate(onPlay: (c) => c.repeat(reverse: true))
      .fadeIn(duration: 1800.ms)
      .then().fadeOut(duration: 1800.ms);
  }
}

class _EyePainter extends CustomPainter {
  final bool isLocked;
  _EyePainter({required this.isLocked});

  @override
  void paint(Canvas canvas, Size size) {
    final w  = size.width;
    final h  = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // ── ALMOND EYE SHAPE — upper + lower lid arcs meeting at the
    // outer + inner canthi. Upper arc is taller (the brow side),
    // lower arc is gentler (the cheek side).
    final eye = Path()
      ..moveTo(0, cy)
      ..cubicTo(w * 0.20, cy - h * 0.55,
                w * 0.80, cy - h * 0.55,
                w,        cy)
      ..cubicTo(w * 0.78, cy + h * 0.40,
                w * 0.22, cy + h * 0.40,
                0,        cy)
      ..close();

    // ── EYE WHITE (sclera) — soft warm cream, not pure white.
    canvas.drawPath(
      eye,
      Paint()..color = const Color(0xFFEDE6DA),
    );

    // ── CLIP everything below to the eye shape (so the iris doesn't
    // bleed past the lashes).
    canvas.save();
    canvas.clipPath(eye);

    final irisCenter = Offset(cx, cy + 1);
    final irisR     = h * (isLocked ? 0.50 : 0.46);
    final pupilR    = h * (isLocked ? 0.22 : 0.18);

    // ── RED GLOW behind the iris when locked. Painted FIRST so it
    // sits behind everything.
    if (isLocked) {
      canvas.drawCircle(
        irisCenter,
        irisR * 1.35,
        Paint()
          ..color = AppColors.accent.withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    // ── IRIS — radial gradient, warmer at the centre, deeper at the
    // rim. Reads as a real iris with depth.
    canvas.drawCircle(
      irisCenter,
      irisR,
      Paint()
        ..shader = RadialGradient(
          colors: const [
            Color(0xFF8E5A2E), // warm amber centre
            Color(0xFF5A371B), // mid brown
            Color(0xFF2A180A), // deep edge
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(
          Rect.fromCircle(center: irisCenter, radius: irisR),
        ),
    );

    // ── LIMBAL RING — the dark circle around the iris. Adds depth
    // and is consistently the marker of a "beautiful eye."
    canvas.drawCircle(
      irisCenter,
      irisR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF1B0E05),
    );

    // ── PUPIL — see-through black void. Slightly larger when locked
    // (dilated response to the user holding gaze).
    canvas.drawCircle(
      irisCenter,
      pupilR,
      Paint()..color = Colors.black,
    );

    // ── CATCHLIGHT — the white speck on the pupil that makes the
    // eye look ALIVE. Upper-right of the pupil, where a key light
    // would land.
    canvas.drawCircle(
      Offset(irisCenter.dx + pupilR * 0.35,
             irisCenter.dy - pupilR * 0.35),
      pupilR * 0.32,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );

    // ── Secondary catchlight — tiny dot lower-left, the reflected
    // bounce light. Sells the realism.
    canvas.drawCircle(
      Offset(irisCenter.dx - pupilR * 0.45,
             irisCenter.dy + pupilR * 0.30),
      pupilR * 0.14,
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );

    canvas.restore();

    // ── UPPER LASH LINE — the dark band where the lashes meet the
    // lid. Drawn OUTSIDE the clip so it reads as a thick edge.
    final upperLash = Path()
      ..moveTo(0, cy)
      ..cubicTo(w * 0.20, cy - h * 0.55,
                w * 0.80, cy - h * 0.55,
                w,        cy);
    canvas.drawPath(
      upperLash,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF0A0A0A),
    );

    // ── INDIVIDUAL EYELASHES on the upper lid — twelve curved
    // strokes, longer in the middle, fanning slightly outward at the
    // corners. Each lash sampled along the upper-lash bezier.
    final lashPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF0A0A0A);

    const lashCount = 12;
    for (var i = 1; i < lashCount; i++) {
      final t = i / lashCount;
      // Bezier point on the upper lid at parameter t
      final p = _cubicPoint(
        t,
        Offset(0, cy),
        Offset(w * 0.20, cy - h * 0.55),
        Offset(w * 0.80, cy - h * 0.55),
        Offset(w,        cy),
      );

      // Lash direction: roughly perpendicular to the lid, fanning
      // slightly outward at the corners.
      final fan = (t - 0.5) * 1.0; // -0.5..0.5
      final angle = -math.pi / 2 + fan * 0.8;
      // Longer in the middle (the iconic flick).
      final len = 7.0 + 6.0 * math.sin(t * math.pi);
      final end = Offset(
        p.dx + math.cos(angle) * len,
        p.dy + math.sin(angle) * len,
      );
      lashPaint.strokeWidth = 1.1 + math.sin(t * math.pi) * 0.6;
      canvas.drawLine(p, end, lashPaint);
    }

    // ── LOWER LID — thin line, barely there. Sells the eye opening
    // without competing with the upper lashes.
    final lowerLid = Path()
      ..moveTo(0, cy)
      ..cubicTo(w * 0.22, cy + h * 0.40,
                w * 0.78, cy + h * 0.40,
                w,        cy);
    canvas.drawPath(
      lowerLid,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFF22150B),
    );
  }

  /// Cubic Bezier point at parameter t.
  Offset _cubicPoint(double t, Offset p0, Offset p1, Offset p2, Offset p3) {
    final u = 1 - t;
    return Offset(
      u * u * u * p0.dx
        + 3 * u * u * t * p1.dx
        + 3 * u * t * t * p2.dx
        + t * t * t * p3.dx,
      u * u * u * p0.dy
        + 3 * u * u * t * p1.dy
        + 3 * u * t * t * p2.dy
        + t * t * t * p3.dy,
    );
  }

  @override
  bool shouldRepaint(covariant _EyePainter old) => old.isLocked != isLocked;
}
