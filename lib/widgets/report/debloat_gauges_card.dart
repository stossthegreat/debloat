import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/face_geometry.dart';
import '../../services/debloat_stats_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// THE DEBLOAT READOUT — the clean ring-gauge block that sits directly
/// under the AI drained-twin image on the results card. One hero ring for
/// the overall drained score + a small trapped-water chip, then a grid of
/// per-zone rings (Jawline, Cheekbones, Under-Eyes, Fluid Balance,
/// Submental, Symmetry). Everything is derived on-device from the scan
/// geometry — no backend call.
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

          // ── Hero row — big overall ring + water chip + tier ────────────
          Row(
            children: [
              _HeroRing(score: r.overall, tier: r.tier),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Overall drained score',
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 12.5, height: 1.3,
                        fontWeight: FontWeight.w600,
                      )),
                    const SizedBox(height: 10),
                    _WaterChip(ml: r.waterMl),
                    const SizedBox(height: 8),
                    Text(
                      r.waterMl <= 60
                          ? 'Barely any water hiding your jawline.'
                          : 'Est. water weight softening your face.',
                      style: GoogleFonts.inter(
                        color: AppColors.textTertiary,
                        fontSize: 11.5, height: 1.3,
                        fontWeight: FontWeight.w500,
                      )),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          Container(height: 1, color: AppColors.divider),
          const SizedBox(height: 16),

          // ── Per-zone gauge grid ────────────────────────────────────────
          LayoutBuilder(
            builder: (context, c) {
              const cols = 3;
              const gap = 12.0;
              final tileW = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: 18,
                children: [
                  for (final s in r.stats)
                    SizedBox(
                      width: tileW,
                      child: _ZoneGauge(stat: s),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Maps a 0..100 drained score to the ring colour: cyan when drained,
/// amber when moderate, soft-red when puffy.
Color _scoreColor(int score) {
  if (score >= 74) return AppColors.brand;
  if (score >= 60) return AppColors.signalAmber;
  if (score >= 45) return AppColors.signalAmber;
  return AppColors.signalRed;
}

// ── Hero ring — large overall drained score ────────────────────────────────
class _HeroRing extends StatelessWidget {
  final int score;
  final String tier;
  const _HeroRing({required this.score, required this.tier});

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(score);
    return SizedBox(
      width: 104, height: 104,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(104, 104),
            painter: _RingPainter(
              progress: score / 100,
              color: color,
              stroke: 9,
              trackColor: AppColors.surface3,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$score',
                style: GoogleFonts.spaceGrotesk(
                  color: AppColors.textPrimary,
                  fontSize: 34, height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.5,
                )),
              const SizedBox(height: 2),
              Text(tier.toUpperCase(),
                style: AppTypography.label.copyWith(
                  color: color,
                  fontSize: 8.5, letterSpacing: 1.6,
                  fontWeight: FontWeight.w900,
                )),
            ],
          ),
        ],
      ),
    );
  }
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

// ── Per-zone small gauge ────────────────────────────────────────────────────
class _ZoneGauge extends StatelessWidget {
  final DebloatStat stat;
  const _ZoneGauge({required this.stat});

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(stat.score);
    return Column(
      children: [
        SizedBox(
          width: 60, height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(60, 60),
                painter: _RingPainter(
                  progress: stat.score / 100,
                  color: color,
                  stroke: 5.5,
                  trackColor: AppColors.surface3,
                ),
              ),
              Text('${stat.score}',
                style: GoogleFonts.spaceGrotesk(
                  color: AppColors.textPrimary,
                  fontSize: 18, height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                )),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(stat.label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: AppColors.textSecondary,
            fontSize: 11.5, height: 1.1,
            fontWeight: FontWeight.w700,
          )),
        const SizedBox(height: 2),
        Text(stat.tier.toUpperCase(),
          style: AppTypography.label.copyWith(
            color: color,
            fontSize: 8, letterSpacing: 1.2,
            fontWeight: FontWeight.w900,
          )),
      ],
    );
  }
}

// ── Ring painter — rounded-cap arc from 12 o'clock, clockwise ───────────────
class _RingPainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;
  final double stroke;
  final Color trackColor;
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.stroke,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) - stroke) / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, math.pi * 2, false, track);

    final p = progress.clamp(0.0, 1.0);
    if (p > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: -math.pi / 2 + math.pi * 2,
          colors: [color.withValues(alpha: 0.7), color],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2, math.pi * 2 * p, false, arc);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.stroke != stroke;
}
