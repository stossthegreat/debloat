import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart' as base;
import '../../theme/auralay_app_colors.dart';
import '../../theme/auralay_app_typography.dart';

/// ImHim Looks PROGRESS share card — the receipt of the glow-up.
///
/// 9:16 composition rendered off-screen by [ShareService.shareProgress]
/// at 1080×device-aspect logical size. Designed to read as a SINGLE
/// brutal claim from the For You feed:
///
///   ┌───────────────── 9 × 16 ─────────────────┐
///   │   DAY 14 · GLOW UP · CERTIFIED           │
///   │                                          │
///   │             ImHim Looks                        │
///   │             ─────                        │
///   │                                          │
///   │             DAY                          │
///   │              14                          │
///   │           STREAK · 14 🔥                 │
///   │                                          │
///   │   AESTHETIC INDEX  →  60   (+12)         │
///   │   VOICE GAME       →  72   (+25)         │
///   │   EYE CONTACT      →  84   (+19)         │
///   │                                          │
///   │   ▁▁▂▃▅▆█  ←  spark line of the arc      │
///   │                                          │
///   │   2 SCANS · 6 GAME REPS · 4 DRILLS       │
///   │                                          │
///   │     "I scanned my face and committed."    │
///   │                                          │
///   │   ImHim Looks · BECOME THE GUY WHO OWNS THE ROOM │
///   │   imhim.app                              │
///   └──────────────────────────────────────────┘
///
/// The psychology brief — why this gets posted:
///  1. CURIOSITY GAP — a number on a black card with no explanation
///     makes the viewer scroll back and tap profile (= app discovery).
///  2. RECEIPT FRAMING — "DAY 14" / "STREAK 14" doubles as proof of
///     consistency, which is the trait the user is broadcasting.
///  3. ROOM FOR DUNK — leaving a verdict line ("committed") lets the
///     poster narrate their own version to their followers.
///  4. SAME WORDMARK AS THE APP — anyone who's seen ImHim Looks once
///     recognises the mark instantly.
class ProgressShareCard extends StatelessWidget {
  /// Days into the protocol (1..N).
  final int day;

  /// Consecutive streak days. May equal [day] (perfect streak) or be
  /// less (recovered streak).
  final int streakDays;

  /// Total scans the user has captured.
  final int scanCount;

  /// Total Free Flow reps.
  final int gameReps;

  /// Total drills done across Eyes + Voice surfaces.
  final int drillsCount;

  /// Latest aesthetic-index score (0..100).
  final int? aestheticNow;

  /// Delta from first scan to most-recent (positive = improved).
  final int? aestheticDelta;

  /// Latest voice-game score (0..100).
  final int? voiceNow;

  /// Delta in voice score across the user's reps.
  final int? voiceDelta;

  /// Aura score (0..100) — the Auralay-imported combined index.
  final int? auraNow;

  /// v290 — IMHIM LOOKS SCORE composite (0..100). The hero of the card.
  /// Looks + Game demoted to "BUILT FROM" inputs underneath; the
  /// score on top is what the viewer reads first.
  final int? imhimNow;

  /// v290 — IMHIM LOOKS SCORE delta from the prior weekly snapshot.
  /// Positive numbers render as green ↑; null / 0 hide the chip
  /// rather than show a confusing "+0".
  final int? imhimDelta;

  /// One-line user-facing verdict — usually the highest-scoring
  /// surface's last verdict so the card has a quote attached. If empty
  /// the quote block is hidden.
  final String verdict;

  /// Oldest scan photo (BEFORE) + newest scan photo (NOW), as on-disk
  /// file paths. When both are present and distinct, the card renders
  /// the BEFORE/NOW face pair the Progress screen shows. Null / equal
  /// → the pair is hidden and the card stays clean.
  final String? beforePhotoPath;
  final String? nowPhotoPath;

  const ProgressShareCard({
    super.key,
    required this.day,
    required this.streakDays,
    required this.scanCount,
    required this.gameReps,
    required this.drillsCount,
    this.aestheticNow,
    this.aestheticDelta,
    this.voiceNow,
    this.voiceDelta,
    this.auraNow,
    this.imhimNow,
    this.imhimDelta,
    this.verdict = '',
    this.beforePhotoPath,
    this.nowPhotoPath,
  });

