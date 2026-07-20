import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/face_metrics.dart';
import '../../models/technique.dart';
import '../../providers/auralay_app_provider.dart';
import '../../services/face_detector_service.dart';
import '../../services/test/charisma_test_engine.dart';
import '../../theme/auralay_app_colors.dart';
import '../../theme/auralay_app_typography.dart';
import '../../widgets/train/eye_target_overlay.dart';
import '../../widgets/train/scan_overlay_painter.dart';

class TrainScreen extends StatefulWidget {
  /// Auto-start the session 600ms after the face lock acquires (no
  /// manual record-button tap required to begin). Session ends when the
  /// user taps record. Default true — there's no longer a dead-screen
  /// path since the /test route was removed.
  final bool autoStart;

  const TrainScreen({super.key, this.autoStart = true});

  @override
  State<TrainScreen> createState() => _TrainScreenState();
}

class _TrainScreenState extends State<TrainScreen>
    with TickerProviderStateMixin {

  // ── Camera ─────────────────────────────────────────────────────────────────
  CameraController? _camera;
  bool _cameraReady = false;
  bool _cameraError = false;

  // ── Detection ──────────────────────────────────────────────────────────────
  final FaceDetectorService _detector = FaceDetectorService();
  bool _processing = false;
  FaceMetrics? _metrics;
  int _noFaceFrames = 0;
  static const int _noFaceThreshold = 20;

  // ── Session ─────────────────────────────────────────────────────────────────
  bool _sessionActive = false;
  bool _calibrating = false;        // true during the 3s baseline capture
  int _sessionSeconds = 0;
  Timer? _sessionTimer;
  final List<double> _auraHistory = [];

  // Per-metric averages so the share card + post-session use AVERAGE, not last frame.
  final List<double> _eyeContactHistory = [];
  final List<double> _stabilityHistory  = [];
  final List<double> _smileHistory      = [];
  final List<double> _blinkHistory      = [];
  // Four-dimension aggregates for the new elite scoring.
  final List<double> _presenceHistory   = [];
  final List<double> _warmthHistory     = [];
  final List<double> _composureHistory  = [];
  final List<double> _rangeHistory      = [];

  // Eye Y at the moment we capture the snapshot — used by the eye-strip
  // share card to clip the eye band exactly.
  double? _lastEyeYNormalized;

  // ── Scan state machine ─────────────────────────────────────────────────────
  ScanState _scanState = ScanState.searching;
  double _lockProgress = 0;

  // ── Animations ─────────────────────────────────────────────────────────────
  late final AnimationController _loopAnim;
  late final AnimationController _lockAnim;

  // ── Technique ──────────────────────────────────────────────────────────────
  int _coachPhraseIndex = 0;
  Timer? _coachTimer;

  @override
  void initState() {
    super.initState();

    _loopAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _lockAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..addListener(() {
        if (mounted) setState(() => _lockProgress = _lockAnim.value);
      });

    _detector.init();
    _initCamera();
  }

  // ── Camera ─────────────────────────────────────────────────────────────────
  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('No cameras');
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      // CRITICAL — platform-split image format so ML Kit actually gets
      // bytes it understands. iOS ML Kit expects BGRA8888; Android ML Kit
      // expects NV21. Setting nv21 unconditionally silently fails on iOS
      // (ML Kit returns empty face lists → scan state never advances).
      // Same bug that bit ImHim Looks before we patched it.
      _camera = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await _camera!.initialize();
      if (!mounted) return;
      setState(() => _cameraReady = true);
      // Defer stream start until AFTER the first paint frame. Otherwise
      // frames can arrive before mounted is true and the _onFrame guard
      // short-circuits every call — symptoms: "camera shows preview but
      // detection never fires." The postFrame callback guarantees the
      // widget tree is fully mounted before ML Kit starts receiving.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _camera == null) return;
        try {
          await _camera!.startImageStream(_onFrame);
        } catch (e) {
          debugPrint('[aura-cam] startImageStream failed: $e');
        }
      });
    } catch (e) {
      debugPrint('[aura-cam] init failed: $e');
      if (mounted) setState(() => _cameraError = true);
    }
  }

  // ── Frame counters for debug heartbeat — so we can tell at a glance
  //    whether camera frames are arriving AND whether ML Kit is parsing
  //    them. Silent-fail is by far the worst mode and this removes it.
  int _framesTotal = 0;
  int _facesHit    = 0;

  // ── Frame processing ────────────────────────────────────────────────────────
  void _onFrame(CameraImage image) async {
    if (_processing) return;
    _processing = true;
    _framesTotal++;
    try {
      final desc = _camera?.description;
      final orientation = desc?.sensorOrientation ?? 0;
      final isFrontCam = desc?.lensDirection == CameraLensDirection.front;
      // Timeout — if ML Kit ever hangs (iOS BGRA edge cases, low-memory
      // stall), _processing would otherwise stick on forever and every
      // subsequent frame drops silently. 400ms is ~12 ML Kit frames of
      // headroom; anything past that is a broken detector, not latency.
      final metrics = await _detector.process(image, orientation,
              isFrontCam: isFrontCam)
          .timeout(const Duration(milliseconds: 400),
              onTimeout: () => null);
      if (!mounted) return;

      if (metrics == null) {
        _noFaceFrames++;
        if (_noFaceFrames >= _noFaceThreshold) _transitionTo(ScanState.searching);
      } else {
        _noFaceFrames = 0;
        _facesHit++;
        _onFaceDetected(metrics);
      }

      // Every ~second, log a debug heartbeat. Shows up in `flutter logs`
      // / Xcode / logcat. Silent failure is over.
      if (_framesTotal % 30 == 0) {
        debugPrint('[aura-detect] frames=$_framesTotal faces=$_facesHit '
            'state=${_scanState.name} img=${image.width}x${image.height} '
            'orient=$orientation');
      }
    } catch (e) {
      debugPrint('[aura-detect] exception: $e');
    } finally {
      _processing = false;
    }
  }

  void _onFaceDetected(FaceMetrics metrics) {
    setState(() => _metrics = metrics);
    switch (_scanState) {
      case ScanState.searching:
        _transitionTo(ScanState.scanning);
      case ScanState.scanning:
        if (metrics.isFaceCentered) _beginLocking();
      case ScanState.locking:
        break;
      case ScanState.locked:
      case ScanState.training:
        if (_sessionActive) _recordFrame(metrics);
    }
  }

  void _beginLocking() {
    _transitionTo(ScanState.locking);
    _lockAnim.forward(from: 0).then((_) {
      if (!mounted) return;
      _transitionTo(ScanState.locked);
      HapticFeedback.mediumImpact();
      // Auto-start session 600ms after lock if configured. Both /test
      // and the MainShell TRAIN tab use this so users never get stuck
      // staring at "LOCKED" with no session running.
      if (widget.autoStart && !_sessionActive) {
        Future<void>.delayed(const Duration(milliseconds: 600), () {
          if (mounted && !_sessionActive) _startSession();
        });
      }
    });
  }

  void _transitionTo(ScanState next) {
    if (_scanState == next) return;
    setState(() {
      _scanState = next;
      if (next == ScanState.searching) {
        _lockProgress = 0;
        _lockAnim.reset();
      }
    });
  }

  // ── Session lifecycle ───────────────────────────────────────────────────────
  void _toggleSession() {
    HapticFeedback.lightImpact();
    _sessionActive ? _endSession() : _startSession();
  }

  void _startSession() {
    // Start a 3-second neutral-baseline capture on the detector BEFORE we
    // open the scoring window. The gaze signal is only legit relative to
    // the user's resting pose — otherwise a naturally asymmetric face gets
    // scored as "looking away" from the first frame.
    _detector.startCalibration(duration: const Duration(seconds: 3));
    setState(() {
      _sessionActive = true;
      _calibrating = true;
      _sessionSeconds = 0;
      _auraHistory.clear();
      _eyeContactHistory.clear();
      _stabilityHistory.clear();
      _smileHistory.clear();
      _blinkHistory.clear();
      _presenceHistory.clear();
      _warmthHistory.clear();
      _composureHistory.clear();
      _rangeHistory.clear();
      _coachPhraseIndex = 0;
    });
    _transitionTo(ScanState.training);
    // Flip calibrating off after the detector's capture window.
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted && _sessionActive) setState(() => _calibrating = false);
    });
    _sessionTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() => _sessionSeconds++));

    // Advance coaching phrases every ~4 seconds
    _coachTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_sessionActive) return;
      final technique = _currentTechnique;
      setState(() {
        _coachPhraseIndex =
            (_coachPhraseIndex + 1) % technique.coachingPhrases.length;
      });
    });
  }

  Future<void> _endSession() async {
    _sessionTimer?.cancel();
    _coachTimer?.cancel();

    // Snapshot the camera BEFORE we tear anything down. Need to pause the
    // image stream first because takePicture() can't run while streaming.
    Uint8List? photoBytes;
    try {
      final cam = _camera;
      if (cam != null && cam.value.isStreamingImages) {
        await cam.stopImageStream();
        final XFile shot = await cam.takePicture();
        photoBytes = await shot.readAsBytes();
        // Restart streaming so the user can train again from this screen
        // without leaving + re-initialising the camera.
        await cam.startImageStream(_onFrame);
      }
    } catch (_) {
      photoBytes = null;
    }

    final avgAura       = _avg(_auraHistory);
    final avgEyeContact = _avg(_eyeContactHistory);
    final avgStability  = _avg(_stabilityHistory);
    final avgSmile      = _avg(_smileHistory);
    final avgBlink      = _avg(_blinkHistory);
    final avgPresence   = _avg(_presenceHistory);
    final avgWarmth     = _avg(_warmthHistory);
    final avgComposure  = _avg(_composureHistory);
    final avgRange      = _avg(_rangeHistory);

    setState(() => _sessionActive = false);
    _transitionTo(ScanState.locked);

    if (!mounted) return;

    // Synthesize a CharismaTestResult from the training session metrics so
    // the elite ResultRevealScreen renders for BOTH the viral test AND the
    // free-practice tab. We don't have phase scores here (no scripted
    // phases in free training), so we map the four dimensions onto four
    // labelled bars and skip the BREAK phase.
    //
    // Approximate "blinks during session" from blinks-per-minute average
    // × elapsed minutes. Same formula as the test engine.
    final testSec = _sessionSeconds.clamp(1, 600);
    final trainingResult = CharismaTestResult(
      overallScore:  avgAura.clamp(0, 100).round(),
      phaseScores:   {
        TestPhaseId.lock:       avgEyeContact,
        TestPhaseId.smile:      avgSmile,
        TestPhaseId.still:      avgStability,
        TestPhaseId.returnHome: (avgComposure * 100).clamp(0, 100),
      },
      avgPresence:   avgPresence  * 100,
      avgComposure:  avgComposure * 100,
      avgWarmth:     avgWarmth    * 100,
      avgRange:      avgRange     * 100,
      blinkCount:    (avgBlink * testSec / 60.0).round(),
      avgBlinkRate:  avgBlink,
      peakSmilePct:  avgSmile,
      lookAwayCount: 0,
      testSeconds:   testSec,
    );

    context.push('/test-result', extra: {
      'result':         trainingResult,
      'photoBytes':     photoBytes,
      'eyeY':           _lastEyeYNormalized,
      'engineName':     _detector.engineName,
      'hasIris':        _detector.hasIris,
      'isFreeTraining': true,
    });
  }

  void _recordFrame(FaceMetrics m) {
    // During the 3s calibration window, skip scoring — the detector's
    // baseline is still being captured and the numbers aren't stable yet.
    if (_calibrating) {
      // Still track the most recent eye Y for the share-card crop.
      final eye = m.leftEyePos != null && m.rightEyePos != null
          ? (m.leftEyePos!.dy + m.rightEyePos!.dy) / 2
          : m.faceCenter.dy - 0.08;
      _lastEyeYNormalized = eye;
      return;
    }

    _auraHistory.add(m.overallAura);
    _eyeContactHistory.add(m.eyeContactPct);
    _stabilityHistory.add(m.stabilityPct);
    _smileHistory.add(m.smilePct);
    _blinkHistory.add(m.blinkRate);
    _presenceHistory.add(m.presenceScore);
    _warmthHistory.add(m.warmthScore);
    _composureHistory.add(m.composureScore);
    _rangeHistory.add(m.rangeScore);

    // Keep last ~4s @ 30fps so averages reflect recent state but smooth noise.
    const cap = 120;
    for (final h in [_auraHistory, _eyeContactHistory, _stabilityHistory,
                     _smileHistory, _blinkHistory,
                     _presenceHistory, _warmthHistory,
                     _composureHistory, _rangeHistory]) {
      if (h.length > cap) h.removeAt(0);
    }

    // Track the most recent eye Y for the share-card crop.
    final eye = m.leftEyePos != null && m.rightEyePos != null
        ? (m.leftEyePos!.dy + m.rightEyePos!.dy) / 2
        : m.faceCenter.dy - 0.08; // fallback ~8% above face centre
    _lastEyeYNormalized = eye;
  }

  double _avg(List<double> xs) =>
      xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

  // ── Computed values ─────────────────────────────────────────────────────────
  Technique get _currentTechnique {
    final day = context.read<AuralayAppProvider>().state.currentDay;
    return Technique.forDay(day);
  }

  String get _coachLine {
    if (!_sessionActive) {
      return switch (_scanState) {
        ScanState.searching => 'Position your face in frame.',
        ScanState.scanning  => 'Reading your presence...',
        ScanState.locking   => 'Hold still.',
        ScanState.locked    => 'Locked. Begin when ready.',
        ScanState.training  => '',
      };
    }

    // Calibration phase — ask the user to hold neutral so the baseline
    // captures their resting pose cleanly.
    if (_calibrating) {
      return 'Hold a neutral face. Calibrating…';
    }

    final phrases = _currentTechnique.coachingPhrases;
    final idx = _coachPhraseIndex.clamp(0, phrases.length - 1);

    // Event-driven coaching: if the user is failing a signal, override the
    // rotating technique phrase with a precise correction. Priority order:
    // gaze first (biggest signal), then blink, then stillness.
    if (_metrics != null) {
      final m = _metrics!;
      if (!m.isGoodEyeContact && _scanState == ScanState.training) {
        return "Eyes back. Don't look away.";
      }
      if (m.isBlinkingTooFast) return 'Slow your blink down.';
      if (!m.isGoodStability)  return 'Keep your head still.';
    }

    return phrases[idx];
  }

  String get _stateLabel => switch (_scanState) {
    ScanState.searching => 'SEARCHING',
    ScanState.scanning  => 'SCANNING',
    ScanState.locking   => 'LOCKING',
    ScanState.locked    => 'LOCKED',
    ScanState.training  => 'TRAINING',
  };

  Color get _stateColor => switch (_scanState) {
    ScanState.searching => AppColors.textTertiary,
    ScanState.scanning  => AppColors.scanBlue,
    ScanState.locking   => AppColors.scanBlue,
    ScanState.locked    => AppColors.signalGreen,
    ScanState.training  => AppColors.accent,
  };

  double get _sessionAura => _auraHistory.isEmpty
      ? 0
      : _auraHistory.reduce((a, b) => a + b) / _auraHistory.length;

  /// True when the user's screen-space gaze sits within a 12% radius of
  /// the eye-target center (preview-space 0.5, 0.42). Drives the
  /// EyeTargetOverlay's lock state in the TRAIN tab.
  bool get _gazeLocked {
    final g = _metrics?.gazePoint;
    if (g == null) return false;
    const target = Offset(0.5, 0.42);
    return (g - target).distance < 0.12;
  }

  String get _timerLabel {
    final m = _sessionSeconds ~/ 60;
    final s = _sessionSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _coachTimer?.cancel();
    _loopAnim.dispose();
    _lockAnim.dispose();
    // Detach the stream callback FIRST so no stale frame tries to touch
    // state after dispose. Fire-and-forget is fine here — dispose() is
    // synchronous by Flutter contract, but the plugin handles the async
    // teardown internally without blocking us.
    final cam = _camera;
    _camera = null;
    if (cam != null) {
      cam.stopImageStream().catchError((_) {}).whenComplete(() {
        cam.dispose();
      });
    }
    _detector.dispose();
    super.dispose();
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final technique = _currentTechnique;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera + overlay fused. CRITICAL: the CustomPaint must be a
          // CHILD of CameraPreview (not a sibling in the outer Stack),
          // so the overlay inherits the EXACT transform the preview uses
          // to fit the portrait screen. Sibling overlays render in raw
          // screen coords while the camera texture is being scaled /
          // rotated / mirrored — causing the mesh to float detached from
          // the actual face. This was the whole root cause of "catches
          // my blinks but nothing else works" — detection fires, but the
          // mesh is drawn at sensor-frame coords that don't match where
          // the face appears in the preview.
          if (_cameraReady && _camera != null)
            _CameraLayer(
              controller: _camera!,
              overlay: AnimatedBuilder(
                animation: Listenable.merge([_loopAnim, _lockAnim]),
                builder: (_, __) => LayoutBuilder(
                  builder: (_, constraints) => CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: ScanOverlayPainter(
                      state: _scanState,
                      metrics: _metrics,
                      animValue: _loopAnim.value,
                      lockProgress: _lockProgress,
                    ),
                  ),
                ),
              ),
            ),

          // Vignette drawn AFTER the camera+overlay so it darkens edges
          // but doesn't obscure the mesh.
          const _Vignette(),

          // ── EYE TARGET — same overlay used in the charisma test ─────
          // Stationary at preview-center. Lock state is computed live
          // from the user's gazePoint vs. a small radius around the
          // target. Gives the user a visible thing to actually look at,
          // and the lock-glow tells them when their gaze is "on".
          if (_sessionActive)
            EyeTargetOverlay(
              center: const Offset(0.5, 0.42),
              locked: _gazeLocked,
            ),

          // Camera error state
          if (_cameraError) const _CameraErrorOverlay(),

          // Top bar
          Positioned(
            top: 0, left: 0, right: 0,
            child: _TopBar(
              technique: technique,
              stateLabel: _stateLabel,
              stateColor: _stateColor,
              sessionActive: _sessionActive,
              timerLabel: _timerLabel,
              auraScore: _sessionAura,
              streak: context.watch<AuralayAppProvider>().state.streakDays,
              onSettings: () => context.push('/settings'),
            ),
          ),

          // Live metric chips (training only)
          if (_sessionActive && _metrics != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 88,
              left: 20, right: 20,
              child: _MetricRow(metrics: _metrics!),
            ),

          // Technique tagline (locked state only — before session begins)
          if (_scanState == ScanState.locked && !_sessionActive)
            Positioned(
              bottom: 215,
              left: 40, right: 40,
              child: _TechniqueIntro(technique: technique),
            ),

          // Coach text
          Positioned(
            bottom: 152,
            left: 32, right: 32,
            child: _CoachText(line: _coachLine),
          ),

          // Record button
          Positioned(
            bottom: 56,
            left: 0, right: 0,
            child: Center(
              child: _RecordButton(
                active: _sessionActive,
                // Was: only enabled on LOCKED or TRAINING. If face detection
                // never fires on device (ML Kit silent-fail), user was
                // trapped — record button permanently disabled. Now any
                // state past SEARCHING unlocks it so the user can always
                // start manually.
                enabled: _cameraReady && _scanState != ScanState.searching,
                onTap: _toggleSession,
              ),
            ),
          ),

          // If face detection hasn't engaged after ~5s, surface a hint so
          // the user knows what to check.
          if (_cameraReady && _metrics == null && _scanState == ScanState.searching)
            const Positioned(
              bottom: 130, left: 24, right: 24,
              child: _SearchingHint(),
            ),
        ],
      ),
    );
  }
}

