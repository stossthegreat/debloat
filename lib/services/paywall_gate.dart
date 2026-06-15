import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/dev_flags.dart';
import 'local_store_service.dart';
import 'purchase_service.dart';

/// Centralised paywall gating. Bro v4 corrected matrix:
///
///   FREE TIER (non-pro):
///     · 0 scans                  (NOT "2 free a week" — none)
///     · 0 Mirror renders         (NOT "10 free a month" — none)
///     · 0 streaks / protocols    (Looks streak system locked)
///     · 1 free Rizz screenshot   (then paywall)
///     · 1 free Game roleplay     (then paywall on SPEAK)
///     · 0 Lines, 0 Rizz Chat     (paywalled outright)
///
///   PRO TIER (subscriber):
///     · 2 scans / week
///     · 10 Mirror renders / month
///     · Unlimited streaks / protocols
///     · Unlimited Rizz screenshot, Lines, Chat, roleplay
///
/// The previous wording had it backwards — "2 scans / week" was
/// implemented as a FREE allowance with pro being unlimited. Bro:
/// "there is no free scans — there's only two scans a week for
/// PAYING users." Fixed throughout.
class PaywallGate {
  /// True when the user has paid (or kBypassPaywall is on for dev).
  ///
  /// Bro: "I've got a sub and it's locking me out of the two rizzes."
  /// Root cause: the local SharedPreferences flag can lag behind
  /// RevenueCat in TestFlight / sandbox / cold-network scenarios. So
  /// every gate check now asks RevenueCat live first; the cache is the
  /// fallback when RC isn't reachable. PurchaseService.isProLive()
  /// also repaints the local cache as a side-effect so subsequent
  /// synchronous reads (e.g. settings tile) agree.
  ///
  /// v242 FIX — the live RC check is wrapped in a 2-second timeout
  /// because Purchases.getCustomerInfo() can hang on TestFlight /
  /// sandbox / cold-network calls. Without this ceiling _goLive (which
  /// awaits isPro() before the WebSocket connect) would sit forever
  /// at _Phase.connecting and force a hard-close — exactly the
  /// "next-character-stays-on-connecting" bug bro flagged. Auralay
  /// doesn't have this paywall gate, which is why Auralay never hit
  /// the same wall.
  static Future<bool> isPro() async {
    if (kBypassPaywall) return true;
    try {
      final live = await PurchaseService.isProLive()
          .timeout(const Duration(seconds: 2));
      if (live != null) return live;
    } catch (_) {
      // Timeout / network refusal — fall through to the cached value.
    }
    return LocalStoreService.isSubscribed();
  }

  // ── Scan gate ───────────────────────────────────────────────────────────
  /// Free users: every scan attempt is capped.
  /// Pro users: 2 scans per week.
  static Future<bool> scanCapReached() async {
    if (!(await isPro())) return true; // free → no scans, ever.
    final used = await LocalStoreService.scansThisWeek();
    return used >= LocalStoreService.kScansPerWeek;
  }

  /// Scans remaining THIS WEEK for the current user.
  ///   · Pro under quota → positive int (2 − used).
  ///   · Pro over quota  → 0.
  ///   · Free user       → 0 (any attempt routes to paywall).
  static Future<int> scansRemainingThisWeek() async {
    if (!(await isPro())) return 0;
    final used = await LocalStoreService.scansThisWeek();
    final left = LocalStoreService.kScansPerWeek - used;
    return left < 0 ? 0 : left;
  }

  // ── Mirror render gate ──────────────────────────────────────────────────
  /// Free users: every Mirror render attempt is capped.
  /// Pro users: 10 renders per calendar month.
  static Future<bool> renderCapReached() async {
    if (!(await isPro())) return true; // free → no renders, ever.
    final used = await LocalStoreService.mirrorRendersThisWeek();
    return used >= LocalStoreService.kRendersPerWeek;
  }

  // ── Rizz screenshot gate ────────────────────────────────────────────────
  /// v238 — Pro users get 15 screenshot rizz analyses per week
  /// (resets Monday). Free users keep the legacy "1 free ever" rule
  /// so the first-time conversion funnel still works.
  static Future<bool> rizzScreenshotCapReached() async {
    if (!(await isPro())) {
      return LocalStoreService.rizzScreenshotFreeUsed();
    }
    return LocalStoreService.screenshotRizzCapReached();
  }

  // ── Rizz LINES + CHAT (paywalled outright for free users) ─────────────
  /// Bro: "the other two rizz cards i.e lines and chat are locked."
  /// No free preview. Pro only.
  static Future<bool> rizzLinesLocked() async => !(await isPro());
  static Future<bool> rizzChatLocked()  async => !(await isPro());

  // ── Looks streaks / protocols (Pro-only) ──────────────────────────────
  /// Bro v4: "they can't use the streaks for looks unless they pay."
  /// The 60-day protocol system + the streak chip + protocol check-ins
  /// are all Pro-only. Free users see the cards but tapping commit
  /// routes to the paywall.
  static Future<bool> streaksLocked() async => !(await isPro());

  // ── Open paywall + re-check on return ──────────────────────────────────
  /// Push the paywall onto the navigation stack with a contextual
  /// `source` for analytics. Returns true if the user came back as pro.
  static Future<bool> open(BuildContext context, {required String source}) async {
    await context.push('/paywall', extra: {'source': source});
    if (!context.mounted) return false;
    return isPro();
  }
}
