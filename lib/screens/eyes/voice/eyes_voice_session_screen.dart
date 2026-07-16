import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../models/face_metrics.dart';
import '../../../models/presence/presence_lesson.dart';
import '../../../models/presence/presence_syllabus.dart';
import '../../../services/audio_session.dart';
import '../../../services/auralay_api.dart';
import '../../../services/face_detector_service.dart';
import '../../../services/presence/presence_api.dart';
import '../../../services/presence/presence_progress_store.dart';
import '../../../theme/auralay_app_colors.dart';
import '../../../theme/auralay_app_typography.dart';
import '../../../widgets/debug_panel.dart';
import '../../../widgets/eyes/auralay_face_overlay_painter.dart';
import '../../../widgets/eyes/fixation_dots.dart';
import '../../../widgets/presence/presence_share_card.dart';
import '../../../widgets/safe_close_button.dart';

/// PRESENCE — Curriculum 2 session screen.
///
/// Same six-beat ritual as The Gaze: STORY → DEMO → INSTRUCT →
/// COUNTDOWN → DRILL → CORRECTION → SCORE. The drill phase records
/// the apprentice delivering ONE target line while the camera tracks
/// his gaze in parallel. On stop:
///
///   - Frontend computes the two local dimensions: eye contact
///     (% of drill frames with eyeContactScore > 0.5) and tension
///     (avg headStability across the drill window).
///   - Audio + lesson context POST to /v1/presence/score. Backend
///     transcribes via Whisper, computes WPM deterministically,
///     scores voiceAuthority + confidence + warmth via GPT, and
///     returns the four voice-side dimensions + Lucien's one-line
///     fatal-flaw stamp.
///   - The composite charisma score is computed locally from all six
///     dims using the lesson's per-dimension weights.
///   - PresenceShareCard takes over with the seven dimensions, the
///     "IMPOSSIBLE TO IGNORE" badge family, the transcript, the
///     fatal-flaw stamp, the weekly-improvement chip.
class EyesVoiceSessionScreen extends StatefulWidget {
  /// Accepted as a [Lesson] or as a [PresenceLesson]; if a generic
  /// rhetoric Lesson is passed (the path the Eyes tab landing took
  /// before we wired in the dedicated Presence syllabus), we
  /// resolve to PresenceSyllabus[0] as a safe fallback.
  final PresenceLesson lesson;
  const EyesVoiceSessionScreen({super.key, required this.lesson});

  /// Convenience constructor for legacy callers that still pass a
  /// generic rhetoric [Lesson] instance — resolves to the matching
  /// Presence lesson by lessonId where possible, else the first.
  factory EyesVoiceSessionScreen.fromLegacy(dynamic legacyLesson) {
    PresenceLesson resolved;
    try {
      final id = (legacyLesson as dynamic).id as String?;
      if (id != null) {
        resolved = PresenceSyllabus.all.firstWhere(
          (l) => l.id == id,
          orElse: () => PresenceSyllabus.all.first,
        );
      } else {
        resolved = PresenceSyllabus.all.first;
      }
    } catch (_) {
      resolved = PresenceSyllabus.all.first;
    }
    return EyesVoiceSessionScreen(lesson: resolved);
  }

  @override
  State<EyesVoiceSessionScreen> createState() =>
      _EyesVoiceSessionScreenState();
}

enum _Phase {
  warmup,
  story,
  demo,
  instruct,
  countdown,
  drillReady,    // armed, awaiting tap-to-record
  recording,
  scoring,
  correction,
  score,
  done,
  error,
}

