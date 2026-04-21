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
          padding: const EdgeInsets.fromLTRB(40, 48, 40, 44),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 1 · SCORE TRANSITION (or just "Mirrorly" if no scores) ──
              // Sized for 1080×1920 export. These LOOK huge in code —
              // but on a social feed thumbnail they'll read as the
              // dominant element of the card, which is the point.
              if (hasScores) ...[
                _ScoreTransitionStatic(
                  currentScore:   currentScore,
                  projectedScore: projectedScore,
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 160, child: Text('CURRENT',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 17, letterSpacing: 4.0,
                        fontWeight: FontWeight.w700,
                      ))),
                    const SizedBox(width: 90),
                    SizedBox(width: 160, child: Text('PROJECTED',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 17, letterSpacing: 4.0,
                        fontWeight: FontWeight.w700,
                      ))),
                  ],
                ),
              ] else
                Text('Mirrorly',
                  style: GoogleFonts.playfairDisplay(
                    color: Colors.white,
                    fontSize: 54, letterSpacing: -1.2,
                    fontWeight: FontWeight.w600, height: 1,
                  )),

              const SizedBox(height: 24),

              // ── 2 · IMAGE (Mirrorly wordmark overlaid top-left of NOW) ──
              AspectRatio(
                aspectRatio: 5 / 6,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Row(
                    children: [
                      Expanded(child: _half(
                        bytes: beforeBytes, url: null,
                        label: 'NOW', align: Alignment.bottomLeft,
                        showBrandWordmark: true,   // brand lives on the NOW side
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

              const SizedBox(height: 32),

              // ── 3 · TAGLINE ──
              Center(
                child: Text(tagline,
                  textAlign: TextAlign.center,
                  maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.playfairDisplay(
                    color: Colors.white,
                    fontSize: 38, letterSpacing: -0.6,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500, height: 1.24,
                  )),
              ),

              const Spacer(),

              // ── 4 · PROOF LINES ──
              // Way bigger than before — these are the credit-line stack
              // that reads at thumbnail size on a feed. 40pt Inter-800
              // all-caps. On 1080×1920 this fills a sixth of the card.
              for (var i = 0; i < proofs.length; i++) ...[
                Text(proofs[i].toUpperCase(),
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 40, letterSpacing: 1.8,
                    fontWeight: FontWeight.w800, height: 1.25,
                  )),
                if (i != proofs.length - 1) const SizedBox(height: 6),
              ],

              const SizedBox(height: 28),

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

        // Soft scrim along the top of the NOW half so the Mirrorly
        // wordmark is legible over any skin tone / bright highlight.
        if (showBrandWordmark)
          Positioned(
            left: 0, right: 0, top: 0, height: 78,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

        if (showBrandWordmark)
          Positioned(
            left: 18, top: 16,
            child: Text('Mirrorly',
              style: GoogleFonts.playfairDisplay(
                color: Colors.white,
                fontSize: 30, letterSpacing: -0.6,
                fontWeight: FontWeight.w600, height: 1,
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 160,
          child: Text('$currentScore',
            textAlign: TextAlign.center,
            style: GoogleFonts.playfairDisplay(
              fontSize: 120, height: 1.0, letterSpacing: -3.6,
              color: Colors.white.withValues(alpha: 0.62),
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
            )),
        ),
        const SizedBox(width: 44),
        Text('→',
          style: GoogleFonts.inter(
            color: ShareCard.accentRed,
            fontSize: 76, height: 1,
            fontWeight: FontWeight.w300,
          )),
        const SizedBox(width: 44),
        SizedBox(
          width: 160,
          child: Text('$projectedScore',
            textAlign: TextAlign.center,
            style: GoogleFonts.playfairDisplay(
              fontSize: 144, height: 1.0, letterSpacing: -4.0,
              color: Colors.white,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w700,
            )),
        ),
      ],
    );
  }
}
