import 'dart:math' as math;
import 'package:flutter/painting.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../models/face_geometry.dart';

class FaceGeometryService {
  /// Extract geometry measurements from ML Kit face detection result.
  static FaceGeometry computeGeometry(Face face, double imgW, double imgH) {
    final contours = face.contours;

    // ── Eye corner landmarks ────────────────────────────────────────────────
    final leftEyeContour  = contours[FaceContourType.leftEye]?.points ?? [];
    final rightEyeContour = contours[FaceContourType.rightEye]?.points ?? [];
    final faceOval        = contours[FaceContourType.face]?.points ?? [];
    final noseBridge      = contours[FaceContourType.noseBridge]?.points ?? [];
    final noseBottom      = contours[FaceContourType.noseBottom]?.points ?? [];
    final leftEyebrow     = contours[FaceContourType.leftEyebrowTop]?.points ?? [];
    final rightEyebrow    = contours[FaceContourType.rightEyebrowTop]?.points ?? [];
    final upperLipTop     = contours[FaceContourType.upperLipTop]?.points ?? [];
    final upperLipBottom  = contours[FaceContourType.upperLipBottom]?.points ?? [];
    final lowerLipTop     = contours[FaceContourType.lowerLipTop]?.points ?? [];
    final lowerLipBottom  = contours[FaceContourType.lowerLipBottom]?.points ?? [];

    final hasData = leftEyeContour.length >= 4 &&
        rightEyeContour.length >= 4 &&
        faceOval.length >= 10;

    if (!hasData) {
      return const FaceGeometry(
        canthalTilt: 0, symmetryScore: 70, facialThirdTop: 33,
        facialThirdMid: 33, facialThirdLow: 34, fwhr: 1.9,
        eyeSpacingRatio: 0.46, jawAngle: 125, chinProjection: 0,
        hasReliableData: false,
      );
    }

    // Normalize helper
    Offset norm(math.Point<int> p) =>
        Offset(p.x / imgW, p.y / imgH);

    // ── Eye centers (computed first so we can find the face midline) ──
    final leftEyeCX  = leftEyeContour.map((p) => p.x).reduce((a, b) => a + b) /
        leftEyeContour.length;
    final leftEyeCY  = leftEyeContour.map((p) => p.y).reduce((a, b) => a + b) /
        leftEyeContour.length;
    final rightEyeCX = rightEyeContour.map((p) => p.x).reduce((a, b) => a + b) /
        rightEyeContour.length;
    final rightEyeCY = rightEyeContour.map((p) => p.y).reduce((a, b) => a + b) /
        rightEyeContour.length;

    // ── Canthal tilt — robust corner detection ────────────────────────────
    // Old impl assumed ML Kit's contour ordering put `.first` at the
    // inner corner. That's NOT consistent across the iOS and Android
    // ML Kit bridges (different SDK builds start the eye loop at
    // different vertices), and when the assumption was wrong the
    // sign of the tilt flipped — every user with downturned eyes
    // got scored as "hunter eyes" because the inner/outer labels
    // were swapped.
    //
    // Robust fix: detect the inner corner GEOMETRICALLY. The inner
    // corner is whichever endpoint of the eye contour is closer to
    // the face midline (between the two eye centers). The outer
    // corner is the other one. This works on both platforms and
    // doesn't depend on which point ML Kit happens to emit first.
    final eyeMidlineX = (leftEyeCX + rightEyeCX) / 2;

    Offset _innerOf(List<math.Point<int>> contour) {
      final a = norm(contour.first);
      final b = norm(contour.last);
      // Compare against eye midline (the point between the two eye
      // centers); the corner closer to it is the inner corner.
      final dxA = (a.dx * imgW - eyeMidlineX).abs();
      final dxB = (b.dx * imgW - eyeMidlineX).abs();
      return dxA < dxB ? a : b;
    }

    Offset _outerOf(List<math.Point<int>> contour) {
      final a = norm(contour.first);
      final b = norm(contour.last);
      final dxA = (a.dx * imgW - eyeMidlineX).abs();
      final dxB = (b.dx * imgW - eyeMidlineX).abs();
      return dxA < dxB ? b : a;
    }

    final leftInner  = _innerOf(leftEyeContour);
    final leftOuter  = _outerOf(leftEyeContour);
    final rightInner = _innerOf(rightEyeContour);
    final rightOuter = _outerOf(rightEyeContour);

    // Tilt per eye: angle of inner→outer line vs horizontal.
    // Positive = outer corner sits ABOVE inner corner on screen
    // (cat eye / "hunter"). We use the absolute horizontal distance
    // so both eyes feed into the same sign convention regardless of
    // which side of the face they're on.
    double _eyeTilt(Offset inner, Offset outer) {
      final dx = (outer.dx - inner.dx).abs();
      // Screen-y grows downward; outer.dy < inner.dy means outer is
      // physically higher than inner. Negate so positive = up.
      final dyUp = -(outer.dy - inner.dy);
      return math.atan2(dyUp, dx) * 180 / math.pi;
    }

    final canthalTilt = (_eyeTilt(leftInner, leftOuter) +
                         _eyeTilt(rightInner, rightOuter)) / 2;

    // ── Face bounding box from oval ────────────────────────────────────────
    final ovalXs = faceOval.map((p) => p.x.toDouble()).toList();
    final ovalYs = faceOval.map((p) => p.y.toDouble()).toList();
    final faceLeft   = ovalXs.reduce(math.min);
    final faceRight  = ovalXs.reduce(math.max);
    final faceTop    = ovalYs.reduce(math.min);
    final faceBottom = ovalYs.reduce(math.max);
    final faceWidth  = faceRight - faceLeft;
    final faceHeight = faceBottom - faceTop;

    if (faceWidth < 10 || faceHeight < 10) {
      return const FaceGeometry(
        canthalTilt: 0, symmetryScore: 70, facialThirdTop: 33,
        facialThirdMid: 33, facialThirdLow: 34, fwhr: 1.9,
        eyeSpacingRatio: 0.46, jawAngle: 125, chinProjection: 0,
        hasReliableData: false,
      );
    }

    // ── Symmetry ──────────────────────────────────────────────────────────
    // Old impl compared only eye-center X offsets from the face midline. That
    // trips `symmetryScore >= 85` for almost everyone because there's only
    // one signal — and nobody sends an asymmetric selfie facing straight on.
    // We now average horizontal midline deviation across 4 paired features:
    // eye centers, eyebrow centroids, mouth corners, and upper jaw edges.
    // Each pair's contribution is the |leftΔ - rightΔ| / faceWidth, then
    // averaged. Scale 8.0 tuned so elite-symmetric faces still peak near 95.
    final faceCX = (faceLeft + faceRight) / 2;
    double centroidX(List<math.Point<int>> pts) =>
        pts.isEmpty ? faceCX
            : pts.map((p) => p.x.toDouble()).reduce((a, b) => a + b) / pts.length;

    final pairOffsets = <double>[];

    // Pair 1 — eye centers (always present given hasData guard).
    pairOffsets.add(
      ((faceCX - leftEyeCX).abs() - (rightEyeCX - faceCX).abs()).abs() / faceWidth);

    // Pair 2 — eyebrow centroids (skip if either side missing).
    if (leftEyebrow.isNotEmpty && rightEyebrow.isNotEmpty) {
      final lbX = centroidX(leftEyebrow);
      final rbX = centroidX(rightEyebrow);
      pairOffsets.add(
        ((faceCX - lbX).abs() - (rbX - faceCX).abs()).abs() / faceWidth);
    }

    // Pair 3 — mouth corners (first & last points on upperLipTop are the
    // left and right corners in ML Kit's ordering).
    if (upperLipTop.length >= 2) {
      final lmx = upperLipTop.first.x.toDouble();
      final rmx = upperLipTop.last.x.toDouble();
      pairOffsets.add(
        ((faceCX - lmx).abs() - (rmx - faceCX).abs()).abs() / faceWidth);
    }

    // Pair 4 — upper jaw width. Take oval points near the cheekbone band
    // and compare leftmost vs rightmost distance from centerline.
    if (faceOval.length >= 8) {
      final cheekBandY = faceTop + faceHeight * 0.42;
      final cheekBand = faceOval
          .where((p) => (p.y - cheekBandY).abs() < faceHeight * 0.08)
          .toList();
      if (cheekBand.length >= 2) {
        final ljx = cheekBand.map((p) => p.x.toDouble()).reduce(math.min);
        final rjx = cheekBand.map((p) => p.x.toDouble()).reduce(math.max);
        pairOffsets.add(
          ((faceCX - ljx).abs() - (rjx - faceCX).abs()).abs() / faceWidth);
      }
    }

    final meanOffset = pairOffsets.reduce((a, b) => a + b) / pairOffsets.length;
    final symmetryScore = ((1.0 - meanOffset * 8.0).clamp(0.4, 1.0) * 100);

    // ── FWHR ──────────────────────────────────────────────────────────────
    // Width at cheekbones (approx middle of face oval)
    final midY        = (faceTop + faceBottom) / 2;
    final cheekPoints = faceOval.where((p) => (p.y - midY).abs() < faceHeight * 0.15);
    final cheekWidth  = cheekPoints.isEmpty
        ? faceWidth
        : (cheekPoints.map((p) => p.x.toDouble()).reduce(math.max) -
               cheekPoints.map((p) => p.x.toDouble()).reduce(math.min));
    // Height: brow to upper lip
    final browY      = leftEyebrow.isNotEmpty
        ? leftEyebrow.map((p) => p.y.toDouble()).reduce(math.min)
        : leftEyeCY - faceHeight * 0.05;
    final noseBaseY  = noseBottom.isNotEmpty
        ? noseBottom.map((p) => p.y.toDouble()).reduce(math.max)
        : leftEyeCY + faceHeight * 0.3;
    final upperLipY  = noseBaseY + (faceBottom - noseBaseY) * 0.3;
    final fwhrHeight = (upperLipY - browY).abs();
    final fwhr       = fwhrHeight > 0 ? cheekWidth / fwhrHeight : 1.9;

    // ── Facial thirds ─────────────────────────────────────────────────────
    final hairlineY = faceTop;
    final chin      = faceBottom;
    final totalH    = chin - hairlineY;
    final browYNorm = browY;
    final noseBaseYNorm = noseBaseY;

    final topThird  = (browYNorm - hairlineY) / totalH * 100;
    final midThird  = (noseBaseYNorm - browYNorm) / totalH * 100;
    final lowThird  = (chin - noseBaseYNorm) / totalH * 100;

    // ── Eye spacing ratio ─────────────────────────────────────────────────
    final interocular   = (rightEyeCX - leftEyeCX).abs();
    final eyeSpacingRatio = interocular / faceWidth;

    // ── Jaw angle (chin apex, kept for descriptive text only) ─────────────
    // This is the angle AT THE CHIN POINT formed by the two
    // chin→gonial vectors. It is NOT a real gonial angle (those need
    // a side profile) — closer to a chin-pointiness proxy. We keep
    // computing it because the chat / protocol templates reference
    // the literal "your jaw angle is 122°" string. Score-wise, it
    // is no longer used; jawWidthRatio (below) drives the jaw axis.
    double jawAngle = 125;
    if (faceOval.length >= 16) {
      final bottomPoints = faceOval
          .where((p) => p.y > faceTop + faceHeight * 0.65)
          .toList();
      if (bottomPoints.length >= 3) {
        final leftJaw  = bottomPoints
            .reduce((a, b) => a.x < b.x ? a : b);
        final rightJaw = bottomPoints
            .reduce((a, b) => a.x > b.x ? a : b);
        final chinPt   = bottomPoints
            .reduce((a, b) => a.y > b.y ? a : b);
        final v1x = leftJaw.x - chinPt.x;
        final v1y = leftJaw.y - chinPt.y;
        final v2x = rightJaw.x - chinPt.x;
        final v2y = rightJaw.y - chinPt.y;
        final dot = v1x * v2x + v1y * v2y;
        final mag = math.sqrt(v1x * v1x + v1y * v1y) *
                    math.sqrt(v2x * v2x + v2y * v2y);
        if (mag > 0) jawAngle = math.acos((dot / mag).clamp(-1.0, 1.0)) * 180 / math.pi;
      }
    }

    // ── Jaw width ratio — REAL frontal-photo jaw definition metric ────────
    // bigonial = jaw width measured at the gonial Y-band (the corners
    // of the jaw, ~70% down the face oval). bizygomatic = cheekbone
    // width measured at the zygomatic Y-band (~40% down). Their
    // ratio is the standard masculinity proxy from frontal anthro-
    // pometric photos:
    //   • Strong wide masculine jaw  → ratio ≥ 0.85
    //   • Soft V-shape feminine chin → ratio ≤ 0.75
    //   • Real range across faces    ≈ 0.65 .. 0.95
    // This replaces the old chin-apex angle as the score driver
    // because the apex angle perversely rewarded pointy chins and
    // penalised wide square jaws — the opposite of what users
    // experience as "good jaw".
    double jawWidthRatio = 0.80;
    if (faceOval.length >= 12 && faceWidth > 0) {
      // Gonial band: ~65–80% down the face oval.
      final gonialBand = faceOval.where((p) =>
        p.y >= faceTop + faceHeight * 0.65 &&
        p.y <= faceTop + faceHeight * 0.80
      ).toList();
      // Zygomatic band: ~32–48% down (cheekbone region).
      final zygoBand = faceOval.where((p) =>
        p.y >= faceTop + faceHeight * 0.32 &&
        p.y <= faceTop + faceHeight * 0.48
      ).toList();
      if (gonialBand.length >= 2 && zygoBand.length >= 2) {
        final gonialW = gonialBand.map((p) => p.x.toDouble()).reduce(math.max) -
                        gonialBand.map((p) => p.x.toDouble()).reduce(math.min);
        final zygoW   = zygoBand.map((p) => p.x.toDouble()).reduce(math.max) -
                        zygoBand.map((p) => p.x.toDouble()).reduce(math.min);
        if (zygoW > 0) jawWidthRatio = (gonialW / zygoW).clamp(0.5, 1.1);
      }
    }

    // ── Nose/chin projection ─────────────────────────────────────────────
    final noseTipY   = noseBridge.isNotEmpty
        ? noseBridge.map((p) => p.y.toDouble()).reduce(math.max)
        : 0.0;
    final chinProjection = faceHeight > 0
        ? (faceBottom - noseTipY) / faceHeight
        : 0.0;

    // ── Face length / head shape ──────────────────────────────────────────
    final faceLengthRatio = faceWidth > 0 ? faceHeight / faceWidth : 1.3;
    final String headShape;
    if (faceLengthRatio >= 1.45) {
      headShape = 'long';
    } else if (faceLengthRatio <= 1.15) {
      headShape = 'broad';
    } else if (fwhr >= 2.0 && jawAngle <= 120) {
      headShape = 'square';
    } else if (faceLengthRatio >= 1.25 && faceLengthRatio <= 1.38) {
      headShape = 'oval';
    } else {
      headShape = 'round';
    }

    // ── Nose length ratio (nose / mid-third height) ──────────────────────
    final noseTopY   = noseBridge.isNotEmpty
        ? noseBridge.map((p) => p.y.toDouble()).reduce(math.min)
        : browY + faceHeight * 0.02;
    final midThirdHeight = (noseBaseY - browY).abs();
    final noseLengthRatio = midThirdHeight > 0
        ? (noseTipY - noseTopY).abs() / midThirdHeight
        : 0.3;

    // ── Lip fullness (total lip area / face width) ───────────────────────
    double lipFullness = 0.5;
    if (upperLipTop.isNotEmpty && lowerLipBottom.isNotEmpty) {
      final lipTop    = upperLipTop.map((p) => p.y.toDouble()).reduce(math.min);
      final lipBottom = lowerLipBottom.map((p) => p.y.toDouble()).reduce(math.max);
      final lipH      = (lipBottom - lipTop).abs();
      lipFullness = faceHeight > 0 ? (lipH / faceHeight * 10).clamp(0.0, 1.0) : 0.5;
    }

    // ── Brow-to-eye gap (vertical) — average both sides ──────────────────
    // Old impl only used the left brow; users with asymmetric brow height
    // got a one-sided reading. Average the two sides when both contours
    // are available, fall back to whichever one we have.
    double brow2EyeGap = 0.04;
    final hasLeftBrow = leftEyebrow.isNotEmpty;
    final hasRightBrow = rightEyebrow.isNotEmpty;
    if (faceHeight > 0 && (hasLeftBrow || hasRightBrow)) {
      final samples = <double>[];
      if (hasLeftBrow) {
        final browBottomY = leftEyebrow.map((p) => p.y.toDouble()).reduce(math.max);
        samples.add((leftEyeCY - browBottomY).abs() / faceHeight);
      }
      if (hasRightBrow) {
        final browBottomY = rightEyebrow.map((p) => p.y.toDouble()).reduce(math.max);
        samples.add((rightEyeCY - browBottomY).abs() / faceHeight);
      }
      brow2EyeGap = (samples.reduce((a, b) => a + b) / samples.length)
          .clamp(0.0, 0.2);
    }

    // ── Philtrum ratio (nose base → upper lip top / lower third) ─────────
    double philtrumRatio = 0.35;
    if (upperLipTop.isNotEmpty) {
      final lipTop = upperLipTop.map((p) => p.y.toDouble()).reduce(math.min);
      final lowerThirdH = (chin - noseBaseY).abs();
      philtrumRatio = lowerThirdH > 0
          ? ((lipTop - noseBaseY).abs() / lowerThirdH).clamp(0.0, 1.0)
          : 0.35;
    }

    // ── Interpupillary ratio ─────────────────────────────────────────────
    final interpupillaryRatio = faceWidth > 0
        ? ((rightEyeCX - leftEyeCX).abs() / faceWidth).clamp(0.15, 0.8)
        : 0.46;

    // Touch intermediate contours so Dart doesn't warn — reserved for
    // future metrics (philtrum detail, lip corner angle, etc.).
    upperLipBottom.length + lowerLipTop.length;

    return FaceGeometry(
      canthalTilt: canthalTilt.clamp(-10.0, 10.0),
      symmetryScore: symmetryScore.clamp(0.0, 100.0),
      facialThirdTop: topThird.clamp(0.0, 100.0),
      facialThirdMid: midThird.clamp(0.0, 100.0),
      facialThirdLow: lowThird.clamp(0.0, 100.0),
      fwhr: fwhr.clamp(1.0, 3.0),
      eyeSpacingRatio: eyeSpacingRatio.clamp(0.2, 0.8),
      jawAngle: jawAngle.clamp(80.0, 180.0),
      chinProjection: chinProjection.clamp(0.0, 0.5),
      faceLengthRatio:     faceLengthRatio.clamp(0.8, 2.0),
      noseLengthRatio:     noseLengthRatio.clamp(0.1, 1.0),
      lipFullness:         lipFullness,
      brow2EyeGap:         brow2EyeGap,
      philtrumRatio:       philtrumRatio,
      interpupillaryRatio: interpupillaryRatio,
      headShape:           headShape,
      jawWidthRatio:       jawWidthRatio,
      hasReliableData: true,
    );
  }

}