class _EyesVoiceSessionScreenState extends State<EyesVoiceSessionScreen>
    with SingleTickerProviderStateMixin {
  // ─── Camera + detection ──────────────────────────────────────────
  CameraController? _camera;
  bool   _cameraReady = false;
  String? _cameraError;
  final FaceDetectorService _detector = FaceDetectorService();
  bool _processing = false;
  FaceMetrics _metrics = FaceMetrics.empty;
  late final AnimationController _loopAnim;

  // ─── Voice playback + mic ────────────────────────────────────────
  final AudioPlayer   _player   = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();
  String? _activeRecordingPath;
  DateTime? _recordingStarted;

  // ─── State ───────────────────────────────────────────────────────
  _Phase _phase = _Phase.warmup;
  bool   _disposed = false;
  bool   _paused = false;
  Completer<void>? _pauseLatch;
  String _errorMsg = '';
  String _currentChunk = '';
  // Which rep we're on: 0 = practice take, 1 = graded take. Lucien's
  // correction sends the apprentice back in for the graded rep instead
  // of ending on the first take.
  int _rep = 0;
  int    _countdownValue = 3;
  Timer? _countdownTimer;

  // Drill aggregates (gaze side).
  final List<FaceMetrics> _samples = [];
  int  _drillBlinks   = 0;
  int  _sessionBlinks = 0;
  bool _wasBlinking   = false;
  DateTime? _lastBlinkAt;

  // Result + history.
  PresenceResult? _result;
  int? _previousBest;
  int? _weeklyDelta;

  // ─── Debug log ───────────────────────────────────────────────────
  final List<DebugEvent> _events = [];
  void _log(String level, String tag, String message) {
    final e = DebugEvent(
      ts: DateTime.now(), level: level, tag: tag, message: message,
    );
    _events.add(e);
    if (_events.length > 60) _events.removeRange(0, _events.length - 60);
    // ignore: avoid_print
    print('[presence] ${e.level.toUpperCase()} ${e.tag} ${e.message}');
  }

  // ─── Lifecycle ───────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loopAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    // Crucial — without this, iOS keeps audioplayers in playback-only
    // mode and the record plugin silently fails when the apprentice
    // taps the mic. That's the root cause of the "Recording too
    // short — try again" bug across every screen that does both.
    // ignore: discarded_futures
    AudioSession.configureForPlayAndRecord();
    // Keep the screen awake through the whole session.
    // ignore: discarded_futures
    WakelockPlus.enable();
    _detector.init();
    _initCamera();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _disposed = true;
    // ignore: discarded_futures
    WakelockPlus.disable();
    _countdownTimer?.cancel();
    _loopAnim.dispose();
    _player.dispose();
    // ignore: discarded_futures
    _recorder.dispose();
    _camera?.stopImageStream().catchError((_) {});
    _camera?.dispose();
    _detector.dispose();
    super.dispose();
  }

  void _closeScreen() {
    if (!mounted) return;
    // Pop FIRST — never let audio/recorder teardown block the exit.
    safePop(context);
    _disposed = true;
    _countdownTimer?.cancel();
    // ignore: discarded_futures
    _player.stop().catchError((_) {});
    // ignore: discarded_futures
    _recorder.stop().catchError((_) {});
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
        ResolutionPreset.low,
        enableAudio: false,  // mic owned by record plugin
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await _camera!.initialize();
      if (!mounted) return;
      setState(() => _cameraReady = true);
      _log('ok', 'CAM', 'initialised');
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _camera == null) return;
        try {
          await _camera!.startImageStream(_onFrame);
        } catch (e) {
          _log('error', 'CAM', 'startImageStream failed: $e');
        }
      });
    } catch (e) {
      _log('error', 'CAM', 'init failed: $e');
      if (!mounted) return;
      setState(() {
        _cameraError = e.toString();
        _phase = _Phase.error;
        _errorMsg = 'Camera unavailable: $e';
      });
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_processing || _disposed) return;
    _processing = true;
    try {
      final m = await _detector.process(
        image,
        _camera?.description.sensorOrientation ?? 0,
        isFrontCam: true,
      );
      if (!mounted || m == null) {
        _processing = false;
        return;
      }
      final isClosed = _isBlinking(m);
      final now = DateTime.now();
      if (isClosed && !_wasBlinking) {
        final ok = _lastBlinkAt == null ||
            now.difference(_lastBlinkAt!).inMilliseconds > 200;
        if (ok) {
          _sessionBlinks++;
          if (_phase == _Phase.recording) _drillBlinks++;
          _lastBlinkAt = now;
        }
      }
      _wasBlinking = isClosed;
      if (_phase == _Phase.recording) _samples.add(m);
      setState(() => _metrics = m);
    } catch (_) {} finally {
      _processing = false;
    }
  }

  bool _isBlinking(FaceMetrics m) {
    final l = m.leftEyeAperture;
    final r = m.rightEyeAperture;
    if (l == null && r == null) return false;
    return (l != null && l < 0.22) || (r != null && r < 0.22);
  }

  // ─── Pause ───────────────────────────────────────────────────────

  void _togglePause() {
    if (_paused) {
      _resume();
    } else {
      _pause();
    }
  }

  void _pause() {
    if (_paused || _disposed) return;
    HapticFeedback.lightImpact();
    setState(() {
      _paused = true;
      _pauseLatch = Completer<void>();
    });
    // ignore: discarded_futures
    _player.pause().catchError((_) {});
    _countdownTimer?.cancel();
    _log('info', 'PAUSE', 'paused');
  }

  void _resume() {
    if (!_paused || _disposed) return;
    HapticFeedback.lightImpact();
    final latch = _pauseLatch;
    setState(() {
      _paused = false;
      _pauseLatch = null;
    });
    // ignore: discarded_futures
    _player.resume().catchError((_) {});
    if (latch != null && !latch.isCompleted) latch.complete();
    _log('info', 'PAUSE', 'resumed');
  }

  Future<void> _checkPauseGate() async {
    if (_pauseLatch != null && !_pauseLatch!.isCompleted) {
      await _pauseLatch!.future;
    }
  }

  // ─── Flow ────────────────────────────────────────────────────────

  Future<void> _run() async {
    if (_disposed) return;
    _rep = 0;
    _log('info', 'SESSION', 'lesson=${widget.lesson.id}');
    await _narrate(_Phase.story,    widget.lesson.story);
    if (_disposed || !mounted) return;
    await _phaseBreak();
    await _narrate(_Phase.demo,     widget.lesson.demo);
    if (_disposed || !mounted) return;
    await _phaseBreak();
    await _narrate(_Phase.instruct, widget.lesson.instruct);
    if (_disposed || !mounted) return;
    await _runCountdown();
    if (_disposed || !mounted) return;
    // Armed — wait for the apprentice to tap mic.
    setState(() => _phase = _Phase.drillReady);
  }

  Future<void> _narrate(_Phase phase, List<String> chunks) async {
    if (_disposed) return;
    setState(() {
      _phase = phase;
      _currentChunk = '';
    });
    for (final chunk in chunks) {
      if (_disposed || !mounted) return;
      await _checkPauseGate();
      if (_disposed || !mounted) return;
      setState(() => _currentChunk = chunk);
      await _speak(chunk);
      if (_disposed || !mounted) return;
      await Future.delayed(Duration(milliseconds: widget.lesson.beatPauseMs));
    }
  }

  Future<void> _phaseBreak() async {
    if (_disposed) return;
    await _checkPauseGate();
    setState(() => _currentChunk = '');
    await Future.delayed(const Duration(milliseconds: 700));
  }

  Future<void> _speak(String text) async {
    if (_disposed) return;
    try {
      final bytes =
          await AuralayApi.diabloSpeak(text: text, mode: 'lucien');
      if (_disposed || !mounted) return;
      if (bytes != null && bytes.isNotEmpty) {
        await _player.play(BytesSource(bytes, mimeType: 'audio/mpeg'));
        try {
          await _player.onPlayerComplete.first
              .timeout(const Duration(seconds: 60));
        } catch (_) {}
      } else {
        await Future.delayed(const Duration(milliseconds: 1200));
      }
    } catch (e) {
      _log('error', 'TTS', e.toString());
    }
  }

  Future<void> _runCountdown() async {
    if (_disposed) return;
    setState(() {
      _phase = _Phase.countdown;
      _countdownValue = 3;
      _currentChunk = '';
    });
    final completer = Completer<void>();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _disposed) {
        t.cancel();
        if (!completer.isCompleted) completer.complete();
        return;
      }
      if (_paused) return;
      setState(() => _countdownValue--);
      if (_countdownValue <= 0) {
        t.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });
    await completer.future;
  }

  // ─── Mic + recording ─────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (_disposed || _phase != _Phase.drillReady) return;
    try {
      if (!await _recorder.hasPermission()) {
        _failWith(const _PEError('Microphone permission denied.'));
        return;
      }
      await AudioSession.prepareForRecording(_player);
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/presence_${DateTime.now().millisecondsSinceEpoch}.m4a';
      const cfg = RecordConfig(
        encoder:     AudioEncoder.aacLc,
        sampleRate:  44100,
        bitRate:     128000,
        numChannels: 1,
      );
      // v307 — !pri recover-and-retry.
      try {
        await _recorder.start(cfg, path: path);
      } catch (err) {
        if (!AudioSession.isInsufficientPriorityError(err)) rethrow;
        _log('warn', 'MIC', '!pri detected — recovering');
        await AudioSession.recoverFromPriorityConflict();
        try {
          await _recorder.start(cfg, path: path);
          _log('ok', 'MIC', '!pri recovery succeeded');
        } catch (err2) {
          _log('error', 'MIC', '!pri recovery FAILED: $err2');
          _failWith(_PEError(AudioSession.priorityConflictMessage));
          return;
        }
      }
      _activeRecordingPath = path;
      _recordingStarted   = DateTime.now();
      _samples.clear();
      _drillBlinks = 0;
      HapticFeedback.mediumImpact();
      _log('ok', 'MIC', 'recording → $path');
      setState(() => _phase = _Phase.recording);
    } catch (e) {
      _log('error', 'MIC', e.toString());
      _failWith(e);
    }
  }

  Future<void> _stopAndScore() async {
    if (_disposed || _phase != _Phase.recording) return;
    String? finalPath;
    try {
      finalPath = await _recorder.stop();
      finalPath ??= _activeRecordingPath;
      HapticFeedback.lightImpact();
    } catch (e) {
      _log('error', 'MIC', 'stop failed: $e');
    }
    if (finalPath == null) {
      _failWith(const _PEError('Recording produced no audio.'));
      return;
    }
    // Give the recorder a beat to flush — the file size check
    // sometimes fires before m4a finishes writing its trailer.
    await Future.delayed(const Duration(milliseconds: 200));
    final file = File(finalPath);
    final exists = await file.exists();
    final size   = exists ? await file.length() : 0;
    _log('info', 'MIC', 'stopped · file=${size}B exists=$exists');
    if (!exists || size < 200) {
      _failWith(const _PEError(
        'No audio captured — check mic permission + that nothing '
        'else is using the microphone.',
      ));
      return;
    }

    final audioMs = _recordingStarted == null
        ? widget.lesson.drillSeconds * 1000
        : DateTime.now().difference(_recordingStarted!).inMilliseconds;

    setState(() => _phase = _Phase.scoring);
    PresenceScoreResponse? backendScore;
    try {
      _log('info', 'API', 'POST /v1/presence/score audioMs=$audioMs');
      backendScore = await PresenceApi.score(
        audioFile:      file,
        audioMs:        audioMs,
        lessonId:       widget.lesson.id,
        targetLine:     widget.lesson.targetLine,
        deliveryCue:    widget.lesson.deliveryCue,
        targetWpmLow:   widget.lesson.targetWpmLow,
        targetWpmHigh:  widget.lesson.targetWpmHigh,
        warmthExpected: widget.lesson.warmthExpected,
      );
    } catch (e) {
      _log('error', 'API', e.toString());
      _failWith(e);
      try { await file.delete(); } catch (_) {}
      return;
    }
    try { await file.delete(); } catch (_) {}
    if (_disposed || !mounted) return;

    // Local dimensions.
    final eyeContact = _samples.isEmpty
        ? 0.0
        : _samples.where((m) => m.eyeContactScore > 0.5).length /
              _samples.length;
    final tension = _samples.isEmpty
        ? 0.0
        : _samples.map((m) => m.headStability).reduce((a, b) => a + b) /
              _samples.length;

    // Composite charisma.
    final w = widget.lesson.weights;
    double composite = 0;
    composite += (w[PresenceDimension.voiceAuthority] ?? 0) * backendScore.voiceAuthority;
    composite += (w[PresenceDimension.pace]           ?? 0) * backendScore.pace;
    composite += (w[PresenceDimension.confidence]     ?? 0) * backendScore.confidence;
    composite += (w[PresenceDimension.eyeContact]     ?? 0) * eyeContact;
    composite += (w[PresenceDimension.warmth]         ?? 0) * backendScore.warmth;
    composite += (w[PresenceDimension.tension]        ?? 0) * tension;
    final weightSum = (w[PresenceDimension.voiceAuthority] ?? 0) +
        (w[PresenceDimension.pace]       ?? 0) +
        (w[PresenceDimension.confidence] ?? 0) +
        (w[PresenceDimension.eyeContact] ?? 0) +
        (w[PresenceDimension.warmth]     ?? 0) +
        (w[PresenceDimension.tension]    ?? 0);
    if (weightSum > 0 && (weightSum - 1.0).abs() > 0.02) {
      composite = composite / weightSum;
    }
    final charisma = composite.clamp(0.0, 1.0);

    final result = PresenceResult(
      lessonId:     widget.lesson.id,
      lessonNumber: widget.lesson.number,
      lessonName:   widget.lesson.name,
      dims: {
        PresenceDimension.voiceAuthority: backendScore.voiceAuthority,
        PresenceDimension.pace:           backendScore.pace,
        PresenceDimension.confidence:     backendScore.confidence,
        PresenceDimension.eyeContact:     eyeContact,
        PresenceDimension.warmth:         backendScore.warmth,
        PresenceDimension.tension:        tension,
        PresenceDimension.charisma:       charisma,
      },
      transcript:   backendScore.transcript,
      fatalFlaw:    backendScore.fatalFlaw,
      wpm:          backendScore.wpm,
      timestampMs:  DateTime.now().millisecondsSinceEpoch,
    );

    if (_disposed || !mounted) return;
    setState(() {
      _result = result;
      _phase  = _Phase.correction;
    });

    // TWO reps, then it ENDS. Rep 1 = practice: Lucien's correction
    // ("Again, this time…") then back in. Rep 2 = graded: a verdict
    // ("good" / "not quite"), NOT another "again" — so it never feels
    // like it wants a third take.
    if (_rep == 0) {
      await _narrate(_Phase.correction, widget.lesson.correction);
      if (_disposed || !mounted) return;
      _rep = 1;
      await _runCountdown();
      if (_disposed || !mounted) return;
      setState(() => _phase = _Phase.drillReady);
      return;
    }

    // Graded rep — Lucien's real verdict on the voice + gaze he just
    // judged, then the card.
    final verdict = _verdictLine(result.charisma);
    setState(() => _currentChunk = verdict);
    await _speak(verdict);
    if (_disposed || !mounted) return;
    _previousBest = await PresenceProgressStore.record(result);
    _weeklyDelta  = await PresenceProgressStore.weeklyImprovement();
    if (_disposed || !mounted) return;
    setState(() => _phase = _Phase.score);
  }

  /// Lucien's spoken verdict at the end — confirms he actually judged
  /// the take. He DID: voice authority/pace/confidence/warmth from the
  /// backend, eye-contact + tension from MediaPipe.
  String _verdictLine(int charisma) {
    if (charisma >= 66) {
      return 'Good. That landed. She felt every word.';
    }
    if (charisma >= 50) {
      return 'Closer. The weight is coming. Not there yet.';
    }
    return 'Not quite. She heard the nerves before the words.';
  }

  // ─── Buttons on the score card ───────────────────────────────────

  void _again() {
    if (_disposed) return;
    setState(() {
      _phase           = _Phase.warmup;
      _currentChunk    = '';
      _samples.clear();
      _drillBlinks     = 0;
      _result          = null;
      _previousBest    = null;
      _weeklyDelta     = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  void _nextLesson() {
    // Close reliably; the Eyes tab reloads and surfaces the next move.
    _closeScreen();
  }

  void _failWith(Object e) {
    if (!mounted || _disposed) return;
    setState(() {
      _phase = _Phase.error;
      _errorMsg = e.toString();
    });
    _log('error', 'API', e.toString());
  }

  String _clip(String s, int n) => s.length > n ? '${s.substring(0, n)}…' : s;

  // ─── UI ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_phase == _Phase.score && _result != null) {
      return PresenceShareCard(
        result:       _result!,
        previousBest: _previousBest,
        weeklyDelta:  _weeklyDelta,
        onAgain:      _again,
        onNext:       _nextLesson,
        onClose:      _closeScreen,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: Stack(
          children: [
            if (_cameraReady && _camera != null)
              Positioned.fill(
                child: _CameraLayer(
                  controller: _camera!,
                  overlay: AnimatedBuilder(
                    animation: _loopAnim,
                    builder: (_, __) => LayoutBuilder(
                      builder: (_, c) => CustomPaint(
                        size: Size(c.maxWidth, c.maxHeight),
                        painter: AuralayFaceOverlayPainter(
                          metrics:  _metrics,
                          pulse:    _loopAnim.value,
                          isLocked: _metrics.isGoodEyeContact,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            const Positioned.fill(child: _Vignette()),

            // Fixation dots during the drill phases so the apprentice
            // has an external gaze target while delivering the line.
            if (_phase == _Phase.countdown ||
                _phase == _Phase.drillReady ||
                _phase == _Phase.recording)
              Positioned.fill(
                child: FixationDots(isLocked: _metrics.isGoodEyeContact),
              ),

            // Top chrome.
            Positioned(
              top: 6, left: 8, right: 8,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Text('PRESENCE',
                      style: AppTypography.label.copyWith(
                        color: AppColors.accent,
                        fontSize: 11,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w900,
                      )),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surface1,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                          color: AppColors.divider, width: 0.6),
                    ),
                    child: Text(
                      'LESSON ${widget.lesson.number.toString().padLeft(2, "0")}',
                      style: AppTypography.label.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 9,
                        letterSpacing: 1.8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Spacer(),
                  _BlinkCounter(blinks: _sessionBlinks),
                  const SizedBox(width: 4),
                  _IconButton(
                    icon: _paused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    onTap: _togglePause,
                  ),
                  _IconButton(icon: Icons.close_rounded, onTap: _closeScreen),
                ],
              ),
            ),

            // Lesson name + one-line.
            Positioned(
              top: 56, left: 20, right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.lesson.name,
                      style: AppTypography.display.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 30,
                        letterSpacing: -1,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                      )),
                  const SizedBox(height: 6),
                  Text(widget.lesson.oneLine,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.accent,
                        fontSize: 13,
                        height: 1.4,
                        fontStyle: FontStyle.italic,
                      )),
                ],
              ),
            ),

            // Narration cards (story / demo / instruct / correction)
            // anchor LOW — just above the mic + status — so the
            // apprentice's eyes stay on the camera, not pulled to
            // mid-screen to read Lucien's text. Target-line card and
            // countdown stay centred — those ARE the focal moments.
            if (_phase == _Phase.story ||
                _phase == _Phase.demo ||
                _phase == _Phase.instruct ||
                _phase == _Phase.correction)
              Positioned(
                left: 20, right: 20, bottom: 200,
                child: _NarrationCard(text: _currentChunk),
              ),
            if (_phase == _Phase.warmup ||
                _phase == _Phase.countdown ||
                _phase == _Phase.drillReady ||
                _phase == _Phase.recording ||
                _phase == _Phase.scoring)
              Positioned(
                top: 140, bottom: 200, left: 20, right: 20,
                child: Center(child: _centreContent()),
              ),

            // Bottom — mic / status.
            Positioned(
              left: 0, right: 0, bottom: 24,
              child: _BottomBar(
                phase:        _phase,
                statusLabel:  _statusLabel(),
                onMicPress:   _onMicPress,
                onErrorClose: _closeScreen,
                errorMsg:     _errorMsg,
              ),
            ),

            // Paused overlay.
            if (_paused)
              Positioned.fill(
                child: Material(
                  color: Colors.black.withValues(alpha: 0.72),
                  child: InkWell(
                    onTap: _resume,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.pause_rounded,
                              color: AppColors.accent, size: 64),
                          const SizedBox(height: 8),
                          Text('PAUSED',
                              style: AppTypography.label.copyWith(
                                color: AppColors.accent,
                                fontSize: 14,
                                letterSpacing: 4,
                                fontWeight: FontWeight.w900,
                              )),
                          const SizedBox(height: 18),
                          Text('TAP TO RESUME',
                              style: AppTypography.label.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                letterSpacing: 3,
                                fontWeight: FontWeight.w900,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Debug.
            Positioned(
              left: 0, bottom: 0,
              child: DebugPanel(
                kvs: {
                  'lesson':  '${widget.lesson.number} · ${widget.lesson.name}',
                  'phase':   _phase.name,
                  'paused':  _paused ? 'yes' : 'no',
                  'cam':     _cameraReady ? 'ready' : 'init…',
                  'samples': '${_samples.length}',
                  'blinks':  '$_sessionBlinks (drill:$_drillBlinks)',
                  'contact': _metrics.eyeContactScore.toStringAsFixed(2),
                  'still':   _metrics.headStability.toStringAsFixed(2),
                  'err':     _errorMsg.isEmpty
                      ? '—'
                      : _clip(_errorMsg, 60),
                },
                events: _events,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _centreContent() {
    switch (_phase) {
      case _Phase.warmup:
        return const _ReadyPlaceholder();
      case _Phase.story:
      case _Phase.demo:
      case _Phase.instruct:
      case _Phase.correction:
        return _NarrationCard(text: _currentChunk);
      case _Phase.countdown:
        return _Countdown(value: _countdownValue);
      case _Phase.drillReady:
      case _Phase.recording:
        return _TargetLineCard(
          line:        widget.lesson.targetLine,
          cue:         widget.lesson.deliveryCue,
          isRecording: _phase == _Phase.recording,
        );
      case _Phase.scoring:
        return const _ScoringIndicator();
      case _Phase.score:
      case _Phase.done:
      case _Phase.error:
        return const SizedBox.shrink();
    }
  }

  void _onMicPress() {
    if (_phase == _Phase.drillReady) {
      // ignore: discarded_futures
      _startRecording();
    } else if (_phase == _Phase.recording) {
      // ignore: discarded_futures
      _stopAndScore();
    }
  }

  String _statusLabel() {
    if (_phase == _Phase.error) return 'LINE DROPPED';
    switch (_phase) {
      case _Phase.warmup:      return 'LUCILE IS APPROACHING';
      case _Phase.story:       return 'LUCILE SETS THE TONE';
      case _Phase.demo:        return 'LISTEN';
      case _Phase.instruct:    return 'GET READY';
      case _Phase.countdown:   return 'BEGIN ON ONE';
      case _Phase.drillReady:  return 'TAP TO DELIVER THE LINE';
      case _Phase.recording:   return 'RECORDING · TAP TO SEND';
      case _Phase.scoring:     return 'LUCILE IS LISTENING';
      case _Phase.correction:  return 'LUCILE TEACHES';
      case _Phase.score:       return 'SESSION COMPLETE';
      default:                 return '';
    }
  }
}

class _PEError implements Exception {
  final String message;
  const _PEError(this.message);
  @override
  String toString() => message;
}

// ─── Pieces ───────────────────────────────────────────────────────

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
        child: Center(child: CameraPreview(controller, child: overlay)),
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

class _IconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () { HapticFeedback.lightImpact(); onTap(); },
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44, height: 44,
          child: Center(
            child: Icon(icon, color: AppColors.textPrimary, size: 22),
          ),
        ),
      ),
    );
  }
}

class _BlinkCounter extends StatelessWidget {
  final int blinks;
  const _BlinkCounter({required this.blinks});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.accentBorder, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.remove_red_eye_outlined,
              color: AppColors.accent, size: 12),
          const SizedBox(width: 5),
          Text('$blinks',
              style: AppTypography.label.copyWith(
                color: AppColors.accent,
                fontSize: 10.5,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w900,
              )),
        ],
      ),
    );
  }
}

