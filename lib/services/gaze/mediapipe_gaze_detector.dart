import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import '../../models/face_metrics.dart';
import 'gaze_detector.dart';

/// MediaPipe-backed detector — ELITE iris tracking.
///
/// Runs MediaPipe Tasks FaceLandmarker (refineLandmarks=true) on the native
/// side and returns a 478-point mesh including the 10 iris landmarks
/// (indices 468–477). With iris centers in image coords we can compute a
/// real gaze vector independent of head pose — the thing the MLKit path
/// physically cannot do.
///
/// ─────────────────────────────────────────────────────────────────────────
///  SETUP CHECKLIST (before flipping GazeEngine.mediapipe):
/// ─────────────────────────────────────────────────────────────────────────
///
///   1. Download the model (3.8 MB) and drop it at:
///        assets/models/face_landmarker.task
///
///      Source: https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task
///
///      Add to pubspec.yaml assets block.
///
///   2. Android — add to android/app/build.gradle.kts dependencies:
///
///        implementation("com.google.mediapipe:tasks-vision:0.10.14")
///
///      Ensure minSdk >= 24 (MediaPipe Tasks requirement).
///
///   3. iOS — create ios/Podfile if absent, add to target 'Runner':
///
///        pod 'MediaPipeTasksVision', '~> 0.10.14'
///
///      Then: `cd ios && pod install`.
///
///   4. Native plugin files (shipped in this branch):
///        android/app/src/main/kotlin/com/auralay/app/MediaPipeFaceLandmarkerPlugin.kt
///        ios/Runner/MediaPipeFaceLandmarkerPlugin.swift
///
///      Both register on the method channel `auralay/mediapipe_face`.
///
///   5. In `main.dart` or your service boot code, switch:
///        final detector = FaceDetectorService(engine: GazeEngine.mediapipe);
///
/// ─────────────────────────────────────────────────────────────────────────
///
/// Until the native plugin is wired + the model is shipped, [init] will
/// throw with a clear message and the app should fall back to MLKit.
class MediaPipeGazeDetector implements GazeDetector {
  @override String get engineName => 'MediaPipe (Iris)';
  @override bool get hasIris => true;

  static const _channel = MethodChannel('auralay/mediapipe_face');

  bool _initialized = false;

  // ── Calibration baseline (gaze vector in normalized image space) ───────
  double? _baselineGazeX;
  double? _baselineGazeY;
  double? _baselineYaw;
  double? _baselinePitch;
  bool _calibrating = false;
  DateTime? _calibrationDeadline;
  final List<double> _calGazeX = [];
  final List<double> _calGazeY = [];
  final List<double> _calYaw = [];
  final List<double> _calPitch = [];

  // ── Blink / smile / stability history (mirrors MLKit impl) ─────────────
  final List<double> _eyeOpenHist = [];
  final List<DateTime> _blinkTs = [];
  final List<double> _yawHist = [];
  final List<double> _pitchHist = [];
  final List<double> _rollHist = [];
  final List<double> _smileHist = [];
  final List<double> _browHist = [];

  @override bool get isCalibrated => _baselineGazeX != null && _baselineYaw != null;

  @override
  Future<void> init() async {
    if (_initialized) return;
    try {
      final bool ready = await _channel.invokeMethod<bool>('init') ?? false;
      if (!ready) {
        throw StateError(
          'MediaPipe plugin returned init=false — check that the model '
          'asset (assets/models/face_landmarker.task) is bundled.',
        );
      }
      _initialized = true;
    } on MissingPluginException {
      throw StateError(
        'MediaPipe native plugin not registered. Run pod install on iOS '
        'and confirm MediaPipeFaceLandmarkerPlugin is wired into MainActivity / '
        'AppDelegate. See header of mediapipe_gaze_detector.dart for setup.',
      );
    }
  }

  @override
  void startCalibration({Duration duration = const Duration(seconds: 3)}) {
    _calibrating = true;
    _calibrationDeadline = DateTime.now().add(duration);
    _calGazeX.clear();
    _calGazeY.clear();
    _calYaw.clear();
    _calPitch.clear();
  }

  @override
  void resetCalibration() {
    _baselineGazeX = null;
    _baselineGazeY = null;
    _baselineYaw = null;
    _baselinePitch = null;
    _calibrating = false;
    _calibrationDeadline = null;
    _calGazeX.clear();
    _calGazeY.clear();
    _calYaw.clear();
    _calPitch.clear();
  }

