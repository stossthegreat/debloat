/// AURALAY dev flags + build-time constants.
///
/// Single source of truth for anything we want to flip without chasing it
/// through ten files: the Diablo unlock password, the backend base URL,
/// whether to bypass paywalls in dev, etc.
abstract final class AuralayDevFlags {
  /// Creator unlock password — the ONE master switch.
  ///
  /// Reached via Settings → CREATOR, or by tapping the AURALAY wordmark
  /// 5 times in 3 seconds. One password does everything: flips Lucien and
  /// the women into the savage, roasting persona across Free Flow / Arena
  /// / Council AND unlocks all Diablo content. Still policy-bounded
  /// server-side (savage/crude yes; sexually explicit + real-world
  /// coercion no — that's what keeps the OpenAI key alive). Change before
  /// ship.
  static const creatorPassword = 'LET.HIM.COOK';

  /// Backend base URL — the Railway service that owns the OpenAI key.
  /// Default is the live production deployment. Override at build time
  /// with --dart-define=AURALAY_API=https://other-url.up.railway.app
  /// (useful for hitting a staging service from a TestFlight build).
  ///
  /// If this string is empty at runtime, the app falls back to local
  /// stubs (heuristic scorer + canned Diablo lines) so it never goes dark.
  static const apiBaseUrl = String.fromEnvironment(
    'AURALAY_API',
    defaultValue: 'https://auralayai-production-65c2.up.railway.app',
  );

  /// True when [apiBaseUrl] is set — the call sites read this to decide
  /// between the real Railway client and the local stub.
  static bool get hasBackend => apiBaseUrl.isNotEmpty;

  /// True in dev to skip purchase checks so every gated feature opens.
  /// Flip false before App Store / Play Store submission.
  static const kBypassPaywall = false;

  /// Master switch for the in-session debug overlay (bottom-left bug icon
  /// + log strip) on every screen. OFF for production. Flip true to bring
  /// it back on every screen at once for diagnosing live sessions.
  /// `final` (not `const`) so toggling it doesn't dead-code the panel.
  static final bool showDebugOverlay = false;
}