/// Hint shown when face detection is taking a while — helps the user
/// correct what they can (lighting, distance, pointing at face) and stops
/// the screen from feeling dead.
class _SearchingHint extends StatelessWidget {
  const _SearchingHint();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.22), width: 0.7),
      ),
      child: const Text(
        'Can\'t see you — bring the camera up to face height, '
        'well lit, and point it at your eyes.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white, fontSize: 12.5,
          height: 1.35, fontWeight: FontWeight.w500,
        ),
      ),
    ).animate().fadeIn(delay: 5000.ms, duration: 500.ms);
  }
}

// ── Camera layer ─────────────────────────────────────────────────────────────
// Cover-fill CameraPreview with the scan overlay as its child. The child
// inherits the preview's display transform (rotation + mirror on iOS front
// cam, scale-to-cover for portrait), so the overlay aligns with the face
// the user is actually looking at — not the raw sensor-frame where ML Kit
// returned coordinates.
class _CameraLayer extends StatelessWidget {
  final CameraController controller;
  final Widget overlay;
  const _CameraLayer({required this.controller, required this.overlay});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * controller.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;

    return ClipRect(
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.center,
        child: Center(
          child: CameraPreview(controller, child: overlay),
        ),
      ),
    );
  }
}

// ── Vignette ──────────────────────────────────────────────────────────────────
class _Vignette extends StatelessWidget {
  const _Vignette();
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.52)],
          stops: const [0.48, 1.0],
        ),
      ),
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final Technique technique;
  final String stateLabel;
  final Color stateColor;
  final bool sessionActive;
  final String timerLabel;
  final double auraScore;
  final int streak;
  final VoidCallback onSettings;

  const _TopBar({
    required this.technique,
    required this.stateLabel,
    required this.stateColor,
    required this.sessionActive,
    required this.timerLabel,
    required this.auraScore,
    required this.streak,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, top + 14, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Streak badge
          if (streak > 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_fire_department_rounded,
                    size: 12, color: AppColors.accent),
                const SizedBox(width: 3),
                Text('$streak',
                  style: AppTypography.label.copyWith(
                      color: AppColors.accent, fontSize: 11)),
              ],
            )
          else
            const SizedBox(width: 32),

          const Spacer(),

          // Centre: state dot + label OR technique name
          if (!sessionActive)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5, height: 5,
                      decoration: BoxDecoration(
                        color: stateColor,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(
                          color: stateColor.withValues(alpha: 0.7),
                          blurRadius: 5, spreadRadius: 1)],
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(stateLabel,
                      style: AppTypography.label.copyWith(
                        color: stateColor, letterSpacing: 2, fontSize: 10)),
                  ],
                ),
                if (stateLabel == 'LOCKED') ...[
                  const SizedBox(height: 4),
                  Text(technique.name.toUpperCase(),
                    style: AppTypography.label.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 9, letterSpacing: 1.5)),
                ],
              ],
            )
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(timerLabel,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 14, letterSpacing: 2.5)),
                const SizedBox(height: 3),
                Text('${_sessionAuraStr(auraScore)} AURA',
                  style: AppTypography.label.copyWith(
                    color: AppColors.accent, fontSize: 9, letterSpacing: 1)),
              ],
            ),

          const Spacer(),

          // Right: settings
          GestureDetector(
            onTap: onSettings,
            child: const Icon(Icons.tune_rounded,
                size: 19, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  String _sessionAuraStr(double v) => v.toStringAsFixed(0);
}

// ── Technique intro (pre-session, locked state) ───────────────────────────────
class _TechniqueIntro extends StatelessWidget {
  final Technique technique;
  const _TechniqueIntro({required this.technique});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          technique.tagline,
          textAlign: TextAlign.center,
          style: AppTypography.label.copyWith(
            color: AppColors.accent,
            letterSpacing: 1.5,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          technique.drillInstruction,
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary.withValues(alpha: 0.75),
            height: 1.6,
            fontSize: 12,
          ),
        ),
      ],
    )
    .animate()
    .fadeIn(delay: 200.ms, duration: 500.ms);
  }
}