  @override
  Future<FaceMetrics?> process(
    CameraImage image,
    int sensorOrientation, {
    bool isFrontCam = true,
  }) async {
    if (!_initialized) return null;

    // Marshal first-plane bytes + metadata to native side. The native plugin
    // wraps them in MPImage / MPPImage and runs the landmarker in live-stream
    // mode. Returns a compact metrics dict — no 478 landmarks over the wire.
    final plane = image.planes.first;
    try {
      final Map<dynamic, dynamic>? result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('detect', {
        'bytes': plane.bytes,
        'width': image.width,
        'height': image.height,
        'bytesPerRow': plane.bytesPerRow,
        'rotation': Platform.isAndroid ? sensorOrientation : 0,
        'format': Platform.isAndroid ? 'nv21' : 'bgra8888',
        'timestampMs': DateTime.now().millisecondsSinceEpoch,
      });

      if (result == null) return null;
      final hasFace = result['face'] as bool? ?? false;
      if (!hasFace) return null;

      return _buildMetrics(result, image.width.toDouble(), image.height.toDouble());
    } on PlatformException {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Metrics from native payload
  // ═══════════════════════════════════════════════════════════════════════

  FaceMetrics _buildMetrics(
    Map<dynamic, dynamic> r,
    double imgW,
    double imgH,
  ) {
    // Expected native payload keys:
    //   face:           bool
    //   yaw, pitch, roll: double (degrees)
    //   leftIris:       [x, y]  normalized 0..1
    //   rightIris:      [x, y]  normalized 0..1
    //   leftEyeCenter:  [x, y]  normalized 0..1
    //   rightEyeCenter: [x, y]  normalized 0..1
    //   leftEyeOpen:    double 0..1
    //   rightEyeOpen:   double 0..1
    //   smile:          double 0..1 (blendshape mouthSmile averaged L+R)
    //   bboxCenter:     [x, y]
    //   bboxWidth:      double
    final yaw   = (r['yaw']   as num?)?.toDouble() ?? 0.0;
    final pitch = (r['pitch'] as num?)?.toDouble() ?? 0.0;
    final roll  = (r['roll']  as num?)?.toDouble() ?? 0.0;
    _push(_yawHist, yaw, 12);
    _push(_pitchHist, pitch, 12);
    _push(_rollHist, roll, 12);

    final leftIris  = _offsetFrom(r['leftIris']);
    final rightIris = _offsetFrom(r['rightIris']);
    final leftEye   = _offsetFrom(r['leftEyeCenter']);
    final rightEye  = _offsetFrom(r['rightEyeCenter']);

    // Iris-in-socket offset — the real gaze signal.
    // Positive x = iris sits toward the OUTER corner of that eye (looking away
    // from center). Normalized by eye width so it's pose-invariant.
    double? gazeX;
    double? gazeY;
    if (leftIris != null && rightIris != null && leftEye != null && rightEye != null) {
      gazeX = ((leftIris.dx - leftEye.dx) + (rightIris.dx - rightEye.dx)) / 2.0;
      gazeY = ((leftIris.dy - leftEye.dy) + (rightIris.dy - rightEye.dy)) / 2.0;
    }

    // bboxCenter from native payload — used both for the FaceMetrics
    // faceCenter field below AND for projecting iris offset into screen
    // space here.
    final bboxCenter = _offsetFrom(r['bboxCenter']) ?? const Offset(0.5, 0.5);
    final bboxWidth  = (r['bboxWidth'] as num?)?.toDouble() ?? 0.4;

    // Screen-space gaze point — project iris offset + face position into
    // preview-space 0..1 coordinates. Iris offsets are in normalized image
    // space, scale by 4x because eye width is ~25% of expected gaze span.
    Offset? gazePoint;
    if (gazeX != null && gazeY != null) {
      final px = (bboxCenter.dx + gazeX * 4.0).clamp(0.0, 1.0);
      final py = (bboxCenter.dy + gazeY * 4.0).clamp(0.0, 1.0);
      gazePoint = Offset(px, py);
    }

    _maybeSampleCalibration(yaw, pitch, gazeX, gazeY);

    final leftOpen  = (r['leftEyeOpen']  as num?)?.toDouble() ?? 1.0;
    final rightOpen = (r['rightEyeOpen'] as num?)?.toDouble() ?? 1.0;
    _detectBlink((leftOpen + rightOpen) / 2.0);
    final blinkRate = _blinkRate();

    final smileProb = (r['smile'] as num?)?.toDouble() ?? 0.0;
    final eyeContraction = (1.0 - (leftOpen + rightOpen) / 2.0).clamp(0.0, 1.0);
    final duchenne = (smileProb * 0.6 + eyeContraction * 0.4).clamp(0.0, 1.0);
    _push(_smileHist, duchenne, 90);
    _push(_browHist, leftOpen + rightOpen, 90);

    // ── TRUE gaze score — iris offset from baseline ──────────────────────
    final gaze = _compositeGaze(gazeX, gazeY, yaw);

    final stability = _stability();

    final presence  = (gaze.score * 0.65 + stability * 0.35).clamp(0.0, 1.0);
    final warmth    = _warmth(duchenne, leftOpen, rightOpen);
    final composure = _composure(blinkRate, stability);
    final range     = _range();

    final overall = (
      presence * 0.42 +
      composure * 0.26 +
      warmth * 0.20 +
      range * 0.12
    ) * 100;

    // MediaPipe payload doesn't ship all 478 landmarks — but it DOES ship
    // the two eye rings so the face overlay can draw the tracking arcs.
    final leftEyePoly  = _poly(r['leftEyePoly']);
    final rightEyePoly = _poly(r['rightEyePoly']);
    final contours = <String, List<Offset>>{};
    if (leftEyePoly.isNotEmpty)  contours['leftEye']  = leftEyePoly;
    if (rightEyePoly.isNotEmpty) contours['rightEye'] = rightEyePoly;
    final contourFlat = <Offset>[...leftEyePoly, ...rightEyePoly];

    final halfW = bboxWidth / 2.0;
    final approxRect = Rect.fromLTWH(
      (bboxCenter.dx - halfW).clamp(0.0, 1.0),
      (bboxCenter.dy - halfW * 1.3).clamp(0.0, 1.0),
      bboxWidth.clamp(0.0, 1.0),
      (halfW * 2.6).clamp(0.0, 1.0),
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
      faceCenter: bboxCenter,
      faceSize: bboxWidth,
      faceRect: approxRect,
      contourPoints: contourFlat,
      contours: contours,
      overallAura: overall.clamp(0, 100),
      calibrated: isCalibrated,
      leftEyePos: leftEye,
      rightEyePos: rightEye,
      // Expose eye-open (0..1) as the aperture so the session screen's
      // blink edge-detector (aperture < 0.22 = closed) counts real blinks.
      leftEyeAperture:  leftOpen,
      rightEyeAperture: rightOpen,
      gazePoint: gazePoint,
    );
  }

  _Gaze _compositeGaze(double? gazeX, double? gazeY, double yaw) {
    // If we don't have iris data, degrade gracefully to yaw-only (which
    // is still better than nothing on calibration dropouts).
    if (gazeX == null || gazeY == null) {
      final yawDev = (yaw - (_baselineYaw ?? 0.0)).abs();
      return _Gaze(
        score: (1.0 / (1.0 + math.exp(-(1.0 - yawDev / 18.0) * 5))).clamp(0.0, 1.0),
        confidence: 0.4,
      );
    }

    final bx = _baselineGazeX ?? 0.0;
    final by = _baselineGazeY ?? 0.0;
    final dx = gazeX - bx;
    final dy = gazeY - by;
    // Magnitude of iris offset from calibrated center, in normalized units.
    // Empirically, |offset| > 0.025 = clearly looking elsewhere.
    final mag = math.sqrt(dx * dx + dy * dy);
    final irisScore = (1.0 / (1.0 + math.exp(-(1.0 - mag / 0.030) * 5))).clamp(0.0, 1.0);

    // Combine with head yaw (lower weight — iris is authoritative).
    final yawDev = (yaw - (_baselineYaw ?? 0.0)).abs();
    final yawScore = (1.0 / (1.0 + math.exp(-(1.0 - yawDev / 22.0) * 5))).clamp(0.0, 1.0);

    final fused = (irisScore * 0.80 + yawScore * 0.20).clamp(0.0, 1.0);
    return _Gaze(score: fused, confidence: isCalibrated ? 0.95 : 0.65);
  }

  void _maybeSampleCalibration(double yaw, double pitch, double? gazeX, double? gazeY) {
    if (!_calibrating) return;
    _calYaw.add(yaw);
    _calPitch.add(pitch);
    if (gazeX != null) _calGazeX.add(gazeX);
    if (gazeY != null) _calGazeY.add(gazeY);

    final now = DateTime.now();
    if (_calibrationDeadline != null && now.isAfter(_calibrationDeadline!)) {
      _baselineYaw   = _median(_calYaw);
      _baselinePitch = _median(_calPitch);
      _baselineGazeX = _calGazeX.isNotEmpty ? _median(_calGazeX) : 0.0;
      _baselineGazeY = _calGazeY.isNotEmpty ? _median(_calGazeY) : 0.0;
      _calibrating = false;
      _calibrationDeadline = null;
    }
  }

  double _warmth(double duchenne, double lOpen, double rOpen) {
    final softness = 1.0 - ((lOpen + rOpen) / 2.0 - 0.7).abs() / 0.3;
    return (duchenne * 0.75 + softness.clamp(0.0, 1.0) * 0.25).clamp(0.0, 1.0);
  }

  double _composure(double blinkRate, double stability) {
    double b;
    if (blinkRate == 0)            { b = 0.6; }
    else if (blinkRate < 8)        { b = blinkRate / 8.0; }
    else if (blinkRate <= 18)      { b = 1.0; }
    else                           { b = math.max(0, 1.0 - (blinkRate - 18) / 14.0); }
    return (b * 0.55 + stability * 0.45).clamp(0.0, 1.0);
  }

  double _range() {
    if (_smileHist.length < 15) return 0.5;
    final sV = _variance(_smileHist);
    final bV = _variance(_browHist);
    final sR = math.exp(-math.pow((sV - 0.02) / 0.03, 2));
    final bR = math.exp(-math.pow((bV - 0.015) / 0.025, 2));
    return ((sR + bR) / 2.0).clamp(0.0, 1.0);
  }

  void _detectBlink(double avgOpen) {
    _push(_eyeOpenHist, avgOpen, 8);
    if (_eyeOpenHist.length < 3) return;
    final n = _eyeOpenHist.length;
    final prev = _eyeOpenHist[n - 2];
    final curr = _eyeOpenHist[n - 1];
    if (prev < 0.25 && curr >= 0.25) {
      _blinkTs.add(DateTime.now());
      final cutoff = DateTime.now().subtract(const Duration(seconds: 60));
      _blinkTs.removeWhere((t) => t.isBefore(cutoff));
    }
  }

  double _blinkRate() {
    if (_blinkTs.isEmpty) return 0;
    final cutoff = DateTime.now().subtract(const Duration(seconds: 60));
    return _blinkTs.where((t) => t.isAfter(cutoff)).length.toDouble();
  }

  double _stability() {
    if (_yawHist.length < 4) return 1.0;
    final v = (_variance(_yawHist) + _variance(_pitchHist) + _variance(_rollHist)) / 3.0;
    return (1.0 / (1.0 + math.exp(-(1.0 - v / 14.0) * 5))).clamp(0.0, 1.0);
  }

  // ── Utility ────────────────────────────────────────────────────────────

  Offset? _offsetFrom(dynamic v) {
    if (v is List && v.length >= 2) {
      final x = (v[0] as num?)?.toDouble();
      final y = (v[1] as num?)?.toDouble();
      if (x != null && y != null) return Offset(x, y);
    }
    return null;
  }

  /// Parse a flat [x0,y0,x1,y1,…] landmark list into preview-space points.
  List<Offset> _poly(dynamic v) {
    final out = <Offset>[];
    if (v is List) {
      for (var i = 0; i + 1 < v.length; i += 2) {
        final x = (v[i] as num?)?.toDouble();
        final y = (v[i + 1] as num?)?.toDouble();
        if (x != null && y != null) out.add(Offset(x, y));
      }
    }
    return out;
  }

  void _push(List<double> l, double v, int cap) {
    l.add(v);
    if (l.length > cap) l.removeAt(0);
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

  @override
  Future<void> dispose() async {
    if (_initialized) {
      try { await _channel.invokeMethod('dispose'); } catch (_) {}
      _initialized = false;
    }
  }
}

class _Gaze {
  final double score;
  final double confidence;
  const _Gaze({required this.score, required this.confidence});
}

// Helper kept for future frame-bytes marshalling optimizations.
// ignore: unused_element
Uint8List _clonePlane(Uint8List bytes) => Uint8List.fromList(bytes);
