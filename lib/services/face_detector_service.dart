import 'package:camera/camera.dart';

import '../models/face_metrics.dart';
import 'gaze/gaze_detector.dart';
import 'gaze/mlkit_gaze_detector.dart';
import 'gaze/mediapipe_gaze_detector.dart';

/// Face detection coordinator.
///
/// Thin delegate over a pluggable [GazeDetector]. The DEFAULT is now the
/// MediaPipe iris engine — real gaze from the 478-point mesh's iris
/// landmarks, which is the only way to score genuine eye contact (MLKit
/// can only approximate gaze from head angle, so it pegged everyone at a
/// perfect lock the moment they held the phone up).
///
///   FaceDetectorService()                             // MediaPipe iris (default)
///   FaceDetectorService(engine: GazeEngine.mlkit)     // force MLKit
///
/// SAFETY NET: if MediaPipe can't come up (native plugin not registered,
/// model missing, unsupported device), [init] transparently falls back to
/// the MLKit head-pose detector so scoring never goes dark. [usingFallback]
/// reports which engine actually ended up running.
class FaceDetectorService {
  final GazeEngine engine;
  GazeDetector _detector;
  bool _fellBack = false;

  FaceDetectorService({this.engine = GazeEngine.mediapipe})
      : _detector = _detectorFor(engine);

  static GazeDetector _detectorFor(GazeEngine e) {
    switch (e) {
      case GazeEngine.mediapipe: return MediaPipeGazeDetector();
      case GazeEngine.mlkit:     return MlkitGazeDetector();
    }
  }

  String get engineName   => _detector.engineName;
  bool get hasIris        => _detector.hasIris;
  bool get isCalibrated   => _detector.isCalibrated;
  /// True once [init] has dropped from MediaPipe to the MLKit fallback.
  bool get usingFallback  => _fellBack;

  Future<void> init() async {
    try {
      await _detector.init();
    } catch (_) {
      // Already MLKit? Then there's nothing to fall back to — rethrow.
      if (_detector is MlkitGazeDetector) rethrow;
      // MediaPipe unavailable — swap in the MLKit head-pose detector so
      // the drill still scores (less precise, but the app never breaks).
      try { await _detector.dispose(); } catch (_) {}
      _detector = MlkitGazeDetector();
      _fellBack = true;
      await _detector.init();
    }
  }

  Future<FaceMetrics?> process(
    CameraImage image,
    int sensorOrientation, {
    bool isFrontCam = true,
  }) =>
      _detector.process(image, sensorOrientation, isFrontCam: isFrontCam);

  void startCalibration({Duration duration = const Duration(seconds: 3)}) =>
      _detector.startCalibration(duration: duration);

  void resetCalibration() => _detector.resetCalibration();

  Future<void> dispose() => _detector.dispose();
}
