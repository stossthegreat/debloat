import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../models/face_metrics.dart';
import '../../services/face_detector_service.dart';
import '../../services/test/charisma_test_engine.dart';
import '../../services/voice/voice_coach.dart';
import '../../theme/auralay_app_colors.dart';
import '../../theme/auralay_app_typography.dart';
import '../../widgets/train/eye_target_overlay.dart';

/// The 30-second viral charisma test.
///
/// Flow:
///   1. Pre-test gate ("READY?" + tap to begin) — gives the user a moment
///      to compose, drops a calibration baseline.
///   2. 5-phase scripted test (see CharismaTestEngine).
///   3. Photo snapshot during PHASE 1 when the user is locked on target —
///      these are the eyes that go on the share card.
///   4. Auto-push to /test-result with the result + photo.
class CharismaTestScreen extends StatefulWidget {
  const CharismaTestScreen({super.key});

  @override
  State<CharismaTestScreen> createState() => _CharismaTestScreenState();
}

class _CharismaTestScreenState extends State<CharismaTestScreen>
    with TickerProviderStateMixin {
  CameraController? _camera;
  bool _cameraReady = false;
  bool _cameraError = false;

  final FaceDetectorService _detector = FaceDetectorService();
  final VoiceCoach _voice = VoiceCoach();
  late final CharismaTestEngine _engine = CharismaTestEngine(voice: _voice);

  bool _processing = false;
  FaceMetrics? _metrics;
  TestFrame _frame = TestFrame.idle();

  // Pre-test gate state
  _Stage _stage = _Stage.gate;
  int _countdown = 0;
  Timer? _countdownTimer;

  // Photo snapshot — captured during phase 1 when locked.
  Uint8List? _heroSnapshot;
  double? _heroEyeY;
  bool _snapshotTaken = false;

  // Tick driver — drives engine.tick() at fps even when no camera frame
  // arrives, so the UI animates smoothly.
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _detector.init();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw Exception('No cameras');
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
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
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _camera == null) return;
        try {
          await _camera!.startImageStream(_onFrame);
        } catch (e) {
          debugPrint('[charisma-test] startImageStream failed: $e');
        }
      });
    } catch (e) {
      debugPrint('[charisma-test] camera init failed: $e');
      if (mounted) setState(() => _cameraError = true);
    }
  }

  void _onFrame(CameraImage image) async {
    if (_processing) return;
    _processing = true;
    try {
      final desc = _camera?.description;
      final orient = desc?.sensorOrientation ?? 0;
      final isFront = desc?.lensDirection == CameraLensDirection.front;
      final m = await _detector
          .process(image, orient, isFrontCam: isFront)
          .timeout(const Duration(milliseconds: 400),
              onTimeout: () => null);
      if (!mounted || m == null) return;
      _metrics = m;

      // Capture the hero eye-strip snapshot during the LOCK phase the
      // first time the user is fully locked. This is what goes on the
      // share card — eyes locked on target = fierce.
      if (!_snapshotTaken &&
          _frame.phaseId == TestPhaseId.lock &&
          _frame.locked &&
          _frame.phaseProgress > 0.4) {
        _captureHeroSnapshot();
      }
    } catch (e) {
      debugPrint('[charisma-test] frame error: $e');
    } finally {
      _processing = false;
    }
  }

  void _onTick(Duration _) {
    if (_stage != _Stage.running) return;
    final frame = _engine.tick(_metrics);
    if (!mounted) return;
    setState(() => _frame = frame);
    if (frame.complete) {
      _finish();
    }
  }

  Future<void> _captureHeroSnapshot() async {
    if (_snapshotTaken) return;
    _snapshotTaken = true;
    try {
      final cam = _camera;
      if (cam == null || !cam.value.isStreamingImages) return;
      // Track the eye Y while we still have metrics.
      final m = _metrics;
      if (m?.leftEyePos != null && m?.rightEyePos != null) {
        _heroEyeY = (m!.leftEyePos!.dy + m.rightEyePos!.dy) / 2;
      }
      // takePicture requires the stream paused.
      await cam.stopImageStream();
      final XFile shot = await cam.takePicture();
      _heroSnapshot = await shot.readAsBytes();
      // Resume so the rest of the test still gets metrics.
      await cam.startImageStream(_onFrame);
    } catch (e) {
      debugPrint('[charisma-test] snapshot failed: $e');
    }
  }

  // ── Pre-test gate ─────────────────────────────────────────────────────

  void _startCountdown() {
    HapticFeedback.lightImpact();
    setState(() {
      _stage = _Stage.countdown;
      _countdown = 3;
    });
    _voice.play(VoiceCoach.lookAtEyes);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_countdown > 1) {
        setState(() => _countdown--);
        HapticFeedback.selectionClick();
      } else {
        t.cancel();
        _beginTest();
      }
    });
  }

  void _beginTest() {
    HapticFeedback.heavyImpact();
    _detector.startCalibration(duration: const Duration(milliseconds: 2500));
    _engine.start();
    setState(() => _stage = _Stage.running);
    _ticker.start();
  }

  Future<void> _finish() async {
    _ticker.stop();
    final result = _engine.buildResult();

    // Final snapshot fallback — if we never got a locked snapshot during
    // phase 1, take one now from the last raw frame.
    if (_heroSnapshot == null) {
      try {
        final cam = _camera;
        if (cam != null && cam.value.isStreamingImages) {
          await cam.stopImageStream();
          final XFile shot = await cam.takePicture();
          _heroSnapshot = await shot.readAsBytes();
          if (_metrics?.leftEyePos != null && _metrics?.rightEyePos != null) {
            _heroEyeY = (_metrics!.leftEyePos!.dy +
                         _metrics!.rightEyePos!.dy) / 2;
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    context.go('/test-result', extra: {
      'result':       result,
      'photoBytes':   _heroSnapshot,
      'eyeY':         _heroEyeY,
      'engineName':   _detector.engineName,
      'hasIris':      _detector.hasIris,
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _ticker.dispose();
    _camera?.stopImageStream();
    _camera?.dispose();
    _detector.dispose();
    _voice.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_cameraReady && _camera != null) _CameraLayer(controller: _camera!),
          const _Vignette(),

          // Live target overlay (only during running stage)
          if (_stage == _Stage.running)
            EyeTargetOverlay(
              center:    _frame.target,
              locked:    _frame.locked,
              intensity: _frame.intensity,
              hidden:    _frame.hidden,
            ),

          // Top progress bar — fills as the test runs
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: _stage == _Stage.running
                    ? _PhaseProgressStrip(frame: _frame)
                    : const SizedBox.shrink(),
              ),
            ),
          ),

          // Bottom caption + label area (running stage)
          if (_stage == _Stage.running) _CaptionLayer(frame: _frame),

          // Pre-test gate
          if (_stage == _Stage.gate) _PreTestGate(onStart: _startCountdown),

          // Countdown
          if (_stage == _Stage.countdown) _CountdownOverlay(value: _countdown),

          // Camera error
          if (_cameraError) const _CameraError(),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Camera layer
// ──────────────────────────────────────────────────────────────────────────

class _CameraLayer extends StatelessWidget {
  final CameraController controller;
  const _CameraLayer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width:  controller.value.previewSize?.height ?? 1,
          height: controller.value.previewSize?.width  ?? 1,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

class _Vignette extends StatelessWidget {
  const _Vignette();
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
          stops: const [0.45, 1.0],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Pre-test gate — composed black panel with READY? + start button
// ──────────────────────────────────────────────────────────────────────────

class _PreTestGate extends StatelessWidget {
  final VoidCallback onStart;
  const _PreTestGate({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.78),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('MIRRORLY',
                style: AppTypography.h1.copyWith(
                  fontSize: 22, letterSpacing: 6,
                  fontWeight: FontWeight.w900,
                )).animate().fadeIn(duration: 480.ms),
              const SizedBox(height: 4),
              Text('CHARISMA INDEX',
                style: AppTypography.label.copyWith(
                  color: AppColors.accent,
                  fontSize: 11, letterSpacing: 3.5,
                  fontWeight: FontWeight.w800,
                )).animate().fadeIn(delay: 120.ms, duration: 400.ms),

              const SizedBox(height: 60),

              Text('30 SECONDS.',
                style: AppTypography.display.copyWith(
                  fontSize: 56, height: 1.0, letterSpacing: -1.5,
                  fontStyle: FontStyle.italic,
                  color: AppColors.accent,
                  fontWeight: FontWeight.w900,
                )).animate().fadeIn(delay: 220.ms, duration: 500.ms),
              const SizedBox(height: 6),
              Text('FIVE BEATS.',
                style: AppTypography.display.copyWith(
                  fontSize: 56, height: 1.0, letterSpacing: -1.5,
                  fontStyle: FontStyle.italic,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w900,
                )).animate().fadeIn(delay: 320.ms, duration: 500.ms),
              const SizedBox(height: 6),
              Text('ONE NUMBER.',
                style: AppTypography.display.copyWith(
                  fontSize: 56, height: 1.0, letterSpacing: -1.5,
                  fontStyle: FontStyle.italic,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w900,
                )).animate().fadeIn(delay: 420.ms, duration: 500.ms),

              const SizedBox(height: 36),

              Container(width: 44, height: 1,
                color: AppColors.accent.withValues(alpha: 0.6))
                .animate().fadeIn(delay: 540.ms, duration: 400.ms),

              const SizedBox(height: 28),

              Text(
                'Look at the eyes.\nA voice will guide you.\nDon\'t look away.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 14, height: 1.6,
                )).animate().fadeIn(delay: 620.ms, duration: 460.ms),

              const Spacer(),

              SizedBox(
                width: double.infinity, height: 60,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  onPressed: onStart,
                  child: const Text('BEGIN THE TEST',
                    style: TextStyle(
                      fontSize: 15, letterSpacing: 3,
                      fontWeight: FontWeight.w900,
                    )),
                ),
              ).animate().fadeIn(delay: 760.ms, duration: 460.ms)
                .slideY(begin: 0.1, end: 0,
                  curve: Curves.easeOut, duration: 460.ms, delay: 760.ms),
              const SizedBox(height: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Countdown — 3, 2, 1
// ──────────────────────────────────────────────────────────────────────────

class _CountdownOverlay extends StatelessWidget {
  final int value;
  const _CountdownOverlay({required this.value});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.66),
      child: Center(
        child: Text(
          '$value',
          key: ValueKey('cd-$value'),
          style: AppTypography.display.copyWith(
            fontSize: 220, height: 1, letterSpacing: -10,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w900,
            color: AppColors.accent,
            shadows: [Shadow(
              color: AppColors.accent.withValues(alpha: 0.45),
              blurRadius: 56,
            )],
          ),
        ).animate(key: ValueKey('cd-$value'))
          .scale(begin: const Offset(1.4, 1.4), end: const Offset(1, 1),
            duration: 360.ms, curve: Curves.easeOutBack)
          .fadeIn(duration: 200.ms),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Caption + phase label (bottom)
// ──────────────────────────────────────────────────────────────────────────

class _CaptionLayer extends StatelessWidget {
  final TestFrame frame;
  const _CaptionLayer({required this.frame});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 24, right: 24, bottom: 56,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // PHASE LABEL — small caps, red, animated on change
          AnimatedSwitcher(
            duration: 300.ms,
            child: Text(
              frame.label,
              key: ValueKey(frame.label),
              style: AppTypography.label.copyWith(
                color: AppColors.accent,
                fontSize: 11, letterSpacing: 3.5,
                fontWeight: FontWeight.w900,
              )),
          ),
          const SizedBox(height: 8),
          // CAPTION — coaching line for the phase
          AnimatedSwitcher(
            duration: 350.ms,
            child: Text(
              frame.caption,
              key: ValueKey(frame.caption),
              textAlign: TextAlign.center,
              style: AppTypography.hudCoach.copyWith(
                fontSize: 19, height: 1.4, letterSpacing: 0.2,
                color: AppColors.textPrimary.withValues(alpha: 0.92),
                shadows: [Shadow(
                  color: Colors.black.withValues(alpha: 0.85),
                  blurRadius: 18)],
              )),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Phase progress strip — 5 small bars at the top showing phase + progress
// ──────────────────────────────────────────────────────────────────────────

class _PhaseProgressStrip extends StatelessWidget {
  final TestFrame frame;
  const _PhaseProgressStrip({required this.frame});

  static const _phases = [
    TestPhaseId.lock,
    TestPhaseId.smile,
    TestPhaseId.breakAway,
    TestPhaseId.returnHome,
    TestPhaseId.still,
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < _phases.length; i++) ...[
          Expanded(child: _PhaseSegment(
            isPast:    _phases.indexOf(frame.phaseId ?? TestPhaseId.lock) > i,
            isActive:  frame.phaseId == _phases[i],
            progress:  frame.phaseId == _phases[i] ? frame.phaseProgress : 0,
          )),
          if (i < _phases.length - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _PhaseSegment extends StatelessWidget {
  final bool isPast;
  final bool isActive;
  final double progress;
  const _PhaseSegment({
    required this.isPast,
    required this.isActive,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 3,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(1.5),
        child: FractionallySizedBox(
          widthFactor: isPast ? 1.0 : (isActive ? progress : 0.0),
          alignment: Alignment.centerLeft,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.accent,
              boxShadow: isActive ? [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.6),
                  blurRadius: 6),
              ] : null,
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Camera error
// ──────────────────────────────────────────────────────────────────────────

class _CameraError extends StatelessWidget {
  const _CameraError();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined,
              size: 36, color: AppColors.textTertiary),
            const SizedBox(height: 14),
            Text('Camera unavailable',
              style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Text('The test needs your front camera. Grant access in Settings.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary)),
          ],
        ),
      ),
    );
  }
}

enum _Stage { gate, countdown, running }
