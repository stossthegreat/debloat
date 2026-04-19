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
  int          _countdown = 3;
  bool         _busy = false;

  Timer? _measureTimer;
  Timer? _countdownTimer;

  int _faceFrames = 0;
  static const int _requiredFrames = 12;  // ~2s of face-lock at typical detect rate

  bool _processing = false;

  // Diagnostic counters — visible on-screen so bugs in the detect pipeline
  // (empty meshes, rotation mismatches, unsupported devices) surface loud
  // instead of manifesting as a silent black overlay.
  int _framesTotal = 0;
  int _facesHit    = 0;
  int _meshHit     = 0;
  int _fallbackHit = 0;
  int _lastMeshPts = 0;
  String _pipelineErr = '';

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

    // Google ML Kit Face Mesh Detection is Android-only — trying to use it
    // on iOS throws MissingPluginException and kills the processing loop.
    // On iOS, mesh stays null and we fall back to face_detection contour points.
    if (Platform.isAndroid) {
      _meshService = FaceMeshService();
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
  Offset _normalize(double bx, double by, double imgW, double imgH) {
    final isIOS = Platform.isIOS;
    double nx, ny;
    switch (_rotation) {
      case InputImageRotation.rotation90deg:
        nx = bx / (isIOS ? imgW : imgH);
        ny = by / (isIOS ? imgH : imgW);
        break;
      case InputImageRotation.rotation270deg:
        nx = 1.0 - bx / (isIOS ? imgW : imgH);
        ny = by / (isIOS ? imgH : imgW);
        break;
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        nx = _isFrontCam ? 1.0 - bx / imgW : bx / imgW;
        ny = by / imgH;
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
          }
        } catch (e) {
          _pipelineErr = 'FM: ${_trim(e)}';
        }
      }
      if (faces.isNotEmpty) _facesHit++;

      if (!mounted) return;

      if (faces.isEmpty) {
        // Only reset to SEARCHING from scanning-phase — once we're past
        // measuring the user briefly loses face detection while rotating,
        // and we don't want to nuke the scan.
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

      if (_phase == ScanPhase.searching && _faceFrames >= 2) {
        _startScanning();
      }

      if (_phase == ScanPhase.scanning) {
        final p = (_faceFrames / _requiredFrames).clamp(0.0, 1.0);
        setState(() => _progress = p);
        if (_faceFrames >= _requiredFrames) {
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
    _measureTimer = Timer.periodic(40.ms, (t) {
      if (!mounted) { t.cancel(); return; }
      final np = _progress + 0.013;  // ~3s full reveal
      setState(() => _progress = np.clamp(0.0, 1.0));

      // LOCK STRIKE haptic — fires exactly when the painter's signature
      // lock-strike visual begins. Gives the user a physical beat that
      // syncs to the flash, ring, and "◆ LOCK ◆" label.
      if (!lockFired && np >= 0.90) {
        lockFired = true;
        HapticFeedback.heavyImpact();
      }

      if (np >= 1.0) {
        t.cancel();
        _startCapture();
      }
    });
  }

  void _startCapture() {
    setState(() {
      _phase     = ScanPhase.capturing;
      _progress  = 1.0;
      _countdown = 3;
    });
    HapticFeedback.mediumImpact();

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) { t.cancel(); return; }
      if (_countdown > 1) {
        HapticFeedback.lightImpact();
        setState(() => _countdown--);
      } else {
        t.cancel();
        HapticFeedback.heavyImpact();
        await _captureAndShip();
      }
    });
  }

  Future<void> _captureAndShip() async {
    if (_busy) return;
    _busy = true;
    setState(() => _phase = ScanPhase.analysing);

    try {
      await _camera?.stopImageStream();
      final file = await _camera?.takePicture();
      if (file == null) throw Exception('capture failed');
      final raw = await File(file.path).readAsBytes();

      // Bake EXIF orientation into the pixels. Front-cam JPEGs from the
      // flutter camera plugin carry orientation metadata that Flutter's
      // Image.memory honours inconsistently — and the backend definitely
      // doesn't honour it when feeding the bytes to Flux Kontext. Rewrite
      // the pixels upright so every downstream consumer sees the correct
      // orientation.
      final bytes = await compute<Uint8List, Uint8List>(
        _bakeOrientation, raw);

      if (!mounted) return;
      final geometry = _geometry ??
          const FaceGeometry(
            canthalTilt: 0, symmetryScore: 70, facialThirdTop: 33,
            facialThirdMid: 33, facialThirdLow: 34, fwhr: 1.9,
            eyeSpacingRatio: 0.46, jawAngle: 125, chinProjection: 0,
            hasReliableData: false,
          );

      context.go('/report', extra: {
        'imageBytes': bytes,
        'geometry':   geometry,
      });
    } catch (e) {
      debugPrint('Capture/ship error: $e');
      if (mounted) {
        setState(() {
          _phase = ScanPhase.searching;
          _faceFrames = 0;
        });
        _camera?.startImageStream(_processFrame);
        _busy = false;
      }
    }
  }

  String get _phaseTitle {
    switch (_phase) {
      case ScanPhase.searching:  return 'LINE UP YOUR FACE';
      case ScanPhase.scanning:   return _scanCopy[_copyIdx];
      case ScanPhase.measuring:  return 'READING YOUR BONES';
      case ScanPhase.capturing:  return 'HOLD STILL';
      case ScanPhase.analysing:  return 'WORKING ON IT';
    }
  }

  String get _phaseSub {
    switch (_phase) {
      case ScanPhase.searching:  return 'Look into the lens';
      case ScanPhase.scanning:   return 'Mapping 468 points on your face';
      case ScanPhase.measuring:  return 'Jawline · eyes · thirds · cheekbones';
      case ScanPhase.capturing:  return 'Capturing your reference frame';
      case ScanPhase.analysing:  return 'Personal analysis incoming';
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

  Widget _diagPanel() {
    // Traffic light: green = mesh firing, amber = fallback only, red = no faces
    final state = _meshHit > 0
        ? ('GREEN', AppColors.signalGreen, 'MEDIAPIPE LIVE')
        : (_fallbackHit > 0
            ? ('AMBER', AppColors.signalAmber, 'FALLBACK (CONTOUR/LANDMARK/BBOX)')
            : ('RED',   AppColors.signalRed,   _facesHit == 0
                ? 'NO FACE DETECTED'
                : 'FACE HIT, MESH FAILED'));
    final plat = Platform.isAndroid ? 'ANDROID' : (Platform.isIOS ? 'iOS' : 'OTHER');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: state.$2.withValues(alpha: 0.6), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 7, height: 7,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: state.$2, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: state.$2.withValues(alpha: 0.6), blurRadius: 6)],
                ),
              ),
              Text('${state.$1} · ${state.$3}',
                style: TextStyle(color: state.$2, fontSize: 9,
                  fontWeight: FontWeight.w800, letterSpacing: 1.4,
                  fontFamilyFallback: const ['monospace'])),
            ],
          ),
          const SizedBox(height: 4),
          Text('$plat · PHASE ${_phase.name.toUpperCase()}',
            style: const TextStyle(color: Colors.white70, fontSize: 8.5,
              fontWeight: FontWeight.w700, letterSpacing: 1.4,
              fontFamilyFallback: ['monospace'])),
          const SizedBox(height: 3),
          Text(
            'FR $_framesTotal   FC $_facesHit   MS $_meshHit   FB $_fallbackHit   PTS $_lastMeshPts',
            style: const TextStyle(color: Colors.white, fontSize: 9,
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
                  mesh:      _mesh,
                  phase:     _phase,
                  progress:  _progress,
                  countdown: _countdown,
                  animT:     _animT,
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

          // Diagnostic panel — shows exactly what the detect pipeline is
          // doing live. Remove once we trust the pipeline on target devices.
          Positioned(
            left: 10, bottom: 14,
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
