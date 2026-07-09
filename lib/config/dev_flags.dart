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
///
/// v186 — flipped to TRUE per bro: "make it all free right now this
/// is testing." Everything Pro is unlocked across the whole app
/// while we shake the keyboard extension out + verify the new
/// funnels work end-to-end. Flip back to FALSE before the next
/// public TestFlight cycle that gates conversion.
///   · Free-tier scan, render, rizz, lines, chat, freeflow, lucien
///     gates all skip when this is true.
///   · LocalStoreService.setSubscribed(true) runs on app launch in
///     main.dart, so any code reading isSubscribed() returns true.
///
/// v225 — flipped back to FALSE. v224 killed the free roleplay grace
/// window + wired the Weekly subscription tier; both are no-ops while
/// the bypass is on. Every paywall is now live:
///   · Scan       — 1 free, then paywall every attempt
///   · Roleplay   — paywall on every free user's hold (no free 60s)
///   · Lucien     — paywall on step-in for free users
///   · Renders    — Pro-only on every attempt
///   · Rizz       — 1 free screenshot reply, then paywall;
///                  Lines + Chat are Pro-only outright
///   · Lessons    — Pro-only from Day 1
const kBypassPaywall = false;

/// Human-readable build tag shown tiny on the paywall so we can instantly
/// tell which build is actually installed on-device (TestFlight lag has
/// repeatedly made us debug a stale build). Bump this with every pubspec
/// build-number bump.
const kBuildTag = 'b345';
