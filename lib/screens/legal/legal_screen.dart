import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';

// App Store guideline 2.3.10 — strip cross-platform billing
// references from the iOS binary. These small helpers keep the
// legal copy below readable while still rendering only the
// platform-relevant phrasing on each build.
String get _storeAccount       => Platform.isIOS ? 'App Store account'
                                                 : 'Google Play account';
String get _appleOrGoogleId    => Platform.isIOS ? 'Apple ID'
                                                 : 'Google Play account';
String get _storeName          => Platform.isIOS ? 'App Store'
                                                 : 'Google Play';
String get _platformAppleStore => Platform.isIOS ? 'Apple'
                                                 : 'Google';

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

LegalDoc get termsDoc => LegalDoc(
  title: 'Terms of Use',
  subtitle: 'MIRRORLY · THE AGREEMENT',
  lastUpdatedLine: 'Last updated 26 May 2026.',
  sections: [
    const LegalSection('ABOUT MIRRORLY',
      'Mirrorly is a self-assessment and self-training tool for '
      'cosmetic, grooming, and charisma decisions. It uses on-device '
      'face measurement (MediaPipe) plus AI image generation and '
      'analysis (Replicate, OpenAI) to show you measurements of your '
      'own face and generate illustrative "after" previews of '
      'grooming changes applied to your photo. The Eyes and Game '
      'tabs add real-time gaze drills, voice-delivery scoring, and '
      'a voice-driven roleplay coach ("Lucien") that uses the '
      'OpenAI Realtime API for live conversation practice. '
      'Mirrorly is not a medical device and does not provide '
      'medical, dental, psychological, or surgical advice.'),
    const LegalSection('WHO CAN USE THIS APP',
      'You must be at least 13 years old to use Mirrorly. If you are '
      'under 18, you represent that your parent or legal guardian has '
      'reviewed and agreed to these terms on your behalf.'),
    LegalSection('ACCOUNTS',
      'Mirrorly does not require an account. Purchases and saved '
      'scans live on your device and are tied to your '
      '$_storeAccount for billing purposes only.'),
    LegalSection('SUBSCRIPTIONS & AUTO-RENEWAL',
      'Mirrorly offers auto-renewing subscriptions:\n\n'
      '• Mirrorly Pro Monthly — \$4.99 USD per month (or local '
      'equivalent), billed monthly until cancelled.\n'
      '• Mirrorly Pro Annual — \$29.99 USD per year (or local '
      'equivalent), with a 7-day free trial for new subscribers, '
      'billed annually until cancelled.\n\n'
      'Subscription terms:\n\n'
      '• Payment is charged to your $_appleOrGoogleId at '
      'confirmation of purchase.\n'
      '• Your subscription automatically renews for the same term at '
      'the same price unless you cancel at least 24 hours before the '
      'current period ends.\n'
      '• Your account is charged for renewal within 24 hours of the '
      'period ending.\n'
      '• You can manage or cancel subscriptions in your '
      '$_appleOrGoogleId settings at any time. Uninstalling the '
      'app does NOT cancel the subscription.\n'
      '• Any unused portion of a free trial period is forfeited when '
      'you purchase a subscription.\n'
      '• No refund is issued for the unused portion of the current '
      'period. Partial refunds, where offered, are handled by '
      '$_platformAppleStore directly, not by Mirrorly.'),
    const LegalSection('ONE-TIME CREDIT PACKS',
      'Credit packs are non-subscription, one-time purchases. '
      'Mirrorly Rescue Pack — \$9.99 USD (or local equivalent) — '
      'grants 20 AI-rendered "after" image credits. Credits do not '
      'expire, but they are non-refundable and non-transferable '
      'between accounts or devices.'),
    const LegalSection('WHAT WE RENDER — AND WHAT WE DO NOT',
      'Mirrorly renders illustrative previews of grooming and '
      'styling changes applied to your photo. These images are '
      'approximations, not photographs of real outcomes, and may '
      'differ from the real-world result you would get from a '
      'barber, surgeon, or dermatologist. Never use a Mirrorly '
      'rendering as the sole basis for a medical, dental, or '
      'surgical decision. Consult a licensed professional.'),
    const LegalSection('YOUR CONTENT',
      'You retain all rights to photos you take inside Mirrorly. By '
      'scanning a photo and granting in-app permission in the AI data '
      'consent dialog, you grant Mirrorly a limited, revocable, '
      'royalty-free licence to process that photo on your device and '
      'transmit it to our AI providers (OpenAI and Replicate) solely '
      'to produce your measurements, score, and rendered outputs. '
      'We do not sell your photos. We do not train AI models on '
      'your photos.'),
    const LegalSection('AI DATA PERMISSION — EVERY DETAIL OF WHAT GETS SENT, WHERE, AND WHY',
      'At the end of onboarding, before any photo bytes leave your '
      'device, Mirrorly displays a full-screen permission dialog '
      '("PERMISSION TO SHARE YOUR PHOTO WITH AI PROVIDERS"). The '
      'same dialog is also shown the first time you reach any '
      'other AI-firing path (Mirror chat, try-on render, '
      'maximise) if it has not already been answered. You must '
      'tap ALLOW for any photo bytes to be transmitted; CANCEL '
      'keeps the photo on your device and aborts the analysis.\n\n'
      'EXACTLY WHAT IS SENT\n\n'
      '1) The selfie photo (JPEG, compressed, base64-encoded '
      'inside an HTTPS POST body).\n'
      '2) Sixteen geometric measurements computed on-device by '
      'Apple ML Kit (iOS) or Google ML Kit (Android) BEFORE '
      'transmission: canthal-tilt angle, jaw apex angle, face '
      'width-to-height ratio, facial-symmetry score, '
      'facial-thirds split, eye-spacing ratio, lip fullness, '
      'brow-to-eye gap, philtrum ratio, interpupillary-distance '
      'ratio, nose-length ratio, face-length ratio, head-shape '
      'category.\n\n'
      'NOT sent: name, email, phone, postal address, location, '
      'contacts, IP-based tracking IDs, advertising IDs, '
      'social-login data.\n\n'
      'EXACT ROUTE THE PHOTO TAKES\n\n'
      'Step 1 — your phone → Mirrorly\'s backend at '
      'https://mirrorly-production.up.railway.app, encrypted by '
      'HTTPS / TLS 1.3. Mirrorly\'s backend does NOT persist the '
      'photo bytes; it forwards them to the relevant AI provider '
      'in-memory and returns the response.\n\n'
      'Step 2 — Mirrorly\'s backend → AI provider:\n'
      '• POST /analyse and POST /rate → OpenAI GPT-4o Vision '
      '(api.openai.com) for analysis text and honest-looks '
      'rating.\n'
      '• POST /maximize and POST /tryon → Replicate '
      '(api.replicate.com) — Google Nano Banana renders the '
      '"maximised" preview, cdingram/face-swap locks identity.\n'
      '• POST /chat → OpenAI for the Mirror advisor\'s face-'
      'specific responses.\n\n'
      'WHO RECEIVES IT, BY NAME\n\n'
      '• OpenAI, L.L.C. (San Francisco, CA, USA) — GPT-4o Vision.\n'
      '• Replicate, Inc. (San Francisco, CA, USA) — Nano Banana '
      '+ cdingram/face-swap.\n'
      '• Mirrorly\'s own backend on Railway — transient routing '
      'only.\n\n'
      'No other party receives your photo or geometry data.\n\n'
      'HOW LONG EACH PARTY KEEPS IT\n\n'
      '• On your phone: until you delete the scan or uninstall.\n'
      '• In flight: TLS 1.3 encrypted.\n'
      '• On Mirrorly\'s backend: bytes not persisted; only '
      'timestamps + HTTP status codes logged, auto-expiring '
      'after 30 days.\n'
      '• On OpenAI: duration of one request; excluded from '
      'training and long-term retention.\n'
      '• On Replicate: duration of one inference request; '
      'excluded from training and not retained long-term.\n\n'
      'WHY YOUR PHOTO IS SENT\n\n'
      'Sole purpose: produce the analysis text, the honest-looks '
      'score, and the rendered preview that you see inside the '
      'app. Never used for advertising, profiling, identity '
      'matching, facial recognition, biometric template building, '
      'AI model training, or resale.\n\n'
      'HOW TO REVOKE\n\n'
      'Settings → Revoke AI permission. The consent flag is '
      'cleared and the dialog is re-shown on your next AI-firing '
      'action. Settings → Delete all data wipes every on-device '
      'scan, render, and protocol.'),
    const LegalSection('VOICE & TRAINING DATA — EYES AND GAME TABS',
      'The Eyes and Game tabs use the device microphone for charisma '
      'training. Microphone access is requested at the iOS / Android '
      'system level the first time you enter a voice drill; you may '
      'deny it and the rest of the app still works.\n\n'
      'WHEN AUDIO IS CAPTURED\n\n'
      'Only when you explicitly tap a record / talk button inside a '
      'voice drill. The app does NOT listen passively, NOT in the '
      'background, NOT outside an active drill. Recording stops the '
      'moment you finish the drill.\n\n'
      'EXACTLY WHAT IS SENT\n\n'
      '1) The short audio clip you just recorded (PCM or compressed '
      'WAV / M4A, base64-encoded inside an HTTPS multipart body), OR '
      '— for live "Free Flow" and "Council" voice sessions — a live '
      'PCM16 stream over a secure WebSocket.\n'
      '2) Lesson metadata: lesson id, target line, target words-per-'
      'minute band, expected warmth flag. No personal identifiers.\n\n'
      'NOT sent: name, email, phone, location, contacts, advertising '
      'IDs, ambient or background audio (the mic is only live during '
      'an active drill).\n\n'
      'EXACT ROUTE THE AUDIO TAKES\n\n'
      'Recorded drills (Eyes voice, Arena, rhetoric scoring):\n'
      'Phone → Mirrorly\'s voice backend at '
      'https://auralayai-production-65c2.up.railway.app, encrypted '
      'by HTTPS / TLS 1.3 → backend forwards to OpenAI in-memory '
      'for one request → response (transcript text + replied audio) '
      'returns to phone. The audio bytes are NOT persisted on the '
      'Mirrorly\'s voice backend; only timestamps and HTTP status codes are '
      'logged for diagnostics, auto-expiring after 30 days.\n\n'
      'Live voice (Free Flow, Council):\n'
      'Phone requests a short-lived ephemeral OpenAI Realtime API '
      'token from Mirrorly\'s voice backend (HTTPS) → phone opens a TLS-'
      'encrypted WebSocket directly to api.openai.com → live audio '
      'streams to OpenAI and replies stream back, never traversing '
      'Mirrorly servers.\n\n'
      'OPENAI MODELS USED\n\n'
      '• Whisper (whisper-1) — transcribes your recorded audio to '
      'text for scoring.\n'
      '• GPT-4o — produces in-character text replies for Lucien and '
      'the Arena women.\n'
      '• gpt-4o-mini-tts — synthesises Lucien\'s and the Arena '
      'characters\' voice replies.\n'
      '• gpt-realtime — drives the live Free Flow and Council voice '
      'sessions via direct WebSocket.\n\n'
      'WHO RECEIVES IT, BY NAME\n\n'
      '• OpenAI, L.L.C. (San Francisco, CA, USA) — receives the '
      'audio for transcription, language modelling, and voice '
      'synthesis.\n'
      '• Mirrorly\'s voice backend on Railway — transient routing '
      'and Realtime token minting only.\n\n'
      'No other party receives your voice data.\n\n'
      'RETENTION\n\n'
      '• On your phone: clips are written to a temporary directory '
      'during the drill and deleted when the drill ends or the app '
      'is closed; transcripts are not stored.\n'
      '• In flight: TLS 1.3 encrypted.\n'
      '• Mirrorly\'s voice backend: bytes not persisted; only HTTP '
      'status + timestamp logs, auto-expiring after 30 days.\n'
      '• OpenAI: duration of one API request (or one live Realtime '
      'session); excluded from training and long-term retention '
      'under OpenAI\'s standard API terms.\n\n'
      'WHY YOUR VOICE IS SENT\n\n'
      'Sole purpose: transcribe what you said, score your delivery '
      '(pace, conviction, warmth, presence), and play back the '
      'in-character reply. Never used for voice-print biometrics, '
      'speaker identification, advertising, profiling, AI model '
      'training, or resale.\n\n'
      'HOW TO STOP IT\n\n'
      'Skip the Eyes and Game tabs, or deny microphone permission '
      'at the iOS / Android system level. Settings → Delete all '
      'data wipes any on-device training history.'),
    const LegalSection('CREATOR MODE',
      'Settings → CREATOR is a password-gated, off-by-default switch '
      'that swaps Lucien and the Arena characters into a sharper, '
      'less filtered persona for the Game tab\'s voice surfaces. It '
      'is intended for adult users who want a less polished coaching '
      'tone.\n\n'
      'Even when CREATOR is ON, the underlying OpenAI policy '
      'guardrails are enforced server-side: no sexually explicit '
      'content, no instructions for real-world harassment, '
      'coercion, or harm, and no targeting of protected groups. '
      'Output remains within OpenAI\'s and the App Store / Play '
      'Store\'s content policies.\n\n'
      'CREATOR is OFF until you explicitly enter the password. '
      'Turning it ON only affects this device. Tapping the same '
      'tile again, or deleting the app, re-locks everything.'),
    const LegalSection('FACE DATA — WHAT WE COLLECT, WHY, WHO RECEIVES IT, HOW LONG WE KEEP IT',
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
    const LegalSection('THIRD-PARTY PROTECTION PARITY',
      'Per App Store guideline 5.1.2(i), any third party that '
      'receives Mirrorly user data must provide the same or equal '
      'privacy protection as Mirrorly itself. Both providers we '
      'transmit photos to meet this bar:\n\n'
      '• OpenAI — under the standard API terms, customer inputs are '
      'excluded from model training, encrypted in transit (TLS) '
      'and at rest, processed transiently for the single request, '
      'and not used for advertising, profiling, or sale to third '
      'parties.\n'
      '• Replicate — under the standard API terms, model inputs are '
      'excluded from training, processed for the duration of one '
      'inference request, not retained long-term, and not used for '
      'advertising, profiling, or sale to third parties.\n\n'
      'Mirrorly does not transmit user photos to any other third '
      'party. The on-device geometry numbers stay on-device unless '
      'they accompany the photo on a single API call.'),
    const LegalSection('ACCEPTABLE USE',
      'You agree not to use Mirrorly to scan, analyse, or render a '
      'face that is not your own without that person\'s explicit '
      'consent. You agree not to use Mirrorly outputs to harass, '
      'demean, or defame any person.'),
    const LegalSection('TERMINATION',
      'We may suspend or terminate access for conduct that violates '
      'these terms, harms other users, or violates applicable law. '
      'You may stop using the app at any time by deleting it.'),
    const LegalSection('DISCLAIMERS & LIABILITY',
      'Mirrorly is provided "as is" without warranty of any kind, '
      'express or implied. To the maximum extent permitted by law, '
      'Mirrorly\'s total liability for any claim is limited to the '
      'amount you paid Mirrorly in the twelve months preceding the '
      'claim.'),
    const LegalSection('CHANGES TO THESE TERMS',
      'We may update these terms. Material changes will be surfaced '
      'inside the app before they take effect. Continued use after '
      'an update constitutes acceptance.'),
    const LegalSection('CONTACT',
      'Questions? Email info@m2mb.co.uk.'),
  ],
);

LegalDoc get privacyDoc => LegalDoc(
  title: 'Privacy Policy',
  subtitle: 'WHAT WE COLLECT · WHERE IT GOES',
  lastUpdatedLine: 'Last updated 4 June 2026.',
  sections: [
    // Explicit, Apple-aligned face-data summary at the very top of
    // the policy. Every bullet App Store guideline 5.1.1(i) asks
    // about is answered here in plain language, in one place, before
    // the longer "every detail" sections below.
    const LegalSection('FACE DATA — QUICK SUMMARY',
      'IS FACE DATA RETAINED?\n'
      'No face image is retained anywhere. The selfie you take is held '
      'in device memory long enough to be analysed in a single API '
      'call, then dropped. Neither Mirrorly nor the third parties we '
      'send it to (OpenAI, Replicate) keep the photo, store a face '
      'template, or build a biometric record from it.\n\n'
      'WHY DO YOU SEND IT AT ALL?\n'
      'To produce the analysis. We send the selfie to OpenAI\'s vision '
      'model so it can return a written read of your face, and to '
      'Replicate so it can render a "maximised" preview based on your '
      'photo. Those two outputs are what the scan screen exists to '
      'show. There is no other use.\n\n'
      'HOW LONG IS IT STORED?\n'
      '• On the third-party servers: never persisted. Each request is '
      'one-shot inference; the photo bytes are dropped from memory '
      'when the response is returned. OpenAI and Replicate are '
      'configured to exclude these requests from any training corpus '
      'and from long-term retention.\n'
      '• On Mirrorly\'s own backend: never persisted. The backend acts '
      'as a transient router — bytes are forwarded in-memory only. '
      'Server logs record only timestamps and HTTP status codes and '
      'auto-expire after 30 days; no image bytes are logged.\n'
      '• On your phone: the scan image you took is kept on your '
      'device until you delete it via Settings → Delete all data, or '
      'uninstall the app. It never leaves your device after the '
      'initial analysis completes.\n\n'
      'WHICH THIRD PARTIES IS IT SHARED WITH AND WHY?\n'
      '• OpenAI, L.L.C. (San Francisco, CA, USA) — sent the selfie + '
      'the 16 on-device geometric measurements so its GPT-4o Vision '
      'model can produce the written analysis, the honest-looks '
      'score, and the chat / advisor replies.\n'
      '• Replicate, Inc. (San Francisco, CA, USA) — sent the selfie '
      'so its Nano Banana + face-swap models can render the '
      '"maximised" preview image you see at the top of the report.\n'
      'Both are sent over HTTPS / TLS 1.3. No other third party '
      'receives the image.\n\n'
      'DO THOSE THIRD PARTIES ALSO STORE THE FACE DATA?\n'
      'No. Per their published API privacy terms and our API '
      'configuration: OpenAI excludes our requests from training and '
      'long-term retention; Replicate excludes them from training '
      'and long-term retention. Each request is treated as a one-shot '
      'inference and the inputs are dropped at response time. Neither '
      'provider builds a face template or biometric record from the '
      'image we send.\n\n'
      'ON-DEVICE FACE MEASUREMENTS (MEDIAPIPE)\n'
      'The 16 geometric measurements (canthal tilt angle, jaw apex '
      'angle, FWHR, facial symmetry score, facial-thirds split, '
      'eye-spacing ratio, lip fullness, brow-to-eye gap, philtrum '
      'ratio, interpupillary-distance ratio, nose-length ratio, '
      'face-length ratio, head-shape category) are computed by '
      'Google MediaPipe ENTIRELY ON YOUR DEVICE. They are scalar '
      'numbers, not a biometric template. The eye-contact training '
      'in the Eyes tab (camera + face-mesh detection) is also '
      '100% on-device — no image bytes leave the phone during a '
      'live eye-contact lesson.\n\n'
      'BIOMETRIC / IDENTITY USE — EXPLICITLY EXCLUDED\n'
      'We do NOT use face data for: identity matching, facial '
      'recognition, biometric template building, advertising, '
      'profiling, AI training, or resale. Sole purpose is to produce '
      'the analysis on the scan screen.'),
    const LegalSection('THE SHORT VERSION',
      'Your photos are processed on your device. Before we send your '
      'photo to OpenAI and Replicate to generate your analysis and '
      'renders, the app shows you an in-app permission dialog '
      'explaining exactly what is sent and to whom — you must tap '
      'ALLOW for the photo to leave your device. After processing, '
      'we forget it.\n\n'
      'The Eyes and Game tabs add voice training: when you tap a '
      'record / talk button inside a drill, the captured audio is '
      'sent (over TLS) to our voice backend, forwarded in-memory '
      'to OpenAI for transcription and reply, and not retained. '
      'Live "Free Flow" and "Council" voice sessions open a TLS '
      'WebSocket directly to OpenAI using an ephemeral token; the '
      'audio does not traverse our servers.\n\n'
      'We do not sell your data. We do not train AI on your face or '
      'your voice. We do not require an account. You can revoke AI '
      'permission and delete all on-device data at any time in '
      'Settings.'),
    const LegalSection('AI DATA PERMISSION — EVERY DETAIL',
      'At the end of onboarding, before any photo bytes leave your '
      'device, Mirrorly displays a full-screen permission dialog '
      '("PERMISSION TO SHARE YOUR PHOTO WITH AI PROVIDERS"). The '
      'same dialog is also shown the first time you reach any '
      'other AI-firing path (Mirror chat, try-on render, '
      'maximise) if it has not already been answered. You must '
      'tap ALLOW for any photo bytes to be transmitted; CANCEL '
      'keeps the photo on your device and aborts the analysis.\n\n'
      'EXACTLY WHAT IS SENT\n\n'
      '1) The selfie photo (JPEG, compressed, base64-encoded '
      'inside an HTTPS POST body).\n'
      '2) Sixteen on-device geometric measurements: canthal-tilt '
      'angle, jaw apex angle, FWHR, facial-symmetry score, '
      'facial-thirds split, eye-spacing ratio, lip fullness, '
      'brow-to-eye gap, philtrum ratio, interpupillary-distance '
      'ratio, nose-length ratio, face-length ratio, head-shape '
      'category.\n\n'
      'NOT sent: name, email, phone, address, location, '
      'contacts, IP-based tracking IDs, advertising IDs, '
      'social-login data.\n\n'
      'EXACT ROUTE\n\n'
      'Phone → Mirrorly backend (mirrorly-production.up.railway'
      '.app) over HTTPS / TLS 1.3 — backend does NOT persist '
      'photo bytes — backend forwards in-memory to OpenAI '
      '(api.openai.com, GPT-4o Vision) for /analyse, /rate, '
      '/chat OR Replicate (api.replicate.com, Nano Banana + '
      'cdingram/face-swap) for /maximize, /tryon — response '
      'returns to phone.\n\n'
      'WHO RECEIVES IT\n\n'
      '• OpenAI, L.L.C. (San Francisco, CA, USA).\n'
      '• Replicate, Inc. (San Francisco, CA, USA).\n'
      '• Mirrorly\'s own backend (Railway), transient routing.\n'
      'No other party.\n\n'
      'RETENTION\n\n'
      '• On your phone: until you delete or uninstall.\n'
      '• In flight: TLS 1.3 encrypted.\n'
      '• Mirrorly backend: bytes not persisted; only timestamps '
      '+ status codes, auto-expire after 30 days.\n'
      '• OpenAI: one API request; excluded from training and '
      'long-term retention.\n'
      '• Replicate: one inference request; excluded from '
      'training and long-term retention.\n\n'
      'WHY\n\n'
      'Sole purpose: produce the analysis, the honest-looks '
      'score, and the rendered preview. Never used for '
      'advertising, profiling, identity matching, facial '
      'recognition, biometric template building, AI training, '
      'or resale.\n\n'
      'HOW TO REVOKE\n\n'
      'Settings → Revoke AI permission. The consent flag is '
      'cleared; the dialog re-shows on the next AI action. '
      'Settings → Delete all data wipes every on-device scan + '
      'render.'),
    const LegalSection('VOICE & TRAINING DATA — EYES AND GAME TABS',
      'WHEN AUDIO IS CAPTURED\n\n'
      'Only when you explicitly tap a record / talk button inside a '
      'voice drill in the Eyes or Game tab. The microphone is NOT '
      'live in the background, NOT outside an active drill, and the '
      'app does NOT listen passively. Microphone permission is '
      'requested by the OS the first time you enter a voice drill; '
      'denying it leaves the rest of the app fully functional.\n\n'
      'EXACTLY WHAT IS SENT\n\n'
      '1) The short audio clip you just recorded, OR — for live '
      '"Free Flow" and "Council" voice sessions — a live PCM16 '
      'audio stream over a secure WebSocket.\n'
      '2) Lesson metadata (lesson id, target words-per-minute band, '
      'expected warmth flag). No personal identifiers.\n\n'
      'NOT sent: name, email, phone, location, contacts, ambient '
      'audio outside the drill, advertising IDs.\n\n'
      'EXACT ROUTE\n\n'
      'Recorded drills: phone → Mirrorly\'s voice backend (https://'
      'auralayai-production-65c2.up.railway.app) over HTTPS / TLS '
      '1.3 → backend forwards to OpenAI in-memory for one request '
      '→ response returns. Mirrorly\'s voice backend does NOT persist '
      'audio bytes; only timestamps + HTTP status codes are logged, '
      'auto-expiring after 30 days.\n\n'
      'Live voice (Free Flow, Council): phone requests an ephemeral '
      'OpenAI Realtime API token from Mirrorly\'s voice backend (HTTPS) '
      '→ phone opens a TLS WebSocket directly to api.openai.com → '
      'live audio streams to OpenAI; replies stream back. Audio '
      'never traverses Mirrorly servers in this mode.\n\n'
      'OPENAI MODELS\n\n'
      'whisper-1 (transcription) · gpt-4o (text replies) · '
      'gpt-4o-mini-tts (voice synthesis) · gpt-realtime (live '
      'voice sessions).\n\n'
      'WHO RECEIVES IT\n\n'
      '• OpenAI, L.L.C. (San Francisco, CA, USA).\n'
      '• Mirrorly\'s voice backend on Railway — transient routing '
      'and Realtime token minting only.\n\n'
      'No other party.\n\n'
      'RETENTION\n\n'
      '• On your phone: clips deleted at drill end; transcripts '
      'not stored.\n'
      '• In flight: TLS 1.3 encrypted.\n'
      '• Mirrorly\'s voice backend: bytes not persisted; only status + '
      'timestamp logs, auto-expire after 30 days.\n'
      '• OpenAI: duration of one API request or one Realtime '
      'session; excluded from training and long-term retention.\n\n'
      'WHY\n\n'
      'Sole purpose: transcribe what you said, score your delivery, '
      'play back the in-character reply. Never used for voice-print '
      'biometrics, speaker identification, advertising, profiling, '
      'AI model training, or resale.\n\n'
      'HOW TO STOP IT\n\n'
      'Deny microphone permission in iOS / Android system settings, '
      'or simply skip the Eyes and Game tabs.'),
    const LegalSection('CREATOR MODE',
      'Settings → CREATOR is a password-gated, off-by-default switch '
      'on the Game tab\'s voice surfaces. It swaps the Lucien and '
      'Arena characters into a less polished coaching tone intended '
      'for adult users.\n\n'
      'Even when CREATOR is ON, OpenAI\'s content policy guardrails '
      'are enforced server-side: no sexually explicit content, no '
      'real-world coercion or harassment instructions, no targeting '
      'of protected groups. CREATOR is OFF by default, must be '
      'explicitly unlocked with a password, applies only on this '
      'device, and can be re-locked at any time.'),
    const LegalSection('WHAT WE COLLECT',
      'On your device: photos you take with the scan camera, the '
      'facial-geometry numbers derived from them (canthal tilt, jaw '
      'angle, FWHR, symmetry score, facial thirds, etc.), your score, '
      'your active protocol, your training drill history (Eyes + '
      'Game), and your purchase receipts. Nothing leaves your '
      'device unless you tap a button that clearly says it will '
      'send an image or audio clip to our servers (e.g. "GENERATE '
      'IMAGE", "SCAN", "RECORD", "TALK").\n\n'
      'On our servers, temporarily: the single photo you submit to '
      '/scan, /rate, /tryon, or /maximize for the duration of one '
      'request (seconds), or the single audio clip you submit to '
      '/v1/diablo/*, /v1/villain/*, /v1/presence/*, /v1/rhetoric/* '
      'for the duration of one request. We do not attach your '
      'photo or audio to a persistent account, because there is '
      'no account.'),
    const LegalSection('FACE DATA — WHAT IT IS, WHAT IT ISN\'T',
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
    const LegalSection('WHO PROCESSES YOUR PHOTOS AND VOICE',
      'PHOTOS\n\n'
      'OpenAI — GPT-4o Vision runs your analysis and honest rating. '
      'Replicate — Google Nano Banana renders your transformation '
      'images; cdingram/face-swap locks the identity.\n\n'
      'VOICE (Eyes + Game tabs)\n\n'
      'OpenAI — whisper-1 transcribes recorded audio, gpt-4o '
      'produces text replies, gpt-4o-mini-tts synthesises in-'
      'character voice replies, and gpt-realtime drives live '
      'sessions. No other vendor processes your voice.\n\n'
      'All providers process the photo or audio for the duration '
      'of one API request (or one Realtime session) and do not, by '
      'their default API terms, retain or train on the data we '
      'send them through the API.'),
    const LegalSection('THIRD-PARTY PROTECTION PARITY',
      'Per App Store guideline 5.1.2(i), any third party that '
      'receives Mirrorly user data must provide the same or equal '
      'privacy protection as Mirrorly itself. Both AI providers '
      'meet this bar:\n\n'
      '• OpenAI — under the standard API terms, customer inputs are '
      'excluded from model training, encrypted in transit (TLS) and '
      'at rest, processed transiently for the single request, and '
      'not used for advertising, profiling, or sale to third '
      'parties.\n'
      '• Replicate — under the standard API terms, model inputs are '
      'excluded from training, processed for the duration of one '
      'inference request, not retained long-term, and not used for '
      'advertising, profiling, or sale to third parties.\n\n'
      'Mirrorly does not transmit user photos to any other third '
      'party — no advertisers, data brokers, analytics providers, '
      'or social-login partners.'),
    const LegalSection('WHAT WE DO NOT COLLECT',
      'No name. No email. No phone number. No location. No social '
      'contacts. No tracking across other apps. No advertising '
      'identifier for profiling purposes. No voice-print '
      'biometrics. No speaker identification. No facial recognition '
      'or biometric template.'),
    const LegalSection('CHILDREN',
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
      'Opt-out of auto-renewal: $_storeName account settings.'),
    LegalSection('PURCHASES',
      'Billing is handled by $_platformAppleStore '
      '($_storeName). Mirrorly never sees your card number. We see '
      'only a receipt that confirms whether your subscription is '
      'active.'),
    const LegalSection('SECURITY',
      'Photos in transit are sent over HTTPS. On your device, '
      'photos are stored in the app\'s sandboxed documents '
      'directory and are deleted when the app is uninstalled.'),
    const LegalSection('CHANGES',
      'We may update this policy. Material changes will be '
      'surfaced inside the app before they take effect.'),
    const LegalSection('CONTACT',
      'Questions or data requests? Email info@m2mb.co.uk.'),
  ],
);