// ── Live metric chips ─────────────────────────────────────────────────────────
class _MetricRow extends StatelessWidget {
  final FaceMetrics metrics;
  const _MetricRow({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Chip(
          label: 'EYES',
          value: '${metrics.eyeContactPct.toStringAsFixed(0)}%',
          good: metrics.isGoodEyeContact,
        ),
        const SizedBox(width: 6),
        _Chip(
          label: 'BLINK',
          value: '${metrics.blinkRate.toStringAsFixed(0)}/m',
          good: !metrics.isBlinkingTooFast && !metrics.isBlinkingTooSlow,
        ),
        const SizedBox(width: 6),
        _Chip(
          label: 'STILL',
          value: '${metrics.stabilityPct.toStringAsFixed(0)}%',
          good: metrics.isGoodStability,
        ),
        const SizedBox(width: 6),
        _Chip(
          label: 'SMILE',
          value: '${metrics.smilePct.toStringAsFixed(0)}%',
          good: metrics.isSmiling,
        ),
      ],
    ).animate().fadeIn(duration: 300.ms);
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String value;
  final bool good;
  const _Chip({required this.label, required this.value, required this.good});

  @override
  Widget build(BuildContext context) {
    final color = good ? AppColors.signalGreen : AppColors.signalAmber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface1.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
            style: AppTypography.label.copyWith(
              fontSize: 8, letterSpacing: 1.5,
              color: AppColors.textTertiary)),
          const SizedBox(height: 2),
          Text(value,
            style: AppTypography.label.copyWith(
              fontSize: 12, color: color, letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

// ── Coach text ────────────────────────────────────────────────────────────────
class _CoachText extends StatelessWidget {
  final String line;
  const _CoachText({required this.line});

  @override
  Widget build(BuildContext context) {
    if (line.isEmpty) return const SizedBox.shrink();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.10),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: child,
        ),
      ),
      child: Text(
        line,
        key: ValueKey(line),
        textAlign: TextAlign.center,
        style: AppTypography.hudCoach.copyWith(
          color: AppColors.textPrimary.withValues(alpha: 0.88),
          fontSize: 18,
          letterSpacing: 0.3,
          height: 1.5,
          shadows: [Shadow(
            color: Colors.black.withValues(alpha: 0.85),
            blurRadius: 18,
          )],
        ),
      ),
    );
  }
}

