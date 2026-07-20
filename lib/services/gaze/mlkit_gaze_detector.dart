import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../models/face_metrics.dart';
import 'gaze_detector.dart';

/// MLKit-backed detector.
///
/// Combines three threads of work:
///
///   1. Main-branch rotation-aware preview-space normalization (ported
///      VERBATIM from ImHim's scan_screen._normalize) — all positional
///      output is in preview-space 0..1, ready to plot in a CustomPaint
///      sitting as a CHILD of CameraPreview. Grouped contours per
///      FaceContourType.name so the painter draws each region (face oval,
///      left eye, right eye, lips, nose, brows) as its own polyline.
///
///   2. Tightened eye-contact sensitivity — yaw sigmoid divisor dropped
///      from 30 → 15 so small head turns actually move the needle.
///
///   3. Calibrated eye-aperture signal — per-session baseline for head yaw
///      and eye-contour aperture. Catches vertical gaze shifts (upper lid
///      retracts looking up, drops looking down) the old scorer missed.
///      Runs 3 extra signals into the gaze fusion on top of main's 15°
///      yaw score.
///
///   4. Four-dimension charisma sub-scores (Presence/Composure/Warmth/Range)
///      computed per frame so the live HUD + post-session verdict can
///      speak in the new dimensions.
///
/// Does NOT track iris position — only MediaPipe gets you that. See
/// MediaPipeGazeDetector for the elite path.
class MlkitGazeDetector implements GazeDetector {
  @override String get engineName => 'MLKit';
  @override bool get hasIris => false;

  late final FaceDetector _detector;
  bool _initialized = false;

  // ── Rolling history ────────────────────────────────────────────────────
  final List<double> _leftEyeOpenHist  = [];
  final List<double> _rightEyeOpenHist = [];
  final List<DateTime> _blinkTimestamps = [];
  final List<double> _yawHist   = [];
  final List<double> _pitchHist = [];
  final List<double> _rollHist  = [];
  final List<double> _smileHist = [];
  final List<double> _apertureHist = [];

  static const int _poseWindow  = 12;  // ~400ms @ 30fps
  static const int _rangeWindow = 90;  // ~3s
  static const double _blinkThreshold = 0.25;

  // ── Calibration baseline ───────────────────────────────────────────────
  double? _baselineYaw;
  double? _baselinePitch;
  double? _baselineEyeApertureL;
  double? _baselineEyeApertureR;

  bool _calibrating = false;
  DateTime? _calibrationDeadline;
  final List<double> _calYaw = [];
  final List<double> _calPitch = [];
  final List<double> _calApertureL = [];
  final List<double> _calApertureR = [];

  @override bool get isCalibrated => _baselineYaw != null;

