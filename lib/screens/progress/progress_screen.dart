import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/protocol.dart';
import '../../models/scan_record.dart';
import '../../services/analytics_service.dart';
import '../../services/face_asset_service.dart';
import '../../services/local_store_service.dart';
import '../../services/ascension_service.dart';
import '../../services/protocol_service.dart';
import '../../services/streak_service.dart';
import '../../services/share_service.dart';
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
    // ignore: discarded_futures
    AnalyticsService.progressScreenViewed();
    _loadAll();
  }

  // v379 — LOOKS ONLY. The Auralay graft (Aura score, gaze/voice drill
  // counts, curriculum) and the game-score history are gone from this
  // surface with the looks pivot; the tab reads scans + renders, full
  // stop.
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
              // Empty-state until the first scan lands — the tab is
              // looks-only, so the scan history IS the data.
              : _scans.isEmpty
                  ? _emptyState()
                  : _body(),
        ),
      ),
    );
  }

  Widget _emptyState() => const _ProgressLocked();

  Widget _body() {
    final sorted = [..._scans]..sort((a, b) => a.takenAt.compareTo(b.takenAt));
    final deltas = _scans.length >= 2 ? _computeAxisDeltas(sorted) : null;
    final hasScans = _scans.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.xxl),
      children: [
        // Masthead — title + heartbeat dot, with a SHARE button +
        // CLOSE X on the right. SHARE renders the ImHim Progress
        // receipt off-screen (DAY hero, streak, per-surface scores)
        // and opens the system share sheet so the user can post their
        // glow-up arc in one tap. CLOSE bails back to wherever pushed
        // them here (Looks masthead, Rizz masthead). Without share
        // here the only post-able artefact was a single session card
        // — the user explicitly asked for a Progress one so the page
        // "hits harder" on the For You feed.
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
            const Spacer(),
            _ProgressShareButton(
              // ignore: discarded_futures
              onTap: () => _shareProgress(sorted, deltas)),
            const SizedBox(width: 8),
            _ProgressCloseButton(onTap: () {
              // ignore: discarded_futures
              AnalyticsService.progressCloseTapped();
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            }),
          ],
        ),
        const SizedBox(height: 2),
        Text('${_scans.length} SCAN${_scans.length == 1 ? '' : 'S'}'
             ' · ${_generations.length} GENERATIONS',
          style: AppTypography.label.copyWith(
            color: AppColors.textMuted, fontSize: 8.5, letterSpacing: 2.8)),

        const SizedBox(height: Sp.lg),

        // ── IMHIM LOOKS HERO. Photo pair → IMHIM LOOKS SCORE →
        // Looks + Consistency chips beneath → italic hard-hitting
        // line on top. v379: pure looks — the Auralay TRAINING block
        // (Aura score, drill counts, curriculum) is gone.
        if (hasScans)
          _ProgressImhimHero(scans: sorted)
              .animate().fadeIn(duration: 420.ms),

        if (hasScans) const SizedBox(height: Sp.lg),

        if (hasScans) ...[
          // Score-over-time chart (ImHim's face-score timeline)
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
        ],

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

  /// Fire the ImHim Looks Progress share card — LOOKS ONLY (v379).
  /// Day + streak come from StreakService (the one source of truth,
  /// so the card matches the flame and DAY N/60 everywhere else);
  /// the IMHIM LOOKS SCORE composite is Looks + Consistency, same
  /// formula as the in-app hero. No game, no aura, no drills.
  Future<void> _shareProgress(
      List<ScanRecord> sortedScans,
      Map<String, (double, double)>? deltas) async {
    HapticFeedback.lightImpact();
    // ignore: discarded_futures
    AnalyticsService.shareTapped(surface: 'progress');

    final aestheticNow = sortedScans.isEmpty ? null : sortedScans.last.score;
    final aestheticDelta = (deltas != null && deltas['Score'] != null)
        ? deltas['Score']!.$1.round()
        : null;

    int day = 1;
    int streak = 0;
    int? imhimNow;
    int? imhimDelta;
    try {
      final snap = await StreakService.progress();
      day    = snap.ascensionDay;
      streak = snap.streak;
      final imhim = AscensionService.imhimScoreFromComponents(
        looks: aestheticNow ?? 0,
        consistency: snap.consistency,
      );
      imhimNow   = imhim;
      imhimDelta = await AscensionService.weeklyDeltaFor(imhim);
    } catch (_) {
      // Prefs unhappy — fall through with nulls so the share card
      // hides the hero number rather than render garbage.
    }

    if (!mounted) return;
    // ignore: discarded_futures
    ShareService.shareProgress(
      context:        context,
      day:            day,
      streakDays:     streak,
      scanCount:      _scans.length,
      gameReps:       0,
      drillsCount:    0,
      aestheticNow:   aestheticNow,
      aestheticDelta: aestheticDelta,
      imhimNow:       imhimNow,
      imhimDelta:     imhimDelta,
      // BEFORE = oldest scan photo, NOW = newest — the same pair the
      // Progress screen renders. sortedScans is oldest → newest.
      beforePhotoPath: sortedScans.isNotEmpty
          ? sortedScans.first.capturedImagePath : null,
      nowPhotoPath:    sortedScans.isNotEmpty
          ? sortedScans.last.capturedImagePath : null,
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
//  Progress locked — the tracking-surface sell page, shown until first scan
// ═══════════════════════════════════════════════════════════════════════════
//
// Like the Mirror-locked page: this is marketing, not a placeholder. Users
// who tap Progress before scanning see a concrete promise — protocol,
// streak, delta chart, generation vault — all activated the moment they
// capture their first face.
class _ProgressLocked extends StatelessWidget {
  const _ProgressLocked();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.xl, Sp.lg, Sp.xxl),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Progress',
                    style: AppTypography.h1.copyWith(
                      fontSize: 32, letterSpacing: -0.8, height: 1)),
                  const SizedBox(height: 4),
                  Text('DELTAS · STREAKS · PROTOCOL',
                    style: AppTypography.label.copyWith(
                      color: AppColors.red,
                      fontSize: 9, letterSpacing: 3.0,
                      fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            _ProgressCloseButton(onTap: () {
              // ignore: discarded_futures
              AnalyticsService.progressCloseTapped();
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            }),
          ],
        ),

        const SizedBox(height: Sp.xxl),

        // Deadly quote — replaces the essay.
        Text('"No vibes.\nOnly numbers."',
          style: AppTypography.h1.copyWith(
            fontSize: 22, height: 1.3, letterSpacing: -0.4,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w600,
          ))
          .animate().fadeIn(duration: 420.ms)
          .slideY(begin: 0.04, end: 0, duration: 420.ms, curve: Curves.easeOut),

        const SizedBox(height: Sp.xl),

        _LockedCapRow(
          icon: Icons.auto_awesome,
          tint: AppColors.red,
          label: '60-DAY PROTOCOL',
          line: 'Routine tuned to your weakest axis.',
          delay: 120,
        ),
        _LockedCapRow(
          icon: Icons.local_fire_department_outlined,
          tint: AppColors.signalAmber,
          label: 'STREAK',
          line: 'One freeze a week. Showing up wins.',
          delay: 200,
        ),
        _LockedCapRow(
          icon: Icons.show_chart_rounded,
          tint: AppColors.measure,
          label: 'DELTA CHART',
          line: 'Same 16 measurements. Every week.',
          delay: 280,
        ),
        _LockedCapRow(
          icon: Icons.grid_view_rounded,
          tint: AppColors.accent,
          label: 'VAULT',
          line: 'Every render you\'ve made — side by side.',
          delay: 360,
        ),

        const SizedBox(height: Sp.xl),

        SizedBox(
          width: double.infinity, height: 56,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: AppColors.base,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Rd.lg)),
              elevation: 0,
            ),
            onPressed: () {
              HapticFeedback.mediumImpact();
              context.push('/scan');
            },
            child: const Text('Begin first scan',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15, letterSpacing: 0.4)),
          ),
        ).animate().fadeIn(delay: 440.ms, duration: 360.ms),
      ],
    );
  }
}

