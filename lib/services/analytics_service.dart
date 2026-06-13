import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../firebase_options.dart';

/// Conversion-funnel telemetry. Single chokepoint for every event we
/// log so renames / parameter changes happen in one place. Initialised
/// from main.dart on app start.
///
/// ── Event taxonomy (kept here so the dashboard never falls out of sync) ──
///
///   Lifecycle
///     app_open                       — first launch / cold start
///     app_resumed                    — return-from-background
///     app_paused      { last_screen } — backgrounded; tells us where users quit
///     screen_view     { screen_name, screen_class } — fired by the router
///                                       observer on every push/pop/replace
///
///   Onboarding
///     onb_started
///     onb_gender_picked       { gender }
///     onb_intro_step          { step }
///     onb_finished
///
///   Scan funnel
///     scan_started
///     scan_step_completed     { step }                — front/left/right
///     scan_completed
///     scan_abandoned          { phase }
///     scan_blocked_free_cap                            — free user hit the 1-scan wall
///
///   AI consent
///     ai_consent_shown/granted/denied/revoked
///
///   Report
///     report_viewed                  { variant }       — locked/full
///     report_unlock_tapped           { source }
///     report_locked_section_tapped   { section }
///     report_done_tapped                                — exit→game funnel
///
///   Paywall
///     paywall_shown                  { source }
///     paywall_dismissed              { source }
///     purchase_started/completed/failed/cancelled { tier }
///     restore_completed              { had_purchase }
///
///   Roleplay (Free Flow / Game tab)
///     freeflow_screen_viewed
///     freeflow_session_started       { vibe, is_free }
///     freeflow_first_hold
///     freeflow_session_ended         { reason, duration_sec, transcript_turns }
///                                       — reason: timer | user | cap | error | bail
///     freeflow_char_switched         { from, to }
///     freeflow_lucien_tapped         { had_first_reply, is_free }
///     freeflow_lucien_upsell_shown
///     freeflow_lucien_upsell_dismissed
///     freeflow_blocked_free_cap      { surface }       — orb | lucien
///     freeflow_voice_cap_hit
///
///   Rizz tab + screens
///     rizz_card_tapped               { card }          — screenshot | lines | chat
///     rizz_screenshot_uploaded       { has_text }
///     rizz_replies_generated         { count, is_free }
///     rizz_blocked_free_cap          { card }
///
///   Tab navigation
///     tab_opened                     { tab }
///
///   Progress
///     progress_screen_viewed
///     progress_close_tapped
///
///   Settings
///     settings_screen_viewed
///     settings_voice_cap_viewed      { used_ms, cap_ms }
///
///   Mirror chat / renders
///     chat_message_sent
///     tryon_rendered
///     maximize_rendered
///
///   Protocol / streak retention
///     protocol_started
///     protocol_day_completed         { day }
///     streak_lost                    { previous_length }
///
///   Review prompt
///     review_prompt_shown            { trigger }       — milestones | post_purchase
///     review_rating_chosen           { stars }
///     review_native_opened
///     review_dismissed
///
/// Privacy stance:
/// - No PII (no name, email, phone, location).
/// - No advertising identifiers.
/// - No third-party integrations beyond Firebase Analytics itself.
/// - The default app-install ID Firebase generates IS used (anonymous,
///   resettable from the device's privacy settings).
/// - Apple App Store privacy questionnaire: this collects "Product
///   Interaction" + "Crash Data" categories under "Analytics", linked
///   to anonymous identifier only.
class AnalyticsService {
  static FirebaseAnalytics? _fa;

  /// The most recent screen the user landed on. Updated by the router
  /// observer on every push/pop. Read by the app-lifecycle hook so the
  /// `app_paused` event carries `last_screen`, which tells us exactly
  /// where users quit. Survives the entire process lifetime.
  static String? _currentScreen;
  static String? get currentScreen => _currentScreen;
  static set currentScreen(String? v) => _currentScreen = v;

  /// Initialise Firebase + Analytics. Safe to call even if the native
  /// config files (GoogleService-Info.plist / google-services.json)
  /// aren't dropped in yet — Firebase.initializeApp() throws and we
  /// catch, leaving every event call a silent no-op until config lands.
  /// Lets local builds compile without the secrets in tree.
  static Future<void> init() async {
    try {
      // Pass FirebaseOptions explicitly. The iOS plist exists on disk
      // but isn't registered in the Xcode project as a bundle resource,
      // so the implicit Firebase.initializeApp() throws "no default
      // app configured" on iOS and analytics never wakes up. Passing
      // options matches what FlutterFire CLI generates and bypasses
      // the plist registration entirely.
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _fa = FirebaseAnalytics.instance;
      // iOS GoogleService-Info.plist ships with IS_ANALYTICS_ENABLED=false
      // (default when GA isn't toggled on at project setup). The plist
      // flag is irrelevant once Firebase initialises via FirebaseOptions,
      // but flipping the runtime flag belt-and-braces is harmless.
      await _fa!.setAnalyticsCollectionEnabled(true);
      // ignore: avoid_print
      print('[Analytics] Firebase initialised + collection enabled.');
    } catch (err) {
      // ignore: avoid_print
      print('[Analytics] Firebase init failed: $err');
      _fa = null;
    }
  }

