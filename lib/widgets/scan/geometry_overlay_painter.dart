import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/face_geometry.dart';
import '../../services/face_mesh_service.dart';

/// Multi-angle Face-ID-style scan. Front, then left 3/4, then right 3/4 —
/// each lock → measure → capture. The dramatic bone overlay fires on every
/// angle. Users experience it as a thorough clinical capture, not a gimmick.
enum ScanPhase {
  searching,     // no face yet — generic or for next angle
  scanning,      // mesh assembly
  measuring,     // bone reveal + lock strike
  rotateLeft,    // cue: "turn slowly LEFT"
  rotateRight,   // cue: "turn slowly RIGHT"
  capturing,     // final capture moment
  analysing,     // send all 3 images + full geometry to backend
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

  // Face-ID style guide state — drives oval color + status text + hold stroke
  final String statusText;
  final String statusColor; // 'idle' | 'adjusting' | 'locked'
  final double holdProgress; // 0..1

  // When true, swap LEFT/RIGHT in user-facing direction cues (rotate arrow +
  // ticker text). Android front-cam preview is NOT auto-mirrored at the
  // platform level the way iOS is, so the user perceives the opposite turn
  // direction. Caller passes `Platform.isAndroid` here.
  final bool mirrorLR;

  // Informational — true when the upstream produced a real 468-point
  // MediaPipe mesh (Android). iOS produces a synthesised semantic mesh
  // from contours instead. No layer currently gates on this — left as
  // a hint for future features that genuinely need real topology.
  final bool denseMesh;

  // Real measured geometry from FaceGeometryService.computeGeometry,
  // recomputed each frame in scan_screen. The painter uses these
  // values for the live HUD readouts (rails, floating measurements,
  // bottom marquee) so what the user sees is what the report will
  // analyse — not a sine-wave decoration.
  final FaceGeometry? geometry;

  /// Optional face bounding-box in screen-pixel space. When non-null,
  /// the Face-ID oval guide and any other decorative elements that
  /// would normally lock to the screen centre re-anchor here so they
  /// follow the actual face. Used on iOS during side-profile scans
  /// where the face naturally drifts off-centre as the user rotates
  /// — without this the green oval floats in empty space while the
  /// face hangs off to one side (the bug in the iOS side-profile
  /// screenshots).
  /// Pass null on Android — Android's behaviour is byte-identical
  /// to before this field existed.
  final Rect? faceBox;

  const GeometryOverlayPainter({
    required this.mesh,
    required this.phase,
    required this.progress,
    required this.animT,
    this.lockProgress = 0,
    this.countdown = 0,
    this.statusText = '',
    this.statusColor = 'idle',
    this.holdProgress = 0,
    this.mirrorLR = false,
    this.denseMesh = false,
    this.geometry,
    this.faceBox,
  });

  // ── Palette ───────────────────────────────────────────────────────────────
  // Debloat rebrand: the old gold anchor accents are recoloured to deep /
  // ice blue so the whole scan reads as one cool blue system (no gold).
  // Names kept so the ~dozen call-sites don't churn.
  static const _cGold    = Color(0xFF0EA5E9); // was gold → deep blue
  static const _cGoldHi  = Color(0xFF7DD3FC); // was gold-hi → ice blue
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

    // ── Face-ID oval guide — drawn during positioning phases ────────────
    // This is the primary instructional element. Everything else layers on.
    final showOvalGuide = phase == ScanPhase.searching
        || phase == ScanPhase.scanning
        || phase == ScanPhase.rotateLeft
        || phase == ScanPhase.rotateRight;
    if (showOvalGuide) {
      _drawFaceOvalGuide(canvas, size);
      _drawStatusCoachText(canvas, size);
    }

