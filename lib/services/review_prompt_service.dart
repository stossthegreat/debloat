import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/review_prompt_dialog.dart';

/// Three-milestone gate for the App Store / Play Store review prompt.
///
/// The dialog only fires after the user has completed all three of:
///   1. First face scan + report (proves they got value from looksmax)
///   2. First Game tab Free Flow session (proves they used the voice AI)
///   3. First Eye-Contact lesson (proves they used the gaze coach)
///
/// Once a user has used the whole product, asking for a review is
/// honest. Asking sooner gets a brigade of 1-stars from people who
/// haven't seen what the app is.
///
/// The prompt fires at most ONCE per device — when the user either
/// taps Submit or Not now, [_kPrompted] flips and we never ask again.
/// This avoids hostile re-prompts that get apps removed from store
/// editorial picks.
///
/// Mark methods flip a SharedPref flag synchronously and are safe to
/// call from anywhere (including session-end / dispose flows where
/// the calling screen is about to be torn down). [maybePrompt] is the
/// UI hook — call from the home screen's initState. When all three
/// milestones are marked and we haven't asked yet, the dialog fires.
class ReviewPromptService {
  static const _kScanDone     = 'review.scan_done';
  static const _kFreeFlowDone = 'review.freeflow_done';
  static const _kEyesDone     = 'review.eyes_done';
  static const _kPrompted     = 'review.prompted';

  // ── Milestone marks (no UI) ────────────────────────────────────────────

  static Future<void> markScanDone()     => _setFlag(_kScanDone);
  static Future<void> markFreeFlowDone() => _setFlag(_kFreeFlowDone);
  static Future<void> markEyesDone()     => _setFlag(_kEyesDone);

  // ── UI hook (call from home screen initState) ──────────────────────────

  static Future<void> maybePrompt(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kPrompted) ?? false) return;
    final scan     = prefs.getBool(_kScanDone)     ?? false;
    final freeflow = prefs.getBool(_kFreeFlowDone) ?? false;
    final eyes     = prefs.getBool(_kEyesDone)     ?? false;
    if (!(scan && freeflow && eyes)) return;
    if (!context.mounted) return;
    // Brief delay so the dialog doesn't compete with first-paint
    // animations on the screen that triggered it.
    await Future.delayed(const Duration(milliseconds: 600));
    if (!context.mounted) return;
    await prefs.setBool(_kPrompted, true);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ReviewPromptDialog(),
    );
  }

  /// Wow-moment trigger — fires after a successful Pro purchase. This
  /// is the "I just paid for this and I'm excited" beat, which is the
  /// HIGHEST-converting moment for a positive rating. Same one-prompt-
  /// per-device ceiling as [maybePrompt], so a user who already saw the
  /// triple-milestone prompt won't see this one (or vice-versa).
  ///
  /// Bro v7: "after a wow moment / after a conversion — pop up with 5
  /// pressable stars, message about feedback being important, clean
  /// beautiful very cleverly placed." We let the unlock land first
  /// (1.4s delay so the user sees their purchased experience for a
  /// breath) and only THEN slide the prompt in.
  static Future<void> maybePromptAfterPurchase(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kPrompted) ?? false) return;
    if (!context.mounted) return;
    // Let the post-purchase route resolve + first paint settle so the
    // dialog feels like a thank-you, not an interruption.
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!context.mounted) return;
    await prefs.setBool(_kPrompted, true);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ReviewPromptDialog(),
    );
  }

  static Future<void> _setFlag(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
  }
}
