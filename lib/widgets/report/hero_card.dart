import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_typography.dart';

/// Hero card on the report page — editorial black with one surgical red
/// accent (the score-transition arrow). Mirrors the share card's language.
///
/// Stack:
///   1.  54  →  76            (white numbers, RED arrow = the transformation)
///   2.  CURRENT · PROJECTED  (tiny captions)
///   3.  [ BEFORE | GENERATE ]  (after side carries the GENERATE button)
///   4.  "You're not unattractive. You're unoptimized."   (big italic serif)
///   5.  TOP 3% HUNTER EYES
///       TOP 5% SYMMETRY
///       STRONG JAW
///
/// The "after" half doubles as the maximize action: when no afterUrl is
/// present and the parent isn't already generating, the right side shows
/// a big red GENERATE button on a dark placeholder. Tap → onGenerate
/// fires (parent calls /maximize) → spinner fades in → image arrives →
/// the placeholder dissolves into the maxed render. Same psychological
/// beat as the Mirror tab's inline tryon.
class HeroCard extends StatefulWidget {
  static const Color accentRed   = Color(0xFFE8222A);
  static const Color projectedGreen = Color(0xFF00FF85);

  final int currentScore;
  final int projectedScore;
  final String tagline;
  final Uint8List? beforeBytes;
  final String? afterUrl;
  final int correctionsCount;     // kept for API parity, not rendered
  final List<String> microProofs;

  /// Fired when the user taps the on-image GENERATE button. Parent is
  /// expected to call /maximize and feed the resulting URL back through
  /// [afterUrl] (and flip [isGenerating] back to false).
  final VoidCallback? onGenerate;

  /// While true, the after half shows a spinner + "RENDERING…" caption
  /// instead of the GENERATE button.
  final bool isGenerating;

  /// LOCKED MODE — bro v6 conversion teaser. When true, the after
  /// half renders a blurred copy of [beforeBytes] with a centered
  /// LOCK pill + "TAP TO UNLOCK" caption. Tapping anywhere on the
  /// after half fires [onLockedTap]. Everything else stays the
  /// same — score row, tagline, proof lines — so the unlocked +
  /// locked variants of this card look identical except for the
  /// blurred half.
  final bool locked;
  final VoidCallback? onLockedTap;

  /// v263 — when true, the projected score number is replaced with a
  /// teasing "?" glyph in the same green Playfair display style.
  /// Used by the onboarding scan reveal (`_buildLockedTeaser`) so
  /// non-pro users see what they could become but not by how much,
  /// drawing the curiosity gap that converts. The PROJECTED label
  /// underneath stays visible — the label tells them what's hidden;
  /// the number is the unlock payoff.
  final bool hideProjected;

  const HeroCard({
    super.key,
    required this.currentScore,
    required this.projectedScore,
    required this.tagline,
    required this.beforeBytes,
    required this.afterUrl,
    required this.correctionsCount,
    required this.microProofs,
    this.onGenerate,
    this.isGenerating = false,
    this.locked = false,
    this.onLockedTap,
    this.hideProjected = false,
  });

  @override
  State<HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<HeroCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _counter;

  @override
  void initState() {
    super.initState();
    _counter = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
      ..forward();
  }

