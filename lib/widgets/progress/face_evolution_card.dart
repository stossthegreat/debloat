import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/scan_record.dart';
import '../../services/analytics_service.dart';
import '../../services/debloat_stats_service.dart';
import '../../services/evolution_video_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// FACE EVOLUTION — the premium, addictive centrepiece of the Progress
/// tab. Replaces the old Ascension Record + Drained Certified sections.
///
/// Reuses the retained per-scan selfies (ScanRecord.capturedImagePath): a
/// draggable vertical divider compares Day 1 (left) against whichever scan
/// is selected (right), a timeline lets you tap through scans, an autoplay
/// scrubs the whole journey, and an AI summary lists the visible changes.
class FaceEvolutionCard extends StatefulWidget {
  /// All scans, any order — the card sorts oldest→newest and keeps only
  /// the ones that actually retained a photo on disk.
  final List<ScanRecord> scans;
  const FaceEvolutionCard({super.key, required this.scans});

  @override
  State<FaceEvolutionCard> createState() => _FaceEvolutionCardState();
}

class _FaceEvolutionCardState extends State<FaceEvolutionCard>
    with SingleTickerProviderStateMixin {
  late List<ScanRecord> _photoScans;
  int _selected = 0;      // index into _photoScans (the RIGHT image)
  double _split = 0.5;    // 0..1 divider position
  bool _playing = false;
  bool _sharing = false;
  late final AnimationController _reveal;

  @override
  void initState() {
    super.initState();
    _recompute();
    _reveal = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600))
      ..addListener(() {
        // Ease the divider from the Day-1 side across to the selected
        // face — a smooth 60fps reveal of the drained result over the
        // bloated original.
        setState(() => _split =
            0.06 + 0.88 * Curves.easeInOutCubic.transform(_reveal.value));
      })
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _playing = false);
        }
      });
  }

  @override
  void didUpdateWidget(covariant FaceEvolutionCard old) {
    super.didUpdateWidget(old);
    _recompute();
  }

  void _recompute() {
    final withPhoto = widget.scans
        .where((s) => (s.capturedImagePath ?? '').isNotEmpty &&
            File(s.capturedImagePath!).existsSync())
        .toList()
      ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
    _photoScans = withPhoto;
    _selected = _photoScans.isEmpty ? 0 : _photoScans.length - 1;
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  ScanRecord get _day1 => _photoScans.first;
  ScanRecord get _sel  => _photoScans[_selected];

  void _select(int i, {bool haptic = true}) {
    if (haptic) HapticFeedback.selectionClick();
    setState(() => _selected = i.clamp(0, _photoScans.length - 1));
  }

  void _watchEvolution() {
    if (_photoScans.length < 2 || _playing) return;
    HapticFeedback.mediumImpact();
    // ignore: discarded_futures
    AnalyticsService.evolutionWatched(_photoScans.length);
    // Pin the right image to the LATEST scan, start the divider hard-left
    // (all Day 1 showing), then sweep it across to reveal the drained
    // face. Loop once, stop.
    setState(() {
      _playing = true;
      _selected = _photoScans.length - 1;
      _split = 0.06;
    });
    _reveal.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    // No photos yet → gentle empty state that still teases the feature.
    if (_photoScans.isEmpty) {
      return _EmptyEvolution();
    }
    final hasTwo = _photoScans.length >= 2;

    return Container(
      constraints: const BoxConstraints(minHeight: 420),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF0C1519), AppColors.surface1]),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.35), width: 1),
        boxShadow: [
          BoxShadow(color: AppColors.brand.withValues(alpha: 0.18),
            blurRadius: 30, spreadRadius: -6, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Row(
            children: [
              Text('FACE EVOLUTION',
                style: AppTypography.label.copyWith(
                  color: AppColors.brand,
                  fontSize: 11.5, letterSpacing: 2.8, fontWeight: FontWeight.w900)),
              const Spacer(),
              Text('${_photoScans.length} Scan${_photoScans.length == 1 ? '' : 's'} Logged',
                style: GoogleFonts.inter(
                  color: AppColors.textTertiary,
                  fontSize: 12.5, fontWeight: FontWeight.w600))
                .animate().fadeIn(delay: 300.ms, duration: 500.ms),
            ],
          ),
          const SizedBox(height: 14),

          // ── Comparison slider ───────────────────────────────────────
          _CompareSlider(
            leftPath:  _day1.capturedImagePath!,
            rightPath: _sel.capturedImagePath!,
            leftLabel:  'DAY 1',
            rightLabel: _dayLabel(_sel),
            split: _split,
            onSplit: (v) => setState(() => _split = v),
          ),

          const SizedBox(height: 14),

          // ── Timeline ────────────────────────────────────────────────
          _Timeline(
            scans: _photoScans,
            selected: _selected,
            baseDate: _day1.takenAt,
            onTap: _select,
          ),

          const SizedBox(height: 14),

          // ── Autoplay ────────────────────────────────────────────────
          if (hasTwo)
            Center(
              child: _WatchButton(playing: _playing, onTap: _watchEvolution),
            ),

          const SizedBox(height: 16),

          // ── AI summary ──────────────────────────────────────────────
          _AiSummary(from: _day1, to: _sel),

          const SizedBox(height: 16),

          // ── Bottom buttons ──────────────────────────────────────────
          Row(
            children: [
              Expanded(child: _GhostBtn(
                icon: Icons.compare_rounded, label: 'COMPARE',
                onTap: () => _openFullscreen(context))),
              const SizedBox(width: 12),
              Expanded(child: _FillBtn(
                icon: Icons.ios_share_rounded,
                label: _sharing ? 'BUILDING…' : 'SHARE',
                loading: _sharing,
                onTap: () => _share(context))),
            ],
          ),
        ],
      ),
    );
  }

  String _dayLabel(ScanRecord s) {
    final d = s.takenAt.difference(_day1.takenAt).inDays;
    if (d <= 0) return _selected == _photoScans.length - 1 ? 'TODAY' : 'DAY 1';
    if (_selected == _photoScans.length - 1) return 'TODAY';
    return 'DAY ${d + 1}';
  }

  void _openFullscreen(BuildContext context) {
    HapticFeedback.selectionClick();
    // ignore: discarded_futures
    AnalyticsService.evolutionCompared();
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _FullscreenCompare(
        leftPath: _day1.capturedImagePath!,
        rightPath: _sel.capturedImagePath!,
        rightLabel: _dayLabel(_sel),
      ),
    ));
  }

  Future<void> _share(BuildContext context) async {
    if (_sharing) return;
    HapticFeedback.selectionClick();
    // ignore: discarded_futures
    AnalyticsService.evolutionShared(_photoScans.length);
    setState(() => _sharing = true);
    try {
      await FaceEvolutionShare.sharePair(
        beforePath: _day1.capturedImagePath!,
        afterPath: _sel.capturedImagePath!,
        afterLabel: _dayLabel(_sel),
        scoreBefore: DebloatStatsService.compute(_day1.geometry).overall,
        scoreAfter:  DebloatStatsService.compute(_sel.geometry).overall,
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}

// ── Draggable before/after comparison ─────────────────────────────────────
class _CompareSlider extends StatelessWidget {
  final String leftPath, rightPath, leftLabel, rightLabel;
  final double split;
  final ValueChanged<double> onSplit;
  const _CompareSlider({
    required this.leftPath,
    required this.rightPath,
    required this.leftLabel,
    required this.rightLabel,
    required this.split,
    required this.onSplit,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          return GestureDetector(
            onHorizontalDragUpdate: (d) =>
                onSplit((d.localPosition.dx / w).clamp(0.02, 0.98)),
            onTapDown: (d) =>
                onSplit((d.localPosition.dx / w).clamp(0.02, 0.98)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // RIGHT (selected) is the base
                _Face(rightPath),
                // LEFT (Day 1) clipped to the left of the divider
                ClipRect(
                  clipper: _LeftClipper(split),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _Face(leftPath, key: ValueKey(leftPath)),
                  ),
                ),
                Positioned(left: 10, top: 10, child: _tag(leftLabel, Colors.white70)),
                Positioned(right: 10, top: 10, child: _tag(rightLabel, AppColors.brand)),
                // Divider + handle
                Positioned(
                  left: w * split - 1, top: 0, bottom: 0,
                  child: Container(width: 2, color: Colors.white),
                ),
                Positioned(
                  left: w * split - 19, top: 0, bottom: 0,
                  child: Center(
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.base,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.brand, width: 2),
                        boxShadow: [BoxShadow(
                          color: AppColors.brand.withValues(alpha: 0.7),
                          blurRadius: 16)],
                      ),
                      child: const Icon(Icons.unfold_more_rounded,
                        color: AppColors.brand, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _tag(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(100)),
    child: Text(t, style: GoogleFonts.inter(
      color: c, fontSize: 10.5, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
  );
}

class _Face extends StatelessWidget {
  final String path;
  const _Face(this.path, {super.key});
  @override
  Widget build(BuildContext context) => Image.file(
    File(path), fit: BoxFit.cover,
    alignment: const Alignment(0, -0.15),
    errorBuilder: (_, __, ___) => Container(
      color: AppColors.surface2,
      alignment: Alignment.center,
      child: const Icon(Icons.face_rounded, color: AppColors.surface3, size: 56)),
  );
}

class _LeftClipper extends CustomClipper<Rect> {
  final double t;
  const _LeftClipper(this.t);
  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, size.width * t, size.height);
  @override
  bool shouldReclip(_LeftClipper old) => old.t != t;
}

// ── Timeline dots ──────────────────────────────────────────────────────────
class _Timeline extends StatelessWidget {
  final List<ScanRecord> scans;
  final int selected;
  final DateTime baseDate;
  final ValueChanged<int> onTap;
  const _Timeline({
    required this.scans,
    required this.selected,
    required this.baseDate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < scans.length; i++) ...[
              _dot(i),
              if (i != scans.length - 1)
                Expanded(child: Container(
                  height: 2,
                  color: i < selected
                      ? AppColors.brand.withValues(alpha: 0.6)
                      : AppColors.surface3)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('DAY 1', style: _lblStyle),
            Text('TODAY', style: _lblStyle),
          ],
        ),
      ],
    );
  }

  TextStyle get _lblStyle => GoogleFonts.inter(
    color: AppColors.textTertiary, fontSize: 9.5,
    letterSpacing: 1.4, fontWeight: FontWeight.w700);

  Widget _dot(int i) {
    final active = i == selected;
    final done = i <= selected;
    return GestureDetector(
      onTap: () => onTap(i),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          width: active ? 16 : 12, height: active ? 16 : 12,
          decoration: BoxDecoration(
            color: done ? AppColors.brand : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: done ? AppColors.brand : AppColors.surface3, width: 2),
            boxShadow: active
                ? [BoxShadow(color: AppColors.brand.withValues(alpha: 0.7), blurRadius: 12)]
                : null,
          ),
        ),
      ),
    );
  }
}

// ── Watch-evolution button ─────────────────────────────────────────────────
class _WatchButton extends StatelessWidget {
  final bool playing;
  final VoidCallback onTap;
  const _WatchButton({required this.playing, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: playing ? null : onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: AppColors.brand.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(playing ? Icons.autorenew_rounded : Icons.play_arrow_rounded,
                color: AppColors.brand, size: 18),
              const SizedBox(width: 7),
              Text(playing ? 'PLAYING…' : 'WATCH EVOLUTION',
                style: GoogleFonts.inter(
                  color: AppColors.brand, fontSize: 12.5,
                  letterSpacing: 1.2, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── AI summary (computed from the two scans) ────────────────────────────────
class _AiSummary extends StatelessWidget {
  final ScanRecord from, to;
  const _AiSummary({required this.from, required this.to});

  List<String> _changes() {
    // Single baseline scan (Day 1 vs itself) → don't fake improvements.
    if (identical(from, to) || from.id == to.id) {
      return const ['Baseline captured — scan again to see your changes'];
    }
    final a = DebloatStatsService.compute(from.geometry);
    final b = DebloatStatsService.compute(to.geometry);
    int scoreOf(DebloatReadout r, String label) {
      for (final s in r.stats) {
        if (s.label == label) return s.score;
      }
      return 0;
    }
    final lines = <String>[];
    if (scoreOf(b, 'Jawline') >= scoreOf(a, 'Jawline'))
      lines.add('Jawline definition increased');
    if (scoreOf(b, 'Cheekbones') >= scoreOf(a, 'Cheekbones'))
      lines.add('Cheeks appear leaner');
    if (scoreOf(b, 'Under-Eyes') >= scoreOf(a, 'Under-Eyes'))
      lines.add('Under-eye puffiness reduced');
    if (b.overall >= a.overall)
      lines.add('Face contour more visible');
    if (lines.isEmpty) lines.add('Baseline captured — keep scanning');
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final changes = _changes();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('VISIBLE CHANGES',
          style: AppTypography.label.copyWith(
            color: AppColors.textTertiary,
            fontSize: 10, letterSpacing: 2.0, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        for (var i = 0; i < changes.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.check_rounded, color: AppColors.signalGreen, size: 17),
                const SizedBox(width: 9),
                Expanded(child: Text(changes[i],
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 14, fontWeight: FontWeight.w600))),
              ],
            ),
          ).animate().fadeIn(delay: (200 * i).ms, duration: 350.ms)
            .slideX(begin: 0.05, end: 0),
      ],
    );
  }
}

class _GhostBtn extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _GhostBtn({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 50, alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surface3)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: AppColors.textSecondary, size: 18),
          const SizedBox(width: 8),
          Text(label, style: GoogleFonts.inter(
            color: AppColors.textSecondary, fontSize: 13,
            letterSpacing: 1, fontWeight: FontWeight.w800)),
        ]),
      ),
    ),
  );
}

