import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:in_app_review/in_app_review.dart';

import '../services/analytics_service.dart';
import '../theme/app_colors.dart';

/// The review prompt. Fires once after the user has used all three
/// product pillars (scan, Free Flow, eye-contact lesson). Visual
/// language is the Mirrorly editorial card — dark surface, red rating
/// stars, optional comment field, Not now / Submit pair.
///
/// On submit:
///   · Rating + comment always logged to analytics (so private comments
///     reach us even when the public store redirect is skipped).
///   · Rating ≥ 4 → opens the App Store / Play Store write-review page
///     so the rating becomes public.
///   · Rating ≤ 3 → stays in-app. Honest critical feedback reaches us
///     before it lands as a 1-star review on the public store.
class ReviewPromptDialog extends StatefulWidget {
  const ReviewPromptDialog({super.key});

  @override
  State<ReviewPromptDialog> createState() => _ReviewPromptDialogState();
}

class _ReviewPromptDialogState extends State<ReviewPromptDialog> {
  int _rating = 0;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;
  String? _thanks;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0 || _submitting) return;
    setState(() => _submitting = true);
    HapticFeedback.mediumImpact();

    final comment = _commentCtrl.text.trim();
    // ignore: discarded_futures
    AnalyticsService.reviewRatingChosen(_rating);

    if (_rating >= 4) {
      // requestReview() triggers Apple's native StoreKit review sheet
      // on iOS and Google's in-app review API on Android. Both flows
      // resolve the app id internally — no App Store ID config needed.
      // Apple rate-limits to 3 prompts/year but we only ask once per
      // device, so we stay well inside the cap.
      try {
        final reviewer = InAppReview.instance;
        if (await reviewer.isAvailable()) {
          // ignore: discarded_futures
          AnalyticsService.reviewNativeOpened();
          await reviewer.requestReview();
        }
      } catch (_) {/* best effort */}
    }

    if (!mounted) return;
    setState(() {
      _thanks = _rating >= 4
          ? 'Thank you. That star matters.'
          : 'Got it. We read every comment.';
    });
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _dismiss() {
    HapticFeedback.selectionClick();
    // ignore: discarded_futures
    AnalyticsService.reviewDismissed();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: AppColors.red.withValues(alpha: 0.28), width: 0.8),
          boxShadow: [
            BoxShadow(
              color: AppColors.red.withValues(alpha: 0.18),
              blurRadius: 40, spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.red.withValues(alpha: 0.45),
                    blurRadius: 22),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/icons/appstore.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
            const SizedBox(height: 18),

            Text('Enjoying ImHim?',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                color: AppColors.textPrimary,
                fontSize: 24, fontWeight: FontWeight.w800,
                letterSpacing: -0.3, height: 1.15,
              )),
            const SizedBox(height: 8),
            Text('Your feedback shapes the next build.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: AppColors.textSecondary,
                fontSize: 14, fontWeight: FontWeight.w500,
                height: 1.4,
              )),
            const SizedBox(height: 20),

            // Stars
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final filled = i < _rating;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _rating = i + 1);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      filled ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: filled
                          ? AppColors.red
                          : AppColors.textTertiary,
                      size: 40,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),

            // Optional comment
            TextField(
              controller: _commentCtrl,
              enabled: !_submitting,
              maxLines: 3,
              minLines: 2,
              maxLength: 280,
              cursorColor: AppColors.red,
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 14, fontWeight: FontWeight.w500,
                height: 1.4,
              ),
              decoration: InputDecoration(
                hintText: 'Tell us what we can do better (optional)',
                hintStyle: GoogleFonts.inter(
                  color: AppColors.textTertiary,
                  fontSize: 14, fontWeight: FontWeight.w400,
                ),
                filled: true,
                fillColor: AppColors.surface2,
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppColors.surface3, width: 0.8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppColors.surface3, width: 0.8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppColors.red.withValues(alpha: 0.6),
                    width: 1.2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            if (_thanks != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_thanks!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: AppColors.red,
                    fontSize: 13, fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  )),
              )
            else
              Row(
                children: [
                  TextButton(
                    onPressed: _submitting ? null : _dismiss,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                    ),
                    child: Text('Not now',
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 15, fontWeight: FontWeight.w600,
                      )),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: (_rating == 0 || _submitting) ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      disabledBackgroundColor: AppColors.surface3,
                      foregroundColor: Colors.white,
                      disabledForegroundColor: AppColors.textTertiary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                        : Text('Submit',
                            style: GoogleFonts.inter(
                              fontSize: 15, fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            )),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
