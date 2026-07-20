import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/auralay_app_colors.dart';
import '../../theme/auralay_app_typography.dart';

/// IMHIM LOOKS share card — elite edition.
///
/// 9:16 composition rendered off-screen by ShareService at 1080×1920
/// logical size (pixel ratio 2.0 → 2160×3840 PNG). Every size in this file
/// is tuned for that target — they look oversized in IDE previews and
/// correct in the feed.
///
///   ┌───────────────────────── 9 × 16 ─────────────────────────┐
///   │  EYE STRIP  (top 22%, eye-centered crop of snapshot)     │
///   │ ──────────────────────────────────────────────────────── │
///   │                                                          │
///   │                        IMHIM LOOKS ·                         │
///   │                  AURA INDEX · 01                         │
///   │                                                          │
///   │                         87                               │
///   │                    (italic red hero)                     │
///   │                                                          │
///   │                      MAGNETIC                            │
///   │                      ────────                            │
///   │                                                          │
///   │    "One brutal italic line about the result."            │
///   │                                                          │
///   │    PRESENCE      ████████████░░░  84%                   │
///   │    COMPOSURE     █████████░░░░░░  72%                   │
///   │    WARMTH        ███████░░░░░░░░  63%                   │
///   │    RANGE         ████░░░░░░░░░░░  48%                   │
///   │                                                          │
///   │   SESSION · APR 23            IMHIM.APP                │
///   └──────────────────────────────────────────────────────────┘
class EyeStripShareCard extends StatelessWidget {
  /// PNG/JPG bytes of the snapshot taken at session end.
  final Uint8List? photoBytes;

  /// Vertical center of the eyes in the photo, normalized 0–1.
  /// Defaults to 0.42 if null (typical portrait composition).
  final double? eyeYNormalized;

  /// 0..100.
  final int score;

  /// Tier stamp — single-word brand mark (MAGNETIC / SHARP / FOUNDATION / …).
  final String tier;

  /// Brutal one-line verdict.
  final String roast;

  /// Four-dimension breakdown — 0..100 each. Keys: Presence, Composure,
  /// Warmth, Range. Missing keys render as 0%.
  final Map<String, double> dimensions;

  /// Session index (1-based). Shown in small caps beneath the wordmark.
  final int sessionIndex;

  /// Technique name (e.g. "The Gaze Hold"). Shown in the footer strip.
  final String? techniqueName;

  const EyeStripShareCard({
    super.key,
    required this.photoBytes,
    required this.eyeYNormalized,
    required this.score,
    required this.tier,
    required this.roast,
    required this.dimensions,
    this.sessionIndex = 1,
    this.techniqueName,
  });

