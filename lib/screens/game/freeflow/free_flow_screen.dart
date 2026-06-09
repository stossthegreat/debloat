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
import '../../../services/review_prompt_service.dart';
import '../../../services/share_service.dart';
import '../../../services/user_memory.dart';
import '../../../services/villain/villain_api.dart';
import '../../../theme/auralay_app_colors.dart';
import '../../../theme/auralay_app_typography.dart';
import '../../../widgets/common/mirrorly_components.dart';
import '../../../widgets/debug_panel.dart';
import '../../../widgets/safe_close_button.dart';
import '../arena/arena_scenes_screen.dart';

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
  /// When true, the screen renders as the GAME tab body — no close
  /// button, no picker phase. INTO YOU is auto-loaded as the default
  /// persona; a "CHANGE CHARACTER" chip + "ARENA" button replace the
  /// default chrome. The session lifecycle (tap-and-hold, scoring,
  /// Lucien step-in) behaves identically to the standalone push.
  final bool tabMode;
  const FreeFlowScreen({super.key, this.tabMode = false});

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
  /// The realtime WS session. NOT final — we recreate the instance
  /// every time _goLive runs so each persona switch gets a clean
  /// session lifecycle (server fires session.created → we send
  /// session.update with the new persona → server fires
  /// session.updated → THEN we accept audio). Reusing the original
  /// instance leaked old internal state into the new connection so
  /// the second persona never received responses (the 03:22 COLD
  /// trace showed connect+commit but no response.created).
  RealtimeSession _session = RealtimeSession();
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
  /// True once the user has held the orb for the first time. The
  /// session clock only starts ticking on that first press — sitting
  /// on the screen reading the scenario shouldn't burn seconds.
  bool _clockStarted = false;
  /// True once the tab-mode auto-start has fired. Prevents the
  /// addPostFrameCallback from firing _goLive twice if the framework
  /// rebuilds the screen before the first frame settles (the source
  /// of the "now it works, now it doesn't" intermittent breakage).
  bool _tabAutoStartFired = false;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    WakelockPlus.enable();
    // GAME-tab mode: auto-pick INTO YOU and go straight into the live
    // circle so the user lands on the recording orb the moment they
    // open the tab. They can switch character via the top-left chip.
    if (widget.tabMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _tabAutoStartFired) return;
        _tabAutoStartFired = true;
        final defaultVibe = _vibes.firstWhere(
          (v) => v.key == 'into_you',
          orElse: () => _vibes.first,
        );
        // ignore: discarded_futures
        _goLive(defaultVibe);
      });
    }
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
    // No in-flight guard here — _switchCharacter explicitly tears
    // the previous session down before calling this, and blocking
    // a legitimate restart while the OLD _goLive is still awaiting
    // its network round-trip was what made CHANGE CHARACTER
    // silently leave the user in connecting state (build 124
    // regression). Tab-mode auto-start double-fire is handled by
    // _tabAutoStartFired in initState.
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

      // 2) Mint a FRESH RealtimeSession for this persona — never reuse
      //    the previous one. Reusing leaked state across personas (the
      //    second persona connected but server never responded — see
      //    debug trace). Tell the old one to die in the background.
      // ignore: discarded_futures
      _session.close();
      _session = RealtimeSession();
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
      // Don't start the session clock here — the user hasn't pressed
      // to talk yet. The clock kicks off the first time they hold
      // the orb so sitting on the screen reading the scenario
      // doesn't burn their three minutes.
      setState(() => _phase = _Phase.live);
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
      // Queue drained. Playback has actually finished — flip the
      // speaking flag NOW (not on ResponseDone, which fires when the
      // server stops generating, often several seconds before the
      // audio finishes playing out of the device speaker). The
      // SERVER-DONE-too-early flip is what made her face flash up
      // in the orb for a split second then vanish while she was
      // still talking.
      if (_herSpeaking && !_responseActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_disposed && mounted && _pcmQueue.isEmpty && !_responseActive) {
            setState(() => _herSpeaking = false);
          }
        });
      }
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
      // DO NOT flip _herSpeaking here. ResponseDone means the server
      // stopped generating — the audio it produced is still queued in
      // _pcmQueue and playing out of the device speaker for several
      // more seconds. The orb stays on her face until _pcmQueue
      // actually drains in _onPcmFeed.
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
    // First press kicks off the session clock. Subsequent holds
    // don't restart it — the 3-minute window keeps draining as
    // expected once the user has chosen to engage.
    if (!_clockStarted) {
      _clockStarted = true;
      _startClock();
    }
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
      // Mark active speaker = Lucien. The orb picks his portrait off
      // this flag instead of _vibe so his face is in the circle the
      // moment he opens his mouth, not the woman's.
      _herSpeaking = true;
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
      // Persist FIRST so the pref is on disk before any animation
      // tears the screen down. Awaited rather than fire-and-forget —
      // a fast back-tap was beating the SharedPreferences write and
      // the Ascend GAME pillar stayed at zero.
      await _persistGame(score.score);
      if (_disposed || !mounted) return;
      setState(() {
        _result = score;
        _phase = _Phase.scored;
      });
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

  /// Best-of update of the GAME pillar score + stamp today as the
  /// last GAME completion day. FreeFlowScore is 0..10 — multiply by
  /// 10 to match the 0..100 storage band used by the LOOKS + AURA
  /// pillars. Today\'s YMD stamp powers the Today\'s Ascension card
  /// tick on the Ascend tab.
  Future<void> _persistGame(int scoreOutOfTen) async {
    final prefs = await SharedPreferences.getInstance();
    final next = (scoreOutOfTen * 10).clamp(0, 100);
    // Always write the LATEST score so the home pillar reflects this
    // session — not the user\'s all-time best, which made the home
    // page feel stuck. Best is kept under a separate key for any
    // future share / progress surface.
    await prefs.setInt('game_score', next);
    final prev = prefs.getInt('game_score_best') ?? 0;
    if (next > prev) await prefs.setInt('game_score_best', next);
    final now = DateTime.now();
    await prefs.setInt(
      'game_done_ymd',
      now.year * 10000 + now.month * 100 + now.day,
    );
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
    _clock?.cancel();
    _createTimer?.cancel();
    // Mark Game milestone for the App Store review prompt.
    // ignore: discarded_futures
    ReviewPromptService.markFreeFlowDone();
    if (widget.tabMode) {
      // In tab mode there's no route to pop. From a DONE / scored
      // state we restart with the same vibe so the user lands back
      // on the live orb ready to go. From an ERROR / stuck state we
      // tear the session down and fall back to the picker so the
      // user can choose a different character instead of looping
      // _goLive on a vibe that just failed.
      if (_phase == _Phase.error) {
        _resetToPicker();
      } else {
        _restartTabSession();
      }
      return;
    }
    safePop(context);
  }

  /// Tab-mode safety net — tear the session down and drop the user on
  /// the picker. Used when an error / stuck connect leaves them with
  /// nothing to interact with. The picker is the existing _buildPicker
  /// rendered by setting phase = _Phase.pick.
  void _resetToPicker() {
    _eventSub?.cancel();
    _micSub?.cancel();
    // ignore: discarded_futures
    _recorder.stop();
    // ignore: discarded_futures
    _session.close();
    if (!mounted) return;
    setState(() {
      _phase         = _Phase.pick;
      _vibe          = null;
      _error         = '';
      _transcript.clear();
      _herCaption    = '';
      _youCaption    = '';
      _herSpeaking   = false;
      _holding       = false;
      _result        = null;
      _remaining     = _sessionSeconds;
      _clockStarted  = false;
    });
  }

  /// Tab-mode reset — tear the current session down and spin up a
  /// fresh INTO YOU session so the orb is ready again. Used by DONE
  /// + RUN IT BACK on the scorecard since neither has a screen to
  /// pop to when the GAME tab IS Free Flow.
  Future<void> _restartTabSession() async {
    final v = _vibe ?? _vibes.firstWhere(
      (x) => x.key == 'into_you',
      orElse: () => _vibes.first,
    );
    _clock?.cancel();
    _createTimer?.cancel();
    _eventSub?.cancel();
    _micSub?.cancel();
    // Fire-and-forget teardown — see _switchCharacter for why.
    // ignore: discarded_futures
    _recorder.stop();
    // ignore: discarded_futures
    _session.close();
    _pcmQueue.clear();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.connecting;
      _transcript.clear();
      _herCaption  = '';
      _youCaption  = '';
      _herSpeaking = false;
      _holding     = false;
      _result      = null;
      _remaining   = _sessionSeconds;
      _clockStarted = false;
    });
    await _goLive(v);
  }

  /// GAME tab — open the arena scene picker. Pushes on top of the
  /// tab so the Free Flow session stays alive in the background; on
  /// pop the user lands back on the live circle.
  void _openArena() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ArenaScenesScreen(),
    ));
  }

  /// GAME tab — character switcher. Shows a modal bottom sheet
  /// listing every vibe; on selection we tear the current session
  /// down and start a fresh one with the new persona, so the user
  /// can swap mid-conversation without leaving the tab.
  Future<void> _showCharacterSheet() async {
    HapticFeedback.selectionClick();
    final picked = await showModalBottomSheet<_Vibe>(
      context: context,
      backgroundColor: AppColors.surface1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CharacterPickerSheet(
        current: _vibe,
        onPicked: (v) => Navigator.of(ctx).pop(v),
      ),
    );
    if (!mounted || picked == null) return;
    if (_vibe?.key == picked.key) return; // no change
    await _switchCharacter(picked);
  }

  /// Tear the running session down + spin up a new one as [vibe].
  /// Used by the tab-mode change-character flow only.
  Future<void> _switchCharacter(_Vibe vibe) async {
    _clock?.cancel();
    _createTimer?.cancel();
    _eventSub?.cancel();
    _micSub?.cancel();
    // Fire-and-forget the teardown. Awaiting close() on a RealtimeSession
    // that's still mid-connect can hang forever (the WS handshake never
    // completes because we just told it to die) — that's what broke even
    // INTO YOU in build 126. Just clear the playback queue so the new
    // persona doesn't inherit tail bytes.
    // ignore: discarded_futures
    _recorder.stop();
    // ignore: discarded_futures
    _session.close();
    _pcmQueue.clear();
    if (!mounted) return;
    setState(() {
      _vibe = vibe;
      _phase = _Phase.connecting;
      _transcript.clear();
      _herCaption = '';
      _youCaption = '';
      _herSpeaking = false;
      _holding = false;
      _result = null;
      _remaining = 180;
      _clockStarted = false;
    });
    await _goLive(vibe);
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
                    // Picker close button is hidden in tab mode (the
                    // tab IS the page — there's nowhere to close to).
                    if (!widget.tabMode) const SafeCloseButton(),
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
              // CHANGE CHARACTER chip in tab mode, plain label in push mode.
              widget.tabMode
                  ? _ChangeCharacterChip(
                      current: _vibe?.label ?? '',
                      onTap: _showCharacterSheet,
                    )
                  : Text(_vibe?.label ?? '',
                      style: AppTypography.label.copyWith(
                        color: AppColors.accent,
                        fontSize: 11,
                        letterSpacing: 2.8,
                        fontWeight: FontWeight.w900,
                      )),
              const Spacer(),
              // ARENA quick-route in tab mode — sits between the timer
              // and the (hidden) close button so the layout is
              // balanced and the arena is one tap away.
              if (widget.tabMode) ...[
                _ArenaPill(onTap: _openArena),
                const SizedBox(width: 8),
              ],
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
              // Close button only when the screen was pushed — in tab
              // mode there is nothing to close to (the tab is the page).
              if (!widget.tabMode)
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
                            _phase == _Phase.scoring,
                        // Active-speaker portrait. Lucien's face takes
                        // the circle the moment he steps in (phase ==
                        // lucien); otherwise the woman's portrait
                        // renders during her speaking turns.
                        imagePath: _phase == _Phase.lucien
                            ? MirrorlyAssets.lucien
                            : _vibe?.assetPath,
                      ),
                    ],
                  ),
                ),
              ),
              // Negative top margin pulls HOLD TO SPEAK back up under
              // the orb where it reads as the orb's caption, not a
              // separate row. White text + pulse animation so it
              // actively asks for attention without competing with
              // the red orb for the same colour slot.
              if (_phase == _Phase.live && !_holding && !_herSpeaking)
                Transform.translate(
                  offset: const Offset(0, -8),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'HOLD TO SPEAK',
                      textAlign: TextAlign.center,
                      style: AppTypography.label.copyWith(
                        color: Colors.white,
                        fontSize: 18,
                        letterSpacing: 4.6,
                        fontWeight: FontWeight.w900,
                      ),
                    )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .fadeIn(duration: 900.ms, curve: Curves.easeInOut)
                        .then()
                        .fade(begin: 1.0, end: 0.55,
                            duration: 900.ms, curve: Curves.easeInOut),
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
                        if (!pro) {
                          _closeScreen();
                          return;
                        }
                        // Tab mode resets inline so the user stays in
                        // the GAME tab. Standalone push replaces.
                        if (widget.tabMode) {
                          _restartTabSession();
                        } else {
                          Navigator.of(context, rootNavigator: true)
                              .pushReplacement(MaterialPageRoute(
                            builder: (_) => const FreeFlowScreen(),
                          ));
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

// ─── Tab-mode chrome widgets ─────────────────────────────────────────

/// The "CHANGE CHARACTER" chip that replaces the persona-name label
/// in tab mode. Pill-shaped, persona name + caret, opens the picker
/// bottom sheet on tap.
class _ChangeCharacterChip extends StatelessWidget {
  final String current;
  final VoidCallback onTap;
  const _ChangeCharacterChip({required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.45), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(current.isEmpty ? 'CHOOSE CHARACTER' : current,
                style: AppTypography.label.copyWith(
                  color: AppColors.red,
                  fontSize: 11, letterSpacing: 2.6,
                  fontWeight: FontWeight.w900,
                )),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.red, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// The ARENA pill — a clean one-tap route into the scripted-scene
/// picker without leaving the tab. Sits next to the timer in tab
/// mode where the close button used to live.
/// ARENA — paired with the CHANGE CHARACTER chip on the left.
/// Exact same size + outlined-red style so the two chips read as a
/// matched pair across the top chrome. Fire icon + label + arrow,
/// all red, on the dark surface1 background.
class _ArenaPill extends StatelessWidget {
  final VoidCallback onTap;
  const _ArenaPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.45), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_fire_department_rounded,
                  color: AppColors.red, size: 14),
              const SizedBox(width: 4),
              Text('ARENA',
                style: AppTypography.label.copyWith(
                  color: AppColors.red,
                  fontSize: 11, letterSpacing: 2.6,
                  fontWeight: FontWeight.w900,
                )),
              const SizedBox(width: 2),
              const Icon(Icons.arrow_forward_rounded,
                  color: AppColors.red, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modal sheet listing every persona. Tap one → returns it via pop;
/// the screen tears down the current session and starts a fresh one
/// without leaving the tab.
class _CharacterPickerSheet extends StatelessWidget {
  final _Vibe? current;
  final ValueChanged<_Vibe> onPicked;
  const _CharacterPickerSheet({
    required this.current,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.surface3,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('CHANGE CHARACTER',
                  style: AppTypography.label.copyWith(
                    color: AppColors.red,
                    fontSize: 11, letterSpacing: 2.8,
                    fontWeight: FontWeight.w800,
                  )),
                const Spacer(),
                // CANCEL — escape route for users who opened the sheet
                // by mistake. Returning null keeps the current session.
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text('CANCEL',
                      style: AppTypography.label.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11, letterSpacing: 2.4,
                        fontWeight: FontWeight.w800,
                      )),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final v in _vibes) ...[
              _CharacterPickerRow(
                vibe:     v,
                selected: v.key == current?.key,
                onTap:    () => onPicked(v),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _CharacterPickerRow extends StatelessWidget {
  final _Vibe vibe;
  final bool  selected;
  final VoidCallback onTap;
  const _CharacterPickerRow({
    required this.vibe,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppColors.red.withValues(alpha: 0.6)
                  : AppColors.surface3,
              width: selected ? 1.2 : 0.6,
            ),
          ),
          child: Row(
            children: [
              ClipOval(
                child: SizedBox(
                  width: 44, height: 44,
                  child: Image.asset(vibe.assetPath,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -0.2),
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.surface3,
                      child: const Icon(Icons.person_rounded,
                          color: AppColors.textTertiary, size: 22),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vibe.label,
                      style: AppTypography.label.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 13, letterSpacing: 2.4,
                        fontWeight: FontWeight.w900,
                      )),
                    const SizedBox(height: 3),
                    Text(vibe.tagline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12, height: 1.35,
                      )),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.red, size: 20)
              else
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textTertiary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
