import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart' as base;
import '../../theme/auralay_app_colors.dart';
import '../../theme/auralay_app_typography.dart';

/// ImHim Looks — 60-DAY PROTOCOL CERTIFICATE share card (v291).
///
/// The receipt of the 60-day Ascension. Locked until Day 60; on
/// unlock, the user generates and shares this card from the Ascend
/// tab's Final Form panel.
///
/// 9:16 composition, same atmospheric halo + two-tone wordmark
/// language as [ProgressShareCard] and [ScoreShareCard] so a viewer
/// who's seen any ImHim Looks card before instantly recognises the brand.
/// What's different:
///
///   ┌──────────── 9 × 16 ────────────┐
///   │ 60 DAY PROTOCOL · COMPLETE     │ ← red eyebrow
///   │            ImHim Looks               │ ← wordmark, then a divider
///   │            ─────               │
///   │                                │
///   │   [Day 1 face]    [Day 60 face]│ ← real before / after
///   │     BEFORE          AFTER      │
///   │                                │
///   │       IMHIM LOOKS SCORE              │
///   │      43  →  71                 │ ← arc, big italics
///   │         ↑ +28                  │
///   │                                │
///   │     "60 days. Locked in."      │ ← italic verdict
///   │            — LUCIEN            │
///   │                                │
///   │   LOOKS         58 → 79  ↑21   │ ← supporting stat rows
///   │   GAME          34 → 88  ↑54   │
///   │   CONSISTENCY   60 → 95  ↑35   │
///   │                                │
///   │   ImHim Looks · BECOME THE GUY …     │
///   │   imhim.app                    │
///   └────────────────────────────────┘
///
/// The psychology brief:
///  1. PHOTO EVIDENCE — real before / after on top. That alone is
///     the share. Score numbers explain WHY the face changed.
///  2. ARC FRAMING — every stat is start → end → delta. The card
///     reads as a TRANSFORMATION, not a snapshot.
///  3. SAME WORDMARK — pattern-matches into the same family as the
///     Glow Up share card so users see them as one product.
class CertificateShareCard extends StatelessWidget {
  /// Local file path of the first scan's captured face photo. Null
  /// falls back to a glyph so the card never breaks if the file was
  /// pruned by iOS storage management.
  final String? beforePhotoPath;

  /// Local file path of the latest (Day-60 window) scan's photo.
  final String? afterPhotoPath;

  // ── IMHIM LOOKS SCORE arc ────────────────────────────────────────────
  final int imhimStart;
  final int imhimEnd;

  // ── Supporting stat rows. Each is (start, end). End − start gives
  //    the delta the card renders as a green pill on the right.
  final int looksStart;
  final int looksEnd;
  final int gameStart;
  final int gameEnd;
  final int consistencyStart;
  final int consistencyEnd;

  /// One italic verdict line at the bottom of the photo block.
  final String verdict;

  const CertificateShareCard({
    super.key,
    required this.imhimStart,
    required this.imhimEnd,
    required this.looksStart,
    required this.looksEnd,
    required this.gameStart,
    required this.gameEnd,
    required this.consistencyStart,
    required this.consistencyEnd,
    this.beforePhotoPath,
    this.afterPhotoPath,
    this.verdict = '60 days. You\'re not the man who started this.',
  });

  String get _date {
    final n = DateTime.now();
    const m = ['JAN','FEB','MAR','APR','MAY','JUN',
               'JUL','AUG','SEP','OCT','NOV','DEC'];
    return '${m[n.month - 1]} ${n.day.toString().padLeft(2, '0')} ${n.year}';
  }

