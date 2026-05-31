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
import '../../widgets/common/ai_consent_dialog.dart';
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
  // Populated once the scan image is persisted. Passed to chat/tryon so the
  // advisor can fire renders inline using the real scan image.
  String? _savedImagePath;
  // GPT-4o Vision honest-looks rating. Fires in parallel with /scan so
  // the added latency is absorbed. Null = model refused (rare) and the
  // dual-score hero degrades to geometry-only.
  HonestRating? _honest;
  // Hero render state. _generating flips true the moment the user taps
  // GENERATE on the hero card. _localUrl holds the maxed image URL once
  // /maximize lands (overrides the empty url on _analysis).
  bool _generating = false;
  String? _localUrl;

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
    // Defer the actual API kick-off by one frame so the in-app
    // AI consent dialog (5.1.2(i)) can render on top of /report
    // when the user first arrives. The scan flow already gates,
    // but /report is also reachable via paywall-success and any
    // future deep link, so we re-check here.
    WidgetsBinding.instance.addPostFrameCallback((_) => _gateAndRun());
  }

  Future<void> _gateAndRun() async {
    // App Store guideline 5.1.2(i) — never fire /analyse or /rate
    // (both ship the photo to OpenAI) until the user has tapped
    // ALLOW in AiConsentDialog. ensure() short-circuits to true
    // when the persisted flag is already set, so users who
    // accepted during scan don't see it again. If they decline
    // here, fall back to /home — the report cannot be produced
    // without the third-party AI calls.
    final consented = await AiConsentDialog.ensure(context);
    if (!mounted) return;
    if (!consented) {
      context.go('/home');
      return;
    }
    _run();
  }

  void _rotateCopy() {
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted || _analysis != null) return;
      setState(() => _copyIdx = (_copyIdx + 1) % _loadingCopy.length);
      _rotateCopy();
    });
  }

  /// Error message surfaced when analyse exhausts its retry budget.
  /// Null while we're still trying / when a previous successful run
  /// has populated [_analysis].
  String? _runError;

  Future<void> _run() async {
    if (mounted) setState(() => _runError = null);
    try {
      await _runInner();
    } catch (err) {
      // analyse/rate hit the retry cap. Surface the error so the
      // build method can render a clean retry state instead of
      // leaving the apprentice on the loading spinner indefinitely.
      if (mounted) setState(() => _runError = err.toString());
    }
  }

  Future<void> _runInner() async {
    // Fire /analyse and /rate in parallel. Both are GPT calls (~6–12s
    // analyse, ~3s rate), so running concurrently keeps the perceived
    // loading time flat at the slower of the two.
    //
    // We deliberately do NOT call /maximize here. The Replicate hero
    // render adds 60–90s on top of analyse, which buried the user
    // staring at a loading screen. Now the report renders the moment
    // GPT lands; the hero card carries an on-image GENERATE button
    // that fires /maximize on user tap (mirror-tab pattern). User can
    // start reading the analysis immediately and scroll back when
    // they want the maxed image.
    //
    // Failure handling: MirrorApiService.analyseOnly retries FOREVER
    // internally — only returns on success. Honest rating degrades to
    // null on model refusal.
    final imageB64 = base64Encode(widget.imageBytes);

    final analyseFuture = MirrorApiService.analyseOnly(
      imageBytes:  widget.imageBytes,
      geometry:    widget.geometry,
      extraImages: widget.extraImages,
    );
    final honestFuture  = HonestRatingService.rate(imageBase64: imageB64);

    final results = await Future.wait<dynamic>([analyseFuture, honestFuture]);
    final result  = results[0] as MirrorAnalysis;
    final honest  = results[1] as HonestRating?;

    if (!mounted) return;
    setState(() {
      _analysis = result;
      _honest   = honest;
    });
    // Persist the scan so it lights up Progress + Advisor tabs. The
    // maximizedImageUrl will be empty here; it gets filled in later
    // when the user taps GENERATE on the hero (see _generate()).
    await _persistScan(result);
  }

  /// Fire /maximize on user tap of the on-hero GENERATE button. Cheap
  /// guard against double-taps, optimistic UI: flip the spinner state
  /// up, await the URL, swap it in. Errors don't surface — maximizeOnly
  /// retries forever, so this only returns on success.
  Future<void> _generate() async {
    final a = _analysis;
    if (a == null || _generating) return;

    // 5.1.2(i) gate — /maximize ships the photo to Replicate.
    // Users reach this from a manual GENERATE tap on the hero
    // card, which can happen long after the original scan
    // consent (e.g. after they revoke from Settings).
    final consented = await AiConsentDialog.ensure(context);
    if (!mounted) return;
    if (!consented) return;

    setState(() => _generating = true);

    final improve = a.report.fixes
        .map((f) => f.visualRequest.isNotEmpty ? f.visualRequest : f.title)
        .toList();

    final url = await MirrorApiService.maximizeOnly(
      imageBytes: widget.imageBytes,
      improve:    improve,
    );
    if (!mounted) return;
    setState(() {
      _localUrl   = url;
      _generating = false;
    });

    // Backfill the persisted scan so the Progress tab gets the maxed
    // twin once the user actually generates it.
    final updated = a.copyWithMaximizedImageUrl(url);
    await _persistScan(updated);
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

    // Snapshot the AI-recommended fixes + their projected delta onto
    // the scan record so the Ascend POTENTIAL card can render the
    // headline + per-fix points without re-hitting /report later.
    final fixSummaries = a.report.fixes.map((f) => ScanFixSummary(
          title:    f.title,
          points:   f.points,
          timeline: f.timeline,
        )).toList();
    final projectedDelta = fixSummaries.fold<int>(
      0, (sum, f) => sum + f.points,
    );

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
      projectedDelta:     projectedDelta,
      fixHeadlines:       fixSummaries,
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
        child: _analysis != null
            ? _buildReport(_analysis!)
            : (_runError != null
                ? _buildError(_runError!)
                : _buildLoading()),
      ),
    );
  }

  /// Surfaced when /analyse + /rate both exhaust the retry cap. Gives
  /// the apprentice a way out of the spinner with a single tap to
  /// retry — no more "spinning for ages" trap.
  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.signalAmber, size: 32),
            const SizedBox(height: 14),
            Text('READ FAILED',
              style: AppTypography.label.copyWith(
                color: AppColors.signalAmber,
                letterSpacing: 2.8, fontSize: 11,
                fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('The analyser couldn\'t finish your scan. '
                 'Tap to try again — your photo is still here.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary, fontSize: 13, height: 1.45)),
            const SizedBox(height: 22),
            SizedBox(
              width: 220, height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: AppColors.base,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Rd.lg)),
                ),
                onPressed: _run,
                child: const Text('Try Again',
                  style: TextStyle(
                    fontWeight: FontWeight.w800, letterSpacing: 0.4)),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => context.go('/home'),
              child: Text('Back to Home',
                style: AppTypography.label.copyWith(
                  color: AppColors.textTertiary,
                  letterSpacing: 2.0, fontSize: 11,
                  fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    // No error screen, ever. MirrorApiService.scan and maximizeOnly
    // retry forever; they only return on success. If the user ever
    // navigates here without connectivity, they'll see the loading
    // state until connectivity returns — but they never see a
    // "Server hiccup" or "Try again" prompt.
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
  /// card. Each line covers a DIFFERENT feature category and a DIFFERENT
  /// rhetorical angle — so users never see "hunter eyes beat 88% of men"
  /// on line 1 and "ideal eye spacing — top 20%" on line 2. Three beats:
  ///
  ///   1 · FEATURE FLEX     — cultural name + measurement   ("Hunter eyes — +3.2° tilt")
  ///   2 · MEASUREMENT      — number + percentile            ("Symmetry 91/100 — top 8%")
  ///   3 · PERCENTILE FLEX  — rarity framing                 ("Dominant frame, rarer than 92% of men")
  ///
  /// Falls back to neutral but punchy lines when fewer than 3 unique
  /// categories surfaced (e.g. a dim scan with only one strength trait).
  List<String> _buildMicroProofs(List<Trait> traits) {
    // Pick one trait per feature category so the three bullets never
    // double up on the same feature (e.g. HUNTER EYES + IDEAL EYE SPACING
    // both collapsing to eyes).
    final byCategory = <String, Trait>{};
    for (final t in traits.where((t) => t.kind == TraitKind.strength)) {
      final cat = _categoryOf(t.name);
      byCategory.putIfAbsent(cat, () => t);
      if (byCategory.length == 3) break;
    }
    final picks = byCategory.values.toList();

    final lines = <String>[
      if (picks.isNotEmpty) _flexLine(picks[0]),
      if (picks.length >= 2) _measureLine(picks[1]),
      if (picks.length >= 3) _percentileLine(picks[2]),
    ];

    // Fallbacks — three distinct angles so the fallback trio doesn't
    // repeat itself either.
    const fallbacks = [
      'Measured profile — 16 geometry points',
      'Proportions on spec — balanced frame',
      'Structured archetype — bones rarer than most',
    ];
    while (lines.length < 3) {
      lines.add(fallbacks[lines.length]);
    }
    return lines;
  }

  /// Coarse feature-category key so we dedupe eyes vs symmetry vs frame.
  static String _categoryOf(String traitName) {
    final n = traitName.toUpperCase();
    if (n.contains('EYE')) return 'EYES';
    if (n.contains('SYMMETRY')) return 'SYMMETRY';
    if (n.contains('BROW')) return 'BROW';
    if (n.contains('LIP')) return 'LIPS';
    if (n.contains('FRAME') || n.contains('DOMINANT')) return 'FRAME';
    if (n.contains('THIRD') || n.contains('PROPORTION') || n.contains('GOLDEN')) {
      return 'PROPORTIONS';
    }
    if (n.contains('JAW') || n.contains('CHIN')) return 'JAW';
    return n;
  }

  /// Bullet 1 — name the feature, cite the measurement. Shareable on its
  /// own. Pulls from the trait's pre-composed `detail` (e.g. "+3.1° TILT").
  static String _flexLine(Trait t) {
    final name = _culturalName(t.name);
    final detail = t.detail.trim();
    return detail.isEmpty ? name : '$name — $detail';
  }

  /// Bullet 2 — lead with the feature and its measurement, add a
  /// percentile label as a secondary flex. Different rhythm from bullet 1
  /// so it doesn't read as a repeat.
  static String _measureLine(Trait t) {
    final name = _culturalName(t.name);
    final detail = t.detail.trim();
    final pct = t.pct.trim();
    if (detail.isEmpty && pct.isEmpty) return name;
    if (detail.isEmpty) return '$name — $pct';
    if (pct.isEmpty) return '$name at $detail';
    return '$name $detail — $pct';
  }

  /// Bullet 3 — the punchy percentile flex. "TOP 3%" lands harder
  /// than "rarer than 97% of men" — shorter, screenshot-ready, and
  /// the cultural-norm way looksmax content frames rarity. Skips the
  /// measurement detail so the shape contrasts with bullets 1 & 2.
  static String _percentileLine(Trait t) {
    final name = _culturalName(t.name);
    final pct = t.pct.trim();
    return pct.isEmpty ? name : '$name — $pct';
  }

  /// Map the trait's grid-label ("HUNTER EYES", "RARE SYMMETRY") to the
  /// short cultural phrase the bullets render with.
  static String _culturalName(String raw) {
    final n = raw.toUpperCase();
    if (n.contains('HUNTER')) return 'Hunter eyes';
    if (n.contains('SYMMETRY')) return 'Symmetry';
    if (n.contains('MODEL LIPS') || n == 'LIPS') return 'Model lips';
    if (n.contains('DOMINANT FRAME')) return 'Dominant frame';
    if (n.contains('GOLDEN THIRDS')) return 'Golden thirds';
    if (n.contains('DOMINANT BROW')) return 'Dominant brow';
    if (n.contains('IDEAL EYE SPACING')) return 'Eye spacing';
    // Default: title-case the raw trait name.
    return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
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
    //   1. The honest-rating viral killer line (_honest.note) — built to
    //      the 3-beat template "<feature> — <metric>. <verdict>."
    //   2. The top strength trait's pre-composed heroLine — already
    //      punchy, already anchored to a real geometry metric. Better
    //      fallback than the longer GPT prose verdict when /rate refused.
    //   3. GPT analyse `oneLineVerdict` — longer, measurement-cited.
    //   4. Strongest-axis fallback so it never defaults blank.
    final honestNote = (_honest?.note ?? '').trim();
    final topStrengthLine = traits
        .where((t) => t.kind == TraitKind.strength)
        .map((t) => t.heroLine.trim())
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    final tagline = honestNote.isNotEmpty
        ? honestNote
        : (topStrengthLine.isNotEmpty
            ? topStrengthLine
            : (a.report.oneLineVerdict.trim().isNotEmpty
                ? a.report.oneLineVerdict
                : '${score.strongestAxis.$1} carries the frame.'));

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
                  // Keep one score-flex line so the share card has a
                  // proof number. The other two come straight from the
                  // on-screen micro-proofs so what gets shared matches
                  // what the user saw — no two different bullet sets,
                  // no bullets that all key on the same feature.
                  microProofs: [
                    if (_honest != null)
                      'HONEST LOOKS · ${_honest!.score}/100'
                    else
                      'BONES · ${score.value}/100',
                    if (microProofs.isNotEmpty) microProofs[0],
                    if (microProofs.length >= 2) microProofs[1],
                  ],
                  text: '${_honest?.score ?? score.value} → $projected. '
                        'Same face. mirrorly.app',
                ),
              ),
            ],
          ),

          const SizedBox(height: Sp.lg),

          // ── 0 · HERO CARD ─ before/after first. User direction:
          //    "it start with before after etc then goes down to the
          //    rest". Visual hook leads, scores follow.
          HeroCard(
            currentScore:     _honest?.score ?? score.value,
            projectedScore:   projected,
            tagline:          tagline,
            beforeBytes:      widget.imageBytes,
            afterUrl:         _localUrl ?? (a.maximizedImageUrl.isNotEmpty
                                ? a.maximizedImageUrl
                                : null),
            correctionsCount: correctionsCount,
            microProofs:      microProofs,
            onGenerate:       _generate,
            isGenerating:     _generating,
          ),

          const SizedBox(height: Sp.md),

          // ── 1 · DUAL-SCORE ─ honest (big) + bone structure (under).
          //    Two scores is the moat. Honest is GPT-4o Vision's real-
          //    photo read — skin, eye area, proportions — with no
          //    geometry context so bones can't bail out a bad face.
          //    Bone structure is our on-device math, shown smaller as
          //    the companion number. Degrades to geometry-only if the
          //    vision pass refused.
          _DualScoreHero(
            honest:    _honest,
            geometry:  score.value,
          ),

          const SizedBox(height: Sp.md),

          // ── 2 · TRAITS GRID — REMOVED per user feedback
          //    The Umax-style state-labelled badges (DOMINANT BROW /
          //    LONG LOWER / TIGHTEN UP / ASYMMETRICAL / SOLID FRAMING /
          //    HUNTER EYES) read as clinical labels instead of
          //    actionable steps. User: "no names other than mogged."
          //    Fix cards below carry the real signal now.
          // TraitGrid(traits: traits)
          //   .animate().fadeIn(delay: 1600.ms, duration: 500.ms),

          // ── 3 · RADAR CHART — REMOVED per user feedback
          //    The full hexagon radar takes a screenful and adds no
          //    actionable info. User: "we much is closer to the
          //    bottom" — saved for a smaller version we'll bring back
          //    inside the geometry collapsed panel later.
          // RadarChart(
          //   values: radarValues,
          //   labels: const ['EYES', 'JAW', 'SYMMETRY', 'LIPS', 'FWHR', 'BALANCE'],
          // ).animate().fadeIn(delay: 1900.ms, duration: 500.ms),

          const SizedBox(height: Sp.xl),

          // GENERATE moved onto the hero card itself (see HeroCard's
          // _afterHalf — when no maxed URL is present the right side
          // renders a big red GENERATE button that fires _generate()).
          // No standalone CTA above the fix cards any more.

          // ── 4 · FIX HEADLINES (text only — no per-fix Flux render) ─────
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
            _FixTextCard(
              index: e.key + 1,
              fix: e.value,
              geometry: widget.geometry,
              pulldown: a.report.pulldown,
            ).animate().fadeIn(delay: Duration(milliseconds: 2600 + e.key * 120))),

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

          // The standalone "Mog Stance" protocol card + duplicate verdict
          // that used to live here were stacking on top of the deeper-
          // analysis blocks visually — the report was reading as a pile
          // of red-bordered cards. The per-fix "ADD TO STREAK" buttons
          // above already commit a fix to the user's daily streak, so
          // the dedicated protocol card is redundant. Done/Consult sits
          // immediately after the deeper analysis now.
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
class _FixTextCard extends StatefulWidget {
  final int index;
  final Fix fix;
  final FaceGeometry geometry;
  final String pulldown;
  const _FixTextCard({
    required this.index,
    required this.fix,
    required this.geometry,
    required this.pulldown,
  });

