import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/scan_record.dart';
import '../../services/debloat_stats_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// SEMICIRCLE 60-DAY GAUGE — the compact progress arc at the top of the
/// Progress tab. Fills toward day 60 based on the earned ascension day
/// (which the streak drives), with "N / 60" underneath.
class SemiCircleDay extends StatelessWidget {
  final int day;        // 1..60 (earned)
  final int total;      // 60
  final String rankLabel;
  const SemiCircleDay({
    super.key,
    required this.day,
    required this.total,
    required this.rankLabel,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (day / total).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF0C1519), AppColors.surface1]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 230, height: 128,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                CustomPaint(
                  size: const Size(230, 128),
                  painter: _SemiPainter(progress: progress)),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$day',
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white, fontSize: 52, height: 1,
                          fontWeight: FontWeight.w800, letterSpacing: -2)),
                      Text('/ $total DAYS',
                        style: AppTypography.label.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 10.5, letterSpacing: 2.4,
                          fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: AppColors.brand.withValues(alpha: 0.4))),
            child: Text(rankLabel.toUpperCase(),
              style: AppTypography.label.copyWith(
                color: AppColors.brand, fontSize: 11,
                letterSpacing: 2.4, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

class _SemiPainter extends CustomPainter {
  final double progress;
  const _SemiPainter({required this.progress});
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 13.0;
    final center = Offset(size.width / 2, size.height - stroke / 2);
    final radius = size.width / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    // Top semicircle: start left (π), sweep π over the top to the right.
    final track = Paint()
      ..style = PaintingStyle.stroke..strokeWidth = stroke
      ..strokeCap = StrokeCap.round..color = AppColors.surface3;
    canvas.drawArc(rect, math.pi, math.pi, false, track);
    if (progress > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(
          colors: [AppColors.accentDeep, AppColors.brand],
        ).createShader(rect);
      canvas.drawArc(rect, math.pi, math.pi * progress, false, arc);
    }
  }
  @override
  bool shouldRepaint(_SemiPainter old) => old.progress != progress;
}

/// PROGRESS STATS — the bottom of the Progress tab. Debloat score over
/// time + first→latest deltas + scan history. Replaces the old
/// looksmax progress screen (canthal/FWHR/symmetry) with debloat metrics.
class ProgressStats extends StatelessWidget {
  final List<ScanRecord> scans; // any order
  const ProgressStats({super.key, required this.scans});

  @override
  Widget build(BuildContext context) {
    final sorted = [...scans]..sort((a, b) => a.takenAt.compareTo(b.takenAt));
    if (sorted.isEmpty) return const SizedBox.shrink();

    // Debloat "overall drained" score per scan.
    final points = sorted
        .map((s) => DebloatStatsService.compute(s.geometry).overall)
        .toList();
    final now = points.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Score over time ─────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.surface3)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('DEBLOAT · OVER TIME',
                    style: AppTypography.label.copyWith(
                      color: AppColors.brand, fontSize: 11,
                      letterSpacing: 2.4, fontWeight: FontWeight.w900)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.brand.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(100)),
                    child: Text('NOW $now',
                      style: AppTypography.label.copyWith(
                        color: AppColors.brand, fontSize: 11,
                        letterSpacing: 1.2, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 130,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _LinePainter(points: points)),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_dateLabel(sorted.first.takenAt), style: _axisStyle),
                  Text(_dateLabel(sorted.last.takenAt), style: _axisStyle),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Delta first → latest (debloat metrics) ──────────────────────
        if (sorted.length >= 2) ...[
          _DeltaCard(first: sorted.first, latest: sorted.last),
          const SizedBox(height: 16),
        ],

        // ── Scan history ────────────────────────────────────────────────
        Text('SCAN HISTORY',
          style: AppTypography.label.copyWith(
            color: AppColors.textTertiary, fontSize: 11,
            letterSpacing: 2.4, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        for (var i = sorted.length - 1; i >= 0; i--)
          _HistoryRow(
            index: i + 1,
            score: points[i],
            date: sorted[i].takenAt,
            isLatest: i == sorted.length - 1),
      ],
    );
  }

  static String _dateLabel(DateTime d) {
    const m = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
    return '${d.day} ${m[d.month - 1]}';
  }

  TextStyle get _axisStyle => GoogleFonts.inter(
    color: AppColors.textTertiary, fontSize: 11, fontWeight: FontWeight.w600);
}

class _DeltaCard extends StatelessWidget {
  final ScanRecord first, latest;
  const _DeltaCard({required this.first, required this.latest});

