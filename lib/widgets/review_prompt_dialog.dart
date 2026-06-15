import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:in_app_review/in_app_review.dart';

import '../services/analytics_service.dart';

/// v249 — smooth two-stage iOS-style review prompt.
///
/// Bro: "look smooth as hell, drives comments, does it after aha
/// moments." The previous dark Playfair editorial card with a comment
/// text field felt like a long-form survey; bro's reference screens
/// (LooksMax AI) use the compact pre-prompt pattern every high-rated
/// iOS app uses:
///
///   Stage 1 — "Enjoying ImHim? Tap a star to rate it on the App
///             Store." + a row of empty stars + "Not Now."
///   Stage 2 — once any star is tapped: filled orange-gold stars +
///             "Thanks for your feedback. You can also write a
///             review." + "Write a Review" (primary) + "OK"
///             (secondary).
///
/// "Write a Review" hands off to InAppReview.requestReview() which
/// surfaces Apple's native StoreKit sheet on iOS / Google's in-app
/// review on Android — that's the screen the reference image 3
/// shows. Both stores resolve the app id internally; no App Store
/// ID config needed here.
///
/// Visual language deliberately leaves the dark editorial Mirrorly
/// chrome behind. iOS users recognise this floating white-card
/// pattern as "the rate prompt", which lifts tap-through.
class ReviewPromptDialog extends StatefulWidget {
  const ReviewPromptDialog({super.key});

  @override
  State<ReviewPromptDialog> createState() => _ReviewPromptDialogState();
}

class _ReviewPromptDialogState extends State<ReviewPromptDialog> {
  int _rating = 0;
  bool _opening = false;

  void _onStarTap(int stars) {
    HapticFeedback.selectionClick();
    setState(() => _rating = stars);
    // ignore: discarded_futures
    AnalyticsService.reviewRatingChosen(stars);
  }

  Future<void> _writeReview() async {
    if (_opening) return;
    setState(() => _opening = true);
    HapticFeedback.mediumImpact();
    try {
      final reviewer = InAppReview.instance;
      if (await reviewer.isAvailable()) {
        // ignore: discarded_futures
        AnalyticsService.reviewNativeOpened();
        await reviewer.requestReview();
      }
    } catch (_) {/* best effort */}
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _ok() {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
  }

  void _notNow() {
    HapticFeedback.selectionClick();
    // ignore: discarded_futures
    AnalyticsService.reviewDismissed();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tapped = _rating > 0;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 36),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
        decoration: BoxDecoration(
          color: const Color(0xFFEDEDED),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/icons/appstore.png',
                    width: 44, height: 44, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      width: 44, height: 44),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tapped
                          ? 'Thanks for your feedback.'
                          : 'Enjoying ImHim?',
                        style: GoogleFonts.inter(
                          color: Colors.black,
                          fontSize: 17, fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tapped
                          ? 'You can also write a review.'
                          : 'Tap a star to rate it on the App Store.',
                        style: GoogleFonts.inter(
                          color: Colors.black.withValues(alpha: 0.65),
                          fontSize: 13.5, fontWeight: FontWeight.w400,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Stars row — outline when untapped, filled gold when tapped.
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  final filled = i < _rating;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _opening ? null : () => _onStarTap(i + 1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Icon(
                        filled
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                        size: 34,
                        color: filled
                          ? const Color(0xFFFFB100)
                          : const Color(0xFF3B82F6),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 14),

            // Action row depends on stage.
            if (!tapped)
              _PillButton(
                label: 'Not Now',
                bold: false,
                onTap: _notNow,
              )
            else ...[
              _PillButton(
                label: 'Write a Review',
                bold: true,
                loading: _opening,
                onTap: _writeReview,
              ),
              const SizedBox(height: 8),
              _PillButton(
                label: 'OK',
                bold: false,
                onTap: _ok,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// iOS-style pill button — light grey background, black text. Used
/// for both the Not Now / OK secondary actions and the Write a Review
/// primary action (primary uses w700, secondary uses w500).
class _PillButton extends StatelessWidget {
  final String label;
  final bool bold;
  final bool loading;
  final VoidCallback onTap;
  const _PillButton({
    required this.label,
    required this.bold,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Center(
              child: loading
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.black))
                : Text(label,
                    style: GoogleFonts.inter(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: bold
                        ? FontWeight.w700
                        : FontWeight.w500,
                    )),
            ),
          ),
        ),
      ),
    );
  }
}