  @override
  Widget build(BuildContext context) {
    // Fill the device-aspect canvas the ShareService composes us into so the
    // exported card is the SAME size as the in-app full screen.
    final size = MediaQuery.of(context).size;
    return SizedBox(
      width: size.width,
      height: size.height,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          // Subtle corner bleed — pure black center with faint glow in the
          // upper arc. Reads as luxury rather than flat poster.
          gradient: RadialGradient(
            center: Alignment(0, -0.6),
            radius: 1.3,
            colors: [Color(0xFF0A0A0C), Color(0xFF000000)],
            stops: [0.0, 0.9],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── HERO — the eye strip (22% of 16 units) ─────────────────
            Expanded(
              flex: 22,
              child: _EyeStrip(
                photoBytes: photoBytes,
                eyeYNormalized: eyeYNormalized ?? 0.42,
              ),
            ),

            // ── MAIN — score + tier + roast + dimensions (78%) ─────────
            Expanded(
              flex: 78,
              child: Stack(
                children: [
                  // Corner crop-marks — printer's registration feel.
                  const Positioned(top: 32, left: 32,  child: _CornerMark(_Corner.tl)),
                  const Positioned(top: 32, right: 32, child: _CornerMark(_Corner.tr)),
                  const Positioned(bottom: 32, left: 32,  child: _CornerMark(_Corner.bl)),
                  const Positioned(bottom: 32, right: 32, child: _CornerMark(_Corner.br)),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(56, 44, 56, 44),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // ─── CERTIFICATE EYEBROW — says what this is ───
                        Text('CERTIFICATE OF PRESENCE',
                          style: AppTypography.label.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 16, letterSpacing: 5,
                            fontWeight: FontWeight.w900,
                          )),
                        const SizedBox(height: 16),
                        // ─── WORDMARK ROW — two-tone italic Playfair ImHim Looks
                        // + red dot. Replaces the old all-caps IMHIM LOOKS so
                        // the eye-strip card matches the rest of the share
                        // family.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            RichText(
                              text: TextSpan(
                                style: GoogleFonts.playfairDisplay(
                                  color: AppColors.textPrimary,
                                  fontSize: 64, height: 1,
                                  letterSpacing: -1.2,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w900,
                                ),
                                children: [
                                  const TextSpan(text: 'Im'),
                                  TextSpan(
                                    text: 'Him',
                                    style: GoogleFonts.playfairDisplay(
                                      color: AppColors.accent,
                                      fontSize: 64, height: 1,
                                      letterSpacing: -1.2,
                                      fontStyle: FontStyle.italic,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              width: 12, height: 12,
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: const BoxDecoration(
                                color: AppColors.accent, shape: BoxShape.circle),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text('AURA INDEX · ${sessionIndex.toString().padLeft(2, '0')}',
                          style: AppTypography.label.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 15, letterSpacing: 4.5,
                            fontWeight: FontWeight.w700,
                          )),

                        const SizedBox(height: 36),

                        // ─── HERO SCORE (the editorial centerpiece) ───
                        _HeroScore(score: score),

                        const SizedBox(height: 22),

                        // ─── TIER STAMP + HAIRLINE ─────────────────────
                        Text(tier.toUpperCase(),
                          style: AppTypography.label.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: 32, letterSpacing: 11,
                            fontWeight: FontWeight.w900,
                          )),
                        const SizedBox(height: 18),
                        Container(
                          height: 2, width: 88,
                          color: AppColors.accent.withValues(alpha: 0.65)),

                        const SizedBox(height: 36),

                        // ─── ROAST LINE ─────────────────────────────────
                        Text(
                          '"$roast"',
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.playfairDisplay(
                            color: AppColors.textPrimary.withValues(alpha: 0.94),
                            fontSize: 30, height: 1.36, letterSpacing: -0.4,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w500,
                          )),

                        const Spacer(),

                        // ─── DIMENSION/PHASE HAIRLINE BAR GRID ──────
                        _DimensionGrid(dimensions: dimensions),

                        const SizedBox(height: 38),

                        // ─── FOOTER — session stamp + wordmark ───────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              techniqueName != null
                                  ? '${techniqueName!.toUpperCase()} · ${_shortDate()}'
                                  : 'SESSION · ${_shortDate()}',
                              style: AppTypography.label.copyWith(
                                color: AppColors.textTertiary,
                                fontSize: 14, letterSpacing: 3.4,
                                fontWeight: FontWeight.w700,
                              )),
                            Text('IMHIM.APP',
                              style: AppTypography.label.copyWith(
                                color: AppColors.accent,
                                fontSize: 15, letterSpacing: 3.8,
                                fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _shortDate() {
    final now = DateTime.now();
    const months = [
      'JAN','FEB','MAR','APR','MAY','JUN',
      'JUL','AUG','SEP','OCT','NOV','DEC',
    ];
    return '${months[now.month - 1]} ${now.day.toString().padLeft(2, '0')}';
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  HERO SCORE — italic Playfair with metallic red gradient.
//  Sized for 1080×1920 output — the single loudest element on the card.
// ═════════════════════════════════════════════════════════════════════════

class _HeroScore extends StatelessWidget {
  final int score;
  const _HeroScore({required this.score});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFF4A52),  // bright crest
          Color(0xFFE8222A),  // core accent
          Color(0xFFB8141A),  // dim base
        ],
        stops: [0.0, 0.55, 1.0],
      ).createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Text(
        score.toString(),
        style: GoogleFonts.playfairDisplay(
          // Sized for social feed impact — looks absurd in IDE, lands
          // correctly when rendered at 1080×1920 and posted in-feed.
          // The score is the BILLBOARD — it must scream from the feed.
          fontSize: 320,
          height: 0.86,
          letterSpacing: -14,
          color: Colors.white, // replaced by shader
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w900,
          shadows: [
            Shadow(
              color: AppColors.accent.withValues(alpha: 0.55),
              blurRadius: 84, offset: const Offset(0, 3)),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  DIMENSION GRID — 4 labeled hairline bars
//  Replaces the dated boxed chip row. Label · track · percent per line.
// ═════════════════════════════════════════════════════════════════════════

class _DimensionGrid extends StatelessWidget {
  final Map<String, double> dimensions;
  const _DimensionGrid({required this.dimensions});

  @override
  Widget build(BuildContext context) {
    // Render whatever dimensions the caller passes, in iteration order
    // (Dart Map preserves insertion order). This lets the post-session
    // verdict use 4-dim Presence/Composure/Warmth/Range AND the new
    // charisma-test reveal use 5-phase Lock/Smile/Break/Return/Still
    // through the same share card.
    final entries = dimensions.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < entries.length; i++) ...[
          _DimBar(
            label: entries[i].key.toUpperCase(),
            value: entries[i].value.clamp(0.0, 100.0),
          ),
          if (i < entries.length - 1) const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _DimBar extends StatelessWidget {
  final String label;
  final double value; // 0..100
  const _DimBar({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final pct = (value / 100.0).clamp(0.0, 1.0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 130,
          child: Text(label,
            style: AppTypography.label.copyWith(
              color: AppColors.textSecondary.withValues(alpha: 0.88),
              fontSize: 14, letterSpacing: 3.2,
              fontWeight: FontWeight.w700,
            )),
        ),
        Expanded(
          child: Stack(
            children: [
              Container(
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              FractionallySizedBox(
                widthFactor: pct,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(1.5),
                    boxShadow: [BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.65),
                      blurRadius: 10,
                    )],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        SizedBox(
          width: 56,
          child: Text('${value.toStringAsFixed(0)}%',
            textAlign: TextAlign.right,
            style: AppTypography.label.copyWith(
              color: AppColors.textPrimary,
              fontSize: 16, letterSpacing: 0.5,
              fontWeight: FontWeight.w800,
            )),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  CORNER CROP-MARKS — L-shaped hairlines at each corner.
//  Precision/test aesthetic. Barely visible, massively elevates craft.
// ═════════════════════════════════════════════════════════════════════════

enum _Corner { tl, tr, bl, br }

class _CornerMark extends StatelessWidget {
  final _Corner corner;
  const _CornerMark(this.corner);

  @override
  Widget build(BuildContext context) {
    const color = Color(0x66E8222A);
    const thickness = 1.4;
    const size = 28.0;

    Border border;
    switch (corner) {
      case _Corner.tl:
        border = const Border(
          top:  BorderSide(color: color, width: thickness),
          left: BorderSide(color: color, width: thickness));
      case _Corner.tr:
        border = const Border(
          top:   BorderSide(color: color, width: thickness),
          right: BorderSide(color: color, width: thickness));
      case _Corner.bl:
        border = const Border(
          bottom: BorderSide(color: color, width: thickness),
          left:   BorderSide(color: color, width: thickness));
      case _Corner.br:
        border = const Border(
          bottom: BorderSide(color: color, width: thickness),
          right:  BorderSide(color: color, width: thickness));
    }
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(border: border),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  EYE STRIP — clips ONLY the eye band from the snapshot
// ═════════════════════════════════════════════════════════════════════════

class _EyeStrip extends StatelessWidget {
  final Uint8List? photoBytes;
  final double eyeYNormalized;
  const _EyeStrip({required this.photoBytes, required this.eyeYNormalized});

  @override
  Widget build(BuildContext context) {
    if (photoBytes == null) return const _StripFallback();

    return LayoutBuilder(
      builder: (_, constraints) {
        final stripW = constraints.maxWidth;
        final stripH = constraints.maxHeight;
        const sourceAspect = 3 / 4; // 4:3 portrait from camera plugin
        final scaledHeight = stripW / sourceAspect;
        final eyesPx = scaledHeight * eyeYNormalized;
        final translateY = -(eyesPx - stripH / 2);

        return ClipRect(
          child: Stack(
            children: [
              Positioned(
                left: 0, top: translateY,
                width: stripW, height: scaledHeight,
                child: Image.memory(
                  photoBytes!,
                  fit: BoxFit.cover,
                  width: stripW, height: scaledHeight,
                  errorBuilder: (_, __, ___) => const _StripFallback(),
                ),
              ),

              // Cinematic top+bottom vignette so the strip blends into the
              // black canvas above and below.
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.75),
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.82),
                      ],
                      stops: const [0.0, 0.26, 0.74, 1.0],
                    ),
                  ),
                ),
              ),

              // Subtle side red wash — brand signature without overpowering.
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        AppColors.accent.withValues(alpha: 0.10),
                        Colors.transparent,
                        AppColors.accent.withValues(alpha: 0.10),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),

              // Bottom hairline — precision divider between strip and card.
              Positioned(
                left: 44, right: 44, bottom: 0,
                child: Container(
                  height: 1,
                  color: AppColors.accent.withValues(alpha: 0.65)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StripFallback extends StatelessWidget {
  const _StripFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface1,
      child: Center(
        child: Icon(Icons.visibility_outlined,
          color: AppColors.accent.withValues(alpha: 0.4), size: 48),
      ),
    );
  }
}
