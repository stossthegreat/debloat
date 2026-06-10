// ───────────────────────────────────────────────────────────────────────────
//  DEV FLAGS
//  Single source of truth for dev-only overrides. Flip these back before
//  shipping — every release build should compile with all flags false.
// ───────────────────────────────────────────────────────────────────────────

/// When true:
///   · The app force-sets the local subscribed flag to true at launch, so
///     every in-app gate that reads LocalStoreService.isSubscribed() passes.
///   · The post-scan paywall gate skips straight to /report.
///   · The "Upgrade" chip in the home header is hidden.
///   · The "Upgrade" tile in settings is hidden.
///   · Onboarding ends on /home instead of /paywall.
///   · PaywallScreen, if opened manually, auto-routes back to /home.
///
/// **FLIP THIS TO FALSE BEFORE SHIPPING.**
///
/// v155 — flipped back to FALSE per bro: "add the lock for
/// subscription on it again the whole app as we previously planned."
/// Testing window for the new rizz tone presets + vision wiring is
/// closed; gates are live again:
///   · 2 scans / week (free tier)
///   · 10 Mirror renders / month (free tier)
///   · 1 free rizz screenshot, then paywall
///   · LINES + Chat with Mirrorly fully paywalled
///   · Game tab: 1 free Free-Flow speak, then paywall on SPEAK.
const kBypassPaywall = false;
