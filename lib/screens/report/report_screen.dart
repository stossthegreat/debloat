import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../models/face_geometry.dart';
import '../../models/mirror_analysis.dart';
import '../../models/scan_record.dart';
import '../../models/protocol.dart';
import '../../services/archetype_service.dart';
import '../../services/face_asset_service.dart';
import '../../services/feature_analysis_service.dart';
import '../../services/honest_rating_service.dart';
import '../../services/local_store_service.dart';
import '../../services/mirror_api_service.dart';
import '../../services/protocol_service.dart';
import '../../services/scoring_service.dart';
import '../../services/trait_builder_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../services/share_service.dart';
import '../../widgets/common/fullscreen_image.dart';
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
  // GPT-4o Vision honest-looks rating. Fires in parallel with /scan so
  // the added latency is absorbed. Null = model refused (rare) and the
  // dual-score hero degrades to geometry-only.
  HonestRating? _honest;

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
      // Fire /scan and /rate in parallel. Rate is ~3s, scan is ~10s, so
      // running concurrently keeps the perceived loading time flat.
      // Rate degrades gracefully to null on refusal / failure — the
      // report still renders in geometry-only mode.
      final imageB64 = base64Encode(widget.imageBytes);

      final scanFuture   = MirrorApiService.scan(
        imageBytes:  widget.imageBytes,
        geometry:    widget.geometry,
        extraImages: widget.extraImages,
      );
      final honestFuture = HonestRatingService.rate(imageBase64: imageB64);

      final results = await Future.wait<dynamic>([scanFuture, honestFuture]);
      final result = results[0] as MirrorAnalysis;
      final honest = results[1] as HonestRating?;

      if (mounted) {
        setState(() {
          _analysis = result;
          _honest   = honest;
        });
      }
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
      // Translate raw backend errors into a human message. We never show
      // "Backend 500: {"error":"Request to ...api.replicate.com... 429
      // Too Many Requests: ..."}" to the user — that's an internal
      // stack-dump and it scares people.
      final friendly = _friendlyError(_error!);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(friendly.title, style: AppTypography.h3.copyWith(
                color: AppColors.signalRed)),
              const SizedBox(height: 12),
              Text(friendly.body,
                style: AppTypography.bodySmall,
                textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () { setState(() => _error = null); _run(); },
                child: const Text('Try again'),
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

  /// Convert backend stack-dump errors into a human message. Raw
  /// backend JSON never reaches the user — they see a clean sentence
  /// plus Try Again. 429s get their own copy since they're transient.
  ({String title, String body}) _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('429') || lower.contains('too many requests') ||
        lower.contains('throttled') || lower.contains('rate limit')) {
      return (
        title: 'Slight wait',
        body: 'We\'re rendering a lot of scans right now. '
              'Give it a few seconds and try again.',
      );
    }
    if (lower.contains('timeout') || lower.contains('timed out') ||
        lower.contains('socket')) {
      return (
        title: 'Connection dropped',
        body: 'Check your connection and try again. '
              'Your scan is safe.',
      );
    }
    if (lower.contains('500') || lower.contains('502') ||
        lower.contains('503') || lower.contains('504')) {
      return (
        title: 'Server hiccup',
        body: 'Something on our end — it\'s usually temporary. '
              'Try again in a moment.',
      );
    }
    return (
      title: 'Scan didn\'t complete',
      body: 'Something interrupted the render. Try again.',
    );
  }

  /// Potential delta — how many points a full maximisation could add.
  /// Capped at 22 so users believe the number.
  int _potentialDelta(int score) {
    final headroom = (100 - score).clamp(0, 40);
    return (headroom * 0.55).round();
  }

  /// Build the 3 micro-proof one-liners shown under the hero + on the share
  /// card. Pulls the top-3 STRENGTH traits and renders their pre-composed
  /// emotional heroLine strings — "Your hunter eyes beat 88% of men" reads
  /// and shares harder than "TOP 12% HUNTER EYES". Falls back to neutral
  /// but punchy lines when fewer than 3 strengths surfaced.
  List<String> _buildMicroProofs(List<Trait> traits) {
    final strengths = traits
        .where((t) => t.kind == TraitKind.strength)
        .take(3)
        .toList();
    final lines = [
      for (final t in strengths)
        t.heroLine.trim().isNotEmpty ? t.heroLine : t.name,
    ];
    while (lines.length < 3) {
      lines.add(const [
        'Measured profile — 16 geometry points',
        'Balanced frame — proportions check',
        'Structured archetype — bones on spec',
      ][lines.length]);
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

    // The tagline under the before/after on both the results hero and
    // the share card. Priority order:
    //   1. The honest-rating viral killer line (_honest.note) — one
    //      sentence leading with the strongest feature, built for
    //      shareability. Freshest per user, never templated.
    //   2. The GPT analyse `oneLineVerdict` — longer, measurement-cited.
    //   3. A computed fallback anchored to their actual strongest axis
    //      so it never defaults to the same string twice.
    final honestNote = (_honest?.note ?? '').trim();
    final tagline = honestNote.isNotEmpty
        ? honestNote
        : (a.report.oneLineVerdict.trim().isNotEmpty
            ? a.report.oneLineVerdict
            : '${score.strongestAxis.$1} carries the frame.');

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
                  context:        context,
                  beforeBytes:    widget.imageBytes,
                  afterUrl:       a.maximizedImageUrl,
                  // Share card leads with the honest (vision) score when
                  // available, so the shared image tells the same truth
                  // as the results page. Projected still comes from the
                  // geometry potential model.
                  currentScore:   _honest?.score ?? score.value,
                  projectedScore: projected,
                  tagline:        tagline,
                  // First two bullets = the two scores (our moat, named).
                  // Third bullet = the top strength trait so the card
                  // still flexes something specific.
                  microProofs: [
                    if (_honest != null)
                      'HONEST LOOKS · ${_honest!.score}/100'
                    else
                      'BONES · ${score.value}/100',
                    'BONE STRUCTURE · ${score.value}/100',
                    microProofs.isNotEmpty ? microProofs.first : 'MEASURED PROFILE',
                  ],
                  text: '${_honest?.score ?? score.value} → $projected. '
                        'Same face. mirrorly.app',
                ),
              ),
            ],
          ),

          const SizedBox(height: Sp.lg),

          // ── 0 · DUAL-SCORE HERO ─ honest (big) + bone structure (under) ─
          // Two scores is the moat. Honest is GPT-4o Vision's real-photo
          // read — skin, eye area, proportions — with no geometry context
          // so bones can't bail out a bad face. Bone structure is our
          // on-device measurement math, shown smaller as the companion
          // number. Degrades to geometry-only if the vision model refused.
          _DualScoreHero(
            honest:    _honest,
            geometry:  score.value,
          ),

          const SizedBox(height: Sp.md),

          // ── 1 · HERO CARD ─ score → projected, tagline, B/A, proofs ────
          HeroCard(
            currentScore:     _honest?.score ?? score.value,
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
          //
          // When the hero URL is empty (Replicate was down during /scan and
          // we returned report-only), the button's state morphs to a
          // "Generate hero image" retry that hits /maximize directly. No
          // re-scan required.
          _ApplyAllFixesButton(
            maximizedImageUrl: a.maximizedImageUrl,
            imageBytes:        widget.imageBytes,
            improveList:       a.report.fixes
                .map((f) => f.visualRequest.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
          ).animate().fadeIn(delay: 2400.ms, duration: 400.ms),

          const SizedBox(height: Sp.xl),

          // ── 5 · FIX HEADLINES (text only — no per-fix Flux render) ─────
          // We deliberately don't render per-fix inline try-ons any more
          // (each tap on "See it" fired a fresh /tryon → 3 extra Nano
          // Banana calls per scan). The hero "Final form" already shows
          // the combined maximized twin, and the Mirror chat can render
          // one-at-a-time if the user wants to drill in. This is a pure
          // cost reduction — text advice stays, generation is centralised.
          Text('THE FIXES',
            style: AppTypography.label.copyWith(
              color: AppColors.textTertiary, letterSpacing: 3.0, fontSize: 10)),
          const SizedBox(height: Sp.sm),
          ...a.report.fixes.asMap().entries.map((e) =>
            _FixTextCard(index: e.key + 1, fix: e.value)
              .animate().fadeIn(delay: Duration(milliseconds: 2600 + e.key * 120))),

          const SizedBox(height: Sp.xl),

          // ── 6 · CONSULT CTA ────────────────────────────────────────────
          _ConsultCard(
            onTap: () => context.push(
              '/chat',
              extra: {'geometry': widget.geometry, 'imagePath': _savedImagePath},
            ),
          ).animate().fadeIn(delay: 2900.ms, duration: 400.ms),

          const SizedBox(height: Sp.xl),

          // ── 7 · DEEPER ANALYSIS ─ always-open full breakdown ───────────
          // Previously the two nested dropdowns (this panel + the inner
          // HiddenDepthPanel) gated content behind two taps. That's our
          // moat — 16 measurements, archetype match, feature-by-feature
          // read, GPT prose — no other app surfaces it. Release it all.
          _DeeperAnalysisPanel(
            analysis:   a,
            geometry:   widget.geometry,
            match:      match,
            savedImagePath: _savedImagePath,
          ).animate().fadeIn(delay: 3000.ms, duration: 400.ms),

          const SizedBox(height: Sp.xl),

          // Verdict
          _Verdict(text: a.report.verdict)
            .animate().fadeIn(delay: 1500.ms, duration: 500.ms)
            .slideY(begin: 0.05, end: 0,
                delay: 1500.ms, duration: 500.ms, curve: Curves.easeOut),

          const SizedBox(height: Sp.xl),

          // ── 8 · PROTOCOL CTA ─ the final commit moment ─────────────────
          // Moved to sit just above the Done/Consult row so it's the last
          // thing the user sees as they finish reading. Auto-prescribed
          // 60-day routine keyed to the scan's pulldown axis. If a
          // protocol is already active the card morphs to "Continue day
          // X" rather than overwriting it.
          _ProtocolCtaCard(
            pulldown: a.report.pulldown,
            geometry: widget.geometry,
          ).animate().fadeIn(delay: 3200.ms, duration: 400.ms),

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
                      backgroundColor: AppColors.red,
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

// ── Full breakdown — always open, always rendered ───────────────────────────
//
// Was a tap-to-expand disclosure. User's call: "instead of drop down, open
// them so it's one big page. That's our thing — we can give all those
// details no one else can. So release it all." Header + animation removed;
// content rendered directly. Try-on chips removed too (per the same note:
// the presets were feeling like a gimmick on the results card, and the
// Mirror chat is where on-demand renders live now).
class _DeeperAnalysisPanel extends StatelessWidget {
  final MirrorAnalysis analysis;
  final FaceGeometry geometry;
  final ArchetypeMatch match;
  final String? savedImagePath;
  const _DeeperAnalysisPanel({
    required this.analysis, required this.geometry, required this.match,
    this.savedImagePath,
  });

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final scoreComputed = ScoringService.compute(geometry);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Small section masthead so the breakdown reads as its own block,
        // not a random pile of cards.
        Text('FULL BREAKDOWN',
          style: AppTypography.label.copyWith(
            color: AppColors.measure,
            letterSpacing: 2.8, fontSize: 10.5,
            fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text('All 16 measurements · archetype · feature-by-feature read',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textTertiary, fontSize: 11.5, height: 1.4)),
        const SizedBox(height: Sp.md),

        // Archetype details
        ArchetypeCard(match: match),
        const SizedBox(height: Sp.md),

        // Feature-by-feature deep read
        FeatureGrid(
          reads: FeatureAnalysisService.analyse(geometry),
          onSeeIt: (read) => context.push(
            '/chat',
            extra: {
              'geometry':  geometry,
              'imagePath': savedImagePath,
              'autoSend':  read.tryonPrompt,
            },
          ),
        ),
        const SizedBox(height: Sp.md),

        // 16-metric grid — previously behind a second tap, now inline
        HiddenDepthPanel(geometry: geometry),
        const SizedBox(height: Sp.md),

        // GPT prose blocks
        if (a.report.oneLineVerdict.isNotEmpty) ...[
          VerdictCard(
            verdict:   a.report.oneLineVerdict,
            score:     scoreComputed.value,
            tier:      scoreComputed.tierLabel,
            archetype: match.archetype.name),
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
        _Block(label: 'WHAT\'S HOLDING IT BACK', color: AppColors.signalAmber,
          body: a.report.pulldown),
      ],
    );
  }
}

// ── APPLY ALL FIXES — the primary transformation moment ─────────────────────
class _ApplyAllFixesButton extends StatefulWidget {
  final String maximizedImageUrl;
  /// Captured selfie bytes — needed to call /maximize for the retry path
  /// if the original /scan returned an empty hero url.
  final Uint8List imageBytes;
  /// The three visualRequest strings from the fix cards (same thing /scan
  /// normally feeds to maximize as the "improve" list).
  final List<String> improveList;

  const _ApplyAllFixesButton({
    required this.maximizedImageUrl,
    required this.imageBytes,
    required this.improveList,
  });

  @override
  State<_ApplyAllFixesButton> createState() => _ApplyAllFixesButtonState();
}

class _ApplyAllFixesButtonState extends State<_ApplyAllFixesButton> {
  bool _applied = false;
  String? _localUrl;   // populated by a successful retry
  bool _retrying = false;
  String? _retryError;

  String get _effectiveUrl =>
      (_localUrl != null && _localUrl!.isNotEmpty)
          ? _localUrl!
          : widget.maximizedImageUrl;

  /// Single tap handler for the APPLY ALL FIXES button. Handles both
  /// cases transparently:
  ///   · URL already present (normal scan) → reveal the hero image.
  ///   · URL empty (Replicate was down during /scan) → fire /maximize
  ///     right here, wait, then reveal. Same button, same interaction —
  ///     the user never sees a separate "retry" card.
  Future<void> _onApplyTap() async {
    if (_retrying) return;
    HapticFeedback.heavyImpact();

    // Fast path — we already have a URL, just reveal it.
    if (_effectiveUrl.isNotEmpty) {
      setState(() => _applied = true);
      return;
    }

    // Slow path — render on demand.
    setState(() { _retrying = true; _retryError = null; });
    try {
      final url = await MirrorApiService.maximizeOnly(
        imageBytes: widget.imageBytes,
        improve:    widget.improveList,
      );
      if (!mounted) return;
      setState(() {
        _localUrl = url;
        _retrying = false;
        _applied  = true; // reveal immediately; the tap was the commit
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _retryError = _friendlyRetryError(err);
        _retrying = false;
      });
    }
  }

  String _friendlyRetryError(Object err) {
    final s = err.toString().toLowerCase();
    if (s.contains('timeout') || s.contains('timed out')) {
      return 'Render is taking too long. Try once more.';
    }
    if (s.contains('429')) {
      return 'We\'re rendering a lot of scans right now. Try again in a moment.';
    }
    if (RegExp(r'\b50\d\b').hasMatch(s)) {
      return 'Image service had a hiccup. Try again.';
    }
    if (s.contains('socket') || s.contains('network')) {
      return 'Connection dropped. Check your network and try again.';
    }
    return 'Couldn\'t render. Try again.';
  }

  @override
  Widget build(BuildContext context) {
    final url = _effectiveUrl;

    // ─── Hero revealed — final form ─────────────────────────────────────
    if (_applied && url.isNotEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(Rd.xl),
          border: Border.all(color: AppColors.divider, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('◆ FINAL FORM UNLOCKED',
              style: AppTypography.label.copyWith(
                color: AppColors.red, letterSpacing: 3.2, fontSize: 10,
                fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(Rd.lg),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: GestureDetector(
                  onTap: () => FullscreenImage.open(context,
                    url: url, caption: 'MAXIMIZED · you, applied'),
                  child: Image.network(url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _errorBox()),
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

    // ─── CTA — Apply all fixes (same button, both paths) ────────────────
    // When url is present, tap → instant reveal.
    // When url is empty,  tap → fire /maximize in-place → reveal on
    // success. Same visual affordance either way; the only surface-level
    // difference is the spinner during the slow path. The old separate
    // "retry card" is gone — users get one button, one interaction.
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _retrying ? null : _onApplyTap,
            borderRadius: BorderRadius.circular(Rd.lg),
            child: Container(
              width: double.infinity, height: 58,
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(Rd.lg),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.red.withValues(alpha: 0.45),
                    blurRadius: 22, offset: const Offset(0, 6)),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_retrying) ...[
                    const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                        color: AppColors.base, strokeWidth: 2.2)),
                    const SizedBox(width: 12),
                    Text('RENDERING…',
                      style: AppTypography.label.copyWith(
                        color: AppColors.base, letterSpacing: 3.0,
                        fontSize: 13, fontWeight: FontWeight.w900)),
                  ] else ...[
                    const Icon(Icons.auto_awesome,
                      size: 18, color: AppColors.base),
                    const SizedBox(width: 10),
                    Text('APPLY ALL FIXES',
                      style: AppTypography.label.copyWith(
                        color: AppColors.base, letterSpacing: 3.0,
                        fontSize: 13, fontWeight: FontWeight.w900)),
                  ],
                ],
              ),
            ),
          ),
        ),
        // Retry error surfaces just below the button — stays visible on
        // the same screen as the CTA so the user can tap again without
        // scrolling or navigating.
        if (_retryError != null) ...[
          const SizedBox(height: 8),
          Text(_retryError!,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.signalAmber, fontSize: 11.5)),
        ],
      ],
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
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(Rd.xl),
            border: Border.all(color: AppColors.divider, width: 0.8),
          ),
          child: Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.divider, width: 0.8),
                ),
                child: const Icon(Icons.auto_awesome,
                  size: 18, color: AppColors.textSecondary),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CONSULT THE AI',
                      style: AppTypography.label.copyWith(
                        color: AppColors.textPrimary, letterSpacing: 2.6, fontSize: 9,
                        fontWeight: FontWeight.w800)),
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
                size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Protocol CTA card — auto-prescribe the 60-day routine keyed to the
