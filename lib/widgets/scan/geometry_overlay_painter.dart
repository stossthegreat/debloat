import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/face_mesh_service.dart';

/// Single-angle scan — spectacle over theatre. Five phases, ~8s total. The
/// moat is visual density on ONE angle, not copying the multi-angle gimmick.
enum ScanPhase {
  searching,
  scanning,
  measuring,
  capturing,
  analysing,
}

/// The scan-screen render stack, engineered to feel like an Iron-Man / Blade
/// Runner / face-ID moment — not a demo app.
///
/// Layer order (bottom-up):
///   1. Ambient particle field (always, slow drift)
///   2. Scanner grid (always, faint)
///   3. Searching reticle       (phase: searching)
///   4. Mesh assembly           (phase: scanning — points rush in, land, bloom)
///   5. Mesh triangle wash      (phase: scanning+)
///   6. Bone structure reveal   (phase: measuring+)
///   7. Measurement callouts    (phase: measuring+, typewriter leader lines)
///   8. Radar shockwave rings   (phase: measuring+)
///   9. Scan-line sweep         (phase: scanning)
///  10. Face-lock corner brackets (phase: measuring+, mesh valid)
///  11. Top ticker / bottom measurement stream
///  12. Capture aperture + glitch countdown (phase: capturing)
///  13. Analysing breath + concentric shockwaves (phase: analysing)
class GeometryOverlayPainter extends CustomPainter {
  final FaceMesh? mesh;
  final ScanPhase phase;
  final double progress;
  final double lockProgress;
  final int countdown;
  final double animT; // seconds since scan screen opened

  const GeometryOverlayPainter({
    required this.mesh,
    required this.phase,
    required this.progress,
    required this.animT,
    this.lockProgress = 0,
    this.countdown = 0,
  });

  // ── Palette ───────────────────────────────────────────────────────────────
  static const _cGold    = Color(0xFFD4A96A);
  static const _cGoldHi  = Color(0xFFFFE6B0);
  static const _cCyan    = Color(0xFF38BDF8);
  static const _cCyanHi  = Color(0xFF8FE9FF);
  static const _cMagenta = Color(0xFFFF4D9E);
  static const _cWhite   = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // ── Layer 1–2: constant ambient ─────────────────────────────────────
    _drawAmbientParticles(canvas, size);
    _drawScannerGrid(canvas, size);

