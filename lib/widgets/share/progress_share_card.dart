import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart' as base;
import '../../theme/auralay_app_colors.dart';
import '../../theme/auralay_app_typography.dart';

/// ImHim PROGRESS share card — the receipt of the glow-up.
///
/// 9:16 composition rendered off-screen by [ShareService.shareProgress]
/// at 1080×device-aspect logical size. Designed to read as a SINGLE
/// brutal claim from the For You feed:
///
///   ┌───────────────── 9 × 16 ─────────────────┐
///   │   DAY 14 · GLOW UP · CERTIFIED           │
///   │                                          │
///   │             ImHim                        │
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
///   │   ImHim · BECOME THE GUY WHO OWNS THE ROOM │
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
///  4. SAME WORDMARK AS THE APP — anyone who's seen ImHim once
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

  /// One-line user-facing verdict — usually the highest-scoring
  /// surface's last verdict so the card has a quote attached. If empty
  /// the quote block is hidden.
  final String verdict;

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
    this.verdict = '',
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
    // v224 redesign: LOOKS + GAME are the two hero numbers. Aura is
    // a secondary chip. The DAY-360pt hero from v216 is downgraded
    // to a small eyebrow chip — "DAY 14 · STREAK 14 🔥" — because
    // a number alone says nothing and screenshot virality lives on
    // the two scores everyone wants to compare. People save+post
    // these because the score is the story, not the day count.

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
                    base.AppColors.red.withValues(alpha: 0.20),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 120, 72, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Eyebrow — clear "what this is".
                Text('MY GLOW UP · CERTIFIED',
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 26, letterSpacing: 7,
                    fontWeight: FontWeight.w900,
                  )),
                const SizedBox(height: 22),
                // ── Brand — two-tone ImHim.
                _ImHimMark(fontSize: 130),
                const SizedBox(height: 18),
                Container(width: 120, height: 3, color: base.AppColors.red),

                const SizedBox(height: 28),
                // ── Day + streak chip — compact, in one strip.
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14),
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
                      fontSize: 28, letterSpacing: 4,
                      fontWeight: FontWeight.w900,
                    )),
                ),

                const Spacer(flex: 2),

                // ── HERO SCORE PANELS — Looks + Game side by side.
                // This is the share angle. Two huge numbers, two
                // unambiguous labels (LOOKS, GAME), one line of
                // sub-label that names what GAME actually is so
                // first-time viewers don't have to guess.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _HeroScorePanel(
                      label:    'LOOKS',
                      subLabel: 'FACE INDEX',
                      value:    aestheticNow,
                      delta:    aestheticDelta,
                      accent:   AppColors.accent,
                    )),
                    Container(
                      width: 1, height: 220,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      color: AppColors.textTertiary.withValues(alpha: 0.35),
                    ),
                    Expanded(child: _HeroScorePanel(
                      label:    'GAME',
                      subLabel: 'VOICE · ROLEPLAY',
                      value:    voiceNow,
                      delta:    voiceDelta,
                      accent:   AppColors.signalAmber,
                    )),
                  ],
                ),

                const Spacer(flex: 1),

                // ── Aura mini-row — only if active.
                if (auraNow != null && auraNow! > 0) ...[
                  Text('AURA · ${auraNow!}',
                    style: AppTypography.label.copyWith(
                      color: AppColors.signalGreen,
                      fontSize: 24, letterSpacing: 4,
                      fontWeight: FontWeight.w900,
                    )),
                  const SizedBox(height: 12),
                ],

                // Activity strip — single line of proof.
                Text(_activityLine,
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 22, letterSpacing: 3,
                    fontWeight: FontWeight.w800,
                  )),

                const Spacer(flex: 1),

                if (verdict.isNotEmpty) ...[
                  Text('"$verdict"',
                    textAlign: TextAlign.center,
                    style: AppTypography.h1Italic.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 38, height: 1.4,
                      fontStyle: FontStyle.italic,
                    )),
                  const Spacer(flex: 1),
                ],

                // Footer wordmark + date.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _ImHimMark(fontSize: 28),
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
                const SizedBox(height: 12),
                Text("BECOME THE GUY WHO OWNS THE ROOM  ·  imhim.app",
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 22, letterSpacing: 5,
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

/// Hero score column — one big colored label, one massive italic number,
/// a thin sub-label that says exactly what the number measures, and an
/// optional delta pill. Two of these sit side-by-side as the centerpiece
/// of the v224 progress card so the share post screenshots cleanly to
/// "LOOKS 68 / GAME 72" without anyone having to read fine print.
class _HeroScorePanel extends StatelessWidget {
  final String label;
  final String subLabel;
  final int?   value;     // null → "—" placeholder + "NOT YET" sublabel
  final int?   delta;
  final Color  accent;
  const _HeroScorePanel({
    required this.label,
    required this.subLabel,
    required this.value,
    required this.delta,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue   = value != null;
    final hasDelta   = hasValue && delta != null && delta != 0;
    final positive   = (delta ?? 0) >= 0;
    final deltaColor = positive ? AppColors.signalGreen : AppColors.signalRed;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
          textAlign: TextAlign.center,
          style: AppTypography.label.copyWith(
            color: accent,
            fontSize: 38, letterSpacing: 5,
            fontWeight: FontWeight.w900,
          )),
        const SizedBox(height: 10),
        Text(hasValue ? '${value!}' : '—',
          textAlign: TextAlign.center,
          style: AppTypography.display.copyWith(
            color: hasValue ? AppColors.textPrimary
                            : AppColors.textTertiary,
            fontSize: 150, height: 0.95,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w900,
            letterSpacing: -6,
          )),
        const SizedBox(height: 6),
        Text(hasValue ? '/ 100' : 'NOT YET',
          textAlign: TextAlign.center,
          style: AppTypography.label.copyWith(
            color: AppColors.textTertiary,
            fontSize: 22, letterSpacing: 3,
            fontWeight: FontWeight.w800,
          )),
        const SizedBox(height: 6),
        Text(subLabel,
          textAlign: TextAlign.center,
          style: AppTypography.label.copyWith(
            color: AppColors.textSecondary,
            fontSize: 18, letterSpacing: 2.5,
            fontWeight: FontWeight.w700,
          )),
        if (hasDelta) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: deltaColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: deltaColor.withValues(alpha: 0.6), width: 1.5),
            ),
            child: Text(
              '${positive ? '+' : ''}$delta',
              style: AppTypography.delta.copyWith(
                color: deltaColor,
                fontSize: 22, fontWeight: FontWeight.w900,
              )),
          ),
        ],
      ],
    );
  }
}

/// Two-tone ImHim wordmark — italic Playfair, white "Im" + red "Him".
/// Duplicated locally so the share card has no theme-variant dependency.
class _ImHimMark extends StatelessWidget {
  final double fontSize;
  const _ImHimMark({required this.fontSize});

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
