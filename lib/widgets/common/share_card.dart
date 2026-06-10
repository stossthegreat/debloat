import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 9:16 share unit — a stand-alone export of the hero card.
///
/// Stack (matches the on-screen hero exactly, one tweak):
///   1. Score transition   56  →  78   (red arrow, the single pop)
///      CURRENT   PROJECTED            (captions)
///   2. Before/After image              (tight crop, eyes upper third)
///      "Mirrorly" overlays top-left of the NOW half so the brand
///      sits inside the image itself instead of competing with the
///      score numbers. Bottom-corner "NOW"/"FIXED" labels preserved.
///   3. Tagline                         (italic serif, same as hero)
///   4. 3 proof lines                   (22pt all-caps, same as hero)
///
/// Padding tightened vs the previous share card so everything fits
/// comfortably in the 9:16 frame.
class ShareCard extends StatelessWidget {
  static const Color accentRed = Color(0xFFE8222A);

  final int currentScore;
  final int projectedScore;
  final String tagline;
  final Uint8List? beforeBytes;
  final String? afterUrl;
  final List<String> microProofs;

  const ShareCard({
    super.key,
    required this.currentScore,
    required this.projectedScore,
    required this.tagline,
    required this.beforeBytes,
    required this.afterUrl,
    required this.microProofs,
  });

  @override
  Widget build(BuildContext context) {
    final proofs = microProofs.take(3).toList();
    final hasScores = currentScore > 0 && projectedScore > 0;

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: ColoredBox(
        color: Colors.black,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 40, 40, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 1 · SCORE TRANSITION (or just "Mirrorly" if no scores) ──
              // Sized LARGE for 1080×1920 export. These look absurd in
              // code; at export size they read as the dominant element.
              if (hasScores) ...[
                _ScoreTransitionStatic(
                  currentScore:   currentScore,
                  projectedScore: projectedScore,
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 160, child: Text('CURRENT',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 18, letterSpacing: 3.6,
                        fontWeight: FontWeight.w700,
                      ))),
                    const SizedBox(width: 80),
                    SizedBox(width: 160, child: Text('PROJECTED',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 18, letterSpacing: 3.6,
                        fontWeight: FontWeight.w700,
                      ))),
                  ],
                ),
              ] else
                Text('ImHim',
                  style: GoogleFonts.playfairDisplay(
                    color: ShareCard.accentRed,
                    fontSize: 72, letterSpacing: -1.6,
                    fontWeight: FontWeight.w800, height: 1,
                  )),

              // Push pics down a little so the score row breathes.
              const SizedBox(height: 16),

              // ── 2 · IMAGE — matches the on-screen HeroCard exactly ──
              // 10:9 (slightly wider than square) is the same crop the
              // user sees on the report screen — face + shoulders visible,
              // hair + chin intact. Tall narrow crops (the previous
              // 5/11.25) forced BoxFit.cover to zoom hard into the middle
              // of the face and cut off both top and bottom — the share
              // looked nothing like the in-app card.
              AspectRatio(
                aspectRatio: 10 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Row(
                    children: [
                      Expanded(child: _half(
                        bytes: beforeBytes, url: null,
                        label: 'NOW', align: Alignment.bottomLeft,
                        showBrandWordmark: true,
                      )),
                      Container(width: 1, color: Colors.white),
                      Expanded(child: _half(
                        bytes: null, url: afterUrl,
                        label: 'FIXED', align: Alignment.bottomRight,
                        showBrandWordmark: false,
                      )),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 22),

              // ── 3 · TAGLINE — WHITE italic, identical to in-app HeroCard.
              // Sourced from the /rate "viral killer line" (strength-led,
              // screenshot-worthy) so it's never templated across users.
              // The in-app card prints this in white at 26pt; scaling
              // 2.7× for the 1080px share width → ~70pt.
              Center(
                child: Text(tagline,
                  textAlign: TextAlign.center,
                  maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.playfairDisplay(
                    color: Colors.white,
                    fontSize: 56, letterSpacing: -0.7,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500, height: 1.22,
                  )),
              ),

              const SizedBox(height: 26),

              // ── 4 · PROOF LINES — CAPS, WHITE, same proportions as in-app.
              // HeroCard runs these at 15pt against ~393pt-wide screens;
              // share card is 1080pt wide so 40pt keeps the relative scale.
              for (var i = 0; i < proofs.length; i++) ...[
                Text(proofs[i].toUpperCase(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 28, letterSpacing: 1.6,
                    fontWeight: FontWeight.w700, height: 1.35,
                  )),
                if (i != proofs.length - 1) const SizedBox(height: 10),
              ],

              const Spacer(),

              // ── 5 · CTA — clear, centred, brand red, button-style block.
              // Replaces the previous tiny grey "mirrorly.app" footer that
              // was lost at the corner. Anyone who sees the card knows
              // exactly where to go and that it's free.
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 22),
                  decoration: BoxDecoration(
                    color: ShareCard.accentRed,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: ShareCard.accentRed.withValues(alpha: 0.45),
                        blurRadius: 32, spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('SCAN YOUR FACE',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 32, letterSpacing: 2.4,
                          fontWeight: FontWeight.w900, height: 1,
                        )),
                      const SizedBox(height: 8),
                      Text('MIRRORLY.APP',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 22, letterSpacing: 3.2,
                          fontWeight: FontWeight.w600, height: 1,
                        )),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _half({
    required Uint8List? bytes,
    required String? url,
    required String label,
    required Alignment align,
    required bool showBrandWordmark,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (bytes != null)
          Image.memory(bytes,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.35))
        else if (url != null && url.isNotEmpty)
          Image.network(url,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.35),
            errorBuilder: (_, __, ___) =>
              const ColoredBox(color: Color(0xFF0C0C0C)))
        else
          const ColoredBox(color: Color(0xFF0C0C0C)),

        // Soft scrim along the top of the NOW half so the big red
        // "Mirrorly" wordmark reads over any skin tone or highlight.
        if (showBrandWordmark)
          Positioned(
            left: 0, right: 0, top: 0, height: 80,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.58),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

        if (showBrandWordmark)
          Positioned(
            left: 20, top: 18,
            child: Text('ImHim',
              style: GoogleFonts.playfairDisplay(
                color: ShareCard.accentRed,
                fontSize: 34, letterSpacing: -0.8,
                fontWeight: FontWeight.w900, height: 1,
                shadows: [
                  // Tight pure-black outline shadow so the red stays
                  // saturated but still reads over a bright highlight.
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.75),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              )),
          ),

        // Bottom scrim under the corner label (same as hero card's).
        Positioned(
          left: 0, right: 0, bottom: 0, height: 90,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.6),
                ],
              ),
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Align(
            alignment: align,
            child: Text(label,
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12, letterSpacing: 3.4,
                fontWeight: FontWeight.w700,
              )),
          ),
        ),
      ],
    );
  }
}