  @override
  State<_FixTextCard> createState() => _FixTextCardState();
}

class _FixTextCardState extends State<_FixTextCard> {
  bool _committed = false;
  bool _busy = false;

  Future<void> _onCommit() async {
    if (_busy || _committed) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    final p = await ProtocolService.commitFix(
      fix:      widget.fix,
      geometry: widget.geometry,
      pulldown: widget.pulldown,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _committed = p != null;
    });
    if (p != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${widget.fix.title}" added to your streak',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textPrimary, fontSize: 13)),
          backgroundColor: AppColors.surface2,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1800),
          action: SnackBarAction(
            label: 'OPEN',
            textColor: AppColors.red,
            onPressed: () => context.push('/protocol'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.index;
    final fix   = widget.fix;
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.md),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.lg),
        // Red accent — user explicitly said NOT the blue cards. Brand
        // red carries the "this is what makes you look better" tone.
        border: Border.all(color: AppColors.red.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$index',
                style: AppTypography.h1.copyWith(
                  color: AppColors.red, fontSize: 30, letterSpacing: -1)),
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
            color: AppColors.red, fontSize: 9, letterSpacing: 1.8)),
          const SizedBox(height: 4),
          Text(fix.action, style: AppTypography.body.copyWith(
            color: AppColors.textPrimary, fontSize: 14, height: 1.55)),
          const SizedBox(height: Sp.md),
          // ── Projected point gain + COMMIT row.
          //    Backend (analyse.js) now returns a `points` integer per
          //    fix — projected delta to the user's overall LOOKS score
          //    from doing this fix. Older reports without the field
          //    default to 0, so the gauge stays hidden until the
          //    backend has shipped the prompt bump.
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (fix.points > 0) ...[
                Container(
                  width: 76,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.red.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(Rd.lg),
                    border: Border.all(
                        color: AppColors.red.withValues(alpha: 0.55),
                        width: 1),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '+${fix.points}',
                        style: AppTypography.h1.copyWith(
                          color: AppColors.red,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.0,
                        ),
                      ),
                      Text(
                        'POINTS',
                        style: AppTypography.label.copyWith(
                          color: AppColors.red,
                          fontSize: 8.5,
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: InkWell(
                  onTap: _committed
                      ? () => context.push('/protocol')
                      : _onCommit,
                  borderRadius: BorderRadius.circular(Rd.lg),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _committed
                          ? AppColors.signalGreen.withValues(alpha: 0.18)
                          : AppColors.red,
                      borderRadius: BorderRadius.circular(Rd.lg),
                      border: _committed
                          ? Border.all(
                              color: AppColors.signalGreen, width: 1)
                          : null,
                      boxShadow: _committed
                          ? null
                          : [BoxShadow(
                              color: AppColors.red.withValues(alpha: 0.32),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            )],
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 18, width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _committed
                                    ? Icons.check_rounded
                                    : Icons.local_fire_department,
                                color: _committed
                                    ? AppColors.signalGreen
                                    : Colors.black,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _committed
                                    ? 'IN YOUR STREAK'
                                    : 'ADD TO STREAK',
                                style: AppTypography.label.copyWith(
                                  color: _committed
                                      ? AppColors.signalGreen
                                      : Colors.black,
                                  fontSize: 12,
                                  letterSpacing: 2.2,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Chip(label: fix.timeline, color: AppColors.textTertiary),
              const SizedBox(width: 8),
              _Chip(label: 'RESCAN DAY ${fix.rescanDay}', color: AppColors.textTertiary),
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
