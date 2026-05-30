import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../theme/auralay_app_colors.dart';

/// Two CINEMATIC painted eyes — the gaze target on the eye-contact
/// session screen. Big, beautiful, alive. Replaces the original
/// abstract red dots.
///
/// Each eye is hand-drawn with CustomPainter:
///   • Almond outline (cubic Bezier upper + lower lid)
///   • Cream sclera with a warm sub-surface tint
///   • Radial-gradient iris: bright amber centre → deep brown edge
///     plus 36 thin radial striations for organic surface
///   • Dark limbal ring (the mark of a beautiful eye)
///   • Deep black "see-through" pupil that DILATES when the user
///     locks gaze — instant non-verbal feedback that the eye is
///     responding to them
///   • Two catchlights (key + bounce) so the eye reads ALIVE
///   • 16 hand-positioned upper lashes fanning outward at the corners
///   • Sparse lower lashes for definition
///   • Soft upper-lid shadow so the eye reads recessed under a brow
///   • Subtle accent rim glow that blooms behind the iris when locked
///
/// The whole widget BREATHES — a 2.4 / 3.6s scale loop so the eyes
/// feel like a living thing on the screen, not a still. When the user
/// locks gaze, the breath SLOWS and the pupil dilates harder.
class FixationDots extends StatelessWidget {
  /// True when the gaze engine has locked on — eyes "wake up."
  final bool isLocked;
  const FixationDots({super.key, required this.isLocked});

  @override
  Widget build(BuildContext context) {
    // CRITICAL: IgnorePointer wraps the WHOLE widget so the
    // Positioned.fill we sit inside doesn't absorb taps.
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (_, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          // Eyes scaled DRAMATICALLY larger than the old dots — these
          // are the focal point of the screen, not decoration.
          final eyeW = (w * 0.34).clamp(120.0, 200.0);
          final eyeH = eyeW * 0.62;
          // Inter-pupillary spacing ~ 52% of screen width.
          final cx = w / 2;
          final eyeSpacing = w * 0.26;
          final y = h * 0.30;
          return Stack(
            children: [
              Positioned(
                left: cx - eyeSpacing - eyeW / 2,
                top:  y - eyeH / 2,
                child: _LivingEye(width: eyeW, height: eyeH,
                    isLocked: isLocked),
              ),
              Positioned(
                left: cx + eyeSpacing - eyeW / 2,
                top:  y - eyeH / 2,
                child: _LivingEye(width: eyeW, height: eyeH,
                    isLocked: isLocked),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Breathing wrapper. Subtle scale loop — never fully static, like
/// real eyes catching breath. Slows when the user locks gaze (the
/// eye "settles in" to the moment).
class _LivingEye extends StatelessWidget {
  final double width;
  final double height;
  final bool isLocked;
  const _LivingEye({
    required this.width,
    required this.height,
    required this.isLocked,
  });

  @override
  Widget build(BuildContext context) {
    final breath = isLocked ? 3600.ms : 2400.ms;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _EyePainter(isLocked: isLocked),
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true))
      .scale(
        begin: const Offset(1.0, 1.0),
        end: Offset(isLocked ? 1.025 : 1.015,
                    isLocked ? 1.025 : 1.015),
        duration: breath,
        curve: Curves.easeInOut,
      );
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

    // ── ALMOND EYE SHAPE — cubic Beziers, dramatic upper arc.
    final eye = Path()
      ..moveTo(0, cy)
      ..cubicTo(w * 0.18, cy - h * 0.62,
                w * 0.82, cy - h * 0.62,
                w,        cy)
      ..cubicTo(w * 0.78, cy + h * 0.42,
                w * 0.22, cy + h * 0.42,
                0,        cy)
      ..close();

    // ── SCLERA — warm cream with a hint of sub-surface pink at the
    // corners. Sells the eye as real instead of cartoon.
    canvas.drawPath(
      eye,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, 0.1),
          radius: 0.95,
          colors: const [
            Color(0xFFF1ECE0),
            Color(0xFFE3D6C8),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    canvas.save();
    canvas.clipPath(eye);

    final irisCenter = Offset(cx, cy + h * 0.02);
    final irisR  = h * (isLocked ? 0.52 : 0.47);
    final pupilR = h * (isLocked ? 0.26 : 0.20);

    // ── RED RIM GLOW behind the iris when locked.
    if (isLocked) {
      canvas.drawCircle(
        irisCenter,
        irisR * 1.45,
        Paint()
          ..color = AppColors.accent.withValues(alpha: 0.60)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }

    // ── IRIS — multi-stop radial gradient.
    final irisRect = Rect.fromCircle(center: irisCenter, radius: irisR);
    canvas.drawCircle(
      irisCenter,
      irisR,
      Paint()
        ..shader = RadialGradient(
          colors: const [
            Color(0xFFA8702E),
            Color(0xFF7A4A20),
            Color(0xFF3F2210),
            Color(0xFF1B0E05),
          ],
          stops: const [0.0, 0.42, 0.82, 1.0],
        ).createShader(irisRect),
    );

    // ── IRIS STRIATIONS — 36 thin radial lines for organic feel.
    final striation = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFE9B879).withValues(alpha: 0.22);
    for (var i = 0; i < 36; i++) {
      final a = (i / 36) * math.pi * 2;
      final inner = pupilR + 2;
      final outer = irisR - 1.5 - (i.isEven ? 0 : irisR * 0.18);
      canvas.drawLine(
        Offset(irisCenter.dx + math.cos(a) * inner,
               irisCenter.dy + math.sin(a) * inner),
        Offset(irisCenter.dx + math.cos(a) * outer,
               irisCenter.dy + math.sin(a) * outer),
        striation,
      );
    }

    // ── LIMBAL RING — the marker of a "beautiful eye."
    canvas.drawCircle(
      irisCenter,
      irisR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = const Color(0xFF170A02),
    );

    // ── PUPIL — pure void. Dilates when locked.
    canvas.drawCircle(
      irisCenter,
      pupilR,
      Paint()..color = Colors.black,
    );

    // ── KEY-LIGHT CATCHLIGHT.
    canvas.drawCircle(
      Offset(irisCenter.dx + pupilR * 0.36,
             irisCenter.dy - pupilR * 0.40),
      pupilR * 0.36,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );

    // ── BOUNCE CATCHLIGHT.
    canvas.drawCircle(
      Offset(irisCenter.dx - pupilR * 0.48,
             irisCenter.dy + pupilR * 0.32),
      pupilR * 0.16,
      Paint()..color = Colors.white.withValues(alpha: 0.48),
    );

    canvas.restore();

    // ── UPPER LID SHADOW — soft dark gradient under the brow.
    canvas.save();
    canvas.clipPath(eye);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h * 0.30),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.30),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h * 0.30)),
    );
    canvas.restore();

    // ── UPPER LASH LINE — thick dark band at the lid edge.
    final upperLash = Path()
      ..moveTo(0, cy)
      ..cubicTo(w * 0.18, cy - h * 0.62,
                w * 0.82, cy - h * 0.62,
                w,        cy);
    canvas.drawPath(
      upperLash,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF0A0A0A),
    );