  @override
  void dispose() {
    _counter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final proofs = widget.microProofs.take(3).toList();

    // No border, no rounded frame, no glow. The card IS the black canvas.
    // Borders read as "UI", not as "editorial", and the user called that
    // out. Pure content, pure typography.
    //
    // Vertical rhythm tuning: the hero number sits ~1cm below the top
    // edge (top pad 56), images tuck up against the CURRENT/PROJECTED
    // labels (gap 12), and the tagline/proofs pull up against the image
    // bottom (gap 12). Image itself is 10:9 (25% shorter than the old
    // 5:6) so the whole card fits more content above the fold.
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 56, 4, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Score transition — red arrow is the single pop colour.
          _ScoreTransition(
            controller: _counter,
            currentScore: widget.currentScore,
            projectedScore: widget.projectedScore,
            hideProjected: widget.hideProjected,
          ),

          const SizedBox(height: 10),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 100, child: Text('CURRENT',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11, letterSpacing: 3.2,
                  fontWeight: FontWeight.w700,
                ))),
              const SizedBox(width: 60),
              SizedBox(width: 100, child: Text('PROJECTED',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 11, letterSpacing: 3.2,
                  fontWeight: FontWeight.w700,
                ))),
            ],
          ).animate().fadeIn(delay: 1500.ms, duration: 400.ms),

          const SizedBox(height: 12),

          // Image — 10:9 crop (25% shorter than the old 5:6 portrait),
          // sits tight under the score so the eye-path reads as one unit.
          // Right half doubles as the GENERATE action when no afterUrl is
          // present yet — see _afterHalf() for the three-state stack
          // (placeholder → spinner → image).
          AspectRatio(
            aspectRatio: 10 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Rd.sm),
              child: Row(
                children: [
                  Expanded(child: _half(
                    bytes: widget.beforeBytes, url: null,
                    label: 'NOW', align: Alignment.bottomLeft,
                    blurred: false)),
                  Container(width: 1, color: Colors.white),
                  Expanded(child: _afterHalf()),
                ],
              ),
            ),
          ).animate().fadeIn(delay: 1700.ms, duration: 500.ms),

          const SizedBox(height: 12),

          // Tagline — bigger than before so the punch lands.
          Center(
            child: Text(widget.tagline,
              textAlign: TextAlign.center,
              maxLines: 3, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.playfairDisplay(
                color: Colors.white,
                fontSize: 26, letterSpacing: -0.4,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500, height: 1.25,
              )),
          ).animate().fadeIn(delay: 1900.ms, duration: 500.ms),

          if (proofs.isNotEmpty) ...[
            const SizedBox(height: 24),

            // Proof lines — sized down (22 → 15) so they read as a trio
            // of tight supporting beats to the tagline above, not as
            // shouting peers. No bullets. No boxes. No divider.
            for (var i = 0; i < proofs.length; i++) ...[
              Text(proofs[i].toUpperCase(),
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 15, letterSpacing: 1.2,
                  fontWeight: FontWeight.w700, height: 1.35,
                ),
              ).animate().fadeIn(
                delay: Duration(milliseconds: 2100 + i * 140),
                duration: 350.ms,
              ).slideX(begin: -0.03, end: 0,
                delay: Duration(milliseconds: 2100 + i * 140),
                duration: 350.ms, curve: Curves.easeOut),
              if (i != proofs.length - 1) const SizedBox(height: 6),
            ],
          ],
        ],
      ),
    );
  }

  /// Three-state stack on the after side:
  ///   1. afterUrl present       → render the maxed image, no overlay.
  ///   2. isGenerating == true   → dark placeholder + spinner + RENDERING…
  ///   3. neither, with onGenerate
  ///                             → dark placeholder + big red GENERATE button.
  ///
  /// State (3) is the new entry point that replaces the old "TAP TO
  /// REVEAL" chip + the standalone APPLY ALL FIXES button. One tap, one
  /// place, on the image itself.
  Widget _afterHalf() {
    final url = widget.afterUrl;
    final hasUrl = url != null && url.isNotEmpty;

    // ── LOCKED MODE — bro v6 teaser. Blurred copy of the user's
    //   own NOW image on the right half + centered LOCK pill +
    //   "TAP TO UNLOCK" caption. Tappable everywhere; tap fires
    //   onLockedTap (which the report screen wires to the
    //   glow-up paywall).
    if (widget.locked) {
      return GestureDetector(
        onTap: widget.onLockedTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // beforeBytes is nullable on HeroCard — null-safety guard
            // so the locked half degrades to a flat dark surface
            // instead of crashing when the scan payload is missing
            // (only ever happens on a deep link without the bytes).
            if (widget.beforeBytes != null)
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Image.memory(widget.beforeBytes!,
                    fit: BoxFit.cover),
              )
            else
              const ColoredBox(color: Color(0xFF0C0C0C)),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end:   Alignment.bottomCenter,
                  colors: [
                    HeroCard.accentRed.withValues(alpha: 0.30),
                    HeroCard.accentRed.withValues(alpha: 0.58),
                  ],
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.6),
                        width: 1.2),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.lock_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text('TAP TO UNLOCK',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 12, letterSpacing: 2.6,
                        fontWeight: FontWeight.w900,
                      )),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 10, bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: HeroCard.accentRed.withValues(alpha: 0.6),
                    width: 0.8),
                ),
                child: Text('MAXED',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 9.5, letterSpacing: 2.2,
                    fontWeight: FontWeight.w900,
                  )),
              ),
            ),
          ],
        ),
      );
    }

    if (hasUrl) {
      return _half(
        bytes: null, url: url,
        label: 'FIXED', align: Alignment.bottomRight,
        blurred: false,
      );
    }

    // Placeholder background — keep it clearly empty rather than
    // showing a duplicate of the NOW image, so the user can tell the
    // maxed render hasn't been computed yet.
    final placeholder = const ColoredBox(color: Color(0xFF0C0C0C));

    if (widget.isGenerating) {
      return Stack(
        fit: StackFit.expand,
        children: [
          placeholder,
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: HeroCard.accentRed)),
                const SizedBox(height: 12),
                Text('RENDERING…',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 10, letterSpacing: 2.4,
                    fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      );
    }

    // Idle — show the GENERATE call to action.
    return Stack(
      fit: StackFit.expand,
      children: [
        placeholder,
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onGenerate,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: HeroCard.accentRed,
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: [
                    BoxShadow(
                      color: HeroCard.accentRed.withValues(alpha: 0.55),
                      blurRadius: 18, offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome,
                      size: 14, color: Colors.white),
                    const SizedBox(width: 8),
                    Text('GENERATE',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 11, letterSpacing: 2.4,
                        fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ),
          ),
        ).animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(begin: 0.97, end: 1.03, duration: 1200.ms,
                   curve: Curves.easeInOut),
      ],
    );
  }

  Widget _half({
    required Uint8List? bytes,
    required String? url,
    required String label,
    required Alignment align,
    required bool blurred,
    VoidCallback? onTap,
  }) {
    Widget img = bytes != null
        ? Image.memory(bytes,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.35))
        : (url != null && url.isNotEmpty
            ? Image.network(url,
                fit: BoxFit.cover,
                alignment: const Alignment(0, -0.35),
                errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: Color(0xFF0C0C0C)))
            : const ColoredBox(color: Color(0xFF0C0C0C)));

    if (blurred) {
      img = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: img,
      );
    }

    final stack = Stack(
      fit: StackFit.expand,
      children: [
        img,

        Positioned(
          left: 0, right: 0, bottom: 0, height: 64,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.55),
                ],
              ),
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Align(
            alignment: align,
            child: Text(label,
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 10.5, letterSpacing: 2.8,
                fontWeight: FontWeight.w700,
              )),
          ),
        ),
      ],
    );

    if (onTap == null) return stack;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: stack),
    );
  }
}

