import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../config/dev_flags.dart';
import '../../../services/audio_session.dart';
import '../../../services/creator_mode_store.dart';
import '../../../services/local_store_service.dart';
import '../../../services/realtime_session.dart';
import '../../../services/share_service.dart';
import '../../../services/user_memory.dart';
import '../../../services/villain/villain_api.dart';
import '../../../theme/auralay_app_colors.dart';
import '../../../theme/auralay_app_typography.dart';
import '../../../widgets/common/mirrorly_components.dart';
import '../../../widgets/debug_panel.dart';
import '../../../widgets/safe_close_button.dart';

/// FREE FLOW — live, streaming voice roleplay (OpenAI Realtime API).
///
/// The fast, lethal, Pingo-style mode the user asked for: pick the kind
/// of woman, get thrown into a continuous back-and-forth where you talk
/// and she answers instantly — no tap-to-record, no upload-and-wait.
/// Mic PCM streams up; her PCM streams down and plays with minimal lag;
/// server VAD handles turn-taking so it free-flows.
///
/// Lucien can STEP IN on demand: tap his button, she freezes, and he
/// drops a savage read of the exchange + the exact line you should have
/// used, then you carry on.
///
/// NOTE FOR DEVICE TESTING: real-time audio is the one thing that needs
/// tuning on a physical device — echo cancellation, mic/speaker levels,
/// and latency vary by phone. `echoCancel` is on to stop her hearing
/// herself; if barge-in feels off we tune silence_duration / threshold
/// server-side.
class FreeFlowScreen extends StatefulWidget {
  const FreeFlowScreen({super.key});

  @override
  State<FreeFlowScreen> createState() => _FreeFlowScreenState();
}

/// The "type of AI" the user picks before going live. Each maps to a
/// scenario name + setting handed to the realtime roleplay persona.
class _Vibe {
  final String key;
  final String label;
  final String tagline;
  final String setting;
  /// OpenAI realtime voice — each type sounds like a different woman.
  final String voice;
  /// One-line scene Lucien sets before you open. Where she is, who
  /// she's with — your cue to make the move.
  final String context;
  /// Asset path to her portrait. Renders inside the orb during the
  /// live phase so the user is talking to a real face, not a glow.
  final String assetPath;
  const _Vibe(this.key, this.label, this.tagline, this.setting, this.voice,
      this.context, this.assetPath);
}

const _vibes = <_Vibe>[
  _Vibe(
    'cold',
    'COLD',
    'Selective. Gives you nothing. Earn every inch.',
    'She is cold and selective — two or three word replies, bored before '
        'you opened your mouth. She is not hostile, she is filtered. She '
        'rewards composure with one extra word and punishes effort by going '
        'flatter. She never explains why.',
    'sage',
    'Coffee shop. She\'s alone at a window table, laptop open, one '
        'earbud in. She clocked you walk in. Make your move.',
    MirrorlyAssets.iceQueen,
  ),
  _Vibe(
    'into_you',
    'INTO YOU',
    'Already a little into you. Don\'t get needy.',
    'She is already a little into you — warm, flirty, leaning in. But the '
        'second you get needy, over-eager, or try too hard, she cools fast. '
        'Reward her warmth with confidence, not gratitude.',
    'coral',
    'Bar, Friday night. She\'s with her friend and she\'s already '
        'glanced over twice. The door\'s open. Make your move.',
    MirrorlyAssets.arenaWoman,
  ),
  _Vibe(
    'chaos',
    'CHAOS',
    'Fast, loud, jumps topics. Keep up.',
    'High energy, half-laughing, jumps topics mid-sentence, three drinks '
        'in. She tests whether you can ride it without scrambling or trying '
        'to slow her down. Match her tempo and she warms; ask her to repeat '
        'and she leaves you behind.',
    'shimmer',
    'House party, kitchen. She\'s mid-laugh with two friends, three '
        'drinks deep, buzzing. Make your move.',
    MirrorlyAssets.chaosGirl,
  ),
  _Vibe(
    'testing',
    'TESTING YOU',
    'Smart. Testing you constantly. Don\'t fold.',
    'She is sharp and tests you constantly — teasing, challenging, calling '
        'out anything rehearsed or try-hard. She rewards a man who holds his '
        'frame and teases back, and punishes folding, explaining yourself, '
        'or seeking her approval.',
    'ballad',
    'Bar. She\'s leaning on the counter with a friend, sizing up the '
        'room, unimpressed by all of it. Make your move.',
    MirrorlyAssets.intellectual,
  ),
  _Vibe(
    'ice_then_fire',
    'ICE THEN FIRE',
    'Starts ice cold. Warms only if you hold.',
    'She starts ice cold and unimpressed. She warms ONLY if the man holds '
        'his frame, stays unbothered, and doesn\'t chase. If he folds or '
        'gets needy she freezes again. The shift from ice to warmth is the '
        'whole reward.',
    'verse',
    'Rooftop bar. She\'s by the railing, arms crossed, looking at the '
        'view like it bores her. Make your move.',
    MirrorlyAssets.socialite,
  ),
];

enum _Phase { pick, connecting, live, lucien, scoring, scored, error }

