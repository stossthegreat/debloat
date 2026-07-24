import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/face_geometry.dart';
import '../../services/debloat_stats_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// THE DEBLOAT READOUT — the stat block directly under the AI drained-twin
/// image. v+22 restyle: the circular ring gauges are GONE (that look is
/// the exact template Apple keeps flagging as spam). The readout is now a
/// drain panel — a big numeral + tier lockup up top, then one segmented
/// horizontal drain bar per zone. Same numbers, unmistakably ours.
/// Everything is derived on-device from the scan geometry — no backend.
class DebloatGaugesCard extends StatelessWidget {
  final FaceGeometry geometry;
  const DebloatGaugesCard({super.key, required this.geometry});

  @override
  Widget build(BuildContext context) {
    final r = DebloatStatsService.compute(geometry);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(color: AppColors.surface3, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section label ──────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 5, height: 5,
                decoration: const BoxDecoration(
                  color: AppColors.brand, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text('DEBLOAT READOUT',
                style: AppTypography.label.copyWith(
                  color: AppColors.brand,
                  fontSize: 10.5, letterSpacing: 3.0,
                  fontWeight: FontWeight.w900,
                )),
            ],
          ),
          const SizedBox(height: 16),

          // ── Hero — big numeral + tier, water chip on the right ─────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('${r.overall}',
                style: GoogleFonts.spaceGrotesk(
                  color: AppColors.textPrimary,
                  fontSize: 56, height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2.5,
                )),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: _scoreColor(r.overall).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: _scoreColor(r.overall).withValues(alpha: 0.5),
                        width: 0.9),
                    ),
                    child: Text(r.tier.toUpperCase(),
                      style: AppTypography.label.copyWith(
                        color: _scoreColor(r.overall),
                        fontSize: 9.5, letterSpacing: 1.8,
                        fontWeight: FontWeight.w900,
                      )),
                  ),
                  const SizedBox(height: 5),
                  Text('DRAINED SCORE',
                    style: AppTypography.label.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 8.5, letterSpacing: 2.0,
                      fontWeight: FontWeight.w800,
                    )),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _WaterChip(ml: r.waterMl),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 128,
                    child: Text(
                      r.waterMl <= 60
                          ? 'Barely any water hiding your jawline.'
                          : 'Est. water weight softening your face.',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.inter(
                        color: AppColors.textTertiary,
                        fontSize: 10.5, height: 1.3,
                        fontWeight: FontWeight.w500,
                      )),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 18),
          Container(height: 1, color: AppColors.divider),
          const SizedBox(height: 16),

          // ── Per-zone drain bars ────────────────────────────────────────
          for (var i = 0; i < r.stats.length; i++) ...[
            _ZoneBar(stat: r.stats[i]),
            if (i != r.stats.length - 1) const SizedBox(height: 13),
          ],
        ],
      ),
    );
  }
}

/// Maps a 0..100 drained score to the fill colour: cyan when drained,
/// amber when moderate, soft-red when puffy.
Color _scoreColor(int score) {
  if (score >= 74) return AppColors.brand;
  if (score >= 45) return AppColors.signalAmber;
  return AppColors.signalRed;
}

// ── Trapped-water chip ──────────────────────────────────────────────────────
class _WaterChip extends StatelessWidget {
  final int ml;
  const _WaterChip({required this.ml});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.brandGlow,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: AppColors.brand.withValues(alpha: 0.45), width: 0.9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.water_drop_rounded,
            size: 13, color: AppColors.brand),
          const SizedBox(width: 5),
          Text('~$ml ml trapped',
            style: GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontSize: 12.5, height: 1,
              fontWeight: FontWeight.w800,
            )),
        ],
      ),
    );
  }
}

// ── One zone as a segmented drain bar ───────────────────────────────────────
class _ZoneBar extends StatelessWidget {
  final DebloatStat stat;
  const _ZoneBar({required this.stat});

  static const _segments = 10;

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(stat.score);
    final filled = (stat.score / 100 * _segments).round().clamp(0, _segments);
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(stat.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 12, height: 1.1,
                  fontWeight: FontWeight.w700,
                )),
              const SizedBox(height: 2),
              Text(stat.tier.toUpperCase(),
                style: AppTypography.label.copyWith(
                  color: color,
                  fontSize: 7.5, letterSpacing: 1.1,
                  fontWeight: FontWeight.w900,
                )),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Row(
            children: [
              for (var i = 0; i < _segments; i++) ...[
                Expanded(
                  child: Container(
                    height: 9,
                    decoration: BoxDecoration(
                      color: i < filled
                          ? color
                          : AppColors.surface3.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: i < filled
                          ? [BoxShadow(
                              color: color.withValues(alpha: 0.35),
                              blurRadius: 6)]
                          : null,
                    ),
                  ),
                ),
                if (i != _segments - 1) const SizedBox(width: 3),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 26,
          child: Text('${stat.score}',
            textAlign: TextAlign.right,
            style: GoogleFonts.spaceGrotesk(
              color: AppColors.textPrimary,
              fontSize: 15, height: 1,
              fontWeight: FontWeight.w800,
            )),
        ),
      ],
    );
  }
}
