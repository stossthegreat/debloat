import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../models/face_geometry.dart';
import '../../models/mirror_analysis.dart';
import '../../models/scan_record.dart';
import '../../services/archetype_service.dart';
import '../../services/face_asset_service.dart';
import '../../services/feature_analysis_service.dart';
import '../../services/local_store_service.dart';
import '../../services/mirror_api_service.dart';
import '../../services/scoring_service.dart';
import '../../services/trait_builder_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../services/chat_service.dart';
import '../../services/share_service.dart';
import '../../widgets/common/fullscreen_image.dart';
import '../../widgets/common/quick_tryon_chips.dart';
import '../../widgets/report/archetype_card.dart';
import '../../widgets/report/feature_grid.dart';
import '../../widgets/report/hero_card.dart';
import '../../widgets/report/hidden_depth_panel.dart';
import '../../widgets/report/radar_chart.dart';
import '../../widgets/report/trait_grid.dart';
import '../../widgets/report/verdict_card.dart';

class ReportScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final FaceGeometry geometry;
  final List<Uint8List> extraImages;

  const ReportScreen({
    super.key,
    required this.imageBytes,
    required this.geometry,
    this.extraImages = const [],
  });

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  MirrorAnalysis? _analysis;
  String? _error;
  // Populated once the scan image is persisted. Passed to chat/tryon so the
  // advisor can fire Flux renders inline using the real scan image.
  String? _savedImagePath;

  static const _loadingCopy = [
    'Resolving skin micro-texture',
    'Comparing structural archetypes',
    'Locking identity anchors',
    'Rendering maximized composite',
    'Finalizing preserve list',
  ];
  int _copyIdx = 0;

  @override
  void initState() {
    super.initState();
    _rotateCopy();
    _run();
  }

  void _rotateCopy() {
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted || _analysis != null) return;
      setState(() => _copyIdx = (_copyIdx + 1) % _loadingCopy.length);
      _rotateCopy();
    });
  }

  Future<void> _run() async {
    try {
      final result = await MirrorApiService.scan(
        imageBytes:  widget.imageBytes,
        geometry:    widget.geometry,
        extraImages: widget.extraImages,
      );
      if (mounted) setState(() => _analysis = result);
      // Persist the scan so it lights up Progress + Advisor tabs.
      await _persistScan(result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _persistScan(MirrorAnalysis a) async {
    final score = ScoringService.compute(widget.geometry);
    final match = ArchetypeService.bestMatch(widget.geometry);
    final id = 'scan-${DateTime.now().millisecondsSinceEpoch}';

    // Save the oriented JPEG to app docs so the advisor + tryon + gallery
    // can load it later without hitting the camera again.
    String? savedPath;
    try {
      savedPath = await FaceAssetService.saveScanImage(
        scanId: id, bytes: widget.imageBytes);
    } catch (_) {}
    if (savedPath != null && mounted) {
      setState(() => _savedImagePath = savedPath);
    }

    final record = ScanRecord(
      id:                 id,
      takenAt:            DateTime.now(),
      geometry:           widget.geometry,
      score:              score.value,
      tierLabel:          score.tierLabel,
      archetypeName:      match.archetype.name,
      archetypeMatchPct:  (match.match * 100).round(),
      capturedImagePath:  savedPath,
      maximizedImageUrl:  a.maximizedImageUrl,
    );
    await LocalStoreService.saveScan(record);

    // Also save the Flux twin into the Generation Vault so it shows up in the
    // gallery on the Progress tab.
    if (a.maximizedImageUrl.isNotEmpty) {
      await LocalStoreService.saveGeneration(GenerationRecord(
        id:            'gen-${DateTime.now().millisecondsSinceEpoch}',
        createdAt:     DateTime.now(),
        prompt:        'Maximized twin · ${match.archetype.name}',
        imageUrl:      a.maximizedImageUrl,
        relatedScanId: record.id,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: _analysis == null
            ? _buildLoading()
            : _buildReport(_analysis!),
      ),
    );
  }

  Widget _buildLoading() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Scan failed', style: AppTypography.h3.copyWith(
                color: AppColors.signalRed)),
              const SizedBox(height: 12),
              Text(_error!, style: AppTypography.bodySmall,
                textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () { setState(() => _error = null); _run(); },
                child: const Text('Retry'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.go('/home'),
                child: const Text('Back to home'),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 44, height: 44,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
          ),
          const SizedBox(height: 24),
          Text(_loadingCopy[_copyIdx].toUpperCase(),
            key: ValueKey(_copyIdx),
            style: AppTypography.label.copyWith(
              color: AppColors.measure, letterSpacing: 2.5, fontSize: 11)),
          const SizedBox(height: 6),
          Text('Identity anchored. ${_loadingCopy.length} layers compiling.',
            style: AppTypography.bodySmall.copyWith(
              fontSize: 11, color: AppColors.textTertiary)),
        ],
      ).animate().fadeIn(duration: 400.ms),
    );
  }

  /// Estimate percentile from score — rough but reads as real.
  int _percentile(int score) {
    if (score >= 92) return 2;
    if (score >= 85) return 8;
    if (score >= 78) return 16;
    if (score >= 70) return 28;
    if (score >= 60) return 44;
    return 62;
  }

  /// Potential delta — how many points a full maximisation could add.
  /// Capped at 22 so users believe the number.
  int _potentialDelta(int score) {
    final headroom = (100 - score).clamp(0, 40);
    return (headroom * 0.55).round();
  }

  /// Build the 3 micro-proof one-liners shown under the hero + on the share
  /// card. Pulls the top-3 STRENGTH traits and renders them as
  /// "TOP X% NAME" so each line reads as a verifiable spec, not marketing.
  /// Falls back to neutral but punchy lines when the user has fewer than 3
  /// strengths surfaced (rare on a clean scan).
  List<String> _buildMicroProofs(List<Trait> traits) {
    final strengths = traits
        .where((t) => t.kind == TraitKind.strength)
        .take(3)
        .toList();
    final lines = <String>[];
    for (final t in strengths) {
      final pct = t.pct.trim();
      // Some pct strings ("BALANCED FULLNESS") aren't percentile-shaped —
      // surface them verbatim. The percentile-shaped ones lead with the
      // number ("TOP 5% SYMMETRY") for the harder flex.
      if (pct.toUpperCase().startsWith('TOP ')) {
        lines.add('$pct ${t.name}');
      } else if (pct.isNotEmpty && !pct.contains(RegExp(r'[A-Z]{2,} [A-Z]{2,}'))) {
        lines.add('${t.name} · $pct');
      } else {
        lines.add(t.name);
      }
    }
    while (lines.length < 3) {
      lines.add(const ['MEASURED PROFILE', 'BALANCED FRAME',
                        'STRUCTURED ARCHETYPE'][lines.length]);
    }
    return lines;
  }

  Widget _buildReport(MirrorAnalysis a) {
    final score = ScoringService.compute(widget.geometry);
    final match = ArchetypeService.bestMatch(widget.geometry);
    final traits = TraitBuilderService.build(widget.geometry);
    final percentile = _percentile(score.value);
    final potential = _potentialDelta(score.value);
    final projected = (score.value + potential).clamp(0, 100);
    final correctionsCount = a.report.fixes.isNotEmpty
        ? a.report.fixes.length
        : 3;

    // Top-3 strength traits formatted as one-liners for the hero + share
    // cards. Falls back to neutral copy if the geometry is too dim to
    // surface 3 strengths (rare — e.g. low-confidence scan).
    final microProofs = _buildMicroProofs(traits);

    // The tagline that punches under the score transition. Prefer the
    // GPT-generated one-line verdict (specific, measurement-cited); fall
    // back to a deterministic line tied to the projection delta so it never
    // looks empty.
    final tagline = (a.report.oneLineVerdict.trim().isNotEmpty)
        ? a.report.oneLineVerdict
        : (potential >= 12
            ? "You're hiding your structure."
            : "You're closer than you think.");

    // 6-axis radar values (each 0..1) built from the same measurements
    // used by the trait system.
    final radarValues = [
      ((widget.geometry.canthalTilt + 2) / 7).clamp(0.0, 1.0),        // EYES
      (1.0 - ((widget.geometry.jawAngle - 110) / 30)).clamp(0.0, 1.0), // JAW
      (widget.geometry.symmetryScore / 100).clamp(0.0, 1.0),           // SYMMETRY
      (widget.geometry.lipFullness).clamp(0.0, 1.0),                   // LIPS
      ((2.0 - (widget.geometry.fwhr - 1.9).abs()) / 2.0).clamp(0.0, 1.0),// FWHR
      (1.0 - ((((widget.geometry.facialThirdTop - 33.33).abs()
                + (widget.geometry.facialThirdMid - 33.33).abs()
                + (widget.geometry.facialThirdLow - 33.33).abs()) / 3) / 10))
          .clamp(0.0, 1.0),                                            // BALANCE
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Share action
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('YOUR ANALYSIS', style: AppTypography.label.copyWith(
                      color: AppColors.textTertiary, letterSpacing: 2.5))
                      .animate().fadeIn(duration: 400.ms),
                    const SizedBox(height: Sp.xs),
                    Text('Down to the millimetre.',
                      style: AppTypography.h1.copyWith(fontSize: 28))
                      .animate().fadeIn(delay: 100.ms, duration: 400.ms),
                  ],
                ),
              ),
              _ShareButton(
                onTap: () => ShareService.shareComposed(
                  context:          context,
                  beforeBytes:      widget.imageBytes,
                  afterUrl:         a.maximizedImageUrl,
                  correctionsCount: correctionsCount,
                  microProofs:      microProofs,
                  text: '$correctionsCount corrections. Same face. mirrorly.app',
                ),
              ),
            ],
          ),

          const SizedBox(height: Sp.lg),

          // ── 1 · HERO CARD ─ score → projected, tagline, B/A, proofs ────
          HeroCard(
            currentScore:     score.value,
            projectedScore:   projected,
            tagline:          tagline,
            beforeBytes:      widget.imageBytes,
            afterUrl:         a.maximizedImageUrl,
            correctionsCount: correctionsCount,
            microProofs:      microProofs,
          ),

          const SizedBox(height: Sp.md),

          // ── 2 · TRAITS GRID ─ Umax secret sauce, ours backed by mesh ───
          TraitGrid(traits: traits)
            .animate().fadeIn(delay: 1600.ms, duration: 500.ms),

          const SizedBox(height: Sp.md),

          // ── 3 · RADAR ─ "measured, not guessed" proof ──────────────────
          RadarChart(
            values: radarValues,
            labels: const ['EYES', 'JAW', 'SYMMETRY', 'LIPS', 'FWHR', 'BALANCE'],
          ).animate().fadeIn(delay: 1900.ms, duration: 500.ms),

          const SizedBox(height: Sp.md),

          // ── 4 · APPLY ALL FIXES ────────────────────────────────────────
          // BeforeAfterCard removed — the hero card now carries the B/A
          // moment, and showing it twice diluted the impact.
          _ApplyAllFixesButton(
            maximizedImageUrl: a.maximizedImageUrl,
          ).animate().fadeIn(delay: 2400.ms, duration: 400.ms),

          const SizedBox(height: Sp.xl),

          // ── 5 · THREE FIX CARDS (GPT-sourced, with inline Flux) ────────
          Text('THE FIXES',
            style: AppTypography.label.copyWith(
              color: AppColors.gold, letterSpacing: 3.0, fontSize: 10)),
          const SizedBox(height: Sp.sm),
          ...a.report.fixes.asMap().entries.map((e) {
            // Each fix card displays the cumulative chain output for its
            // index — instantly, without a second Flux call. intermediateUrls
            // comes from the hero's 3-pass chain. If missing (older scan
            // or chain failure), the card falls back to firing /tryon.
            final pre = e.key < a.intermediateUrls.length
                ? a.intermediateUrls[e.key]
                : null;
            return _FixCard(
              index: e.key + 1, fix: e.value,
              capturedBytes:  widget.imageBytes,
              geometry:       widget.geometry,
              precomputedUrl: pre,
            ).animate().fadeIn(delay: Duration(milliseconds: 2600 + e.key * 120));
          }),

          const SizedBox(height: Sp.xl),

          // ── 7 · CONSULT CTA ────────────────────────────────────────────
          _ConsultCard(
            onTap: () => context.push(
              '/chat',
              extra: {'geometry': widget.geometry, 'imagePath': _savedImagePath},
            ),
          ).animate().fadeIn(delay: 3000.ms, duration: 400.ms),

          const SizedBox(height: Sp.xl),

          // ── 8 · DEEPER ANALYSIS ─ collapsed; the full detail dump ──────
          _DeeperAnalysisPanel(
            analysis:   a,
            geometry:   widget.geometry,
            match:      match,
            savedImagePath: _savedImagePath,
          ).animate().fadeIn(delay: 3200.ms, duration: 400.ms),

          const SizedBox(height: Sp.xl),

          // Verdict
          _Verdict(text: a.report.verdict)
            .animate().fadeIn(delay: 1500.ms, duration: 500.ms)
            .slideY(begin: 0.05, end: 0,
                delay: 1500.ms, duration: 500.ms, curve: Curves.easeOut),

          const SizedBox(height: Sp.xl),

          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.accent.withValues(alpha: 0.4)),
                      foregroundColor: AppColors.textPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Rd.lg)),
                    ),
                    onPressed: () => context.go('/home'),
                    child: const Text('Done'),
                  ),
                ),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: AppColors.base,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Rd.lg)),
                    ),
                    onPressed: () => context.push(
                      '/chat',
                      extra: {
                        'geometry':  widget.geometry,
                        'imagePath': _savedImagePath,
                      },
                    ),
                    child: const Text('Consult',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.md),
        ],
      ),
    );
  }
}