/// Current → arrow → projected. The arrow is THE single red accent on the
/// whole card. Everything else is white. Current in muted white (you've
/// been this all along); projected in bold white (here's where you land);
/// arrow in red (the path is the product).
class _ScoreTransition extends StatelessWidget {
  final AnimationController controller;
  final int currentScore;
  final int projectedScore;
  /// v263 — when true, render "?" instead of the projected number so
  /// the onboarding teaser hides the payoff. Same green Playfair
  /// style; the curiosity gap is the conversion driver.
  final bool hideProjected;

  const _ScoreTransition({
    required this.controller,
    required this.currentScore,
    required this.projectedScore,
    this.hideProjected = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = Curves.easeOutExpo.transform(controller.value);
        final shownCurrent = (t * currentScore).round();
        final revealT = ((controller.value - 0.7) / 0.3).clamp(0.0, 1.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 100,
              child: Text('$shownCurrent',
                textAlign: TextAlign.center,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 68, height: 1.0, letterSpacing: -2.0,
                  color: Colors.white.withValues(alpha: 0.62),
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                )),
            ),
            const SizedBox(width: 32),
            Opacity(
              opacity: revealT,
              child: Transform.scale(
                scale: 0.8 + revealT * 0.2,
                child: Text('→',
                  style: GoogleFonts.inter(
                    color: HeroCard.accentRed,
                    fontSize: 44, height: 1,
                    fontWeight: FontWeight.w300,
                  )),
              ),
            ),
            const SizedBox(width: 32),
            SizedBox(
              width: 100,
              child: Opacity(
                opacity: revealT,
                child: Transform.scale(
                  scale: 0.9 + revealT * 0.1,
                  // v263 — hideProjected swaps the number for "?" so
                  // the onboarding teaser holds the payoff back. Same
                  // green Playfair sizing so the layout doesn't shift.
                  child: Text(hideProjected ? '?' : '$projectedScore',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 82, height: 1.0, letterSpacing: -2.4,
                      // Bro v6: "make the potential number green
                      // nothing else added." This is the only score
                      // colour change — current stays white-dim,
                      // arrow stays red.
                      color: HeroCard.projectedGreen,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w700,
                    )),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