  String get _date {
    final n = DateTime.now();
    const m = ['JAN','FEB','MAR','APR','MAY','JUN',
               'JUL','AUG','SEP','OCT','NOV','DEC'];
    return '${m[n.month - 1]} ${n.day.toString().padLeft(2, '0')} ${n.year}';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // v290 — IMHIM LOOKS SCORE leads. Bro: "imhim score is in the progress
    // icon share right now its game looks scores but above them in
    // the middle needs imhim score". Same atmospheric halo, same
    // brand. The hero number is now the unified composite (320pt
    // italic), with LOOKS / GAME demoted to the BUILT FROM input row
    // underneath. This is the consultant's "one character to level"
    // psychology applied to the share asset.

    return Container(
      width: size.width, height: size.height, color: AppColors.base,
      child: Stack(
        children: [
          // Atmospheric halo — keyed off the red brand so the card
          // doesn't shift mood when scores change.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.35),
                  radius: 0.95,
                  colors: [
                    base.AppColors.red.withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            // Top inset nudged 90 → 120 so the header cluster sits a
            // touch lower (bro: "content's a bit high, half a cm down").
            // Bottom trimmed to 32 to keep room for the full-bleed pair.
            padding: const EdgeInsets.fromLTRB(56, 120, 56, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Eyebrow — what this is.
                Text('MY GLOW UP · CERTIFIED',
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 24, letterSpacing: 6,
                    fontWeight: FontWeight.w900,
                  )),
                const SizedBox(height: 16),
                // ── Brand — two-tone ImHim Looks.
                _MirrorlyMark(fontSize: 100),
                const SizedBox(height: 12),
                Container(width: 100, height: 3, color: base.AppColors.red),
                const SizedBox(height: 22),

                // ── TAGLINE.
                Text('LOOKS GET ATTENTION.\nGAME KEEPS IT.',
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 28, letterSpacing: 2.4,
                    height: 1.18,
                    fontWeight: FontWeight.w900,
                  )),

                const SizedBox(height: 28),

                // ── IMHIM LOOKS SCORE HERO. The unified composite.
                _MirrorlyScoreShareHero(
                  score: imhimNow,
                  delta: imhimDelta,
                ),

                const SizedBox(height: 24),

                // ── Day + streak pill — anchors the score in TIME.
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 12),
                  decoration: BoxDecoration(
                    color: base.AppColors.red.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                        color: base.AppColors.red.withValues(alpha: 0.55),
                        width: 2),
                  ),
                  child: Text(
                    streakDays > 0
                        ? 'DAY $day  ·  STREAK $streakDays 🔥'
                        : 'DAY $day  ·  RAW',
                    style: AppTypography.label.copyWith(
                      color: base.AppColors.red,
                      fontSize: 22, letterSpacing: 3,
                      fontWeight: FontWeight.w900,
                    )),
                ),

                const SizedBox(height: 26),

                // ── BEFORE / NOW — the glow-up receipt, the same face
                // pair the Progress screen shows. Only when we have two
                // distinct scan photos; otherwise the card stays clean.
                if (beforePhotoPath != null &&
                    nowPhotoPath != null &&
                    beforePhotoPath != nowPhotoPath) ...[
                  // Full-bleed BEFORE/NOW — break out of the 56px gutter
                  // with an OverflowBox so the pair spans the whole card
                  // edge-to-edge, the two halves flush against each other
                  // (bro: "left side to right side, no gaps"). Labels are
                  // overlaid on each half so the photos stay full height.
                  SizedBox(
                    // Two 4:5 panes at half the card width each. A fixed
                    // height is required because an OverflowBox in a
                    // Column otherwise gets unbounded height.
                    height: size.width * 0.625,
                    child: OverflowBox(
                      minWidth: size.width,
                      maxWidth: size.width,
                      child: Row(
                        children: [
                          Expanded(child: _FacePane(
                            path:       beforePhotoPath!,
                            label:      'BEFORE',
                            labelColor: Colors.white,
                          )),
                          Expanded(child: _FacePane(
                            path:       nowPhotoPath!,
                            label:      'NOW',
                            labelColor: base.AppColors.red,
                          )),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                ],

                // ── LOOKS / GAME pills — the two inputs, in the same
                // pill language the Progress screen uses (LOOKS blue,
                // GAME gold). Replaces the old BUILT FROM bar rows.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ScorePill(
                      label: 'LOOKS',
                      value: aestheticNow,
                      accent: AppColors.accent,
                    ),
                    const SizedBox(width: 22),
                    _ScorePill(
                      label: 'GAME',
                      value: voiceNow,
                      accent: AppColors.signalAmber,
                    ),
                  ],
                ),

                const Spacer(),

                // ── Activity strip — single line of proof.
                Text(_activityLine,
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 18, letterSpacing: 3,
                    fontWeight: FontWeight.w800,
                  )),

                if (verdict.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('"$verdict"',
                    textAlign: TextAlign.center,
                    style: AppTypography.h1Italic.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 26, height: 1.4,
                      fontStyle: FontStyle.italic,
                    )),
                ],

