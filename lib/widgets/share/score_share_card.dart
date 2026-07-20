import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart' as base;
import '../../theme/auralay_app_colors.dart';
import '../../theme/auralay_app_typography.dart';

/// ImHim Looks universal score share card — the one that gets posted.
///
/// 9:16 composition rendered off-screen by [ShareService.shareScore] at
/// 1080×1920 logical size. Used by every result in the app — The Gaze,
/// Eye Contact + Voice, and Free Flow — so a shared card always reads as
/// the same brand, scored the same way: out of 10.
///
///   VOICE GAME · CERTIFIED
///   ImHim Looks  ← two-tone wordmark, red "Him"
///   ───────────────
///   FREE FLOW · INTO YOU
///
///            8
///          / 10
///
///        [ MAGNETIC ]
///
///   "One brutal italic line about how it went."
///                  — LUCIEN
///
///   EYE STABILITY     ██████████░░  9
///   TENSION           ████████░░░░  7
///   ...
///
///   ImHim Looks · BECOME THE GUY WHO OWNS THE ROOM · imhim.app
class ScoreShareCard extends StatelessWidget {
  /// Brand shown at the very top — rendered as the two-tone ImHim Looks
  /// wordmark (white "Im", red "Him") so the share card matches the
  /// in-app wordmark you see on the live roleplay orb.
  static const String tagline = "BECOME THE GUY WHO OWNS THE ROOM";
  static const String domain  = 'imhim.app';

  /// What this card is for — e.g. "THE GAZE", "FREE FLOW",
  /// "EYE CONTACT + VOICE".
  final String kindLabel;

  /// The specific lesson / scene — e.g. "THE LOCK", "COLD".
  final String subLabel;

  /// 0–10.
  final int score;

  /// Single-word verdict stamp — MAGNETIC / DECIDED / 8/10 vibe word.
  final String badge;

  /// One brutal italic line (Lucien's verdict / the lesson quote).
  final String verdict;

  /// Optional breakdown rows: (label, 0–10).
  final List<({String label, int score})> stats;

  const ScoreShareCard({
    super.key,
    required this.kindLabel,
    required this.subLabel,
    required this.score,
    required this.badge,
    required this.verdict,
    this.stats = const [],
  });

  Color get _scoreColor => score >= 7
      ? AppColors.signalGreen
      : (score <= 3 ? AppColors.signalRed : AppColors.accent);

  /// Surface-specific eyebrow so the card reads clearly out of context.
  /// "FREE FLOW" → "VOICE GAME · CERTIFIED"; gaze + eye-contact surfaces
  /// get their own eyebrow so a viewer who's never seen the app knows
  /// exactly what was scored.
  String get _certifiedEyebrow {
    final k = kindLabel.toUpperCase();
    if (k.contains('FREE FLOW')) return 'VOICE GAME · CERTIFIED';
    if (k.contains('VOICE'))     return 'VOICE · CERTIFIED';
    if (k.contains('GAZE'))      return 'EYE CONTACT · CERTIFIED';
    if (k.contains('EYE'))       return 'EYE CONTACT · CERTIFIED';
    return 'CERTIFIED';
  }

  String get _date {
    final n = DateTime.now();
    const m = ['JAN','FEB','MAR','APR','MAY','JUN',
               'JUL','AUG','SEP','OCT','NOV','DEC'];
    return '${m[n.month - 1]} ${n.day.toString().padLeft(2, '0')} ${n.year}';
  }