class _NarrationCard extends StatelessWidget {
  final String text;
  const _NarrationCard({required this.text});
  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    // No card chrome — just the words over the camera. Shadows keep
    // it legible against a bright or busy frame.
    return Container(
      key: ValueKey(text),
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      child: Text('"$text"',
          textAlign: TextAlign.center,
          style: AppTypography.h1Italic.copyWith(
            color: Colors.white,
            fontSize: 20,
            height: 1.5,
            fontStyle: FontStyle.italic,
            shadows: const [
              Shadow(color: Colors.black, blurRadius: 12),
              Shadow(color: Colors.black, blurRadius: 24),
            ],
          )),
    ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.04, end: 0);
  }
}

class _ReadyPlaceholder extends StatelessWidget {
  const _ReadyPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Text('…',
        style: AppTypography.display.copyWith(
          color: AppColors.textTertiary,
          fontSize: 28,
          fontWeight: FontWeight.w900,
        ));
  }
}

class _Countdown extends StatelessWidget {
  final int value;
  const _Countdown({required this.value});
  @override
  Widget build(BuildContext context) {
    if (value <= 0) return const SizedBox.shrink();
    return Text('$value',
        key: ValueKey(value),
        style: AppTypography.display.copyWith(
          color: AppColors.textPrimary,
          fontSize: 140,
          height: 1.0,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w900,
          letterSpacing: -6,
        ))
      .animate(key: ValueKey(value))
      .fadeIn(duration: 200.ms)
      .scale(begin: const Offset(0.7, 0.7), end: const Offset(1, 1),
          duration: 300.ms, curve: Curves.easeOut)
      .then().fadeOut(duration: 200.ms, delay: 500.ms);
  }
}

