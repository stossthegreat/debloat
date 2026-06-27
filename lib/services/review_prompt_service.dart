import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../navigation/app_router.dart';
import '../widgets/review_prompt_dialog.dart';
import 'analytics_service.dart';

/// Single-shot store-review prompt.
///
/// v249 — bro: "where is the pop up for leaving a review bro it's
/// important man… we need it man." The previous gate required ALL
/// THREE pillars (scan + Free Flow + eyes lesson) before the dialog
/// would ever fire, so most users never saw it. Loosened to ANY ONE
/// milestone — the dialog fires the moment a user completes their
/// first scan OR first Free Flow OR first eyes lesson. Still one
/// prompt per device.
///
/// We also fixed the post-purchase bug: the paywall pushed
/// `context.go('/home')` BEFORE calling [maybePromptAfterPurchase],
/// which meant the paywall's BuildContext was already unmounted by
/// the time the 1.4s "let the wow land" delay finished. The dialog
/// silently died. v249 grabs the root navigator context off the
/// global [appRouter] AFTER the delay so it can't go stale.
class ReviewPromptService {
  static const _kScanDone     = 'review.scan_done';
  static const _kFreeFlowDone = 'review.freeflow_done';
  static const _kEyesDone     = 'review.eyes_done';
  static const _kPrompted     = 'review.prompted';

  // ── Milestone marks (no UI) ────────────────────────────────────────────

  static Future<void> markScanDone()     => _setFlag(_kScanDone);
  static Future<void> markFreeFlowDone() => _setFlag(_kFreeFlowDone);
  static Future<void> markEyesDone()     => _setFlag(_kEyesDone);

  // ── UI hook (call from home screen initState + report viewed) ─────────

  /// Fire the prompt if ANY pillar has been used and we haven't asked
  /// this device yet. Loosened from the v247 AND-gate per bro: "where
  /// is the pop up… we need it." Safe to call from anywhere — if the
  /// pref was already flipped or no pillar is yet ticked, it's a no-op.
  static Future<void> maybePrompt(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kPrompted) ?? false) return;
    final any = (prefs.getBool(_kScanDone)     ?? false)
             || (prefs.getBool(_kFreeFlowDone) ?? false)
             || (prefs.getBool(_kEyesDone)     ?? false);
    if (!any) return;
    if (!context.mounted) return;
    await Future.delayed(const Duration(milliseconds: 600));
    if (!context.mounted) return;
    await prefs.setBool(_kPrompted, true);
    // ignore: discarded_futures
    AnalyticsService.reviewPromptShown('milestone');
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ReviewPromptDialog(),
    );
  }

  /// Wow-moment trigger — fires after a successful Pro purchase. The
  /// paywall calls this AFTER `context.go(...)`, so by the time the
  /// 1.4s "let the destination paint" delay completes, the paywall's
  /// BuildContext is unmounted. v249 fix: grab the root navigator
  /// context off the global appRouter AFTER the delay so the dialog
  /// has a live context to mount against.
  static Future<void> maybePromptAfterPurchase(BuildContext _) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kPrompted) ?? false) return;
    await Future.delayed(const Duration(milliseconds: 1400));
    final ctx = appRouter.routerDelegate.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await prefs.setBool(_kPrompted, true);
    // ignore: discarded_futures
    AnalyticsService.reviewPromptShown('post_purchase');
    await showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => const ReviewPromptDialog(),
    );
  }

  /// Wow-moment trigger — fires after the report screen finishes
  /// rendering the first scan score. This is THE emotional peak: the
  /// user just saw their face graded and is leaning in. v249 — added
  /// per bro: "good apps have it it pops up with five stars."
  static Future<void> maybePromptAfterReport(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kPrompted) ?? false) return;
    if (!context.mounted) return;
    await Future.delayed(const Duration(milliseconds: 1800));
    final ctx = context.mounted
        ? context
        : appRouter.routerDelegate.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await prefs.setBool(_kPrompted, true);
    // ignore: discarded_futures
    AnalyticsService.reviewPromptShown('post_report');
    await showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => const ReviewPromptDialog(),
    );
  }

  /// Wow-moment trigger — fires on the first Game result, the moment
  /// Lucien drops his score + verdict card. The second aha moment after
  /// the scan reveal. One-prompt-per-device still holds: whichever aha
  /// moment the user reaches first claims the single prompt, so a user
  /// who already rated after their scan won't be re-asked here.
  static Future<void> maybePromptAfterGame(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kPrompted) ?? false) return;
    if (!context.mounted) return;
    await Future.delayed(const Duration(milliseconds: 1800));
    final ctx = context.mounted
        ? context
        : appRouter.routerDelegate.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await prefs.setBool(_kPrompted, true);
    // ignore: discarded_futures
    AnalyticsService.reviewPromptShown('post_game');
    await showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => const ReviewPromptDialog(),
    );
  }

  static Future<void> _setFlag(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
  }
}
