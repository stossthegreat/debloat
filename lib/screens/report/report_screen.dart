import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/face_geometry.dart';
import '../../models/mirror_analysis.dart';
import '../../models/scan_record.dart';
import '../../models/protocol.dart';
import '../../services/archetype_service.dart';
import '../../services/analytics_service.dart';
import '../../services/daily_nudge_service.dart';
import '../../services/face_asset_service.dart';
import '../../services/feature_analysis_service.dart';
import '../../services/honest_rating_service.dart';
import '../../services/local_store_service.dart';
import '../../services/mirror_api_service.dart';
import '../../services/paywall_gate.dart';
import '../../services/protocol_service.dart';
import '../../services/scoring_service.dart';
import '../../services/trait_builder_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../services/review_prompt_service.dart';
import '../../services/share_service.dart';
import '../../widgets/common/fullscreen_image.dart';
import '../../widgets/report/ai_verdict_panel.dart';
import '../../widgets/report/aspect_protocol_cards.dart';
import '../../widgets/report/hero_card.dart';
import '../../widgets/report/hidden_depth_panel.dart';
import '../../widgets/report/per_trait_scores.dart';
import '../../widgets/report/trait_grid.dart';

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
  // Bro v6 conversion flow: non-pro users see a TEASER variant of the
  // report — score reveal + blurred glow-up + locked panels + paywall
  // CTAs. Resolved once on mount; the live RevenueCat read keeps it
  // honest against TestFlight / sandbox lag.
  bool _isPro = false;
  bool _proResolved = false;

  // ─── HeroCard GENERATE button wiring ──────────────────────────────────
  //
  // The HeroCard owns the on-image GENERATE button (right half of the
  // before/after split, fires when no afterUrl is present yet). The
  // parent — that\'s us — is responsible for actually calling /maximize
  // when the button is tapped and feeding the resulting url back in. In
  // the redesign I forgot to pass onGenerate + isGenerating, which made
  // the GENERATE button a dead pixel. _localMaximizedUrl holds a
  // url-from-retry so a successful tap surfaces the maxed image even if
  // the original /scan returned empty.
  bool   _generatingHero = false;
  String _localMaximizedUrl = '';

  // Loading copy honest to what's actually running. Bro: "the nano
  // banana after image is still getting in the way — why you making
  // us wait twice." We DO NOT call /maximize on this screen anymore
  // (the hero render is on-demand via the GENERATE button), so the
  // copy no longer mentions "maximized composite" — that string was
  // tricking users into thinking they were waiting for the Replicate
  // job that never fires here.
  static const _loadingCopy = [
    'Reading skin micro-texture',
    'Comparing structural archetypes',
    'Locking identity anchors',
    'Compiling the honest read',
  ];
  int  _copyIdx       = 0;
  bool _slowResponse  = false; // flips true after 30s — shows
                               // the "taking longer than usual"
                               // band so the user knows the screen
                               // isn\'t frozen.

  @override
  void initState() {
    super.initState();
    _rotateCopy();
    _watchForSlowResponse();
    _resolvePro();
    _run();
  }

  Future<void> _resolvePro() async {
    final pro = await PaywallGate.isPro();
    if (!mounted) return;
    setState(() {
      _isPro = pro;
      _proResolved = true;
    });
  }

  void _rotateCopy() {
    // 1.4s rotation feels quicker / more elite than the old 2s. Long
    // enough to read, fast enough to feel like real progress.
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted || _analysis != null) return;
      setState(() => _copyIdx = (_copyIdx + 1) % _loadingCopy.length);
      _rotateCopy();
    });
  }

  /// After 30s of waiting, surface a "slow response" band so the user
  /// knows the screen isn't frozen. Bro: "no reason why it should ever
  /// take more than 20-30 seconds" — 30s here matches that ceiling.
  void _watchForSlowResponse() {
    // Bro v6: "should be quicker and elite loading and it should say
    // still working even after 20-30 seconds." 20s feels alive vs the
    // old 30s — by 20s the user is already wondering if it's frozen.
    Future.delayed(const Duration(seconds: 20), () {
      if (!mounted || _analysis != null || _error != null) return;
      setState(() => _slowResponse = true);
    });
  }

  Future<void> _run() async {
    // Bro: "the ai is still taking ages sometimes — no reason it
    // should ever take more than 20-30 seconds, never hiccup. The
    // nano banana after image is getting in the way — why you making
    // us wait TWICE."
    //
    // Old flow blocked on Future.wait([analyseOnly, rate]) — meaning
    // a slow /rate call could pin the report at the loading screen
    // for up to 60s, twice over a slow connection. New flow:
    //   · analyseOnly  → AWAITED. The moment it lands the report
    //                    paints. Typical 6-12s.
    //   · honest /rate → BACKGROUND. Fired in parallel, lands a few
    //                    seconds later via setState; the dual-score
    //                    hero degrades to bones-only until it does.
    //   · /maximize    → never called on this screen. The hero
    //                    render is on-demand via the GENERATE button.
    //
    // Result: user sees the report ~6-12s after the camera capture,
    // never blocked behind the Replicate render they didn't ask for.
    try {
      final imageB64 = base64Encode(widget.imageBytes);

      // Fire honest rating as background — never awaited here.
      // ignore: discarded_futures
      HonestRatingService.rate(imageBase64: imageB64).then((honest) {
        if (!mounted || honest == null) return;
        setState(() => _honest = honest);
      });

      final result = await MirrorApiService.analyseOnly(
        imageBytes:  widget.imageBytes,
        geometry:    widget.geometry,
        extraImages: widget.extraImages,
      );

      if (mounted) {
        setState(() {
          _analysis = result;
        });
        // ignore: discarded_futures
        AnalyticsService.reportViewed(_isPro ? 'full' : 'locked');
      }
      // Persist the scan so it lights up Progress + Advisor tabs.
      await _persistScan(result);
      // Mark the looksmax milestone for the App Store review prompt.
      // v249 — gate loosened: ANY one milestone now fires the prompt
      // (was: requires all three pillars). Trigger directly here on
      // the report screen — the first scan reveal is the strongest
      // aha moment we have, and bro shipped the loose gate so this
      // is allowed to fire.
      await ReviewPromptService.markScanDone();
      if (mounted) {
        // ignore: discarded_futures
        ReviewPromptService.maybePromptAfterReport(context);
      }
      // Reschedule the daily nudge — after a fresh scan the state
      // moves from NO_SCAN to POST_SCAN_NO_GAME (or stays in an
      // active streak), so today's 7:30pm copy needs to update.
      // ignore: discarded_futures
      DailyNudgeService.reschedule();
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

    // Snapshot the AI-recommended fixes onto the scan record so the
    // Ascend POTENTIAL card can render the headline + per-fix points
    // without re-hitting /report later.
    final fixSummaries = a.report.fixes.map((f) => ScanFixSummary(
          title:    f.title,
          points:   f.points,
          timeline: f.timeline,
        )).toList();
    // Bro v222 → v224 follow-up: the Looks-tab _HopeCard needs to read
    // EXACTLY the same NOW → POTENTIAL the user just saw on the
    // HeroCard. The HeroCard does:
    //     currentScore   = _honest?.score ?? geometry           (52)
    //     projectedScore = geometry + _potentialDelta(geometry) (86)
    // So we persist the SAME pair onto the ScanRecord — store the
    // honest score (preferred) as scan.score, and store the visible
    // delta (projected - headlineCurrent) as projectedDelta. The home
    // _HopeCard's `current + projectedDelta` then lands on the same
    // PROJECTED the report just headlined. No middle ground.
    final headlineCurrent  = _honest?.score ?? score.value;
    final formulaProjected = (score.value + _potentialDelta(score.value))
        .clamp(0, 100);
    final projectedDelta   = (formulaProjected - headlineCurrent)
        .clamp(0, 100);

    final record = ScanRecord(
      id:                 id,
      takenAt:            DateTime.now(),
      geometry:           widget.geometry,
      // Persist the headline number (honest, falls back to geometry)
      // so every downstream surface — Looks tab _HopeCard, Ascend
      // POTENTIAL, Progress charts — reads the SAME score the user
      // just saw on the HeroCard.
      score:              headlineCurrent,
      tierLabel:          score.tierLabel,
      archetypeName:      match.archetype.name,
      archetypeMatchPct:  (match.match * 100).round(),
      capturedImagePath:  savedPath,
      maximizedImageUrl:  a.maximizedImageUrl,
      projectedDelta:     projectedDelta,
      fixHeadlines:       fixSummaries,
    );
    await LocalStoreService.saveScan(record);

    // Write the LOOKS pillar score so the home Ascend tab updates the
    // moment this scan persists. We prefer the GPT vision (HONEST
    // LOOKS) score since that\'s the headline number the user just
    // saw on the report — falling back to the geometry score when
    // vision refused. Bro: the home pillar must reflect the latest
    // attempt, not stay stuck on a stale value. Best is kept in
    // looks_score_best for any future progress chart that needs it.
    try {
      final prefs = await SharedPreferences.getInstance();
      final headline = _honest?.score ?? score.value;
      await prefs.setInt('looks_score', headline);
      final prev = prefs.getInt('looks_score_best') ?? 0;
      if (headline > prev) await prefs.setInt('looks_score_best', headline);
    } catch (_) {}

    // Stamp today as the LOOKS completion day so the Ascend tab\'s
    // Today\'s Ascension card ticks LOOKS off the moment a fresh
    // scan persists. Pure side-effect — no layout change.
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setInt(
        'looks_done_ymd',
        now.year * 10000 + now.month * 100 + now.day,
      );
    } catch (_) {}

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
            : (_proResolved && !_isPro
                ? _buildLockedTeaser(_analysis!)
                : _buildReport(_analysis!)),
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

    // Loading state. Bro: "the way it loads people don\'t actually
    // know if it\'s really loading." Bigger spinner, step counter
    // ("3 of 5"), an honest "this can take up to a minute" line so
    // the user knows we\'re working not stuck, and the actual step
    // text rotates every 2s as before.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 60, height: 60,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColors.accent,
              backgroundColor: AppColors.surface2,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'STEP ${_copyIdx + 1} OF ${_loadingCopy.length}',
            style: AppTypography.label.copyWith(
              color: AppColors.accent,
              letterSpacing: 3.0, fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(_loadingCopy[_copyIdx].toUpperCase(),
              key: ValueKey(_copyIdx),
              textAlign: TextAlign.center,
              style: AppTypography.label.copyWith(
                color: AppColors.textPrimary,
                letterSpacing: 2.2,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              )),
          ),
          const SizedBox(height: 12),
          Text(
            'Reading your face — mesh, geometry, archetype, skin '
            'texture. The honest read usually lands in 10-20 seconds.',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(
              fontSize: 12,
              height: 1.45,
              color: AppColors.textTertiary,
            ),
          ),
          // Slow-response notice — after 60s, surface a small amber
          // band that just says "this is taking longer than usual,
          // keep waiting." No retry button (bro: "don\'t put retry
          // on the scan rendering loading screen, just tell them
          // to keep waiting"). Letting users hammer retry on a slow
          // backend only piles up more work for the same queue.
          if (_slowResponse) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.signalAmber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.signalAmber.withValues(alpha: 0.45),
                  width: 0.8),
              ),
              child: Column(
                children: [
                  Text('STILL WORKING',
                    style: AppTypography.label.copyWith(
                      color: AppColors.signalAmber,
                      letterSpacing: 3.2, fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    )),
                  const SizedBox(height: 6),
                  Text(
                    'The honest read is heavy — bones, skin, eyes, '
                    'archetype. Almost there.',
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(
                      fontSize: 11.5,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
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

  /// Called when the user taps the GENERATE button on the HeroCard\'s
  /// after side. Fires /maximize against the scan\'s improve list and
  /// drops the resulting url into [_localMaximizedUrl] so HeroCard
  /// stops showing the placeholder. Already-have-url path is a no-op
  /// (HeroCard automatically renders the image).
  Future<void> _generateHero(MirrorAnalysis a) async {
    if (_generatingHero) return;
    final existing = _localMaximizedUrl.isNotEmpty
        ? _localMaximizedUrl
        : a.maximizedImageUrl;
    if (existing.isNotEmpty) return; // image already on screen
    // Bro v4: Mirror renders are PRO-ONLY. Free users have no render
    // allowance — every attempt hits the paywall. Pro users get the
    // 10/month quota.
    final pro = await PaywallGate.isPro();
    if (!pro) {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      context.push('/paywall', extra: {'source': 'render_locked'});
      return;
    }
    final used = await LocalStoreService.mirrorRendersThisWeek();
    if (used >= LocalStoreService.kRendersPerWeek) {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      context.push('/paywall', extra: {'source': 'render_quota_capped'});
      return;
    }
    HapticFeedback.heavyImpact();
    setState(() => _generatingHero = true);
    try {
      final url = await MirrorApiService.maximizeOnly(
        imageBytes: widget.imageBytes,
        improve:    a.report.fixes
          .map((f) => f.visualRequest.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      );
      if (!mounted) return;
      setState(() {
        _localMaximizedUrl = url;
        _generatingHero    = false;
      });
      // Pro user just used one of their rolling-weekly renders.
      await LocalStoreService.markMirrorRenderUsed();
    } catch (_) {
      if (!mounted) return;
      setState(() => _generatingHero = false);
    }
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

    // ArchetypeService.bestMatch + the 6-axis radar values block were
    // removed from this builder along with the report screen redesign
    // — they only fed into the old confusing middle "mash"
    // (RadarChart, ArchetypeCard, HiddenDepthPanel, FeatureGrid
    // duplicate, VerdictCard and GPT prose blocks). The new layout
    // surfaces analytical, comparative and prescriptive content via
    // PerTraitScores, TraitGrid and AspectProtocolCards respectively,
    // none of which need those locals.

    // Bro v2: "you made the wrong card bigger — revert the top one, the
    // NEW ones (AI Verdict) make them wider." So the outer ScrollView
    // gets its Sp.lg side padding back; every section reads at normal
    // inset EXCEPT the AI Verdict panel which breaks out wider by using
    // a negative-margin Transform so its four tiles bleed closer to the
    // screen edge than everything else.
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
                  // Use the local maxed URL when the user has hit
                  // GENERATE since the /scan. Falls back to the
                  // original /scan url when present. Bro: "after
                  // they\'ve generated their maxed image the image
                  // is still not in the share card. That\'s our
                  // main thing."
                  afterUrl:       _localMaximizedUrl.isNotEmpty
                                      ? _localMaximizedUrl
                                      : a.maximizedImageUrl,
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
                        'Same face. imhim.app',
                ),
              ),
            ],
          ),

          const SizedBox(height: Sp.lg),

          // ── 0 · DUAL-SCORE HERO — normal inset.
          _DualScoreHero(
            honest:    _honest,
            geometry:  score.value,
          ),

          const SizedBox(height: Sp.md),

          // ── 1 · HERO CARD — normal inset.
          HeroCard(
            currentScore:     _honest?.score ?? score.value,
            projectedScore:   projected,
            tagline:          tagline,
            beforeBytes:      widget.imageBytes,
            afterUrl:         _localMaximizedUrl.isNotEmpty
                                  ? _localMaximizedUrl
                                  : a.maximizedImageUrl,
            correctionsCount: correctionsCount,
            microProofs:      microProofs,
            isGenerating:     _generatingHero,
            onGenerate:       () => _generateHero(a),
          ),

          const SizedBox(height: Sp.lg),

          // ── 2 · AI VERDICT — same inset as the per-trait card below.
          // v216a: the previous Transform.translate(-Sp.lg) + SizedBox
          // (width: screen) trick left-bled the panel without widening
          // it (SizedBox can't override the parent's tighter constraint),
          // so the four tiles rendered flush-left with an Sp.lg×2 dead
          // strip on the right. Drop the wrapper so the verdict panel
          // sits at the same Sp.lg gutter as PerTraitScores beneath it.
          if (_honest?.verdict != null) ...[
            AiVerdictPanel(
              verdict: _honest!.verdict!,
              extraStrengths: _buildExtraStrengths(),
            ).animate().fadeIn(delay: 1450.ms, duration: 500.ms),
            const SizedBox(height: Sp.lg),
          ],

          // ── 3 · PER-TRAIT SCORES — normal inset.
          PerTraitScores(
            honest:   _honest,
            geometry: widget.geometry,
          ).animate().fadeIn(delay: 1500.ms, duration: 500.ms),

          const SizedBox(height: Sp.md),

          // ── 4 · GEOMETRY BREAKDOWN — normal inset.
          TraitGrid(traits: traits)
            .animate().fadeIn(delay: 1700.ms, duration: 500.ms),

          const SizedBox(height: Sp.md),

          HiddenDepthPanel(geometry: widget.geometry)
            .animate().fadeIn(delay: 1850.ms, duration: 500.ms),

          const SizedBox(height: Sp.xl),

          // ── 5 · 60-DAY ASPECT PROTOCOLS — normal inset.
          AspectProtocolCards(
            geometry:       widget.geometry,
            savedImagePath: _savedImagePath,
          ).animate().fadeIn(delay: 2100.ms, duration: 400.ms),

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

  /// Build a list of additional strength tiles to render under the
  /// "Biggest Strength" card. Bro: "only gives one example of what's
  /// good — give them a little more." Pulls the top-scoring sub-axes
  /// from the GPT vision rating (skin, hair, jawline, eyes, etc.) and
  /// surfaces the 2 highest above the biggest-strength axis, each with
  /// the qualifier word from subTiers as the headline.
  List<({String eyebrow, String headline, String body})> _buildExtraStrengths() {
    final subScores = _honest?.subScores;
    final subTiers  = _honest?.subTiers;
    if (subScores == null || subScores.isEmpty) return const [];

    final ranked = subScores.entries
        .where((e) => e.value >= 60) // only flex genuine strengths
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Skip the top one — it's already in biggestStrength. Take next 2.
    final extras = ranked.skip(1).take(2);

    String labelFor(String key) => switch (key.toLowerCase()) {
      'skin'        => 'YOUR SKIN HOLDS UP',
      'hair'        => 'YOUR HAIR LANDS',
      'jawline'     => 'YOUR JAW READS',
      'masculinity' => 'YOUR DIMORPHISM HITS',
      'eyes'        => 'YOUR EYES CARRY',
      'face'        => 'YOUR FACE STRUCTURE WORKS',
      _             => 'STRENGTH · ${key.toUpperCase()}',
    };

    String bodyFor(String key, int score) {
      final tier = (subTiers?[key] ?? '').trim();
      if (tier.isNotEmpty) return '$tier — scoring $score/100 on vision.';
      return 'Scoring $score/100 on the vision pass — above average.';
    }

    return extras.map((e) => (
      eyebrow:  labelFor(e.key),
      headline: (subTiers?[e.key] ?? '').trim().isNotEmpty
          ? (subTiers![e.key] ?? '')
          : '${e.value}/100',
      body:     bodyFor(e.key, e.value),
    )).toList();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  LOCKED TEASER — what non-pro users see after their first scan.
  //  Bro v6: "user comes through onboarding boom it scans face first,
  //  then current score / potential / their photo / blurred glow-up /
  //  UNLOCK PRO TO SEE YOU MAXED / blurred sections below. Touch the
  //  after photo → paywall. Touch anything blurred → paywall. Clear
  //  paywall buttons in a few places."
  //
  //  Reuses the same DualScoreHero numbers + the user's MediaPipe
  //  capture, BUT every "what next" surface is locked behind the
  //  glow-up paywall variant (source: 'glowup_locked'). The "after"
  //  image is the existing maximized-twin slot painted blurred + with
  //  a centered LOCK pill — no Replicate call fires for free users
  //  (they never get past the gate to consume credits).
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildLockedTeaser(MirrorAnalysis a) {
    final score      = ScoringService.compute(widget.geometry);
    final current    = _honest?.score ?? score.value;
    final potential  = _potentialDelta(current);
    final projected  = (current + potential).clamp(0, 100);
    // Same tagline + proof recipe the unlocked report uses, so the
    // locked variant of HeroCard reads identically except for the
    // after half.
    final traits     = TraitBuilderService.build(widget.geometry);
    final microProofs = _buildMicroProofs(traits);
    final honestNote = (_honest?.note ?? '').trim();
    final tagline = honestNote.isNotEmpty
        ? honestNote
        : (a.report.oneLineVerdict.trim().isNotEmpty
            ? a.report.oneLineVerdict
            : '${score.strongestAxis.$1} carries the frame.');
    final correctionsCount = a.report.fixes.isNotEmpty
        ? a.report.fixes.length
        : 3;

    Future<void> openPaywall(String src) async {
      HapticFeedback.mediumImpact();
      // Split the funnel: "_locked" tile taps (per-section curiosity)
      // vs. the main unlock CTAs ("glowup_unlock_main" / "glowup_after_tap").
      // Both surfaces eventually fire paywall_shown via paywall_screen,
      // but distinguishing the SOURCE of intent lets us measure which
      // teaser surface is doing the real conversion work.
      if (src.endsWith('_locked')) {
        // Strip the prefix + suffix so the param reads as a clean
        // section tag (verdict / pertrait / geometry / protocols).
        final section = src
            .replaceFirst('glowup_', '')
            .replaceFirst('_locked', '');
        // ignore: discarded_futures
        AnalyticsService.reportLockedSectionTapped(section);
      } else {
        // ignore: discarded_futures
        AnalyticsService.reportUnlockTapped(src);
      }
      // Unlock-in-place: on a successful purchase the paywall pops back
      // to THIS still-mounted report instead of routing to /home, and we
      // re-resolve Pro below so the locked teaser rebuilds as the full
      // unlocked report — results + glow-up render — using the analysis
      // we already loaded. No re-scan, no second backend call.
      await context.push('/paywall', extra: {
        'source':        src,
        'unlockInPlace': true,
      });
      if (mounted) await _resolvePro();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Same header as the unlocked report — title block only, no
          // share button (nothing to share until they unlock).
          Text('YOUR ANALYSIS',
            style: AppTypography.label.copyWith(
              color: AppColors.textTertiary, letterSpacing: 2.5))
            .animate().fadeIn(duration: 400.ms),
          const SizedBox(height: Sp.xs),
          Text('Down to the millimetre.',
            style: AppTypography.h1.copyWith(fontSize: 28))
            .animate().fadeIn(delay: 100.ms, duration: 400.ms),
          const SizedBox(height: Sp.lg),

          // Same dual-score hero the unlocked report ships — but with the
          // secondary geometry score withheld behind a green "?".
          _DualScoreHero(honest: _honest, geometry: score.value, locked: true),
          const SizedBox(height: Sp.md),

          // Same HeroCard — only difference is locked=true on the
          // after half (blurred copy of user's own NOW + LOCK pill +
          // tap routes to paywall). Projected number renders green
          // here too because that change went in at the HeroCard
          // level — both locked and unlocked benefit.
          HeroCard(
            currentScore:     current,
            projectedScore:   projected,
            tagline:          tagline,
            beforeBytes:      widget.imageBytes,
            afterUrl:         '', // empty so the locked overlay paints
            correctionsCount: correctionsCount,
            microProofs:      microProofs,
            locked:           true,
            // v263 — onboarding scan reveal blanks the potential
            // number with "?". Current score visible (proves the
            // app analyzed the face); projected number hidden
            // (proves there's a payoff worth unlocking for).
            // Curiosity gap drives conversion.
            hideProjected:    true,
            onLockedTap:      () => openPaywall('glowup_after_tap'),
          ),
          const SizedBox(height: Sp.md),

          // ONE big CTA under the before/after. Bro v6: "just have one
          // under the before after and one on the after" — that's the
          // tap-on-after-image + this single button. Nothing else.
          // v263 — CTA copy no longer reveals +X POINTS. The "?" on
          // the projected score IS the unlock — surfacing the
          // delta defeats the curiosity gap.
          _UnlockCta(
            label: 'UNLOCK TO SEE YOUR POTENTIAL',
            onTap: () => openPaywall('glowup_unlock_main'),
          ),
          const SizedBox(height: Sp.xl),

          // Blanked-out section cards — same vertical hierarchy as the
          // unlocked report (AI Verdict → Per-Trait → Geometry →
          // 60-day Protocols), titles only, content area is a flat
          // black box. Each tile is tappable to paywall but is NOT a
          // button — only the one above is.
          _LockedSection(
            eyebrow: 'AI VERDICT',
            line:    'honest read · on photo',
            height:  150,
            onTap:   () => openPaywall('glowup_verdict_locked'),
          ),
          const SizedBox(height: Sp.md),
          _LockedSection(
            eyebrow: 'PER-TRAIT SCORES',
            line:    'skin · hair · jaw · eyes · face',
            height:  140,
            onTap:   () => openPaywall('glowup_pertrait_locked'),
          ),
          const SizedBox(height: Sp.md),
          _LockedSection(
            eyebrow: 'GEOMETRY',
            line:    '16 measurements · on-device math',
            height:  140,
            onTap:   () => openPaywall('glowup_geometry_locked'),
          ),
          const SizedBox(height: Sp.md),
          _LockedSection(
            eyebrow: '60-DAY PROTOCOLS',
            line:    'skin · jaw · debloat · hair',
            height:  140,
            onTap:   () => openPaywall('glowup_protocols_locked'),
          ),
          const SizedBox(height: Sp.xl),

          // Bro v8: "make the done button at the bottom a little
          // bigger you can barely see it" + "user presses done →
          // routes to roleplay so they land on the main Free Flow
          // screen with the big CTA." Discreet text-only button
          // upgraded to a pill with enough presence to be a true
          // exit, still subordinate to the UNLOCK CTA above
          // (outlined accent, not filled red). Routes /home tab 1
          // = GAME, dropping the user straight into the Lucien
          // free-roleplay surface.
          Center(
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(99),
              child: InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: () {
                  HapticFeedback.selectionClick();
                  // ignore: discarded_futures
                  AnalyticsService.reportDoneTapped();
                  context.go('/home', extra: {'initialTab': 1});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface1,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: AppColors.textSecondary.withValues(alpha: 0.55),
                      width: 1.0),
                  ),
                  child: Text('DONE',
                    style: AppTypography.label.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 13, letterSpacing: 3.4,
                      fontWeight: FontWeight.w900,
                    )),
                ),
              ),
            ),
          ),
          const SizedBox(height: Sp.md),
        ],
      ),
    );
  }
}