  @override
  Widget build(BuildContext context) {
    final a = DebloatStatsService.compute(first.geometry);
    final b = DebloatStatsService.compute(latest.geometry);
    int of(r, String l) {
      for (final s in r.stats) { if (s.label == l) return s.score as int; }
      return 0;
    }
    final deltas = <({String label, int d})>[
      (label: 'Overall',    d: b.overall - a.overall),
      (label: 'Jawline',    d: of(b, 'Jawline') - of(a, 'Jawline')),
      (label: 'Cheeks',     d: of(b, 'Cheekbones') - of(a, 'Cheekbones')),
      (label: 'Under-eye',  d: of(b, 'Under-Eyes') - of(a, 'Under-Eyes')),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surface3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PROGRESS · FIRST → LATEST',
            style: AppTypography.label.copyWith(
              color: AppColors.brand, fontSize: 11,
              letterSpacing: 2.0, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final x in deltas) ...[
                Expanded(child: _DeltaChip(label: x.label, delta: x.d)),
                if (x != deltas.last) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  final String label;
  final int delta;
  const _DeltaChip({required this.label, required this.delta});
  @override
  Widget build(BuildContext context) {
    final up = delta >= 0;
    final c = up ? AppColors.signalGreen : AppColors.signalRed;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.4))),
      child: Column(
        children: [
          Text(label.toUpperCase(),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: AppTypography.label.copyWith(
              color: AppColors.textSecondary, fontSize: 8.5,
              letterSpacing: 0.8, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text('${up ? '+' : ''}$delta',
            style: GoogleFonts.spaceGrotesk(
              color: c, fontSize: 19, height: 1,
              fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final int index, score;
  final DateTime date;
  final bool isLatest;
  const _HistoryRow({
    required this.index,
    required this.score,
    required this.date,
    required this.isLatest,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.6))),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(index.toString().padLeft(2, '0'),
              style: GoogleFonts.spaceGrotesk(
                color: AppColors.textTertiary, fontSize: 14,
                fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_tier(score),
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white, fontSize: 17,
                    fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                const SizedBox(height: 2),
                Text(_when(date),
                  style: GoogleFonts.inter(
                    color: AppColors.textTertiary, fontSize: 13,
                    fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Text('$score',
            style: GoogleFonts.spaceGrotesk(
              color: AppColors.brand, fontSize: 26,
              fontWeight: FontWeight.w800, letterSpacing: -1)),
        ],
      ),
    );
  }

  String _tier(int s) {
    if (s >= 88) return 'Drained';
    if (s >= 74) return 'Lean';
    if (s >= 60) return 'Moderate';
    if (s >= 45) return 'Soft';
    return 'Bloated';
  }

  String _when(DateTime d) {
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(d.year, d.month, d.day)).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    return '$days days ago';
  }
}

class _LinePainter extends CustomPainter {
  final List<int> points;
  const _LinePainter({required this.points});
  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const padTop = 16.0, padBot = 8.0;
    final chartH = size.height - padTop - padBot;
    final maxV = 100.0, minV = 0.0;
    final n = points.length;

    Offset at(int i) {
      final x = n == 1 ? size.width / 2 : size.width * (i / (n - 1));
      final y = padTop + chartH * (1 - (points[i] - minV) / (maxV - minV));
      return Offset(x, y);
    }

    // gridlines
    final grid = Paint()..color = AppColors.divider..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = padTop + chartH * (i / 2);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final pts = [for (var i = 0; i < n; i++) at(i)];
    // fill
    if (pts.length > 1) {
      final fill = Path()..moveTo(pts.first.dx, size.height - padBot);
      for (final p in pts) { fill.lineTo(p.dx, p.dy); }
      fill..lineTo(pts.last.dx, size.height - padBot)..close();
      canvas.drawPath(fill, Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [AppColors.brand.withValues(alpha: 0.28), Colors.transparent],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
    }
    // line
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) { line.lineTo(p.dx, p.dy); }
    canvas.drawPath(line, Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 3
      ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round
      ..color = AppColors.brand
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 0.5));
    // dots
    for (final p in pts) {
      canvas.drawCircle(p, 4.5, Paint()..color = AppColors.base);
      canvas.drawCircle(p, 4.5, Paint()
        ..style = PaintingStyle.stroke..strokeWidth = 2.5..color = AppColors.brand);
    }
  }
  @override
  bool shouldRepaint(_LinePainter old) => old.points != points;
}
