import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

/// Conversion-funnel telemetry. Single chokepoint for every event we
/// log so renames / parameter changes happen in one place. Initialised
/// from main.dart on app start.
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

  /// Initialise Firebase + Analytics. Safe to call even if the native
  /// config files (GoogleService-Info.plist / google-services.json)
  /// aren't dropped in yet — Firebase.initializeApp() throws and we
  /// catch, leaving every event call a silent no-op until config lands.
  /// Lets local builds compile without the secrets in tree.
  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
      _fa = FirebaseAnalytics.instance;
      // iOS GoogleService-Info.plist ships with IS_ANALYTICS_ENABLED=false
      // (Firebase Console default when GA isn't toggled on at project setup).
      // Force collection on at runtime so events actually flow without
      // needing to re-download the plist.
      await _fa!.setAnalyticsCollectionEnabled(true);
      if (kDebugMode) {
        // ignore: avoid_print
        print('[Analytics] Firebase initialised + collection enabled.');
      }
    } catch (err) {
      // ignore: avoid_print
      print('[Analytics] Firebase not configured yet: $err');
      _fa = null;
    }
  }

  static FirebaseAnalytics? get instance => _fa;

  // ── Event helpers ───────────────────────────────────────────────────

  static Future<void> _log(String name, [Map<String, Object?>? params]) async {
    final fa = _fa;
    if (fa == null) return;
    try {
      await fa.logEvent(
        name: name,
        parameters: params?.map((k, v) => MapEntry(k, v ?? '')).cast<String, Object>(),
      );
    } catch (_) {/* best-effort */}
  }

  // First-launch / app open.
  static Future<void> appOpen() => _log('app_open');

  // Scan funnel.
  static Future<void> scanStarted()           => _log('scan_started');
  static Future<void> scanCompleted()         => _log('scan_completed');
  static Future<void> scanAbandoned(String phase) =>
      _log('scan_abandoned', {'phase': phase});

  // AI consent funnel (the App Store gate that's caused us so much
  // pain — track grant rate so we know if the dialog copy is leaking).
  static Future<void> consentShown()   => _log('ai_consent_shown');
  static Future<void> consentGranted() => _log('ai_consent_granted');
  static Future<void> consentDenied()  => _log('ai_consent_denied');
  static Future<void> consentRevoked() => _log('ai_consent_revoked');

  // Paywall funnel.
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

  // Tab navigation.
  static Future<void> tabOpened(String tab) =>
      _log('tab_opened', {'tab': tab});

  // Mirror chat / try-on engagement.
  static Future<void> chatMessageSent()   => _log('chat_message_sent');
  static Future<void> tryOnRendered()     => _log('tryon_rendered');
  static Future<void> maximizeRendered()  => _log('maximize_rendered');

  // Protocol / streak retention.
  static Future<void> protocolStarted() => _log('protocol_started');
  static Future<void> protocolDayCompleted(int day) =>
      _log('protocol_day_completed', {'day': day});
  static Future<void> streakLost(int previousLength) =>
      _log('streak_lost', {'previous_length': previousLength});
}
