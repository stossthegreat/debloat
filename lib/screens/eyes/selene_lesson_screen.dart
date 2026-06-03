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
import 'package:shared_preferences/shared_preferences.dart';
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

  // Drill clock — starts when Beat 4 fires. Used by _onFunctionCall
  // to compute secondsElapsed / secondsRemaining for Selene\'s
  // coaching cues during the lock. Per-lesson because different
  // lessons run different drill lengths (THE LOCK = 12s, THE SILENT
  // HOLD = 25s, etc).
  DateTime? _drillStartedAt;
  int get _drillSeconds => widget.lesson.drillSeconds;

  // ─── Lesson conductor — Flutter directs, model performs ──────────
  //
  // Every beat in SeleneGaze.theLockBeats is a contract: a cue +
  // a Flutter-side floor (minimum wall-clock time) + an eyes-overlay
  // state. The conductor enforces all three so the lesson cannot
  // rush.

  /// Index of the NEXT beat to fire on _sendNextBeat. Post-increments
  /// inside that method so this points one past the currently active
  /// beat.
  int _beatIdx = 0;

  /// Wall-clock when the currently active beat fired. Used to
  /// reason about elapsed phase time. Null between beats.
  DateTime? _phaseStartedAt;

  /// Flips true when the realtime model emits ResponseDone for the
  /// current beat. Required (alongside _phaseFloorMet) before we
  /// will advance to the next beat.
  bool _phaseResponseDone = false;

  /// Flips true when the floor timer for the current beat expires.
  /// Required (alongside _phaseResponseDone) before we will
  /// advance. This is what stops the lesson from racing — even if
  /// the model rips through its lines in 5 seconds, Flutter holds
  /// the beat on screen until the floor for that beat elapses.
  bool _phaseFloorMet = false;

  /// Per-beat timer that flips _phaseFloorMet to true after the
  /// beat\'s floorMs elapses. Cancelled and re-armed on every beat.
  Timer? _phaseFloorTimer;

  /// The 12-second DRILL clock. Hard-gated: when Beat 4 fires this
  /// starts, and only this timer is allowed to advance the lesson
  /// to Beat 5 — ResponseDones during the drill are ignored entirely
  /// (the model is firing short coaching lines via read_gaze and
  /// each one would otherwise fire a ResponseDone).
  Timer? _drillTimer;

  /// True while Beat 4 (the lock itself) is the active phase. Drives
  /// both the auto-advance suppression and the eyes overlay being
  /// pinned on. Set by _sendNextBeat when Beat 4 fires, cleared by
  /// _drillTimer when 12 wall-clock seconds elapse.
  bool _inDrillPhase = false;

  /// True while Selene\'s cinematic eyes asset should be visible.
  /// Driven by [SeleneBeat.showEyes] on the active beat — Beat 3
  /// (THE MOVES — "pick my left eye, the iris") and Beat 4 (the
  /// lock itself) both show them. Every other beat clears the
  /// overlay so the apprentice\'s own face is clean while she
  /// teaches.
  bool _showEyes = false;

  /// Final breath of silence between a beat ending and the next one
  /// firing, after both ResponseDone AND floor are met. Adds a
  /// deliberate "she finished — now there is a beat — now next"
  /// rhythm so the lesson never bounces line-to-line.
  Timer? _advanceTimer;
  static const int _interBeatBreathMs = 1500;

  /// The Selene beats for THIS lesson, generated once on
  /// connect from [SeleneGaze.beatsFor]. Every lesson in
  /// [GazeSyllabus] now flows through the same beat structure with
  /// content rendered from its own pedagogy (story / demo / instruct
  /// / correction / drillSeconds), so THE LOCK, THE DROP, SOFT EYES,
  /// CAUGHT, etc. all run on the identical conductor without per-
  /// lesson code branches here.
  late final List<SeleneBeat> _beats;
  late final GazeLesson? _nextLesson;

  /// Per-frame samples of eyeContactScore captured during the 12s
  /// drill. Averaged on lesson close to produce the AURA pillar
  /// score the Today\'s Ascension card reads. Without this Selene
  /// completions never ticked off AURA and the home counter sat
  /// at 0 / 3 no matter how many drills the apprentice ran.
  final List<double> _drillEcsSamples = [];
  bool _persistedThisRun = false;

  /// Stats from the most recent completed drill. AGAIN injects these
  /// into the Beat 4 cue so Selene opens the next rep with a
  /// correction anchored in what just happened ("last rep: you blinked
  /// 14 times. this rep: cut them in half. again.") instead of just
  /// re-firing the same script. Bro: "go again this time blink less
  /// or whatever — you know what I mean." Null on the FIRST rep of a
  /// fresh session, populated after the drill clock expires.
  _PriorAttempt? _priorAttempt;

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
  // _beatIdx is declared above in the lesson-conductor block; the
  // duplicate previously sitting here was a leftover from the
  // refactor and caused the iOS Release build to fail with "already
  // declared in this scope." _lessonDone stays here — it\'s the only
  // UI flag the build below reads to surface the AGAIN / NEXT LESSON
  // CTAs after BEAT 7.
  bool _lessonDone = false;
  // Drives the breathing pulse on the AuralayFaceOverlayPainter so
  // the white lines on his eyelids feel alive — same animation the
  // scripted lesson uses.
  late final AnimationController _loopAnim;

  // ─── Lifecycle ──────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Build the Selene beat arc for THIS lesson + look up the next
    // lesson in the syllabus so Beat 7\'s close line references it.
    final all = GazeSyllabus.all;
    final idx = all.indexWhere((l) => l.id == widget.lesson.id);
    _nextLesson = (idx >= 0 && idx < all.length - 1) ? all[idx + 1] : null;
    _beats = SeleneGaze.beatsFor(widget.lesson, nextLesson: _nextLesson);

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
    _drillTimer?.cancel();
    _advanceTimer?.cancel();
    _phaseFloorTimer?.cancel();
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
      // Sample eye-contact score during the drill so we can compute
      // the AURA pillar score at lesson close. Bound the buffer so
      // an extended replay session doesn\'t balloon memory.
      if (_inDrillPhase) {
        _drillEcsSamples.add(m.eyeContactScore);
        if (_drillEcsSamples.length > 600) {
          _drillEcsSamples.removeRange(0, _drillEcsSamples.length - 600);
        }
      }
      setState(() => _metrics = m);
    } catch (_) {} finally {
      _processing = false;
    }
  }

  /// Stamp today\'s AURA completion so the Ascend tab\'s Today\'s
  /// Ascension card ticks AURA off. Mirrors the scripted lesson\'s
  /// _persistAura in eyes_session_screen.dart so both lesson paths
  /// feed the same counter the home screen reads. Idempotent across
  /// AGAIN replays inside the same session via _persistedThisRun —
  /// the first close stamps the day, subsequent replays still
  /// recompute the score but don\'t spam writes.
  Future<void> _persistAuraCompletion() async {
    if (_drillEcsSamples.isEmpty) return;
    final avgEcs = _drillEcsSamples.reduce((a, b) => a + b) /
        _drillEcsSamples.length;
    final score = (avgEcs * 100).round().clamp(0, 100);
    try {
      final prefs = await SharedPreferences.getInstance();
      final prev = prefs.getInt('aura_score') ?? 0;
      if (score > prev) await prefs.setInt('aura_score', score);
      final now = DateTime.now();
      await prefs.setInt(
        'aura_done_ymd',
        now.year * 10000 + now.month * 100 + now.day,
      );
      _persistedThisRun = true;
    } catch (_) {}
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

  /// Fire the next beat in Selene\'s lesson arc. Each beat is a
  /// [SeleneBeat] contract: a cue + a wall-clock floor + an eyes-
  /// overlay state. Flutter is the conductor — the model performs
  /// the cue, Flutter holds the lesson on the beat until BOTH the
  /// floor has elapsed AND the model has emitted ResponseDone.
  /// Beat 4 is the exception: it\'s a hard 12-second wall-clock
  /// drill, advanced by [_drillTimer] only.
  void _sendNextBeat() {
    final beats = _beats;
    if (_beatIdx >= beats.length) {
      if (mounted) setState(() => _lessonDone = true);
      // Lesson reached close → stamp AURA completion so the home
      // tab\'s Today\'s Ascension counter ticks up. Fire-and-forget;
      // failure here must never block the UI.
      // ignore: discarded_futures
      _persistAuraCompletion();
      return;
    }

    final beat = beats[_beatIdx];
    final isDrill = (_beatIdx == 3); // Beat 4 (0-indexed) is THE DRILL.

    // Reset per-beat state BEFORE firing so a stray ResponseDone
    // from the previous beat can\'t accidentally advance us.
    _phaseStartedAt    = DateTime.now();
    _phaseResponseDone = false;
    _phaseFloorMet     = false;
    _phaseFloorTimer?.cancel();
    _advanceTimer?.cancel();

    if (mounted) {
      setState(() {
        _showEyes     = beat.showEyes;
        _inDrillPhase = isDrill;
      });
    }

    if (isDrill) {
      // Hard 12-second wall-clock drill. ResponseDone during this
      // phase is ignored; the timer is the only thing that advances.
      _drillStartedAt = DateTime.now();
      _drillEcsSamples.clear();
      _drillTimer?.cancel();
      _drillTimer = Timer(Duration(seconds: _drillSeconds), () {
        if (!mounted) return;
        // Snapshot drill stats BEFORE we tear down the in-drill state
        // so AGAIN can read them on the next rep. Average eye-contact
        // score across the held samples + blink count is enough for
        // Selene to anchor a corrective opening line on the rerun.
        final samples = List<double>.from(_drillEcsSamples);
        final avgEcs  = samples.isEmpty
            ? 0.0
            : samples.reduce((a, b) => a + b) / samples.length;
        final minEcs  = samples.isEmpty
            ? 0.0
            : samples.reduce((a, b) => a < b ? a : b);
        _priorAttempt = _PriorAttempt(
          avgEyeContact: avgEcs,
          minEyeContact: minEcs,
          blinks:        _drillBlinks,
        );
        setState(() {
          _inDrillPhase = false;
          _showEyes     = false;
        });
        _sendNextBeat();
      });
    } else {
      // Teaching beat. Floor timer is what enforces "this beat must
      // stay on screen at least floorMs." Combined with the
      // ResponseDone gate in _onEvent, the lesson cannot advance
      // until BOTH are met.
      _phaseFloorTimer = Timer(
        Duration(milliseconds: beat.floorMs),
        () {
          if (!mounted) return;
          _phaseFloorMet = true;
          _tryAdvance();
        },
      );
    }

    // For BEAT 4, prepend a "PRIOR REP" coaching directive if AGAIN
    // landed us here with stats from the previous drill. The model
    // uses this to open the new rep with a correction anchored in
    // what just happened ("last rep — your eyes drifted around
    // second seven. this rep, stay on the iris. twelve seconds.
    // begin."). Without this, AGAIN re-runs the exact same script
    // and the rerun feels mechanical instead of taught.
    final cueToSend = isDrill && _priorAttempt != null
        ? '${_priorAttemptDirective(_priorAttempt!)}\n\n${beat.cue}'
        : beat.cue;

    _session.sendTextMessage(cueToSend);
    _beatIdx++;
  }

  /// Build a short corrective directive for the model to prepend to
  /// the Beat 4 cue when AGAIN is the entry point. Six words max for
  /// the line itself; the surrounding prompt frame tells the model
  /// to deliver it BEFORE "twelve seconds. begin." so the apprentice
  /// hears the correction first, then the call.
  String _priorAttemptDirective(_PriorAttempt p) {
    String hint;
    if (p.avgEyeContact < 0.55) {
      hint = 'this rep, do not look away from my iris.';
    } else if (p.blinks > 10) {
      hint = 'this rep, half the blinks.';
    } else if (p.avgEyeContact < 0.72) {
      hint = 'this rep, narrow the lids a hair more.';
    } else if (p.minEyeContact < 0.45) {
      hint = 'this rep, do not drift past second seven.';
    } else {
      hint = 'this rep, hold it heavier.';
    }
    return '''[PRIOR REP CONTEXT] He just finished a rep. Before you deliver "Twelve seconds. Begin." on this Beat 4, FIRST say a single short coaching line that names what happened and what to fix. Use this exact corrective hint, in your voice, low and slow: "$hint" Then pause 1.5 seconds. THEN run Beat 4 normally.''';
  }

  /// Advance to the next beat IFF: model is done speaking the
  /// current cue AND the wall-clock floor for the current beat has
  /// elapsed. Called from the ResponseDone handler and from the
  /// floor timer expiry — whichever lands last triggers the actual
  /// advance, after a final 1.5-second breath of silence so the
  /// transition reads as deliberate rather than racing.
  void _tryAdvance() {
    if (!mounted) return;
    if (_lessonDone) return;
    if (_inDrillPhase) return; // drill timer owns advance during the lock
    if (!_phaseResponseDone || !_phaseFloorMet) return;
    _advanceTimer?.cancel();
    _advanceTimer = Timer(
      const Duration(milliseconds: _interBeatBreathMs),
      () {
        if (!mounted) return;
        if (_lessonDone || _inDrillPhase) return;
        _sendNextBeat();
      },
    );
  }

  /// AGAIN — restart the rep without the intro / theory / moves
  /// preamble. He already heard those; another rep means another
  /// lock. Cancels every pending timer and resets the per-beat
  /// state cleanly, then jumps to BEAT 4 (THE CALL + DRILL). The
  /// AURA persistence flag stays sticky so the day isn\'t double-
  /// stamped across replays.
  void _runAgain() {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    _advanceTimer?.cancel();
    _drillTimer?.cancel();
    _phaseFloorTimer?.cancel();
    setState(() {
      _drillStartedAt    = null;
      _drillBlinks       = 0;
      _drillEcsSamples.clear();
      _lastCoachingCue   = '';
      _inDrillPhase      = false;
      _showEyes          = false;
      _phaseStartedAt    = null;
      _phaseResponseDone = false;
      _phaseFloorMet     = false;
      _lessonDone        = false;
      _beatIdx           = 3; // 0-indexed — beat 4 is "THE CALL + DRILL"
    });
    _sendNextBeat();
  }

  /// NEXT — advance to the next lesson in the gaze syllabus. Closes
  /// the current Selene session and pushes the next lesson\'s live
  /// screen. Falls back to closing the screen if this is the last
  /// lesson in the syllabus. Previously NEXT just popped to home,
  /// which read as "the app is broken" rather than "we\'re moving on."
  void _goToNextLesson() {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    _advanceTimer?.cancel();
    _drillTimer?.cancel();
    final all = GazeSyllabus.all;
    final currentIdx = all.indexWhere((l) => l.id == widget.lesson.id);
    if (currentIdx < 0 || currentIdx >= all.length - 1) {
      // No next lesson — close cleanly.
      _closeScreen();
      return;
    }
    final next = all[currentIdx + 1];
    // Use go (not push) so the back stack doesn\'t deepen lesson by
    // lesson — pressing X always exits to home, never back into a
    // previous lesson.
    context.go('/eyes/live/${next.id}');
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
      // Wrap _herCaption clear in setState so the on-screen transcript
      // refreshes immediately between beats; without this the caption
      // from beat N stays on screen until beat N+1\'s first delta
      // lands, and on screenshots that looked like multiple beats
      // were stacking into one wall of text.
      _pcmQueue.clear();
      setState(() => _herCaption = '');
      // ignore: discarded_futures
      FlutterPcmSound.start();
    } else if (e is ResponseDone) {
      setState(() => _herSpeaking = false);
      // ResponseDone is ONE of the two conditions that allow advance.
      // The other is the per-beat floor timer. _tryAdvance gates on
      // both. During the drill phase, ResponseDones come from the
      // model\'s short coaching cues (one per read_gaze metric
      // breach) and are entirely ignored — the drill timer owns
      // advance there.
      if (_lessonDone || _inDrillPhase) return;
      _phaseResponseDone = true;
      _tryAdvance();
    } else if (e is FunctionCallRequested) {
      _onFunctionCall(e);
    } else if (e is RawEvent && e.type == 'session.created') {
      // Backend has minted the session; OpenAI is ready to accept
      // overrides. Push Selene\'s persona + kickoff BEFORE the model
      // has any chance to emit a default-persona response.
      _armSelene();
    }
  }

  /// Tracks the last coaching cue Flutter handed to Selene so we
  /// don\'t repeat the same line multiple times in a single drill —
  /// once she says "you drifted", we don\'t fire it again until the
  /// metric recovers and breaches again later.
  String _lastCoachingCue = '';

  /// Resolve the most pressing coaching cue from the current face
  /// metrics. Returns an empty string when no cue should fire
  /// (silence is the lock). Tier ladder:
  ///   T-1  no face / camera blind — must coach, can\'t practise without
  ///   T0   sustained drift — eyes nowhere near the iris
  ///   T1   anxious blinks
  ///   T2   tense body
  ///   T2.5 mid-range hold, push for the smolder
  ///   T3   warm approval / time signal during a strong hold
  /// Cues are imperative, ≤6 words, external-focus per the motor-
  /// learning literature (Wulf 2013).
  String _resolveCoachingCue({
    required double eyeContactScore,
    required double blinkRate,
    required double tensionScore,
    required double secondsElapsed,
    required double secondsRemaining,
  }) {
    // Final beat — call her break verdict (varied so the same
    // phrasing doesn\'t fire every rep).
    if (secondsRemaining <= 0.0) {
      if (eyeContactScore >= 0.78) return ''; // strong → silence, let him break first
      if (eyeContactScore >= 0.55) return 'and break. you found me at the end.';
      return 'and break. you held what you could.';
    }

    // T-1 — MediaPipe sees no face at all (or near-zero score for
    // sustained beats). Without this fallback Selene goes silent
    // when the user holds their phone wrong, which reads as broken
    // instead of corrective. Bro: "even if you don\'t get enough
    // data from MediaPipe… she says we\'re going again, this time
    // softer your eyes."
    if (eyeContactScore < 0.20) {
      if (secondsElapsed > 3.0) return 'center your face. let me see you.';
      return 'phone at eye level. look at the lens.';
    }

    // T0 — completely off the iris.
    if (eyeContactScore < 0.55) return 'you drifted. find my left eye.';

    // T1 — anxious blinks (only meaningful past the first 2s of the
    // drill, otherwise startle blinks fire and read as a problem
    // when they\'re not).
    if (secondsElapsed > 2.0) {
      if (blinkRate > 28) return 'stop blinking. dead lid.';
      if (blinkRate > 22) return 'slow your blinks.';
    }

    // T2 — tense body.
    if (tensionScore < 0.55) return 'drop your shoulders.';

    // T2.5 — mid-range hold, push for the smolder.
    if (eyeContactScore < 0.75 && secondsElapsed > 4.0) {
      return 'tighten. narrow your lids.';
    }

    // T3 — time-aware approval / final-stretch cues.
    if (secondsRemaining < 3.0 && eyeContactScore > 0.7) {
      return 'almost. don\'t move.';
    }
    if (eyeContactScore > 0.82 && secondsRemaining > 6.0 && secondsElapsed > 2.0) {
      return 'good. that\'s the lock.';
    }
    // T4 — sustained mid-band hold that\'s NEITHER bad nor strong.
    // Without a cue here Selene stays silent the whole drill on a
    // mediocre rep, which reads as broken. A single mid-drill
    // tightening nudge gives her presence without monologue.
    if (eyeContactScore >= 0.6 && eyeContactScore <= 0.78 &&
        secondsElapsed > 5.0 && secondsRemaining > 3.0) {
      return 'half a millimetre tighter.';
    }
    return '';
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
    // First call → drill clock starts (idempotent — Beat 4 already
    // set this when the beat fired; this is the fallback path).
    _drillStartedAt ??= DateTime.now();
    final elapsed = DateTime.now().difference(_drillStartedAt!).inMilliseconds / 1000.0;
    final remaining = (_drillSeconds - elapsed).clamp(0.0, _drillSeconds.toDouble());

    // Round the metrics to two decimals so Selene never sees noise.
    final m = _metrics;
    final tensionScore = ((m.headStability + m.composureScore) / 2.0).clamp(0.0, 1.0);

    // Resolve the live coaching cue from Flutter — the model uses
    // this directly (Beat 4 cue tells it: "say exactly coachingCue
    // or stay silent"). Flutter is the brain, Selene is the voice.
    // Debounce so the same cue doesn\'t repeat within the same
    // drill — once she says "you drifted" we don\'t fire it again
    // until the metric recovers and breaches again later.
    String cue = _resolveCoachingCue(
      eyeContactScore:  m.eyeContactScore,
      blinkRate:        m.blinkRate,
      tensionScore:     tensionScore,
      secondsElapsed:   elapsed,
      secondsRemaining: remaining,
    );
    if (cue == _lastCoachingCue) cue = '';
    if (cue.isNotEmpty) _lastCoachingCue = cue;

    final result = <String, dynamic>{
      'eyeContactScore':   double.parse(m.eyeContactScore.toStringAsFixed(2)),
      'blinkRate':         double.parse(m.blinkRate.toStringAsFixed(1)),
      'tensionScore':      double.parse(tensionScore.toStringAsFixed(2)),
      'headStability':     double.parse(m.headStability.toStringAsFixed(2)),
      'smileAuthenticity': double.parse(m.smileAuthenticity.toStringAsFixed(2)),
      'secondsElapsed':    double.parse(elapsed.toStringAsFixed(1)),
      'secondsRemaining':  double.parse(remaining.toStringAsFixed(1)),
      'drillBlinks':       _drillBlinks,
      // FLUTTER → SELENE coaching directive. Beat 4\'s cue instructs
      // Selene to say this line verbatim if non-empty, otherwise to
      // stay silent. This is the closed-loop reactive coaching path
      // — metrics in, cue out, voiced immediately.
      'coachingCue':       cue,
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
            // The eye target — Selene\'s cinematic eyes. Visible
            // during BEAT 3 (THE MOVES — she\'s telling him to "pick
            // my left eye, the iris" so the overlay makes the
            // instruction concrete) AND BEAT 4 (the 12s lock itself).
            // Every other beat hides them so the apprentice\'s own
            // camera view is clean while she teaches. State is read
            // straight off the active SeleneBeat.showEyes.
            Positioned.fill(
              child: FixationDots(
                isLocked: _metrics.isGoodEyeContact,
                active:   _showEyes,
              ),
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

            // AGAIN / NEXT — surfaces only after the close beat (BEAT 7).
            // Selene says "Again. Or next." and now there\'s an actual
            // control. Voice picks up nothing reliably mid-room, so the
            // tap is the foolproof path. AGAIN re-runs the drill only
            // (skips intro/theory). NEXT closes the lesson cleanly.
            if (_lessonDone)
              Positioned(
                left: 24, right: 24, bottom: 28,
                child: Row(
                  children: [
                    Expanded(
                      child: _SeleneCta(
                        label: 'AGAIN',
                        filled: true,
                        onTap: _runAgain,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SeleneCta(
                        // Label tells the apprentice WHERE the next
                        // tap goes — to the next lesson in the
                        // syllabus, not just out of the screen.
                        label: _nextLesson != null ? 'NEXT LESSON' : 'DONE',
                        filled: false,
                        onTap: _goToNextLesson,
                      ),
                    ),
                  ],
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

/// Snapshot of the most recent completed drill. Selene reads this
/// when AGAIN fires the next rep so her opening line is a
/// correction anchored in what just happened, not a generic
/// re-run of the same Beat 4 script.
class _PriorAttempt {
  final double avgEyeContact; // 0..1
  final double minEyeContact; // 0..1
  final int    blinks;
  const _PriorAttempt({
    required this.avgEyeContact,
    required this.minEyeContact,
    required this.blinks,
  });
}

/// Big bottom-row CTA — appears as the AGAIN / NEXT pair when
/// Selene\'s lesson reaches the close beat. Filled accent for the
/// primary action (AGAIN), outlined for the secondary (NEXT).
/// Kept local so it can stay tight to the lesson\'s visual language
/// without leaking through to other screens.
class _SeleneCta extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _SeleneCta({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () { HapticFeedback.mediumImpact(); onTap(); },
        borderRadius: BorderRadius.circular(100),
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: filled
                ? AppColors.accent
                : AppColors.accent.withValues(alpha: 0.55),
              width: 1.4,
            ),
            boxShadow: filled
              ? [BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.45),
                  blurRadius: 18, offset: const Offset(0, 6))]
              : null,
          ),
          child: Text(
            label,
            style: AppTypography.label.copyWith(
              color: filled ? Colors.black : AppColors.accent,
              fontSize: 13,
              letterSpacing: 3.2,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

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
