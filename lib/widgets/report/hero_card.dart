import 'dart:typed_data';
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
///   3.  [ BEFORE | AFTER ]   (tight face crop, eyes in upper third)
///   4.  "You're not unattractive. You're unoptimized."   (big italic serif)
///   5.  TOP 3% HUNTER EYES   (22pt all-caps, white, big enough to read)
///       TOP 5% SYMMETRY
///       STRONG JAW
class HeroCard extends StatefulWidget {
  static const Color accentRed = Color(0xFFE8222A);

  final int currentScore;
  final int projectedScore;
  final String tagline;
  final Uint8List? beforeBytes;
  final String? afterUrl;
  final int correctionsCount;     // kept for API parity, not rendered
  final List<String> microProofs;

  const HeroCard({
    super.key,
    required this.currentScore,
    required this.projectedScore,
    required this.tagline,
    required this.beforeBytes,
    required this.afterUrl,
    required this.correctionsCount,
    required this.microProofs,
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
          AspectRatio(
            aspectRatio: 10 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Rd.sm),
              child: Row(
                children: [
                  Expanded(child: _half(
                    bytes: widget.beforeBytes, url: null,
                    label: 'NOW', align: Alignment.bottomLeft)),
                  Container(width: 1, color: Colors.white),
                  Expanded(child: _half(
                    bytes: null, url: widget.afterUrl,
                    label: 'FIXED', align: Alignment.bottomRight)),
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
            const SizedBox(height: 28),

            // Proof lines — big, all-caps, readable from across the room.
            // No bullets. No boxes. No divider. The spacing is the structure.
            for (var i = 0; i < proofs.length; i++) ...[
              Text(proofs[i].toUpperCase(),
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 22, letterSpacing: 1.5,
                  fontWeight: FontWeight.w700, height: 1.35,
                ),
              ).animate().fadeIn(
                delay: Duration(milliseconds: 2100 + i * 140),
                duration: 350.ms,
              ).slideX(begin: -0.03, end: 0,
                delay: Duration(milliseconds: 2100 + i * 140),
                duration: 350.ms, curve: Curves.easeOut),
              if (i != proofs.length - 1) const SizedBox(height: 4),
            ],
          ],
        ],
      ),
    );
  }

  Widget _half({
    required Uint8List? bytes,
    required String? url,
    required String label,
    required Alignment align,
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

  const _ScoreTransition({
    required this.controller,
    required this.currentScore,
    required this.projectedScore,
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
                  child: Text('$projectedScore',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 82, height: 1.0, letterSpacing: -2.4,
                      color: Colors.white,
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
