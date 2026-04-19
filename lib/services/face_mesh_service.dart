import 'package:flutter/painting.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';

/// Holds the 468 normalized face mesh points.
/// All coordinates are 0..1 relative to the source image.
/// Optional parallel list of Z-depth values (negative = closer to camera,
/// positive = farther) enables 3D parallax rendering in the overlay.
class FaceMesh {
  final List<Offset> points;
  final List<double>? depths;

  const FaceMesh(this.points, {this.depths});

  // Lowered from 50 so bounding-box / landmark fallbacks still render
  // something rather than being silently discarded. Layer-specific guards
  // inside the painter (`< 200`, `< 400`) enforce higher thresholds where
  // topology-specific indices matter (bone lines, triangle wash).
  bool get isValid => points.length >= 4;

  /// Known MediaPipe face mesh indices for key anchors.
  /// https://developers.google.com/mediapipe/solutions/vision/face_landmarker
  static const int idxLeftEyeOuter  = 33;
  static const int idxLeftEyeInner  = 133;
  static const int idxRightEyeInner = 362;
  static const int idxRightEyeOuter = 263;
  static const int idxNoseTip       = 1;
  static const int idxChin          = 152;
  static const int idxForehead      = 10;
  static const int idxCheekL        = 234;
  static const int idxCheekR        = 454;

  Offset? at(int i) => i < points.length ? points[i] : null;

  Offset? get leftEyeCenter {
    final a = at(idxLeftEyeOuter);
    final b = at(idxLeftEyeInner);
    if (a == null || b == null) return null;
    return Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  }

  Offset? get rightEyeCenter {
    final a = at(idxRightEyeOuter);
    final b = at(idxRightEyeInner);
    if (a == null || b == null) return null;
    return Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  }
}

class FaceMeshService {
  final FaceMeshDetector _detector =
      FaceMeshDetector(option: FaceMeshDetectorOptions.faceMesh);

  Future<FaceMesh?> detect(
    InputImage image,
    Offset Function(double x, double y) mapper,
  ) async {
    final meshes = await _detector.processImage(image);
    if (meshes.isEmpty) return null;

    final m = meshes.first;
    final pts    = <Offset>[];
    final depths = <double>[];
    for (final p in m.points) {
      pts.add(mapper(p.x.toDouble(), p.y.toDouble()));
      depths.add(p.z.toDouble());
    }
    return FaceMesh(pts, depths: depths);
  }

  Future<void> close() async => _detector.close();
}
