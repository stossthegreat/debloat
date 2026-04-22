import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../models/protocol.dart';
import '../../models/scan_record.dart';
import '../../services/local_store_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

class ProgressScreen extends StatefulWidget {
  final ScanRecord? latest;
  final Protocol?   protocol;
  final Future<void> Function() onReload;

  const ProgressScreen({
    super.key,
    required this.latest,
    required this.protocol,
    required this.onReload,
  });

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  List<ScanRecord> _scans = [];
  List<GenerationRecord> _generations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final scans = await LocalStoreService.loadScans();
    final gens  = await LocalStoreService.loadGenerations();
    if (!mounted) return;
    setState(() {
      _scans = scans;
      _generations = gens;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadAll();
            await widget.onReload();
          },
          color: AppColors.red,
          backgroundColor: AppColors.surface1,
          child: _loading
              ? const Center(child: CircularProgressIndicator(
                  color: AppColors.red, strokeWidth: 2))
              : _scans.isEmpty
                  ? _emptyState()
                  : _body(),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return ListView(
      padding: const EdgeInsets.all(Sp.xxl),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.15),
        Icon(Icons.show_chart_rounded,
          size: 48, color: AppColors.divider),
        const SizedBox(height: Sp.md),
        Text('No history yet.',
          textAlign: TextAlign.center,
          style: AppTypography.h1.copyWith(fontSize: 26)),
        const SizedBox(height: 6),
        Text('Every scan lands here. Weekly rescans show deltas — axis by axis.',
          textAlign: TextAlign.center,
          style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: Sp.xl),
        Center(
          child: SizedBox(
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: AppColors.base,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Rd.lg)),
              ),
              onPressed: () => context.push('/scan'),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 28),
                child: Text('Begin first scan'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _body() {
    final sorted = [..._scans]..sort((a, b) => a.takenAt.compareTo(b.takenAt));
    final deltas = _computeAxisDeltas(sorted);

    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.xxl),
      children: [
        // Masthead
        Row(
          children: [
            Text('Progress',
              style: AppTypography.h1.copyWith(
                fontSize: 30, letterSpacing: -0.8, height: 1)),
            const SizedBox(width: 10),
            Container(
              width: 5, height: 5, margin: const EdgeInsets.only(top: 8),
              decoration: const BoxDecoration(
                color: AppColors.red, shape: BoxShape.circle),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text('${_scans.length} SCAN${_scans.length == 1 ? '' : 'S'}'
             ' · ${_generations.length} GENERATIONS',
          style: AppTypography.label.copyWith(
            color: AppColors.textMuted, fontSize: 8.5, letterSpacing: 2.8)),

        const SizedBox(height: Sp.xl),

        // Score-over-time chart
        _ChartCard(scans: sorted)
          .animate().fadeIn(duration: 400.ms),

        const SizedBox(height: Sp.md),

        if (deltas != null) ...[
          _DeltaRow(deltas: deltas)
            .animate().fadeIn(delay: 160.ms, duration: 400.ms),
          const SizedBox(height: Sp.md),
        ],

        _ScanHistoryList(scans: _scans)
          .animate().fadeIn(delay: 280.ms, duration: 400.ms),

        const SizedBox(height: Sp.lg),

        if (_generations.isNotEmpty) ...[
          Text('GENERATION VAULT',
            style: AppTypography.label.copyWith(
              color: AppColors.textTertiary, letterSpacing: 2.5, fontSize: 10)),
          const SizedBox(height: 6),
          Text('Every render, saved.',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary, fontSize: 12)),
          const SizedBox(height: Sp.md),
          _GenerationGrid(generations: _generations)
            .animate().fadeIn(delay: 400.ms, duration: 400.ms),
        ],
      ],
    );
  }

  /// Returns a map of axis name → (delta, percent-change) between the first
  /// and most-recent scan. Null if only one scan exists.
  Map<String, (double delta, double pctChange)>? _computeAxisDeltas(List<ScanRecord> sorted) {
    if (sorted.length < 2) return null;
    final first = sorted.first;
    final last  = sorted.last;
    double pct(double a, double b) => a == 0 ? 0 : ((b - a) / a * 100);
    return {
      'Symmetry':      (last.geometry.symmetryScore - first.geometry.symmetryScore,
                        pct(first.geometry.symmetryScore, last.geometry.symmetryScore)),
      'Jaw angle':     (last.geometry.jawAngle - first.geometry.jawAngle,
                        pct(first.geometry.jawAngle, last.geometry.jawAngle)),
      'Canthal':       (last.geometry.canthalTilt - first.geometry.canthalTilt,
                        pct(first.geometry.canthalTilt, last.geometry.canthalTilt)),
      'FWHR':          (last.geometry.fwhr - first.geometry.fwhr,
                        pct(first.geometry.fwhr, last.geometry.fwhr)),
      'Chin':          (last.geometry.chinProjection - first.geometry.chinProjection,
                        pct(first.geometry.chinProjection, last.geometry.chinProjection)),
      'Score':         ((last.score - first.score).toDouble(),
                        pct(first.score.toDouble(), last.score.toDouble())),
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Score-over-time chart
// ═══════════════════════════════════════════════════════════════════════════
class _ChartCard extends StatelessWidget {
  final List<ScanRecord> scans;
  const _ChartCard({required this.scans});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AESTHETIC INDEX · OVER TIME',
            style: AppTypography.label.copyWith(
              color: AppColors.textTertiary, letterSpacing: 2.5, fontSize: 9)),
          const SizedBox(height: Sp.md),
          SizedBox(
            height: 160,
            child: CustomPaint(
              size: Size.infinite,
              painter: _ScoreChartPainter(scans: scans),
            ),
          ),
          const SizedBox(height: Sp.sm),
          Row(
            children: [
              Text(_fmt(scans.first.takenAt),
                style: AppTypography.label.copyWith(
                  color: AppColors.textTertiary, fontSize: 8.5, letterSpacing: 1.8)),
              const Spacer(),
              Text(_fmt(scans.last.takenAt),
                style: AppTypography.label.copyWith(
                  color: AppColors.textTertiary, fontSize: 8.5, letterSpacing: 1.8)),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) {
    const months = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
    return '${d.day} ${months[d.month - 1]}';
  }
}

class _ScoreChartPainter extends CustomPainter {
  final List<ScanRecord> scans;
  _ScoreChartPainter({required this.scans});

  @override
  void paint(Canvas canvas, Size size) {
    if (scans.isEmpty) return;

    const padX = 10.0, padTop = 14.0, padBot = 14.0;
    final chartW = size.width - padX * 2;
    final chartH = size.height - padTop - padBot;

    // Find y range (either full 0-100, or tightened when data clusters high)
    final scoresOnly = scans.map((s) => s.score.toDouble()).toList();
    final minS = scoresOnly.reduce(math.min);
    final maxS = scoresOnly.reduce(math.max);
    final yMin = math.max(0.0, (minS - 8).floorToDouble());
    final yMax = math.min(100.0, (maxS + 8).ceilToDouble());
    final yRange = (yMax - yMin).clamp(1.0, 100.0);

    // Grid lines (horizontal, 4 tiers)
    final gridPaint = Paint()
      ..color = AppColors.surface3.withValues(alpha: 0.6)
      ..strokeWidth = 0.6;
    for (var i = 0; i <= 3; i++) {
      final y = padTop + chartH * (i / 3);
      canvas.drawLine(Offset(padX, y), Offset(size.width - padX, y), gridPaint);
    }

    // Compute points
    final points = <Offset>[];
    for (var i = 0; i < scans.length; i++) {
      final x = padX + (scans.length == 1 ? chartW / 2 : chartW * (i / (scans.length - 1)));
      final y = padTop + chartH * (1 - (scans[i].score - yMin) / yRange);
      points.add(Offset(x, y));
    }

    // Area fill under the line
    if (points.length > 1) {
      final areaPath = Path()
        ..moveTo(points.first.dx, padTop + chartH)
        ..lineTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        final prev = points[i - 1];
        final cur  = points[i];
        final midX = (prev.dx + cur.dx) / 2;
        areaPath.cubicTo(midX, prev.dy, midX, cur.dy, cur.dx, cur.dy);
      }
      areaPath
        ..lineTo(points.last.dx, padTop + chartH)
        ..close();
      canvas.drawPath(areaPath, Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [
            AppColors.divider,
            AppColors.divider,
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
    }

    // Main line — smooth
    if (points.length > 1) {
      final linePath = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        final prev = points[i - 1];
        final cur  = points[i];
        final midX = (prev.dx + cur.dx) / 2;
        linePath.cubicTo(midX, prev.dy, midX, cur.dy, cur.dx, cur.dy);
      }
      canvas.drawPath(linePath, Paint()
        ..color = AppColors.red
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round);
    }

    // Data points
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      canvas.drawCircle(p, 4.5, Paint()..color = AppColors.surface1);
      canvas.drawCircle(p, 4.5, Paint()
        ..color = AppColors.red
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke);

      // Only label first + last to avoid clutter
      if (i == 0 || i == points.length - 1) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${scans[i].score}',
            style: TextStyle(
              color: AppColors.red, fontSize: 10, fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              fontFamilyFallback: const ['monospace']),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy - 20));
      }
    }
  }

  @override
  bool shouldRepaint(_ScoreChartPainter old) => old.scans != scans;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Axis delta row
