import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/face_metrics.dart';
import '../../models/gaze/gaze_lesson.dart';
import '../../models/gaze/gaze_syllabus.dart';
import '../../services/audio_session.dart';
import '../../services/face_detector_service.dart';
import '../../services/gaze/selene_persona.dart';
import '../../services/realtime_session.dart';
import '../../theme/auralay_app_colors.dart';
import '../../theme/auralay_app_typography.dart';
import '../../widgets/eyes/auralay_face_overlay_painter.dart';
import '../../widgets/eyes/fixation_dots.dart';

/// SELENE — live AI gaze lesson.
///
/// One screen, one woman. Selene runs the entire lesson via the
/// OpenAI Realtime API: frame, theory, drill call, real-time coaching
/// against the apprentice's live face metrics, debrief. No scripted
/// TTS, no canned beats — every word adapts to what his face is
/// actually doing.
///
/// Architecture:
///   • Camera + FaceDetector run for the whole session — same as the
///     scripted lesson, so the metrics surface (blinkRate,
///     eyeContactScore, tensionScore) is identical.
///   • RealtimeSession is opened with mode='lesson'. Immediately after
///     connect we override the session via session.update so the
///     SeleneGaze persona + read_gaze tool are loaded regardless of
///     whichever default persona the backend would have served.
///   • Mic streams PCM16 @ 24kHz continuously. Server VAD handles
///     turn-taking — Selene speaks as soon as the apprentice stops.
///   • When she calls the read_gaze tool, we return the current
///     FaceMetrics + the running drill timer as the function output.
///     The drill timer starts on her FIRST tool call (i.e. the moment
///     she's running the live coaching phase, not the FRAME/THEORY
///     phases above it).
class SeleneLessonScreen extends StatefulWidget {
  final GazeLesson lesson;
  const SeleneLessonScreen({super.key, required this.lesson});

  @override
  State<SeleneLessonScreen> createState() => _SeleneLessonScreenState();
}