    // ── Phase-specific stack ────────────────────────────────────────────
    switch (phase) {
      case ScanPhase.searching:
        _drawSearchingReticle(canvas, size);
        _drawTopTicker(canvas, size, '◦ SEARCHING · ALIGN FACE · WAIT FOR LOCK');
        break;

      case ScanPhase.scanning:
        if (mesh != null && mesh!.isValid) {
          _drawMeshAssembly(canvas, size);
          _drawMeshTriangleWash(canvas, size);
          _drawScanSweep(canvas, size);
          _drawFaceLockBrackets(canvas, size, intensity: 0.6);
        }
        _drawTopTicker(canvas, size,
          '▸ MAPPING ${_visibleCount().toString().padLeft(3, '0')} / 468 POINTS ON YOUR FACE');
        _drawBottomMeasurementStream(canvas, size);
        break;

      case ScanPhase.measuring:
        if (mesh != null && mesh!.isValid) {
          _drawMeshDots(canvas, size, alphaScale: 0.55);
          _drawMeshTriangleWash(canvas, size);
          _drawBoneStructure(canvas, size, dramatic: true);
          _drawMeasurementCallouts(canvas, size);
          _drawFloatingMeasurements(canvas, size);
          _drawRadarRings(canvas, size);
          _drawFaceLockBrackets(canvas, size, intensity: 1.0);
          // Signature LOCK STRIKE at the climax of measuring — full-screen
          // vignette flash + ring shockwave + "LOCK" label pulse. This is
          // THE moment that lands on TikTok.
          if (progress >= 0.90) _drawLockStrike(canvas, size);
        }
        _drawTopTicker(canvas, size,
          progress >= 0.90
            ? '◆ LOCK ACQUIRED  ·  EVERY MM MAPPED'
            : '◉ YOUR BONES, READ  ·  LOCKING YOUR ARCHETYPE');
        _drawBottomMeasurementStream(canvas, size);
        break;

      case ScanPhase.capturing:
        if (mesh != null && mesh!.isValid) {
          _drawMeshDots(canvas, size, alphaScale: 0.4);
          _drawBoneStructure(canvas, size, pulseBoost: true);
          _drawFaceLockBrackets(canvas, size, intensity: 1.0, snap: true);
        }
        _drawCaptureAperture(canvas, size);
        if (countdown > 0) _drawGlitchCountdown(canvas, size);
        _drawTopTicker(canvas, size, '▣ CAPTURING REFERENCE FRAME  ·  HOLD STILL');
        break;

      case ScanPhase.analysing:
        if (mesh != null && mesh!.isValid) {
          _drawMeshDots(canvas, size, alphaScale: 0.5, breath: true);
          _drawBoneStructure(canvas, size, pulseBoost: true);
        }
        _drawAnalysingShockwaves(canvas, size);
        _drawTopTicker(canvas, size, '◈ COMPOSITING  ·  RENDERING MAXIMIZED TWIN');
        break;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 1  —  Ambient particle field
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawAmbientParticles(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    const count = 55;
    for (var i = 0; i < count; i++) {
      final seed = i * 31.1;
      final px = (_hash(seed) * size.width);
      final py = (_hash(seed + 13) * size.height);
      // Slow drift
      final drift = math.sin(animT * 0.25 + seed) * 18;
      final driftY = math.cos(animT * 0.20 + seed) * 12;
      final x = (px + drift) % size.width;
      final y = (py + driftY) % size.height;

      final pulse = (math.sin(animT * 1.2 + seed * 3.7) + 1) / 2;
      final r = 0.6 + pulse * 1.8;
      final alpha = (0.05 + pulse * 0.25).clamp(0.0, 0.30);

      // Alternate palette — cyan majority, gold and magenta sprinkled
      final color = i % 11 == 0 ? _cMagenta
                  : i % 5  == 0 ? _cGold
                                : _cCyan;
      paint.color = color.withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 2  —  Scanner grid
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawScannerGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _cCyan.withValues(alpha: 0.06)
      ..strokeWidth = 0.5;
    const step = 52.0;
    // Vertical
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // Horizontal
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Bright scanning crosshair — subtle animated accent
    final hairX = (animT * 90) % size.width;
    final hairY = (animT * 62) % size.height;
    final accentV = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.transparent, _cCyan.withValues(alpha: 0.12), Colors.transparent],
      ).createShader(Rect.fromLTWH(hairX - 1, 0, 2, size.height))
      ..strokeWidth = 1;
    canvas.drawLine(Offset(hairX, 0), Offset(hairX, size.height), accentV);

    final accentH = Paint()
      ..shader = LinearGradient(
        colors: [Colors.transparent, _cCyan.withValues(alpha: 0.10), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, hairY - 1, size.width, 2))
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, hairY), Offset(size.width, hairY), accentH);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 3  —  Searching reticle (no face yet)
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawSearchingReticle(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Rotating outer ring with broken segments
    final rOuter = math.min(size.width, size.height) * 0.32;
    final rotate = animT * 0.6;
    final segPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.4;
    for (var i = 0; i < 8; i++) {
      final a0 = rotate + i * (math.pi / 4);
      final seg = math.pi / 10;
      final alpha = 0.25 + (math.sin(animT * 2 + i) + 1) / 2 * 0.45;
      segPaint.color = (i.isEven ? _cGold : _cCyan).withValues(alpha: alpha);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: rOuter),
        a0, seg, false, segPaint,
      );
    }

    // Inner targeting square (45° rotated, pulsing)
    final pulse = (math.sin(animT * 3) + 1) / 2;
    final boxSize = 44.0 + pulse * 6;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(math.pi / 4);
    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = _cCyan.withValues(alpha: 0.55 + pulse * 0.3);
    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: boxSize, height: boxSize),
      boxPaint,
    );
    canvas.restore();

    // Central crosshair
    final hair = Paint()
      ..color = _cGold.withValues(alpha: 0.75)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(cx - 10, cy), Offset(cx - 3, cy), hair);
    canvas.drawLine(Offset(cx + 3, cy), Offset(cx + 10, cy), hair);
    canvas.drawLine(Offset(cx, cy - 10), Offset(cx, cy - 3), hair);
    canvas.drawLine(Offset(cx, cy + 3), Offset(cx, cy + 10), hair);
    canvas.drawCircle(Offset(cx, cy), 1.5,
      Paint()..color = _cGold);

    // Four outer corner brackets (wider search area)
    _drawCornerBrackets(canvas, size,
      rect: Rect.fromCenter(
        center: Offset(cx, cy),
        width: size.width * 0.72,
        height: size.height * 0.55,
      ),
      color: _cCyan.withValues(alpha: 0.32),
      armLen: 22,
      thickness: 1.4,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 4  —  Mesh assembly (sci-fi version)
  // ═══════════════════════════════════════════════════════════════════════════
  /// Points rush in from off-screen and snap to landmark positions. Each
  /// point blooms (bright flash) when it lands. This is the signature moment.
  void _drawMeshAssembly(Canvas canvas, Size size) {
    final points = mesh!.points;
    final total  = points.length;
    final reveal = (progress / 0.6).clamp(0.0, 1.0); // 0..1 across scanning
    final visibleTarget = (total * reveal).floor();

    final dotPaint   = Paint()..style = PaintingStyle.fill;
    final trailPaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 0.7;
    final glowPaint  = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < total; i++) {
      final landed = i < visibleTarget;
      final p = points[i];
      final x = p.dx * size.width;
      final y = p.dy * size.height;

      if (!landed) {
        // Has this point begun its flight? Stagger by index.
        final begin = i / total * 0.9;
        if (reveal < begin) continue;
        // Local flight progress 0..1
        final local = ((reveal - begin) / 0.12).clamp(0.0, 1.0);
        // Origin on a random-ish point on the outside edge.
        final seed = i * 7.911;
        final edge = _hash(seed) * 4;
        final along = _hash(seed + 1);
        final Offset origin;
        if (edge < 1) {
          origin = Offset(along * size.width, -30);
        } else if (edge < 2) {
          origin = Offset(size.width + 30, along * size.height);
        } else if (edge < 3) {
          origin = Offset(along * size.width, size.height + 30);
        } else {
          origin = Offset(-30, along * size.height);
        }
        final eased = Curves.easeOutCubic.transform(local);
        final pos = Offset.lerp(origin, Offset(x, y), eased)!;

        // Trail
        final trailStart = Offset.lerp(origin, Offset(x, y), (eased - 0.25).clamp(0.0, 1.0))!;
        trailPaint.color = _cCyan.withValues(alpha: 0.45 * local);
        canvas.drawLine(trailStart, pos, trailPaint);

        // Dot
        dotPaint.color = _cCyanHi.withValues(alpha: 0.9 * local);
        canvas.drawCircle(pos, 1.6, dotPaint);
        continue;
      }

      // Landed — maintain positions with a brief bloom near the reveal edge
      final localEdge = (visibleTarget - i).toDouble();
      final blooming  = localEdge < 4;
      if (blooming) {
        final bloomLife = (1 - localEdge / 4).clamp(0.0, 1.0);
        glowPaint.color = _cWhite.withValues(alpha: 0.8 * bloomLife);
        canvas.drawCircle(Offset(x, y), 4.0 + bloomLife * 3, glowPaint);
      }
      dotPaint.color = _cCyan.withValues(alpha: 0.85);
      canvas.drawCircle(Offset(x, y), 1.3, dotPaint);
    }
  }

  /// Stable mesh dots (used in measuring + capturing after assembly done).
  void _drawMeshDots(Canvas canvas, Size size,
      {double alphaScale = 1.0, bool breath = false}) {
    final points = mesh!.points;
    final depths = mesh!.depths;
    final dotPaint = Paint()..style = PaintingStyle.fill;
    final b = breath ? (math.sin(animT * 1.5) * 0.15 + 1.0) : 1.0;

    // Pre-compute depth range so near/far mapping is stable per-frame.
    double zMin = 0, zMax = 0;
    if (depths != null && depths.isNotEmpty) {
      zMin = depths.reduce(math.min);
      zMax = depths.reduce(math.max);
      if (zMax - zMin < 1e-5) zMax = zMin + 1e-5;
    }

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final x = p.dx * size.width;
      final y = p.dy * size.height;

      // 3D PARALLAX — points closer to camera (smaller Z in MediaPipe's
      // convention) render brighter + bigger. Creates a volumetric feel
      // nobody else in this category uses because nobody reads Z off the
      // mesh. This IS a moat.
      double depthMul = 1.0;
      double depthAlpha = 1.0;
      if (depths != null && i < depths.length) {
        final z = depths[i];
        // Normalize so near = 1.0, far = 0.0
        final n = 1.0 - ((z - zMin) / (zMax - zMin)).clamp(0.0, 1.0);
        depthMul   = 0.7 + n * 0.9;   // size range 0.7x .. 1.6x
        depthAlpha = 0.45 + n * 0.75; // alpha range 0.45 .. 1.2
      }

      // Two-tone: nose bridge + eye landmarks in gold, rest cyan
      final isAnchor = i == 1 || i == 4 || i == 6 || i == 10 ||
                       i == 152 || i == 33 || i == 263;
      dotPaint.color = (isAnchor ? _cGoldHi : _cCyan)
          .withValues(alpha: (0.65 * alphaScale * depthAlpha).clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), 1.2 * b * depthMul, dotPaint);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 5  —  Mesh triangle wash (gossamer, large mesh only)
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawMeshTriangleWash(Canvas canvas, Size size) {
    final points = mesh!.points;
    if (points.length < 400) return; // Skip on fallback
    final revealBase = phase == ScanPhase.scanning
        ? ((progress - 0.35) / 0.25).clamp(0.0, 1.0)
        : 1.0;
    if (revealBase <= 0) return;

    // Reuse static edge list as line network — cheaper than true tri fill.
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = _cCyan.withValues(alpha: 0.18 * revealBase);

    for (final (a, b) in _faceMeshEdges) {
      if (a >= points.length || b >= points.length) continue;
      final pa = points[a];
      final pb = points[b];
      canvas.drawLine(
        Offset(pa.dx * size.width, pa.dy * size.height),
        Offset(pb.dx * size.width, pb.dy * size.height),
        linePaint,
      );
    }

    // Bright moving edge — a single cyan flash travels along a sub-loop
    // each cycle to give a "neural pulse" feel.
    final cyclePhase = (animT * 0.7) % 1.0;
    final pulseIdx = (cyclePhase * _faceMeshEdges.length).floor();
    final flashPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = _cCyanHi.withValues(alpha: 0.9 * revealBase);
    for (var i = 0; i < 6; i++) {
      final idx = (pulseIdx + i) % _faceMeshEdges.length;
      final (a, b) = _faceMeshEdges[idx];
      if (a >= points.length || b >= points.length) continue;
      final pa = points[a];
      final pb = points[b];
      flashPaint.color = _cCyanHi.withValues(
        alpha: (1 - i / 6) * 0.9 * revealBase);
      canvas.drawLine(
        Offset(pa.dx * size.width, pa.dy * size.height),
        Offset(pb.dx * size.width, pb.dy * size.height),
        flashPaint,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 6  —  Bone structure (X-ray reveal, gold)
  //  `dramatic`: 2.5x stroke, triple-blur glow halo, white core overlay
  //  `holdFull`: stay at full reveal (for rotate-prompt / post-measure)
  //  `profile`:  adds side-view-specific vectors (chin projection, malar line)
  //  `pulseBoost`: fast pulse for capture/analysing
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawBoneStructure(Canvas canvas, Size size, {
    bool pulseBoost = false,
    bool dramatic   = false,
  }) {
    final points = mesh!.points;
    if (points.length < 200) return;

    final reveal = phase == ScanPhase.measuring
        ? ((progress - 0.05) / 0.8).clamp(0.0, 1.0)
        : 1.0;
    if (reveal <= 0) return;

    Offset? px(int i) {
      if (i >= points.length) return null;
      final p = points[i];
      return Offset(p.dx * size.width, p.dy * size.height);
    }

    // Width multiplier — dramatic mode thickens everything by 2x+
    final wMul = dramatic ? 2.2 : 1.0;
    final glowMul = dramatic ? 4.8 : 3.5;

    final xrayPulse = pulseBoost
      ? (math.sin(animT * 4) * 0.12 + 0.88)
      : (math.sin(animT * 1.8) * 0.08 + 0.92);

    void chain(List<int> indices, double phaseStart, double phaseEnd,
        {double width = 2.2, double alpha = 1.0, Color? color}) {
      final local = ((reveal - phaseStart) / (phaseEnd - phaseStart)).clamp(0.0, 1.0);
      if (local <= 0) return;
      final pts = indices.map(px).whereType<Offset>().toList();
      if (pts.length < 2) return;

      final totalSegs = pts.length - 1;
      final drawSegs  = (totalSegs * local).floor();
      final partial   = (totalSegs * local) - drawSegs;
      final w = width * wMul;

      final c = color ?? _cGold;

      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (var i = 1; i <= drawSegs; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      if (drawSegs < totalSegs && partial > 0) {
        final a = pts[drawSegs];
        final b = pts[drawSegs + 1];
        path.lineTo(a.dx + (b.dx - a.dx) * partial,
                    a.dy + (b.dy - a.dy) * partial);
      }

      // 1. Outer soft halo (huge blur, low alpha)
      if (dramatic) {
        canvas.drawPath(path, Paint()
          ..color = c.withValues(alpha: alpha * 0.25 * xrayPulse)
          ..strokeWidth = w * glowMul * 1.3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
      }

      // 2. Medium blur halo
      canvas.drawPath(path, Paint()
        ..color = c.withValues(alpha: alpha * 0.55 * xrayPulse)
        ..strokeWidth = w * glowMul
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, dramatic ? 5 : 3));

      // 3. Main gold line (crisp)
      canvas.drawPath(path, Paint()
        ..color = c.withValues(alpha: alpha * xrayPulse)
        ..strokeWidth = w
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);

      // 4. Cyan undercore (offset subtly — chromatic aberration / neon feel)
      if (dramatic) {
        canvas.drawPath(path, Paint()
          ..color = _cCyanHi.withValues(alpha: alpha * 0.35 * xrayPulse)
          ..strokeWidth = w * 0.55
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2));
      }

      // 5. Bright white core (makes lines feel incandescent)
      if (dramatic) {
        canvas.drawPath(path, Paint()
          ..color = _cWhite.withValues(alpha: alpha * 0.65)
          ..strokeWidth = w * 0.35
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
      }

      // Leading tip flare — bright white at the drawing edge
      if (drawSegs < totalSegs && partial > 0 && partial < 0.95) {
        final a = pts[drawSegs];
        final b = pts[drawSegs + 1];
        final tip = Offset(
          a.dx + (b.dx - a.dx) * partial,
          a.dy + (b.dy - a.dy) * partial);
        canvas.drawCircle(tip, dramatic ? 6 : 3.5,
          Paint()..color = _cWhite);
        canvas.drawCircle(tip, dramatic ? 14 : 7, Paint()
          ..color = c.withValues(alpha: 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        // Outer radiant ring — gives the "moment of contact" feel
        if (dramatic) {
          canvas.drawCircle(tip, 22, Paint()
            ..color = c.withValues(alpha: 0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
        }
      }

      // Joint pips — thicker in dramatic mode
      final pipRadius = dramatic ? 2.8 : 1.8;
      final pipGlowR  = dramatic ? 6.5 : 3.5;
      final pipPaint = Paint()
        ..color = c.withValues(alpha: 0.95 * xrayPulse)
        ..style = PaintingStyle.fill;
      final pipGlow = Paint()
        ..color = c.withValues(alpha: 0.4 * xrayPulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
        ..style = PaintingStyle.fill;
      for (var i = 0; i < drawSegs + 1 && i < pts.length; i++) {
        canvas.drawCircle(pts[i], pipGlowR, pipGlow);
        canvas.drawCircle(pts[i], pipRadius, pipPaint);
      }
    }

    // Mandible — defining bone. First, thickest, widest.
    chain(const [
      234, 93, 132, 58, 172, 136, 150, 149, 176, 148, 152,
      377, 400, 378, 379, 365, 397, 288, 361, 323, 454,
    ], 0.00, 0.28, width: 2.8);

    // Zygomatic L/R
    chain(const [234, 227, 116, 123, 117, 118, 101], 0.20, 0.45, width: 2.0);
    chain(const [454, 447, 345, 352, 346, 347, 330], 0.20, 0.45, width: 2.0);

    // Orbital frame L
    chain(const [
      33, 246, 161, 160, 159, 158, 157, 173, 133, 155, 154, 153, 145, 144, 163, 7, 33,
    ], 0.35, 0.60, width: 1.6, alpha: 0.85);
    // Orbital frame R
    chain(const [
      263, 466, 388, 387, 386, 385, 384, 398, 362, 382, 381, 380, 374, 373, 390, 249, 263,
    ], 0.35, 0.60, width: 1.6, alpha: 0.85);

    // Frontal bone sweep
    chain(const [70, 63, 105, 66, 107, 9, 336, 296, 334, 293, 300],
        0.50, 0.72, width: 1.8);

    // Nose bridge
    chain(const [168, 6, 197, 195, 5, 4, 1], 0.55, 0.78, width: 1.9);

    // Chin vector
    chain(const [152, 175, 199, 200, 18], 0.65, 0.85, width: 2.2);

    // Hairline pips — final lockup
    if (reveal > 0.82) {
      final anchorAlpha = ((reveal - 0.82) / 0.18).clamp(0.0, 1.0);
      final anchorPaint = Paint()
        ..color = _cGoldHi.withValues(alpha: 0.9 * anchorAlpha * xrayPulse)
        ..style = PaintingStyle.fill;
      final anchorGlow = Paint()
        ..color = _cGold.withValues(alpha: 0.55 * anchorAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
        ..style = PaintingStyle.fill;
      const hair = [10, 109, 67, 103, 54, 21, 162, 127,
                    356, 389, 251, 284, 332, 297, 338];
      for (final i in hair) {
        final p = px(i);
        if (p != null) {
          canvas.drawCircle(p, dramatic ? 8 : 5, anchorGlow);
          canvas.drawCircle(p, dramatic ? 3 : 2, anchorPaint);
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 6b  —  Floating live measurement readouts (numbers at anchors)
  //  These are the numbers animating next to the mesh, terminal-style. Each
  //  appears when its reveal phase begins, with a slight flicker to read as
  //  "live data streaming in."
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawFloatingMeasurements(Canvas canvas, Size size) {
    final points = mesh!.points;
    if (points.length < 200) return;
    final reveal = ((progress - 0.55) / 0.35).clamp(0.0, 1.0);
    if (reveal <= 0) return;

    Offset? px(int i) {
      if (i >= points.length) return null;
      final p = points[i];
      return Offset(p.dx * size.width, p.dy * size.height);
    }

    // Fake-live values modulated so they feel alive. These visually SELL
    // the precision — the verdict/real data in the report comes from backend.
    final canthal = (3.0 + math.sin(animT * 2.1) * 0.12);
    final jaw     = (118 + math.sin(animT * 1.6) * 0.6);
    final fwhr    = (1.87 + math.sin(animT * 1.9) * 0.015);
    final sym     = (87  + math.sin(animT * 1.3) * 0.8);

    final readouts = <(Offset?, String, double)>[
      (px(FaceMesh.idxLeftEyeOuter),  'CANTHAL ${canthal.toStringAsFixed(2)}°', 0.00),
      (px(FaceMesh.idxChin),          'JAW ${jaw.toStringAsFixed(0)}°',         0.20),
      (px(FaceMesh.idxCheekL),        'FWHR ${fwhr.toStringAsFixed(2)}',        0.40),
      (px(FaceMesh.idxCheekR),        'SYM ${sym.toStringAsFixed(0)}%',         0.60),
    ];

    for (final (anchor, text, delay) in readouts) {
      if (anchor == null) continue;
      final local = ((reveal - delay) / 0.25).clamp(0.0, 1.0);
      if (local <= 0) continue;

      // Flicker effect — reads as "data streaming in"
      final flicker = (math.sin(animT * 18 + anchor.dx) + 1) / 2;
      final alpha = local * (0.75 + flicker * 0.25);

      _drawTerminalReadout(canvas, anchor, text, alpha);
    }
  }

  void _drawTerminalReadout(Canvas canvas, Offset anchor, String text, double alpha) {
    // Position text slightly offset from anchor
    final pos = Offset(anchor.dx + 14, anchor.dy - 8);

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: _cGoldHi.withValues(alpha: alpha),
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          fontFamilyFallback: const ['monospace'],
          shadows: [
            Shadow(
              color: _cGold.withValues(alpha: alpha * 0.6),
              blurRadius: 4,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Dark underlay pill for legibility on light skin
    final rect = Rect.fromLTWH(
      pos.dx - 4, pos.dy - 2, tp.width + 8, tp.height + 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = Colors.black.withValues(alpha: alpha * 0.55),
    );
    tp.paint(canvas, pos);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 6c  —  THE LOCK STRIKE (signature moment)
  //  Fires at the climax of measuring (progress >= 0.9). Full-screen
  //  vignette flash + ring shockwave from face center + "◆ LOCK ◆" label.
  //  This is the beat that lands on a 10-second TikTok. Don't skip.
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawLockStrike(Canvas canvas, Size size) {
    // Strike intensity — peaks right at progress=0.9 then fades.
    final strikeT = ((progress - 0.90) / 0.10).clamp(0.0, 1.0);
    // Ease-out envelope — sharp in, slow fade
    final envelope = 1 - math.pow(1 - strikeT, 2).toDouble();

    // 1. Full-screen gold vignette flash
    final vignette = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.2,
        colors: [
          Colors.transparent,
          _cGold.withValues(alpha: 0.0),
          _cGold.withValues(alpha: 0.28 * (1 - strikeT)),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height), vignette);

    // 2. Center-screen bright starburst
    final cx = size.width / 2;
    final cy = size.height * 0.45;
    final burstR = 30 + envelope * 80;
    canvas.drawCircle(Offset(cx, cy), burstR * 0.3, Paint()
      ..color = _cWhite.withValues(alpha: 0.85 * (1 - strikeT)));
    canvas.drawCircle(Offset(cx, cy), burstR, Paint()
      ..color = _cGold.withValues(alpha: 0.55 * (1 - strikeT))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    canvas.drawCircle(Offset(cx, cy), burstR * 2.4, Paint()
      ..color = _cGold.withValues(alpha: 0.22 * (1 - strikeT))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22));

    // 3. Expanding ring shockwave
    final ringR = envelope * math.min(size.width, size.height) * 0.8;
    final ringAlpha = (1 - envelope) * 0.9;
    if (ringAlpha > 0.02) {
      canvas.drawCircle(Offset(cx, cy), ringR, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 + (1 - envelope) * 3
        ..color = _cGoldHi.withValues(alpha: ringAlpha));
      canvas.drawCircle(Offset(cx, cy), ringR * 1.08, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _cGold.withValues(alpha: ringAlpha * 0.55));
    }

    // 4. "◆ LOCK ◆" label pulse, center-top
    final labelT = ((strikeT - 0.05) / 0.3).clamp(0.0, 1.0);
    final labelOpacity = labelT * (1 - (strikeT - 0.3).clamp(0.0, 0.7) / 0.7);
    if (labelOpacity > 0.05) {
      final scale = 0.8 + labelT * 0.3;
      canvas.save();
      canvas.translate(cx, size.height * 0.25);
      canvas.scale(scale, scale);
      final tp = TextPainter(
        text: TextSpan(
          text: '◆ LOCK ◆',
          style: TextStyle(
            color: _cGoldHi.withValues(alpha: labelOpacity),
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: 8,
            fontFamilyFallback: const ['monospace'],
            shadows: [
              Shadow(
                color: _cGold.withValues(alpha: labelOpacity * 0.8),
                blurRadius: 16,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 7  —  Measurement callouts (leader lines → corner labels)
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawMeasurementCallouts(Canvas canvas, Size size) {
    final points = mesh!.points;
    if (points.length < 200) return;
    final reveal = ((progress - 0.4) / 0.5).clamp(0.0, 1.0);
    if (reveal <= 0) return;

    Offset? px(int i) {
      if (i >= points.length) return null;
      final p = points[i];
      return Offset(p.dx * size.width, p.dy * size.height);
    }

    // Anchor → corner endpoint → label text
    final callouts = <(Offset? anchor, Offset corner, String label, double delay)>[
      (px(FaceMesh.idxLeftEyeOuter),  Offset(size.width * 0.08, size.height * 0.20),
        'CANTHAL +3.1°',  0.05),
      (px(FaceMesh.idxRightEyeOuter), Offset(size.width * 0.92, size.height * 0.22),
        'SYMMETRY 87%',   0.20),
      (px(FaceMesh.idxCheekL),        Offset(size.width * 0.06, size.height * 0.62),
        'FWHR 1.87',      0.35),
      (px(FaceMesh.idxCheekR),        Offset(size.width * 0.94, size.height * 0.60),
        'THIRDS 33/33/34', 0.48),
      (px(FaceMesh.idxChin),          Offset(size.width * 0.90, size.height * 0.86),
        'JAW 118°',       0.62),
      (px(FaceMesh.idxNoseTip),       Offset(size.width * 0.10, size.height * 0.86),
        'CHIN +3.4mm',    0.75),
    ];

    for (final (anchor, corner, label, delay) in callouts) {
      if (anchor == null) continue;
      final local = ((reveal - delay) / 0.25).clamp(0.0, 1.0);
      if (local <= 0) continue;
      _drawLeaderCallout(canvas, anchor, corner, label, local);
    }
  }

  void _drawLeaderCallout(Canvas canvas, Offset anchor, Offset corner, String label, double t) {
    // Mid-elbow point — path goes anchor → elbow → corner, then label.
    final elbow = Offset(
      corner.dx + (anchor.dx - corner.dx) * 0.35,
      corner.dy,
    );

    final leaderEnd = Offset.lerp(anchor, elbow, t)!;
    final cornerEnd = t > 0.6 ? Offset.lerp(elbow, corner, (t - 0.6) / 0.4)! : elbow;

    final linePaint = Paint()
      ..color = _cGold.withValues(alpha: 0.85 * t)
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(anchor, leaderEnd, linePaint);
    if (t > 0.6) canvas.drawLine(elbow, cornerEnd, linePaint);

    // Anchor node pulse
    final pulse = (math.sin(animT * 4 + anchor.dx) + 1) / 2;
    canvas.drawCircle(anchor, 2.4,
      Paint()..color = _cWhite.withValues(alpha: 0.85 * t));
    canvas.drawCircle(anchor, 5 + pulse * 3,
      Paint()..color = _cGold.withValues(alpha: 0.25 * t));

    // Typewriter label
    if (t > 0.75) {
      final charCount = ((t - 0.75) / 0.25 * label.length).ceil().clamp(0, label.length);
      final shown = label.substring(0, charCount);
      _drawLabelBoxed(canvas, corner, shown,
        anchorRight: corner.dx > 0.5 /* not used for side yet */ ? true : false);
    }
  }

  void _drawLabelBoxed(Canvas canvas, Offset pos, String text, {bool anchorRight = true}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: _cGold,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
          fontFamilyFallback: ['monospace'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final pad = const EdgeInsets.symmetric(horizontal: 6, vertical: 3);
    final rect = Rect.fromLTWH(
      pos.dx - (anchorRight ? 0 : tp.width + pad.horizontal),
      pos.dy - tp.height / 2 - pad.vertical / 2,
      tp.width + pad.horizontal,
      tp.height + pad.vertical,
    );

    canvas.drawRect(rect,
      Paint()..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawRect(rect, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = _cGold.withValues(alpha: 0.55));

    tp.paint(canvas, Offset(rect.left + pad.left, rect.top + pad.top));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 8  —  Radar shockwave rings
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawRadarRings(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.45;
    final cycle = (animT * 0.5) % 1.0;
    for (var i = 0; i < 3; i++) {
      final t = (cycle + i / 3) % 1.0;
      final r = 30 + t * 200;
      final alpha = (1 - t) * 0.35;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 + (1 - t) * 1.5
        ..color = _cGold.withValues(alpha: alpha);
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 9  —  Scan line sweep
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawScanSweep(Canvas canvas, Size size) {
    // Cycle once per 2.2 s, vertical sweep top → bottom with trailing band
    final t = (animT * 0.45) % 1.0;
    final y = size.height * (0.08 + 0.84 * t);

    // Band
    final bandShader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [
        Colors.transparent,
        _cCyan.withValues(alpha: 0.18),
        _cCyanHi.withValues(alpha: 0.55),
        _cCyan.withValues(alpha: 0.18),
        Colors.transparent,
      ],
      stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
    ).createShader(Rect.fromLTWH(0, y - 48, size.width, 96));
    canvas.drawRect(Rect.fromLTWH(0, y - 48, size.width, 96),
      Paint()..shader = bandShader);

    // Bright line
    final linePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          _cCyanHi.withValues(alpha: 0.95),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, y - 1, size.width, 2))
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);

    // Particle trail behind the line
    final trailPaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 22; i++) {
      final seed = i * 11.7;
      final px = _hash(seed) * size.width;
      final offsetY = 2 + _hash(seed + 3) * 16;
      final r = 0.8 + _hash(seed + 7) * 1.4;
      trailPaint.color = _cCyanHi.withValues(alpha: 0.55 - offsetY / 30);
      canvas.drawCircle(Offset(px, y - offsetY), r, trailPaint);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 10  —  Face-lock corner brackets
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawFaceLockBrackets(Canvas canvas, Size size,
      {double intensity = 1.0, bool snap = false}) {
    if (mesh == null || mesh!.points.length < 100) return;
    // Bounding box of detected mesh points
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final p in mesh!.points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final rect = Rect.fromLTRB(
      (minX * size.width) - 14,
      (minY * size.height) - 14,
      (maxX * size.width) + 14,
      (maxY * size.height) + 14,
    );

    // Snap-in animation when capturing: brackets come in from outside
    double extra = 0;
    if (snap) {
      final snapT = ((animT * 3) % 1.0);
      extra = (1 - snapT).clamp(0.0, 1.0) * 24;
    }
    final snappedRect = rect.inflate(extra);

    _drawCornerBrackets(canvas, size,
      rect: snappedRect,
      color: _cGold.withValues(alpha: 0.85 * intensity),
      armLen: 18,
      thickness: 2,
    );

    // Small status text near top-left of the bracket
    final tp = TextPainter(
      text: TextSpan(
        text: 'FACE LOCK ◉',
        style: TextStyle(
          color: _cGold.withValues(alpha: 0.85 * intensity),
          fontSize: 8,
          fontWeight: FontWeight.w800,
          letterSpacing: 2.4,
          fontFamilyFallback: const ['monospace'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(rect.left, rect.top - 14));
  }

  void _drawCornerBrackets(Canvas canvas, Size size, {
    required Rect rect,
    required Color color,
    required double armLen,
    required double thickness,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.square;
    // Top-left
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(armLen, 0), paint);
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(0, armLen), paint);
    // Top-right
    canvas.drawLine(rect.topRight, rect.topRight + Offset(-armLen, 0), paint);
    canvas.drawLine(rect.topRight, rect.topRight + Offset(0, armLen), paint);
    // Bottom-left
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + Offset(armLen, 0), paint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + Offset(0, -armLen), paint);
    // Bottom-right
    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(-armLen, 0), paint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(0, -armLen), paint);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 11  —  Top ticker (animated marquee)
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawTopTicker(Canvas canvas, Size size, String text) {
    // Render at ~12% height — under the safe-area top bar (SafeArea content
    // is in the scan widget stack, not here; we offset slightly for design).
    final y = 92.0;

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: _cCyan.withValues(alpha: 0.85),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.2,
          fontFamilyFallback: const ['monospace'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Background pill
    final pillRect = Rect.fromCenter(
      center: Offset(size.width / 2, y),
      width: tp.width + 26, height: tp.height + 10,
    );
    final rrect = RRect.fromRectAndRadius(pillRect, const Radius.circular(100));
    canvas.drawRRect(rrect,
      Paint()..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawRRect(rrect, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = _cCyan.withValues(alpha: 0.35));

    // Pulse dot on the left
    final pulse = (math.sin(animT * 4) + 1) / 2;
    canvas.drawCircle(
      Offset(pillRect.left + 10, y),
      2.2 + pulse * 1.2,
      Paint()..color = _cCyan.withValues(alpha: 0.7 + pulse * 0.3),
    );

    tp.paint(canvas,
      Offset(pillRect.left + 20, y - tp.height / 2));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 11b  —  Bottom measurement stream (live ticker)
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawBottomMeasurementStream(Canvas canvas, Size size) {
    // Near the bottom edge, above the phase HUD.
    final y = size.height - 130;

    // Fake live-stream values modulated by animT so it feels alive.
    final values = <String>[
      'CANTHAL ${(3.0 + math.sin(animT * 2) * 0.15).toStringAsFixed(2)}°',
      'SYM ${(87 + math.sin(animT * 1.5) * 1.2).toStringAsFixed(1)}%',
      'FWHR ${(1.87 + math.sin(animT * 1.8) * 0.02).toStringAsFixed(2)}',
      'JAW ${(118 + math.sin(animT * 1.3) * 0.8).toStringAsFixed(0)}°',
      'CHIN +${(3.4 + math.sin(animT * 1.6) * 0.1).toStringAsFixed(1)}mm',
      'THIRDS 33/33/34',
    ];
    final text = values.join('   ·   ');

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: _cGold.withValues(alpha: 0.75),
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.8,
          fontFamilyFallback: const ['monospace'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Scrolling marquee — shift with animT
    final shift = (animT * 28) % (tp.width + 80);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, y - 12, size.width, 20));
    tp.paint(canvas, Offset(size.width - shift, y));
    tp.paint(canvas, Offset(size.width - shift + tp.width + 80, y));
    canvas.restore();

    // Fade edges
    final fadeLeft = Paint()
      ..shader = LinearGradient(
        colors: [Colors.black, Colors.transparent],
      ).createShader(Rect.fromLTWH(0, y - 12, 40, 20));
    canvas.drawRect(Rect.fromLTWH(0, y - 12, 40, 20), fadeLeft);
    final fadeRight = Paint()
      ..shader = LinearGradient(
        colors: [Colors.transparent, Colors.black],
      ).createShader(Rect.fromLTWH(size.width - 40, y - 12, 40, 20));
    canvas.drawRect(Rect.fromLTWH(size.width - 40, y - 12, 40, 20), fadeRight);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 12  —  Capture aperture + glitch countdown
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawCaptureAperture(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.86,
      height: size.height * 0.75,
    );

    // Dashed outer frame rotating subtly
    final dashPaint = Paint()
      ..color = _cMagenta.withValues(alpha: 0.75)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    _drawDashedRRect(canvas,
      RRect.fromRectAndRadius(rect, const Radius.circular(18)),
      dashPaint, dash: 9, gap: 6);

    // Inner hairline
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(6), const Radius.circular(14)),
      Paint()
        ..color = _cGold.withValues(alpha: 0.55)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawDashedRRect(Canvas canvas, RRect rrect, Paint paint,
      {required double dash, required double gap}) {
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    for (final m in metrics) {
      double distance = 0;
      while (distance < m.length) {
        final seg = m.extractPath(distance, distance + dash);
        canvas.drawPath(seg, paint);
        distance += dash + gap;
      }
    }
  }

  void _drawGlitchCountdown(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final base = TextStyle(
      fontSize: 120,
      fontWeight: FontWeight.w800,
      letterSpacing: -6,
      height: 1,
      fontFamilyFallback: const ['monospace'],
    );

    // RGB split layers (chromatic aberration)
    final shake = math.sin(animT * 60) * 2;
    final r = TextPainter(
      text: TextSpan(text: '$countdown',
        style: base.copyWith(color: _cMagenta.withValues(alpha: 0.85))),
      textDirection: TextDirection.ltr,
    )..layout();
    final g = TextPainter(
      text: TextSpan(text: '$countdown',
        style: base.copyWith(color: _cCyanHi.withValues(alpha: 0.85))),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = TextPainter(
      text: TextSpan(text: '$countdown',
        style: base.copyWith(color: _cWhite)),
      textDirection: TextDirection.ltr,
    )..layout();

    r.paint(canvas, Offset(cx - w.width / 2 - 3 + shake, cy - w.height / 2));
    g.paint(canvas, Offset(cx - w.width / 2 + 3 - shake, cy - w.height / 2));
    w.paint(canvas, Offset(cx - w.width / 2, cy - w.height / 2));

    // Scan-glitch bar
    final glitchOn = math.sin(animT * 22) > 0.82;
    if (glitchOn) {
      final gy = cy - w.height / 2 + _hash(animT * 0.9) * w.height;
      canvas.drawRect(
        Rect.fromLTWH(cx - w.width / 2 - 10, gy, w.width + 20, 6),
        Paint()..color = _cCyanHi.withValues(alpha: 0.5)
          ..blendMode = BlendMode.plus,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 13  —  Analysing shockwaves
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawAnalysingShockwaves(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Three concentric shockwaves
    final cycle = (animT * 0.6) % 1.0;
    for (var i = 0; i < 4; i++) {
      final t = (cycle + i / 4) % 1.0;
      final r = 20 + t * 260;
      final alpha = (1 - t) * 0.4;
      canvas.drawCircle(Offset(cx, cy), r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 + (1 - t) * 2
        ..color = _cGold.withValues(alpha: alpha));
    }

    // Center starburst
    final pulse = (math.sin(animT * 4) + 1) / 2;
    canvas.drawCircle(Offset(cx, cy), 6 + pulse * 5,
      Paint()..color = _cWhite.withValues(alpha: 0.9));
    canvas.drawCircle(Offset(cx, cy), 14 + pulse * 10, Paint()
      ..color = _cGold.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));

    // Radial sweep lines
    for (var i = 0; i < 12; i++) {
      final a = (animT * 0.8) + i * (math.pi / 6);
      final p1 = Offset(cx + math.cos(a) * 18, cy + math.sin(a) * 18);
      final p2 = Offset(cx + math.cos(a) * 38, cy + math.sin(a) * 38);
      canvas.drawLine(p1, p2, Paint()
        ..color = _cGold.withValues(alpha: 0.6)
        ..strokeWidth = 1.2);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Utilities
  // ═══════════════════════════════════════════════════════════════════════════
  int _visibleCount() {
    if (mesh == null) return 0;
    final total = mesh!.points.length;
    final reveal = (progress / 0.6).clamp(0.0, 1.0);
    return (total * reveal).floor();
  }

  /// Deterministic pseudo-random 0..1 from a seed. Used for ambient particles
  /// + any place we want stable "randomness" across frames.
  double _hash(double seed) {
    final x = math.sin(seed * 12.9898) * 43758.5453;
    return x - x.floorToDouble();
  }

  @override
  bool shouldRepaint(GeometryOverlayPainter old) =>
      old.mesh         != mesh       ||
      old.phase        != phase      ||
      old.progress     != progress   ||
      old.countdown    != countdown  ||
      old.animT        != animT      ||
      old.lockProgress != lockProgress;
}

// ── Static MediaPipe face mesh edge subset (~80 edges covering face oval,
//     eyes, eyebrows, nose, lips — the skeleton, not full 2000+ edges) ───────
const List<(int, int)> _faceMeshEdges = [
  // Face oval (partial)
  (10, 338), (338, 297), (297, 332), (332, 284), (284, 251), (251, 389),
  (389, 356), (356, 454), (454, 323), (323, 361), (361, 288), (288, 397),
  (397, 365), (365, 379), (379, 378), (378, 400), (400, 377), (377, 152),
  (152, 148), (148, 176), (176, 149), (149, 150), (150, 136), (136, 172),
  (172, 58), (58, 132), (132, 93), (93, 234), (234, 127), (127, 162),
  (162, 21), (21, 54), (54, 103), (103, 67), (67, 109), (109, 10),

  // Left eye
  (33, 7), (7, 163), (163, 144), (144, 145), (145, 153), (153, 154),
  (154, 155), (155, 133), (133, 173), (173, 157), (157, 158), (158, 159),
  (159, 160), (160, 161), (161, 246), (246, 33),

  // Right eye
  (263, 249), (249, 390), (390, 373), (373, 374), (374, 380), (380, 381),
  (381, 382), (382, 362), (362, 398), (398, 384), (384, 385), (385, 386),
  (386, 387), (387, 388), (388, 466), (466, 263),

  // Left eyebrow
  (70, 63), (63, 105), (105, 66), (66, 107),
  // Right eyebrow
  (300, 293), (293, 334), (334, 296), (296, 336),

  // Nose bridge
  (168, 6), (6, 197), (197, 195), (195, 5), (5, 4), (4, 1),

  // Outer lips
  (61, 146), (146, 91), (91, 181), (181, 84), (84, 17), (17, 314),
  (314, 405), (405, 321), (321, 375), (375, 291), (291, 409), (409, 270),
  (270, 269), (269, 267), (267, 0), (0, 37), (37, 39), (39, 40), (40, 185), (185, 61),
];