// _DeeperAnalysisPanel deleted — it referenced ArchetypeCard /
// FeatureGrid / HiddenDepthPanel / VerdictCard imports that were
// removed in the report-screen redesign, so the iOS Release build
// failed compiling its body even though nothing rendered it. The
// archetype + 16-metric + GPT prose sections moved off the main
// report per bro's "clean per-trait, one geometry breakdown, then
// 60-day protocols" spec — they're not coming back to this screen.

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
  /// Locked teaser variant — the secondary BONE STRUCTURE number is
  /// withheld behind a green "?" (same curiosity gap as the HeroCard's
  /// projected score). The headline out-of-100 stays visible so the
  /// card still proves the app actually read the face.
  final bool locked;

  const _DualScoreHero({
    required this.honest,
    required this.geometry,
    this.locked = false,
  });

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
              if (locked)
                // Withheld geometry score — green "?" sized to sit where
                // the number was so the row stays perfectly balanced.
                Text('?',
                  style: AppTypography.measurement.copyWith(
                    color: AppColors.signalGreen,
                    fontSize: 30, height: 1,
                    letterSpacing: -1.2,
                    fontWeight: FontWeight.w800))
              else ...[
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
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 520.ms).slideY(
      begin: 0.04, end: 0, curve: Curves.easeOutCubic, duration: 520.ms);
  }
}
class _UnlockCta extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _UnlockCta({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.red,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          alignment: Alignment.center,
          child: Text(label,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 13.5, letterSpacing: 2.8,
              fontWeight: FontWeight.w900,
            )),
        ),
      ),
    );
  }
}