class _FillBtn extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  final bool loading;
  const _FillBtn({
    required this.icon, required this.label, required this.onTap,
    this.loading = false,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.brand,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: loading ? null : onTap, borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 50, alignment: Alignment.center,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (loading)
            const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation(AppColors.base)))
          else
            Icon(icon, color: AppColors.base, size: 18),
          const SizedBox(width: 8),
          Text(label, style: GoogleFonts.inter(
            color: AppColors.base, fontSize: 13,
            letterSpacing: 1, fontWeight: FontWeight.w800)),
        ]),
      ),
    ),
  );
}

class _EmptyEvolution extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.25)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_awesome_motion_rounded,
            color: AppColors.brand, size: 40),
          const SizedBox(height: 14),
          Text('FACE EVOLUTION',
            style: AppTypography.label.copyWith(
              color: AppColors.brand, fontSize: 11.5,
              letterSpacing: 2.8, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text('Scan again over the next weeks to watch your face get leaner, '
              'day by day.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 14, height: 1.4, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  FULLSCREEN COMPARE — the big draggable slider.
// ═══════════════════════════════════════════════════════════════════════════
class _FullscreenCompare extends StatefulWidget {
  final String leftPath, rightPath, rightLabel;
  const _FullscreenCompare({
    required this.leftPath,
    required this.rightPath,
    required this.rightLabel,
  });
  @override
  State<_FullscreenCompare> createState() => _FullscreenCompareState();
}

class _FullscreenCompareState extends State<_FullscreenCompare> {
  double _split = 0.5;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop()),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _CompareSlider(
                  leftPath: widget.leftPath,
                  rightPath: widget.rightPath,
                  leftLabel: 'DAY 1',
                  rightLabel: widget.rightLabel,
                  split: _split,
                  onSplit: (v) => setState(() => _split = v)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SHARE — exports the branded MP4 reveal clip (Day 1 → now) built by
//  EvolutionVideoService: full DEBLOAT OS wordmark, day chips, glowing
//  sweep divider, "+N DRAINED SCORE" end card. A real video plays
//  everywhere — iMessage, IG stories, TikTok, WhatsApp. Falls back to
//  the GIF reveal, then a side-by-side JPG, then the raw photos, so the
//  share sheet always opens.
// ═══════════════════════════════════════════════════════════════════════════
class FaceEvolutionShare {
  static Future<void> sharePair({
    required String beforePath,
    required String afterPath,
    required String afterLabel,
    int scoreBefore = 0,
    int scoreAfter = 0,
  }) async {
    final text = 'My Debloat OS face evolution. Day 1 → $afterLabel 💧→🗿';
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final args = <String, String>{'before': beforePath, 'after': afterPath};

    // 1) The real thing — branded MP4 via the native H.264 encoder.
    try {
      final mp4 = await EvolutionVideoService.buildRevealVideo(
        beforePath: beforePath,
        afterPath: afterPath,
        dayLabel: afterLabel,
        scoreBefore: scoreBefore,
        scoreAfter: scoreAfter,
      );
      if (mp4 != null) {
        await Share.shareXFiles(
          [XFile(mp4, mimeType: 'video/mp4')], text: text);
        return;
      }
    } catch (_) {/* fall through */}

    // 2) Animated GIF reveal — legacy fallback if the native encoder is
    //    unavailable (e.g. stale build without the channel).
    try {
      final bytes = await compute(encodeRevealGif, args);
      if (bytes != null && bytes.isNotEmpty) {
        final f = File('${dir.path}/evolution_$stamp.gif');
        await f.writeAsBytes(bytes);
        await Share.shareXFiles(
          [XFile(f.path, mimeType: 'image/gif')], text: text);
        return;
      }
    } catch (_) {/* fall through */}

    // 3) Static side-by-side JPG (also off-thread).
    try {
      final bytes = await compute(encodeJpgPair, args);
      if (bytes != null && bytes.isNotEmpty) {
        final f = File('${dir.path}/evolution_$stamp.jpg');
        await f.writeAsBytes(bytes);
        await Share.shareXFiles(
          [XFile(f.path, mimeType: 'image/jpeg')], text: text);
        return;
      }
    } catch (_) {/* fall through */}

    // 4) Raw photos — guarantees the share sheet still opens.
    try {
      await Share.shareXFiles([
        XFile(beforePath, mimeType: 'image/jpeg'),
        XFile(afterPath, mimeType: 'image/jpeg'),
      ], text: text);
    } catch (_) {}
  }
}

// ── Isolate entry points (top-level for compute) ────────────────────────────

/// Builds an animated GIF that wipes Day 1 away to reveal the latest scan
/// — the same reveal the card plays. Runs in a background isolate. Returns
/// the GIF bytes, or null on any failure.
Uint8List? encodeRevealGif(Map<String, String> args) {
  try {
    final beforeRaw = img.decodeImage(File(args['before']!).readAsBytesSync());
    final afterRaw  = img.decodeImage(File(args['after']!).readAsBytesSync());
    if (beforeRaw == null || afterRaw == null) return null;

    const h = 460; // keep the GIF light + fast to encode
    final bR = img.copyResize(beforeRaw, height: h);
    final aR = img.copyResize(afterRaw, height: h);
    final w = bR.width < aR.width ? bR.width : aR.width;
    final b = img.copyCrop(bR, x: (bR.width - w) ~/ 2, y: 0, width: w, height: h);
    final a = img.copyCrop(aR, x: (aR.width - w) ~/ 2, y: 0, width: w, height: h);
    final white = img.ColorRgb8(255, 255, 255);

    const frames = 14;
    img.Image? gif;
    for (var i = 0; i < frames; i++) {
      final t = i / (frames - 1); // 0..1 reveal
      final frame = img.Image.from(a); // after is the base
      final cutW = ((1 - t) * w).round();
      if (cutW > 0) {
        final beforePart = img.copyCrop(b, x: 0, y: 0, width: cutW, height: h);
        img.compositeImage(frame, beforePart, dstX: 0, dstY: 0);
        img.drawLine(frame,
          x1: cutW, y1: 0, x2: cutW, y2: h, color: white, thickness: 3);
      }
      frame.frameDuration = i == frames - 1 ? 1400 : 95; // hold last frame
      if (gif == null) {
        gif = frame;
      } else {
        gif.addFrame(frame);
      }
    }
    if (gif == null) return null;
    return Uint8List.fromList(img.encodeGif(gif));
  } catch (_) {
    return null;
  }
}

/// Side-by-side Day 1 | now JPG, in a background isolate.
Uint8List? encodeJpgPair(Map<String, String> args) {
  try {
    final before = img.decodeImage(File(args['before']!).readAsBytesSync());
    final after  = img.decodeImage(File(args['after']!).readAsBytesSync());
    if (before == null || after == null) return null;
    const h = 900;
    final b = img.copyResize(before, height: h);
    final a = img.copyResize(after, height: h);
    const gap = 8;
    final canvas = img.Image(width: b.width + a.width + gap, height: h);
    img.fill(canvas, color: img.ColorRgb8(5, 9, 11));
    img.compositeImage(canvas, b, dstX: 0, dstY: 0);
    img.compositeImage(canvas, a, dstX: b.width + gap, dstY: 0);
    return Uint8List.fromList(img.encodeJpg(canvas, quality: 90));
  } catch (_) {
    return null;
  }
}