// ── Consultation CTA card ────────────────────────────────────────────────────
// ── DEEPER ANALYSIS · collapsed disclosure housing all old widgets ──────────
class _DeeperAnalysisPanel extends StatefulWidget {
  final MirrorAnalysis analysis;
  final FaceGeometry geometry;
  final ArchetypeMatch match;
  final String? savedImagePath;
  const _DeeperAnalysisPanel({
    required this.analysis, required this.geometry, required this.match,
    this.savedImagePath,
  });
  @override
  State<_DeeperAnalysisPanel> createState() => _DeeperAnalysisPanelState();
}

class _DeeperAnalysisPanelState extends State<_DeeperAnalysisPanel> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(Rd.lg),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(Rd.lg),
                border: Border.all(
                  color: AppColors.measure.withValues(alpha: 0.38), width: 0.9),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.measure.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.measure.withValues(alpha: 0.6), width: 0.8),
                    ),
                    child: const Icon(Icons.all_inclusive,
                      size: 17, color: AppColors.measure),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('READ THE FULL BREAKDOWN',
                          style: AppTypography.label.copyWith(
                            color: AppColors.measure,
                            letterSpacing: 2.6, fontSize: 10.5,
                            fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text('All 16 measurements · GPT read · fixes timeline',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textTertiary, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 240),
                    child: const Icon(Icons.expand_more_rounded,
                      color: AppColors.measure, size: 22),
                  ),
                ],
              ),
            ),
          ),
        ),

        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _open ? _fullDetail(context) : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _fullDetail(BuildContext context) {
    final a = widget.analysis;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Archetype details
          ArchetypeCard(match: widget.match),
          const SizedBox(height: Sp.md),

          // Feature-by-feature deep read
          FeatureGrid(
            reads: FeatureAnalysisService.analyse(widget.geometry),
            onSeeIt: (read) => context.push(
              '/chat',
              extra: {
                'geometry':  widget.geometry,
                'imagePath': widget.savedImagePath,
                'autoSend':  read.tryonPrompt,
              },
            ),
          ),
          const SizedBox(height: Sp.md),

          // 16-metric grid behind one more tap
          HiddenDepthPanel(geometry: widget.geometry),
          const SizedBox(height: Sp.md),

          // GPT prose blocks
          if (a.report.oneLineVerdict.isNotEmpty) ...[
            VerdictCard(
              verdict:   a.report.oneLineVerdict,
              score:     ScoringService.compute(widget.geometry).value,
              tier:      ScoringService.compute(widget.geometry).tierLabel,
              archetype: widget.match.archetype.name),
            const SizedBox(height: Sp.md),
          ],

          if (a.report.boneReading.isNotEmpty) ...[
            _Block(label: 'THE READ', color: AppColors.measure,
              body: a.report.boneReading),
            const SizedBox(height: Sp.md),
          ],
          _Block(label: 'WHAT\'S ALREADY WORKING', color: AppColors.signalGreen,
            body: a.report.strongest),
          const SizedBox(height: Sp.md),
          _Block(label: 'WHAT\'S HOLDING IT BACK', color: AppColors.signalRed,
            body: a.report.pulldown),

          const SizedBox(height: Sp.md),

          // Quick-action chips — kept here for depth users who want more renders
          Text('TRY MORE LOOKS',
            style: AppTypography.label.copyWith(
              color: AppColors.gold, letterSpacing: 2.5, fontSize: 9)),
          const SizedBox(height: Sp.sm),
          QuickTryonChips(
            geometry: widget.geometry,
            onTap: (style, cat) => context.push(
              '/chat',
              extra: {
                'geometry':  widget.geometry,
                'imagePath': widget.savedImagePath,
                'autoSend':  style,
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── APPLY ALL FIXES — the primary transformation moment ─────────────────────
class _ApplyAllFixesButton extends StatefulWidget {
  final String maximizedImageUrl;
  const _ApplyAllFixesButton({required this.maximizedImageUrl});

  @override
  State<_ApplyAllFixesButton> createState() => _ApplyAllFixesButtonState();
}

class _ApplyAllFixesButtonState extends State<_ApplyAllFixesButton> {
  bool _applied = false;

  @override
  Widget build(BuildContext context) {
    if (_applied) {
      // Final form unlocked — the maximized twin blown up, with glow
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.gold.withValues(alpha: 0.24),
              AppColors.gold.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(Rd.xl),
          border: Border.all(color: AppColors.gold, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.3),
              blurRadius: 36, offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('◆ FINAL FORM UNLOCKED',
              style: AppTypography.label.copyWith(
                color: AppColors.gold, letterSpacing: 3.2, fontSize: 10,
                fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(Rd.lg),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: GestureDetector(
                  onTap: () => FullscreenImage.open(context,
                    url: widget.maximizedImageUrl, caption: 'MAXIMIZED · you, applied'),
                  child: widget.maximizedImageUrl.isNotEmpty
                      ? Image.network(widget.maximizedImageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _errorBox())
                      : _errorBox(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('Tap to open fullscreen · share · screenshot',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary, fontSize: 11,
                fontStyle: FontStyle.italic)),
          ],
        ),
      ).animate()
        .fadeIn(duration: 450.ms)
        .scale(begin: const Offset(0.92, 0.92), end: const Offset(1, 1),
            duration: 450.ms, curve: Curves.easeOutBack);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.heavyImpact();
          setState(() => _applied = true);
        },
        borderRadius: BorderRadius.circular(Rd.lg),
        child: Container(
          width: double.infinity, height: 58,
          decoration: BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(Rd.lg),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withValues(alpha: 0.45),
                blurRadius: 22, offset: const Offset(0, 6)),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_awesome,
                size: 18, color: AppColors.base),
              const SizedBox(width: 10),
              Text('APPLY ALL FIXES',
                style: AppTypography.label.copyWith(
                  color: AppColors.base, letterSpacing: 3.0, fontSize: 13,
                  fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorBox() => Container(
    color: AppColors.surface1,
    alignment: Alignment.center,
    child: Text('Maximized render unavailable',
      style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted)),
  );
}

class _ConsultCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ConsultCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.xl),
        child: Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.gold.withValues(alpha: 0.10),
                AppColors.gold.withValues(alpha: 0.03),
              ],
            ),
            borderRadius: BorderRadius.circular(Rd.xl),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.6), width: 0.8),
                ),
                child: const Icon(Icons.auto_awesome,
                  size: 18, color: AppColors.gold),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CONSULT THE AI',
                      style: AppTypography.label.copyWith(
                        color: AppColors.gold, letterSpacing: 2.6, fontSize: 9)),
                    const SizedBox(height: 3),
                    Text('Ask about haircut, beard, skin, surgery — answered '
                         'against your measured bones.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary, fontSize: 12, height: 1.4)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward_rounded,
                size: 18, color: AppColors.gold),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Share button (top-right of report header) ───────────────────────────────