  static FirebaseAnalytics? get instance => _fa;

  // ── Internal helper ────────────────────────────────────────────────

  static Future<void> _log(String name, [Map<String, Object?>? params]) async {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[Analytics] $name ${params ?? ''}');
    }
    final fa = _fa;
    if (fa == null) return;
    try {
      await fa.logEvent(
        name: name,
        parameters: params?.map((k, v) => MapEntry(k, v ?? ''))
            .cast<String, Object>(),
      );
    } catch (_) {/* best-effort */}
  }

  // ── Lifecycle ──────────────────────────────────────────────────────

  static Future<void> appOpen()    => _log('app_open');
  static Future<void> appResumed() => _log('app_resumed');
  static Future<void> appPaused()  =>
      _log('app_paused', {'last_screen': _currentScreen ?? 'unknown'});

  /// Fired by the router observer on every navigation. Also updates
  /// `_currentScreen` so the next `app_paused` can carry the right
  /// last-screen tag. Uses Firebase's reserved `screen_view` name so
  /// it shows up in the built-in "Screens" report.
  static Future<void> screenView(String screenName, [String? screenClass]) async {
    _currentScreen = screenName;
    final fa = _fa;
    if (fa == null) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[Analytics] screen_view $screenName ($screenClass)');
      }
      return;
    }
    try {
      await fa.logScreenView(
        screenName:  screenName,
        screenClass: screenClass ?? screenName,
      );
    } catch (_) {/* best-effort */}
  }

  // ── Onboarding ─────────────────────────────────────────────────────

  static Future<void> onbStarted() => _log('onb_started');
  static Future<void> onbGenderPicked(String gender) =>
      _log('onb_gender_picked', {'gender': gender});
  static Future<void> onbIntroStep(int step) =>
      _log('onb_intro_step', {'step': step});
  static Future<void> onbFinished() => _log('onb_finished');

  // ── Scan funnel ────────────────────────────────────────────────────

  static Future<void> scanStarted()           => _log('scan_started');
  static Future<void> scanStepCompleted(String step) =>
      _log('scan_step_completed', {'step': step});
  static Future<void> scanCompleted()         => _log('scan_completed');
  static Future<void> scanAbandoned(String phase) =>
      _log('scan_abandoned', {'phase': phase});
  static Future<void> scanBlockedFreeCap()    => _log('scan_blocked_free_cap');

  // ── AI consent ─────────────────────────────────────────────────────

  static Future<void> consentShown()   => _log('ai_consent_shown');
  static Future<void> consentGranted() => _log('ai_consent_granted');
  static Future<void> consentDenied()  => _log('ai_consent_denied');
  static Future<void> consentRevoked() => _log('ai_consent_revoked');

  // ── Report ─────────────────────────────────────────────────────────

  static Future<void> reportViewed(String variant) =>
      _log('report_viewed', {'variant': variant});
  static Future<void> reportUnlockTapped(String source) =>
      _log('report_unlock_tapped', {'source': source});
  static Future<void> reportLockedSectionTapped(String section) =>
      _log('report_locked_section_tapped', {'section': section});
  static Future<void> reportDoneTapped() => _log('report_done_tapped');

  // ── Paywall ────────────────────────────────────────────────────────

  static Future<void> paywallShown(String source) =>
      _log('paywall_shown', {'source': source});
  static Future<void> paywallDismissed(String source) =>
      _log('paywall_dismissed', {'source': source});
  static Future<void> purchaseStarted(String tier) =>
      _log('purchase_started', {'tier': tier});
  static Future<void> purchaseCompleted(String tier) =>
      _log('purchase_completed', {'tier': tier});
  static Future<void> purchaseFailed(String tier, String reason) =>
      _log('purchase_failed', {'tier': tier, 'reason': reason});
  static Future<void> purchaseCancelled(String tier) =>
      _log('purchase_cancelled', {'tier': tier});
  static Future<void> restoreCompleted(bool hadPurchase) =>
      _log('restore_completed', {'had_purchase': hadPurchase});

  // ── Roleplay (Free Flow) ───────────────────────────────────────────

  static Future<void> freeflowScreenViewed() =>
      _log('freeflow_screen_viewed');
  static Future<void> freeflowSessionStarted({
    required String vibe,
    required bool isFree,
  }) =>
      _log('freeflow_session_started', {'vibe': vibe, 'is_free': isFree});
  static Future<void> freeflowFirstHold() => _log('freeflow_first_hold');
  static Future<void> freeflowSessionEnded({
    required String reason,           // timer | user | cap | error | bail
    required int durationSec,
    required int transcriptTurns,
  }) =>
      _log('freeflow_session_ended', {
        'reason':           reason,
        'duration_sec':     durationSec,
        'transcript_turns': transcriptTurns,
      });
  static Future<void> freeflowCharSwitched(String from, String to) =>
      _log('freeflow_char_switched', {'from': from, 'to': to});
  static Future<void> freeflowLucienTapped({
    required bool hadFirstReply,
    required bool isFree,
  }) =>
      _log('freeflow_lucien_tapped', {
        'had_first_reply': hadFirstReply,
        'is_free':         isFree,
      });
  static Future<void> freeflowLucienUpsellShown() =>
      _log('freeflow_lucien_upsell_shown');
  static Future<void> freeflowLucienUpsellDismissed() =>
      _log('freeflow_lucien_upsell_dismissed');
  static Future<void> freeflowBlockedFreeCap(String surface) =>
      _log('freeflow_blocked_free_cap', {'surface': surface});
  static Future<void> freeflowVoiceCapHit() =>
      _log('freeflow_voice_cap_hit');

  // ── Rizz tab + screens ─────────────────────────────────────────────

  static Future<void> rizzCardTapped(String card) =>
      _log('rizz_card_tapped', {'card': card});
  static Future<void> rizzScreenshotUploaded({required bool hasText}) =>
      _log('rizz_screenshot_uploaded', {'has_text': hasText});
  static Future<void> rizzRepliesGenerated({
    required int count,
    required bool isFree,
  }) =>
      _log('rizz_replies_generated', {'count': count, 'is_free': isFree});
  static Future<void> rizzBlockedFreeCap(String card) =>
      _log('rizz_blocked_free_cap', {'card': card});

  // ── Tab navigation ─────────────────────────────────────────────────

  static Future<void> tabOpened(String tab) =>
      _log('tab_opened', {'tab': tab});

  // ── Progress ───────────────────────────────────────────────────────

  static Future<void> progressScreenViewed() =>
      _log('progress_screen_viewed');
  static Future<void> progressCloseTapped() =>
      _log('progress_close_tapped');
  /// Fires when any in-app SHARE button is tapped. `surface` names the
  /// origin ("progress", "freeflow", "gaze") so the funnel report can
  /// tell us which result pages are actually post-able vs. dead ends.
  static Future<void> shareTapped({required String surface}) =>
      _log('share_tapped', {'surface': surface});

  // ── Settings ───────────────────────────────────────────────────────

  static Future<void> settingsScreenViewed() =>
      _log('settings_screen_viewed');
  static Future<void> settingsVoiceCapViewed({
    required int usedMs,
    required int capMs,
  }) =>
      _log('settings_voice_cap_viewed',
          {'used_ms': usedMs, 'cap_ms': capMs});

  // ── Mirror chat / renders ──────────────────────────────────────────

  static Future<void> chatMessageSent()   => _log('chat_message_sent');
  static Future<void> tryOnRendered()     => _log('tryon_rendered');
  static Future<void> maximizeRendered()  => _log('maximize_rendered');

  // ── Protocol / streak retention ────────────────────────────────────

  static Future<void> protocolStarted() => _log('protocol_started');
  static Future<void> protocolDayCompleted(int day) =>
      _log('protocol_day_completed', {'day': day});
  static Future<void> streakLost(int previousLength) =>
      _log('streak_lost', {'previous_length': previousLength});

  // ── ImHim Keyboard ─────────────────────────────────────────────────

  /// User landed on the install/onboarding screen.
  static Future<void> keyboardInstallViewed() =>
      _log('keyboard_install_viewed');

  /// User tapped the hero tile in Rizz tab or Settings → opened install.
  static Future<void> keyboardInstallTileTapped(String source) =>
      _log('keyboard_install_tile_tapped', {'source': source});

  /// User tapped "OPEN SETTINGS" on the install screen — we deep-linked
  /// them into iOS Settings. (No way to know if they actually completed
  /// the install — iOS doesn't expose that — so this is the closest
  /// proxy to "started the install".)
  static Future<void> keyboardInstallSettingsTapped() =>
      _log('keyboard_install_settings_tapped');

  // ── Review prompt ──────────────────────────────────────────────────

  static Future<void> reviewPromptShown(String trigger) =>
      _log('review_prompt_shown', {'trigger': trigger});
  static Future<void> reviewRatingChosen(int stars) =>
      _log('review_rating_chosen', {'stars': stars});
  static Future<void> reviewNativeOpened() =>
      _log('review_native_opened');
  static Future<void> reviewDismissed() =>
      _log('review_dismissed');
}