class _FreeFlowScreenState extends State<FreeFlowScreen> {
  final RealtimeSession _session  = RealtimeSession();
  final AudioRecorder   _recorder = AudioRecorder();
  final AudioPlayer     _lucienPlayer = AudioPlayer();

  StreamSubscription<RealtimeEvent>? _eventSub;
  StreamSubscription<Uint8List>?     _micSub;
  Timer? _clock;
  Timer? _createTimer;   // debounced response.create after a release
  Timer? _pcmWatchdog;   // revives a stalled playback engine

  _Phase  _phase = _Phase.pick;
  _Vibe?  _vibe;
  String  _error = '';
  bool    _disposed = false;
  // Process-wide: the native PCM engine is set up once and reused across
  // every Free Flow session (never released — see dispose()).
  static bool _pcmEngineReady = false;
  bool    _pcmStarted = false;
  int     _lastFeedMs = 0;        // when the PCM engine last asked for data
  bool    _holding = false;      // push-to-talk: mic only forwards while held
  bool    _creator = false;      // Creator UNCHAINED mode
  bool    _responseActive = false; // a model response is currently generating

  // Live captions.
  String _herCaption = '';
  String _youCaption = '';
  bool   _herSpeaking = false;

  // ─── Live diagnostics ────────────────────────────────────────────────
  // The realtime audio loop is invisible without this — it surfaces what
  // OpenAI is actually sending (or not) so we can see why she does/doesn't
  // reply on a real device.
  final List<DebugEvent> _events = [];
  int _audioDeltaCount = 0;
  int _micChunks = 0;
  void _log(String level, String tag, String message) {
    _events.add(DebugEvent(
        ts: DateTime.now(), level: level, tag: tag, message: message));
    if (_events.length > 80) _events.removeRange(0, _events.length - 80);
    // ignore: avoid_print
    print('[freeflow] ${level.toUpperCase()} $tag $message');
  }

  // Full back-and-forth, captured for the end-of-session scorecard.
  final List<Map<String, String>> _transcript = [];
  FreeFlowScore? _result;

  // PCM playback queue (int16 samples). Fed to flutter_pcm_sound on its
  // feed callback; cleared instantly on barge-in so she stops the moment
  // you start talking.
  final List<int> _pcmQueue = [];

