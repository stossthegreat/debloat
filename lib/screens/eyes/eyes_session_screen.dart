import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/face_metrics.dart';
import '../../models/gaze/gaze_lesson.dart';
import '../../models/gaze/gaze_syllabus.dart';
import '../../services/audio_session.dart';
import '../../services/auralay_api.dart';
import '../../services/face_detector_service.dart';
import '../../services/gaze/gaze_progress_store.dart';
import '../../services/gaze/gaze_scorer.dart';
import '../../theme/auralay_app_colors.dart';
import '../../theme/auralay_app_typography.dart';
import '../../widgets/debug_panel.dart';
import '../../widgets/eyes/auralay_face_overlay_painter.dart';
import '../../widgets/eyes/fixation_dots.dart';
import '../../widgets/eyes/gaze_share_card.dart';
import '../../widgets/safe_close_button.dart';

/// THE GAZE — session screen.
///
/// Walks the apprentice through a six-beat ritual:
///
///   1. STORY      — Lucien sets the tone in short chunks, each
///                   played as its own TTS call with a long pause in
///                   between. The chunked-array shape is what gives
///                   him deliberate cadence; a single long string
///                   would race through.
///   2. DEMO       — Lucien demonstrates. Same chunked pattern.
///   3. INSTRUCT   — One-or-two-line handoff. The last beat ends on
///                   "Begin." Then a slow 3-2-1 countdown sits in
///                   front of the camera so the apprentice settles
///                   into the room before the timer starts.
///   4. DRILL      — Timer runs. Per-frame [FaceMetrics] samples
///                   accumulate. Manual blink edge-detection on the
///                   eye aperture signal.
///   5. CORRECTION — Lucien teaches the WHY. Same chunked pattern.
///   6. SCORE      — [GazeShareCard] takes over with the six-dimension
///                   breakdown, the magnetic badge, the weekly delta.
///
/// All audio playback awaits onPlayerComplete before the next beat
/// fires — no cut-offs, no two voices on top of each other. Pause +
/// X buttons are explicit InkWell-backed 44pt tap targets.
class EyesSessionScreen extends StatefulWidget {
  final GazeLesson lesson;
  const EyesSessionScreen({super.key, required this.lesson});

  @override
  State<EyesSessionScreen> createState() => _EyesSessionScreenState();
}

enum _Phase {
  warmup,
  story,
  demo,
  instruct,
  countdown,
  drill,
  scoring,
  correction,
  score,
  done,
  error,
}

