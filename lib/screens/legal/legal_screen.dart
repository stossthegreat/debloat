import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';

/// Legal screens — Terms of Use + Privacy Policy. Rendered in-app so
/// Apple App Review can reach them directly from the paywall and the
/// settings menu without touching a web link.
///
/// Content is intentionally plain-English and short. Apple's review team
/// penalises walls of unreadable legalese; the important clauses
/// (subscription auto-renewal, cancellation path, data we collect) are
/// surfaced in their own headed sections so a reviewer can tick them off.
class LegalScreen extends StatelessWidget {
  final LegalDoc doc;
  const LegalScreen({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                children: [
                  for (final b in doc.sections) ...[
                    Text(b.title,
                      style: GoogleFonts.inter(
                        color: AppColors.red,
                        fontSize: 11, letterSpacing: 2.6,
                        fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(b.body,
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimary,
                        fontSize: 14, height: 1.55,
                        fontWeight: FontWeight.w400)),
                    const SizedBox(height: 22),
                  ],
                  const SizedBox(height: 12),
                  Text(doc.lastUpdatedLine,
                    style: GoogleFonts.inter(
                      color: AppColors.textTertiary,
                      fontSize: 11, letterSpacing: 1.4,
                      fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 20, 16),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                context.pop();
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.surface1, shape: BoxShape.circle,
                  border: Border.all(color: AppColors.divider, width: 0.8),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 14, color: AppColors.textSecondary),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(doc.title,
                  style: GoogleFonts.playfairDisplay(
                    color: AppColors.textPrimary,
                    fontSize: 24, height: 1,
                    letterSpacing: -0.5,
                    fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(doc.subtitle,
                  style: GoogleFonts.inter(
                    color: AppColors.textTertiary,
                    fontSize: 9, letterSpacing: 2.4,
                    fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  CONTENT
//
//  These documents are kept in source because (a) the app has no live
//  backend doc-fetching, (b) Apple reviewers need to find the same text
//  every time they check, (c) content changes ship with app updates
//  anyway. Plain English. No jargon. Auto-renewal + cancellation are
//  called out in dedicated sections so App Review ticks the box on
//  first pass.
// ═══════════════════════════════════════════════════════════════════════════

class LegalSection {
  final String title;
  final String body;
  const LegalSection(this.title, this.body);
}

class LegalDoc {
  final String title;
  final String subtitle;
  final String lastUpdatedLine;
  final List<LegalSection> sections;
  const LegalDoc({
    required this.title,
    required this.subtitle,
    required this.lastUpdatedLine,
    required this.sections,
  });
}

const termsDoc = LegalDoc(
  title: 'Terms of Use',
  subtitle: 'MIRRORLY · THE AGREEMENT',
  lastUpdatedLine: 'Last updated 25 April 2026.',
  sections: [
    LegalSection('ABOUT MIRRORLY',
      'Mirrorly is a self-assessment tool for cosmetic and grooming '
      'decisions. It uses on-device face measurement (MediaPipe) plus '
      'AI image generation and analysis (Replicate, OpenAI) to show '
      'you measurements of your own face and generate illustrative '
      '"after" previews of grooming changes applied to your photo. '
      'Mirrorly is not a medical device and does not provide medical, '
      'dental, psychological, or surgical advice.'),
    LegalSection('WHO CAN USE THIS APP',
      'You must be at least 13 years old to use Mirrorly. If you are '
      'under 18, you represent that your parent or legal guardian has '
      'reviewed and agreed to these terms on your behalf.'),
    LegalSection('ACCOUNTS',
      'Mirrorly does not require an account. Purchases and saved '
      'scans live on your device and are tied to your App Store or '
      'Google Play account for billing purposes only.'),
    LegalSection('SUBSCRIPTIONS & AUTO-RENEWAL',
      'Mirrorly offers auto-renewing subscriptions:\n\n'
      '• Mirrorly Pro Monthly — \$4.99 USD per month (or local '
      'equivalent), billed monthly until cancelled.\n'
      '• Mirrorly Pro Annual — \$29.99 USD per year (or local '
      'equivalent), with a 7-day free trial for new subscribers, '
      'billed annually until cancelled.\n\n'
      'Subscription terms:\n\n'
      '• Payment is charged to your Apple ID or Google Play account '
      'at confirmation of purchase.\n'
      '• Your subscription automatically renews for the same term at '
      'the same price unless you cancel at least 24 hours before the '
      'current period ends.\n'
      '• Your account is charged for renewal within 24 hours of the '
      'period ending.\n'
      '• You can manage or cancel subscriptions in your Apple ID or '
      'Google Play account settings at any time. Uninstalling the '
      'app does NOT cancel the subscription.\n'
      '• Any unused portion of a free trial period is forfeited when '
      'you purchase a subscription.\n'
      '• No refund is issued for the unused portion of the current '
      'period. Partial refunds, where offered, are handled by Apple '
      'or Google directly, not by Mirrorly.'),
    LegalSection('ONE-TIME CREDIT PACKS',
      'Credit packs are non-subscription, one-time purchases. '
      'Mirrorly Rescue Pack — \$9.99 USD (or local equivalent) — '
      'grants 20 AI-rendered "after" image credits. Credits do not '
      'expire, but they are non-refundable and non-transferable '
      'between accounts or devices.'),
    LegalSection('WHAT WE RENDER — AND WHAT WE DO NOT',
      'Mirrorly renders illustrative previews of grooming and '
      'styling changes applied to your photo. These images are '
      'approximations, not photographs of real outcomes, and may '
      'differ from the real-world result you would get from a '
      'barber, surgeon, or dermatologist. Never use a Mirrorly '
      'rendering as the sole basis for a medical, dental, or '
      'surgical decision. Consult a licensed professional.'),
    LegalSection('YOUR CONTENT',
      'You retain all rights to photos you take inside Mirrorly. By '
      'scanning a photo, you grant Mirrorly a limited, revocable, '
      'royalty-free licence to process that photo on your device and '
      'transmit it to our AI providers (OpenAI and Replicate) solely '
      'to produce your measurements, score, and rendered outputs. '
      'We do not sell your photos. We do not train AI models on '
      'your photos.'),
    LegalSection('FACE DATA — WHAT WE COLLECT, WHY, WHO RECEIVES IT, HOW LONG WE KEEP IT',
      'WHAT FACE DATA MIRRORLY COLLECTS\n\n'
      'Mirrorly collects two related pieces of face data:\n'
      '1) The selfie photograph captured with the in-app scan camera.\n'
      '2) Sixteen scalar geometric measurements derived from that '
      'photograph, computed entirely on your device by Apple ML Kit '
      '(iOS) or Google ML Kit (Android). These measurements are plain '
      'numbers describing facial shape — canthal-tilt angle in '
      'degrees, jaw angle in degrees, face width-to-height ratio, '
      'facial symmetry score, facial-thirds proportions, eye spacing '
      'ratio, lip fullness, brow-to-eye gap, philtrum ratio, '
      'interpupillary ratio, nose length ratio, face length ratio, '
      'and a head-shape category. They are NOT a biometric template, '
      'a face print, or anything that could be used to recognise or '
      'identify you.\n\n'
      'HOW MIRRORLY USES FACE DATA\n\n'
      '• Compute and display your geometry score, trait badges, and '
      'archetype match on screen, on-device.\n'
      '• Generate a written analysis of your facial proportions '
      '(photo sent to OpenAI GPT-4o Vision for one API request).\n'
      '• Generate an illustrative "maximised" preview image (photo '
      'sent to Replicate Nano Banana + cdingram/face-swap for one '
      'API request).\n'
      '• Persist the photo and the geometry numbers in the app\'s '
      'sandboxed local storage so you can revisit prior scans.\n\n'
      'Mirrorly does NOT use face data for: facial recognition, '
      'identity matching, authentication, ARKit Face ID, advertising, '
      'profiling, AI model training, building a biometric template, '
      'or any cross-app tracking purpose.\n\n'
      'WHO RECEIVES FACE DATA\n\n'
      'The selfie photo is sent over HTTPS to two third-party AI '
      'providers, solely to deliver app functionality:\n'
      '• OpenAI (GPT-4o Vision) — to generate analysis text and '
      'cosmetic rating. Default API endpoints exclude inputs from '
      'training and long-term retention.\n'
      '• Replicate (Google Nano Banana + cdingram/face-swap) — to '
      'render the "maximised" preview image. API terms exclude '
      'inputs from training and provide for transient processing.\n\n'
      'No other third party receives face data. No advertisers, data '
      'brokers, analytics providers, or social-login partners.\n\n'
      'STORAGE LOCATIONS\n\n'
      '• On your device — app sandbox, until you uninstall.\n'
      '• Transiently on OpenAI / Replicate infrastructure — seconds.\n'
      '• On Mirrorly servers — request timestamps and status codes '
      'only (no photo bytes, no face data); logs expire after 30 days.\n\n'
      'HOW LONG FACE DATA IS RETAINED\n\n'
      'On your device: indefinitely, until uninstall or scan deletion.\n'
      'On Mirrorly\'s servers: never retained.\n'
      'On OpenAI / Replicate: only for the duration of one API call.\n\n'
      'You can stop the app from collecting any face data at any time '
      'by deleting it.'),
    LegalSection('ACCEPTABLE USE',
      'You agree not to use Mirrorly to scan, analyse, or render a '
      'face that is not your own without that person\'s explicit '
      'consent. You agree not to use Mirrorly outputs to harass, '
      'demean, or defame any person.'),
    LegalSection('TERMINATION',
      'We may suspend or terminate access for conduct that violates '
      'these terms, harms other users, or violates applicable law. '
      'You may stop using the app at any time by deleting it.'),
    LegalSection('DISCLAIMERS & LIABILITY',
      'Mirrorly is provided "as is" without warranty of any kind, '
      'express or implied. To the maximum extent permitted by law, '
      'Mirrorly\'s total liability for any claim is limited to the '
      'amount you paid Mirrorly in the twelve months preceding the '
      'claim.'),
    LegalSection('CHANGES TO THESE TERMS',
      'We may update these terms. Material changes will be surfaced '
      'inside the app before they take effect. Continued use after '
      'an update constitutes acceptance.'),
    LegalSection('CONTACT',
      'Questions? Email info@m2mb.co.uk.'),
  ],
);

const privacyDoc = LegalDoc(
  title: 'Privacy Policy',
  subtitle: 'WHAT WE COLLECT · WHERE IT GOES',
  lastUpdatedLine: 'Last updated 25 April 2026.',
  sections: [
    LegalSection('THE SHORT VERSION',
      'Your photos are processed on your device. We send your photo '
      'to OpenAI and Replicate to generate your analysis and '
      'renders, then we forget it. We do not sell your data. We do '
      'not train AI on your face. We do not require an account.'),
    LegalSection('WHAT WE COLLECT',
      'On your device: photos you take with the scan camera, the '
      'facial-geometry numbers derived from them (canthal tilt, jaw '
      'angle, FWHR, symmetry score, facial thirds, etc.), your score, '
      'your active protocol, and your purchase receipts. Nothing '
      'leaves your device unless you tap a button that clearly says '
      'it will send an image to our servers (e.g. "GENERATE IMAGE", '
      '"SCAN").\n\n'
      'On our servers, temporarily: the single photo you submit to '
      '/scan, /rate, /tryon, or /maximize for the duration of that '
      'one request (seconds), plus the measurements and the '
      'generated image URL. We do not attach your photo to a '
      'persistent account, because there is no account.'),
    LegalSection('FACE DATA — WHAT IT IS, WHAT IT ISN\'T',
      'Mirrorly uses on-device computer vision to derive geometric '
      'measurements from your selfie (Apple ML Kit on iOS, Google '
      'ML Kit on Android — both run entirely on the phone). These '
      'measurements are plain numbers: a canthal-tilt degree, a jaw '
      'angle, a symmetry score. They are NOT a biometric template '
      'that could be used to recognise you, match you to another '
      'photo, or unlock anything.\n\n'
      'WHAT MIRRORLY DOES with face data:\n'
      '• Compute and display your geometry score on-device.\n'
      '• Send the photo to OpenAI (GPT-4o Vision) and Replicate '
      '(Google Nano Banana, cdingram/face-swap) for the duration '
      'of one API call to generate your analysis prose and your '
      '"maximized twin" rendered image.\n'
      '• Store the photo + the geometry numbers locally on your '
      'device, in the app sandbox, until you delete the app.\n\n'
      'WHAT MIRRORLY DOES NOT DO with face data:\n'
      '• No facial recognition. We never match your face to any '
      'identity, account, or external database.\n'
      '• No biometric template. The geometry numbers are not a '
      'fingerprint of your face — they describe shape, not identity.\n'
      '• No long-term server storage. Photos sent to OpenAI / '
      'Replicate are processed for one request and discarded by '
      'their default API terms; we do not retain a copy on a '
      'Mirrorly server.\n'
      '• No model training. Neither Mirrorly nor any third party we '
      'send your photo to trains AI models on it (per our use of '
      'OpenAI and Replicate\'s default API endpoints, which exclude '
      'API inputs from training).\n'
      '• No sharing with data brokers, advertisers, or analytics '
      'partners.'),
    LegalSection('WHO PROCESSES YOUR PHOTOS',
      'OpenAI — GPT-4o Vision runs your analysis and honest rating. '
      'Replicate — Google Nano Banana renders your transformation '
      'images; cdingram/face-swap locks the identity. Both providers '
      'process the photo for the duration of one API request and '
      'do not, by their terms, retain or train on the data we send '
      'them through the API.'),
    LegalSection('WHAT WE DO NOT COLLECT',
      'No name. No email. No phone number. No location. No social '
      'contacts. No tracking across other apps. No advertising '
      'identifier for profiling purposes.'),
    LegalSection('CHILDREN',
      'Mirrorly is not intended for children under 13. We do not '
      'knowingly collect data from children under 13. If you '
      'believe a child has used the app, email info@m2mb.co.uk '
      'and we will delete any on-device and server-side records '
      'associated with the submission.'),
    LegalSection('YOUR RIGHTS',
      'Access: all your data is on your device; open it in '
      'Settings → App Privacy → See all app data.\n'
      'Deletion: delete the app to erase on-device data; the '
      'transient server-side request data is auto-expired.\n'
      'Opt-out of auto-renewal: App Store or Google Play account '
      'settings.'),
    LegalSection('PURCHASES',
      'Billing is handled by Apple (App Store) or Google (Play '
      'Billing). Mirrorly never sees your card number. We see only '
      'a receipt that confirms whether your subscription is active.'),
    LegalSection('SECURITY',
      'Photos in transit are sent over HTTPS. On your device, '
      'photos are stored in the app\'s sandboxed documents '
      'directory and are deleted when the app is uninstalled.'),
    LegalSection('CHANGES',
      'We may update this policy. Material changes will be '
      'surfaced inside the app before they take effect.'),
    LegalSection('CONTACT',
      'Questions or data requests? Email info@m2mb.co.uk.'),
  ],
);