class _TargetLineCard extends StatelessWidget {
  final String line;
  final String cue;
  final bool   isRecording;
  const _TargetLineCard({
    required this.line,
    required this.cue,
    required this.isRecording,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isRecording ? AppColors.accent : AppColors.accentBorder,
          width: isRecording ? 1.4 : 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentGlow.withValues(
                alpha: isRecording ? 0.42 : 0.20),
            blurRadius: 28, spreadRadius: -4,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isRecording ? 'SAY IT NOW' : 'SAY THIS',
              style: AppTypography.label.copyWith(
                color: AppColors.accent,
                fontSize: 10,
                letterSpacing: 2.8,
                fontWeight: FontWeight.w900,
              )),
          const SizedBox(height: 10),
          Text('"$line"',
              style: AppTypography.h1Italic.copyWith(
                color: Colors.white,
                fontSize: 20,
                height: 1.4,
                fontStyle: FontStyle.italic,
              )),
          const SizedBox(height: 12),
          Container(height: 0.5, color: AppColors.divider),
          const SizedBox(height: 10),
          Text(cue,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.45,
                fontStyle: FontStyle.italic,
              )),
        ],
      ),
    ).animate().fadeIn(duration: 240.ms).slideY(begin: 0.04, end: 0);
  }
}

class _ScoringIndicator extends StatelessWidget {
  const _ScoringIndicator();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Dot(delay: 0),
        const SizedBox(width: 8),
        _Dot(delay: 200),
        const SizedBox(width: 8),
        _Dot(delay: 400),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final int delay;
  const _Dot({required this.delay});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10, height: 10,
      decoration: const BoxDecoration(
        color: AppColors.accent, shape: BoxShape.circle),
    ).animate(onPlay: (c) => c.repeat(reverse: true))
      .fadeIn(delay: delay.ms, duration: 500.ms)
      .then().fadeOut(duration: 500.ms);
  }
}