/// One locked section — replaces an AI/geometry output card on the
/// teaser. Shows only its eyebrow + the small italic line we use
/// elsewhere ("honest read · on photo" etc), with a flat black
/// content box where the real answer would render. Tapping anywhere
/// fires the paywall. NOT a styled button — the only button-styled
/// CTA on the locked teaser is the one under the HeroCard.
class _LockedSection extends StatelessWidget {
  final String eyebrow;
  final String line;
  final double height;
  final VoidCallback onTap;
  const _LockedSection({
    required this.eyebrow,
    required this.line,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Rd.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.lg),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(Rd.lg),
            border: Border.all(
              color: AppColors.divider, width: 0.6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      color: AppColors.red, size: 14),
                  const SizedBox(width: 6),
                  Text(eyebrow,
                    style: AppTypography.label.copyWith(
                      color: AppColors.red,
                      fontSize: 11, letterSpacing: 3.0,
                      fontWeight: FontWeight.w800,
                    )),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.label.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 10, letterSpacing: 1.6,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                      )),
                  ),
                  Icon(Icons.lock_rounded,
                      color: AppColors.red.withValues(alpha: 0.85),
                      size: 14),
                ],
              ),
              const SizedBox(height: 12),
              // Solid black content area — same rounded corners as
              // the unlocked content cards so the lock state reads
              // as "same card, content withheld."
              Container(
                width: double.infinity,
                height: height,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(Rd.md),
                  border: Border.all(
                    color: AppColors.surface3, width: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
