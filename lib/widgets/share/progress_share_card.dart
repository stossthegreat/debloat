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
    final hasAes   = aestheticNow != null;
    final hasVoice = voiceNow != null;
    final hasAura  = auraNow != null;

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
                  center: const Alignment(0, -0.45),
                  radius: 0.95,
                  colors: [
                    base.AppColors.red.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(96, 120, 96, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('DAY $day · GLOW UP · CERTIFIED',
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 26, letterSpacing: 6,
                    fontWeight: FontWeight.w900,
                  )),
                const SizedBox(height: 22),
                _ImHimMark(fontSize: 130),
                const SizedBox(height: 18),
                Container(width: 120, height: 3, color: base.AppColors.red),

                const Spacer(flex: 2),

                // ── DAY hero — the receipt number. Bigger than the
                // score itself because consistency is the share angle.
                Text('DAY',
                  style: AppTypography.label.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 28, letterSpacing: 8,
                    fontWeight: FontWeight.w900,
                  )),
                const SizedBox(height: 6),
                Text('$day',
                  style: AppTypography.display.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 360, height: 0.9,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -12,
                  )),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 36, vertical: 16),
                  decoration: BoxDecoration(
                    color: base.AppColors.red.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                        color: base.AppColors.red.withValues(alpha: 0.55),
                        width: 2),
                  ),
                  child: Text(
                    streakDays > 0
                        ? 'STREAK · $streakDays 🔥'
                        : 'RAW · LOG ONE TO START',
                    style: AppTypography.label.copyWith(
                      color: base.AppColors.red,
                      fontSize: 30, letterSpacing: 4,
                      fontWeight: FontWeight.w900,
                    )),
                ),

                const Spacer(flex: 2),

                // ── Score grid — surface, value, delta. Each row only
                // appears when the user has data for it; the layout
                // collapses gracefully on day-1 share-outs (just the
                // DAY hero + counts + tagline).
                if (hasAes)
                  _ScoreRow(
                    label:  'AESTHETIC',
                    value:  aestheticNow!,
                    delta:  aestheticDelta,
                    accent: AppColors.accent,
                  ),
                if (hasVoice) ...[
                  const SizedBox(height: 14),
                  _ScoreRow(
                    label:  'VOICE GAME',
                    value:  voiceNow!,
                    delta:  voiceDelta,
                    accent: AppColors.signalAmber,
                  ),
                ],
                if (hasAura) ...[
                  const SizedBox(height: 14),
                  _ScoreRow(
                    label:  'AURA',
                    value:  auraNow!,
                    delta:  null,
                    accent: AppColors.signalGreen,
                  ),
                ],

                const Spacer(flex: 1),

                // Activity strip — single grey-tone line so it reads
                // as proof, not as the headline.
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

class _ScoreRow extends StatelessWidget {
  final String label;
  final int    value;
  final int?   delta;
  final Color  accent;
  const _ScoreRow({
    required this.label,
    required this.value,
    required this.delta,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final hasDelta = delta != null && delta != 0;
    final positive = (delta ?? 0) >= 0;
    final deltaColor = positive ? AppColors.signalGreen : AppColors.signalRed;
    return Row(
      children: [
        Expanded(
          child: Text(label,
            style: AppTypography.label.copyWith(
              color: accent,
              fontSize: 30, letterSpacing: 4,
              fontWeight: FontWeight.w900,
            )),
        ),
        Text('$value',
          style: AppTypography.display.copyWith(
            color: AppColors.textPrimary,
            fontSize: 56, height: 1,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w900,
            letterSpacing: -2,
          )),
        if (hasDelta) ...[
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: deltaColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: deltaColor.withValues(alpha: 0.55), width: 1.5),
            ),
            child: Text(
              '${positive ? '+' : ''}$delta',
              style: AppTypography.delta.copyWith(
                color: deltaColor,
                fontSize: 24, fontWeight: FontWeight.w900,
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
