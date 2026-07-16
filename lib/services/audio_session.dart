import 'package:audioplayers/audioplayers.dart';

/// Shared iOS / Android audio-session configuration.
///
/// Two related iOS bugs this helper handles:
///
///   1. "Recording too short / 28-byte file" — audioplayers holds
///      the session in playback mode, record_darwin's setCategory
///      swap silently fails, recorder writes an m4a header with
///      zero samples behind it. Fix: [prepareForRecording] does a
///      release-and-reassert dance so the record plugin's
///      setCategory actually moves the session.
///
///   2. "Failed to start recording, setCategory, OSStatus 561017449"
///      — surfaces in two ways:
///
///        a) v287 — option-set mismatch between audioplayers
///           (had mixWithOthers) and record_darwin (didn't). iOS
///           refused the implicit downgrade mid-session. Fixed by
///           aligning the option sets so neither configurator
///           tries to remove a flag the other set.
///
///        b) v307 — `!pri` insufficient-priority. Another session
///           on the device (Spotify in non-mixable mode, an active
///           phone call, Siri, CarPlay) holds higher priority and
///           iOS denies our claim. There's nothing we can do
///           server-side to MAKE iOS let go of that session — but
///           we can detect the error, run a recovery dance
///           (switch to ambient briefly to let our prior claim
///           release, then re-assert playAndRecord with
///           mixWithOthers so we're a polite citizen), and retry
///           the recorder. If the retry ALSO fails the conflict
///           is OS-level — surface
///           [priorityConflictMessage] to the user so they know
///           to pause the other audio.
abstract final class AudioSession {
  /// Which context is currently asserted. Tracked by KIND (not a bare
  /// bool) so a playback-only screen and a record-capable screen can
  /// hand the session back and forth — each configure call re-asserts
  /// only when the active kind differs.
  static _SessionKind _active = _SessionKind.none;

  /// One-time setup at the top of any screen that records.
  static Future<void> configureForPlayAndRecord() async {
    if (_active == _SessionKind.playAndRecord) return;
    try {
      await AudioPlayer.global.setAudioContext(_playAndRecordContext());
      _active = _SessionKind.playAndRecord;
    } catch (_) {
      // Will retry next time.
    }
  }

  /// Setup for screens that PLAY voice but never touch the mic (the
  /// Aura gaze lessons: camera + TTS only). v362 — these screens used
  /// to assert playAndRecord, which runs the voice-call processing
  /// chain: quieter output on iOS, and on Android it routed the TTS
  /// through the VOICE-CALL stream instead of media — "the voice is
  /// proper low, can barely hear it". Pure playback = full media
  /// loudness on both platforms.
  static Future<void> configureForPlayback() async {
    if (_active == _SessionKind.playback) return;
    try {
      await AudioPlayer.global.setAudioContext(_playbackContext());
      _active = _SessionKind.playback;
    } catch (_) {
      // Will retry next time.
    }
  }

  /// Force the next configure call to actually run setAudioContext
  /// again instead of short-circuiting on the cached kind. Use when
  /// tearing down a screen that owns the mic / speaker so the next
  /// screen\'s configure re-asserts the session context.
  static void invalidate() {
    _active = _SessionKind.none;
  }

  /// Force the session into a clean record-capable state RIGHT BEFORE
  /// recorder.start(). The two-step (stop the player, give iOS ~250ms,
  /// re-assert the category) is what stops record_darwin writing a
  /// 28-byte ghost file because iOS hasn't actually handed it the mic.
  static Future<void> prepareForRecording(AudioPlayer player) async {
    try { await player.stop(); } catch (_) {}
    // Give iOS a beat to release the playback session.
    await Future.delayed(const Duration(milliseconds: 250));
    try {
      await AudioPlayer.global.setAudioContext(_playAndRecordContext());
    } catch (_) {}
    // Second short pause so the new category is fully applied before
    // record_darwin tries to set it again from Swift.
    await Future.delayed(const Duration(milliseconds: 100));
  }

  /// v307 — recover from an iOS InsufficientPriority (!pri / OSStatus
  /// 561017449) error thrown by recorder.start[Stream]. Forces a
  /// release-and-reassert dance:
  ///   1. Switch the audioplayers context to a neutral ambient
  ///      category so iOS releases our prior playAndRecord claim.
  ///   2. Wait 400ms for actual deactivation.
  ///   3. Re-assert playAndRecord.
  ///   4. Brief settle delay.
  /// Caller retries the recorder ONCE after this returns.
  static Future<void> recoverFromPriorityConflict() async {
    _active = _SessionKind.none;
    try {
      await AudioPlayer.global.setAudioContext(_ambientContext());
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 400));
    try {
      await AudioPlayer.global.setAudioContext(_playAndRecordContext());
      _active = _SessionKind.playAndRecord;
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 150));
  }

  /// True if a PlatformException from record.start is the iOS
  /// InsufficientPriority error. Match on the OSStatus number,
  /// the symbolic name, OR the record-plugin setCategory string
  /// (older record_darwin builds didn't surface the symbolic name).
  static bool isInsufficientPriorityError(Object err) {
    final s = err.toString();
    return s.contains('561017449') ||
        s.contains('InsufficientPriority') ||
        (s.contains('setCategory') && s.contains('record'));
  }

  /// User-facing copy when recovery itself fails — the conflict is
  /// OS-level and we can't break it from inside the app. Surface
  /// this via a snackbar / inline error so the user knows WHY they
  /// can't record and what to do about it.
  static const String priorityConflictMessage =
      "Another app is using your microphone or playing audio. "
      "Pause Spotify, Apple Music, your phone call, or Siri, "
      "then try again.";

  static AudioContext _playAndRecordContext() => AudioContext(
        iOS: AudioContextIOS(
          // Options aligned with what record_darwin uses internally
          // so the v287 mid-session-downgrade error doesn't recur.
          // mixWithOthers is OFF here because record_darwin sets
          // categoryOptions WITHOUT mixWithOthers; aligning kills
          // the swap.
          category: AVAudioSessionCategory.playAndRecord,
          options: const {
            AVAudioSessionOptions.defaultToSpeaker,
            AVAudioSessionOptions.allowBluetooth,
            AVAudioSessionOptions.allowBluetoothA2DP,
          },
        ),
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.speech,
          usageType: AndroidUsageType.voiceCommunication,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      );

  /// Full-loudness media playback — no mic claim, no voice-call
  /// processing. iOS `playback` always routes to the loud speaker;
  /// Android uses the MEDIA stream (the volume rocker most users
  /// actually have turned up), not the in-call stream.
  static AudioContext _playbackContext() => AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {},
        ),
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: true,
          contentType: AndroidContentType.speech,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      );

  /// Neutral ambient context used only by [recoverFromPriorityConflict]
  /// to give iOS a clean release before we re-claim playAndRecord.
  static AudioContext _ambientContext() => AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.ambient,
          options: const {
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: false,
          contentType: AndroidContentType.unknown,
          usageType: AndroidUsageType.unknown,
          audioFocus: AndroidAudioFocus.none,
        ),
      );
}

/// Which audio-session shape is currently asserted via
/// AudioPlayer.global.setAudioContext.
enum _SessionKind { none, playback, playAndRecord }