/// Static (non-animated) score transition for off-screen captures. Share
/// renders happen at a single frame, so we can't animate — draw the final
/// state directly. Geometry matches the hero card's animated version so
/// the share is visually identical to what the user sees on screen.
class _ScoreTransitionStatic extends StatelessWidget {
  final int currentScore;
  final int projectedScore;

  const _ScoreTransitionStatic({
    required this.currentScore,
    required this.projectedScore,
  });

  @override
  Widget build(BuildContext context) {
    // No fixed-width SizedBoxes on the score glyphs. A 232pt italic
    // Playfair digit renders ~110px wide; two digits plus italic
    // slope easily overflowed the previous 220px cap, which is why
    // "80" was wrapping to two lines. Let each number size to its
    // natural intrinsic width, and center the row on the arrow.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('$currentScore',
          maxLines: 1,
          style: GoogleFonts.playfairDisplay(
            fontSize: 150, height: 1.0, letterSpacing: -4.5,
            color: Colors.white.withValues(alpha: 0.62),
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w500,
          )),
        const SizedBox(width: 32),
        Text('→',
          style: GoogleFonts.inter(
            color: ShareCard.accentRed,
            fontSize: 90, height: 1,
            fontWeight: FontWeight.w300,
          )),
        const SizedBox(width: 32),
        Text('$projectedScore',
          maxLines: 1,
          style: GoogleFonts.playfairDisplay(
            fontSize: 178, height: 1.0, letterSpacing: -5.0,
            color: ShareCard.accentRed,        // the "after" number = brand red
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w700,
            shadows: [
              Shadow(
                color: ShareCard.accentRed.withValues(alpha: 0.35),
                blurRadius: 28,
              ),
            ],
          )),
      ],
    );
  }
}