// ── Capability row (progress-locked variant) ───────────────────────────────
class _LockedCapRow extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String label;
  final String line;
  final int delay;
  const _LockedCapRow({
    required this.icon,
    required this.tint,
    required this.label,
    required this.line,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: AppColors.divider, width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.13),
              shape: BoxShape.circle,
              border: Border.all(
                color: tint.withValues(alpha: 0.5), width: 0.8),
            ),
            child: Icon(icon, size: 16, color: tint),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                  style: AppTypography.label.copyWith(
                    color: tint, letterSpacing: 2.4, fontSize: 9)),
                const SizedBox(height: 3),
                Text(line,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12.5, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(
      delay: Duration(milliseconds: delay), duration: 360.ms)
      .slideY(begin: 0.06, end: 0,
        delay: Duration(milliseconds: delay),
        duration: 360.ms, curve: Curves.easeOut);
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
    // v302 — chart card lifted out of the "coffin" feel. Warmer
    // surface (surfaceElevated), red-tinted border, subtle glow,
    // and a colored axis label so the eye reads the section as a
    // live arc, not a tombstone.
    final last = scans.last.score;
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(
          color: AppColors.red.withValues(alpha: 0.22), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withValues(alpha: 0.12),
            blurRadius: 24, spreadRadius: 0),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('LOOKS · OVER TIME',
                style: AppTypography.label.copyWith(
                  color: AppColors.red,
                  letterSpacing: 2.5, fontSize: 9.5,
                  fontWeight: FontWeight.w900)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('NOW $last',
                  style: AppTypography.label.copyWith(
                    color: AppColors.red,
                    fontSize: 9, letterSpacing: 1.6,
                    fontWeight: FontWeight.w900)),
              ),
            ],
          ),
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
      // v302 — warm red area gradient instead of the invisible
      // divider-on-divider wash. Bro: charts felt "in a coffin."
      canvas.drawPath(areaPath, Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [
            AppColors.red.withValues(alpha: 0.35),
            AppColors.red.withValues(alpha: 0.04),
            Colors.transparent,
          ],
          stops: const [0.0, 0.7, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
    }

    // Main line — smooth, with a soft outer glow stroke
    // underneath so the arc lifts off the dark surface.
    if (points.length > 1) {
      final linePath = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        final prev = points[i - 1];
        final cur  = points[i];
        final midX = (prev.dx + cur.dx) / 2;
        linePath.cubicTo(midX, prev.dy, midX, cur.dy, cur.dx, cur.dy);
      }
      // Glow underlay — wider, low alpha, blurred via maskFilter.
      canvas.drawPath(linePath, Paint()
        ..color = AppColors.red.withValues(alpha: 0.55)
        ..strokeWidth = 6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      // Main stroke on top.
      canvas.drawPath(linePath, Paint()
        ..color = AppColors.red
        ..strokeWidth = 2.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round);
    }

    // Data points — endpoints get a halo so first/last read as
    // anchors, intermediate dots stay minimal.
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final isEnd = (i == 0 || i == points.length - 1);
      if (isEnd) {
        canvas.drawCircle(p, 9, Paint()
          ..color = AppColors.red.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      }
      canvas.drawCircle(p, isEnd ? 5.5 : 4.5,
        Paint()..color = AppColors.surface1);
      canvas.drawCircle(p, isEnd ? 5.5 : 4.5, Paint()
        ..color = AppColors.red
        ..strokeWidth = isEnd ? 2.0 : 1.6
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


// ═══════════════════════════════════════════════════════════════════════════
//  Close X — small circular button mirroring the masthead cog styling,
//  used in BOTH the populated body header and the locked empty-state
//  header so /progress always has an exit, regardless of which sub-tree
//  the user is staring at.
// ═══════════════════════════════════════════════════════════════════════════
/// SHARE button — same circular footprint as the close X so the
/// masthead stays balanced, but with a red iOS-style outbox icon and a
/// red ring instead of grey so it reads as the primary action. Tapping
/// pipes through to [_ProgressScreenState._shareProgress].
class _ProgressShareButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ProgressShareButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        customBorder: const CircleBorder(),
        child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: AppColors.surface1,
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.55), width: 1.0),
            boxShadow: [
              BoxShadow(
                color: AppColors.red.withValues(alpha: 0.18),
                blurRadius: 10, spreadRadius: 0),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.ios_share_rounded,
              size: 18, color: AppColors.red),
        ),
      ),
    );
  }
}