// ═══════════════════════════════════════════════════════════════════════════
class _DeltaRow extends StatelessWidget {
  final Map<String, (double, double)> deltas;
  const _DeltaRow({required this.deltas});

  @override
  Widget build(BuildContext context) {
    final entries = deltas.entries.toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
            child: Text('DELTA · FIRST → LATEST',
              style: AppTypography.label.copyWith(
                color: AppColors.accent, letterSpacing: 2.5, fontSize: 9)),
          ),
          const SizedBox(height: Sp.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
            child: Row(
              children: [
                for (final e in entries) ...[
                  _DeltaChip(label: e.key, delta: e.value.$1, pct: e.value.$2),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  final String label;
  final double delta, pct;
  const _DeltaChip({required this.label, required this.delta, required this.pct});

  @override
  Widget build(BuildContext context) {
    final positive = delta >= 0;
    final color = positive ? AppColors.signalGreen : AppColors.signalRed;
    final sign  = positive ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
            style: AppTypography.label.copyWith(
              color: AppColors.textSecondary, fontSize: 8, letterSpacing: 1.6)),
          const SizedBox(height: 2),
          Text('$sign${delta.toStringAsFixed(1)}',
            style: AppTypography.measurement.copyWith(
              color: color, fontSize: 13, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Scan history — list of past scans
// ═══════════════════════════════════════════════════════════════════════════
class _ScanHistoryList extends StatelessWidget {
  final List<ScanRecord> scans;
  const _ScanHistoryList({required this.scans});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SCAN HISTORY',
          style: AppTypography.label.copyWith(
            color: AppColors.textTertiary, letterSpacing: 2.5, fontSize: 10)),
        const SizedBox(height: Sp.sm),
        for (var i = 0; i < scans.length; i++) ...[
          _ScanRow(scan: scans[i], index: i + 1, total: scans.length),
          if (i < scans.length - 1)
            Container(height: 1, color: AppColors.divider,
              margin: const EdgeInsets.symmetric(vertical: 2)),
        ],
      ],
    );
  }
}

class _ScanRow extends StatelessWidget {
  final ScanRecord scan;
  final int index, total;
  const _ScanRow({required this.scan, required this.index, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.md),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(index.toString().padLeft(2, '0'),
              style: AppTypography.measurement.copyWith(
                color: AppColors.textMuted, fontSize: 12,
                fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(scan.archetypeName,
                  style: AppTypography.h3.copyWith(fontSize: 14)),
                const SizedBox(height: 2),
                Text('${scan.tierLabel} · ${_fmt(scan.takenAt)}',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiary, fontSize: 11.5)),
              ],
            ),
          ),
          Text('${scan.score}',
            style: AppTypography.measurement.copyWith(
              color: AppColors.red, fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  String _fmt(DateTime d) {
    final now = DateTime.now();
    if (now.difference(d).inDays == 0) return 'Today';
    if (now.difference(d).inDays == 1) return 'Yesterday';
    if (now.difference(d).inDays < 7)  return '${now.difference(d).inDays} d ago';
    return '${d.day}/${d.month}/${d.year.toString().substring(2)}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Generation vault — grid of all Flux images
// ═══════════════════════════════════════════════════════════════════════════
class _GenerationGrid extends StatelessWidget {
  final List<GenerationRecord> generations;
  const _GenerationGrid({required this.generations});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8,
        childAspectRatio: 0.78),
      itemCount: generations.length,
      itemBuilder: (_, i) {
        final g = generations[i];
        return ClipRRect(
          borderRadius: BorderRadius.circular(Rd.md),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(color: AppColors.surface1)),
              if (g.imageUrl.isNotEmpty)
                Image.network(g.imageUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(Icons.broken_image,
                    color: AppColors.textMuted, size: 22),
                  loadingBuilder: (c, child, p) =>
                    p == null ? child : const Center(
                      child: SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: AppColors.red))),
                ),
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
                    ),
                  ),
                  child: Text(g.prompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.label.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 8, letterSpacing: 1.2)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
