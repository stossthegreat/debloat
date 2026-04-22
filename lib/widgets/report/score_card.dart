import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/scoring_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// The headline card. One number, one tier, one tagline.
/// Designed to be a screenshot-worthy moment — this is the shareable hook.
class ScoreCard extends StatelessWidget {
  final AestheticScore score;

  const ScoreCard({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.lg),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topLeft,
          radius: 1.6,
          colors: [
            AppColors.red.withValues(alpha: 0.13),
            AppColors.surface1.withValues(alpha: 0.95),
            AppColors.surface1,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(Rd.xxl),
        border: Border.all(
          color: AppColors.red.withValues(alpha: 0.35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('AESTHETIC INDEX',
                style: AppTypography.label.copyWith(
                  color: AppColors.textTertiary, letterSpacing: 3.2, fontSize: 9)),
              const SizedBox(width: 8),
              _Pip(color: AppColors.textTertiary.withValues(alpha: 0.75)),
              const Spacer(),
              if (!score.reliable)
                Text('LOW CONFIDENCE',
                  style: AppTypography.label.copyWith(
                    color: AppColors.signalAmber, letterSpacing: 2.0, fontSize: 8)),
            ],
          ),
          const SizedBox(height: Sp.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(150, 150),
                      painter: _ScoreArcPainter(
                        value: score.value / 100,
                        // Arc neutralized — only the NUMBER gets the red
                        // hero treatment so the page doesn't read as "error".
                        color: AppColors.textTertiary,
                        trackColor: AppColors.surface3,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${score.value}',
                          style: AppTypography.display.copyWith(
                            fontSize: 58,
                            color: AppColors.red,
                            letterSpacing: -3,
                            height: 1,
                            fontStyle: FontStyle.italic,
                          )),
                        const SizedBox(height: 2),
                        Text('/ 100',
                          style: AppTypography.label.copyWith(
                            color: AppColors.textTertiary,
                            letterSpacing: 2.0, fontSize: 9)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Sp.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(score.tierLabel,
                        style: AppTypography.h1.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 30,
                          letterSpacing: -0.6,
                          height: 1.0,
                        ))
                        .animate().fadeIn(duration: 400.ms, delay: 200.ms),
                      const SizedBox(height: 6),
                      Text('TIER',
                        style: AppTypography.label.copyWith(
                          color: AppColors.textTertiary, letterSpacing: 2.8, fontSize: 8)),
                      const SizedBox(height: 10),
                      Text(score.tierTagline,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.5,
                          fontSize: 12,
                        )),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.md),
          _AxisBars(axes: score.axes),
        ],
      ),
    );
  }
}

class _Pip extends StatelessWidget {
  final Color color;
  const _Pip({required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: 4, height: 4,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _AxisBars extends StatelessWidget {
  final AxisBreakdown axes;
  const _AxisBars({required this.axes});

  @override
  Widget build(BuildContext context) {
    final rows = <(String, double)>[
      ('CANTHAL',   axes.canthal),
      ('SYMMETRY',  axes.symmetry),
      ('THIRDS',    axes.thirds),
      ('FWHR',      axes.fwhr),
      ('EYES',      axes.eyeSpace),
      ('JAW',       axes.jaw),
      ('CHIN',      axes.chin),
    ];
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          _AxisRow(label: rows[i].$1, value: rows[i].$2, delay: 300 + i * 60),
          if (i != rows.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _AxisRow extends StatelessWidget {
  final String label;
  final double value;
  final int delay;
  const _AxisRow({required this.label, required this.value, required this.delay});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 74,
          child: Text(label,
            style: AppTypography.label.copyWith(
              color: AppColors.textTertiary,
              fontSize: 9, letterSpacing: 2.0)),
        ),
        Expanded(
          child: Stack(
            children: [
              Container(
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.surface3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              FractionallySizedBox(
                widthFactor: value.clamp(0.0, 1.0),
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.red.withValues(alpha: 0.35),
                        AppColors.red,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.red.withValues(alpha: 0.35),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                )
                .animate()
                .fadeIn(duration: 400.ms, delay: Duration(milliseconds: delay))
                .slideX(begin: -0.3, end: 0,
                  duration: 500.ms, delay: Duration(milliseconds: delay),
                  curve: Curves.easeOutCubic),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 28,
          child: Text('${(value * 100).round()}',
            textAlign: TextAlign.right,
            style: AppTypography.measurement.copyWith(
              fontSize: 11,
              color: AppColors.red.withValues(alpha: 0.85))),
        ),
      ],
    );
  }
}

class _ScoreArcPainter extends CustomPainter {
  final double value; // 0..1
  final Color color;
  final Color trackColor;

  _ScoreArcPainter({
    required this.value,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 6;
    const startAngle = -math.pi / 2 - math.pi * 0.75;
    const sweepTotal = math.pi * 1.5;

    // Track
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, sweepTotal,
      false, trackPaint,
    );

    // Value — gold with subtle gradient shader
    final valuePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: startAngle,
        endAngle: startAngle + sweepTotal,
        colors: [
          color.withValues(alpha: 0.35),
          color,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, sweepTotal * value,
      false, valuePaint,
    );

    // Tick marks — 10 dividers around track
    final tickPaint = Paint()
      ..color = trackColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 0; i <= 10; i++) {
      final t = i / 10;
      final angle = startAngle + sweepTotal * t;
      final inner = center + Offset(math.cos(angle), math.sin(angle)) * (radius - 9);
      final outer = center + Offset(math.cos(angle), math.sin(angle)) * (radius - 5);
      canvas.drawLine(inner, outer, tickPaint);
    }
  }

  @override
  bool shouldRepaint(_ScoreArcPainter old) =>
      old.value != value || old.color != color;
}