class _ProgressCloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ProgressCloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        customBorder: const CircleBorder(),
        child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: AppColors.surface1,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.surface3, width: 0.6),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.close_rounded,
              size: 20, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}


/// PROGRESS hero — LOOKS ONLY (v379).
///
/// Stack (top → bottom):
///   1. Hard-hitting identity line (italic Playfair, rotates daily
///      via AscensionService.todayMessageFor so it never stales).
///   2. IMHIM LOOKS SCORE composite — 84pt italic numeral in red, "/100"
///      anchor and weekly delta arrow beneath. Looks + Consistency
///      only; the game input is dead since the looks pivot.
///   3. BEFORE / AFTER face pair — first scan capturedImagePath vs
///      latest, accent borders, "BEFORE" / "NOW" labels.
///   4. LOOKS · CONSISTENCY inline chips — the two live pillars.
///
/// Card surface gets a soft red atmospheric wash + glow so the
/// block reads as warm, not interred.
class _ProgressImhimHero extends StatefulWidget {
  final List<ScanRecord> scans; // chronological asc
  const _ProgressImhimHero({required this.scans});
  @override
  State<_ProgressImhimHero> createState() => _ProgressImhimHeroState();
}

class _ProgressImhimHeroState extends State<_ProgressImhimHero> {
  int  _imhim       = 0;
  int  _delta       = 0;
  int  _day         = 1;
  int  _consistency = 0;
  bool _ready       = false;
  Protocol? _proto;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Protocol? p;
    try { p = await ProtocolService.loadActive(); } catch (_) {}
    final looks = widget.scans.isEmpty ? 0 : widget.scans.last.score;
    final snap = await StreakService.progress();
    final imhim = AscensionService.imhimScoreFromComponents(
      looks: looks, consistency: snap.consistency);
    final delta = await AscensionService.weeklyDeltaFor(imhim);
    if (!mounted) return;
    setState(() {
      _imhim = imhim;
      _delta = delta;
      _day = snap.ascensionDay;
      _consistency = snap.consistency;
      _proto = p;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scans = widget.scans;
    final firstScan = scans.first;
    final lastScan  = scans.last;
    final looks = lastScan.score;
    final streak = _proto?.effectiveStreak ?? 0;
    final line = AscensionService.todayMessageFor(
      day: _day, streak: streak);
    final deltaText = !_ready
        ? '—'
        : _delta == 0
            ? '+0 this week'
            : _delta > 0
                ? '↑ +$_delta this week'
                : '↓ $_delta this week';
    final deltaColor = !_ready || _delta == 0
        ? AppColors.textTertiary
        : _delta > 0
            ? AppColors.signalGreen
            : AppColors.signalAmber;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        // Warm gradient wash — kills the "coffin" feel without
        // breaking the black-first brand. Radial top-bias so the
        // glow lives behind the hero number.
        gradient: RadialGradient(
          center: const Alignment(0, -0.5),
          radius: 1.1,
          colors: [
            AppColors.red.withValues(alpha: 0.16),
            AppColors.surface1,
          ],
        ),
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(
          color: AppColors.red.withValues(alpha: 0.30), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withValues(alpha: 0.18),
            blurRadius: 32, spreadRadius: 0),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Hard-hitting identity line.
          if (line.isNotEmpty) ...[
            Text(line,
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                color: AppColors.textPrimary,
                fontSize: 16, height: 1.35,
                letterSpacing: -0.4,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
              )),
            const SizedBox(height: 18),
          ],

          // ── IMHIM LOOKS SCORE numeral hero.
          Text('IMHIM LOOKS SCORE',
            style: GoogleFonts.inter(
              color: AppColors.red,
              fontSize: 10.5, letterSpacing: 3.2,
              fontWeight: FontWeight.w900,
            )),
          const SizedBox(height: 4),
          Text('${_ready ? _imhim : 0}',
            style: GoogleFonts.playfairDisplay(
              color: Colors.white,
              fontSize: 84, height: 1,
              letterSpacing: -2.6,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w900,
            )),
          const SizedBox(height: 2),
          Text('/ 100',
            style: GoogleFonts.inter(
              color: AppColors.textTertiary,
              fontSize: 11, letterSpacing: 2.4,
              fontWeight: FontWeight.w800,
            )),
          const SizedBox(height: 8),
          Text(deltaText,
            style: GoogleFonts.inter(
              color: deltaColor,
              fontSize: 12, letterSpacing: 1.2,
              fontWeight: FontWeight.w900,
            )),

          const SizedBox(height: 22),

          // ── BEFORE / AFTER face pair.
          Row(
            children: [
              Expanded(
                child: _ProgressFaceTile(
                  label: 'BEFORE',
                  imagePath: firstScan.capturedImagePath,
                  accent: AppColors.textTertiary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ProgressFaceTile(
                  label: scans.length > 1 ? 'NOW' : 'TODAY',
                  imagePath: lastScan.capturedImagePath,
                  accent: AppColors.red,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // ── LOOKS · CONSISTENCY supporting chips — the two inputs
          // the composite is actually built from since the looks pivot.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ProgressStatChip(
                label: 'LOOKS', value: looks, accent: AppColors.measure),
              const SizedBox(width: 12),
              _ProgressStatChip(
                label: 'CONSISTENCY',
                value: _ready ? _consistency : 0,
                accent: AppColors.red),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressFaceTile extends StatelessWidget {
  final String label;
  final String? imagePath;
  final Color accent;
  const _ProgressFaceTile({
    required this.label,
    required this.imagePath,
    required this.accent,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 4 / 5,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(Rd.lg),
              border: Border.all(
                color: accent.withValues(alpha: 0.55), width: 1.4),
            ),
            clipBehavior: Clip.antiAlias,
            // Resolve through FaceAssetService so the photo survives the
            // iOS container-UUID drift after an app update (the stored
            // absolute path goes stale; the file is still there under the
            // current docs dir). Was Image.file(rawPath) → vanished on
            // update.
            child: FutureBuilder<String?>(
              future: FaceAssetService.resolvePath(imagePath),
              builder: (_, snap) {
                final p = snap.data;
                if (p == null) return _placeholder();
                return Image.file(File(p), fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder());
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
          style: GoogleFonts.inter(
            color: accent,
            fontSize: 11, letterSpacing: 2.6,
            fontWeight: FontWeight.w900,
          )),
      ],
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.surface2,
        alignment: Alignment.center,
        child: Icon(Icons.face_retouching_natural_outlined,
          size: 36, color: AppColors.textTertiary.withValues(alpha: 0.55)),
      );
}

class _ProgressStatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color accent;
  const _ProgressStatChip({
    required this.label, required this.value, required this.accent});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: accent.withValues(alpha: 0.55), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(label,
            style: GoogleFonts.inter(
              color: accent,
              fontSize: 11, letterSpacing: 2.4,
              fontWeight: FontWeight.w900,
            )),
          const SizedBox(width: 8),
          Text('$value',
            style: GoogleFonts.playfairDisplay(
              color: Colors.white,
              fontSize: 22, height: 1,
              letterSpacing: -0.8,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w900,
            )),
        ],
      ),
    );
  }
}