                const SizedBox(height: 22),

                // Footer wordmark + date.
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

  String get _activityLine {
    final parts = <String>[];
    if (scanCount   > 0) parts.add('$scanCount SCAN${scanCount   == 1 ? '' : 'S'}');
    if (gameReps    > 0) parts.add('$gameReps GAME REP${gameReps == 1 ? '' : 'S'}');
    if (drillsCount > 0) parts.add('$drillsCount DRILL${drillsCount == 1 ? '' : 'S'}');
    return parts.isEmpty ? 'FIRST DAY ON THE PROTOCOL' : parts.join('  ·  ');
  }
}

/// v290 — IMHIM LOOKS SCORE share hero. Single massive italic numeral on
/// top of the share card, "/100" anchored beneath, optional weekly
/// delta pill underneath. The composite is the hook; viewers read
/// the number first, then the BUILT FROM row tells them how it was
/// earned. Same italic Playfair language as the in-app score block.
class _MirrorlyScoreShareHero extends StatelessWidget {
  final int? score;
  final int? delta;
  const _MirrorlyScoreShareHero({required this.score, required this.delta});

  @override
  Widget build(BuildContext context) {
    final hasValue   = score != null;
    final hasDelta   = hasValue && delta != null && delta != 0;
    final positive   = (delta ?? 0) >= 0;
    final deltaColor = positive ? AppColors.signalGreen : AppColors.signalRed;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('IMHIM LOOKS SCORE',
          textAlign: TextAlign.center,
          style: AppTypography.label.copyWith(
            color: base.AppColors.red,
            fontSize: 36, letterSpacing: 8,
            fontWeight: FontWeight.w900,
          )),
        const SizedBox(height: 18),
        Text(hasValue ? '${score!}' : '—',
          textAlign: TextAlign.center,
          style: AppTypography.display.copyWith(
            color: hasValue ? AppColors.textPrimary
                            : AppColors.textTertiary,
            fontSize: 360, height: 0.92,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w900,
            letterSpacing: -10,
          )),
        const SizedBox(height: 4),
        Text(hasValue ? '/ 100' : 'NOT YET',
          textAlign: TextAlign.center,
          style: AppTypography.label.copyWith(
            color: AppColors.textTertiary,
            fontSize: 26, letterSpacing: 4,
            fontWeight: FontWeight.w900,
          )),
        if (hasDelta) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              color: deltaColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: deltaColor.withValues(alpha: 0.6), width: 1.8),
            ),
            child: Text(
              '${positive ? "↑ +" : "↓ "}$delta THIS WEEK',
              style: AppTypography.label.copyWith(
                color: deltaColor,
                fontSize: 22, letterSpacing: 3,
                fontWeight: FontWeight.w900,
              )),
          ),
        ],
      ],
    );
  }
}

/// One BEFORE/NOW face tile — rounded portrait photo with a label
/// beneath, mirroring the Progress screen's glow-up pair. The image is
/// loaded from disk; [ShareService.shareProgress] precaches it before
/// the off-screen capture so it paints in the single render pass.
class _FacePane extends StatelessWidget {
  final String path;
  final String label;
  final Color labelColor;
  const _FacePane({
    required this.path,
    required this.label,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(path),
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.2),
            errorBuilder: (_, __, ___) => const ColoredBox(
              color: Color(0xFF161616),
              child: Center(
                child: Icon(Icons.person_outline_rounded,
                  color: Colors.white24, size: 90),
              ),
            ),
          ),
          // Bottom scrim so the overlaid label always reads.
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              height: 170,
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
                  color: labelColor,
                  fontSize: 30, letterSpacing: 6,
                  fontWeight: FontWeight.w900,
                )),
            ),
          ),
        ],
      ),
    );
  }
}

/// LOOKS / GAME score pill — accent-outlined capsule with the label in
/// the accent colour and the value in big white italic, matching the
/// pills on the Progress screen (LOOKS blue, GAME gold).
class _ScorePill extends StatelessWidget {
  final String label;
  final int? value;
  final Color accent;
  const _ScorePill({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 18),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: accent.withValues(alpha: 0.55), width: 2.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label,
            style: AppTypography.label.copyWith(
              color: accent,
              fontSize: 30, letterSpacing: 3,
              fontWeight: FontWeight.w900,
            )),
          const SizedBox(width: 16),
          Text(value != null ? '$value' : '—',
            style: AppTypography.display.copyWith(
              color: AppColors.textPrimary,
              fontSize: 52, height: 1,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.5,
            )),
        ],
      ),
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