class _ShareButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ShareButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: AppColors.gold.withValues(alpha: 0.55), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.ios_share_rounded,
                size: 14, color: AppColors.gold),
              const SizedBox(width: 6),
              Text('SHARE',
                style: AppTypography.label.copyWith(
                  color: AppColors.gold, letterSpacing: 2.0, fontSize: 10,
                  fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Block card ────────────────────────────────────────────────────────────────
class _Block extends StatelessWidget {
  final String label;
  final Color color;
  final String body;

  const _Block({required this.label, required this.color, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 2, height: 36,
            margin: const EdgeInsets.only(top: 2, right: Sp.sm),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.label.copyWith(
                  color: color, letterSpacing: 1.8, fontSize: 9)),
                const SizedBox(height: 5),
                Text(body, style: AppTypography.body.copyWith(
                  color: AppColors.textPrimary, height: 1.55)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Fix card ──────────────────────────────────────────────────────────────────
class _FixCard extends StatefulWidget {
  final int index;
  final Fix fix;
  final Uint8List? capturedBytes;
  final FaceGeometry geometry;
  /// Pre-rendered URL from the hero's Flux chain — the cumulative state
  /// after this fix was applied. When present, the card shows it
  /// immediately on tap (no extra API call). Falls back to firing /tryon
  /// only if absent (older scan, chain failure, etc).
  final String? precomputedUrl;
  const _FixCard({
    required this.index, required this.fix,
    required this.capturedBytes, required this.geometry,
    this.precomputedUrl,
  });
  @override
  State<_FixCard> createState() => _FixCardState();
}

class _FixCardState extends State<_FixCard> {
  String? _renderUrl;
  bool    _rendering = false;
  String? _renderError;

  Future<void> _seeIt() async {
    if (_rendering) return;

    // Fast path — the Flux chain already produced the cumulative image
    // for this fix as part of /scan. Use it verbatim, no second Flux call.
    final pre = widget.precomputedUrl;
    if (pre != null && pre.isNotEmpty) {
      setState(() {
        _renderUrl   = pre;
        _renderError = null;
      });
      return;
    }

    setState(() { _rendering = true; _renderError = null; });

    try {
      // PROTOCOL vs VISUAL — critical split. `fix.action` is the user's
      // routine ("Tretinoin 0.025% nightly, moisturize with CeraVe") and
      // Flux Kontext, being an image model, will render that literally
      // (cream on the face, bottles in the shot). GPT now returns a
      // dedicated `visualRequest` that describes only the visible end
      // state of the face — use that when we have it, and fall back to
      // the title alone if GPT/older-cache didn't populate it.
      final style = widget.fix.visualRequest.trim().isNotEmpty
          ? widget.fix.visualRequest
          : widget.fix.title;
      final cat   = _guessCategory(widget.fix.title, widget.fix.action);
      // Save bytes to disk on-the-fly so TryOnService can load them.
      final bytes = widget.capturedBytes;
      String? url;
      if (bytes != null) {
        // Inline call — bypass the service's file-path loading by posting
        // bytes directly. Simpler: reuse the service by saving a temp file.
        final tempId = 'fix-${DateTime.now().millisecondsSinceEpoch}';
        final path = await FaceAssetService.saveScanImage(
          scanId: tempId, bytes: bytes);
        url = await TryOnService.render(
          imagePath:    path,
          styleRequest: style,
          category:     cat,
          geometry:     widget.geometry,
        );
      }
      if (!mounted) return;
      setState(() {
        _renderUrl = url;
        _rendering = false;
        _renderError = url == null ? 'Couldn\'t render — try again' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rendering = false;
        _renderError = 'Error rendering';
      });
    }
  }

  String _guessCategory(String title, String action) {
    final t = '$title $action'.toLowerCase();
    // Order matters — beard/facial-hair keywords often also contain "hair"
    // ("facial hair"), so check beard first before the haircut regex.
    if (RegExp(r'\b(beard|stubble|facial hair|goatee|mustache|moustache)\b').hasMatch(t)) return 'beard';
    if (RegExp(r'\b(brow|eyebrow|browline)\b').hasMatch(t))                               return 'eyebrow';
    if (RegExp(r'\b(glasses|frame|eyewear|specs)\b').hasMatch(t))                          return 'glasses';
    if (RegExp(r'\b(skin|acne|pore|texture|tone|retinol|tret|cream|sunscreen|glow|blemish|dark circle|under-eye)\b').hasMatch(t)) return 'skin';
    if (RegExp(r'\b(teeth|tooth|whiten|bleach|smile)\b').hasMatch(t))                      return 'teeth';
    if (RegExp(r'\b(color|dye|tint|bleach|highlight)\b').hasMatch(t))                      return 'hair_color';
    if (RegExp(r'\b(lean|cut|body|weight|fat|recomp|bulk)\b').hasMatch(t))                 return 'weight';
    if (RegExp(r'\b(hair|fade|crop|cut|fringe|undercut|buzz|trim|taper|hairstyle)\b').hasMatch(t)) return 'haircut';
    // Fallback: 'generic' (not 'haircut'). A generic fix gets a conservative
    // preservation clause in tryon.js that locks every feature — safer than
    // accidentally classifying a jaw-exercise fix as a haircut and shaving
    // the user's head.
    return 'generic';
  }

  @override
  Widget build(BuildContext context) {
    final fix = widget.fix;
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.md),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.index}',
                style: AppTypography.h1.copyWith(
                  color: AppColors.accent, fontSize: 28, letterSpacing: -1)),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(fix.title.toUpperCase(),
                      style: AppTypography.h3.copyWith(
                        color: AppColors.textPrimary, letterSpacing: 0.5)),
                    const SizedBox(height: 4),
                    Text(fix.reason,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary, height: 1.55)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.sm),
          const Divider(height: 1),
          const SizedBox(height: Sp.sm),
          Text('DO THIS', style: AppTypography.label.copyWith(
            color: AppColors.measure, fontSize: 9, letterSpacing: 1.8)),
          const SizedBox(height: 4),
          Text(fix.action, style: AppTypography.body.copyWith(
            color: AppColors.textPrimary, fontSize: 14, height: 1.55)),
          const SizedBox(height: Sp.sm),
          Row(
            children: [
              _Chip(label: fix.timeline, color: AppColors.textTertiary),
              const SizedBox(width: 8),
              _Chip(label: 'RESCAN DAY ${fix.rescanDay}', color: AppColors.accent),
            ],
          ),
          const SizedBox(height: Sp.md),

          // "See It" — generates a Flux Kontext render of the user with this change
          if (_renderUrl != null)
            GestureDetector(
              onTap: () => FullscreenImage.open(context,
                url: _renderUrl, caption: fix.title),
              child: Container(
                width: double.infinity,
                height: 160,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Rd.md),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
                ),
                child: Image.network(_renderUrl!, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                    child: Text('Render unavailable',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textMuted))),
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity, height: 44,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.gold.withValues(alpha: 0.55)),
                  foregroundColor: AppColors.gold,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Rd.md)),
                ),
                onPressed: _rendering ? null : _seeIt,
                child: _rendering
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8, color: AppColors.gold))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome,
                          size: 14, color: AppColors.gold),
                        const SizedBox(width: 8),
                        Text('SEE IT ON YOUR FACE',
                          style: AppTypography.label.copyWith(
                            color: AppColors.gold, letterSpacing: 2.0,
                            fontSize: 10, fontWeight: FontWeight.w800)),
                      ],
                    ),
              ),
            ),
          if (_renderError != null) ...[
            const SizedBox(height: 6),
            Text(_renderError!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.signalAmber, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      border: Border.all(color: color.withValues(alpha: 0.3)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(label.toUpperCase(),
      style: AppTypography.label.copyWith(
        color: color, fontSize: 9, letterSpacing: 1.4)),
  );
}

// ── Verdict ───────────────────────────────────────────────────────────────────
class _Verdict extends StatelessWidget {
  final String text;
  const _Verdict({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(color: AppColors.accentBorder),
        boxShadow: [BoxShadow(
          color: AppColors.accent.withValues(alpha: 0.06),
          blurRadius: 24,
        )],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VERDICT', style: AppTypography.label.copyWith(
            color: AppColors.accent, letterSpacing: 2.5)),
          const SizedBox(height: Sp.md),
          Text(text, style: AppTypography.body.copyWith(
            height: 1.75, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