  @override
  Widget build(BuildContext context) {
    // Fill the device-aspect canvas the ShareService composes us into, so
    // the exported card is the SAME size as the in-app full screen.
    final size = MediaQuery.of(context).size;
    return Container(
      width: size.width,
      height: size.height,
      color: AppColors.base,
      child: Stack(
        children: [
          // Atmospheric halo.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.35),
                  radius: 0.9,
                  colors: [
                    _scoreColor.withValues(alpha: 0.20),
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
                // Eyebrow — names the surface ("VOICE GAME · CERTIFIED",
                // "EYE CONTACT · CERTIFIED" etc.) so someone who has
                // never seen the app instantly knows what they're
                // looking at. Replaces the old "CERTIFICATE OF GAME"
                // which read as nothing.
                Text(_certifiedEyebrow,
                    textAlign: TextAlign.center,
                    style: AppTypography.label.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 26,
                      letterSpacing: 7,
                      fontWeight: FontWeight.w900,
                    )),
                const SizedBox(height: 22),
                // Brand — two-tone ImHim Looks wordmark, rendered at huge
                // size so the card reads as an ImHim Looks card from across
                // a feed. Drop-in for the old all-caps IMHIM LOOKS text.
                _MirrorlyMark(fontSize: 130),
                const SizedBox(height: 20),
                Container(
                    width: 120, height: 3, color: AppColors.accent),
                const SizedBox(height: 28),
                Text('$kindLabel  ·  $subLabel'.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: AppTypography.label.copyWith(
                      color: AppColors.accent,
                      fontSize: 30,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w900,
                    )),

                const Spacer(flex: 2),

                // The number.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$score',
                        style: AppTypography.display.copyWith(
                          color: _scoreColor,
                          fontSize: 360,
                          height: 0.9,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -12,
                        )),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 70),
                      child: Text(' / 10',
                          style: AppTypography.label.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 54,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w900,
                          )),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 36, vertical: 18),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(100),
                    border:
                        Border.all(color: AppColors.accentBorder, width: 2),
                  ),
                  child: Text(badge.toUpperCase(),
                      style: AppTypography.label.copyWith(
                        color: AppColors.accent,
                        fontSize: 34,
                        letterSpacing: 5,
                        fontWeight: FontWeight.w900,
                      )),
                ),

                const Spacer(flex: 1),

                if (verdict.isNotEmpty) ...[
                  Text('"$verdict"',
                      textAlign: TextAlign.center,
                      style: AppTypography.h1Italic.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 46,
                        height: 1.4,
                        fontStyle: FontStyle.italic,
                      )),
                  const SizedBox(height: 20),
                  Text('— LUCIEN',
                      style: AppTypography.label.copyWith(
                        color: AppColors.accent,
                        fontSize: 26,
                        letterSpacing: 5,
                        fontWeight: FontWeight.w900,
                      )),
                ],

                const Spacer(flex: 2),

                // Breakdown.
                if (stats.isNotEmpty)
                  ...stats.take(5).map((s) => _StatRow(
                        label: s.label,
                        score: s.score,
                      )),

                const Spacer(flex: 2),

                // Compact footer wordmark + date so the brand appears
                // again at the bottom of the card for posts cropped to
                // the score area only.
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
                          fontSize: 22,
                          letterSpacing: 4,
                          fontWeight: FontWeight.w900,
                        )),
                  ],
                ),
                const SizedBox(height: 12),
                Text('$tagline  ·  $domain',
                    textAlign: TextAlign.center,
                    style: AppTypography.label.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 22,
                      letterSpacing: 5,
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

/// Two-tone ImHim Looks wordmark — italic Playfair, white "Im" + red "Him".
/// Same recipe as widgets/common/mirrorly_wordmark.dart, copied here so the
/// share card has no dependency on the theme variant that owns the
/// canonical red. Sized purely by [fontSize].
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
          TextSpan(
            text: '  Looks',
            style: style.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: fontSize * 0.42,
              letterSpacing: 0.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final int score;
  const _StatRow({required this.label, required this.score});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 360,
            child: Text(label.toUpperCase(),
                style: AppTypography.label.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 28,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w900,
                )),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (score / 10).clamp(0.0, 1.0),
                minHeight: 14,
                backgroundColor: AppColors.surface3,
                valueColor: const AlwaysStoppedAnimation(AppColors.accent),
              ),
            ),
          ),
          const SizedBox(width: 28),
          SizedBox(
            width: 56,
            child: Text('$score',
                textAlign: TextAlign.right,
                style: AppTypography.display.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                )),
          ),
        ],
      ),
    );
  }
}