    // ── INDIVIDUAL UPPER LASHES — 16 strokes, longer + thicker in
    // the middle (the iconic flick).
    final lashPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF000000);

    const lashCount = 16;
    for (var i = 1; i < lashCount; i++) {
      final t = i / lashCount;
      final p = _cubicPoint(
        t,
        Offset(0, cy),
        Offset(w * 0.18, cy - h * 0.62),
        Offset(w * 0.82, cy - h * 0.62),
        Offset(w,        cy),
      );
      final fan = (t - 0.5) * 1.2;
      final angle = -math.pi / 2 + fan * 0.7;
      final len = h * (0.28 + 0.18 * math.sin(t * math.pi));
      final end = Offset(
        p.dx + math.cos(angle) * len,
        p.dy + math.sin(angle) * len,
      );
      lashPaint.strokeWidth = 1.4 + math.sin(t * math.pi) * 0.9;
      canvas.drawLine(p, end, lashPaint);
    }

    // ── LOWER LID line.
    final lowerLid = Path()
      ..moveTo(0, cy)
      ..cubicTo(w * 0.22, cy + h * 0.42,
                w * 0.78, cy + h * 0.42,
                w,        cy);
    canvas.drawPath(
      lowerLid,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = const Color(0xFF22150B),
    );

    // ── SPARSE LOWER LASHES.
    const lowerLashCount = 8;
    for (var i = 1; i < lowerLashCount; i++) {
      final t = i / lowerLashCount;
      final p = _cubicPoint(
        t,
        Offset(0, cy),
        Offset(w * 0.22, cy + h * 0.42),
        Offset(w * 0.78, cy + h * 0.42),
        Offset(w,        cy),
      );
      final angle = math.pi / 2 + (t - 0.5) * 0.6;
      final len = h * 0.10 * math.sin(t * math.pi);
      canvas.drawLine(
        p,
        Offset(p.dx + math.cos(angle) * len,
               p.dy + math.sin(angle) * len),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 0.9
          ..color = const Color(0xFF1A0F05),
      );
    }
  }

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