class _BottomBar extends StatelessWidget {
  final _Phase      phase;
  final String      statusLabel;
  final VoidCallback onMicPress;
  final VoidCallback onErrorClose;
  final String      errorMsg;
  const _BottomBar({
    required this.phase,
    required this.statusLabel,
    required this.onMicPress,
    required this.onErrorClose,
    required this.errorMsg,
  });
  @override
  Widget build(BuildContext context) {
    Widget child;
    if (phase == _Phase.error) {
      child = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.signalRedBorder, width: 0.8),
              ),
              child: Text(errorMsg,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.signalRed,
                    fontSize: 12.5,
                    height: 1.4,
                    fontStyle: FontStyle.italic,
                  )),
            ),
            const SizedBox(height: 12),
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(100),
              child: InkWell(
                onTap: onErrorClose,
                borderRadius: BorderRadius.circular(100),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface3,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: AppColors.divider, width: 0.6),
                  ),
                  child: Text('GO BACK',
                      style: AppTypography.label.copyWith(
                        color: AppColors.accent,
                        fontSize: 11,
                        letterSpacing: 2.4,
                        fontWeight: FontWeight.w900,
                      )),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      child = _MicButton(phase: phase, onPress: onMicPress);
    }
    return Column(
      children: [
        child,
        const SizedBox(height: 14),
        Text(statusLabel,
            style: AppTypography.label.copyWith(
              color: AppColors.accent,
              fontSize: 11,
              letterSpacing: 3,
              fontWeight: FontWeight.w900,
            )),
      ],
    );
  }
}

class _MicButton extends StatelessWidget {
  final _Phase phase;
  final VoidCallback onPress;
  const _MicButton({required this.phase, required this.onPress});
  @override
  Widget build(BuildContext context) {
    final isRecording = phase == _Phase.recording;
    final isReady     = phase == _Phase.drillReady;
    final canTap      = isReady || isRecording;
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: canTap ? () { HapticFeedback.mediumImpact(); onPress(); } : null,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: isRecording ? 118 : 104,
          height: isRecording ? 118 : 104,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: !canTap ? AppColors.surface3 : AppColors.accent,
            boxShadow: !canTap ? [] : [
              BoxShadow(
                color: AppColors.accent.withValues(
                    alpha: isRecording ? 0.55 : 0.30),
                blurRadius: isRecording ? 60 : 36,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Icon(
            isRecording
                ? Icons.stop_rounded
                : (!canTap
                    ? Icons.hourglass_empty_rounded
                    : Icons.mic_rounded),
            color: !canTap ? AppColors.textTertiary : Colors.white,
            size: isRecording ? 48 : 40,
          ),
        ),
      ),
    );
  }
}
