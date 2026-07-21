import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';
import '../common/mirrorly_wordmark.dart';

/// BODY transformation share card — 9:16 export (1080×1920), rendered
/// offscreen by ShareService.shareBodyTransformation and never shown
/// in UI.
///
/// Layout (bro's spec — "images bigger, quick score at top of the
/// images, a hard-hitting description underneath"):
///   1. ImHim Looks wordmark + mission chip
///   2. Score row — NOW → POTENTIAL with the red arrow
///   3. THE PAIR — before/after fills most of the card (the hero)
///   4. One hard line under the images
///   5. Brand footer + domain
///
/// Both panes take BYTES (the caller pre-downloads the after render)
/// so the single offscreen paint frame always has pixels to draw —
/// no async network image race.
class BodyShareCard extends StatelessWidget {
  final Uint8List beforeBytes;
  final Uint8List afterBytes;
  final int scoreNow;
  final int scorePotential;
  final String missionName;   // SHRED / BUILD / ATHLETIC
  final String tagline;       // the hard line under the images
  const BodyShareCard({
    super.key,
    required this.beforeBytes,
    required this.afterBytes,
    required this.scoreNow,
    required this.scorePotential,
    required this.missionName,
    required this.tagline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1080,
      height: 1920,
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(56, 64, 56, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 1. Brand + mission chip.
          Row(
            children: [
              const MirrorlyWordmark(fontSize: 72),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 26, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.red,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('BODY · $missionName',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 26,
                      letterSpacing: 5,
                      fontWeight: FontWeight.w900,
                    )),
              ),
            ],
          ),

          const SizedBox(height: 44),

          // ── 2. The quick score — NOW → POTENTIAL over the images.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _score('$scoreNow', Colors.white, 'NOW'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: Icon(Icons.arrow_forward_rounded,
                    color: AppColors.red, size: 84),
              ),
              _score('$scorePotential', AppColors.signalGreen, 'POTENTIAL',
                  glow: true),
            ],
          ),

          const SizedBox(height: 40),

          // ── 3. THE PAIR — the hero. Fills the card.
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(44),
              child: Row(
                children: [
                  Expanded(
                    child: _pane(
                      bytes: beforeBytes,
                      label: 'NOW',
                      labelColor: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                  Container(width: 3, color: Colors.white),
                  Expanded(
                    child: _pane(
                      bytes: afterBytes,
                      label: 'COMMITTED',
                      labelColor: AppColors.signalGreen,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 44),

          // ── 4. The hard line.
          Text(tagline,
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                color: Colors.white,
                fontSize: 58,
                height: 1.15,
                letterSpacing: -1.0,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w800,
              )),

          const SizedBox(height: 40),

          // ── 5. Brand footer.
          Text('BECOME THE GUY WHO OWNS THE ROOM  ·  imhim.app',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 24,
                letterSpacing: 6,
                fontWeight: FontWeight.w800,
              )),
        ],
      ),
    );
  }

  Widget _score(String value, Color color, String label,
      {bool glow = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: GoogleFonts.inter(
              color: label == 'NOW'
                  ? Colors.white.withValues(alpha: 0.55)
                  : AppColors.signalGreen.withValues(alpha: 0.85),
              fontSize: 24,
              letterSpacing: 6,
              fontWeight: FontWeight.w900,
            )),
        const SizedBox(height: 4),
        Text(value,
            style: GoogleFonts.playfairDisplay(
              color: color,
              fontSize: 128,
              height: 0.95,
              letterSpacing: -5,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w900,
              shadows: glow
                  ? [
                      Shadow(
                        color: AppColors.signalGreen.withValues(alpha: 0.45),
                        blurRadius: 40,
                      ),
                    ]
                  : null,
            )),
      ],
    );
  }

  Widget _pane({
    required Uint8List bytes,
    required String label,
    required Color labelColor,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(bytes, fit: BoxFit.cover),
        // Bottom scrim so the corner label always reads.
        Positioned(
          left: 0, right: 0, bottom: 0, height: 140,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.72),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 26),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Text(label,
                style: GoogleFonts.inter(
                  color: labelColor,
                  fontSize: 30,
                  letterSpacing: 7,
                  fontWeight: FontWeight.w900,
                )),
          ),
        ),
      ],
    );
  }
}
