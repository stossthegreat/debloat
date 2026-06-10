import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/face_geometry.dart';
import '../../services/analytics_service.dart';
import '../../services/face_geometry_service.dart';
import '../../services/face_mesh_service.dart';
import '../../services/local_store_service.dart';
import '../../services/paywall_gate.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/common/ai_consent_dialog.dart';
import '../../widgets/common/imhim_wordmark.dart';
import '../../widgets/scan/geometry_overlay_painter.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with TickerProviderStateMixin {
  CameraController? _camera;
  FaceDetector?     _faceDetector;
  // Per-platform dense-mesh sources. Android uses Google ML Kit's
  // face mesh detector (Android-only plugin). On iOS we don't run a
  // third-party detector — _buildSemanticMesh below synthesises a
  // dense canonical-MediaPipe-indexed mesh from ML Kit's face
  // contours, which the painter renders identically to the Android
  // path.
  FaceMeshService?  _meshService;

  // Image orientation snapshot taken at init, reused for every frame's point
  // transform so landmarks rotate/mirror into the same space as the preview.
  InputImageRotation _rotation = InputImageRotation.rotation0deg;
  bool _isFrontCam = false;
  // True when the current frame produced a real 468-point MediaPipe mesh
  // (Android only). The painter uses this to gate topology-dependent
  // layers (bone structure, measurement arcs) that index into obscure
  // MediaPipe indices we can't synthesize from ML Kit contours on iOS.
  bool _denseMesh = false;

  ScanPhase    _phase    = ScanPhase.searching;
  FaceMesh?    _mesh;
  FaceGeometry? _geometry;
  double       _progress = 0.0;
  final int    _countdown = 3; // legacy — painter takes it, unused in multi-angle flow
  bool         _busy = false;

  // ── Weekly scan cap state ─────────────────────────────────────────────
  // Bro: "two scans a week … now it's like the flood gates are open."
  // Resolved once on mount — if a non-pro user has already burned their
  // 2 scans this week, we skip every expensive init (camera, mesh,
  // wakelock) and render a paywall card instead.
  // Entry-gate fields removed in v158 — the onboarding flow is:
  //   gender pick → /scan (camera ALWAYS runs) → AI consent →
  //   if !pro → /paywall (returns to /report on purchase)
  //   if  pro → quota check (2/week) → /report
  // The scan screen no longer paints a "capped" card on entry; the
  // paywall is only ever a destination AFTER the user has captured
  // their scan and consented. That preserves the onboarding funnel.

  Timer? _measureTimer;
  Timer? _countdownTimer;

  int _faceFrames = 0;
  // Stable-in-position frames required before advancing. 30fps typical →
  // 90 frames ≈ 3s for front lock, 54 frames ≈ 1.8s for side lock.
  static const int _requiredFrames      = 30;
  static const int _sideRequiredFrames  = 18;

  // ── Face-ID style signals — computed every frame ─────────────────────────
  // Face lock is the Apple/Jumio/Yoti pattern: oval guide + distance check
  // + stability hold. These fields feed the painter and gate progression.
  double _bboxArea   = 0;   // face-box area as fraction of screen
  double _offsetX    = 0;   // face-center offset from screen-center (−1..1)
  double _offsetY    = 0;   // same, vertical
  double _yawDeg     = 0;   // head yaw from ML Kit euler angle Y
  bool   _faceInPosition = false; // green-light signal per current phase
  String _statusText = 'POSITION YOUR FACE IN THE CIRCLE';
  String _statusColor = 'idle'; // idle | adjusting | locked
  double _holdProgress = 0.0; // 0..1, fills the oval stroke when holding

  bool _processing = false;

  // ── Multi-angle capture state ────────────────────────────────────────────
  // Angle 0 = front, 1 = left 3/4, 2 = right 3/4
  int _angleIdx = 0;
  final List<Uint8List> _capturedImages = [];
  // Geometry captured on the FRONT pass — sides are visual only (Flux needs
  // a single input image anyway, and front gives the richest mesh).
  FaceGeometry? _primaryGeometry;


  // 60fps animation clock — drives particle drift, scan sweep, radar rings,
  // pulse, glitch cadence. Monotonic seconds since screen init.
  Ticker? _animTicker;
  double _animT = 0;


  // Rotating copy per phase
  static const _scanCopy = [
    '468 points locked',
    'Reading your jawline',
    'Eye tilt found',
    'Face width calculated',
    'Matching your archetype',
  ];
  int _copyIdx = 0;
  Timer? _copyTimer;

  @override
  void initState() {
    super.initState();
    // Camera ALWAYS starts. The paywall is a post-consent destination
    // (see _postScan) — never an entry block. Bro v4: "users go
    // through onboarding straight scan with mediapipe then the terms
    // they press continue then boom paywall exactly what it was."
    WakelockPlus.enable();
    _animTicker = createTicker((elapsed) {
      if (!mounted) return;
      setState(() => _animT = elapsed.inMicroseconds / 1e6);
    })..start();
    LocalStoreService.setOnboarded(true);
    AnalyticsService.scanStarted();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableContours: true,
        enableLandmarks: true,
        enableClassification: true,
        minFaceSize: 0.25,
      ),
    );

    _rotation = Platform.isIOS
        ? InputImageRotation.rotation0deg
        : (InputImageRotationValue.fromRawValue(front.sensorOrientation)
              ?? InputImageRotation.rotation270deg);
    _isFrontCam = front.lensDirection == CameraLensDirection.front;

    // Android gets the full 468-point mesh via google_mlkit_face_mesh_detection
    // (Android-only plugin). iOS doesn't get a separate detector — instead
    // _buildSemanticMesh synthesises a dense canonical-MediaPipe-indexed
    // mesh from ML Kit contour data so the painter renders identically.
    if (Platform.isAndroid) {
      _meshService = FaceMeshService();
    } else {
      _meshService = null;
    }

    // Canonical Flutter + ML Kit setup — per google_mlkit_commons README:
    //   Android → NV21 (natively delivered by camera 0.10.5+, no conversion)
    //   iOS     → BGRA8888 (bytes accepted directly by ML Kit)
    // Manual YUV420→NV21 conversion has stride bugs on high-res Pixel/Samsung
    // modes (uvRow > w/2 * uvPx) which silently produces garbage and makes
    // the detector return zero faces. Don't roll your own.
    _camera = CameraController(
      front,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    try {
      await _camera!.initialize();
      if (!mounted) return;
      setState(() {});
      _camera!.startImageStream(_processFrame);
    } catch (e) {
      debugPrint('Camera init: $e');
    }
  }

  // Canonical single-plane InputImage — per google_ml_kit_flutter sample
  // (packages/example/lib/vision_detector_views/camera_view.dart). With the
  // camera plugin configured to deliver NV21 on Android and BGRA on iOS, we
  // just forward the first plane to ML Kit verbatim. No conversion, no stride
  // handling, no manual byte shuffling.
  //
  // Rotation: reuse `_rotation` set in _initCamera. Previously this method
  // re-read camera.description.sensorOrientation per frame, which on iOS
  // returned 90/270° while `_rotation` (used downstream by _normalize) was
  // hardcoded to 0°. ML Kit and the coordinate translator disagreed about
  // the frame, so landmarks came out flipped — the iOS "skeleton turns the
  // wrong way" bug. Single source of truth fixes it.
  InputImage? _buildInputImage(CameraImage image) {
    final camera = _camera;
    if (camera == null) return null;
    if (image.planes.isEmpty) return null;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _rotation,
        format: Platform.isAndroid
            ? InputImageFormat.nv21
            : InputImageFormat.bgra8888,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  // Canonical coordinate translator — ported from the official Flutter ML Kit
  // sample (coordinates_translator.dart). Critical finding: ML Kit returns
  // points in the **rotated (upright) frame**, not the raw buffer. For a 90°
  // rotation, the upright image has dims (H, W) swapped, so we divide x by
  // imageH on Android but by imageW on iOS (because the iOS Flutter plugin
  // ignores the rotation metadata natively). The 270° case also implicitly
  // mirrors — that's why front-cam in portrait (typical 270°) doesn't need an
  // extra flip. 0°/180° is the only case where we mirror explicitly for front.
  //
  // Returns normalized 0..1 display-space coordinates for the portrait preview.
  /// Coordinate translator — canonical Google ML Kit pattern.
  ///
  /// Proven by: Google's own `CameraXLivePreviewActivity.java` sample
  /// (which swaps image w/h when rotation is 90°/180°) + flutter-ml's
  /// `coordinates_translator.dart` example painter — THE reference impl
  /// for this stack.
  ///
  /// KEY FACT: ML Kit returns landmarks in the ROTATED upright frame, not
  /// the raw sensor frame. For a portrait phone with a landscape sensor at
  /// rotation 270°, landmark x maxes at sensor HEIGHT (= portrait width).
  ///
  /// Rotation 270° also bakes in a horizontal flip — that's why front-cam
  /// portrait "just works" without an extra `_isFrontCam` mirror. Applying
  /// a second mirror on 270° sends the overlay to the wrong side.
  Offset _normalize(double bx, double by, double imgW, double imgH) {
    double nx, ny;
    switch (_rotation) {
      case InputImageRotation.rotation90deg:
        // Back cam portrait typical. Upright width = sensor height.
        nx = bx / imgH;
        ny = by / imgW;
        break;
      case InputImageRotation.rotation270deg:
        // Front cam portrait typical. Implicit horizontal flip is part of
        // the 270° transformation — do NOT add an extra front-cam mirror.
        nx = 1.0 - bx / imgH;
        ny = by / imgW;
        break;
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        nx = bx / imgW;
        ny = by / imgH;
        // Mirror for front cam — but ONLY on Android. iOS Flutter
        // camera plugin delivers the front-cam BGRA buffer already
        // in the mirrored orientation that matches the auto-mirrored
        // preview, so an explicit mirror here creates a double flip
        // → mesh tracks the wrong direction (user turns right, mesh
        // goes left). Skip the mirror on iOS to keep mesh + preview
        // in sync.
        if (_isFrontCam && !Platform.isIOS) nx = 1.0 - nx;
        break;
    }
    return Offset(nx, ny);
  }

  /// Build a "semantic-compatible" FaceMesh from ML Kit contours. iOS
  /// can't run google_mlkit_face_mesh_detection (Android-only plugin),
  /// so the painter — which indexes into canonical MediaPipe positions
  /// like `idxLeftEyeOuter = 33`, `idxChin = 152`, the 36 face-oval
  /// indices, and the chain indices used by the bone-structure layer
  /// — used to render almost nothing on iOS. This builder backfills:
  /// it maps ML Kit's contours onto the canonical MediaPipe indices
  /// the painter consumes, so EVERY layer (silhouette glow, live
  /// measurement rails, floating measurements, feature beam,
  /// constellation, bone structure, measurement arcs, mesh dots)
  /// renders identically on iOS.
  ///
  /// Out-of-canvas sentinel for unmapped indices means painter helpers
  /// that filter via per-point bounds checks render correctly without
  /// drawing junk in the middle of the face.
  FaceMesh? _buildSemanticMesh(Face face, double imgW, double imgH) {
    final faceOval        = face.contours[FaceContourType.face]?.points ?? [];
    final leftEye         = face.contours[FaceContourType.leftEye]?.points ?? [];
    final rightEye        = face.contours[FaceContourType.rightEye]?.points ?? [];
    final noseBridge      = face.contours[FaceContourType.noseBridge]?.points ?? [];
    final noseBottom      = face.contours[FaceContourType.noseBottom]?.points ?? [];
    final leftEyebrowTop  = face.contours[FaceContourType.leftEyebrowTop]?.points ?? [];
    final rightEyebrowTop = face.contours[FaceContourType.rightEyebrowTop]?.points ?? [];
    final upperLipTop     = face.contours[FaceContourType.upperLipTop]?.points ?? [];
    final lowerLipBottom  = face.contours[FaceContourType.lowerLipBottom]?.points ?? [];

    if (faceOval.length < 8) return null;

    Offset norm(num x, num y) =>
        _normalize(x.toDouble(), y.toDouble(), imgW, imgH);

    // 500 covers every canonical index the painter touches. Off-canvas
    // sentinel keeps unmapped indices visually inert (the painter's
    // bounds-check filters them out before drawing).
    const sentinel = Offset(-10, -10);
    final pts = List<Offset>.filled(500, sentinel);

    /// Spread an ordered ML Kit contour over a list of canonical MediaPipe
    /// indices. Linearly samples the source contour at evenly spaced
    /// positions along its length so a 16-point contour can fill a
    /// 17-index chain without creating duplicate-stacked dots.
    void spread(List<dynamic> src, List<int> dstIdx) {
      if (src.isEmpty || dstIdx.isEmpty) return;
      final n = src.length;
      for (var i = 0; i < dstIdx.length; i++) {
        final t = i / math.max(1, dstIdx.length - 1);
        final s = (t * (n - 1)).round().clamp(0, n - 1);
        final p = src[s];
        pts[dstIdx[i]] = norm(p.x, p.y);
      }
    }

    // Face-oval extremes → cardinal anchors.
    var topI = 0, botI = 0, leftI = 0, rightI = 0;
    for (var i = 1; i < faceOval.length; i++) {
      final p = faceOval[i];
      if (p.y < faceOval[topI].y)   topI   = i;
      if (p.y > faceOval[botI].y)   botI   = i;
      if (p.x < faceOval[leftI].x)  leftI  = i;
      if (p.x > faceOval[rightI].x) rightI = i;
    }
    pts[FaceMesh.idxForehead] = norm(faceOval[topI].x,   faceOval[topI].y);
    pts[FaceMesh.idxChin]     = norm(faceOval[botI].x,   faceOval[botI].y);
    pts[FaceMesh.idxCheekL]   = norm(faceOval[leftI].x,  faceOval[leftI].y);
    pts[FaceMesh.idxCheekR]   = norm(faceOval[rightI].x, faceOval[rightI].y);

    // Eye corners — ML Kit returns each eye contour starting at the
    // outer corner and going around. First/last give the two corners.
    if (leftEye.length >= 2) {
      pts[FaceMesh.idxLeftEyeOuter] = norm(leftEye.first.x, leftEye.first.y);
      pts[FaceMesh.idxLeftEyeInner] = norm(leftEye.last.x,  leftEye.last.y);
    }
    if (rightEye.length >= 2) {
      pts[FaceMesh.idxRightEyeOuter] = norm(rightEye.first.x, rightEye.first.y);
      pts[FaceMesh.idxRightEyeInner] = norm(rightEye.last.x,  rightEye.last.y);
    }

    // Nose tip — last point on nose bridge (lowest = tip).
    if (noseBridge.isNotEmpty) {
      final tip = noseBridge.reduce((a, b) => a.y > b.y ? a : b);
      pts[FaceMesh.idxNoseTip] = norm(tip.x, tip.y);
    }

    // ── Face oval ─ canonical MediaPipe oval indices clockwise from top.
    const ovalCanonical = [
      10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288,
      397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136,
      172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109,
    ];
    final n = faceOval.length;
    for (var i = 0; i < ovalCanonical.length; i++) {
      final src = (topI + (i * n / ovalCanonical.length).round()) % n;
      final p = faceOval[src];
      pts[ovalCanonical[i]] = norm(p.x, p.y);
    }

    // ── Mandible chain (bone structure layer) — already covered by oval.
    // Indices 234, 93, 132, 58, 172, 136, 150, 149, 176, 148, 152, 377,
    // 400, 378, 379, 365, 397, 288, 361, 323, 454 are all in ovalCanonical
    // above, so the bone-structure jaw chain renders unchanged.

    // ── Zygomatic L / R (cheekbone shelf) — straight diagonal sweep
    // from the cheek extreme inward and slightly down to a point on
    // the lower jaw line. Linear-interp gives the bone-structure layer
    // a real cheekbone bracket rather than a flat horizontal.
    void linearChain(Offset a, Offset b, List<int> dst) {
      for (var i = 0; i < dst.length; i++) {
        final t = i / math.max(1, dst.length - 1);
        pts[dst[i]] = Offset(a.dx + (b.dx - a.dx) * t,
                             a.dy + (b.dy - a.dy) * t);
      }
    }
    final cheekLOff = norm(faceOval[leftI].x, faceOval[leftI].y);
    final cheekROff = norm(faceOval[rightI].x, faceOval[rightI].y);
    final lJawSrc = faceOval[(leftI + n ~/ 12) % n];
    final rJawSrc = faceOval[(rightI - n ~/ 12 + n) % n];
    linearChain(cheekLOff, norm(lJawSrc.x, lJawSrc.y),
        const [234, 227, 116, 123, 117, 118, 101]);
    linearChain(cheekROff, norm(rJawSrc.x, rJawSrc.y),
        const [454, 447, 345, 352, 346, 347, 330]);

    // ── Orbital frames L / R — full eye-socket trace. ML Kit gives
    // ~16 points per eye contour, the canonical chain has 17 indices —
    // spread() handles the resampling.
    if (leftEye.length >= 4) {
      spread(leftEye, const [
        33, 246, 161, 160, 159, 158, 157, 173, 133, 155,
        154, 153, 145, 144, 163, 7, 33,
      ]);
    }
    if (rightEye.length >= 4) {
      spread(rightEye, const [
        263, 466, 388, 387, 386, 385, 384, 398, 362, 382,
        381, 380, 374, 373, 390, 249, 263,
      ]);
    }

    // ── Frontal bone sweep — combine left + center + right brow points.
    if (leftEyebrowTop.length >= 3 && rightEyebrowTop.length >= 3) {
      // Brow indices on the chain: 70, 63, 105, 66, 107 (left) → 9 (center) →
      // 336, 296, 334, 293, 300 (right). Sample left, set 9 to the brow
      // midpoint between the two innermost points, then right.
      spread(leftEyebrowTop,  const [70, 63, 105, 66, 107]);
      spread(rightEyebrowTop, const [336, 296, 334, 293, 300]);
      final lInner = leftEyebrowTop.last;
      final rInner = rightEyebrowTop.last;
      pts[9] = norm((lInner.x + rInner.x) / 2, (lInner.y + rInner.y) / 2);
    }

    // ── Nose bridge — chain (168, 6, 197, 195, 5, 4, 1).
    if (noseBridge.length >= 3) {
      spread(noseBridge, const [168, 6, 197, 195, 5, 4, 1]);
    } else if (noseBottom.isNotEmpty && pts[10].dx >= 0) {
      // Fallback — interpolate between forehead and noseBottom centroid.
      final cx = noseBottom.map((p) => p.x).reduce((a, b) => a + b) / noseBottom.length;
      final cy = noseBottom.map((p) => p.y).reduce((a, b) => a + b) / noseBottom.length;
      final tipN = norm(cx, cy);
      const bridge = [168, 6, 197, 195, 5, 4, 1];
      for (var i = 0; i < bridge.length; i++) {
        final t = i / (bridge.length - 1);
        pts[bridge[i]] = Offset(
          pts[10].dx + (tipN.dx - pts[10].dx) * t,
          pts[10].dy + (tipN.dy - pts[10].dy) * t);
      }
    }

    // ── Chin vector (152, 175, 199, 200, 18) — extends from chin point
    // up toward the lower lip. We have 152 from the face oval; place 18
    // at the lower-lip-bottom centroid and interpolate the rest.
    if (lowerLipBottom.isNotEmpty) {
      final cx = lowerLipBottom.map((p) => p.x).reduce((a, b) => a + b) / lowerLipBottom.length;
      final cy = lowerLipBottom.map((p) => p.y).reduce((a, b) => a + b) / lowerLipBottom.length;
      final lipN = norm(cx, cy);
      pts[18] = lipN;
      const chinChain = [152, 175, 199, 200, 18];
      for (var i = 1; i < chinChain.length - 1; i++) {
        final t = i / (chinChain.length - 1);
        pts[chinChain[i]] = Offset(
          pts[152].dx + (lipN.dx - pts[152].dx) * t,
          pts[152].dy + (lipN.dy - pts[152].dy) * t);
      }
    }

    // ── Lip outline — used by mesh-dot density and constellation.
    if (upperLipTop.length >= 3) {
      spread(upperLipTop, const [61, 78, 95, 88, 178, 87, 14, 317, 402, 318, 324, 308, 291]);
    }

    // ── Cheek interpolation — fills additional dot density across the
    // cheek areas so _drawMeshDots reads as a uniform face mesh.
    // Indices roughly correspond to MediaPipe cheek mesh points.
    if (pts[FaceMesh.idxCheekL].dx >= 0 && pts[FaceMesh.idxLeftEyeOuter].dx >= 0) {
      final eyeL = pts[FaceMesh.idxLeftEyeOuter];
      final cheekL = pts[FaceMesh.idxCheekL];
      const leftCheekFill = [50, 36, 205, 187, 207, 213, 192];
      for (var i = 0; i < leftCheekFill.length; i++) {
        final t = (i + 1) / (leftCheekFill.length + 1);
        pts[leftCheekFill[i]] = Offset(
          eyeL.dx + (cheekL.dx - eyeL.dx) * t,
          eyeL.dy + (cheekL.dy - eyeL.dy) * t);
      }
    }
    if (pts[FaceMesh.idxCheekR].dx >= 0 && pts[FaceMesh.idxRightEyeOuter].dx >= 0) {
      final eyeR = pts[FaceMesh.idxRightEyeOuter];
      final cheekR = pts[FaceMesh.idxCheekR];
      const rightCheekFill = [280, 266, 425, 411, 427, 433, 416];
      for (var i = 0; i < rightCheekFill.length; i++) {
        final t = (i + 1) / (rightCheekFill.length + 1);
        pts[rightCheekFill[i]] = Offset(
          eyeR.dx + (cheekR.dx - eyeR.dx) * t,
          eyeR.dy + (cheekR.dy - eyeR.dy) * t);
      }
    }

    return FaceMesh(pts);
  }

  // Front-cam preview is auto-mirrored on iOS at the platform level. Android
  // shows the un-mirrored view, so when our internal logic wants the user to
  // turn LEFT (subject's own left), the user perceives it as RIGHT in the
  // preview. Swap the LEFT/RIGHT in user-facing strings on Android only.
  String _dir(String iosLabel) {
    if (!Platform.isAndroid) return iosLabel;
    return iosLabel
        .replaceAll('LEFT', '\u0001')
        .replaceAll('RIGHT', 'LEFT')
        .replaceAll('\u0001', 'RIGHT');
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_processing ||
        _phase == ScanPhase.capturing ||
        _phase == ScanPhase.analysing) { return; }
    _processing = true;

    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) return;

      final imgW = image.width.toDouble();
      final imgH = image.height.toDouble();

      List<Face> faces = [];
      FaceMesh? mesh;
      try {
        faces = await _faceDetector!.processImage(inputImage);
      } catch (_) {}
      if (_meshService != null) {
        try {
          mesh = await _meshService!.detect(
            inputImage,
            (x, y) => _normalize(x, y, imgW, imgH),
          );
        } catch (_) {}
      }

      if (!mounted) return;

      if (faces.isEmpty) {
        // Only reset to SEARCHING from scanning-phase. Past that — measuring,
        // rotate cues, side scanning — the user is legitimately moving and
        // may briefly lose detection. We protect the existing state.
        if (_phase == ScanPhase.searching || _phase == ScanPhase.scanning) {
          _faceFrames = 0;
          if (_phase != ScanPhase.searching) {
            setState(() {
              _phase    = ScanPhase.searching;
              _progress = 0;
              _mesh     = null;
            });
          }
        }
        return;
      }

      final face = faces.first;

      // ── Face-ID style signals ───────────────────────────────────────────
      // Bbox area (fraction of image), center offset, yaw. Feed the oval
      // guide + gate progression on these rather than a frame counter alone.
      //
      // CRITICAL: ML Kit returns bounding-box coordinates in the UPRIGHT
      // (rotated) frame, not the raw sensor frame. For a 1280x720 landscape
      // sensor at rotation 270° the upright frame is 720x1280 portrait, so
      // `bb.left/right` live in 0..720 and `bb.top/bottom` in 0..1280. If we
      // normalize by the raw sensor dims instead, a perfectly-centered face
      // reads as offset ≈ -0.4, the "CENTER YOUR FACE" check fails every
      // frame, the phase never advances to SCANNING, and the mesh overlay
      // never renders — which is exactly the Android symptom users hit
      // despite MediaPipe returning all 468 points. Swap the dims for
      // 90°/270° rotations so the centered-check uses the same frame the
      // bbox is actually in.
      {
        final bb = face.boundingBox;
        final bool swapped = _rotation == InputImageRotation.rotation90deg ||
                             _rotation == InputImageRotation.rotation270deg;
        final double uprightW = swapped ? imgH : imgW;
        final double uprightH = swapped ? imgW : imgH;
        final double uprightA = uprightW * uprightH;
        _bboxArea = (bb.width * bb.height) / (uprightA <= 0 ? 1 : uprightA);
        final double cx = (bb.left + bb.right) / 2;
        final double cy = (bb.top + bb.bottom) / 2;
        _offsetX = ((cx - uprightW / 2) / uprightW) * 2;  // roughly -1..1
        _offsetY = ((cy - uprightH / 2) / uprightH) * 2;
        // Raw yaw from ML Kit. Convention: subject turning toward OWN LEFT
        // shoulder = NEGATIVE. iOS system-mirrors the preview but ML Kit
        // output is in the same mirrored space, so the raw yaw already
        // matches what the user sees. No platform flip needed.
        _yawDeg = face.headEulerAngleY ?? 0.0;
      }

      // Position gating depends on current phase.
      final bool frontalLockWanted =
          _angleIdx == 0 &&
          (_phase == ScanPhase.searching || _phase == ScanPhase.scanning);
      final bool leftProfileWanted =
          _angleIdx == 1 &&
          (_phase == ScanPhase.searching || _phase == ScanPhase.scanning);
      final bool rightProfileWanted =
          _angleIdx == 2 &&
          (_phase == ScanPhase.searching || _phase == ScanPhase.scanning);

      bool inPosition = false;
      String nextStatus = _statusText;
      String nextColor = _statusColor;

      if (frontalLockWanted) {
        // Front — need centered + correct distance + frontal yaw
        if (_bboxArea < 0.10) {
          nextStatus = 'MOVE CLOSER';
          nextColor = 'adjusting';
        } else if (_bboxArea > 0.42) {
          nextStatus = 'MOVE BACK';
          nextColor = 'adjusting';
        } else if (_offsetX.abs() > 0.16 || _offsetY.abs() > 0.20) {
          nextStatus = 'CENTER YOUR FACE';
          nextColor = 'adjusting';
        } else if (_yawDeg.abs() > 12) {
          nextStatus = 'LOOK STRAIGHT AT THE LENS';
          nextColor = 'adjusting';
        } else {
          inPosition = true;
          nextStatus = 'HOLD STILL';
          nextColor = 'locked';
        }
      } else if (leftProfileWanted) {
        // ML Kit convention: face turning toward SUBJECT'S LEFT shoulder
        // (= camera's right) → NEGATIVE yaw. This is the fix — previously
        // had signs flipped and users were told to turn the wrong way.
        if (_yawDeg > -18) {
          nextStatus = _dir('TURN FURTHER LEFT');
          nextColor = 'adjusting';
        } else if (_yawDeg < -48) {
          nextStatus = 'TURN BACK A LITTLE';
          nextColor = 'adjusting';
        } else {
          inPosition = true;
          nextStatus = _dir('HOLD STILL · LEFT');
          nextColor = 'locked';
        }
      } else if (rightProfileWanted) {
        // Subject's RIGHT shoulder = camera's left → POSITIVE yaw.
        if (_yawDeg < 18) {
          nextStatus = _dir('TURN FURTHER RIGHT');
          nextColor = 'adjusting';
        } else if (_yawDeg > 48) {
          nextStatus = 'TURN BACK A LITTLE';
          nextColor = 'adjusting';
        } else {
          inPosition = true;
          nextStatus = _dir('HOLD STILL · RIGHT');
          nextColor = 'locked';
        }
      } else if (_phase == ScanPhase.measuring) {
        // During the dramatic bone reveal, just show the scan label.
        inPosition = true;
        nextStatus = 'ANALYSING · ${((_progress * 100).clamp(0, 100)).toStringAsFixed(0)}%';
        nextColor = 'locked';
      } else if (_phase == ScanPhase.rotateLeft) {
        inPosition = false;
        nextStatus = _dir('TURN LEFT');
        nextColor = 'adjusting';
      } else if (_phase == ScanPhase.rotateRight) {
        inPosition = false;
        nextStatus = _dir('TURN RIGHT');
        nextColor = 'adjusting';
      }

      _faceInPosition = inPosition;
      if (nextStatus != _statusText || nextColor != _statusColor) {
        _statusText  = nextStatus;
        _statusColor = nextColor;
      }

      // LAYERED FALLBACK — try in order, take the first that yields a
      // usable mesh. Guarantees we advance past SEARCHING the moment a
      // face is on screen, regardless of which ML Kit surface fires.
      //   1. MediaPipe face mesh    (Android, 468 pts, full topology)
      //   2. SEMANTIC contour mesh  (iOS — anchor indices populated to
      //                              match MediaPipe so the painter's
      //                              canonical lookups keep working)
      //   3. Flat contour blob      (any platform, last-ditch points)
      //   4. Landmarks + bbox       (always works, ~12 pts)
      //
      // _denseMesh tracks whether layer 1 succeeded — the painter gates
      // topology-dependent layers (bone structure, measurement arcs)
      // on it, since those use obscure MediaPipe indices that only
      // exist in a real 468-point mesh.
      bool denseMesh = mesh != null && mesh.isValid && mesh.points.length >= 200;

      if (mesh == null || !mesh.isValid) {
        mesh = _buildSemanticMesh(face, imgW, imgH);
      }

      if (mesh == null || !mesh.isValid) {
        final pts = <Offset>[];
        for (final contour in face.contours.values) {
          if (contour == null) continue;
          for (final p in contour.points) {
            pts.add(_normalize(p.x.toDouble(), p.y.toDouble(), imgW, imgH));
          }
        }
        if (pts.length >= 20) {
          mesh = FaceMesh(pts);
        }
      }

      if (mesh == null || !mesh.isValid) {
        // Layer 4 — landmarks + bbox
        final pts = <Offset>[];
        for (final lm in face.landmarks.values) {
          if (lm == null) continue;
          pts.add(_normalize(
            lm.position.x.toDouble(), lm.position.y.toDouble(), imgW, imgH));
        }
        final bb = face.boundingBox;
        final bboxPts = [
          Offset(bb.left,              bb.top),
          Offset(bb.right,             bb.top),
          Offset(bb.right,             bb.bottom),
          Offset(bb.left,              bb.bottom),
          Offset((bb.left + bb.right) / 2, bb.top),
          Offset(bb.right,             (bb.top + bb.bottom) / 2),
          Offset((bb.left + bb.right) / 2, bb.bottom),
          Offset(bb.left,              (bb.top + bb.bottom) / 2),
          Offset((bb.left + bb.right) / 2, (bb.top + bb.bottom) / 2),
        ];
        for (final p in bboxPts) {
          pts.add(_normalize(p.dx, p.dy, imgW, imgH));
        }
        if (pts.isNotEmpty) {
          mesh = FaceMesh(pts);
        }
      }

      // Even if mesh is STILL null somehow, advance phase — a face was seen.
      // The painter checks for mesh validity before drawing mesh-dependent
      // layers, so SEARCHING → SCANNING always transitions when a face lands.
      mesh ??= FaceMesh(const []);
      _denseMesh = denseMesh;

      _faceFrames++;
      final geom = FaceGeometryService.computeGeometry(face, imgW, imgH);

      setState(() {
        _mesh     = mesh;
        _geometry = geom;
      });

      // Face-ID-style gating: face must be IN position for the counter to
      // advance. Out of position = decrement (hysteresis, prevents flicker).
      // This is what turns the scan from a timer-gimmick into a real lock.
      if (_faceInPosition) {
        _faceFrames = _faceFrames + 1;
      } else {
        _faceFrames = (_faceFrames - 3).clamp(0, 9999).toInt();
      }

      // Update hold progress for the oval stroke
      final threshold = _angleIdx == 0 ? _requiredFrames : _sideRequiredFrames;
      _holdProgress = (_faceFrames / threshold).clamp(0.0, 1.0);

      if (_phase == ScanPhase.searching && _faceFrames >= 4) {
        _startScanning();
      }

      if (_phase == ScanPhase.scanning) {
        setState(() => _progress = _holdProgress);
        if (_faceFrames >= threshold) {
          _startMeasuring();
        }
      }
    } finally {
      _processing = false;
    }
  }

  void _startScanning() {
    setState(() {
      _phase    = ScanPhase.scanning;
      _progress = 0;
    });
    HapticFeedback.lightImpact();
    _copyTimer?.cancel();
    _copyTimer = Timer.periodic(700.ms, (_) {
      if (!mounted) return;
      setState(() => _copyIdx = (_copyIdx + 1) % _scanCopy.length);
    });
  }

  /// Measuring — slowed so the dramatic bone reveal takes ~3s. Combined
  /// with ~2s of scanning and 3s countdown, total scan is ~8s: enough for
  /// the user to feel the depth of analysis without padding.
  void _startMeasuring() {
    setState(() {
      _phase    = ScanPhase.measuring;
      _progress = 0.0;
    });
    HapticFeedback.mediumImpact();
    bool lockFired = false;
    _measureTimer?.cancel();
    // Front = ~5s deliberate cinematic reveal (the moment users record).
    // Sides = ~2.2s each — brisker since front already carries the drama.
    final increment = _angleIdx == 0 ? 0.008 : 0.018;
    _measureTimer = Timer.periodic(40.ms, (t) {
      if (!mounted) { t.cancel(); return; }
      final np = _progress + increment;
      setState(() => _progress = np.clamp(0.0, 1.0));

      if (!lockFired && np >= 0.90) {
        lockFired = true;
        HapticFeedback.heavyImpact();
      }

      if (np >= 1.0) {
        t.cancel();
        _snapCurrentAngle();
      }
    });
  }

  /// Takes a silent picture of the current frame, stashes it, then either
  /// prompts for the next rotation OR proceeds to capture → analyse.
  Future<void> _snapCurrentAngle() async {
    if (_busy) return;
    _busy = true;

    try {
      // Stop stream briefly, take picture, restart stream.
      await _camera?.stopImageStream();
      final file = await _camera?.takePicture();
      if (file == null) throw Exception('capture failed at angle $_angleIdx');
      final raw = await File(file.path).readAsBytes();
      final bytes = await compute<Uint8List, Uint8List>(_bakeOrientation, raw);

      _capturedImages.add(bytes);
      if (_angleIdx == 0) _primaryGeometry = _geometry;

      HapticFeedback.heavyImpact();

      // Advance to next angle OR ship to backend
      if (_angleIdx == 0) {
        setState(() {
          _phase = ScanPhase.rotateLeft;
          _progress = 1.0;
          _angleIdx = 1;
        });
        // Wait 2s for user to turn head, then re-acquire
        _measureTimer?.cancel();
        _measureTimer = Timer(const Duration(milliseconds: 2000), () {
          if (!mounted) return;
          _beginNextAngle();
        });
      } else if (_angleIdx == 1) {
        setState(() {
          _phase = ScanPhase.rotateRight;
          _progress = 1.0;
          _angleIdx = 2;
        });
        _measureTimer?.cancel();
        _measureTimer = Timer(const Duration(milliseconds: 2000), () {
          if (!mounted) return;
          _beginNextAngle();
        });
      } else {
        // All 3 captured → ship
        await _shipToBackend();
      }
    } catch (e) {
      debugPrint('Snap error at angle $_angleIdx: $e');
      // Try to continue — ship what we have if we got at least 1 image
      if (_capturedImages.isNotEmpty) {
        await _shipToBackend();
      } else if (mounted) {
        setState(() {
          _phase = ScanPhase.searching;
          _faceFrames = 0;
          _angleIdx = 0;
        });
        _camera?.startImageStream(_processFrame);
        _busy = false;
      }
    }
  }

  /// Restart the detection loop for the next angle.
  void _beginNextAngle() {
    if (!mounted) return;
    setState(() {
      _phase      = ScanPhase.scanning;
      _progress   = 0.0;
      _faceFrames = 0;
      _mesh       = null;
    });
    _busy = false;
    _camera?.startImageStream(_processFrame);
  }

  /// All 3 images captured — navigate to report with primary geometry.
  /// Backend currently consumes only one image (front), so we send that as
  /// imageBytes but pass all 3 as `images` for forward compatibility when
  /// /scan is upgraded to multi-image GPT vision.
  ///
  /// THE PAYWALL GATE. MediaPipe work finishes in this method — the
  /// measurements are already on-device, for free. The expensive
  /// calls (Replicate, OpenAI) happen inside /report. So we check the
  /// subscription flag here: paid users pass through to /report, free
  /// users get routed to /paywall with the scan payload stashed so a
  /// successful purchase drops them straight into their report.
  ///
  /// The user's framing: "they turn both sides, boom paywall" — they
  /// get the full scan experience and hit the wall at the point of
  /// maximum curiosity, not before.
  Future<void> _shipToBackend() async {
    AnalyticsService.scanCompleted();
    setState(() => _phase = ScanPhase.analysing);

    final primaryGeom = _primaryGeometry ?? _geometry ??
        const FaceGeometry(
          canthalTilt: 0, symmetryScore: 70, facialThirdTop: 33,
          facialThirdMid: 33, facialThirdLow: 34, fwhr: 1.9,
          eyeSpacingRatio: 0.46, jawAngle: 125, chinProjection: 0,
          hasReliableData: false,
        );

    final imageBytes = _capturedImages.isNotEmpty
        ? _capturedImages.first : Uint8List(0);
    final extraImages = _capturedImages.length > 1
        ? _capturedImages.sublist(1) : <Uint8List>[];

    if (!mounted) return;

    // App Store guideline 5.1.2(i) gate. Before any selfie bytes
    // leave the device for OpenAI / Replicate, the user must have
    // granted explicit in-app permission. The /report screen is
    // where MirrorApiService.analyseOnly fires the first network
    // call, so we MUST get consent before we route there (and
    // before /paywall, since a successful purchase forwards to
    // /report with the scan payload). ensure() short-circuits when
    // the persisted flag is already set so a returning user only
    // sees the dialog once.
    final consented = await AiConsentDialog.ensure(context);
    if (!mounted) return;
    if (!consented) {
      // User declined. Reset the scan flow back to the searching
      // phase so they can re-try (and either grant permission
      // next time, or simply leave). Do NOT navigate forward —
      // no photo bytes can be transmitted without consent.
      setState(() => _phase = ScanPhase.searching);
      return;
    }

    // Paywall gate — runs AFTER scan capture + consent. Bro v4:
    //   "users go through onboarding straight scan with mediapipe
    //    then the terms they press continue then BOOM paywall."
    //
    // Free users (not subscribed): paywall pushed with the scan
    // payload stashed; on purchase the paywall forwards to /report
    // so they don't lose their MediaPipe capture.
    //
    // Pro users: enforce the 2/week quota. Under quota → mark slot,
    // proceed. Over quota → paywall with the same payload so the
    // resubscribe path still preserves the scan.
    final pro = await PaywallGate.isPro();
    if (!pro) {
      if (!mounted) return;
      context.go('/paywall', extra: {
        'afterPurchase': '/report',
        'imageBytes':    imageBytes,
        'geometry':      primaryGeom,
        'extraImages':   extraImages,
        'source':        'scan_locked',
      });
      return;
    }
    final usedThisWeek = await LocalStoreService.scansThisWeek();
    if (usedThisWeek >= LocalStoreService.kScansPerWeek) {
      if (!mounted) return;
      context.go('/paywall', extra: {
        'afterPurchase': '/report',
        'imageBytes':    imageBytes,
        'geometry':      primaryGeom,
        'extraImages':   extraImages,
        'source':        'scan_quota_capped',
      });
      return;
    }
    await LocalStoreService.markScanUsed();
    if (!mounted) return;

    context.go('/report', extra: {
      'imageBytes':  imageBytes,
      'geometry':    primaryGeom,
      'extraImages': extraImages,
    });
  }

  // Phase labels are DEliberately generic now — the active user instruction
  // (MOVE CLOSER / HOLD STILL / TURN LEFT) is shown by the oval's coaching
  // text above. Bottom labels are just phase indicators.
  String get _phaseTitle {
    switch (_phase) {
      case ScanPhase.searching:
        return _angleIdx == 0 ? 'STEP 01 · FRONT'
             : _angleIdx == 1 ? 'STEP 02 · LEFT'
             :                  'STEP 03 · RIGHT';
      case ScanPhase.scanning:      return 'LOCK ACQUIRING';
      case ScanPhase.measuring:     return 'READING YOUR BONES';
      case ScanPhase.rotateLeft:    return 'STEP 02 · LEFT';
      case ScanPhase.rotateRight:   return 'STEP 03 · RIGHT';
      case ScanPhase.capturing:     return 'CAPTURING';
      case ScanPhase.analysing:     return 'WORKING ON IT';
    }
  }

  String get _phaseSub {
    switch (_phase) {
      case ScanPhase.searching:
      case ScanPhase.scanning:
      case ScanPhase.rotateLeft:
      case ScanPhase.rotateRight:
        return 'Follow the coaching above';
      case ScanPhase.measuring:     return 'Jawline · eyes · thirds · cheekbones';
      case ScanPhase.capturing:     return 'Capturing your reference frame';
      case ScanPhase.analysing:     return 'Personal analysis incoming';
    }
  }

  @override
  void dispose() {
    _measureTimer?.cancel();
    _countdownTimer?.cancel();
    _copyTimer?.cancel();
    _animTicker?.dispose();
    _camera?.stopImageStream();
    _camera?.dispose();
    _faceDetector?.close();
    _meshService?.close();
    WakelockPlus.disable();
    super.dispose();
  }

  /// Compute the face's bounding box in painter-canvas-pixel space
  /// from the current mesh, on iOS only. Returns null on Android (or
  /// when the mesh is missing / invalid) so the painter falls back
  /// to its existing screen-locked behaviour — Android's experience
  /// is unchanged.
  ///
  /// Why iOS-only: Android runs real MediaPipe and the face stays
  /// roughly centred in the user's natural framing, so a screen-
  /// locked oval works fine. iOS synthesises the mesh from ML Kit
  /// contours, and during side-profile rotation the face naturally
  /// drifts off-centre — the painter's screen-locked oval ends up
  /// floating in empty space (the bug shown in the side-profile
  /// screenshots). Anchoring the oval to the actual face bbox keeps
  /// the lock-on experience equivalent to the front-on capture.
  Rect? _computeFaceBoxIos(Size canvasSize) {
    if (!Platform.isIOS) return null;
    final m = _mesh;
    if (m == null || !m.isValid || m.points.isEmpty) return null;
    final pts = m.points;
    double minX = pts.first.dx, maxX = pts.first.dx;
    double minY = pts.first.dy, maxY = pts.first.dy;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    // Mesh points are in 0..1 normalised painter-canvas coords.
    // Reject degenerate boxes (e.g. when only fallback landmarks
    // are populated and they cluster at one point).
    final nW = maxX - minX;
    final nH = maxY - minY;
    if (nW < 0.05 || nH < 0.05) return null;
    return Rect.fromLTRB(
      minX * canvasSize.width,
      minY * canvasSize.height,
      maxX * canvasSize.width,
      maxY * canvasSize.height,
    );
  }

  // Cover-fill camera: scale the CameraPreview's natural AspectRatio box
  // up until it fully covers the screen (parts of the preview are clipped on
  // the overflow side). The mesh overlay is passed as CameraPreview's `child`
  // so it inhabits the SAME coord space as the preview texture and therefore
  // stays aligned with the face no matter how much we scale.
  Widget _fullscreenCamera(CameraController c) {
    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * c.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;

    return ClipRect(
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.center,
        child: Center(
          child: CameraPreview(
            c,
            // LayoutBuilder + explicit `size` is critical here — a childless
            // CustomPaint without an explicit size defaults to Size.zero, and
            // inside CameraPreview's Stack it can silently render as a zero
            // canvas. Passing the constraints guarantees the painter knows
            // its real box size.
            child: LayoutBuilder(
              builder: (_, constraints) => CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: GeometryOverlayPainter(
                  mesh:         _mesh,
                  phase:        _phase,
                  progress:     _progress,
                  countdown:    _countdown,
                  animT:        _animT,
                  statusText:   _statusText,
                  statusColor:  _statusColor,
                  holdProgress: _holdProgress,
                  // Front-cam preview behaves opposite on Android (no auto
                  // mirror) — flag the painter to swap LEFT/RIGHT cues.
                  mirrorLR:     Platform.isAndroid,
                  denseMesh:    _denseMesh,
                  // Real per-frame geometry — the painter feeds these
                  // directly into the live HUD readouts so the user
                  // sees their ACTUAL canthal tilt, jaw angle, FWHR,
                  // symmetry instead of a hardcoded sine-wave wiggle.
                  geometry:     _geometry,
                  // iOS-only face-anchored oval. Android already
                  // tracks fine via real MediaPipe; passing null
                  // there preserves the existing screen-locked
                  // oval the user described as "elite". On iOS the
                  // synthesised mesh drifts off-centre during side
                  // profiles, so we re-anchor the oval to the
                  // mesh's bounding box every frame.
                  faceBox:      _computeFaceBoxIos(constraints.biggest),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _camera;
    final initialized = preview != null && preview.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (initialized)
            _fullscreenCamera(preview)
          else
            const ColoredBox(color: Colors.black),

          // Darken edges for focus
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.85,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
          ),

          // Phase HUD — bottom, editorial format (indexed label + italic sub)
          Positioned(
            left: 0, right: 0, bottom: 84,
            child: Column(
              children: [
                // Index badge — "01 / 05" surgical counter feel
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: AppColors.red.withValues(alpha: 0.35), width: 0.8),
                  ),
                  child: Text(
                    '${(_phase.index + 1).toString().padLeft(2, '0')} / 05  ·  '
                    '${_phase.name.toUpperCase()}',
                    style: AppTypography.label.copyWith(
                      color: AppColors.red,
                      fontSize: 9,
                      letterSpacing: 2.4,
                    ),
                  ),
                ).animate(key: ValueKey(_phase))
                  .fadeIn(duration: 260.ms)
                  .slideY(begin: 0.3, end: 0, duration: 260.ms, curve: Curves.easeOut),

                // Main phase title
                Text(_phaseTitle,
                  key: ValueKey('$_phase-$_copyIdx'),
                  textAlign: TextAlign.center,
                  style: AppTypography.labelBold.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    letterSpacing: 3.2,
                  ),
                ).animate(key: ValueKey('$_phase-$_copyIdx'))
                  .fadeIn(duration: 220.ms),

                const SizedBox(height: 8),

                // Italic sub — luxury editorial undertext
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Text(_phaseSub,
                    textAlign: TextAlign.center,
                    style: AppTypography.h1Italic.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      letterSpacing: 0.1,
                      height: 1.4,
                    ),
                  ).animate(key: ValueKey(_phase))
                    .fadeIn(duration: 300.ms),
                ),
              ],
            ),
          ),

          // Progress bar during scanning — gold hairline
          if (_phase == ScanPhase.scanning || _phase == ScanPhase.measuring)
            Positioned(
              left: 40, right: 40, bottom: 56,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: AppColors.surface3.withValues(alpha: 0.5),
                  valueColor: const AlwaysStoppedAnimation(AppColors.red),
                  minHeight: 1.5,
                ),
              ),
            ),

          // Top bar — editorial masthead
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.md, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Wordmark — serif, editorial
                      const ImHimWordmark(fontSize: 22, letterSpacing: -0.6),
                      const SizedBox(width: 10),
                      Container(
                        width: 4, height: 4,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: const BoxDecoration(
                          color: AppColors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const Spacer(),
                      // Close (X) — top-right exit. First-launch users
                      // who refuse the camera or the moment land in
                      // /home where the Mirror-tab pre-scan stack
                      // upsells the scan. Existing users pop back to
                      // wherever they came from.
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            // Mark onboarded so the splash doesn't
                            // re-route them straight back here on
                            // next launch — they had their chance.
                            LocalStoreService.setOnboarded(true);
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go('/home');
                            }
                          },
                          borderRadius: BorderRadius.circular(22),
                          child: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.28),
                                width: 0.8),
                            ),
                            child: const Icon(Icons.close_rounded,
                              size: 18, color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Settings button — gold-lined, minimal
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => context.push('/settings'),
                          borderRadius: BorderRadius.circular(22),
                          child: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.red.withValues(alpha: 0.4),
                                width: 0.8),
                            ),
                            child: const Icon(Icons.tune,
                              size: 16, color: AppColors.red),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Under-byline
                  Text('THE FACE, MEASURED',
                    style: AppTypography.label.copyWith(
                      color: AppColors.textMuted, fontSize: 8, letterSpacing: 2.8)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

}

/// Isolate entrypoint — decode the JPEG, apply EXIF rotation/mirror into
/// the pixels, re-encode. Runs off the UI thread via `compute`.
Uint8List _bakeOrientation(Uint8List input) {
  try {
    final decoded = img.decodeImage(input);
    if (decoded == null) return input;
    final baked = img.bakeOrientation(decoded);
    return Uint8List.fromList(img.encodeJpg(baked, quality: 92));
  } catch (_) {
    return input;
  }
}