// scan's pulldown axis. Smart-state: shows "Start" for a fresh user, and
// "Continue day X · N-day streak" if they already have an active protocol.
// Never overwrites an existing protocol — the user ends it explicitly from
// the Protocol screen if they want to start over.
class _ProtocolCtaCard extends StatefulWidget {
  final String pulldown;
  final FaceGeometry geometry;
  const _ProtocolCtaCard({
    required this.pulldown, required this.geometry,
  });

  @override
  State<_ProtocolCtaCard> createState() => _ProtocolCtaCardState();
}

class _ProtocolCtaCardState extends State<_ProtocolCtaCard> {
  Protocol? _active;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadActive();
  }

  Future<void> _loadActive() async {
    final p = await ProtocolService.loadActive();
    if (!mounted) return;
    setState(() { _active = p; _loading = false; });
  }

  Future<void> _onTap() async {
    if (_busy) return;
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    try {
      // Existing protocol? Continue it — do not overwrite a run in progress.
      if (_active != null) {
        if (!mounted) return;
        context.push('/protocol');
        return;
      }
      // Fresh — auto-prescribe and push.
      final scan = await LocalStoreService.latestScan();
      if (scan == null) return;
      await ProtocolService.startForScan(
        scan,
        pulldown: widget.pulldown,
        geometry: widget.geometry,
      );
      if (!mounted) return;
      context.push('/protocol');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      // Reserve approximate card height so the layout doesn't jump once the
      // active protocol check resolves.
      return const SizedBox(height: 168);
    }

    final hasActive = _active != null;
    // Resolve the canonical axis from the prose pulldown + geometry so the
    // card shows a short clean label ("Jaw definition"), not the full
    // 2-sentence backend pulldown. This is the same resolution used when
    // the user actually taps Start — so what they see matches what they'll
    // get.
    final resolvedAxis = ProtocolService.resolveAxis(
      pulldown: widget.pulldown,
      geometry: widget.geometry,
    );

    final header = hasActive ? 'ACTIVE · 60-DAY PROTOCOL' : '60-DAY PROTOCOL';
    final headline = hasActive
        ? _active!.title
        : 'Targeting ${resolvedAxis.toLowerCase()}.';
    final body = hasActive
        ? 'Day ${_active!.currentDay} of ${_active!.lengthDays}. '
          '${_active!.effectiveStreak}-day streak. Tap to log today.'
        : 'A daily routine built from your scan — morning, midday, '
          'evening, night — time-banded and evidence-aware. Streak locks '
          'it in. Rescans at day 14, 30, 60.';
    final btnText = hasActive ? 'Continue today' : 'Start the 60-day plan';

    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(
          color: AppColors.red.withValues(alpha: 0.32), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(header,
                style: AppTypography.label.copyWith(
                  color: AppColors.red,
                  letterSpacing: 2.8, fontSize: 10,
                  fontWeight: FontWeight.w800)),
              const Spacer(),
              if (hasActive) ...[
                Icon(Icons.local_fire_department,
                  size: 13, color: AppColors.red),
                const SizedBox(width: 2),
                Text('${_active!.effectiveStreak}',
                  style: AppTypography.measurement.copyWith(
                    color: AppColors.red,
                    fontSize: 12, fontWeight: FontWeight.w800)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(headline,
            style: AppTypography.h1.copyWith(
              fontSize: 22, letterSpacing: -0.4, height: 1.15)),
          const SizedBox(height: 6),
          Text(body,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12.5, height: 1.5)),
          const SizedBox(height: Sp.md),
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: AppColors.base,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Rd.lg)),
                elevation: 0,
              ),
              onPressed: _busy ? null : _onTap,
              child: _busy
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                        color: AppColors.base, strokeWidth: 2))
                  : Text(btnText,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14, letterSpacing: 0.4)),
            ),
          ),
        ],
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
            color: AppColors.red.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.55), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.ios_share_rounded,
                size: 14, color: AppColors.red),
              const SizedBox(width: 6),
              Text('SHARE',
                style: AppTypography.label.copyWith(
                  color: AppColors.red, letterSpacing: 2.0, fontSize: 10,
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
// ── Fix text card — text-only, no inline render ────────────────────────────
// Previously this card offered a "See it" button that fired /tryon and
// rendered a per-fix Nano Banana image (three fix cards × one render each =
// three extra generations per scan, the single biggest cost item in the
// report). We've pulled that generation out of the report entirely. The
// hero "Final form" already shows the combined maximized twin; users who
// want to drill into a single change can do it one at a time via the
// Mirror chat, which remains the only per-user render surface.
class _FixTextCard extends StatelessWidget {
  final int index;
  final Fix fix;
  const _FixTextCard({required this.index, required this.fix});

  @override
  Widget build(BuildContext context) {
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
              Text('$index',
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

// ═══════════════════════════════════════════════════════════════════════════
//  DUAL SCORE HERO
//
//  The two-score read sits directly above the main hero card:
//    HONEST LOOKS  — big italic red number, GPT-4o Vision's real-photo rating.
//    BONE STRUCTURE — small chip, on-device geometry score.
//
//  Honest is the hero because it's the uncontaminated truth. Bones are the
//  secondary because that's our unique measurement moat — we keep it
//  visible so users know the geometry is real, not invented.
//
//  Degrades cleanly: if honest is null (model refused or network failed)
//  the bones score promotes to hero and the eyebrow reads BONES ONLY.
// ═══════════════════════════════════════════════════════════════════════════
class _DualScoreHero extends StatelessWidget {
  final HonestRating? honest;
  final int geometry;

  const _DualScoreHero({required this.honest, required this.geometry});

  @override
  Widget build(BuildContext context) {
    final hasHonest = honest != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(
          color: AppColors.red.withValues(alpha: 0.28), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withValues(alpha: 0.14),
            blurRadius: 24, spreadRadius: -4),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(hasHonest ? 'THE TRUTH · TWO SCORES' : 'THE READ · BONES ONLY',
            style: AppTypography.label.copyWith(
              color: AppColors.red,
              letterSpacing: 3.0, fontSize: 9.5,
              fontWeight: FontWeight.w800)),

          const SizedBox(height: 14),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${honest?.score ?? geometry}',
                style: AppTypography.measurement.copyWith(
                  color: AppColors.red,
                  fontSize: 78, height: 1,
                  letterSpacing: -2.8,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w800,
                  shadows: [
                    Shadow(
                      color: AppColors.red.withValues(alpha: 0.35),
                      blurRadius: 22),
                  ],
                )),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text('/ 100',
                  style: AppTypography.label.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 11, letterSpacing: 2.2,
                    fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(hasHonest ? 'HONEST LOOKS' : 'BONE STRUCTURE',
                      style: AppTypography.label.copyWith(
                        color: AppColors.textSecondary,
                        letterSpacing: 2.4, fontSize: 9.5,
                        fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(hasHonest ? 'GPT-4 · VISION' : 'ON-DEVICE GEOMETRY',
                      style: AppTypography.label.copyWith(
                        color: AppColors.textTertiary,
                        letterSpacing: 2.0, fontSize: 8,
                        fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),

          if (hasHonest && honest!.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(honest!.note,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
                fontSize: 13, height: 1.45,
                fontStyle: FontStyle.italic)),
          ],

          const SizedBox(height: 14),
          Container(height: 1, color: AppColors.divider),
          const SizedBox(height: 12),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: AppColors.signalGreen.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.signalGreen.withValues(alpha: 0.45),
                    width: 0.8),
                ),
                child: const Center(
                  child: Icon(Icons.straighten_rounded,
                    size: 15, color: AppColors.signalGreen),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('BONE STRUCTURE',
                      style: AppTypography.label.copyWith(
                        color: AppColors.textTertiary,
                        letterSpacing: 2.4, fontSize: 9,
                        fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(hasHonest
                        ? 'Geometry — what bones alone would score.'
                        : 'Vision pass unavailable — showing bones only.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11.5, height: 1.35)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('$geometry',
                style: AppTypography.measurement.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 30, height: 1,
                  letterSpacing: -1.2,
                  fontWeight: FontWeight.w800)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('/100',
                  style: AppTypography.label.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 9, letterSpacing: 1.4,
                    fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 520.ms).slideY(
      begin: 0.04, end: 0, curve: Curves.easeOutCubic, duration: 520.ms);
  }
}