  @override
  Future<void> init() async {
    if (_initialized) return;
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableLandmarks: true,
        enableContours: true,
        enableClassification: true,
        enableTracking: true,
        minFaceSize: 0.15,
      ),
    );
    _initialized = true;
  }

  @override
  void startCalibration({Duration duration = const Duration(seconds: 3)}) {
    _calibrating = true;
    _calibrationDeadline = DateTime.now().add(duration);
    _calYaw.clear();
    _calPitch.clear();
    _calApertureL.clear();
    _calApertureR.clear();
  }

  @override
  void resetCalibration() {
    _baselineYaw = null;
    _baselinePitch = null;
    _baselineEyeApertureL = null;
    _baselineEyeApertureR = null;
    _calibrating = false;
    _calibrationDeadline = null;
    _calYaw.clear();
    _calPitch.clear();
    _calApertureL.clear();
    _calApertureR.clear();
  }

  @override
  Future<FaceMetrics?> process(
    CameraImage image,
    int sensorOrientation, {
    bool isFrontCam = true,
  }) async {
    if (!_initialized) return null;

    final rotation = Platform.isIOS
        ? InputImageRotation.rotation0deg
        : _rotFromSensor(sensorOrientation);

    final input = _toInputImage(image, rotation);
    if (input == null) return null;

    final faces = await _detector.processImage(input);
    if (faces.isEmpty) return null;

    final face = faces.reduce((a, b) =>
        a.boundingBox.width > b.boundingBox.width ? a : b);

    return _extract(
      face,
      image.width.toDouble(),
      image.height.toDouble(),
      isFrontCam: isFrontCam,
      rotation: rotation,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Metric extraction
  // ═══════════════════════════════════════════════════════════════════════

  FaceMetrics _extract(
    Face face,
    double imgW,
    double imgH, {
    required bool isFrontCam,
    required InputImageRotation rotation,
  }) {
    final yaw   = face.headEulerAngleY ?? 0.0;
    final pitch = face.headEulerAngleX ?? 0.0;
    final roll  = face.headEulerAngleZ ?? 0.0;

    _push(_yawHist,   yaw,   _poseWindow);
    _push(_pitchHist, pitch, _poseWindow);
    _push(_rollHist,  roll,  _poseWindow);

    // ── Rotation-aware preview-space normalizer (from main/ImHim Looks) ─────
    //
    // ML Kit returns landmarks in the ROTATED UPRIGHT frame, not the raw
    // sensor frame. For a portrait phone with a landscape sensor at
    // rotation 270°, landmark x maxes at sensor HEIGHT — that's why the
    // 90/270 branches divide by imgH, not imgW.
    //
    // Rotation 270° ALREADY bakes in a horizontal flip — do NOT add an
    // extra front-cam mirror in that branch (double-flip = overlay on the
    // wrong side).
    Offset norm(double bx, double by) {
      double nx, ny;
      switch (rotation) {
        case InputImageRotation.rotation90deg:
          nx = bx / imgH;
          ny = by / imgW;
          break;
        case InputImageRotation.rotation270deg:
          nx = 1.0 - bx / imgH;
          ny = by / imgW;
          break;
        case InputImageRotation.rotation0deg:
        case InputImageRotation.rotation180deg:
          nx = bx / imgW;
          ny = by / imgH;
          if (isFrontCam) nx = 1.0 - nx;
          break;
      }
      return Offset(nx.clamp(0.0, 1.0), ny.clamp(0.0, 1.0));
    }

    // ── Grouped contours + flat legacy list ──────────────────────────────
    final contourMap = <String, List<Offset>>{};
    final contourFlat = <Offset>[];
    for (final type in FaceContourType.values) {
      final contour = face.contours[type];
      if (contour == null || contour.points.isEmpty) continue;
      final pts = <Offset>[];
      for (final p in contour.points) {
        final n = norm(p.x.toDouble(), p.y.toDouble());
        pts.add(n);
        contourFlat.add(n);
      }
      contourMap[type.name] = pts;
    }

    // ── Eye aperture from contour polygon (independent of head pose) ─────
    // height/width of the eye contour's axis-aligned bbox. Drops when lids
    // close, rises when looking up — gives us a vertical-gaze signal the
    // pure yaw scorer can't see.
    final leftAp  = _eyeAperture(face.contours[FaceContourType.leftEye]);
    final rightAp = _eyeAperture(face.contours[FaceContourType.rightEye]);

    _maybeSampleCalibration(yaw, pitch, leftAp, rightAp);

    // ── Face bbox in preview space (for oval guide painter) ──────────────
    final bb = face.boundingBox;
    final rectTL = norm(bb.left,  bb.top);
    final rectBR = norm(bb.right, bb.bottom);
    final faceRect = Rect.fromLTRB(
      rectTL.dx < rectBR.dx ? rectTL.dx : rectBR.dx,
      rectTL.dy,
      rectTL.dx > rectBR.dx ? rectTL.dx : rectBR.dx,
      rectBR.dy,
    );
    final bbCenter = face.boundingBox.center;
    final fc = norm(bbCenter.dx, bbCenter.dy);
    final faceW = (face.boundingBox.width / imgW).clamp(0.0, 1.0);

    // ── Eye landmark positions (preview space) ───────────────────────────
    final leftLm  = face.landmarks[FaceLandmarkType.leftEye];
    final rightLm = face.landmarks[FaceLandmarkType.rightEye];
    final leftEyePos  = leftLm  != null
        ? norm(leftLm.position.x.toDouble(), leftLm.position.y.toDouble())
        : null;
    final rightEyePos = rightLm != null
        ? norm(rightLm.position.x.toDouble(), rightLm.position.y.toDouble())
        : null;

    // ── Eye open / blink / smile ─────────────────────────────────────────
    final leftOpen  = face.leftEyeOpenProbability  ?? 1.0;
    final rightOpen = face.rightEyeOpenProbability ?? 1.0;
    _detectBlink(leftOpen, rightOpen);
    final blinkRate = _blinkRate();

    final smileProb = face.smilingProbability ?? 0.0;
    final eyeContraction = (1.0 - (leftOpen + rightOpen) / 2.0).clamp(0.0, 1.0);
    final duchenne = (smileProb * 0.6 + eyeContraction * 0.4).clamp(0.0, 1.0);
    _push(_smileHist, duchenne, _rangeWindow);
    _push(_apertureHist, (leftOpen + rightOpen) / 2.0, _rangeWindow);

    // ── Composite eye-contact score ──────────────────────────────────────
    // Fuse main's 15°-tightened yaw with baseline-relative eye-aperture
    // deltas. Pre-calibration we fall back on yaw only (lower confidence).
    final gaze = _compositeGaze(
      yaw: yaw,
      leftAp: leftAp,
      rightAp: rightAp,
    );

    // ── Screen-space gaze point estimation ───────────────────────────────
    // Approximate where the user is looking on the preview by offsetting
    // the face center by their head pose. Front-cam preview is mirrored,
    // so for a user looking at preview-x = 1.0 (right edge), the camera
    // sees them turn LEFT (negative yaw). We undo the mirror with a
    // negation when isFrontCam.
    //
    // Yaw range ±25° spans the full preview width. Pitch ±20° spans full
    // height. These are tuned for a typical hand-held selfie viewing
    // distance — accurate enough for "is the user staring at this on-
    // screen target?" but not pixel-perfect (MediaPipe iris is the real
    // version of this).
    final yawDev = yaw - (_baselineYaw ?? 0.0);
    final pitchDev = pitch - (_baselinePitch ?? 0.0);
    final gazeOffsetX = (yawDev / 25.0).clamp(-0.5, 0.5);
    final gazeOffsetY = (pitchDev / 20.0).clamp(-0.5, 0.5);
    final gazeX = (fc.dx + (isFrontCam ? -gazeOffsetX : gazeOffsetX))
        .clamp(0.0, 1.0);
    final gazeY = (fc.dy + gazeOffsetY).clamp(0.0, 1.0);
    final gazePoint = Offset(gazeX, gazeY);

    final stability = _stability();

    // ── Four-dimension sub-scores ────────────────────────────────────────
    final presence  = _presence(gaze.score, stability);
    final warmth    = _warmth(duchenne, leftOpen, rightOpen);
    final composure = _composure(blinkRate, stability);
    final range     = _range();

    final overall = _compositeScore(
      presence: presence,
      warmth: warmth,
      composure: composure,
      range: range,
    );

    return FaceMetrics(
      eyeContactScore: gaze.score,
      gazeConfidence:  gaze.confidence,
      blinkRate:       blinkRate,
      smileAuthenticity: duchenne,
      headStability:   stability,
      presenceScore:   presence,
      warmthScore:     warmth,
      composureScore:  composure,
      rangeScore:      range,
      headPitch: pitch,
      headYaw:   yaw,
      headRoll:  roll,
      faceCenter: fc,
      faceSize: faceW,
      faceRect: faceRect,
      contourPoints: contourFlat,
      contours: contourMap,
      overallAura: overall,
      calibrated: isCalibrated,
      leftEyePos: leftEyePos,
      rightEyePos: rightEyePos,
      leftEyeAperture:  leftAp,
      rightEyeAperture: rightAp,
      gazePoint: gazePoint,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Gaze signal fusion (main's 15° yaw + my aperture deltas)
  // ═══════════════════════════════════════════════════════════════════════

  _Gaze _compositeGaze({
    required double yaw,
    required double? leftAp,
    required double? rightAp,
  }) {
    // Signal A — head yaw vs baseline (or absolute when uncalibrated).
    //   main tightened the divisor to 15. Keep that baseline sensitivity.
    final yawBaseline = _baselineYaw ?? 0.0;
    final yawDev = (yaw - yawBaseline).abs();
    final yawScore = _sigmoid(1.0 - yawDev / 15.0);

    // Signal B — eye aperture delta from baseline (vertical gaze).
    double apertureScore = 0.75;
    double apertureWeight = 0.0;
    if (leftAp != null && rightAp != null) {
      apertureWeight = 1.0;
      final lBase = _baselineEyeApertureL ?? leftAp;
      final rBase = _baselineEyeApertureR ?? rightAp;
      final lDelta = (leftAp  - lBase).abs();
      final rDelta = (rightAp - rBase).abs();
      final avgDelta = (lDelta + rDelta) / 2.0;
      apertureScore = _sigmoid(1.0 - avgDelta / 0.09);
    }

    // Signal C — eye aperture asymmetry (weak horizontal gaze proxy).
    double asymScore = 0.80;
    double asymWeight = 0.0;
    if (leftAp != null && rightAp != null) {
      asymWeight = 0.5;
      final asym = (leftAp - rightAp).abs();
      asymScore = _sigmoid(1.0 - asym / 0.18);
    }

    const yawWeight = 1.0;
    final totalW = yawWeight + apertureWeight + asymWeight;
    final fused = (yawScore * yawWeight +
                   apertureScore * apertureWeight +
                   asymScore * asymWeight) / totalW;

    final confidence = isCalibrated
        ? (apertureWeight > 0 ? 0.85 : 0.55)
        : 0.45;

    return _Gaze(score: fused.clamp(0.0, 1.0), confidence: confidence);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Eye aperture from 16-point contour polygon
  // ═══════════════════════════════════════════════════════════════════════

  double? _eyeAperture(FaceContour? contour) {
    if (contour == null || contour.points.length < 4) return null;
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final p in contour.points) {
      final x = p.x.toDouble();
      final y = p.y.toDouble();
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    final w = maxX - minX;
    final h = maxY - minY;
    if (w <= 0) return null;
    return (h / w).clamp(0.0, 1.5);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Calibration sampling
  // ═══════════════════════════════════════════════════════════════════════

  void _maybeSampleCalibration(
    double yaw,
    double pitch,
    double? leftAp,
    double? rightAp,
  ) {
    if (!_calibrating) return;
    _calYaw.add(yaw);
    _calPitch.add(pitch);
    if (leftAp  != null) _calApertureL.add(leftAp);
    if (rightAp != null) _calApertureR.add(rightAp);

    final now = DateTime.now();
    if (_calibrationDeadline != null && now.isAfter(_calibrationDeadline!)) {
      _baselineYaw   = _median(_calYaw);
      _baselinePitch = _median(_calPitch);
      _baselineEyeApertureL = _calApertureL.isNotEmpty ? _median(_calApertureL) : null;
      _baselineEyeApertureR = _calApertureR.isNotEmpty ? _median(_calApertureR) : null;
      _calibrating = false;
      _calibrationDeadline = null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Four-dimension sub-scores
  // ═══════════════════════════════════════════════════════════════════════

  double _presence(double gaze, double stability) =>
      (gaze * 0.65 + stability * 0.35).clamp(0.0, 1.0);

  double _warmth(double duchenne, double lOpen, double rOpen) {
    final softness = 1.0 - ((lOpen + rOpen) / 2.0 - 0.7).abs() / 0.3;
    return (duchenne * 0.75 + softness.clamp(0.0, 1.0) * 0.25).clamp(0.0, 1.0);
  }

  double _composure(double blinkRate, double stability) {
    double b;
    if (blinkRate == 0)          { b = 0.6; }
    else if (blinkRate < 8)      { b = blinkRate / 8.0; }
    else if (blinkRate <= 18)    { b = 1.0; }
    else                         { b = math.max(0, 1.0 - (blinkRate - 18) / 14.0); }
    return (b * 0.55 + stability * 0.45).clamp(0.0, 1.0);
  }

  double _range() {
    if (_smileHist.length < 15) return 0.5;
    final sV = _variance(_smileHist);
    final aV = _variance(_apertureHist);
    final sR = math.exp(-math.pow((sV - 0.02) / 0.03, 2).toDouble());
    final aR = math.exp(-math.pow((aV - 0.015) / 0.025, 2).toDouble());
    return ((sR + aR) / 2.0).clamp(0.0, 1.0);
  }

  double _compositeScore({
    required double presence,
    required double warmth,
    required double composure,
    required double range,
  }) {
    const wP = 0.42, wC = 0.26, wW = 0.20, wR = 0.12;
    final raw = presence * wP + composure * wC + warmth * wW + range * wR;
    return (raw * 100).clamp(0, 100);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Blink detection
  // ═══════════════════════════════════════════════════════════════════════

  void _detectBlink(double leftOpen, double rightOpen) {
    _push(_leftEyeOpenHist,  leftOpen,  8);
    _push(_rightEyeOpenHist, rightOpen, 8);
    if (_leftEyeOpenHist.length < 3) return;

    final n = _leftEyeOpenHist.length;
    final prev = (_leftEyeOpenHist[n - 2] + _rightEyeOpenHist[n - 2]) / 2;
    final curr = (_leftEyeOpenHist[n - 1] + _rightEyeOpenHist[n - 1]) / 2;
    if (prev < _blinkThreshold && curr >= _blinkThreshold) {
      _blinkTimestamps.add(DateTime.now());
      final cutoff = DateTime.now().subtract(const Duration(seconds: 60));
      _blinkTimestamps.removeWhere((t) => t.isBefore(cutoff));
    }
  }

  double _blinkRate() {
    if (_blinkTimestamps.isEmpty) return 0;
    final cutoff = DateTime.now().subtract(const Duration(seconds: 60));
    return _blinkTimestamps.where((t) => t.isAfter(cutoff)).length.toDouble();
  }

  double _stability() {
    if (_yawHist.length < 4) return 1.0;
    final v = (_variance(_yawHist) + _variance(_pitchHist) + _variance(_rollHist)) / 3.0;
    return _sigmoid(1.0 - v / 14.0);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Platform image bridge
  // ═══════════════════════════════════════════════════════════════════════

  InputImage? _toInputImage(CameraImage image, InputImageRotation rotation) {
    final format = Platform.isAndroid
        ? InputImageFormat.nv21
        : InputImageFormat.bgra8888;
    final plane = image.planes.first;
    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: plane.bytesPerRow,
    );
    return InputImage.fromBytes(bytes: plane.bytes, metadata: metadata);
  }

  InputImageRotation _rotFromSensor(int deg) {
    switch (deg) {
      case 90:  return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default:  return InputImageRotation.rotation0deg;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Utilities
  // ═══════════════════════════════════════════════════════════════════════

  void _push(List<double> list, double v, int cap) {
    list.add(v);
    if (list.length > cap) list.removeAt(0);
  }

  double _variance(List<double> xs) {
    if (xs.isEmpty) return 0;
    final mean = xs.reduce((a, b) => a + b) / xs.length;
    double s = 0;
    for (final x in xs) { s += (x - mean) * (x - mean); }
    return s / xs.length;
  }

  double _median(List<double> xs) {
    if (xs.isEmpty) return 0;
    final s = List<double>.from(xs)..sort();
    final n = s.length;
    return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
  }

  double _sigmoid(double x) => 1.0 / (1.0 + math.exp(-x * 5));

  @override
  Future<void> dispose() async {
    if (_initialized) {
      await _detector.close();
      _initialized = false;
    }
  }
}

class _Gaze {
  final double score;
  final double confidence;
  const _Gaze({required this.score, required this.confidence});
}