  int get _imhimDelta       => imhimEnd       - imhimStart;
  int get _looksDelta       => looksEnd       - looksStart;
  int get _gameDelta        => gameEnd        - gameStart;
  int get _consistencyDelta => consistencyEnd - consistencyStart;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Container(
      width: size.width, height: size.height, color: AppColors.base,
      child: Stack(
        children: [
          // Atmospheric halo — same red brand keying as the other
          // ImHim Looks share cards so the family reads as one.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.30),
                  radius: 1.0,
                  colors: [
                    base.AppColors.red.withValues(alpha: 0.28),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 90, 56, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Eyebrow + brand stack
                Text('60 DAY PROTOCOL · COMPLETE',
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(
                    color: base.AppColors.red,
                    fontSize: 26, letterSpacing: 6,
                    fontWeight: FontWeight.w900,
                  )),
                const SizedBox(height: 16),
                _MirrorlyMark(fontSize: 96),
                const SizedBox(height: 12),
                Container(width: 110, height: 3, color: base.AppColors.red),
                const SizedBox(height: 22),
                Text('IMHIM CERTIFIED',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.playfairDisplay(
                    color: AppColors.textPrimary,
                    fontSize: 56, height: 1.05,
                    letterSpacing: -1.6,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w900,
                  )),

                const SizedBox(height: 36),

                // ── Before / NOW photo pair — Day 1 vs the Day-60-window
                // scan. This IS the share; the score arc explains it.
                // Full-bleed: breaks out of the 56px gutter so the pair
                // spans the whole card edge-to-edge, the two halves flush
                // against each other, labels overlaid. The transformation
                // is the hero.
                SizedBox(
                  // Two 4:5 panes at half the card width each. Fixed
                  // height — an OverflowBox in a Column would otherwise
                  // get unbounded height.
                  height: size.width * 0.625,
                  child: OverflowBox(
                    minWidth: size.width,
                    maxWidth: size.width,
                    child: Row(
                      children: [
                        Expanded(child: _CertFacePanel(
                          label:     'BEFORE',
                          imagePath: beforePhotoPath,
                          accent:    Colors.white,
                        )),
                        Expanded(child: _CertFacePanel(
                          label:     'NOW',
                          imagePath: afterPhotoPath,
                          accent:    base.AppColors.red,
                        )),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // ── IMHIM LOOKS SCORE arc. The composite headline.
                Text('IMHIM LOOKS SCORE',
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(
                    color: base.AppColors.red,
                    fontSize: 30, letterSpacing: 7,
                    fontWeight: FontWeight.w900,
                  )),
                const SizedBox(height: 14),
                _ScoreArc(
                  start:    imhimStart,
                  end:      imhimEnd,
                  delta:    _imhimDelta,
                  bigSize:  220,
                ),

                const SizedBox(height: 30),

                if (verdict.isNotEmpty) ...[
                  Text('"$verdict"',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.playfairDisplay(
                      color: AppColors.textPrimary,
                      fontSize: 30, height: 1.35,
                      letterSpacing: -0.6,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w700,
                    )),
                  const SizedBox(height: 6),
                  Text('— LUCIEN',
                    textAlign: TextAlign.center,
                    style: AppTypography.label.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 18, letterSpacing: 4,
                      fontWeight: FontWeight.w900,
                    )),
                  const SizedBox(height: 28),
                ],

                // ── Supporting stat rows (the receipt).
                _StatArcRow(
                  label: 'LOOKS',
                  start: looksStart,
                  end:   looksEnd,
                  delta: _looksDelta,
                  accent: AppColors.accent,
                ),
                // v371 — GAME arc retired (looks pivot).
                const SizedBox(height: 12),
                _StatArcRow(
                  label:  'CONSISTENCY',
                  start:  consistencyStart,
                  end:    consistencyEnd,
                  delta:  _consistencyDelta,
                  accent: base.AppColors.red,
                ),

                const Spacer(),

                // ── Footer wordmark + date
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _MirrorlyMark(fontSize: 28),
                    const SizedBox(width: 14),
                    Container(
                      width: 4, height: 4,
                      decoration: const BoxDecoration(
                        color: AppColors.textTertiary,
                        shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 14),
                    Text('CERTIFIED  $_date',
                      style: AppTypography.label.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 22, letterSpacing: 4,
                        fontWeight: FontWeight.w900,
                      )),
                  ],
                ),
                const SizedBox(height: 10),
                Text("BECOME THE GUY WHO OWNS THE ROOM  ·  imhim.app",
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 20, letterSpacing: 5,
                    fontWeight: FontWeight.w900,
                  )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Single face panel for the before / after row. Square, rounded
/// corners, accent border so AFTER reads brighter than BEFORE.
/// Falls back to a face glyph if the local file is missing — iOS
/// occasionally prunes cached photos, the certificate must still
/// render cleanly so the user has something to share.
class _CertFacePanel extends StatelessWidget {
  final String label;
  final String? imagePath;
  final Color accent;
  const _CertFacePanel({
    required this.label,
    required this.imagePath,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final file = imagePath == null ? null : File(imagePath!);
    final hasFile = file != null && file.existsSync();
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Stack(
        fit: StackFit.expand,
        children: [
          hasFile
              ? Image.file(file, fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.2),
                  errorBuilder: (_, __, ___) => _facePlaceholder())
              : _facePlaceholder(),
          // Bottom scrim so the overlaid label always reads.
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              height: 180,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0, right: 0, bottom: 30,
            child: Center(
              child: Text(label,
                style: AppTypography.label.copyWith(
                  color: accent,
                  fontSize: 32, letterSpacing: 6,
                  fontWeight: FontWeight.w900,
                )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _facePlaceholder() => Container(
        color: AppColors.surface2,
        alignment: Alignment.center,
        child: Icon(Icons.face_retouching_natural_outlined,
          size: 90, color: AppColors.textTertiary.withValues(alpha: 0.6)),
      );
}

/// Big composite score arc in the middle of the card —
/// "[start] → [end]" italic, "↑ +N" pill underneath.
class _ScoreArc extends StatelessWidget {
  final int start;
  final int end;
  final int delta;
  final double bigSize;
  const _ScoreArc({
    required this.start,
    required this.end,
    required this.delta,
    required this.bigSize,
  });

  @override
  Widget build(BuildContext context) {
    final positive = delta >= 0;
    final deltaColor =
        positive ? AppColors.signalGreen : AppColors.signalRed;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('$start',
              style: GoogleFonts.playfairDisplay(
                color: AppColors.textTertiary,
                fontSize: bigSize * 0.7, height: 0.95,
                letterSpacing: -bigSize * 0.02,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w900,
              )),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: bigSize * 0.08),
              child: Icon(Icons.arrow_forward_rounded,
                color: base.AppColors.red, size: bigSize * 0.45),
            ),
            Text('$end',
              style: GoogleFonts.playfairDisplay(
                color: AppColors.textPrimary,
                fontSize: bigSize, height: 0.95,
                letterSpacing: -bigSize * 0.03,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w900,
              )),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 22, vertical: 10),
          decoration: BoxDecoration(
            color: deltaColor.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: deltaColor.withValues(alpha: 0.7), width: 2),
          ),
          child: Text(
            positive ? '↑ +$delta' : '↓ $delta',
            style: AppTypography.label.copyWith(
              color: deltaColor,
              fontSize: 28, letterSpacing: 3,
              fontWeight: FontWeight.w900,
            )),
        ),
      ],
    );
  }
}

/// One stat row in the receipt — "LOOKS  58 → 79  +21".
/// Label left, arc middle, delta right.
class _StatArcRow extends StatelessWidget {
  final String label;
  final int start;
  final int end;
  final int delta;
  final Color accent;
  const _StatArcRow({
    required this.label,
    required this.start,
    required this.end,
    required this.delta,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final positive   = delta >= 0;
    final deltaColor =
        positive ? AppColors.signalGreen : AppColors.signalRed;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 230,
          child: Text(label,
            style: AppTypography.label.copyWith(
              color: accent,
              fontSize: 24, letterSpacing: 3.6,
              fontWeight: FontWeight.w900,
            )),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$start',
                style: GoogleFonts.playfairDisplay(
                  color: AppColors.textTertiary,
                  fontSize: 40, height: 1,
                  letterSpacing: -1.0,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w900,
                )),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward_rounded,
                  color: AppColors.textTertiary, size: 24),
              ),
              Text('$end',
                style: GoogleFonts.playfairDisplay(
                  color: AppColors.textPrimary,
                  fontSize: 54, height: 1,
                  letterSpacing: -1.4,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w900,
                )),
            ],
          ),
        ),
        SizedBox(
          width: 100,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: deltaColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: deltaColor.withValues(alpha: 0.6), width: 1.4),
            ),
            child: Text(
              positive ? '+$delta' : '$delta',
              textAlign: TextAlign.center,
              style: AppTypography.label.copyWith(
                color: deltaColor,
                fontSize: 20, letterSpacing: 1.6,
                fontWeight: FontWeight.w900,
              )),
          ),
        ),
      ],
    );
  }
}

/// Two-tone ImHim Looks wordmark — italic Playfair, white "Im" + red "Him".
/// Duplicated locally so the share card has no theme-variant dependency.
class _MirrorlyMark extends StatelessWidget {
  final double fontSize;
  const _MirrorlyMark({required this.fontSize});

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.playfairDisplay(
      fontSize:      fontSize,
      height:        1.0,
      letterSpacing: -fontSize * 0.02,
      fontStyle:     FontStyle.italic,
      fontWeight:    FontWeight.w900,
    );
    return RichText(
      text: TextSpan(
        style: style.copyWith(color: Colors.white),
        children: [
          const TextSpan(text: 'Im'),
          TextSpan(
            text: 'Him',
            style: style.copyWith(color: base.AppColors.red),
          ),
        ],
      ),
    );
  }
}