class _EyesSessionScreenState extends State<EyesSessionScreen>
    with SingleTickerProviderStateMixin {
  // ─── Camera + detection ───────────────────────────────────────────
  CameraController? _camera;
  bool   _cameraReady = false;
  String? _cameraError;
  final FaceDetectorService _detector = FaceDetectorService();
  bool _processing = false;
  FaceMetrics _metrics = FaceMetrics.empty;
  late final AnimationController _loopAnim;

  // ─── Voice ────────────────────────────────────────────────────────
  final AudioPlayer _player = AudioPlayer();

  // ─── State ────────────────────────────────────────────────────────
  _Phase _phase = _Phase.warmup;
  bool   _disposed = false;
  bool   _paused = false;
  Completer<void>? _pauseLatch;
  String _errorMsg = '';
  String _currentChunk = '';      // Visible chunk text mid-narration.
  int    _countdownValue = 3;     // 3, 2, 1, 0
  int    _drillElapsed = 0;       // seconds
  Timer? _drillTimer;
  Timer? _countdownTimer;

  // Drill aggregates.
  final List<FaceMetrics> _samples = [];
  int _drillBlinks = 0;
  int _sessionBlinks = 0;
  bool _wasBlinking = false;
  /// Last counted blink timestamp — used to debounce jittery aperture
  /// readings. Without this the counter fires dozens of times from
  /// small wobbles around the threshold.
  DateTime? _lastBlinkAt;
  static const int _blinkCooldownMs = 200;

  // Result + history.
  GazeResult? _result;
  int? _previousBest;
  int? _weeklyDelta;
  /// Practice-gated cap on the displayed gaze score. Ramps from 0.40
  /// at session #1 to 1.00 at session #24 so a single perfect rep
  /// can\'t inflate the headline — the apprentice has to drill
  /// through the curriculum to earn the 10. Read from
  /// [GazeProgressStore.progressionCap] before the result lands.
  double _progressionCap = 1.0;

  // ─── Debug log ────────────────────────────────────────────────────
  final List<DebugEvent> _events = [];

  void _log(String level, String tag, String message) {
    final e = DebugEvent(
      ts: DateTime.now(), level: level, tag: tag, message: message,
    );
    _events.add(e);
    if (_events.length > 60) _events.removeRange(0, _events.length - 60);
    // ignore: avoid_print
    print('[gaze] ${e.level.toUpperCase()} ${e.tag} ${e.message}');
  }

  // ─── Lifecycle ────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loopAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    // ignore: discarded_futures
    AudioSession.configureForPlayAndRecord();
    // Keep the screen on for the whole drill — it was dimming/sleeping.
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
    _drillTimer?.cancel();
    _countdownTimer?.cancel();
    _loopAnim.dispose();
    _player.dispose();
    _camera?.stopImageStream().catchError((_) {});
    _camera?.dispose();
    _detector.dispose();
    super.dispose();
  }

  void _closeScreen() {
    if (!mounted) return;
    // Pop FIRST — never let teardown block the exit. A hung/slow
    // _player.stop() used to swallow the close entirely.
    safePop(context);
    _disposed = true;
    _drillTimer?.cancel();
    _countdownTimer?.cancel();
    // ignore: discarded_futures
    _player.stop().catchError((_) {});
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
        enableAudio: false,
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
          _log('ok', 'CAM', 'streaming frames');
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
      // Blink edge-detect with a 200ms cooldown to prevent runaway
      // counting from aperture wobble. The original 0.18 threshold
      // missed real blinks; 0.28 over-counted (89 in a session); 0.22
      // with cooldown is the band that catches actual eyelid drops
      // and rejects detector jitter.
      final isClosed = _isBlinking(m);
      final now = DateTime.now();
      if (isClosed && !_wasBlinking) {
        final ok = _lastBlinkAt == null ||
            now.difference(_lastBlinkAt!).inMilliseconds >
                _blinkCooldownMs;
        if (ok) {
          _sessionBlinks++;
          if (_phase == _Phase.drill) _drillBlinks++;
          _lastBlinkAt = now;
        }
      }
      _wasBlinking = isClosed;
      if (_phase == _Phase.drill) _samples.add(m);
      setState(() => _metrics = m);
    } catch (_) {} finally {
      _processing = false;
    }
  }

  /// True if EITHER eye looks closed. We use the looser threshold of
  /// 0.28 because aperture ratios on real users in 30-60fps streams
  /// often plateau around 0.22-0.28 mid-blink rather than dropping
  /// near 0; the previous 0.18 cut-off was missing legitimate blinks.
  bool _isBlinking(FaceMetrics m) {
    final l = m.leftEyeAperture;
    final r = m.rightEyeAperture;
    if (l == null && r == null) return false;
    // Threshold 0.22 — middle of the band between original 0.18
    // (missed real blinks) and 0.28 (over-counted aperture wobble).
    // Combined with the 200ms cooldown above it gives realistic
    // ~12-20 blinks/min counts.
    final lClosed = l != null && l < 0.22;
    final rClosed = r != null && r < 0.22;
    return lClosed || rClosed;
  }

  // ─── Pause ────────────────────────────────────────────────────────

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
    _drillTimer?.cancel();
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
    if (_phase == _Phase.drill) _resumeDrillTimer();
    if (_phase == _Phase.countdown) _resumeCountdown();
    _log('info', 'PAUSE', 'resumed');
  }

  Future<void> _checkPauseGate() async {
    if (_pauseLatch != null && !_pauseLatch!.isCompleted) {
      await _pauseLatch!.future;
    }
  }

  // ─── Flow ─────────────────────────────────────────────────────────

  Future<void> _run() async {
    if (_disposed) return;
    _log('info', 'SESSION', 'lesson=${widget.lesson.id}');
    // 1. STORY
    await _narrate(_Phase.story, widget.lesson.story);
    if (_disposed || !mounted) return;
    await _phaseBreak();
    // 2. DEMO
    await _narrate(_Phase.demo, widget.lesson.demo);
    if (_disposed || !mounted) return;
    await _phaseBreak();
    // 3. INSTRUCT
    await _narrate(_Phase.instruct, widget.lesson.instruct);
    if (_disposed || !mounted) return;

    // CINEMATIC SOCIALS path — Lucien calls the moves live, one take,
    // then a verdict. No two-pass.
    if (widget.lesson.sequenceCues.isNotEmpty) {
      await _runCountdown();
      if (_disposed || !mounted) return;
      await _runSequenceDrill();
      if (_disposed || !mounted) return;
      await _finishScore();
      if (_disposed || !mounted) return;
      final v = _verdictLine(_result?.gazeScore ?? 0);
      setState(() { _phase = _Phase.correction; _currentChunk = v; });
      await _speak(v);
      if (_disposed || !mounted) return;
      setState(() => _phase = _Phase.score);
      return;
    }

    // 4. COUNTDOWN → DRILL (rep 1 — the practice attempt)
    await _runCountdown();
    if (_disposed || !mounted) return;
    await _runDrillPass();
    if (_disposed || !mounted) return;
    // 5. CORRECTION — Lucien teaches, then sends him back in. The
    //    correction beats END on "Again. This time…", so we honour it
    //    with a real second rep instead of stopping on a score card.
    await _phaseBreak();
    if (_disposed || !mounted) return;
    await _narrate(_Phase.correction, widget.lesson.correction);
    if (_disposed || !mounted) return;
    // 6. COUNTDOWN → DRILL (rep 2 — the graded attempt)
    await _runCountdown();
    if (_disposed || !mounted) return;
    await _runDrillPass();
    if (_disposed || !mounted) return;
    // 7. SCORE — only the coached second rep is graded.
    await _finishScore();
    if (_disposed || !mounted) return;
    // 8. VERDICT — Lucien's spoken call on the gaze he just judged
    //    (MediaPipe: eye stability, blinks, smile, head stillness). Two
    //    reps then a verdict — it never asks for a phantom third.
    final verdict = _verdictLine(_result?.gazeScore ?? 0);
    setState(() {
      _phase = _Phase.correction;
      _currentChunk = verdict;
    });
    await _speak(verdict);
    if (_disposed || !mounted) return;
    // Persist the AURA pillar score for the Ascend tab — keep the
    // running BEST across all gaze sessions so the pillar reads as
    // "what I've actually pulled off", not the dip from the last
    // bad rep. Apply the same progression cap the share card uses so
    // the Ascend pillar number matches what they just saw on the
    // score reveal — no "lesson card showed 4/10 but Ascend says 7".
    final gaze = ((_result?.gazeScore ?? 0) * _progressionCap).round();
    if (gaze > 0) {
      // ignore: discarded_futures
      _persistAura(gaze);
    }
    setState(() => _phase = _Phase.score);
  }

  /// Update the persisted AURA pillar score (Ascend) with the best
  /// score we've seen across all gaze sessions. Best-of semantics so
  /// a single bad rep can't tank the pillar number.
  Future<void> _persistAura(int gazeScore) async {
    final prefs = await SharedPreferences.getInstance();
    final prev = prefs.getInt('aura_score') ?? 0;
    if (gazeScore > prev) {
      await prefs.setInt('aura_score', gazeScore.clamp(0, 100));
    }
  }

  /// Lucien's spoken verdict — confirms the gaze was really judged.
  String _verdictLine(int gaze) {
    if (gaze >= 65) return 'Good. That\'s a gaze that holds the room.';
    if (gaze >= 50) return 'Better. You felt the difference that time.';
    return 'Not quite. You broke too early. But now you know.';
  }

  /// Plays each chunk through TTS, showing the chunk's text on screen,
  /// then waiting [lesson.beatPauseMs] before the next chunk. The
  /// chunked pattern is what gives Lucien his deliberate cadence —
  /// see GazeLesson docstring.
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
      _log('info', 'TTS', 'chunk[${phase.name}]: '
          '"${_clip(chunk, 60)}"');
      await _speak(chunk);
      if (_disposed || !mounted) return;
      await _pauseBeats(widget.lesson.beatPauseMs);
    }
  }

  Future<void> _phaseBreak() async {
    if (_disposed) return;
    await _checkPauseGate();
    setState(() => _currentChunk = '');
    await _pauseBeats(700);
  }

  Future<void> _pauseBeats(int ms) async {
    await Future.delayed(Duration(milliseconds: ms));
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
        } catch (_) {
          // TimeoutException — keep going.
        }
      } else {
        _log('warn', 'TTS', 'no audio bytes');
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

  void _resumeCountdown() {
    // Resume the same Timer.periodic; nothing to do here — paused
    // state is held by the gate.
  }

  /// CINEMATIC drill — Lucien calls each move out loud while the camera
  /// records the whole take. Samples accumulate the entire time (phase
  /// stays `drill`), so the reel is still scored. The cue shows big on
  /// screen as he says it.
  Future<void> _runSequenceDrill() async {
    if (_disposed) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _phase = _Phase.drill;
      _drillElapsed = 0;
      _drillBlinks = 0;
      _samples.clear();
      _currentChunk = '';
    });
    for (final cue in widget.lesson.sequenceCues) {
      if (_disposed || !mounted) return;
      await _checkPauseGate();
      if (_disposed || !mounted) return;
      setState(() => _currentChunk = cue);
      await _speak(cue);
      if (_disposed || !mounted) return;
      // Hold the move a beat so the camera catches it and they can land
      // it for the clip.
      await _pauseBeats(750);
    }
    if (_disposed || !mounted) return;
    setState(() {
      _phase = _Phase.scoring;
      _currentChunk = '';
    });
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 400));
  }

  /// One drill rep. Clears the accumulators, runs the timer while
  /// MediaPipe samples accumulate, then a short hold. Does NOT score —
  /// scoring is deferred to [_finishScore] so a lesson can run two
  /// reps (practice + graded) and only grade the second.
  Future<void> _runDrillPass() async {
    if (_disposed) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _phase = _Phase.drill;
      _drillElapsed = 0;
      _drillBlinks = 0;
      _samples.clear();
    });
    _resumeDrillTimer();
    // Wait for the timer to drain.
    while (_drillElapsed < widget.lesson.drillSeconds &&
           !_disposed && mounted) {
      await Future.delayed(const Duration(milliseconds: 200));
      await _checkPauseGate();
    }
    if (_disposed || !mounted) return;
    setState(() => _phase = _Phase.scoring);
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 600));
  }

  /// Scores the most recent rep, persists it, and surfaces the result.
  Future<void> _finishScore() async {
    if (_disposed || !mounted) return;
    final result = GazeScorer.score(
      lesson:  widget.lesson,
      samples: _samples,
      blinks:  _drillBlinks,
    );
    // Read the cap BEFORE recording — the cap counts PRIOR attempts,
    // not the one we\'re about to log. Otherwise session #1 picks up
    // the bump from session #1 logging itself.
    _progressionCap = await GazeProgressStore.progressionCap();
    _previousBest = await GazeProgressStore.record(result);
    _weeklyDelta  = await GazeProgressStore.weeklyImprovement();
    if (_disposed || !mounted) return;
    setState(() => _result = result);
    _log('ok', 'SCORE',
        'magnetic=${result.gazeScore} '
        'eye=${result.dimPct(GazeDimension.eyeStability)} '
        'blinks=${result.blinks}');
  }

  void _resumeDrillTimer() {
    _drillTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _disposed || _paused) return;
      setState(() => _drillElapsed++);
      if (_drillElapsed >= widget.lesson.drillSeconds) {
        t.cancel();
      }
    });
  }

  // ─── Buttons on the score card ────────────────────────────────────

  void _again() {
    if (_disposed) return;
    setState(() {
      _phase           = _Phase.warmup;
      _currentChunk    = '';
      _drillElapsed    = 0;
      _drillBlinks     = 0;
      _samples.clear();
      _result          = null;
      _previousBest    = null;
      _weeklyDelta     = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  void _nextLesson() {
    // Close reliably; the Eyes tab reloads and surfaces the next
    // uncompleted move.
    _closeScreen();
  }

  String _clip(String s, int n) => s.length > n ? '${s.substring(0, n)}…' : s;

  // ─── UI ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Score share card replaces everything.
    if (_phase == _Phase.score && _result != null) {
      return GazeShareCard(
        result:         _result!,
        lesson:         widget.lesson,
        previousBest:   _previousBest,
        weeklyDelta:    _weeklyDelta,
        quote:          _stampQuote(),
        progressionCap: _progressionCap,
        onAgain:        _again,
        onNext:         _nextLesson,
        onClose:        _closeScreen,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera + ghost overlay (always visible during ritual).
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

            // Two red fixation dots in the upper third — the
            // apprentice's gaze target during a drill. Drawn OUTSIDE
            // the camera transform stack so they sit at absolute
            // screen coords regardless of preview mirror/scale.
            if (_phase == _Phase.countdown ||
                _phase == _Phase.drill)
              Positioned.fill(
                child: FixationDots(isLocked: _metrics.isGoodEyeContact),
              ),

            // ── Cinematic intensity layer — only during the drill.
            // Dark vignette pulled around the edges so the eyes
            // become the focal point, plus a pulsing "HOLD" caption
            // below them that brightens when the user locks gaze.
            // Hidden during countdown / instruct so the chrome there
            // stays readable.
            if (_phase == _Phase.drill)
              Positioned.fill(
                child: IgnorePointer(
                  child: _DrillIntensityLayer(
                    isLocked: _metrics.isGoodEyeContact,
                  ),
                ),
              ),

            // Top chrome.
            Positioned(
              top: 6, left: 8, right: 8,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Text('THE GAZE',
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

            // Narration cards anchor LOW (just above the status
            // pill) so the apprentice's eyes stay on the camera,
            // not pulled up to read the middle of the screen. The
            // countdown + drill ticker stay vertically centred —
            // those are the "look at this" moments.
            if (_phase == _Phase.story ||
                _phase == _Phase.demo ||
                _phase == _Phase.instruct ||
                _phase == _Phase.correction)
              Positioned(
                left: 20, right: 20, bottom: 96,
                child: _NarrationCard(text: _currentChunk),
              ),
            if (_phase == _Phase.warmup ||
                _phase == _Phase.countdown ||
                _phase == _Phase.drill ||
                _phase == _Phase.scoring)
              Positioned(
                top: 140, bottom: 180, left: 20, right: 20,
                child: Center(child: _centreContent()),
              ),

            // Bottom — status label + objective.
            Positioned(
              left: 20, right: 20, bottom: 32,
              child: Column(
                children: [
                  if (_phase == _Phase.drill)
                    _ObjectivePill(text: widget.lesson.objective),
                  if (_phase == _Phase.drill) const SizedBox(height: 10),
                  Text(_statusLabel(),
                      style: AppTypography.label.copyWith(
                        color: AppColors.accent,
                        fontSize: 11,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w900,
                      )),
                ],
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

            // Camera-error overlay.
            if (_cameraError != null)
              Positioned(
                left: 20, right: 20, top: 180,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface1,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.signalRedBorder, width: 0.8),
                  ),
                  child: Text(
                    'Camera unavailable: $_cameraError',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.signalRed,
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic,
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
                  'smile':   _metrics.smileAuthenticity.toStringAsFixed(2),
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
      case _Phase.drill:
        // Cinematic socials lesson — show the move Lucien is calling,
        // big, instead of a countdown ticker.
        if (widget.lesson.sequenceCues.isNotEmpty) {
          return _CueCard(text: _currentChunk);
        }
        return _DrillTicker(
          elapsed: _drillElapsed,
          total:   widget.lesson.drillSeconds,
        );
      case _Phase.scoring:
        return const _ScoringIndicator();
      case _Phase.score:
      case _Phase.done:
      case _Phase.error:
        return const SizedBox.shrink();
    }
  }

  String _statusLabel() {
    if (_phase == _Phase.error) return 'CAMERA OFFLINE';
    switch (_phase) {
      case _Phase.warmup:     return 'LUCIEN IS APPROACHING';
      case _Phase.story:      return 'LUCIEN SETS THE TONE';
      case _Phase.demo:       return 'WATCH HIM';
      case _Phase.instruct:   return 'GET READY';
      case _Phase.countdown:  return 'BEGIN ON ONE';
      case _Phase.drill:      return widget.lesson.objective.toUpperCase();
      case _Phase.scoring:    return 'SCORING…';
      case _Phase.correction: return 'LUCIEN TEACHES';
      case _Phase.score:      return 'SESSION COMPLETE';
      default:                return '';
    }
  }

  /// Pull one quote out of the lesson's story to stamp on the share
  /// card. Picks the first chunk that's short enough to read.
  String _stampQuote() {
    for (final s in widget.lesson.story) {
      if (s.length <= 60) return s;
    }
    return widget.lesson.oneLine;
  }
}

// ─── Camera + vignette ───────────────────────────────────────────────

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

// ─── Pieces ──────────────────────────────────────────────────────────

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

/// The big move-cue shown during a cinematic socials drill, as Lucien
/// calls each beat. No card chrome — just the move, large, over the
/// camera, so it films clean.
class _CueCard extends StatelessWidget {
  final String text;
  const _CueCard({required this.text});
  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: ValueKey(text),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(text,
          textAlign: TextAlign.center,
          style: AppTypography.display.copyWith(
            color: Colors.white,
            fontSize: 34,
            height: 1.1,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            shadows: const [
              Shadow(color: Colors.black, blurRadius: 14),
              Shadow(color: Colors.black, blurRadius: 28),
            ],
          )),
    ).animate(key: ValueKey(text)).fadeIn(duration: 200.ms).scale(
          begin: const Offset(0.94, 0.94),
          end: const Offset(1, 1),
          duration: 240.ms,
          curve: Curves.easeOut,
        );
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

class _DrillTicker extends StatelessWidget {
  final int elapsed;
  final int total;
  const _DrillTicker({required this.elapsed, required this.total});
  @override
  Widget build(BuildContext context) {
    final remaining = (total - elapsed).clamp(0, total);
    final ratio = total > 0 ? (elapsed / total).clamp(0.0, 1.0) : 0.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(remaining.toString(),
            style: AppTypography.display.copyWith(
              color: AppColors.textPrimary,
              fontSize: 96,
              height: 1.0,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w900,
              letterSpacing: -3,
            )),
        const SizedBox(height: 12),
        SizedBox(
          width: 220,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 3,
              backgroundColor: AppColors.surface3,
              valueColor: const AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
        ),
      ],
    );
  }
}

class _ObjectivePill extends StatelessWidget {
  final String text;
  const _ObjectivePill({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.accentBorder, width: 0.8),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: AppTypography.label.copyWith(
            color: AppColors.textPrimary,
            fontSize: 11,
            letterSpacing: 1.8,
            fontWeight: FontWeight.w900,
          )),
    );
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

// ─── Drill intensity layer ─────────────────────────────────────────
// Sits on top of FixationDots during the drill phase. Two pieces:
//   1. A deep vignette around the screen edges so the eyes feel like
//      a cinema close-up — peripheral attention dies, you're locked
//      on the pair.
//   2. A breathing "HOLD" / "STAY" caption below the eyes that
//      brightens when the gaze engine confirms lock and dims when
//      the user drifts. Single-word, italic Playfair, no chrome.
//
// IgnorePointer-wrapped from the parent so it never intercepts taps.

class _DrillIntensityLayer extends StatelessWidget {
  final bool isLocked;
  const _DrillIntensityLayer({required this.isLocked});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Deep cinematic vignette. Black almost everywhere — only
        //    the eyes band stays visible. SUBTLE EDGE VIGNETTE ONLY —
        //    the user kept asking why the screen was blacking out and
        //    "doing some weird thing with the camera". Heavy fade had
        //    pure-black inner ring suppressing the camera face. Now
        //    just a soft edge darkening so the camera passthrough
        //    stays fully visible (the way the original scripted
        //    lesson always was), the eye target sits over the top.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.40),
              radius: 1.10,
              colors: [
                Colors.transparent,
                Colors.transparent,
                Colors.black.withValues(alpha: 0.40),
                Colors.black.withValues(alpha: 0.70),
              ],
              stops: const [0.0, 0.40, 0.80, 1.0],
            ),
          ),
        ),
        // ── Centered HOLD caption sitting just below the eyes
        // (eyes are at 28% vertical, caption at 50%).
        Align(
          alignment: const Alignment(0, 0.05),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 280),
            opacity: isLocked ? 0.95 : 0.42,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 280),
              style: GoogleFonts.playfairDisplay(
                fontSize: 22,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w800,
                color: isLocked ? Colors.white : AppColors.textSecondary,
                letterSpacing: 6.0,
                height: 1.0,
                shadows: isLocked
                    ? [
                        Shadow(
                          color: AppColors.accent.withValues(alpha: 0.55),
                          blurRadius: 14,
                        ),
                      ]
                    : const [],
              ),
              child: Text(isLocked ? 'HOLD' : 'STAY'),
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
            .scale(
              begin: const Offset(1.0, 1.0),
              end: Offset(isLocked ? 1.06 : 1.02,
                          isLocked ? 1.06 : 1.02),
              duration: 1400.ms,
              curve: Curves.easeInOut,
            ),
        ),
      ],
    );
  }
}