  // Session length.
  static const int _sessionSeconds = 180;
  int _remaining = _sessionSeconds;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    _disposed = true;
    // ignore: discarded_futures
    WakelockPlus.disable();
    _clock?.cancel();
    _createTimer?.cancel();
    _pcmWatchdog?.cancel();
    _eventSub?.cancel();
    _micSub?.cancel();
    // ignore: discarded_futures
    _recorder.dispose();
    _lucienPlayer.dispose();
    // ignore: discarded_futures
    _session.close();
    // Do NOT release() the PCM engine. release() tears down the native
    // audio engine, and on iOS a subsequent setup() does NOT rebuild it —
    // that is the "first roleplay works, every one after a rebuild is
    // silent" bug. We set the engine up ONCE per process and reuse it; here
    // we just detach this screen's feed callback so a disposed screen never
    // gets pinged. The next session rebinds its own callback + start()s.
    FlutterPcmSound.setFeedCallback((_) {});
    super.dispose();
  }

  // ─── Go live ────────────────────────────────────────────────────────

  Future<void> _goLive(_Vibe vibe) async {
    setState(() {
      _vibe = vibe;
      _phase = _Phase.connecting;
      _error = '';
    });
    try {
      if (!await _recorder.hasPermission()) {
        _fail('Microphone permission denied.');
        return;
      }
      await AudioSession.configureForPlayAndRecord();

      // 1) Streaming playback engine — 24kHz PCM16 mono to match the
      //    Realtime API output. Set up ONCE per process and reused across
      //    sessions; re-running setup() after a release() is what left every
      //    session past the first silent. We never release() now, so guard
      //    setup() to run a single time, then just (re)bind this screen's
      //    feed callback each session.
      if (!_pcmEngineReady) {
        await FlutterPcmSound.setup(sampleRate: 24000, channelCount: 1);
        FlutterPcmSound.setFeedThreshold(6000);
        _pcmEngineReady = true;
      }
      FlutterPcmSound.setFeedCallback(_onPcmFeed);

      // WAKE THE ENGINE NOW. It is reused across sessions and is almost
      // certainly sitting stopped/underrun from the previous session.
      // start() re-triggers the feed callback (the silence keep-warm then
      // holds it alive), so playback is live the instant this session opens
      // — NOT only when the first reply arrives. This is what fixes "works
      // once": every new session re-arms the shared engine here.
      _pcmStarted = true;
      _lastFeedMs = DateTime.now().millisecondsSinceEpoch;
      // ignore: discarded_futures
      FlutterPcmSound.start();

      // Safety net for the tail of a turn: if audio is still queued but the
      // engine has stopped asking for it (stalled), revive it. Per-delta
      // kicks cover mid-stream; this covers the last chunk after deltas stop.
      _pcmWatchdog = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (_disposed) return;
        if (_pcmQueue.isNotEmpty) _kickPcmIfStalled();
      });

      // 2) Mint + open the realtime session as the chosen woman.
      _creator = await CreatorModeStore.isActive();
      final memoryBlock = await UserMemory.buildSystemPromptBlock(
        filterTopic: 'rizz',
      );
      _eventSub = _session.events.listen(_onEvent);
      await _session.connect(body: {
        'mode':            'freeflow',
        'vibeLabel':       vibe.label,
        'voice':           vibe.voice,
        'scenarioSetting': vibe.setting,
        'creator':         _creator,
        'memoryBlock':     memoryBlock,
      });

      // 3) Stream the mic up as PCM16 — but only FORWARD chunks while the
      //    user is holding the talk button (push-to-talk). The stream
      //    stays alive; gating on _holding means she never hears herself
      //    and only gets what he actually says.
      final micStream = await _recorder.startStream(const RecordConfig(
        encoder:       AudioEncoder.pcm16bits,
        sampleRate:    24000,
        numChannels:   1,
        echoCancel:    true,
        autoGain:      true,
        noiseSuppress: true,
      ));
      _micSub = micStream.listen((bytes) {
        if (_disposed || !_holding) return;
        _micChunks++;
        _session.sendAudioChunk(bytes);
      });

      if (_disposed || !mounted) return;
      _log('ok', 'WS', 'connected · ${vibe.label} · creator=$_creator');
      setState(() => _phase = _Phase.live);
      _startClock();
      HapticFeedback.mediumImpact();
    } catch (e) {
      _fail(e.toString());
    }
  }

  // ─── PCM playback feed ───────────────────────────────────────────────

  // Feed SMALL chunks (~100ms) so the engine asks for data on a fast,
  // predictable heartbeat (~10x/sec). A steady heartbeat is what lets us
  // tell a live engine from a dead one quickly (see _kickPcmIfStalled) and
  // recover in ~0.5s instead of leaving a long silent gap. Threshold 6000
  // (250ms) keeps a comfortable cushion against network jitter.
  static const _feedFrames = 2400;        // 100ms @ 24kHz
  void _onPcmFeed(int remainingFrames) {
    if (_disposed) return;
    _lastFeedMs = DateTime.now().millisecondsSinceEpoch;
    if (_pcmQueue.isEmpty) {
      // Keep the engine warm with a beat of silence so it never dies on a
      // brief underrun between audio bursts.
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

  // Self-healing kick. The native PCM engine can DIE mid-stream (audio-
  // session contention with the always-on mic, route changes) and then
  // never call the feed callback again on its own — that is the "voice
  // keeps stopping" bug.
  //
  // With the ~100ms feed heartbeat above, a LIVE engine pings the callback
  // roughly every 100ms. So if the callback has been silent for >500ms,
  // the engine is genuinely dead — restart it. 500ms is 5x the healthy
  // cadence (no false positives, so no mid-playback stutter) yet recovers
  // 3x faster than the old 1.5s gap. start() is a no-op when alive.
  static const _pcmStallMs = 500;
  void _kickPcmIfStalled() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!_pcmStarted || now - _lastFeedMs > _pcmStallMs) {
      _pcmStarted = true;
      _lastFeedMs = now;
      // ignore: discarded_futures
      FlutterPcmSound.start();
    }
  }

  // ─── Realtime events ─────────────────────────────────────────────────

  void _onEvent(RealtimeEvent e) {
    if (_disposed || !mounted) return;
    if (e is AudioDelta) {
      // Append int16 samples to the playback queue.
      final b = e.pcm16leBytes;
      final i16 = b.buffer.asInt16List(b.offsetInBytes, b.lengthInBytes ~/ 2);
      _pcmQueue.addAll(i16);
      _audioDeltaCount++;
      if (_audioDeltaCount == 1) _log('ok', 'AUDIO', 'her audio started');
      _kickPcmIfStalled();
      if (!_herSpeaking) setState(() => _herSpeaking = true);
    } else if (e is DiabloTranscriptDelta) {
      setState(() => _herCaption += e.delta);
    } else if (e is DiabloTranscriptDone) {
      if (e.transcript.trim().isNotEmpty) {
        _transcript.add({'role': 'her', 'text': e.transcript.trim()});
        _log('ok', 'HER', e.transcript.trim());
      }
      setState(() => _herCaption = e.transcript);
    } else if (e is UserTranscript) {
      if (e.text.trim().isNotEmpty) {
        _transcript.add({'role': 'user', 'text': e.text.trim()});
        _log('ok', 'YOU', e.text.trim());
      }
      setState(() => _youCaption = e.text);
    } else if (e is ResponseStarted) {
      _responseActive = true;
      _audioDeltaCount = 0;
      // Force a FRESH engine start at the top of EVERY turn. This is the
      // fix for "voice works once then stops": after the first reply the
      // engine goes idle and will not wake on its own, so each new turn
      // must restart it. Safe here — we just cleared the queue, so only
      // silence (if anything) is playing; restarting can't glitch audible
      // speech. (The mid-playback watchdog stays conservative at 500ms.)
      _pcmQueue.clear();
      _pcmStarted = true;
      _lastFeedMs = DateTime.now().millisecondsSinceEpoch;
      // ignore: discarded_futures
      FlutterPcmSound.start();
      _log('info', 'RESP', 'response.created · pcm restarted');
      setState(() => _herCaption = '');
    } else if (e is ResponseDone) {
      _responseActive = false;
      // Leave _pcmStarted true — the engine stays warm (silence) between
      // turns; the stall detector revives it if iOS ever kills it.
      _log('info', 'RESP', 'response.done · audioDeltas=$_audioDeltaCount');
      setState(() => _herSpeaking = false);
    } else if (e is RealtimeErrorEvent) {
      // Log EVERY error (so we can see benign ones too), but only a
      // genuinely fatal one drops the line. response.cancel with nothing
      // active and empty-buffer commits are benign.
      _log('error', 'ERR', '${e.code}: ${e.message}');
      final m = e.message.toLowerCase();
      final benign = m.contains('no active response') ||
          m.contains('cancellation failed') ||
          m.contains('buffer is empty') ||
          m.contains('already has an active response') ||
          m.contains('no audio') ||
          e.code == 'response_cancel_not_active' ||
          e.code == 'input_audio_buffer_commit_empty';
      if (!benign) _fail(e.message);
    } else if (e is RawEvent) {
      // Surface the handshake + lifecycle types so we can see the
      // session actually configure (session.created/updated, commits,
      // rate limits, etc.).
      _log('info', 'EV', e.type);
    }
  }

  // ─── Push-to-talk ────────────────────────────────────────────────────

  void _startHold() {
    if (_phase != _Phase.live || _holding) return;
    // Cancel any pending create from a previous release so rapid taps
    // can't fire two response.create calls (which OpenAI rejects as
    // "conversation already has an active response").
    _createTimer?.cancel();
    // If she's mid-reply, take the floor: stop her audio + generation.
    if (_herSpeaking || _responseActive || _pcmQueue.isNotEmpty) {
      _pcmQueue.clear();
      _session.cancelResponse();   // benign error if none active — filtered
      _responseActive = false;
    }
    HapticFeedback.mediumImpact();
    _micChunks = 0;
    _log('info', 'PTT', 'hold');
    setState(() {
      _holding = true;
      _herSpeaking = false;
      _youCaption = '';
    });
  }

  void _endHold() {
    if (!_holding) return;
    HapticFeedback.lightImpact();
    setState(() => _holding = false);
    _log('info', 'PTT', 'release · micChunks=$_micChunks');
    // Commit the held audio, then ask her to respond. The small gap lets
    // OpenAI turn the committed buffer into a conversation item before
    // response.create fires. Debounced + guarded so we never stack two
    // active responses.
    _session.commitInputAudio();
    _createTimer?.cancel();
    _createTimer = Timer(const Duration(milliseconds: 220), () {
      if (_disposed) return;
      if (_responseActive) {
        // Something is still generating — clear it, then create once.
        _session.cancelResponse();
        _responseActive = false;
      }
      _session.requestResponse();
      _log('info', 'PTT', 'commit + response.create');
    });
  }

  // ─── Lucien steps in ─────────────────────────────────────────────────

  // The realtime model occasionally leaks a stage cue ("[laughs]",
  // "(sneers)", "*cackles*") into the transcript even though the AUDIO
  // performs it correctly. Strip those from the displayed caption.
  static final _cueRe = RegExp(r'[\[(\*][^\])\*]*[\])\*]');
  String _stripStageCues(String s) =>
      s.replaceAll(_cueRe, '').replaceAll(RegExp(r'\s{2,}'), ' ').trim();

  Future<void> _lucienStepIn() async {
    if (_phase != _Phase.live) return;
    HapticFeedback.heavyImpact();
    // Capture the exchange BEFORE we clear the caption.
    final her = _herCaption.trim();
    final you = _youCaption.trim();
    // Take the floor from the woman + clear her audio, then force a fresh
    // engine start so Lucien reliably speaks (same "restart every turn"
    // fix that keeps the woman's voice alive past the first reply).
    _pcmQueue.clear();
    _session.cancelResponse();
    _responseActive = false;
    _pcmStarted = true;
    _lastFeedMs = DateTime.now().millisecondsSinceEpoch;
    // ignore: discarded_futures
    FlutterPcmSound.start();
    setState(() {
      _phase = _Phase.lucien;
      _herCaption = '';
    });

    // Lucien speaks through the SAME expressive realtime engine the
    // woman uses (gpt-realtime), in his own ash voice — so he actually
    // laughs and performs instead of a read-aloud TTS spelling out
    // "ja ja ja". A transient one-shot session: connect, request one
    // spoken turn, play it, close.
    final lucien = RealtimeSession();
    final done = Completer<void>();
    final caption = StringBuffer();
    StreamSubscription<RealtimeEvent>? sub;
    try {
      _log('info', 'LUCIEN', 'realtime step-in · creator=$_creator');
      sub = lucien.events.listen((e) {
        if (_disposed || !mounted) return;
        if (e is AudioDelta) {
          final b = e.pcm16leBytes;
          final i16 =
              b.buffer.asInt16List(b.offsetInBytes, b.lengthInBytes ~/ 2);
          _pcmQueue.addAll(i16);
          _kickPcmIfStalled();
        } else if (e is DiabloTranscriptDelta) {
          caption.write(e.delta);
          setState(() => _herCaption = _stripStageCues(caption.toString()));
        } else if (e is DiabloTranscriptDone) {
          setState(() => _herCaption = _stripStageCues(e.transcript));
        } else if (e is ResponseDone) {
          if (!done.isCompleted) done.complete();
        } else if (e is RealtimeErrorEvent) {
          _log('error', 'LUCIEN', '${e.code}: ${e.message}');
          if (!done.isCompleted) done.complete();
        }
      });
      await lucien.connect(body: {
        'mode':      'lucien',
        'vibeLabel': _vibe?.label ?? '',
        'lastHer':   her,
        'lastYou':   you,
        'creator':   _creator,
      });
      if (_disposed) return;
      lucien.requestResponse();
      // Wait for generation to finish, then let the buffered audio drain.
      await done.future.timeout(const Duration(seconds: 70)).catchError((_) {});
      int guard = 0;
      while (!_disposed && _pcmQueue.length > 2400 && guard < 200) {
        await Future.delayed(const Duration(milliseconds: 150));
        guard++;
      }
      await Future.delayed(const Duration(milliseconds: 400));
    } catch (e) {
      _log('error', 'LUCIEN', e.toString());
    } finally {
      await sub?.cancel();
      // ignore: discarded_futures
      lucien.close();
    }
    if (_disposed || !mounted) return;
    setState(() => _phase = _Phase.live);
  }

  // ─── Clock ───────────────────────────────────────────────────────────

  void _startClock() {
    _clock = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_disposed || !mounted) {
        t.cancel();
        return;
      }
      setState(() => _remaining--);
      if (_remaining <= 0) {
        t.cancel();
        _endAndScore();
      }
    });
  }

  /// End the live session and get Lucien's /10 verdict. Stops the mic +
  /// her audio, scores the captured transcript, plays the verdict, and
  /// drops the shareable scorecard.
  Future<void> _endAndScore() async {
    if (_phase == _Phase.scoring || _phase == _Phase.scored) return;
    _clock?.cancel();
    _createTimer?.cancel();
    HapticFeedback.mediumImpact();
    // Stop streaming both ways.
    _pcmQueue.clear();
    _session.cancelResponse();
    await _micSub?.cancel();
    // ignore: discarded_futures
    _recorder.stop().catchError((_) {});
    setState(() => _phase = _Phase.scoring);
    try {
      final score = await VillainApi.freeflowScore(
        transcript: _transcript,
        vibeLabel:  _vibe?.label ?? 'woman',
        creator:    _creator,
      );
      if (_disposed || !mounted) return;
      setState(() {
        _result = score;
        _phase = _Phase.scored;
      });
      // Persist the GAME pillar score for the Ascend tab — best-of
      // semantics so a single fumbled session can't tank the pillar
      // number. FreeFlowScore is already 0..10, so we multiply by
      // 10 to land in the same 0..100 storage band the LOOKS and
      // AURA pillars use (home_screen divides by 10 to display).
      // ignore: discarded_futures
      _persistGame(score.score);
      if (score.audioBytes != null && score.audioBytes!.isNotEmpty) {
        try {
          await _lucienPlayer
              .play(BytesSource(score.audioBytes!, mimeType: 'audio/mpeg'));
        } catch (_) {}
      }
    } catch (e) {
      _fail(e.toString());
    }
  }

  /// Best-of update of the GAME pillar score read by the Ascend tab.
  /// FreeFlowScore is 0..10 — multiply by 10 to match the 0..100
  /// storage band used by the LOOKS + AURA pillars.
  Future<void> _persistGame(int scoreOutOfTen) async {
    final prefs = await SharedPreferences.getInstance();
    final next = (scoreOutOfTen * 10).clamp(0, 100);
    final prev = prefs.getInt('game_score') ?? 0;
    if (next > prev) await prefs.setInt('game_score', next);
  }

  void _fail(String msg) {
    if (!mounted || _disposed) return;
    setState(() {
      _phase = _Phase.error;
      _error = msg;
    });
  }

  void _closeScreen() {
    if (!mounted) return;
    // Pop only — dispose() runs on pop and performs all teardown
    // (mic, session, pcm engine), so we never double-close anything.
    _clock?.cancel();
    _createTimer?.cancel();
    safePop(context);
  }

  // ─── UI ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: _phase == _Phase.pick
            ? _buildPicker()
            : (_phase == _Phase.scored && _result != null
                ? _buildScorecard(_result!)
                : _buildLive()),
      ),
    );
  }

  Widget _buildPicker() {
    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 14, 8),
                child: Row(
                  children: [
                    Text('FREE FLOW · LIVE',
                        style: AppTypography.label.copyWith(
                          color: AppColors.accent,
                          fontSize: 11,
                          letterSpacing: 3.2,
                          fontWeight: FontWeight.w900,
                        )),
                    const Spacer(),
                    const SafeCloseButton(),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pick who you\'re talking to.',
                        style: AppTypography.display.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 34,
                          letterSpacing: -1.2,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        )),
                    const SizedBox(height: 10),
                    Text('Real-time. You talk, she answers. No waiting.',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.accent,
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                        )),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final v = _vibes[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _VibeCard(vibe: v, onTap: () => _goLive(v)),
                    );
                  },
                  childCount: _vibes.length,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLive() {
    final mins = (_remaining ~/ 60).toString();
    final secs = (_remaining % 60).toString().padLeft(2, '0');
    return Stack(
      children: [
        // Top chrome.
        Positioned(
          top: 6, left: 8, right: 8,
          child: Row(
            children: [
              const SizedBox(width: 8),
              Text(_vibe?.label ?? '',
                  style: AppTypography.label.copyWith(
                    color: AppColors.accent,
                    fontSize: 11,
                    letterSpacing: 2.8,
                    fontWeight: FontWeight.w900,
                  )),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.surface1,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: AppColors.divider, width: 0.6),
                ),
                child: Text('$mins:$secs',
                    style: AppTypography.label.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w900,
                    )),
              ),
              Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: () { HapticFeedback.lightImpact(); _closeScreen(); },
                  customBorder: const CircleBorder(),
                  child: const SizedBox(
                    width: 44, height: 44,
                    child: Center(
                      child: Icon(Icons.close_rounded,
                          color: AppColors.textPrimary, size: 24),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Centre — fixed orb up top; the caption sits in a scrollable
        // band below it so long text (her replies, Lucien's reads) never
        // collides with the bottom controls.
        Positioned(
          top: 56, left: 0, right: 0, bottom: 188,
          child: Column(
            children: [
              // The orb IS the talk button. Hold it to speak; a ring
              // spins while you hold; release to send. Uses raw pointer
              // events (Listener) not tap gestures, so sliding your
              // finger or drifting off the edge never cancels the hold —
              // only lifting your finger ends it.
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown:   (_) => _startHold(),
                onPointerUp:     (_) => _endHold(),
                onPointerCancel: (_) => _endHold(),
                child: SizedBox(
                  width: 260, height: 260,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_holding)
                        const SizedBox(
                          width: 234, height: 234,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor:
                                AlwaysStoppedAnimation(AppColors.accent),
                          ),
                        ),
                      _Orb(
                        active: _phase == _Phase.live,
                        speaking: _herSpeaking,
                        holding: _holding,
                        thinking: _phase == _Phase.connecting ||
                            _phase == _Phase.lucien ||
                            _phase == _Phase.scoring,
                        // Render HER face as the orb itself so the user
                        // is talking to a real person, not a glow.
                        imagePath: _vibe?.assetPath,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Press-and-hold instruction directly under the orb so a
              // brand-new user knows immediately HOW to talk to her.
              // Visible only while the live phase is idle (not while
              // she's mid-reply, not while Lucien is reading / scoring).
              if (_phase == _Phase.live && !_holding && !_herSpeaking)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'HOLD TO SPEAK',
                    textAlign: TextAlign.center,
                    style: AppTypography.label.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      letterSpacing: 3.0,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              if (_holding)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'LISTENING — RELEASE TO SEND',
                    textAlign: TextAlign.center,
                    style: AppTypography.label.copyWith(
                      color: AppColors.accent,
                      fontSize: 11,
                      letterSpacing: 3.0,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              if (_phase == _Phase.lucien || _phase == _Phase.scoring)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                      _phase == _Phase.scoring
                          ? 'LUCIEN IS SCORING YOU'
                          : 'LUCIEN IS READING IT',
                      textAlign: TextAlign.center,
                      style: AppTypography.label.copyWith(
                        color: AppColors.accent,
                        fontSize: 12,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w900,
                      )),
                ),
              // Scrollable caption band — long lines scroll here instead
              // of running under the controls.
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 2, 28, 8),
                  child: Column(
                    children: [
                      if (_herCaption.isEmpty &&
                          _transcript.isEmpty &&
                          _phase == _Phase.live)
                        Text(_vibe?.context ?? 'Make your move.',
                            textAlign: TextAlign.center,
                            style: AppTypography.h1Italic.copyWith(
                              color: Colors.white,
                              fontSize: 18,
                              height: 1.5,
                              fontStyle: FontStyle.italic,
                            ))
                      else if (_herCaption.isNotEmpty)
                        Text(_herCaption,
                            textAlign: TextAlign.center,
                            style: AppTypography.h1Italic.copyWith(
                              color: Colors.white,
                              fontSize: 19,
                              height: 1.45,
                              fontStyle: FontStyle.italic,
                            )),
                      if (_youCaption.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text('you: $_youCaption',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 12.5,
                              height: 1.4,
                            )),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Bottom — status + Lucien step-in.
        Positioned(
          left: 0, right: 0, bottom: 28,
          child: Column(
            children: [
              Text(
                _phase == _Phase.connecting
                    ? 'CONNECTING…'
                    : _holding
                        ? 'LISTENING… RELEASE TO SEND'
                        : (_herSpeaking
                            ? 'SHE\'S TALKING'
                            : 'HOLD THE CIRCLE TO TALK'),
                style: AppTypography.label.copyWith(
                  color: AppColors.accent,
                  fontSize: 11,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _phase == _Phase.live ? _lucienStepIn : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 14),
                    decoration: BoxDecoration(
                      color: _phase == _Phase.live
                          ? AppColors.accent
                          : AppColors.surface3,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('LUCIEN — STEP IN',
                        style: AppTypography.label.copyWith(
                          color: _phase == _Phase.live
                              ? Colors.white
                              : AppColors.textTertiary,
                          fontSize: 12,
                          letterSpacing: 2.6,
                          fontWeight: FontWeight.w900,
                        )),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(100),
                child: InkWell(
                  onTap: _phase == _Phase.live ? _endAndScore : null,
                  borderRadius: BorderRadius.circular(100),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Text('END & GET SCORED',
                        style: AppTypography.label.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 10.5,
                          letterSpacing: 2.4,
                          fontWeight: FontWeight.w900,
                        )),
                  ),
                ),
              ),
            ],
          ),
        ),

        if (_phase == _Phase.error)
          Positioned(
            left: 16, right: 16, bottom: 110,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.signalRedBorder, width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LINE DROPPED',
                      style: AppTypography.label.copyWith(
                        color: AppColors.signalRed,
                        fontSize: 11,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w900,
                      )),
                  const SizedBox(height: 6),
                  Text(
                    _error.length > 200
                        ? '${_error.substring(0, 200)}…'
                        : _error,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(100),
                    child: InkWell(
                      onTap: _closeScreen,
                      borderRadius: BorderRadius.circular(100),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surface3,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text('GO BACK',
                            style: AppTypography.label.copyWith(
                              color: AppColors.accent,
                              fontSize: 10,
                              letterSpacing: 2.4,
                              fontWeight: FontWeight.w900,
                            )),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Live diagnostics — tap to expand. Shows whether OpenAI is
        // actually sending her response (response.created / audio deltas)
        // or erroring out.
        Positioned(
          left: 0, bottom: 0,
          child: DebugPanel(
            kvs: {
              'phase':    _phase.name,
              'holding':  _holding ? 'yes' : 'no',
              'resp':     _responseActive ? 'active' : 'idle',
              'herAudio': '$_audioDeltaCount',
              'turns':    '${_transcript.length}',
              'creator':  _creator ? 'on' : 'off',
            },
            events: _events,
            margin: const EdgeInsets.only(left: 10, bottom: 6),
          ),
        ),
      ],
    );
  }

  String _freeflowBadge(int score) {
    if (score >= 9) return 'LETHAL';
    if (score >= 7) return 'REAL GAME';
    if (score >= 4) return 'FORGETTABLE';
    return 'SHE LEFT';
  }

  Widget _buildScorecard(FreeFlowScore s) {
    final color = s.score >= 7
        ? AppColors.signalGreen
        : (s.score <= 3 ? AppColors.signalRed : AppColors.accent);
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.4),
                  radius: 0.95,
                  colors: [
                    color.withValues(alpha: 0.16),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('FREE FLOW · ${_vibe?.label ?? ''}',
                      style: AppTypography.label.copyWith(
                        color: AppColors.accent,
                        fontSize: 11,
                        letterSpacing: 2.8,
                        fontWeight: FontWeight.w900,
                      )),
                ],
              ),
              const Spacer(),
              Text('YOUR GAME',
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w900,
                  )),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${s.score}',
                      style: AppTypography.display.copyWith(
                        color: color,
                        fontSize: 130,
                        height: 1.0,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -5,
                      )),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Text(' / 10',
                        style: AppTypography.label.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 18,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w900,
                        )),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (s.verdict.isNotEmpty)
                Text('"${s.verdict}"',
                    textAlign: TextAlign.center,
                    style: AppTypography.h1Italic.copyWith(
                      color: Colors.white,
                      fontSize: 20,
                      height: 1.45,
                      fontStyle: FontStyle.italic,
                    )),
              const SizedBox(height: 8),
              Text('— LUCIEN',
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(
                    color: AppColors.accent,
                    fontSize: 10,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w900,
                  )),
              const SizedBox(height: 24),
              if (s.landed.isNotEmpty)
                _ScoreRow(label: 'LANDED', text: s.landed,
                    color: AppColors.signalGreen),
              if (s.flopped.isNotEmpty)
                _ScoreRow(label: 'FLOPPED', text: s.flopped,
                    color: AppColors.signalRed),
              if (s.line.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface1,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: AppColors.accentBorder, width: 0.8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('THE LINE YOU NEEDED',
                          style: AppTypography.label.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 9.5,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w900,
                          )),
                      const SizedBox(height: 6),
                      Text(s.line,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            height: 1.4,
                            fontStyle: FontStyle.italic,
                          )),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              _ScoreCta(
                label: 'SHARE',
                filled: true,
                onTap: () => ShareService.shareScore(
                  context:   context,
                  kindLabel: 'FREE FLOW',
                  subLabel:  _vibe?.label ?? '',
                  score:     s.score,
                  badge:     _freeflowBadge(s.score),
                  verdict:   s.verdict,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ScoreCta(
                      label: 'RUN IT BACK',
                      filled: false,
                      onTap: () async {
                        // Pro restarts freely; a free user has already
                        // spent their one Free Flow, so close back to the
                        // Game tab where the card is now locked → paywall.
                        final pro = kBypassPaywall
                            ? true
                            : await LocalStoreService.isSubscribed();
                        if (!mounted) return;
                        if (pro) {
                          Navigator.of(context, rootNavigator: true)
                              .pushReplacement(MaterialPageRoute(
                            builder: (_) => const FreeFlowScreen(),
                          ));
                        } else {
                          _closeScreen();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ScoreCta(
                      label: 'DONE',
                      filled: false,
                      onTap: _closeScreen,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VibeCard extends StatelessWidget {
  final _Vibe vibe;
  final VoidCallback onTap;
  const _VibeCard({required this.vibe, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.accentBorder, width: 0.8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vibe.label,
                        style: AppTypography.label.copyWith(
                          color: Colors.white,
                          fontSize: 15,
                          letterSpacing: 2.4,
                          fontWeight: FontWeight.w900,
                        )),
                    const SizedBox(height: 6),
                    Text(vibe.tagline,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.accent,
                          fontSize: 13,
                          height: 1.35,
                          fontStyle: FontStyle.italic,
                        )),
                  ],
                ),
              ),
              const Icon(Icons.graphic_eq_rounded,
                  color: AppColors.accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final String label;
  final String text;
  final Color color;
  const _ScoreRow(
      {required this.label, required this.text, required this.color});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(label,
                style: AppTypography.label.copyWith(
                  color: color,
                  fontSize: 10,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w900,
                )),
          ),
          Expanded(
            child: Text(text,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  height: 1.4,
                )),
          ),
        ],
      ),
    );
  }
}