    // ── Phase-specific stack ────────────────────────────────────────────
    switch (phase) {
      case ScanPhase.searching:
        _drawSearchingReticle(canvas, size);
        break;

      case ScanPhase.scanning:
        if (mesh != null && mesh!.isValid) {
          _drawMeshAssembly(canvas, size);
          _drawMeshTriangleWash(canvas, size);
          _drawLiveMeasurementLines(canvas, size);  // NEW — horizontal rails
          _drawScanSweep(canvas, size);
          _drawFaceLockBrackets(canvas, size, intensity: 0.6);
        }
        _drawBottomMeasurementStream(canvas, size);
        break;

      case ScanPhase.measuring:
        if (mesh != null && mesh!.isValid) {
          _drawFaceSilhouetteGlow(canvas, size);      // glowing gold oval
          // Keep the mesh RICH throughout — previously dimmed to 0.55 but
          // user wants the opening density maintained.
          _drawMeshDots(canvas, size, alphaScale: 1.0);
          _drawMeshTriangleWash(canvas, size);
          _drawBoneStructure(canvas, size, dramatic: true);
          _drawMeasurementArcs(canvas, size);         // jaw / canthal / FWHR arcs
          _drawConstellation(canvas, size);           // twinkling anchor stars
          _drawFeatureBeam(canvas, size);             // sweeping feature scan
          _drawLiveMeasurementLines(canvas, size);    // sci-fi horizontal rails
          _drawDigitalRain(canvas, size);             // numbers streaming
          _drawFloatingMeasurements(canvas, size);
          _drawRadarRings(canvas, size);
          _drawFaceLockBrackets(canvas, size, intensity: 1.0);
          // Signature LOCK STRIKE at the climax of measuring — holds longer
          // now (0.85 → 1.0, up from 0.90) so users actually see it.
          if (progress >= 0.85) _drawLockStrike(canvas, size);
        }
        _drawTopTicker(canvas, size,
          progress >= 0.90
            ? '◆ LOCK ACQUIRED  ·  EVERY MM MAPPED'
            : '◉ YOUR BONES, READ  ·  LOCKING YOUR ARCHETYPE');
        _drawBottomMeasurementStream(canvas, size);
        break;

      case ScanPhase.rotateLeft:
      case ScanPhase.rotateRight:
        if (mesh != null && mesh!.isValid) {
          _drawMeshDots(canvas, size, alphaScale: 0.3);
          _drawBoneStructure(canvas, size, dramatic: true);
        }
        // On Android, front-cam preview isn't auto-mirrored, so the user
        // sees themselves the way a stranger would. Swap LEFT/RIGHT in the
        // arrow direction + ticker text to match what they physically need.
        final bool wantLeftCue = (phase == ScanPhase.rotateLeft) ^ mirrorLR;
        _drawRotateCue(canvas, size, leftwards: wantLeftCue);
        _drawTopTicker(canvas, size,
          wantLeftCue
            ? '↺ TURN SLOWLY LEFT · PROFILE INCOMING'
            : '↻ TURN SLOWLY RIGHT · CAPTURING LAST ANGLE');
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
  //  Face-ID oval guide + coaching text (Apple / Jumio / Yoti pattern)
  //  - 72% screen-width portrait oval, centered at 45% screen height
  //  - Stroke color tracks status: idle (grey) → adjusting (amber) →
  //    locked (green)
  //  - Hold-progress animates a bright stroke around the perimeter
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawFaceOvalGuide(Canvas canvas, Size size) {
    final Rect rect;
    if (faceBox != null) {
      // Face-anchored mode (iOS side-profile scans). Inflate the
      // detected face bbox by ~16% so the oval frames the head with
      // a comfortable margin instead of clipping the hairline. This
      // makes the green guide ring TRACK THE FACE during rotation
      // rather than floating in empty screen space.
      final bbox = faceBox!;
      final padX = bbox.width  * 0.16;
      final padY = bbox.height * 0.20;
      rect = Rect.fromCenter(
        center: bbox.center,
        width:  bbox.width  + padX * 2,
        height: bbox.height + padY * 2,
      );
    } else {
      // Default (Android, and iOS front-on): screen-locked
      // 72% × 96% portrait oval. Unchanged from the original impl.
      final scx = size.width / 2;
      final scy = size.height * 0.45;
      final ovalW = size.width * 0.72;
      final ovalH = size.width * 0.96;  // portrait ratio ~1:1.33
      rect = Rect.fromCenter(
        center: Offset(scx, scy), width: ovalW, height: ovalH);
    }

    // Locals derived from `rect` so the tick-mark loop and any other
    // ring-following math below work regardless of which branch built
    // the rect (face-anchored vs screen-locked).
    final cx    = rect.center.dx;
    final cy    = rect.center.dy;
    final ovalW = rect.width;
    final ovalH = rect.height;

    // Color by status — matches research guide (idle/adjusting/locked)
    const idleColor      = Color(0xFF8A8F98);
    const adjustingColor = Color(0xFFFFC857);
    const lockedColor    = Color(0xFF2ECC71);
    final Color stateColor = statusColor == 'locked' ? lockedColor
                           : statusColor == 'adjusting' ? adjustingColor
                           : idleColor;

    // Scrim outside the oval — dims the rest of the frame so attention lands
    // on the face zone. Classic ID-capture move.
    final scrim = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(scrim, Paint()
      ..color = Colors.black.withValues(alpha: 0.35));

    // Base idle stroke
    canvas.drawOval(rect, Paint()
      ..color = stateColor.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8);

    // Hold-progress stroke — sweeps around the oval as user holds still.
    // Starts at the top (12 o'clock) and goes clockwise.
    if (holdProgress > 0.01 && statusColor == 'locked') {
      final progressPaint = Paint()
        ..color = lockedColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.6
        ..strokeCap = StrokeCap.round;
      final glowPaint = Paint()
        ..color = lockedColor.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

      const start = -math.pi / 2;
      final sweep = 2 * math.pi * holdProgress;
      canvas.drawArc(rect, start, sweep, false, glowPaint);
      canvas.drawArc(rect, start, sweep, false, progressPaint);
    }

    // Small 12-tick marks around the oval for biometric feel
    final tickPaint = Paint()
      ..color = stateColor.withValues(alpha: 0.45)
      ..strokeWidth = 1.2;
    final rx = ovalW / 2;
    final ry = ovalH / 2;
    for (var i = 0; i < 24; i++) {
      final a = (i / 24) * 2 * math.pi - math.pi / 2;
      final inX = cx + math.cos(a) * (rx - 5);
      final inY = cy + math.sin(a) * (ry - 5);
      final outX = cx + math.cos(a) * (rx - 1);
      final outY = cy + math.sin(a) * (ry - 1);
      canvas.drawLine(Offset(inX, inY), Offset(outX, outY), tickPaint);
    }

    // Subtle scale pulse when locked to communicate "active"
    if (statusColor == 'locked') {
      final pulse = (math.sin(animT * 4) * 0.006 + 1.0);
      final pulseRect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: ovalW * pulse, height: ovalH * pulse);
      canvas.drawOval(pulseRect, Paint()
        ..color = lockedColor.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    }
  }

  void _drawStatusCoachText(Canvas canvas, Size size) {
    if (statusText.isEmpty) return;

    const idleColor      = Color(0xFF8A8F98);
    const adjustingColor = Color(0xFFFFC857);
    const lockedColor    = Color(0xFF2ECC71);
    final Color c = statusColor == 'locked' ? lockedColor
                  : statusColor == 'adjusting' ? adjustingColor
                  : idleColor;

    final y = size.height * 0.14;
    final tp = TextPainter(
      text: TextSpan(
        text: statusText,
        style: TextStyle(
          color: c,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          fontFamilyFallback: const ['monospace'],
          shadows: [
            Shadow(color: c.withValues(alpha: 0.55), blurRadius: 10),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(minWidth: 0, maxWidth: size.width - 40);

    // Dark pill under text for legibility
    final rect = Rect.fromLTWH(
      (size.width - tp.width) / 2 - 16,
      y - 9,
      tp.width + 32,
      tp.height + 18,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(100)),
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(100)),
      Paint()
        ..color = c.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    tp.paint(canvas, Offset((size.width - tp.width) / 2, y));
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
  //  NOTE: the oval face-guide (drawn elsewhere) is the primary visual.
  //  This only adds a central crosshair + outer corner brackets. The
  //  previously-drawn mid-size rotating segment ring has been removed.
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawSearchingReticle(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Central crosshair (the "little one in the center" — kept)
    final hair = Paint()
      ..color = _cGold.withValues(alpha: 0.75)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(cx - 10, cy), Offset(cx - 3, cy), hair);
    canvas.drawLine(Offset(cx + 3, cy), Offset(cx + 10, cy), hair);
    canvas.drawLine(Offset(cx, cy - 10), Offset(cx, cy - 3), hair);
    canvas.drawLine(Offset(cx, cy + 3), Offset(cx, cy + 10), hair);
    canvas.drawCircle(Offset(cx, cy), 1.5, Paint()..color = _cGold);

    // Outer corner brackets (the biggest container — kept)
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
      // Skip the iOS semantic-mesh sentinel so unpopulated canonical
      // MediaPipe slots don't paint stray dots off the canvas edge.
      if (p.dx < 0 || p.dx > 1 || p.dy < 0 || p.dy > 1) continue;
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
      final baseColor = isAnchor ? _cGoldHi : _cCyan;
      // Glow under-dot for each landmark — makes them read at distance
      dotPaint.color = baseColor
          .withValues(alpha: (0.35 * alphaScale * depthAlpha).clamp(0.0, 1.0));
      dotPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawCircle(Offset(x, y), 3.2 * b * depthMul, dotPaint);
      // Crisp core — solid, bright
      dotPaint.maskFilter = null;
      dotPaint.color = baseColor
          .withValues(alpha: (0.95 * alphaScale * depthAlpha).clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), 1.5 * b * depthMul, dotPaint);
      // White specular hit on brighter anchors
      if (isAnchor) {
        canvas.drawCircle(Offset(x, y), 0.7 * b * depthMul, Paint()
          ..color = _cWhite.withValues(alpha: 0.9 * alphaScale * depthAlpha));
      }
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

    // Base edge network — now way more visible. Alpha 0.18 → 0.42 plus a
    // 1.4px stroke instead of 0.5px. This is the "spider-web" layer that
    // makes the face feel topologically mapped.
    final edgeGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..color = _cCyan.withValues(alpha: 0.28 * revealBase)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final edgeLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = _cCyanHi.withValues(alpha: 0.70 * revealBase);
    final edgeCore = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = _cWhite.withValues(alpha: 0.45 * revealBase);

    for (final (a, b) in _faceMeshEdges) {
      if (a >= points.length || b >= points.length) continue;
      final pa = points[a];
      final pb = points[b];
      final p1 = Offset(pa.dx * size.width, pa.dy * size.height);
      final p2 = Offset(pb.dx * size.width, pb.dy * size.height);
      canvas.drawLine(p1, p2, edgeGlow);
      canvas.drawLine(p1, p2, edgeLine);
      canvas.drawLine(p1, p2, edgeCore);
    }

    // Bright moving neural pulse — larger, brighter trail (12 segments, was 6)
    final cyclePhase = (animT * 0.7) % 1.0;
    final pulseIdx = (cyclePhase * _faceMeshEdges.length).floor();
    for (var i = 0; i < 12; i++) {
      final idx = (pulseIdx + i) % _faceMeshEdges.length;
      final (a, b) = _faceMeshEdges[idx];
      if (a >= points.length || b >= points.length) continue;
      final pa = points[a];
      final pb = points[b];
      final p1 = Offset(pa.dx * size.width, pa.dy * size.height);
      final p2 = Offset(pb.dx * size.width, pb.dy * size.height);
      final trailAlpha = (1 - i / 12) * revealBase;
      canvas.drawLine(p1, p2, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.5
        ..color = _cCyanHi.withValues(alpha: 0.55 * trailAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.drawLine(p1, p2, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = _cWhite.withValues(alpha: 0.9 * trailAlpha));
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
    if (points.isEmpty) return;

    final reveal = phase == ScanPhase.measuring
        ? ((progress - 0.05) / 0.8).clamp(0.0, 1.0)
        : 1.0;
    if (reveal <= 0) return;

    // px() filters sentinel placeholders (out-of-canvas coords used by
    // the iOS semantic mesh for unmapped indices) so chains drawn from
    // MediaPipe topology don't include invisible far-off points.
    // chain() iterates whatever survives, so iOS chains end up shorter
    // but still draw the segments where data exists.
    Offset? px(int i) {
      if (i >= points.length) return null;
      final p = points[i];
      if (p.dx < 0 || p.dx > 1 || p.dy < 0 || p.dy > 1) return null;
      return Offset(p.dx * size.width, p.dy * size.height);
    }

    // Width multiplier — dramatic mode thickens everything by ~3x, with a
    // massive glow halo. This is the "undeniable" weight the overlay needs.
    final wMul = dramatic ? 3.0 : 1.0;
    final glowMul = dramatic ? 6.5 : 3.5;

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

      // 1. Outer MASSIVE halo (huge blur, enhances weight)
      if (dramatic) {
        canvas.drawPath(path, Paint()
          ..color = c.withValues(alpha: alpha * 0.32 * xrayPulse)
          ..strokeWidth = w * glowMul * 1.6
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
      }

      // 2. Medium blur halo
      canvas.drawPath(path, Paint()
        ..color = c.withValues(alpha: alpha * 0.65 * xrayPulse)
        ..strokeWidth = w * glowMul
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, dramatic ? 7 : 3));

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

    // Mandible — defining bone. Thickest line, first to reveal.
    chain(const [
      234, 93, 132, 58, 172, 136, 150, 149, 176, 148, 152,
      377, 400, 378, 379, 365, 397, 288, 361, 323, 454,
    ], 0.00, 0.28, width: 3.4);

    // Zygomatic L/R (cheekbone shelf)
    chain(const [234, 227, 116, 123, 117, 118, 101], 0.20, 0.45, width: 2.4);
    chain(const [454, 447, 345, 352, 346, 347, 330], 0.20, 0.45, width: 2.4);

    // Orbital frame L (full eye-socket trace — this is what the user loved)
    chain(const [
      33, 246, 161, 160, 159, 158, 157, 173, 133, 155, 154, 153, 145, 144, 163, 7, 33,
    ], 0.35, 0.60, width: 2.0, alpha: 1.0);
    // Orbital frame R
    chain(const [
      263, 466, 388, 387, 386, 385, 384, 398, 362, 382, 381, 380, 374, 373, 390, 249, 263,
    ], 0.35, 0.60, width: 2.0, alpha: 1.0);

    // Iris ring L / R — tight rings around the pupil that read as "it can
    // see every part of your eye." Draws AFTER the orbital frame so it sits
    // on top as the finishing touch.
    chain(const [468, 469, 470, 471, 472, 468],
        0.58, 0.72, width: 1.4, alpha: 0.95, color: _cCyanHi);
    chain(const [473, 474, 475, 476, 477, 473],
        0.58, 0.72, width: 1.4, alpha: 0.95, color: _cCyanHi);

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
  //  Live measurement rails — horizontal lines extending from 5 anchor
  //  landmarks to the screen edge, each ending in a value pill. Reads like
  //  a HUD overlay in a sci-fi film. Shown live throughout scanning AND
  //  measuring so data density stays high the whole scan.
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawLiveMeasurementLines(Canvas canvas, Size size) {
    final points = mesh!.points;
    // Anchor-driven (33, 234, 454, 1, 152) — works on iOS too via the
    // semantic mesh. Just need enough points for the canonical indices
    // to be addressable, which the semantic builder guarantees (length
    // 500). We still bail on a totally empty mesh.
    if (points.isEmpty) return;

    Offset? px(int i) {
      if (i >= points.length) return null;
      final p = points[i];
      // Off-canvas sentinel — semantic mesh fills unmapped indices with
      // (-10, -10). Treat anything outside [0,1] as "no data here" so
      // we don't try to anchor a rail to thin air.
      if (p.dx < 0 || p.dx > 1 || p.dy < 0 || p.dy > 1) return null;
      return Offset(p.dx * size.width, p.dy * size.height);
    }

    // Real measurements from this frame's FaceGeometryService pass.
    // Geometry can be null briefly between the first frame's mesh
    // arriving and the geometry being computed — fall back to a
    // small idle wobble so the rails don't blink to zero.
    final g = geometry;
    final canthal = g?.canthalTilt        ?? (math.sin(animT * 2.1) * 0.12);
    final jaw     = g?.jawAngle           ?? (118 + math.sin(animT * 1.6) * 0.6);
    final fwhr    = g?.fwhr               ?? (1.87 + math.sin(animT * 1.9) * 0.015);
    final sym     = g?.symmetryScore      ?? (87 + math.sin(animT * 1.3) * 0.8);
    final nose    = g?.noseLengthRatio    ?? (0.34 + math.sin(animT * 1.5) * 0.008);

    // Canthal tilt clamps to ±10° in FaceGeometryService when the
    // eye-corner detection breaks down (typically head rotated > 25°).
    // Showing "CANTHAL 10.00°" in that state is misleading — replace
    // with a dash so the user reads "couldn't measure this angle yet"
    // instead of "your tilt is locked at the maximum". Same logic used
    // in _drawFloatingMeasurements + _drawMeasurementArcs below.
    final canthalText = canthal.abs() >= 9.5
        ? 'EYE TILT · —'
        : 'EYE TILT · ${canthal.toStringAsFixed(2)}°';

    // 5 rails — each: (anchor index, left-side boolean, label text, delay)
    final rails = <({int anchor, bool leftSide, String label, double delayFrac})>[
      (anchor: 33,    leftSide: true,  label: canthalText, delayFrac: 0.00),
      (anchor: 454,   leftSide: false, label: 'SYM · ${sym.toStringAsFixed(0)}%',          delayFrac: 0.10),
      (anchor: 234,   leftSide: true,  label: 'FWHR · ${fwhr.toStringAsFixed(2)}',         delayFrac: 0.20),
      (anchor: 1,     leftSide: false, label: 'NOSE · ${nose.toStringAsFixed(2)}',         delayFrac: 0.30),
      (anchor: 152,   leftSide: false, label: 'JAW · ${jaw.toStringAsFixed(0)}°',          delayFrac: 0.40),
    ];

    // Base reveal so rails don't blast in all at once during scanning
    final baseReveal = phase == ScanPhase.scanning
        ? ((progress - 0.1) / 0.5).clamp(0.0, 1.0)
        : 1.0;
    if (baseReveal <= 0) return;

    for (final r in rails) {
      final anchor = px(r.anchor);
      if (anchor == null) continue;

      final local = ((baseReveal - r.delayFrac) / 0.3).clamp(0.0, 1.0);
      if (local <= 0) continue;

      _drawSingleRail(canvas, size, anchor, r.label, r.leftSide, local);
    }
  }

  void _drawSingleRail(Canvas canvas, Size size, Offset anchor,
      String label, bool leftSide, double t) {
    final endX = leftSide ? 18.0 : size.width - 18.0;
    final railEnd = Offset(endX, anchor.dy);

    // Current end of the animating line
    final currentEndX = anchor.dx + (railEnd.dx - anchor.dx) * t;
    final currentEnd = Offset(currentEndX, anchor.dy);

    // 1. Soft gold glow under the line
    canvas.drawLine(anchor, currentEnd, Paint()
      ..color = _cGold.withValues(alpha: 0.55 * t)
      ..strokeWidth = 4.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
      ..strokeCap = StrokeCap.round);
    // 2. Crisp gold line
    canvas.drawLine(anchor, currentEnd, Paint()
      ..color = _cGoldHi.withValues(alpha: 0.95 * t)
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round);
    // 3. Tip flare — small bright circle at the leading edge while drawing
    if (t < 0.98) {
      canvas.drawCircle(currentEnd, 3.5, Paint()
        ..color = _cWhite.withValues(alpha: 0.95));
      canvas.drawCircle(currentEnd, 8, Paint()
        ..color = _cGold.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }

    // 4. Anchor node — filled gold dot with white centre at the landmark
    canvas.drawCircle(anchor, 4.2, Paint()
      ..color = _cGold.withValues(alpha: 0.5 * t)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    canvas.drawCircle(anchor, 2.2, Paint()
      ..color = _cGoldHi.withValues(alpha: 0.95 * t));
    canvas.drawCircle(anchor, 0.9, Paint()
      ..color = _cWhite.withValues(alpha: t));

    // 5. Label pill at the end (only after line fully drawn)
    if (t >= 0.9) {
      final labelAlpha = ((t - 0.9) / 0.1).clamp(0.0, 1.0);
      _drawRailLabel(canvas, size, railEnd, label, leftSide, labelAlpha);
    }
  }

  void _drawRailLabel(Canvas canvas, Size size, Offset endPoint,
      String label, bool leftSide, double alpha) {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: _cGoldHi.withValues(alpha: alpha),
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.8,
          fontFamilyFallback: const ['monospace'],
          shadows: [
            Shadow(color: _cGold.withValues(alpha: alpha * 0.65), blurRadius: 6),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final pillPad = const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
    final rectX = leftSide
        ? endPoint.dx - tp.width - pillPad.horizontal + 12
        : endPoint.dx - 12;
    final rect = Rect.fromLTWH(
      rectX,
      endPoint.dy - tp.height / 2 - pillPad.vertical / 2,
      tp.width + pillPad.horizontal,
      tp.height + pillPad.vertical,
    );

    // Dark underlay for legibility on any skin tone
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = Colors.black.withValues(alpha: 0.7 * alpha),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()
        ..color = _cGold.withValues(alpha: 0.5 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7,
    );
    tp.paint(canvas, Offset(rect.left + pillPad.left, rect.top + pillPad.top));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Face silhouette glow — traces the outer face oval with a huge gold
  //  halo, making the entire face read as highlighted. This is the heaviest
  //  weight layer in the overlay — it's what makes the whole thing feel
  //  like an X-ray of the user, not a surface effect.
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawFaceSilhouetteGlow(Canvas canvas, Size size) {
    final points = mesh!.points;
    if (points.isEmpty) return;

    // Face-oval indices (MediaPipe 468 mesh face boundary, clockwise).
    // The semantic-mesh builder on iOS distributes ML Kit's face oval
    // contour points across these same canonical indices, so the glow
    // traces the same outline on both platforms.
    const faceOvalIdx = [
      10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288,
      397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136,
      172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109,
    ];

    final reveal = phase == ScanPhase.measuring
        ? (progress.clamp(0.0, 1.0))
        : 1.0;
    if (reveal < 0.02) return;

    final pts = faceOvalIdx.map((i) {
      if (i >= points.length) return null;
      final p = points[i];
      // Skip sentinel / unmapped entries.
      if (p.dx < 0 || p.dx > 1 || p.dy < 0 || p.dy > 1) return null;
      return Offset(p.dx * size.width, p.dy * size.height);
    }).whereType<Offset>().toList();
    if (pts.length < 8) return;

    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    path.close();

    final pulse = (math.sin(animT * 1.8) * 0.12 + 0.88);

    // 1. Massive outer halo
    canvas.drawPath(path, Paint()
      ..color = _cGold.withValues(alpha: 0.32 * reveal * pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 32
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20));

    // 2. Medium halo
    canvas.drawPath(path, Paint()
      ..color = _cGold.withValues(alpha: 0.55 * reveal * pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));

    // 3. Crisp edge line
    canvas.drawPath(path, Paint()
      ..color = _cGoldHi.withValues(alpha: 0.9 * reveal)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);

    // 4. Bright white core (razor thin — makes edge feel incandescent)
    canvas.drawPath(path, Paint()
      ..color = _cWhite.withValues(alpha: 0.7 * reveal)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..strokeCap = StrokeCap.round);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Constellation — bright twinkling stars at key anchor landmarks. Gives
  //  the face a living, starlit quality. Stars twinkle out of phase so the
  //  whole mesh shimmers.
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawConstellation(Canvas canvas, Size size) {
    final points = mesh!.points;
    if (points.isEmpty) return;

    final reveal = ((progress - 0.25) / 0.6).clamp(0.0, 1.0);
    if (reveal <= 0) return;

    const anchors = [
      1, 4, 6, 10, 33, 133, 152, 168, 197, 263, 362,
      234, 454, 175, 18, 199, 200, 0, 13, 14, 17, 61, 291,
      78, 95, 88, 178, 87, 14, 317, 402, 318, 324, 308,
    ];

    for (final i in anchors) {
      if (i >= points.length) continue;
      final p = points[i];
      // Skip unmapped / sentinel anchors so iOS doesn't draw stars
      // bunched off-canvas or in random positions.
      if (p.dx < 0 || p.dx > 1 || p.dy < 0 || p.dy > 1) continue;
      final x = p.dx * size.width;
      final y = p.dy * size.height;

      // Each anchor twinkles on its own phase
      final phaseOff = i * 0.37;
      final tw = (math.sin(animT * 3.2 + phaseOff) + 1) / 2;
      final alpha = reveal * (0.45 + tw * 0.5);
      final size2 = 1.6 + tw * 2.2;

      // Core white
      canvas.drawCircle(Offset(x, y), size2 * 0.6, Paint()
        ..color = _cWhite.withValues(alpha: alpha));
      // Gold bloom
      canvas.drawCircle(Offset(x, y), size2 * 2.6, Paint()
        ..color = _cGold.withValues(alpha: alpha * 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));

      // Cross-flare for brightest stars (every 4th anchor)
      if (i % 4 == 0 && tw > 0.75) {
        final flareLen = size2 * 5;
        final flarePaint = Paint()
          ..color = _cGoldHi.withValues(alpha: alpha * 0.7)
          ..strokeWidth = 0.8;
        canvas.drawLine(
          Offset(x - flareLen, y), Offset(x + flareLen, y), flarePaint);
        canvas.drawLine(
          Offset(x, y - flareLen), Offset(x, y + flareLen), flarePaint);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Measurement arcs — visualise specific measurements as arcs / brackets
  //  drawn over the face. Canthal tilt as a curved line above each eye, FWHR
  //  as bracket ticks across cheekbones, jaw angle as an arc at the gonion.
  //  This makes the "we measured you" feel VISIBLE, not just numerical.
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawMeasurementArcs(Canvas canvas, Size size) {
    final points = mesh!.points;
    if (points.isEmpty) return;

    final reveal = ((progress - 0.40) / 0.50).clamp(0.0, 1.0);
    if (reveal <= 0) return;

    Offset? px(int i) {
      if (i >= points.length) return null;
      final p = points[i];
      // Filter the iOS semantic-mesh sentinel so arcs aren't anchored
      // to off-canvas points when an index is unpopulated.
      if (p.dx < 0 || p.dx > 1 || p.dy < 0 || p.dy > 1) return null;
      return Offset(p.dx * size.width, p.dy * size.height);
    }

    final paint = Paint()
      ..color = _cGoldHi.withValues(alpha: 0.85 * reveal)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final glow = Paint()
      ..color = _cGold.withValues(alpha: 0.6 * reveal)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    // 1. FWHR bracket — between cheekbones, horizontal bracket with ticks
    final cheekL = px(234);
    final cheekR = px(454);
    if (cheekL != null && cheekR != null && reveal > 0.1) {
      final yMid = (cheekL.dy + cheekR.dy) / 2;
      final localFwhr = ((reveal - 0.1) / 0.3).clamp(0.0, 1.0);
      final drawnCheekR = Offset(
        cheekL.dx + (cheekR.dx - cheekL.dx) * localFwhr,
        yMid,
      );
      canvas.drawLine(Offset(cheekL.dx, yMid), drawnCheekR, glow);
      canvas.drawLine(Offset(cheekL.dx, yMid), drawnCheekR, paint);
      // End ticks
      canvas.drawLine(
        Offset(cheekL.dx, yMid - 8), Offset(cheekL.dx, yMid + 8), paint);
      if (localFwhr >= 1.0) {
        canvas.drawLine(
          Offset(cheekR.dx, yMid - 8), Offset(cheekR.dx, yMid + 8), paint);
      }
    }

    // 2. Jaw angle arc — at left jaw gonion, small arc showing the angle
    final jawL    = px(172);
    final chin    = px(152);
    final jawBack = px(58);
    if (jawL != null && chin != null && jawBack != null && reveal > 0.35) {
      final arcProg = ((reveal - 0.35) / 0.3).clamp(0.0, 1.0);
      _drawArcAtCorner(canvas, jawL, chin, jawBack,
        r: 24, sweepProg: arcProg,
        paint: paint, glow: glow);
    }
    // Right jaw arc
    final jawR     = px(397);
    final jawBackR = px(288);
    if (jawR != null && chin != null && jawBackR != null && reveal > 0.45) {
      final arcProg = ((reveal - 0.45) / 0.3).clamp(0.0, 1.0);
      _drawArcAtCorner(canvas, jawR, chin, jawBackR,
        r: 24, sweepProg: arcProg,
        paint: paint, glow: glow);
    }

    // 3. Canthal tilt mini-arcs at outer eye corners
    final leftOuter  = px(33);
    final leftInner  = px(133);
    final rightOuter = px(263);
    final rightInner = px(362);
    if (leftOuter != null && leftInner != null && reveal > 0.55) {
      _drawShortArcBetween(canvas, leftOuter, leftInner,
        offsetAbove: 8, paint: paint, glow: glow,
        progress: ((reveal - 0.55) / 0.25).clamp(0.0, 1.0));
    }
    if (rightOuter != null && rightInner != null && reveal > 0.65) {
      _drawShortArcBetween(canvas, rightInner, rightOuter,
        offsetAbove: 8, paint: paint, glow: glow,
        progress: ((reveal - 0.65) / 0.25).clamp(0.0, 1.0));
    }
  }

  void _drawArcAtCorner(Canvas canvas, Offset corner, Offset armA, Offset armB, {
    required double r,
    required double sweepProg,
    required Paint paint,
    required Paint glow,
  }) {
    if (sweepProg <= 0) return;
    final a1 = math.atan2(armA.dy - corner.dy, armA.dx - corner.dx);
    final a2 = math.atan2(armB.dy - corner.dy, armB.dx - corner.dx);
    var sweep = a2 - a1;
    // Normalize to shortest direction
    while (sweep > math.pi) { sweep -= 2 * math.pi; }
    while (sweep < -math.pi) { sweep += 2 * math.pi; }
    final rect = Rect.fromCircle(center: corner, radius: r);
    canvas.drawArc(rect, a1, sweep * sweepProg, false, glow);
    canvas.drawArc(rect, a1, sweep * sweepProg, false, paint);
  }

  void _drawShortArcBetween(Canvas canvas, Offset a, Offset b, {
    required double offsetAbove,
    required Paint paint,
    required Paint glow,
    required double progress,
  }) {
    if (progress <= 0) return;
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2 - offsetAbove);
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy);
    // Draw a fraction of the path via PathMetrics for animated reveal
    for (final m in path.computeMetrics()) {
      final partial = m.extractPath(0, m.length * progress);
      canvas.drawPath(partial, glow);
      canvas.drawPath(partial, paint);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Feature beam — a horizontal scan-line that sweeps down the face,
  //  pausing at each feature with a "SCANNING [X]... LOCKED" label. This is
  //  the biometric-grade moment that sells the precision.
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawFeatureBeam(Canvas canvas, Size size) {
    // Pure horizontal sweep — no point indexing required. Just needs to
    // know a face was detected (any non-empty mesh).
    final points = mesh!.points;
    if (points.isEmpty) return;

    // 6 feature zones, each gets its own progress slice.
    const zones = [
      (0.00, 0.15, 'FOREHEAD',    0.18),
      (0.15, 0.30, 'EYE LINE',    0.30),
      (0.30, 0.45, 'CHEEKBONES',  0.44),
      (0.45, 0.60, 'NOSE',        0.52),
      (0.60, 0.75, 'LIPS',        0.68),
      (0.75, 0.92, 'JAWLINE',     0.82),
    ];

    for (final (start, end, label, yPct) in zones) {
      if (progress < start) continue;
      final local = ((progress - start) / (end - start)).clamp(0.0, 1.0);
      final y = size.height * yPct;

      final active = progress >= start && progress < end;
      final locked = progress >= end;

      if (active) {
        // Bright sweeping beam across the feature's vertical band
        final beamPaint = Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.transparent,
              _cGoldHi.withValues(alpha: 0.85),
              _cGoldHi.withValues(alpha: 1.0),
              _cGoldHi.withValues(alpha: 0.85),
              Colors.transparent,
            ],
            stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
          ).createShader(Rect.fromLTWH(0, y - 1.5, size.width, 3))
          ..strokeWidth = 2.5;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), beamPaint);

        // Feature band highlight — subtle horizontal glow strip
        final band = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              _cGold.withValues(alpha: 0.14 * math.sin(local * math.pi)),
              Colors.transparent,
            ],
          ).createShader(Rect.fromLTWH(0, y - 22, size.width, 44));
        canvas.drawRect(Rect.fromLTWH(0, y - 22, size.width, 44), band);

        // Label — "SCANNING FOREHEAD..." right side, animating in
        _drawBeamLabel(canvas, size, y,
          text: 'SCANNING $label...',
          color: _cGoldHi, alpha: 0.95,
          rightSide: true);
      } else if (locked) {
        // Locked — a checkmark + "LOCKED" on left side
        _drawBeamLabel(canvas, size, y,
          text: '✓ $label',
          color: _cGoldHi, alpha: 0.6,
          rightSide: false);
      }
    }
  }

  void _drawBeamLabel(Canvas canvas, Size size, double y, {
    required String text,
    required Color color,
    required double alpha,
    required bool rightSide,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color.withValues(alpha: alpha),
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.2,
          fontFamilyFallback: const ['monospace'],
          shadows: [
            Shadow(color: _cGold.withValues(alpha: alpha * 0.7), blurRadius: 6),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final x = rightSide
      ? size.width - tp.width - 16
      : 16.0;

    // Dark pill under text for legibility
    final rect = Rect.fromLTWH(x - 5, y - tp.height / 2 - 2, tp.width + 10, tp.height + 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = Colors.black.withValues(alpha: alpha * 0.6),
    );
    tp.paint(canvas, Offset(x, y - tp.height / 2));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Digital rain — streams of measurement numbers falling down left + right
  //  edges of the screen. Subtle but adds data density — feels like the whole
  //  face is producing a firehose of values.
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawDigitalRain(Canvas canvas, Size size) {
    const cols = 3;
    for (var side = 0; side < 2; side++) {
      for (var c = 0; c < cols; c++) {
        final seed = side * 100.0 + c * 17.0;
        final colX = side == 0
          ? 8.0 + c * 22
          : size.width - 8 - (cols - c) * 22;
        final speed = 0.55 + _hash(seed) * 0.6;
        final offset = (animT * speed) % 1.0;

        // Draw 8 characters per column, each a random measurement digit
        for (var row = 0; row < 10; row++) {
          final y = (offset * size.height + row * 26) % (size.height + 60) - 30;
          final alphaFade = math.max(0.0, 1 - row / 10) * 0.5;

          final digit = _pickDigit(seed + row * 3.3 + animT * 0.3);
          final tp = TextPainter(
            text: TextSpan(
              text: digit,
              style: TextStyle(
                color: _cCyan.withValues(alpha: alphaFade),
                fontSize: 10,
                fontFamilyFallback: const ['monospace'],
                fontWeight: FontWeight.w700,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(colX, y));
        }
      }
    }
  }

  String _pickDigit(double seed) {
    const chars = ['0','1','2','3','4','5','6','7','8','9',
                   'mm','°','%','.',':','/','·','▸','◉','◆','◇'];
    final i = (_hash(seed) * chars.length).floor() % chars.length;
    return chars[i];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Rotate cue (shown during rotateLeft / rotateRight phases)
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawRotateCue(Canvas canvas, Size size, {required bool leftwards}) {
    final cx = size.width / 2;
    final cy = size.height * 0.55;

    final pulse = (math.sin(animT * 2.8) + 1) / 2;
    final scaleP = 1.0 + pulse * 0.15;
    final translateX = math.sin(animT * 2.0) * 18 * (leftwards ? -1 : 1);

    canvas.save();
    canvas.translate(cx + translateX, cy);
    canvas.scale(scaleP, scaleP);

    // Curved arrow
    const r = 74.0;
    final dir = leftwards ? -1 : 1;
    final arrowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..color = _cGoldHi.withValues(alpha: 0.88)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: r),
      leftwards ? math.pi * 1.2 : -math.pi * 0.2,
      math.pi * 1.1 * dir.toDouble(),
      false, arrowPaint,
    );

    // Arrowhead
    final tipAngle = leftwards
      ? math.pi * 1.2 + math.pi * 1.1 * -1
      : -math.pi * 0.2 + math.pi * 1.1;
    final tip = Offset(math.cos(tipAngle) * r, math.sin(tipAngle) * r);
    final tangent = Offset(
      -math.sin(tipAngle) * dir.toDouble(),
      math.cos(tipAngle) * dir.toDouble());
    final p1 = tip + tangent * 14 + Offset(-tangent.dy, tangent.dx) * 12;
    final p2 = tip + tangent * 14 + Offset(tangent.dy, -tangent.dx) * 12;
    final headPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..color = _cGoldHi;
    canvas.drawLine(tip, p1, headPaint);
    canvas.drawLine(tip, p2, headPaint);

    // Center label
    final tp = TextPainter(
      text: TextSpan(
        text: leftwards ? 'TURN LEFT' : 'TURN RIGHT',
        style: TextStyle(
          color: _cGoldHi,
          fontSize: 15,
          fontWeight: FontWeight.w900,
          letterSpacing: 4.5,
          fontFamilyFallback: const ['monospace'],
          shadows: [
            Shadow(color: _cGold.withValues(alpha: 0.9), blurRadius: 10),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));

    canvas.restore();

    // Sub-instruction
    final sub = TextPainter(
      text: const TextSpan(
        text: 'hold — lock acquiring',
        style: TextStyle(
          color: Color(0xFFF7F7F9),
          fontSize: 12,
          fontWeight: FontWeight.w500,
          
          letterSpacing: 0.6,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    sub.paint(canvas, Offset(cx - sub.width / 2, cy + r + 48));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 6b  —  Floating live measurement readouts (numbers at anchors)
  //  These are the numbers animating next to the mesh, terminal-style. Each
  //  appears when its reveal phase begins, with a slight flicker to read as
  //  "live data streaming in."
  // ═══════════════════════════════════════════════════════════════════════════
  void _drawFloatingMeasurements(Canvas canvas, Size size) {
    final points = mesh!.points;
    // Anchor-only — uses idxLeftEyeOuter, idxChin, idxCheekL, idxCheekR
    // which the iOS semantic mesh populates correctly.
    if (points.isEmpty) return;
    final reveal = ((progress - 0.55) / 0.35).clamp(0.0, 1.0);
    if (reveal <= 0) return;

    Offset? px(int i) {
      if (i >= points.length) return null;
      final p = points[i];
      // Sentinel guard so an unmapped anchor doesn't paint a readout
      // off-screen at (-X, -Y).
      if (p.dx < 0 || p.dx > 1 || p.dy < 0 || p.dy > 1) return null;
      return Offset(p.dx * size.width, p.dy * size.height);
    }

    // Real measurements from FaceGeometryService.computeGeometry, fed
    // in by scan_screen each frame. Idle fallback only fires before
    // the first geometry pass lands.
    final g = geometry;
    final canthal = g?.canthalTilt   ?? (math.sin(animT * 2.1) * 0.12);
    final jaw     = g?.jawAngle      ?? (118 + math.sin(animT * 1.6) * 0.6);
    final fwhr    = g?.fwhr          ?? (1.87 + math.sin(animT * 1.9) * 0.015);
    final sym     = g?.symmetryScore ?? (87 + math.sin(animT * 1.3) * 0.8);

    // Suppress canthal value when it's at the ±10° clamp boundary —
    // means the eye-corner detection broke down (face rotated > ~25°).
    // Showing "CANTHAL 10.00°" in that state is misleading.
    final canthalLabel = canthal.abs() >= 9.5
        ? 'CANTHAL —'
        : 'CANTHAL ${canthal.toStringAsFixed(2)}°';

    final readouts = <(Offset?, String, double)>[
      (px(FaceMesh.idxLeftEyeOuter),  canthalLabel,                              0.00),
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
    // Strike now spans 0.85–1.0 (was 0.90–1.0). With the slower measuring
    // timer this means the lock moment lasts ~1s on screen — long enough
    // to register on camera, still punchy.
    final strikeT = ((progress - 0.85) / 0.15).clamp(0.0, 1.0);
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

    // Real measurements from the live geometry pass. Idle fallback only
    // shows during the brief window before the first frame's geometry
    // lands; once we have data, every value below is the user's actual
    // face metric, recomputed every frame.
    final g = geometry;
    final canthal = g?.canthalTilt    ?? (3.0 + math.sin(animT * 2) * 0.15);
    final sym     = g?.symmetryScore  ?? (87 + math.sin(animT * 1.5) * 1.2);
    final fwhr    = g?.fwhr           ?? (1.87 + math.sin(animT * 1.8) * 0.02);
    final jaw     = g?.jawAngle       ?? (118 + math.sin(animT * 1.3) * 0.8);
    final chin    = g?.chinProjection ?? (0.34 + math.sin(animT * 1.6) * 0.01);
    // Facial thirds — round to nearest integer for the marquee compactness.
    final t1 = (g?.facialThirdTop ?? 33).round();
    final t2 = (g?.facialThirdMid ?? 33).round();
    final t3 = (g?.facialThirdLow ?? 34).round();
    // Same clamp-boundary suppression as the floating labels above.
    final canthalStr = canthal.abs() >= 9.5
        ? 'CANTHAL —'
        : 'CANTHAL ${canthal.toStringAsFixed(2)}°';
    final values = <String>[
      canthalStr,
      'SYM ${sym.toStringAsFixed(1)}%',
      'FWHR ${fwhr.toStringAsFixed(2)}',
      'JAW ${jaw.toStringAsFixed(0)}°',
      'CHIN ${chin.toStringAsFixed(2)}',
      'THIRDS $t1/$t2/$t3',
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

  /// Deterministic pseudo-random 0..1 from a seed. Used for ambient particles
  /// + any place we want stable "randomness" across frames.
  double _hash(double seed) {
    final x = math.sin(seed * 12.9898) * 43758.5453;
    return x - x.floorToDouble();
  }

  @override
  bool shouldRepaint(GeometryOverlayPainter old) =>
      old.mesh         != mesh         ||
      old.phase        != phase        ||
      old.progress     != progress     ||
      old.countdown    != countdown    ||
      old.animT        != animT        ||
      old.lockProgress != lockProgress ||
      old.statusText   != statusText   ||
      old.statusColor  != statusColor  ||
      old.holdProgress != holdProgress ||
      old.geometry     != geometry;
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
