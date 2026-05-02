import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/local_store_service.dart';
import '../../theme/app_colors.dart';

/// Modal disclosure asking the user to permit transmission of their
/// selfie photo to the third-party AI providers Mirrorly uses to
/// generate the analysis and renders.
///
/// Required by App Store guideline 5.1.2(i): the user must be told
/// what data is sent, who it is sent to, and must explicitly grant
/// permission BEFORE the app shares personal data with a third-party
/// AI service. Apple explicitly notes that putting the disclosure
/// only in the Privacy Policy is not sufficient — there has to be an
/// in-app permission gate. This is that gate.
///
/// Asked once per install. The choice is persisted in
/// [LocalStoreService.setAiConsent]. The user can revoke it later
/// from the Settings screen, which clears the flag and re-shows this
/// dialog on the next scan.
class AiConsentDialog extends StatelessWidget {
  const AiConsentDialog({super.key});

  /// Show the dialog. Returns true iff the user tapped ALLOW. A
  /// tapping of CANCEL, the back button, or a barrier dismissal all
  /// resolve to false — the caller must NOT proceed to send any
  /// data in those cases.
  static Future<bool> show(BuildContext context) async {
    final granted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (_) => const AiConsentDialog(),
    );
    if (granted == true) {
      await LocalStoreService.setAiConsent(true);
      return true;
    }
    return false;
  }

  /// Centralised "make sure consent exists before transmitting" helper.
  /// Call this from EVERY entry point that fires an AI / backend call
  /// carrying user data (scan, chat send, try-on, maximise, rate). It
  /// short-circuits to true when the persisted flag is already set, so
  /// the user only sees one dialog ever (until they revoke). When the
  /// user is asked and declines, returns false and the caller MUST
  /// abort the operation without sending any bytes.
  ///
  /// Apple guideline 5.1.2(i) requires the dialog to gate every path
  /// — not just the scan flow — because the reviewer can navigate to
  /// chat / try-on / maximise without going through the scan, and
  /// data must not transmit on any of those paths without permission.
  static Future<bool> ensure(BuildContext context) async {
    if (await LocalStoreService.hasAiConsent()) return true;
    if (!context.mounted) return false;
    return show(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.base,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.12), width: 0.8),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('SHARE PHOTO WITH AI PROVIDERS?',
                style: GoogleFonts.inter(
                  color: AppColors.red,
                  fontSize: 11, letterSpacing: 2.6,
                  fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Text('Before Mirrorly can produce your analysis and your '
                   '"maximised" preview image, your selfie photo must '
                   'be sent to two third-party AI services over an '
                   'encrypted connection.',
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 14, height: 1.5,
                  fontWeight: FontWeight.w500)),
              const SizedBox(height: 16),

              _Bullet(
                head: 'WHAT IS SENT',
                body: 'Only the selfie photo you just captured, plus '
                      'sixteen geometric measurements (canthal tilt, '
                      'jaw angle, symmetry score, facial-thirds '
                      'proportions, etc.) computed on this device. '
                      'No name, no email, no contacts, no location.'),
              const SizedBox(height: 12),
              _Bullet(
                head: 'WHO RECEIVES IT',
                body: '• OpenAI (GPT-4o Vision) — generates your '
                      'written analysis and honest-looks rating.\n'
                      '• Replicate (Google Nano Banana + '
                      'cdingram/face-swap) — renders your '
                      '"maximised" preview image.'),
              const SizedBox(height: 12),
              _Bullet(
                head: 'HOW LONG THEY KEEP IT',
                body: 'For the duration of one API request only. '
                      'Both providers\' default API terms exclude '
                      'inputs from training data and from long-term '
                      'retention. Mirrorly itself never stores the '
                      'photo on a server.'),
              const SizedBox(height: 12),
              _Bullet(
                head: 'EQUAL PROTECTION',
                body: 'OpenAI and Replicate are bound by their '
                      'enterprise privacy commitments to handle the '
                      'data they receive with the same or equal '
                      'protection Mirrorly guarantees here: encrypted '
                      'in transit (HTTPS/TLS), excluded from model '
                      'training, no long-term retention, no cross-app '
                      'tracking, no resale to advertisers or data '
                      'brokers.'),
              const SizedBox(height: 12),
              _Bullet(
                head: 'YOU CAN REVOKE THIS',
                body: 'Settings → Revoke AI permission. After that, '
                      'no further scans will be transmitted until '
                      'you grant permission again.'),

              const SizedBox(height: 18),
              Text('Tap ALLOW to permit Mirrorly to send your photo '
                   'to OpenAI and Replicate for this and future '
                   'scans. Tap CANCEL to keep your photo on this '
                   'device — without permission, the analysis and '
                   'render cannot be produced.',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 12.5, height: 1.5,
                  fontWeight: FontWeight.w500)),
              const SizedBox(height: 18),

              Row(
                children: [
                  Expanded(child: OutlinedButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).pop(false);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.28),
                        width: 0.8),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('CANCEL',
                      style: GoogleFonts.inter(
                        fontSize: 12, letterSpacing: 1.8,
                        fontWeight: FontWeight.w800)),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: ElevatedButton(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      Navigator.of(context).pop(true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('ALLOW',
                      style: GoogleFonts.inter(
                        fontSize: 12, letterSpacing: 1.8,
                        fontWeight: FontWeight.w900)),
                  )),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String head, body;
  const _Bullet({required this.head, required this.body});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(head,
          style: GoogleFonts.inter(
            color: AppColors.red,
            fontSize: 9.5, letterSpacing: 2.0,
            fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(body,
          style: GoogleFonts.inter(
            color: AppColors.textPrimary,
            fontSize: 13, height: 1.45,
            fontWeight: FontWeight.w500)),
      ],
    );
  }
}
