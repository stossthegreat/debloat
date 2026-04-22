import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Hexagonal radar chart — 6 axes of facial metrics. User's polygon drawn
/// in gold overlaid on a faint ideal polygon for reference.
///
/// Why: this is the "measured, not guessed" proof UX that Umax rides.
/// Visual confirmation that we ACTUALLY computed their features.
class RadarChart extends StatefulWidget {
  /// 6 values normalized 0..1 for the 6 axes.
  final List<double> values; // length 6
  final List<String> labels; // length 6

  const RadarChart({super.key, required this.values, required this.labels})
      : assert(values.length == 6 && labels.length == 6);

  @override
  State<RadarChart> createState() => _RadarChartState();
}

class _RadarChartState extends State<RadarChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
      ..forward();
  }
  @override
  void dispose() { _ac.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(color: AppColors.divider, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('FACIAL RADAR',
                style: AppTypography.label.copyWith(
                  color: AppColors.textTertiary, letterSpacing: 3.0, fontSize: 10)),
              const Spacer(),
              Text('Your Polygon · Ideal Polygon',
                style: AppTypography.label.copyWith(
                  color: AppColors.textMuted, fontSize: 8, letterSpacing: 1.4)),
            ],
          ),
          const SizedBox(height: 10),
          AspectRatio(
            aspectRatio: 1,
            child: AnimatedBuilder(
              animation: _ac,
              builder: (_, __) => CustomPaint(
                painter: _RadarPainter(
                  values: widget.values,
                  labels: widget.labels,
                  t: Curves.easeOutCubic.transform(_ac.value),
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }
}

class _RadarPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final double t; // 0..1 animation

  _RadarPainter({required this.values, required this.labels, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = math.min(cx, cy) - 34;
    const n = 6;

    // Concentric rings (4 levels)
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = AppColors.surface3;
    for (var r = 1; r <= 4; r++) {
      final rr = radius * (r / 4);
      final path = Path();
      for (var i = 0; i < n; i++) {
        final angle = -math.pi / 2 + i * (2 * math.pi / n);
        final x = cx + math.cos(angle) * rr;
        final y = cy + math.sin(angle) * rr;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, ringPaint);
    }

    // Axis spokes
    final spokePaint = Paint()
      ..color = AppColors.surface3.withValues(alpha: 0.8)
      ..strokeWidth = 0.6;
    for (var i = 0; i < n; i++) {
      final angle = -math.pi / 2 + i * (2 * math.pi / n);
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + math.cos(angle) * radius, cy + math.sin(angle) * radius),
        spokePaint,
      );
    }

    // Ideal polygon (faint, full hex) — reference
    final idealPath = Path();
    for (var i = 0; i < n; i++) {
      final angle = -math.pi / 2 + i * (2 * math.pi / n);
      final x = cx + math.cos(angle) * radius * 0.95;
      final y = cy + math.sin(angle) * radius * 0.95;
      if (i == 0) {
        idealPath.moveTo(x, y);
      } else {
        idealPath.lineTo(x, y);
      }
    }
    idealPath.close();
    canvas.drawPath(idealPath, Paint()
      ..color = AppColors.red.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill);
    canvas.drawPath(idealPath, Paint()
      ..color = AppColors.red.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6);

    // User polygon — animated fill
    final userPath = Path();
    for (var i = 0; i < n; i++) {
      final v = values[i].clamp(0.0, 1.0) * t;
      final angle = -math.pi / 2 + i * (2 * math.pi / n);
      final x = cx + math.cos(angle) * radius * v;
      final y = cy + math.sin(angle) * radius * v;
      if (i == 0) {
        userPath.moveTo(x, y);
      } else {
        userPath.lineTo(x, y);
      }
    }
    userPath.close();

    // Glow underlay
    canvas.drawPath(userPath, Paint()
      ..color = AppColors.red.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
    // Filled polygon
    canvas.drawPath(userPath, Paint()
      ..color = AppColors.red.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill);
    // Crisp outline
    canvas.drawPath(userPath, Paint()
      ..color = AppColors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);

    // Vertex dots on user polygon
    for (var i = 0; i < n; i++) {
      final v = values[i].clamp(0.0, 1.0) * t;
      final angle = -math.pi / 2 + i * (2 * math.pi / n);
      final x = cx + math.cos(angle) * radius * v;
      final y = cy + math.sin(angle) * radius * v;
      canvas.drawCircle(Offset(x, y), 4.5, Paint()
        ..color = AppColors.red);
      canvas.drawCircle(Offset(x, y), 1.8, Paint()
        ..color = Colors.white);
    }

    // Axis labels
    for (var i = 0; i < n; i++) {
      final angle = -math.pi / 2 + i * (2 * math.pi / n);
      final lx = cx + math.cos(angle) * (radius + 18);
      final ly = cy + math.sin(angle) * (radius + 18);
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: AppTypography.label.copyWith(
            color: AppColors.textSecondary,
            fontSize: 10, letterSpacing: 1.6,
            fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.values != values || old.labels != labels || old.t != t;
}