// ── Record button ──────────────────────────────────────────────────────────────
class _RecordButton extends StatelessWidget {
  final bool active;
  final bool enabled;
  final VoidCallback onTap;
  const _RecordButton({
    required this.active, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        width: active ? 58 : 72,
        height: active ? 58 : 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? AppColors.signalRed.withValues(alpha: 0.10)
              : Colors.transparent,
          border: Border.all(
            color: enabled
                ? (active ? AppColors.signalRed : AppColors.textPrimary)
                : AppColors.textTertiary,
            width: 2,
          ),
          boxShadow: active
              ? [BoxShadow(
                  color: AppColors.signalRed.withValues(alpha: 0.32),
                  blurRadius: 28, spreadRadius: 4)]
              : enabled
                  ? [BoxShadow(
                      color: AppColors.textPrimary.withValues(alpha: 0.07),
                      blurRadius: 18)]
                  : [],
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: active
                ? Container(
                    key: const ValueKey('stop'),
                    width: 15, height: 15,
                    decoration: BoxDecoration(
                      color: AppColors.signalRed,
                      borderRadius: BorderRadius.circular(3),
                    ))
                : Container(
                    key: const ValueKey('start'),
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      color: enabled
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                      shape: BoxShape.circle,
                    )),
          ),
        ),
      ),
    );
  }
}

// ── Camera error ──────────────────────────────────────────────────────────────
class _CameraErrorOverlay extends StatelessWidget {
  const _CameraErrorOverlay();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.camera_alt_outlined,
              size: 36, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text('Camera unavailable',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text('Grant camera access in Settings.',
            style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}
