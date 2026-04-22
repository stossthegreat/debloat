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
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 200, child: Text('CURRENT',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 22, letterSpacing: 4.4,
                        fontWeight: FontWeight.w700,
                      ))),
                    const SizedBox(width: 100),
                    SizedBox(width: 200, child: Text('PROJECTED',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 22, letterSpacing: 4.4,
                        fontWeight: FontWeight.w700,
                      ))),
                  ],
                ),
              ] else
                Text('Mirrorly',
                  style: GoogleFonts.playfairDisplay(
                    color: ShareCard.accentRed,
                    fontSize: 72, letterSpacing: -1.6,
                    fontWeight: FontWeight.w800, height: 1,
                  )),

              // Push pics down a little so the score row breathes.
              const SizedBox(height: 40),

              // ── 2 · IMAGE (Mirrorly wordmark + RED on NOW side) ──
              // Flexible so the image shrinks if the bigger typography
              // above/below eats into its room — never clips.
              // User asked for ~33% bigger before/after images — aspect
              // tightened from 5:6 (0.83) to 5:8 (0.625), making the
              // image block 33% taller at the same width. Each half
              // shows substantially more of the user's face.
              Flexible(
                child: AspectRatio(
                  aspectRatio: 5 / 8,
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
              ),

              const SizedBox(height: 36),

              // ── 3 · TAGLINE — BIG italic serif quote. ──
              Center(
                child: Text(tagline,
                  textAlign: TextAlign.center,
                  maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.playfairDisplay(
                    color: Colors.white,
                    fontSize: 54, letterSpacing: -0.9,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500, height: 1.22,
                  )),
              ),

              // Tight gap — proofs sit right under the tagline so they
              // never get clipped by chat-app previews that overlay a
              // reply bar at the bottom.
              const SizedBox(height: 24),

              // ── 4 · PROOF LINES — BIG caps, RED. The "verified" flex. ──
              for (var i = 0; i < proofs.length; i++) ...[
                Text(proofs[i].toUpperCase(),
                  style: GoogleFonts.inter(
                    color: ShareCard.accentRed,
                    fontSize: 58, letterSpacing: 2.2,
                    fontWeight: FontWeight.w800, height: 1.22,
                  )),
                if (i != proofs.length - 1) const SizedBox(height: 8),
              ],

              const Spacer(),

              Align(
                alignment: Alignment.centerRight,
                child: Text('mirrorly.app',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 18, letterSpacing: 0.6,
                    fontWeight: FontWeight.w500,
                  )),
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
            child: Text('Mirrorly',
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
            fontSize: 200, height: 1.0, letterSpacing: -6.0,
            color: Colors.white.withValues(alpha: 0.62),
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w500,
          )),
        const SizedBox(width: 42),
        Text('→',
          style: GoogleFonts.inter(
            color: ShareCard.accentRed,
            fontSize: 120, height: 1,
            fontWeight: FontWeight.w300,
          )),
        const SizedBox(width: 42),
        Text('$projectedScore',
          maxLines: 1,
          style: GoogleFonts.playfairDisplay(
            fontSize: 232, height: 1.0, letterSpacing: -6.6,
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
