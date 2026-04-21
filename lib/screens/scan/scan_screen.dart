import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../../models/face_geometry.dart';
import '../../services/face_geometry_service.dart';
import '../../services/face_mesh_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/scan/geometry_overlay_painter.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with TickerProviderStateMixin {
  CameraController? _camera;
  FaceDetector?     _faceDetector;
  FaceMeshService?  _meshService;

  // Image orientation snapshot taken at init, reused for every frame's point
  // transform so landmarks rotate/mirror into the same space as the preview.
  InputImageRotation _rotation = InputImageRotation.rotation0deg;
  bool _isFrontCam = false;

  ScanPhase    _phase    = ScanPhase.searching;
  FaceMesh?    _mesh;
  FaceGeometry? _geometry;
  double       _progress = 0.0;
  final int    _countdown = 3; // legacy — painter takes it, unused in multi-angle flow
  bool         _busy = false;

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

  // Diagnostic counters — surfaced on-screen in _diagPanel() so we can tell
  // at a glance whether the pipeline is firing: faces detected (FC), mesh
  // returning 468-pt data (MS), or whether we're on contour/landmark fallback
  // (FB). Without this panel, Android silent-failures look identical to a
  // "nothing rendering" bug.
  int _framesTotal = 0;
  int _facesHit    = 0;
  int _meshHit     = 0;
  int _fallbackHit = 0;
  int _lastMeshPts = 0;
  String _pipelineErr = '';
  int _lastPlanes = 0;
  int _lastRawFmt = 0;
  int _lastImgW = 0;
  int _lastImgH = 0;

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
    _animTicker = createTicker((elapsed) {
      if (!mounted) return;
      setState(() => _animT = elapsed.inMicroseconds / 1e6);
    })..start();
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
    // (Android-only plugin). iOS falls back to contour points from face_detection
    // — same pipeline, fewer points, still renders.
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
  InputImage? _buildInputImage(CameraImage image) {
    final camera = _camera;
    if (camera == null) return null;
    if (image.planes.isEmpty) return null;

    final rotation = Platform.isIOS
        ? (InputImageRotationValue.fromRawValue(camera.description.sensorOrientation)
              ?? InputImageRotation.rotation0deg)
        : (InputImageRotationValue.fromRawValue(camera.description.sensorOrientation)
              ?? InputImageRotation.rotation270deg);

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
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
        if (_isFrontCam) nx = 1.0 - nx;
        break;
    }
    return Offset(nx, ny);
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_processing ||
        _phase == ScanPhase.capturing ||
        _phase == ScanPhase.analysing) { return; }
    _processing = true;

    try {
      _framesTotal++;
      _lastPlanes = image.planes.length;
      _lastRawFmt = image.format.raw;
      _lastImgW   = image.width;
      _lastImgH   = image.height;
      final inputImage = _buildInputImage(image);
      if (inputImage == null) return;

      final imgW = image.width.toDouble();
      final imgH = image.height.toDouble();

      // Run face detection always. Run mesh detection only where supported.
      List<Face> faces = [];
      FaceMesh? mesh;
      try {
        faces = await _faceDetector!.processImage(inputImage);
      } catch (e) {
        _pipelineErr = 'FD: ${_trim(e)}';
      }
      if (_meshService != null) {
        try {
          mesh = await _meshService!.detect(
            inputImage,
            (x, y) => _normalize(x, y, imgW, imgH),
          );
          if (mesh != null && mesh.isValid) {
            _meshHit++;
            _lastMeshPts = mesh.points.length;
            // Clear any stale error from the warm-up frames so the HUD
            // doesn't keep showing "plugin returned no faces" after the
            // plugin has clearly recovered.
            if (_pipelineErr.startsWith('FM:') ||
                _pipelineErr.contains('MESH')) {
              _pipelineErr = '';
            }
          }
        } catch (e) {
          _pipelineErr = 'FM: ${_trim(e)}';
        }
      }
      if (faces.isNotEmpty) _facesHit++;

      // One-line heartbeat every 30 frames (~1s). Shows up in logcat for
      // `flutter logs` / Android Studio so we can diagnose silent failures
      // without reading on-screen HUD text from a screenshot.
      if (_framesTotal % 30 == 0) {
        debugPrint('[scan] FR=$_framesTotal FC=$_facesHit MS=$_meshHit '
            'FB=$_fallbackHit PTS=$_lastMeshPts planes=$_lastPlanes '
            'fmt=$_lastRawFmt dim=${_lastImgW}x$_lastImgH '
            'rot=${_rotation.name} err="${_pipelineErr}"');
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
          nextStatus = 'TURN FURTHER LEFT';
          nextColor = 'adjusting';
        } else if (_yawDeg < -48) {
          nextStatus = 'TURN BACK A LITTLE';
          nextColor = 'adjusting';
        } else {
          inPosition = true;
          nextStatus = 'HOLD STILL · LEFT';
          nextColor = 'locked';
        }
      } else if (rightProfileWanted) {
        // Subject's RIGHT shoulder = camera's left → POSITIVE yaw.
        if (_yawDeg < 18) {
          nextStatus = 'TURN FURTHER RIGHT';
          nextColor = 'adjusting';
        } else if (_yawDeg > 48) {
          nextStatus = 'TURN BACK A LITTLE';
          nextColor = 'adjusting';
        } else {
          inPosition = true;
          nextStatus = 'HOLD STILL · RIGHT';
          nextColor = 'locked';
        }
      } else if (_phase == ScanPhase.measuring) {
        // During the dramatic bone reveal, just show the scan label.
        inPosition = true;
        nextStatus = 'ANALYSING · ${((_progress * 100).clamp(0, 100)).toStringAsFixed(0)}%';
        nextColor = 'locked';
      } else if (_phase == ScanPhase.rotateLeft) {
        inPosition = false;
        nextStatus = 'TURN LEFT';
        nextColor = 'adjusting';
      } else if (_phase == ScanPhase.rotateRight) {
        inPosition = false;
        nextStatus = 'TURN RIGHT';
        nextColor = 'adjusting';
      }

      _faceInPosition = inPosition;
      if (nextStatus != _statusText || nextColor != _statusColor) {
        _statusText  = nextStatus;
        _statusColor = nextColor;
      }

      // LAYERED FALLBACK — try in order, take the first that yields enough
      // points. This guarantees we advance past SEARCHING the moment a face
      // is on screen, regardless of which ML Kit surface fires on the device.
      //   1. MediaPipe face mesh (Android only, 468 pts)
      //   2. Face contours (iOS + older Android, up to ~130 pts)
      //   3. Face landmarks (eyes, nose, mouth — ~8 pts, always available)
      //   4. BoundingBox sampled corners + center (always works, 9 pts)
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
          _fallbackHit++;
          _lastMeshPts = pts.length;
        }
      }

      if (mesh == null || !mesh.isValid) {
        // Layer 3 — landmarks
        final pts = <Offset>[];
        for (final lm in face.landmarks.values) {
          if (lm == null) continue;
          pts.add(_normalize(
            lm.position.x.toDouble(), lm.position.y.toDouble(), imgW, imgH));
        }
        // Layer 4 — bounding box corners + mid-edges + center
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
          _fallbackHit++;
          _lastMeshPts = pts.length;
        }
      }

      // Even if mesh is STILL null somehow, advance phase — a face was seen.
      // The painter checks for mesh validity before drawing mesh-dependent
      // layers, so SEARCHING → SCANNING always transitions when a face lands.
      mesh ??= FaceMesh(const []);

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
  Future<void> _shipToBackend() async {
    setState(() => _phase = ScanPhase.analysing);

    final primaryGeom = _primaryGeometry ?? _geometry ??
        const FaceGeometry(
          canthalTilt: 0, symmetryScore: 70, facialThirdTop: 33,
          facialThirdMid: 33, facialThirdLow: 34, fwhr: 1.9,
          eyeSpacingRatio: 0.46, jawAngle: 125, chinProjection: 0,
          hasReliableData: false,
        );

    if (!mounted) return;
    context.go('/report', extra: {
      'imageBytes':  _capturedImages.isNotEmpty
          ? _capturedImages.first : Uint8List(0),
      'geometry':    primaryGeom,
      'extraImages': _capturedImages.length > 1
          ? _capturedImages.sublist(1) : <Uint8List>[],
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
    super.dispose();
  }

  String _trim(Object e) {
    final s = e.toString();
    return s.length > 40 ? s.substring(0, 40) : s;
  }

  // Live pipeline HUD. Small black pill at the top-left. Tells us exactly
  // which stage is failing on a device without needing logcat:
  //   FR  frames processed
  //   FC  faces detected (non-zero = face detector works)
  //   MS  mesh hits (non-zero = 468-pt Face Mesh plugin works)
  //   FB  fallback hits (contour / landmark / bbox fills)
  //   PTS points in last mesh
  //   PLANES/FMT what the camera delivered
  //   DIM   source image dims
  //   ROT   rotation ML Kit was told
  Widget _diagPanel() {
    final (String tag, Color color, String label) = _meshHit > 0
        ? ('GREEN', AppColors.signalGreen, 'MEDIAPIPE LIVE')
        : (_fallbackHit > 0
            ? ('AMBER', AppColors.signalAmber, 'FALLBACK ONLY')
            : ('RED',   AppColors.signalRed,
                _facesHit == 0 ? 'NO FACE' : 'FACE, NO MESH'));
    final plat = Platform.isAndroid ? 'ANDROID' : (Platform.isIOS ? 'iOS' : 'OTHER');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      constraints: const BoxConstraints(maxWidth: 300),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Container(
              width: 7, height: 7,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: color, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)],
              ),
            ),
            Text('$tag · $label',
              style: TextStyle(color: color, fontSize: 9,
                fontWeight: FontWeight.w800, letterSpacing: 1.4,
                fontFamilyFallback: const ['monospace'])),
          ]),
          const SizedBox(height: 4),
          Text('$plat · ${_phase.name.toUpperCase()}',
            style: const TextStyle(color: Colors.white70, fontSize: 8.5,
              fontWeight: FontWeight.w700, letterSpacing: 1.4,
              fontFamilyFallback: ['monospace'])),
          const SizedBox(height: 3),
          Text(
            'FR $_framesTotal  FC $_facesHit  MS $_meshHit  FB $_fallbackHit  PTS $_lastMeshPts',
            style: const TextStyle(color: Colors.white, fontSize: 9,
              fontWeight: FontWeight.w600, letterSpacing: 0.6, height: 1.3,
              fontFamilyFallback: ['monospace'])),
          const SizedBox(height: 3),
          Text(
            'PLANES $_lastPlanes  FMT $_lastRawFmt  DIM ${_lastImgW}x$_lastImgH  ROT ${_rotation.name}',
            style: const TextStyle(color: Colors.white70, fontSize: 9,
              fontWeight: FontWeight.w600, letterSpacing: 0.6, height: 1.3,
              fontFamilyFallback: ['monospace'])),
          if (_pipelineErr.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(_pipelineErr,
              style: TextStyle(color: AppColors.signalAmber, fontSize: 8.5,
                fontWeight: FontWeight.w700, height: 1.3,
                fontFamilyFallback: const ['monospace'])),
          ],
        ],
      ),
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
                      color: AppColors.gold.withValues(alpha: 0.35), width: 0.8),
                  ),
                  child: Text(
                    '${(_phase.index + 1).toString().padLeft(2, '0')} / 05  ·  '
                    '${_phase.name.toUpperCase()}',
                    style: AppTypography.label.copyWith(
                      color: AppColors.gold,
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
                  valueColor: const AlwaysStoppedAnimation(AppColors.gold),
                  minHeight: 1.5,
                ),
              ),
            ),

          // Live pipeline HUD — restored so Android silent-failures can be
          // diagnosed from the device screen alone. Top-left so it doesn't
          // overlap the phase copy at the bottom or the masthead at the top.
          Positioned(
            left: 10, top: 60,
            child: SafeArea(child: _diagPanel()),
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
                      Text('Mirrorly',
                        style: AppTypography.h1.copyWith(
                          fontSize: 22,
                          letterSpacing: -0.6,
                          color: AppColors.textPrimary,
                          height: 1,
                        )),
                      const SizedBox(width: 10),
                      Container(
                        width: 4, height: 4,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: const BoxDecoration(
                          color: AppColors.gold,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const Spacer(),
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
                                color: AppColors.gold.withValues(alpha: 0.4),
                                width: 0.8),
                            ),
                            child: const Icon(Icons.tune,
                              size: 16, color: AppColors.gold),
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