class _SeleneLessonScreenState extends State<SeleneLessonScreen>
    with SingleTickerProviderStateMixin {
  // Camera + face metrics.
  CameraController? _camera;
  bool _cameraReady = false;
  final FaceDetectorService _detector = FaceDetectorService();
  FaceMetrics _metrics = FaceMetrics.empty;
  bool _processing = false;

  // Blink counting — same logic as the scripted lesson.
  int _drillBlinks = 0;
  bool _wasBlinking = false;
  DateTime? _lastBlinkAt;
  static const int _blinkCooldownMs = 200;

  // Realtime session + audio I/O.
  final RealtimeSession _session = RealtimeSession();
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>?     _micSub;
  StreamSubscription<RealtimeEvent>? _eventSub;

  // Streaming PCM playback queue.
  final List<int> _pcmQueue = [];
  bool _pcmEngineReady = false;
  bool _pcmStarted = false;
  int _lastFeedMs = 0;
  Timer? _pcmWatchdog;
  static const int _feedFrames = 2400;        // 100ms @ 24kHz
  static const int _pcmStallMs = 500;

  // Drill clock — starts the FIRST time Selene calls read_gaze.
  DateTime? _drillStartedAt;
  static const int _drillSeconds = 12;

  // UI state.
  bool _disposed = false;
  bool _connecting = true;
  String _connectError = '';
  String _herCaption = '';
  bool _herSpeaking = false;
  // True once Selene\'s persona override has been pushed AND a
  // kickoff message sent. Guards against double-firing if
  // session.created arrives more than once.
  bool _seleneArmed = false;
  // Beat-driven lesson runner. Selene was stopping after the first
  // response because the realtime model decides when its OWN turn
  // ends. Solution: each lesson beat is its own response.create
  // call, fired sequentially on ResponseDone. She physically cannot
  // stop short — Flutter keeps her going beat by beat until the arc
  // is complete.
  int _beatIdx = 0;
  bool _lessonDone = false;
  // Drives the breathing pulse on the AuralayFaceOverlayPainter so
  // the white lines on his eyelids feel alive — same animation the
  // scripted lesson uses.
  late final AnimationController _loopAnim;

  // ─── Lifecycle ──────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loopAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    // ignore: discarded_futures
    AudioSession.configureForPlayAndRecord();
    // ignore: discarded_futures
    WakelockPlus.enable();
    _detector.init();
    _initCamera();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _disposed = true;
    _loopAnim.dispose();
    // ignore: discarded_futures
    WakelockPlus.disable();
    _pcmWatchdog?.cancel();
    _micSub?.cancel();
    _eventSub?.cancel();
    // ignore: discarded_futures
    _recorder.dispose();
    // Detach the feed callback so the engine doesn't ping a dead screen.
    FlutterPcmSound.setFeedCallback((_) {});
    _camera?.stopImageStream().catchError((_) {});
    _camera?.dispose();
    _detector.dispose();
    // ignore: discarded_futures
    _session.close();
    super.dispose();
  }

  void _closeScreen() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) return;
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
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _camera == null) return;
        try {
          await _camera!.startImageStream(_onFrame);
        } catch (_) {}
      });
    } catch (_) {}
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
      if (!mounted || m == null) return;
      // Blink edge-detect — same thresholds as the scripted lesson.
      final isClosed = _isBlinking(m);
      final now = DateTime.now();
      if (isClosed && !_wasBlinking) {
        final ok = _lastBlinkAt == null ||
            now.difference(_lastBlinkAt!).inMilliseconds > _blinkCooldownMs;
        if (ok) {
          if (_drillStartedAt != null) _drillBlinks++;
          _lastBlinkAt = now;
        }
      }
      _wasBlinking = isClosed;
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

  // ─── Start the Selene session ──────────────────────────────────────

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          setState(() {
            _connecting    = false;
            _connectError  = 'Microphone permission denied.';
          });
        }
        return;
      }

      // 1) PCM playback engine — set up once per process, reuse across
      //    sessions. Mirrors the Free Flow tab's pattern so we benefit
      //    from the same self-healing watchdog behaviour.
      if (!_pcmEngineReady) {
        await FlutterPcmSound.setup(sampleRate: 24000, channelCount: 1);
        FlutterPcmSound.setFeedThreshold(6000);
        _pcmEngineReady = true;
      }
      FlutterPcmSound.setFeedCallback(_onPcmFeed);
      _pcmStarted = true;
      _lastFeedMs = DateTime.now().millisecondsSinceEpoch;
      // ignore: discarded_futures
      FlutterPcmSound.start();
      _pcmWatchdog = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (_disposed) return;
        if (_pcmQueue.isNotEmpty) _kickPcmIfStalled();
      });

      // 2) Subscribe to Realtime events. We wait for session.created
      //    (broadcast as a RawEvent below) before pushing our persona
      //    override + kickoff — otherwise the backend\'s default
      //    Lucien-flavoured persona has time to fire a response and
      //    the apprentice hears a male voice quoting aphorisms
      //    before Selene\'s instructions land.
      _eventSub = _session.events.listen(_onEvent);

      // 3) Mint the session via the backend through the FREEFLOW
      //    contract, NOT the 'lesson' contract. Reason: the lesson
      //    route on the backend hardcodes Lucien\'s male voice and
      //    only the freeflow route reads body.voice and forwards it
      //    to OpenAI\'s session-create call (same path the Game-tab
      //    women already use — ice_queen, arena, chaos_girl, …).
      //    Selene\'s instructions then get fully overridden via
      //    session.update once session.created lands, so the
      //    freeflow default persona never speaks a word.
      await _session.connect(body: {
        'mode':            'freeflow',
        'vibeLabel':       'selene',
        'voice':           SeleneGaze.voice,
        'scenarioSetting': 'an eye-contact masterclass',
      });

      // 6) Mic streaming — push every chunk continuously. Server VAD
      //    handles turn-taking. The Selene persona never expects a
      //    push-to-talk gesture; the apprentice can simply ask a
      //    question and she answers.
      final stream = await _recorder.startStream(const RecordConfig(
        encoder:       AudioEncoder.pcm16bits,
        sampleRate:    24000,
        numChannels:   1,
        echoCancel:    true,
        noiseSuppress: true,
        autoGain:      true,
      ));
      _micSub = stream.listen((bytes) {
        if (_disposed) return;
        _session.sendAudioChunk(bytes);
      });

      if (!mounted) return;
      setState(() => _connecting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting   = false;
          _connectError = 'Could not connect to Selene: $e';
        });
      }
    }
  }

  String _promptForLesson(GazeLesson l) {
    // Lesson 1 ships with the full Selene masterclass prompt. Other
    // lessons fall back to a thin shim until each one has its own
    // masterclass written (THE DROP, SOFT EYES, …).
    if (l.id == 'the_lock') return SeleneGaze.theLockPrompt;
    return SeleneGaze.theLockPrompt; // placeholder while the others land
  }

  /// Arm Selene the instant the realtime session opens. Three things
  /// have to happen IN THIS ORDER before the model has a chance to
  /// reply with whatever default persona the backend handed it:
  ///   1. session.update — overrides instructions / voice / tools so
  ///      the model is Selene, not Lucien.
  ///   2. conversation.item.create system message — second layer of
  ///      identity reinforcement; if the backend\'s default persona
  ///      is still leaking through, this hard-pins her character on
  ///      the conversation itself.
  ///   3. response.create with the kickoff cue — only NOW do we
  ///      invite her to speak.
  void _armSelene() {
    if (_seleneArmed) return;
    _seleneArmed = true;

    _session.updateSession({
      'instructions': _promptForLesson(widget.lesson),
      'voice':        SeleneGaze.voice,
      'modalities':   ['audio', 'text'],
      'tools':        SeleneGaze.tools,
      'tool_choice':  'auto',
      'turn_detection': {
        'type':                'server_vad',
        'threshold':           0.5,
        'prefix_padding_ms':   300,
        // Bumped 500 → 2500 — Selene\'s prompted cadence has her
        // pausing about a second between sentences ("Sit up… phone
        // at eye level… look at me."). At the 500ms threshold the
        // server VAD was ending her turn after the first line and
        // she\'d stop the lesson entirely. 2.5 seconds is past her
        // longest natural in-line pause but short enough that the
        // apprentice can still interrupt by speaking >0.5s.
        'silence_duration_ms': 2500,
        'create_response':     true,
      },
    });

    // Kick off beat 1 of the lesson. ResponseDone on each beat will
    // auto-advance to the next via [_sendNextBeat] in [_onEvent].
    _sendNextBeat();
  }

  /// Fire the next lesson beat as its own response.create. Called
  /// once at session.created (beat 1), then on every ResponseDone
  /// (beats 2-7). Stops auto-advancing after the close so Selene
  /// listens for him at the end.
  void _sendNextBeat() {
    final beats = SeleneGaze.theLockBeats;
    if (_beatIdx >= beats.length) {
      _lessonDone = true;
      return;
    }
    _session.sendTextMessage(beats[_beatIdx]);
    _beatIdx++;
  }

  // ─── PCM playback feed ─────────────────────────────────────────────

  void _onPcmFeed(int remainingFrames) {
    if (_disposed) return;
    _lastFeedMs = DateTime.now().millisecondsSinceEpoch;
    if (_pcmQueue.isEmpty) {
      FlutterPcmSound.feed(
          PcmArrayInt16.fromList(List<int>.filled(_feedFrames, 0)));
      return;
    }
    final take =
        _pcmQueue.length > _feedFrames ? _feedFrames : _pcmQueue.length;
    final chunk = _pcmQueue.sublist(0, take);
    _pcmQueue.removeRange(0, take);
    FlutterPcmSound.feed(PcmArrayInt16.fromList(chunk));
  }

  void _kickPcmIfStalled() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!_pcmStarted || now - _lastFeedMs > _pcmStallMs) {
      _pcmStarted = true;
      _lastFeedMs = now;
      // ignore: discarded_futures
      FlutterPcmSound.start();
    }
  }

  // ─── Realtime event handling ───────────────────────────────────────

  void _onEvent(RealtimeEvent e) {
    if (_disposed || !mounted) return;
    if (e is AudioDelta) {
      final b = e.pcm16leBytes;
      final i16 = b.buffer.asInt16List(b.offsetInBytes, b.lengthInBytes ~/ 2);
      _pcmQueue.addAll(i16);
      _kickPcmIfStalled();
      if (!_herSpeaking) setState(() => _herSpeaking = true);
    } else if (e is DiabloTranscriptDelta) {
      setState(() => _herCaption += e.delta);
    } else if (e is DiabloTranscriptDone) {
      setState(() => _herCaption = e.transcript);
    } else if (e is ResponseStarted) {
      // Top of every turn — flush the queue + restart the engine so
      // the next reply lands without underrun, exactly like Free Flow.
      _pcmQueue.clear();
      _herCaption = '';
      // ignore: discarded_futures
      FlutterPcmSound.start();
    } else if (e is ResponseDone) {
      setState(() => _herSpeaking = false);
      // Auto-advance the lesson to the next beat. After the final
      // beat (CLOSE) this is a no-op so Selene waits for him to
      // pick "again" vs "next".
      if (!_lessonDone) _sendNextBeat();
    } else if (e is FunctionCallRequested) {
      _onFunctionCall(e);
    } else if (e is RawEvent && e.type == 'session.created') {
      // Backend has minted the session; OpenAI is ready to accept
      // overrides. Push Selene\'s persona + kickoff BEFORE the model
      // has any chance to emit a default-persona response.
      _armSelene();
    }
  }

  void _onFunctionCall(FunctionCallRequested e) {
    if (e.name != 'read_gaze') {
      // Unknown tool — reply with empty so Selene doesn't stall.
      _session.sendFunctionCallOutput(
        callId: e.callId,
        output:  '{}',
      );
      return;
    }
    // First call → drill clock starts.
    _drillStartedAt ??= DateTime.now();
    final elapsed = DateTime.now().difference(_drillStartedAt!).inMilliseconds / 1000.0;
    final remaining = (_drillSeconds - elapsed).clamp(0.0, _drillSeconds.toDouble());

    // Round the metrics to two decimals so Selene never sees noise.
    final m = _metrics;
    final tensionScore = ((m.headStability + m.composureScore) / 2.0).clamp(0.0, 1.0);
    final result = <String, dynamic>{
      'eyeContactScore':  double.parse(m.eyeContactScore.toStringAsFixed(2)),
      'blinkRate':        double.parse(m.blinkRate.toStringAsFixed(1)),
      'tensionScore':     double.parse(tensionScore.toStringAsFixed(2)),
      'headStability':    double.parse(m.headStability.toStringAsFixed(2)),
      'smileAuthenticity': double.parse(m.smileAuthenticity.toStringAsFixed(2)),
      'secondsElapsed':   double.parse(elapsed.toStringAsFixed(1)),
      'secondsRemaining': double.parse(remaining.toStringAsFixed(1)),
      'drillBlinks':      _drillBlinks,
    };
    _session.sendFunctionCallOutput(
      callId: e.callId,
      output:  jsonEncode(result),
    );
  }

  // ─── UI ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera passthrough — same _CameraLayer pattern the
            // scripted lesson uses (Transform.scale based on aspect
            // ratio so the apprentice\'s head doesn\'t get squished
            // into a narrow strip) + the AuralayFaceOverlayPainter
            // overlay so the white lines above his eyelids show in
            // real time, fed by the same MediaPipe FaceMetrics as
            // every other gaze screen.
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
            // Deep vignette — same treatment as the scripted drill.
            // Only the eye band stays visible; the apprentice's own
            // camera face is suppressed to a barely-there silhouette.
            const Positioned.fill(child: _LiveVignette()),
            // The eye target — Selene's eyes.
            Positioned.fill(
              child: FixationDots(isLocked: _metrics.isGoodEyeContact),
            ),

            // Top chrome — THE GAZE / lesson chip / live indicator / close.
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
                      'LESSON ${widget.lesson.number.toString().padLeft(2, "0")} · LIVE',
                      style: AppTypography.label.copyWith(
                        color: AppColors.accent,
                        fontSize: 9,
                        letterSpacing: 1.8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Spacer(),
                  _LiveDot(active: _herSpeaking),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: _closeScreen,
                    customBorder: const CircleBorder(),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.close_rounded,
                          color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ),

            // Selene's name + lesson title under the chrome.
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
                  const SizedBox(height: 4),
                  Text('with Selene',
                    style: GoogleFonts.inter(
                      color: AppColors.accent,
                      fontSize: 12.5,
                      letterSpacing: 0.4,
                      fontStyle: FontStyle.italic,
                    )),
                ],
              ),
            ),

            // Live caption — Selene's transcript streamed under the eyes.
            if (_herCaption.isNotEmpty)
              Positioned(
                left: 24, right: 24, bottom: 96,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: 0.96,
                  child: Text(
                    _herCaption,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.playfairDisplay(
                      color: Colors.white,
                      fontSize: 18,
                      height: 1.45,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.85),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Connecting / error overlays.
            if (_connecting)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.75),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 32, height: 32,
                        child: CircularProgressIndicator(
                          color: AppColors.accent, strokeWidth: 2),
                      ),
                      const SizedBox(height: 18),
                      Text('Connecting Selene…',
                        style: AppTypography.label.copyWith(
                          color: AppColors.accent,
                          fontSize: 11, letterSpacing: 3,
                          fontWeight: FontWeight.w900,
                        )),
                    ],
                  ),
                ),
              ),
            if (_connectError.isNotEmpty)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.85),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_connectError,
                        textAlign: TextAlign.center,
                        style: AppTypography.body.copyWith(
                          color: Colors.white, fontSize: 14, height: 1.45)),
                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: _closeScreen,
                        child: const Text('CLOSE',
                          style: TextStyle(
                            color: Colors.white,
                            letterSpacing: 2.4,
                            fontWeight: FontWeight.w800,
                          )),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Live indicator — small red pulse next to "LIVE" when Selene is
