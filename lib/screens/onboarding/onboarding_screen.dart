import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/dev_flags.dart';
import '../../services/local_store_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/mirrorly_wordmark.dart';

/// Three-page onboarding. No animations, no custom painters. Every screen
/// answers one question in under six seconds:
///
///   Page 1 — THE SCAN     (MediaPipe · "we map every millimetre")
///   Page 2 — THE SCORE    (two scores · bones + looks, both real)
///   Page 3 — THE MIRROR   (AI that knows your face, advises + renders)
///
/// Each page: red eyebrow label, huge headline, short sub, one big
/// proof card that IS the visual. Big writing. Minimal copy. No reticle
/// animations, no pulsing dots — the design sells itself.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pc = PageController();
  int _i = 0;
  static const _pages = 3;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.lightImpact();
    if (_i < _pages - 1) {
      _pc.animateToPage(_i + 1,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic);
    } else {
      // Mark onboarding complete BEFORE routing to paywall. That way even
      // if the user abandons the paywall or swipes the app away, the next
      // launch skips onboarding and goes straight to home (or paywall if
      // they never purchased). User feedback: "they need to land in home."
      _finishOnboarding();
    }
  }

  Future<void> _finishOnboarding() async {
    // First-launch routing now goes straight to /scan from the
    // splash, so this onboarding flow is only reachable as a
    // fallback (e.g. user clears app data after a previous version
    // landed them here). The per-call AiConsentDialog.ensure()
    // gates on scan / chat / report / try-on / maximise still cover
    // every transmission path, so no extra gate is needed here.
    await LocalStoreService.setOnboarded(true);
    if (!mounted) return;
    // Dev-flag bypass skips the paywall; everyone lands on /home. In
    // production the paywall sits between onboarding and home exactly
    // as before.
    context.go(kBypassPaywall ? '/home' : '/paywall');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar: wordmark + page indicator ─────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      // Bumped from 22 → 30 so the onboarding scan +
                      // score + mirror pages all read as Mirrorly from
                      // the first frame of a screen recording — was
                      // previously almost invisible against the
                      // 44pt page headlines.
                      const MirrorlyWordmark(fontSize: 30, letterSpacing: -0.7),
                      const SizedBox(width: 8),
                      Container(
                        width: 4, height: 4,
                        margin: const EdgeInsets.only(top: 13),
                        decoration: const BoxDecoration(
                          color: AppColors.red, shape: BoxShape.circle),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var p = 0; p < _pages; p++) ...[
                        _PageDot(active: _i == p),
                        if (p != _pages - 1) const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // ── Pages ──────────────────────────────────────────────────────
            Expanded(
              child: PageView(
                controller: _pc,
                physics: const ClampingScrollPhysics(),
                onPageChanged: (i) => setState(() => _i = i),
                children: const [
                  _PageScan(),
                  _PageScore(),
                  _PageMirror(),
                ],
              ),
            ),

            // ── Bottom CTA ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: SizedBox(
                width: double.infinity, height: 58,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: _next,
                  child: Text(
                    _i == _pages - 1 ? 'BEGIN' : 'CONTINUE',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15, letterSpacing: 2.6,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SHARED PAGE LAYOUT — every onboarding page follows this shape so the
//  cadence feels consistent: eyebrow, huge headline, one-line sub, proof
//  card in the centre. No page breaks the rhythm.
// ═══════════════════════════════════════════════════════════════════════════
class _PageShell extends StatelessWidget {
  final String eyebrow;     // "01 · THE SCAN"
  final String headlineA;   // first line of the huge headline
  final String headlineB;   // second line
  final String sub;         // 1–2 sentences max
  final Widget card;        // the proof card

  const _PageShell({
    required this.eyebrow,
    required this.headlineA,
    required this.headlineB,
    required this.sub,
    required this.card,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(eyebrow,
            style: GoogleFonts.inter(
              color: AppColors.red,
              fontSize: 10, letterSpacing: 3.2,
              fontWeight: FontWeight.w800,
            )).animate().fadeIn(duration: 320.ms),

          const SizedBox(height: 14),

          Text(headlineA,
            style: GoogleFonts.playfairDisplay(
              color: Colors.white,
              fontSize: 44, height: 1.02,
              letterSpacing: -1.6,
              fontWeight: FontWeight.w700,
            )).animate().fadeIn(delay: 120.ms, duration: 420.ms)
              .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),

          Text(headlineB,
            style: GoogleFonts.playfairDisplay(
              color: AppColors.red,
              fontSize: 44, height: 1.02,
              letterSpacing: -1.6,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w700,
            )).animate().fadeIn(delay: 200.ms, duration: 420.ms)
              .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),

          const SizedBox(height: 18),

          Text(sub,
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 15, height: 1.5,
              fontWeight: FontWeight.w400,
            )).animate().fadeIn(delay: 280.ms, duration: 420.ms),

          const Spacer(),

          Center(child: card).animate()
            .fadeIn(delay: 360.ms, duration: 520.ms)
            .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic),

          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  PAGE 1 — THE SCAN
//  Card: mask-face icon + three live measurement rows. The card IS the
//  sales pitch — "we measure things no one else measures".
// ═══════════════════════════════════════════════════════════════════════════
class _PageScan extends StatelessWidget {
  const _PageScan();

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      eyebrow:   '01 · THE SCAN',
      headlineA: 'We map every',
      headlineB: 'millimetre.',
      sub:       'One selfie. Sixteen surgical measurements in six seconds.',
      card: _ProofCard(
        header: 'WHAT WE MEASURE',
        hero: Container(
          width: 60, height: 60,
          decoration: BoxDecoration(
            color: AppColors.red.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.55), width: 0.8),
          ),
          child: const Icon(Icons.face_retouching_natural_rounded,
            size: 34, color: AppColors.red),
        ),
        heroLabel: 'PRECISION\nFACE MAPPING',
        rows: const [
          ('CANTHAL TILT', '2.4°'),
          ('JAW ANGLE',    '118°'),
          ('SYMMETRY',     '87 / 100'),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  PAGE 2 — THE SCORE
//  Card: side-by-side scores — BONES (our geometry) and LOOKS (GPT-4 honest
//  vision rating). Proves the moat: two numbers no one else runs.
// ═══════════════════════════════════════════════════════════════════════════
class _PageScore extends StatelessWidget {
  const _PageScore();

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      eyebrow:   '02 · THE SCORE',
      headlineA: 'Two scores.',
      headlineB: 'Both honest.',
      sub:       'Your bone structure and your real-world looks, measured '
                 'separately. No flattery.',
      card: const _TwoScoreCard(bones: 74, looks: 58),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  PAGE 3 — THE MIRROR
//  Card: a specimen chat bubble from The Mirror + the GENERATE IMAGE button
//  underneath — the exact real UI they'll see once paid.
// ═══════════════════════════════════════════════════════════════════════════
class _PageMirror extends StatelessWidget {
  const _PageMirror();

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      eyebrow:   '03 · THE MIRROR',
      headlineA: 'The AI that',
      headlineB: 'knows your face.',
      sub:       'It reads your bones, tells you what suits you, and renders '
                 'you wearing it.',
      card: const _MirrorCard(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  PROOF CARDS
// ═══════════════════════════════════════════════════════════════════════════

/// Generic proof card: hero icon + header row, stacked measurement rows.
/// Used by page 1. Wide, tall, black with a red glow ring.
class _ProofCard extends StatelessWidget {
  final String header;
  final Widget hero;
  final String heroLabel;
  final List<(String, String)> rows;

  const _ProofCard({
    required this.header,
    required this.hero,
    required this.heroLabel,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.red.withValues(alpha: 0.35), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withValues(alpha: 0.18),
            blurRadius: 30, spreadRadius: -6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              hero,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(header,
                      style: GoogleFonts.inter(
                        color: AppColors.red,
                        fontSize: 9.5, letterSpacing: 2.8,
                        fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(heroLabel,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 16, height: 1.1,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.06)),
          const SizedBox(height: 14),
          for (var i = 0; i < rows.length; i++) ...[
            _ProofRow(label: rows[i].$1, value: rows[i].$2),
            if (i != rows.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ProofRow extends StatelessWidget {
  final String label;
  final String value;
  const _ProofRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
          style: GoogleFonts.inter(
            color: AppColors.textSecondary,
            fontSize: 12, letterSpacing: 1.8,
            fontWeight: FontWeight.w700)),
        Text(value,
          style: GoogleFonts.playfairDisplay(
            color: Colors.white,
            fontSize: 18, height: 1,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ──── Two-score card (page 2) ──────────────────────────────────────────────

class _TwoScoreCard extends StatelessWidget {
  final int bones;
  final int looks;
  const _TwoScoreCard({required this.bones, required this.looks});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.red.withValues(alpha: 0.35), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withValues(alpha: 0.18),
            blurRadius: 30, spreadRadius: -6),
        ],
      ),
      child: Row(
        children: [
          Expanded(child: _ScoreCol(
            label: 'BONE STRUCTURE',
            value: bones,
            tint: Colors.white,
            italic: false,
          )),
          Container(
            width: 1, height: 100,
            color: Colors.white.withValues(alpha: 0.08)),
          Expanded(child: _ScoreCol(
            label: 'HONEST LOOKS',
            value: looks,
            tint: AppColors.red,
            italic: true,
          )),
        ],
      ),
    );
  }
}

class _ScoreCol extends StatelessWidget {
  final String label;
  final int value;
  final Color tint;
  final bool italic;
  const _ScoreCol({
    required this.label, required this.value,
    required this.tint, required this.italic,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
          style: GoogleFonts.inter(
            color: AppColors.textTertiary,
            fontSize: 9, letterSpacing: 2.6,
            fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Text('$value',
          style: GoogleFonts.playfairDisplay(
            color: tint,
            fontSize: 64, height: 1,
            letterSpacing: -2.2,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            fontWeight: FontWeight.w700,
            shadows: italic ? [
              Shadow(
                color: tint.withValues(alpha: 0.35),
                blurRadius: 22),
            ] : null,
          )),
        const SizedBox(height: 4),
        Text('/ 100',
          style: GoogleFonts.inter(
            color: AppColors.textTertiary,
            fontSize: 10, letterSpacing: 2.0,
            fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ──── The Mirror card (page 3) ─────────────────────────────────────────────

/// Static snapshot of the real chat UI — a specimen assistant bubble from
/// The Mirror plus the GENERATE IMAGE button underneath. Shows exactly
/// what the paid experience looks like.
class _MirrorCard extends StatelessWidget {
  const _MirrorCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.red.withValues(alpha: 0.35), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withValues(alpha: 0.18),
            blurRadius: 30, spreadRadius: -6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mirror header row
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.red.withValues(alpha: 0.55), width: 0.8),
                ),
                child: const Center(
                  child: Icon(Icons.auto_awesome_rounded,
                    size: 15, color: AppColors.red),
                ),
              ),
              const SizedBox(width: 10),
              Text('THE MIRROR',
                style: GoogleFonts.inter(
                  color: AppColors.red,
                  fontSize: 10, letterSpacing: 2.8,
                  fontWeight: FontWeight.w800)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text('LIVE',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 8, letterSpacing: 1.6,
                    fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Specimen reply bubble
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: const BorderRadius.only(
                topLeft:  Radius.circular(6),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08), width: 0.8),
            ),
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14, height: 1.45,
                  fontWeight: FontWeight.w400),
                children: [
                  TextSpan(
                    text: 'Your jaw angle is ',
                  ),
                  TextSpan(
                    text: '124°',
                    style: GoogleFonts.playfairDisplay(
                      color: AppColors.red,
                      fontSize: 15, height: 1,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w700)),
                  TextSpan(
                    text: ' — soft side. A mid-fade with 4cm textured crop, '
                          'side-parted off the stronger cheekbone, compresses '
                          'the length and sharpens the read.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Fake GENERATE IMAGE button — visual only
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFFE8222A), Color(0xFFB31018)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.red.withValues(alpha: 0.6), width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: AppColors.red.withValues(alpha: 0.35),
                  blurRadius: 18, offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_fix_high_rounded,
                  size: 14, color: Colors.white),
                const SizedBox(width: 8),
                Text('GENERATE IMAGE',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12, letterSpacing: 2.2,
                    fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
class _PageDot extends StatelessWidget {
  final bool active;
  const _PageDot({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: active ? 20 : 6, height: 6,
      decoration: BoxDecoration(
        color: active ? AppColors.red : Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
