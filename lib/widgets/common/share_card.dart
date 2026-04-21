import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// 9:16 composed image — the share unit. All text BAKED into the image so
/// it travels everywhere and reads the same.
///
/// VIRAL SHARE FORMAT (locked):
///   1. Tiny Mirrorly wordmark, top-left
///   2. HUGE  "X CORRECTIONS." / "SAME FACE."  — the dominant message
///   3. Before / After (tight crop, full width)
///   4. Three micro-proof lines (top symmetry / exposed jaw / etc.)
///   5. Footer: "MEASURED · NOT GUESSED"   ·   mirrorly.app
///
/// Nothing else. No score number, no archetype, no percentile pills, no
/// trait grid. People share flex + transformation, not reports.
class ShareCard extends StatelessWidget {
  final Uint8List? beforeBytes;
  final String? afterUrl;
  final int correctionsCount;     // 3 → "3 CORRECTIONS."
  final List<String> microProofs; // 3 short lines, already uppercased

  const ShareCard({
    super.key,
    required this.beforeBytes,
    required this.afterUrl,
    required this.correctionsCount,
    required this.microProofs,
  });

  @override
  Widget build(BuildContext context) {
    // Show up to 3 proofs; pad with empties so layout is stable if fewer.
    final proofs = microProofs.take(3).toList();

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF080808),
          gradient: RadialGradient(
            center: const Alignment(0, -0.4),
            radius: 1.4,
            colors: [
              AppColors.gold.withValues(alpha: 0.18),
              const Color(0xFF050505),
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(38, 44, 38, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tiny brand — keeps origin clear without competing with the hook.
            Row(
              children: [
                Text('Mirrorly',
                  style: AppTypography.h1.copyWith(
                    fontSize: 26, letterSpacing: -0.7, height: 1)),
                const SizedBox(width: 8),
                Container(
                  width: 5, height: 5, margin: const EdgeInsets.only(top: 9),
                  decoration: const BoxDecoration(
                    color: AppColors.gold, shape: BoxShape.circle),
                ),
              ],
            ),

            const Spacer(flex: 2),

            // ── THE HOOK ──────────────────────────────────────────────────
            // Two stacked lines, tightest leading possible. White on top,
            // gold accent on the second so the eye lands on "SAME FACE."
            Text('$correctionsCount CORRECTIONS.',
              style: AppTypography.display.copyWith(
                fontSize: 78, height: 0.92, letterSpacing: -2.2,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
              )),
            Text('SAME FACE.',
              style: AppTypography.display.copyWith(
                fontSize: 78, height: 0.92, letterSpacing: -2.2,
                color: AppColors.gold,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                shadows: [
                  Shadow(color: AppColors.gold.withValues(alpha: 0.45),
                    blurRadius: 22),
                ],
              )),

            const Spacer(flex: 1),

            // ── BEFORE / AFTER ───────────────────────────────────────────
            // Tight, full-width, gold hairline border. No labels overlaying
            // the faces — the hook above already framed the read.
            Expanded(
              flex: 12,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.7), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.18),
                      blurRadius: 24, spreadRadius: 1),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Row(
                    children: [
                      Expanded(child: _half(beforeBytes, null)),
                      Container(width: 1.4, color: AppColors.gold),
                      Expanded(child: _half(null, afterUrl)),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── MICRO PROOF ──────────────────────────────────────────────
            // Three short bullets. Diamond glyph, all-caps, gold core / white
            // body — reads like a spec sheet, not marketing copy.
            for (final p in proofs) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('◇',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 16, height: 1,
                      fontWeight: FontWeight.w800)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(p,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppTypography.label.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 17, letterSpacing: 2.4,
                        fontWeight: FontWeight.w900,
                      )),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],

            const Spacer(flex: 1),

            // ── FOOTER ───────────────────────────────────────────────────
            Row(
              children: [
                Text('MEASURED · NOT GUESSED',
                  style: AppTypography.label.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 9.5, letterSpacing: 2.6,
                    fontWeight: FontWeight.w800)),
                const Spacer(),
                Text('mirrorly.app',
                  style: AppTypography.label.copyWith(
                    color: AppColors.gold,
                    fontSize: 10.5, letterSpacing: 2.4,
                    fontWeight: FontWeight.w900)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _half(Uint8List? bytes, String? url) {
    if (bytes != null) {
      return Image.memory(bytes, fit: BoxFit.cover);
    }
    if (url != null && url.isNotEmpty) {
      return Image.network(url, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.surface1));
    }
    return const ColoredBox(color: AppColors.surface1);
  }
}
