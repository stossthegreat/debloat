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
import '../../services/test/seduction_lesson_engine.dart';
import '../../services/voice/voice_coach.dart';
import '../../theme/auralay_app_colors.dart';
import '../../theme/auralay_app_typography.dart';
import '../../widgets/train/eye_target_overlay.dart';

/// 60-second seduction LESSON.
///
/// Different intent than the charisma TEST:
///   * The test grades you on hold-the-gaze-and-don't-flinch.
///   * The lesson TEACHES five classic seductive moves and grades the
///     execution of each one — head-down-eyes-up, slow blink, side glance,
///     half smile, the full flow.
///
/// Same UI scaffold as CharismaTestScreen but the engine is different and
/// the gate copy frames it as a LESSON, not a TEST. The result card reuses
/// the cinematic ResultRevealScreen — its dimension grid renders whatever
/// phase keys the engine produces.
class SeductionLessonScreen extends StatefulWidget {
  const SeductionLessonScreen({super.key});

  @override
  State<SeductionLessonScreen> createState() => _SeductionLessonScreenState();
}

class _SeductionLessonScreenState extends State<SeductionLessonScreen>
    with TickerProviderStateMixin {
  CameraController? _camera;
  bool _cameraReady = false;
  bool _cameraError = false;

  final FaceDetectorService _detector = FaceDetectorService();
  final VoiceCoach _voice = VoiceCoach();
  late final SeductionLessonEngine _engine = SeductionLessonEngine(voice: _voice);

  bool _processing = false;
  FaceMetrics? _metrics;
  TestFrame _frame = TestFrame.idle();

  _Stage _stage = _Stage.gate;
  int _countdown = 0;
  Timer? _countdownTimer;

  Uint8List? _heroSnapshot;
  double? _heroEyeY;
  bool _snapshotTaken = false;

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
          debugPrint('[seduction] startImageStream failed: $e');
        }
      });
    } catch (e) {
      debugPrint('[seduction] camera init failed: $e');
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

      // Snapshot during phase 1 (LOOK UP) when the head is tilted right
      // and eyes are aimed up — that's the most striking eye-strip frame.
      if (!_snapshotTaken &&
          _frame.phaseId == TestPhaseId.lookUp &&
          _frame.locked &&
          _frame.phaseProgress > 0.45) {
        _captureHero();
      }
    } catch (e) {
      debugPrint('[seduction] frame error: $e');
    } finally {
      _processing = false;
    }
  }

  Future<void> _captureHero() async {
    if (_snapshotTaken) return;
    _snapshotTaken = true;
    try {
      final cam = _camera;
      if (cam == null || !cam.value.isStreamingImages) return;
      final m = _metrics;
      if (m?.leftEyePos != null && m?.rightEyePos != null) {
        _heroEyeY = (m!.leftEyePos!.dy + m.rightEyePos!.dy) / 2;
      }
      await cam.stopImageStream();
      final shot = await cam.takePicture();
      _heroSnapshot = await shot.readAsBytes();
      await cam.startImageStream(_onFrame);
    } catch (e) {
      debugPrint('[seduction] snapshot failed: $e');
    }
  }

  void _onTick(Duration _) {
    if (_stage != _Stage.running) return;
    final frame = _engine.tick(_metrics);
    if (!mounted) return;
    setState(() => _frame = frame);
    if (frame.complete) _finish();
  }

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
        _begin();
      }
    });
  }

  void _begin() {
    HapticFeedback.heavyImpact();
    _detector.startCalibration(duration: const Duration(milliseconds: 2200));
    _engine.start();
    setState(() => _stage = _Stage.running);
    _ticker.start();
  }

  Future<void> _finish() async {
    _ticker.stop();
    final result = _engine.buildResult();

    if (_heroSnapshot == null) {
      try {
        final cam = _camera;
        if (cam != null && cam.value.isStreamingImages) {
          await cam.stopImageStream();
          final shot = await cam.takePicture();
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
      'result':         result,
      'photoBytes':     _heroSnapshot,
      'eyeY':           _heroEyeY,
      'engineName':     _detector.engineName,
      'hasIris':        _detector.hasIris,
      'isFreeTraining': true, // routes RETAKE → /train
      'isSeduction':    true,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_cameraReady && _camera != null) _CameraLayer(controller: _camera!),
          const _Vignette(),

          if (_stage == _Stage.running)
            EyeTargetOverlay(
              center:    _frame.target,
              locked:    _frame.locked,
              intensity: _frame.intensity,
              hidden:    _frame.hidden,
            ),

          // Top progress strip
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: _stage == _Stage.running
                    ? _SeductionProgressStrip(frame: _frame)
                    : const SizedBox.shrink(),
              ),
            ),
          ),

          // Caption
          if (_stage == _Stage.running) _CaptionLayer(frame: _frame),

          if (_stage == _Stage.gate) _LessonGate(onStart: _startCountdown),
          if (_stage == _Stage.countdown) _CountdownOverlay(value: _countdown),
          if (_cameraError) const _CameraError(),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Camera layer + vignette (shared with charisma test, copied here for
//  easy customisation later without a coupling)
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
//  Pre-lesson gate
// ──────────────────────────────────────────────────────────────────────────

class _LessonGate extends StatelessWidget {
  final VoidCallback onStart;
  const _LessonGate({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.78),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('IMHIM',
                style: AppTypography.h1.copyWith(
                  fontSize: 22, letterSpacing: 6,
                  fontWeight: FontWeight.w900,
                )).animate().fadeIn(duration: 480.ms),
              const SizedBox(height: 4),
              Text('SEDUCTION · LESSON 01',
                style: AppTypography.label.copyWith(
                  color: AppColors.accent,
                  fontSize: 11, letterSpacing: 3.5,
                  fontWeight: FontWeight.w800,
                )).animate().fadeIn(delay: 120.ms, duration: 400.ms),

              const SizedBox(height: 50),

              Text('FIVE MOVES.',
                style: AppTypography.display.copyWith(
                  fontSize: 56, height: 1.0, letterSpacing: -1.5,
                  fontStyle: FontStyle.italic,
                  color: AppColors.accent,
                  fontWeight: FontWeight.w900,
                )).animate().fadeIn(delay: 220.ms, duration: 500.ms),
              const SizedBox(height: 6),
              Text('SIXTY SECONDS.',
                style: AppTypography.display.copyWith(
                  fontSize: 56, height: 1.0, letterSpacing: -1.5,
                  fontStyle: FontStyle.italic,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w900,
                )).animate().fadeIn(delay: 320.ms, duration: 500.ms),
              const SizedBox(height: 6),
              Text('ONE LESSON.',
                style: AppTypography.display.copyWith(
                  fontSize: 56, height: 1.0, letterSpacing: -1.5,
                  fontStyle: FontStyle.italic,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w900,
                )).animate().fadeIn(delay: 420.ms, duration: 500.ms),

              const SizedBox(height: 30),

              Container(width: 44, height: 1,
                color: AppColors.accent.withValues(alpha: 0.6))
                .animate().fadeIn(delay: 540.ms, duration: 400.ms),

              const SizedBox(height: 22),

              // Quick preview of the 5 moves so the user knows what's coming.
              const _MoveList(),

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
                  child: const Text('BEGIN THE LESSON',
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

class _MoveList extends StatelessWidget {
  const _MoveList();

  static const _moves = [
    ('1', 'THE LOOK UP',     'chin down · eyes up'),
    ('2', 'THE SLOW BLINK',  'gaze held · close · open'),
    ('3', 'THE SIDE GLANCE', 'away · slow · return'),
    ('4', 'THE HALF SMILE',  'half · uneven · held'),
    ('5', 'THE FLOW',        'all of it · in one ribbon'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < _moves.length; i++) ...[
          _MoveRow(
            number: _moves[i].$1,
            title: _moves[i].$2,
            subtitle: _moves[i].$3,
            delay: Duration(milliseconds: 600 + i * 80),
          ),
          if (i < _moves.length - 1) const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _MoveRow extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;
  final Duration delay;
  const _MoveRow({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return Animate(
      delay: delay,
      effects: [
        FadeEffect(duration: 360.ms),
        SlideEffect(
          begin: const Offset(-0.04, 0), end: Offset.zero,
          duration: 360.ms, curve: Curves.easeOut),
      ],
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(number,
              style: AppTypography.display.copyWith(
                color: AppColors.accent,
                fontSize: 16, fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic, height: 1,
              )),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(title,
                  style: AppTypography.label.copyWith(
                    color: Colors.white,
                    fontSize: 12.5, letterSpacing: 1.6,
                    fontWeight: FontWeight.w900,
                  )),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('· $subtitle',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 11.5, letterSpacing: 0.2,
                    ),
                    overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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

class _SeductionProgressStrip extends StatelessWidget {
  final TestFrame frame;
  const _SeductionProgressStrip({required this.frame});

  static const _phases = [
    TestPhaseId.lookUp,
    TestPhaseId.slowBlink,
    TestPhaseId.sideGlance,
    TestPhaseId.knowingSmile,
    TestPhaseId.theFlow,
  ];

  @override
  Widget build(BuildContext context) {
    final activeIdx = _phases.indexOf(frame.phaseId ?? TestPhaseId.lookUp);
    return Row(
      children: [
        for (int i = 0; i < _phases.length; i++) ...[
          Expanded(child: _PhaseSegment(
            isPast:    activeIdx > i,
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
            Text('The lesson needs your front camera. Grant access in Settings.',
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