/// speaking. Dim when she's listening so the apprentice can read the
/// turn-taking at a glance.
class _LiveDot extends StatelessWidget {
  final bool active;
  const _LiveDot({required this.active});
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      width: 10, height: 10,
      decoration: BoxDecoration(
        color: active
            ? AppColors.accent
            : AppColors.accent.withValues(alpha: 0.30),
        shape: BoxShape.circle,
        boxShadow: active
            ? [BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.55),
                blurRadius: 8)]
            : null,
      ),
    );
  }
}

/// Soft edge vignette only — mirrors the scripted lesson's gentle
/// treatment. NO heavy black-out; the camera passthrough stays fully
/// visible so the apprentice's own face is part of the frame the way
/// every previous version of this surface worked.
class _LiveVignette extends StatelessWidget {
  const _LiveVignette();
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
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
    );
  }
}

/// Top-level helper — opens Selene's live lesson 1.
GazeLesson seleneLesson1() =>
    GazeSyllabus.byId('the_lock');

/// Aspect-aware camera wrapper. Mirrors the scripted lesson\'s
/// _CameraLayer so the apprentice\'s head doesn\'t get stretched
/// into a narrow strip when the device\'s aspect ratio doesn\'t
/// match the sensor\'s. Transform.scale + center crop is the
/// standard Flutter Camera-fit-the-screen pattern.
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