class _ScoreCta extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _ScoreCta(
      {required this.label, required this.filled, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () { HapticFeedback.lightImpact(); onTap(); },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? AppColors.accent : AppColors.surface1,
            borderRadius: BorderRadius.circular(12),
            border: filled
                ? null
                : Border.all(color: AppColors.accentBorder, width: 0.8),
          ),
          child: Text(label,
              style: AppTypography.label.copyWith(
                color: filled ? Colors.white : AppColors.accent,
                fontSize: 12,
                letterSpacing: 3,
                fontWeight: FontWeight.w900,
              )),
        ),
      ),
    );
  }
}

/// The live orb / talk button — breathes when idle, brightens while you
/// hold to talk, pulses hard when she's speaking.
class _Orb extends StatelessWidget {
  final bool active;
  final bool speaking;
  final bool holding;
  final bool thinking;
  /// When set, the orb renders HER face as a circular portrait with a
  /// pulsing red rim — far more compelling than a generic glow. Null
  /// falls back to the original glowing orb.
  final String? imagePath;
  const _Orb({
    required this.active,
    required this.speaking,
    required this.thinking,
    this.holding = false,
    this.imagePath,
  });
  @override
  Widget build(BuildContext context) {
    final size = (speaking || holding) ? 220.0 : 192.0;
    // Rim accent — red when she speaks (her voice), indigo when the
    // user is holding (your voice), dim when idle.
    final rim = speaking
        ? AppColors.red
        : (holding ? AppColors.accent : AppColors.divider);
    final glowAlpha = holding ? 0.7 : (speaking ? 0.65 : 0.18);

    // Only show HER face when SHE is speaking. Idle + while the user
    // is holding-to-speak the orb stays as the red/indigo gradient so
    // the screen reads as the user's instrument until she takes the
    // floor — at which point her face fades in inside the same circle.
    final showFace = speaking && imagePath != null;

    final Widget gradient = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: holding
              ? [
                  AppColors.accent,
                  AppColors.accent.withValues(alpha: 0.85),
                ]
              : [
                  AppColors.red,
                  AppColors.red.withValues(alpha: 0.78),
                ],
        ),
        boxShadow: [
          BoxShadow(
            color: rim.withValues(alpha: glowAlpha.clamp(0.0, 1.0)),
            blurRadius: (speaking || holding) ? 80 : 44,
            spreadRadius: (speaking || holding) ? 4 : -6,
          ),
        ],
      ),
    );

    Widget w;
    if (!showFace) {
      w = gradient;
    } else {
      w = AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: rim, width: 3),
          boxShadow: [
            BoxShadow(
              color: rim.withValues(alpha: glowAlpha.clamp(0.0, 1.0)),
              blurRadius: 70,
              spreadRadius: 3,
            ),
          ],
        ),
        child: ClipOval(
          child: Image.asset(
            imagePath!,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.25),
            errorBuilder: (_, __, ___) => Container(
              color: AppColors.surface1,
              alignment: Alignment.center,
              child: const Icon(Icons.person_rounded,
                  size: 64, color: AppColors.surface3),
            ),
          ),
        ),
      );
    }

    // Hold = steady (ring spins separately). Otherwise breathe — faster
    // and a touch bigger when she's speaking so the eye locks on.
    if (holding || (!active && !thinking)) return w;
    return w
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scale(
          begin: const Offset(1, 1),
          end: Offset(speaking ? 1.045 : 1.02, speaking ? 1.045 : 1.02),
          duration: (speaking ? 520 : 1400).ms,
          curve: Curves.easeInOut,
        );
  }
}
