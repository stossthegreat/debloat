import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../config/dev_flags.dart';
import '../../models/protocol.dart';
import '../../models/scan_record.dart';
import '../../models/technique.dart';
import '../../providers/auralay_app_provider.dart';
import '../../services/analytics_service.dart';
import '../../services/gaze/gaze_progress_store.dart';
import '../../services/local_store_service.dart';
import '../../services/presence/presence_progress_store.dart';
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
  List<GameScoreEntry> _gameScores = [];
  bool _loading = true;

  // Auralay training stats — surfaced in the TRAINING section.
  int _gazeCompleted = 0;
  int _presenceCompleted = 0;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    AnalyticsService.progressScreenViewed();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final scans = await LocalStoreService.loadScans();
    final gens  = await LocalStoreService.loadGenerations();
    final game  = await LocalStoreService.loadGameScores();
    final gz    = await GazeProgressStore.completedCount();
    final pr    = await PresenceProgressStore.completedCount();
    if (!mounted) return;
    setState(() {
      _scans = scans;
      _generations = gens;
      _gameScores = game;
      _gazeCompleted = gz;
      _presenceCompleted = pr;
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
              // Empty-state ONLY when nothing exists on any pillar — no
              // scans AND no Auralay training AND no game sessions. As
              // soon as the user has touched any surface, the tab shows
              // the relevant blocks (training, game chart, scan chart).
              : (_scans.isEmpty &&
                      _gameScores.isEmpty &&
                      _gazeCompleted == 0 &&
                      _presenceCompleted == 0)
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
    final hasTraining = _gazeCompleted > 0 || _presenceCompleted > 0;
    final hasScans    = _scans.isNotEmpty;
    final hasGame     = _gameScores.isNotEmpty;

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
            _ProgressShareButton(onTap: () => _shareProgress(sorted, deltas)),
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
             ' · ${_gameScores.length} GAME REP${_gameScores.length == 1 ? '' : 'S'}'
             ' · ${_generations.length} GENERATIONS'
             ' · ${_gazeCompleted + _presenceCompleted} DRILLS',
          style: AppTypography.label.copyWith(
            color: AppColors.textMuted, fontSize: 8.5, letterSpacing: 2.8)),

        const SizedBox(height: Sp.xl),

        // ── TRAINING block (Auralay graft) ──────────────────────────────
        // Aura Score hero + Day/Streak chips + per-tab drill counts +
        // technique curriculum dot row. Shows once the user has ANY
        // Auralay activity, otherwise hidden so the tab still feels like
        // Mirrorly to scan-first users.
        if (hasTraining) ...[
          _TrainingBlock(
            gazeCompleted:     _gazeCompleted,
            presenceCompleted: _presenceCompleted,
          ).animate().fadeIn(duration: 400.ms),
          const SizedBox(height: Sp.lg),
        ],

        if (hasScans) ...[
          // Score-over-time chart (Mirrorly's face-score timeline)
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

        // ── GAME · OVER TIME — Lucien scorecard arc.
        // Mirror of the Aesthetic Index chart, but for roleplay reps.
        // Renders the moment the user has finished one Free Flow
        // session; with one point it shows the single dot + the
        // session-count caption, with multiple points it draws the
        // arc so the user sees their voice game compounding.
        if (hasGame) ...[
          _GameChartCard(scores: _gameScores)
            .animate().fadeIn(delay: 200.ms, duration: 400.ms),
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

  /// Fire the ImHim Progress share card. Aggregates the user's data
  /// from every tracked surface (scans, game reps, gaze drills, voice
  /// drills) plus the Auralay-imported day/streak/aura state into one
  /// post-able receipt. Deltas come from the same axis-delta pass that
  /// powers the in-app DELTA · FIRST → LATEST row so the share number
  /// matches what the user just looked at.
  void _shareProgress(
      List<ScanRecord> sortedScans,
      Map<String, (double, double)>? deltas) {
    HapticFeedback.lightImpact();
    // ignore: discarded_futures
    AnalyticsService.shareTapped(surface: 'progress');

    final aux = context.read<AuralayAppProvider>().state;
    final aestheticNow = sortedScans.isEmpty ? null : sortedScans.last.score;
    final aestheticDelta = (deltas != null && deltas['Score'] != null)
        ? deltas['Score']!.$1.round()
        : null;

    // Game arc: now = last score, delta = (last − first) across all reps.
    int? voiceNow;
    int? voiceDelta;
    if (_gameScores.isNotEmpty) {
      final sorted = [..._gameScores]
        ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
      voiceNow   = sorted.last.score;
      voiceDelta = sorted.length >= 2
          ? sorted.last.score - sorted.first.score
          : null;
    }

    // ignore: discarded_futures
    ShareService.shareProgress(
      context:        context,
      day:            aux.currentDay,
      streakDays:     aux.streakDays,
      scanCount:      _scans.length,
      gameReps:       _gameScores.length,
      drillsCount:    _gazeCompleted + _presenceCompleted,
      aestheticNow:   aestheticNow,
      aestheticDelta: aestheticDelta,
      voiceNow:       voiceNow,
      voiceDelta:     voiceDelta,
      auraNow:        aux.auraScore > 0 ? aux.auraScore : null,
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

// ═══════════════════════════════════════════════════════════════════════════
//  TRAINING block — Auralay graft
//
//  Surfaces the data accumulated by the Eyes + Game tabs. Reads from
//  [AuralayAppProvider] (Aura score, current day, training streak) plus
//  the per-curriculum drill counters passed in from the parent.
//
//  Tap Aura number → Eyes tab (drill more, raise the score).
//  Tap a technique dot → /lesson/<id> deep-link.
// ═══════════════════════════════════════════════════════════════════════════
class _TrainingBlock extends StatelessWidget {
  final int gazeCompleted;
  final int presenceCompleted;
  const _TrainingBlock({
    required this.gazeCompleted,
    required this.presenceCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuralayAppProvider>().state;
    return Container(
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TRAINING',
            style: AppTypography.label.copyWith(
              color: AppColors.accent, letterSpacing: 2.8, fontSize: 9.5)),
          const SizedBox(height: 6),
          Text('Eyes · Game · Streak',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary, fontSize: 12)),

          const SizedBox(height: Sp.md),

          // Aura score hero — Auralay's signature number.
          _AuraHero(score: state.auraScore, day: state.currentDay),

          const SizedBox(height: Sp.md),

          // Day / Streak row
          Row(
            children: [
              Expanded(child: _StatChip(
                label: 'DAY', value: '${state.currentDay}', accent: AppColors.measure)),
              const SizedBox(width: 8),
              Expanded(child: _StatChip(
                label: 'STREAK',
                value: '${state.streakDays}',
                accent: state.streakDays > 0
                    ? AppColors.red
                    : AppColors.textTertiary,
                trailing: state.streakDays > 0 ? ' 🔥' : '',
              )),
            ],
          ),

          const SizedBox(height: Sp.md),

          // Per-tab drill counts
          Row(
            children: [
              Expanded(child: _StatChip(
                label: 'EYES · GAZE',
                value: '$gazeCompleted / 10',
                accent: gazeCompleted > 0 ? AppColors.signalGreen : AppColors.textTertiary,
              )),
              const SizedBox(width: 8),
              Expanded(child: _StatChip(
                label: 'EYES · VOICE',
                value: '$presenceCompleted / 10',
                accent: presenceCompleted > 0 ? AppColors.signalGreen : AppColors.textTertiary,
              )),
            ],
          ),

          const SizedBox(height: Sp.md),

          // Technique curriculum — compact 11-dot row representing days
          _TechniqueRow(currentDay: state.currentDay),
        ],
      ),
    );
  }
}

class _AuraHero extends StatelessWidget {
  final int score;
  final int day;
  const _AuraHero({required this.score, required this.day});

  String get _stageLabel {
    if (score < 20) return 'Raw material.';
    if (score < 40) return 'Building foundations.';
    if (score < 60) return 'Control developing.';
    if (score < 78) return 'Presence forming.';
    if (score < 90) return 'The room notices.';
    return 'Magnetic.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Text('AURA SCORE',
            style: AppTypography.label.copyWith(
              color: AppColors.accent, letterSpacing: 2.4, fontSize: 9)),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: score.toDouble()),
            duration: const Duration(milliseconds: 1400),
            curve: Curves.easeOutCubic,
            builder: (_, value, __) => Text(
              value.round().toString(),
              style: AppTypography.display.copyWith(
                fontSize: 56,
                color: AppColors.textPrimary,
                letterSpacing: -2,
                fontWeight: FontWeight.w800,
                fontStyle: FontStyle.italic,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: score / 100),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => LinearProgressIndicator(
                value: v,
                backgroundColor: AppColors.surface3,
                valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                minHeight: 2,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(_stageLabel,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  final String trailing;
  const _StatChip({
    required this.label,
    required this.value,
    required this.accent,
    this.trailing = '',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
            style: AppTypography.label.copyWith(
              color: accent, letterSpacing: 2, fontSize: 9)),
          const SizedBox(height: 3),
          Text('$value$trailing',
            style: AppTypography.h2.copyWith(
              color: AppColors.textPrimary,
              fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _TechniqueRow extends StatelessWidget {
  final int currentDay;
  const _TechniqueRow({required this.currentDay});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CURRICULUM',
            style: AppTypography.label.copyWith(
              color: AppColors.textTertiary, letterSpacing: 2, fontSize: 9)),
          const SizedBox(height: 8),
          // Day-dot row — 11 dots, mastered green, current red glow,
          // locked muted. Tap any unlocked dot → /lesson/<id>.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final t in Technique.all)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: t.isUnlocked(currentDay)
                          ? () async {
                              HapticFeedback.selectionClick();
                              // Paywall gate — the /train curriculum is
                              // pro-only. Free users (who reach this row
                              // via their one free Eyes drill) get the
                              // paywall instead of the lesson.
                              final pro = kBypassPaywall
                                  ? true
                                  : await LocalStoreService.isSubscribed();
                              if (!context.mounted) return;
                              context.push(
                                pro
                                    ? '/lesson/${t.id}'
                                    : '/paywall',
                                extra: pro ? {'currentDay': currentDay} : null,
                              );
                            }
                          : null,
                      child: _TechDot(
                        day: t.day,
                        unlocked: t.isUnlocked(currentDay),
                        mastered: t.isMastered(currentDay),
                        current:  t.day == currentDay,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TechDot extends StatelessWidget {
  final int day;
  final bool unlocked, mastered, current;
  const _TechDot({
    required this.day,
    required this.unlocked,
    required this.mastered,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final color = !unlocked
        ? AppColors.textTertiary.withValues(alpha: 0.3)
        : mastered
            ? AppColors.signalGreen
            : current
                ? AppColors.red
                : AppColors.accent;
    return Column(
      children: [
        Container(
          width: 22, height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: mastered
                ? AppColors.signalGreen.withValues(alpha: 0.18)
                : Colors.transparent,
            border: Border.all(color: color, width: 1.3),
            boxShadow: current
                ? [BoxShadow(
                    color: AppColors.red.withValues(alpha: 0.45),
                    blurRadius: 8, spreadRadius: 1)]
                : null,
          ),
          child: Center(
            child: mastered
                ? Icon(Icons.check, size: 12, color: AppColors.signalGreen)
                : Text('$day',
                    style: AppTypography.label.copyWith(
                      color: color, fontSize: 9, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Game · over time — Lucien scorecard arc.
//  Same structure as _ChartCard, tuned for game scores: amber accent
//  (matches the "voice" surface across the rest of the app) and a
//  caption that says how many reps the user has actually banked.
// ═══════════════════════════════════════════════════════════════════════════
class _GameChartCard extends StatelessWidget {
  final List<GameScoreEntry> scores;
  const _GameChartCard({required this.scores});

  @override
  Widget build(BuildContext context) {
    final latest = scores.last.score;
    final best   = scores.map((e) => e.score).reduce(math.max);
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(color: AppColors.signalAmber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('GAME · OVER TIME',
                style: AppTypography.label.copyWith(
                  color: AppColors.signalAmber,
                  letterSpacing: 2.5, fontSize: 9)),
              const Spacer(),
              Text('BEST $best · NOW $latest',
                style: AppTypography.label.copyWith(
                  color: AppColors.textTertiary,
                  letterSpacing: 1.6, fontSize: 8.5)),
            ],
          ),
          const SizedBox(height: Sp.md),
          SizedBox(
            height: 160,
            child: CustomPaint(
              size: Size.infinite,
              painter: _GameChartPainter(scores: scores),
            ),
          ),
          const SizedBox(height: Sp.sm),
          Row(
            children: [
              Text(_fmt(scores.first.takenAt),
                style: AppTypography.label.copyWith(
                  color: AppColors.textTertiary, fontSize: 8.5, letterSpacing: 1.8)),
              const Spacer(),
              Text('${scores.length} REP${scores.length == 1 ? '' : 'S'}',
                style: AppTypography.label.copyWith(
                  color: AppColors.textTertiary, fontSize: 8.5, letterSpacing: 1.8)),
              const Spacer(),
              Text(_fmt(scores.last.takenAt),
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

class _GameChartPainter extends CustomPainter {
  final List<GameScoreEntry> scores;
  _GameChartPainter({required this.scores});

  @override
  void paint(Canvas canvas, Size size) {
    if (scores.isEmpty) return;

    const padX = 10.0, padTop = 14.0, padBot = 14.0;
    final chartW = size.width - padX * 2;
    final chartH = size.height - padTop - padBot;

    final values = scores.map((s) => s.score.toDouble()).toList();
    final minS = values.reduce(math.min);
    final maxS = values.reduce(math.max);
    final yMin = math.max(0.0, (minS - 8).floorToDouble());
    final yMax = math.min(100.0, (maxS + 8).ceilToDouble());
    final yRange = (yMax - yMin).clamp(1.0, 100.0);

    final gridPaint = Paint()
      ..color = AppColors.surface3.withValues(alpha: 0.6)
      ..strokeWidth = 0.6;
    for (var i = 0; i <= 3; i++) {
      final y = padTop + chartH * (i / 3);
      canvas.drawLine(Offset(padX, y), Offset(size.width - padX, y), gridPaint);
    }

    final points = <Offset>[];
    for (var i = 0; i < scores.length; i++) {
      final x = padX + (scores.length == 1 ? chartW / 2 : chartW * (i / (scores.length - 1)));
      final y = padTop + chartH * (1 - (scores[i].score - yMin) / yRange);
      points.add(Offset(x, y));
    }

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
            AppColors.signalAmber.withValues(alpha: 0.18),
            AppColors.signalAmber.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
    }

    if (points.length > 1) {
      final linePath = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        final prev = points[i - 1];
        final cur  = points[i];
        final midX = (prev.dx + cur.dx) / 2;
        linePath.cubicTo(midX, prev.dy, midX, cur.dy, cur.dx, cur.dy);
      }
      canvas.drawPath(linePath, Paint()
        ..color = AppColors.signalAmber
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round);
    }

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      canvas.drawCircle(p, 4.5, Paint()..color = AppColors.surface1);
      canvas.drawCircle(p, 4.5, Paint()
        ..color = AppColors.signalAmber
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke);

      if (i == 0 || i == points.length - 1) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${scores[i].score}',
            style: TextStyle(
              color: AppColors.signalAmber, fontSize: 10,
              fontWeight: FontWeight.w800, letterSpacing: 0.5,
              fontFamilyFallback: const ['monospace']),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy - 20));
      }
    }
  }

  @override
  bool shouldRepaint(_GameChartPainter old) => old.scores != scores;
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
