import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/protocol.dart';
import '../../models/scan_record.dart';
import '../../services/analytics_service.dart';
import '../../services/debloat_report_service.dart';
import '../../services/debloat_stats_service.dart';
import '../../services/local_store_service.dart';
import '../../services/notification_service.dart';
import '../../services/paywall_gate.dart';
import '../../services/protocol_service.dart';
import '../../services/daily_mission_service.dart';
import '../../services/streak_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/common/brand_wordmark.dart';
import '../../widgets/common/ui_kit.dart';
// DEBLOAT OS. Four surfaces, one promise per tab:
//   TODAY / FOOD / SCAN / PROGRESS.
import '../debloat/debloat_tab_screen.dart';
import '../food/food_tab_screen.dart';
import 'ascend_screen.dart';

/// The hub. Four surfaces, one promise per tab:
///   0. TODAY    — the daily anti-bloat system (landing tab)
///   1. FOOD     — photograph meals for sodium load + bloat grade
///   2. SCAN     — the face measurement + bloat read
///   3. PROGRESS — streak, daily actions, trend over time
class HomeScreen extends StatefulWidget {
  /// Optional initial tab.
  final int? initialTab;
  const HomeScreen({super.key, this.initialTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _tab;
  ScanRecord? _latest;
  /// v281 — full scan history surfaced to the Ascend tab's
  /// timeline. Loaded alongside latestScan() so the home tab only
  /// runs one read for both fields.
  List<ScanRecord> _scans = const [];
  Protocol?   _protocol;
  /// Every active protocol the user has committed to, keyed by axis.
  /// Bro\'s multi-commit model — SKIN, JAW, DEBLOAT, HAIR can all be
  /// running in parallel and each one surfaces as its own tile on
  /// the Looks tab.
  Map<String, Protocol> _activeProtocols = const {};
  bool _loading = true;
  int _dayStreak  = 0;
  int _longestStreak = 0;
  // Earned ascension day (total days shown up, 1..60) + rolling 7-day
  // mission-completion consistency, both from StreakService.progress so
  // the Ascend tab's DAY N/60 and CONSISTENCY bar agree with the flame.
  int _ascensionDay = 1;
  int _consistency  = 0;
  // v289 — raw 0-100 versions surfaced separately because the
  // Ascend tab's DEBLOAT-score formula needs the original precision;
  // the /10 fields above stay around for the home-tab pillar tiles
  // that have always rendered out of 10.
  int _looksScore100 = 0;
  // Today's quota-aware mission set from DailyMissionService — rotates
  // daily, only offers what the weekly allowances can actually complete.
  List<DailyMission> _dailyMissions = const [];
  // Today\'s Ascension — has the LOOKS pillar logged a completion TODAY?
  // The scan/protocol flows write `looks_done_ymd` (year*10000 +
  // month*100 + day) to SharedPreferences when a rep lands; here we
  // read it and compare against today\'s YMD.
  bool _looksDoneToday = false;
  /// v302 — Pro / paid state. Drives the POTENTIAL-score lock on
  /// THE READ card so free users see a blacked-out value with a
  /// lock affordance; flipped to true the moment Pro is detected.
  bool _isPro = false;

  static int _todayYmd() {
    final n = DateTime.now();
    return n.year * 10000 + n.month * 100 + n.day;
  }

  @override
  void initState() {
    super.initState();
    // FOUR tabs: TODAY (0) / FOOD (1) / SCAN (2) / PROGRESS (3).
    // TODAY leads the nav and is the default landing tab, so the app
    // opens on the work rather than on a face score. Callers that want
    // a specific tab pass initialTab; anything out of range falls back
    // to TODAY so older deep links don't crash.
    final t = widget.initialTab ?? 0;
    _tab = (t >= 0 && t < 4) ? t : 0;
    _reload();
    // Review popup COMMENTED OUT per bro — its "leave a comment"
    // path still opens the OLD Mirrorly App Store listing
    // (id6762532788). Re-enable once the Debloat OS listing has its
    // own ID wired through ReviewPromptService.
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   if (mounted) ReviewPromptService.maybePrompt(context);
    // });
  }

  Future<void> _reload() async {
    final latest     = await LocalStoreService.latestScan();
    // v281 — also load the full scan history for the Ascend tab
    // timeline. loadScans() returns reverse-chronological (latest
    // first) — same order the timeline renders.
    final allScans   = await LocalStoreService.loadScans();
    final all        = await ProtocolService.loadAllActive();
    // Pick a representative active protocol for the legacy _protocol
    // field (used by the masthead streak chip + the Today\'s Ascension
    // streak fallback). Prefer the longest-streak one so the masthead
    // reflects the user\'s best running streak across all axes.
    Protocol? protocol;
    for (final p in all.values) {
      if (protocol == null ||
          p.effectiveStreak > protocol.effectiveStreak) {
        protocol = p;
      }
    }
    final prefs    = await SharedPreferences.getInstance();

    // ── DAILY STREAK ─────────────────────────────────────────────────────
    // Centralised in StreakService so the Looks / Ascend surfaces all
    // read the same number. A day counts the moment the daily looks
    // mission (scan or protocol check-in) is done.
    final today    = _todayYmd();
    final looksOk  = (prefs.getInt('looks_done_ymd') ?? 0) == today;
    // v302 — Pro flag for the POTENTIAL lock on THE READ card.
    final pro = await PaywallGate.isPro();
    // One call for the whole ascension triad — streak, earned day, and
    // rolling-7-day consistency — so every surface reads the same
    // numbers.
    final snap = await StreakService.progress();
    final curStreak  = snap.streak;
    final longStreak = snap.longest;
    // Today's quota-aware mission set (rotates daily, remembers what's
    // done) for the Ascend panel. progress() above already generated /
    // persisted today's set, so this read is instant and consistent.
    final dailyMissions = await DailyMissionService.loadToday();

    if (!mounted) return;
    setState(() {
      _latest          = latest;
      _scans           = allScans;
      _protocol        = protocol;
      _activeProtocols = all;
      _loading         = false;
      // Raw /100 value feeds the Ascend tab's DEBLOAT-score
      // formula. looks_score is written by the report screen (GPT
      // honest headline); latest?.score is the legacy fallback for
      // users whose first scan landed before the looks_score key
      // existed.
      final looksRaw = prefs.getInt('looks_score') ?? latest?.score ?? 0;
      _looksScore100 = looksRaw.clamp(0, 100);
      // Daily streak from StreakService — the single source every
      // masthead + the Ascend panel now read.
      _dayStreak     = curStreak;
      _longestStreak = longStreak;
      _ascensionDay  = snap.ascensionDay;
      _consistency   = snap.consistency;
      _dailyMissions = dailyMissions;
      _looksDoneToday = looksOk;
      _isPro = pro;
    });
  }

  void _switchTab(int i) {
    HapticFeedback.selectionClick();
    setState(() => _tab = i);
    // Tab-switch analytics — paired with the router observer's
    // screen_view event so we can rebuild the SCAN / FOOD / DEBLOAT /
    // ASCEND funnel without having to dedupe screen_views by source.
    const tabNames = ['scan', 'food', 'debloat', 'progress'];
    if (i >= 0 && i < tabNames.length) {
      // ignore: discarded_futures
      AnalyticsService.tabOpened(tabNames[i]);
    }
    // Re-read scan + pillar prefs + advance the streak whenever the
    // user returns to the Scan (0), Debloat (2), OR Ascend (3) tab —
    // keeps the masthead flame and the Ascend streak panel live the
    // moment they finish a mission elsewhere in the app. Food (1) is
    // self-contained and needs no reload.
    if (i == 0 || i == 2 || i == 3) {
      // ignore: discarded_futures
      _reload();
    }
    // v298 — opening Ascend is the canonical "I saw the
    // notification" moment. Clear the iOS app-icon badge in
    // addition to the lifecycle-resume clear so users who tap
    // Ascend mid-session don't keep staring at the red dot.
    if (i == 3) {
      // ignore: discarded_futures
      NotificationService.clearIconBadge();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      // v57 — the nav is a floating dock now, so the page runs to the
      // bottom edge underneath it instead of being cropped above a bar.
      extendBody: true,
      body: _loading
          ? const _Splash()
          : IndexedStack(
              index: _tab,
              // v57 tab roster: TODAY (0) · FOOD (1) · SCAN (2) ·
              // PROGRESS (3). The daily anti-bloat system leads and is
              // the landing tab — this app is a bloat tracker you work
              // every day, not a face-rating app you open once. The
              // face scan demotes to slot 2, where it belongs: a
              // measurement you take periodically to check the trend.
              children: [
                // Tab 0 — TODAY: the daily debloat system. Every toggle
                // calls back into _reload so the flame + the Progress
                // consistency stay live.
                DebloatTabScreen(
                  dayStreak: _dayStreak,
                  onChanged: _reload,
                ),
                // Tab 1 — FOOD: photograph a meal, get its sodium load
                // and facial-bloat grade. Self-contained; owns its own
                // capture + backend call + result persistence.
                const FoodTabScreen(),
                // Tab 2 — SCAN: the face measurement + bloat read.
                _ScanHubTab(
                  latest:           _latest,
                  protocol:         _protocol,
                  activeProtocols:  _activeProtocols,
                  dayStreak:        _dayStreak,
                  isPro:            _isPro,
                  onRefresh:        _reload,
                ),
                // Tab 3 — ASCEND. Pulls the protocol + scan history +
                // completion booleans from this screen's state so it
                // never has to spin up its own service layer.
                AscendScreen(
                  onJumpToTab:          _switchTab,
                  activeProtocols:      _activeProtocols,
                  onRefresh:            _reload,
                  protocol:             _protocol,
                  latest:               _latest,
                  allScans:             _scans,
                  dayStreak:            _dayStreak,
                  longestStreak:        _longestStreak,
                  ascensionDay:         _ascensionDay,
                  consistency:          _consistency,
                  dailyMissions:        _dailyMissions,
                  looksDoneToday:       _looksDoneToday,
                  looksScore100:        _looksScore100,
                ),
              ],
            ),
      bottomNavigationBar: _NavBar(
        index: _tab,
        onTap: _switchTab,
        // v298 — pending dot on Ascend tab (index 3) when the user
        // has an open daily action. The canonical "do this" signal
        // is whether today's protocol is still un-logged; tapping
        // the tab routes them to the missions panel where they
        // clear it.
        ascendPending: !_looksDoneToday,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Tab 0 — Scan hub
// ═══════════════════════════════════════════════════════════════════════════
class _ScanHubTab extends StatelessWidget {
  final ScanRecord?              latest;
  /// Legacy single active protocol — used by tiles that only know
  /// how to render one. The Looks tab itself uses [activeProtocols]
  /// to render every committed run.
  final Protocol?                protocol;
  /// Every active protocol the user has committed to, keyed by
  /// canonical axis. Each surfaces as its own compact tile under
  /// the scan button.
  final Map<String, Protocol>    activeProtocols;
  /// Day-streak count (consecutive days the user logged anything).
  /// Surfaces as a small flame-prefixed badge in the masthead so the
  /// streak loop survives the Ascend-tab removal.
  final int                      dayStreak;
  /// v302 — Pro flag. Locks the POTENTIAL value on THE READ card
  /// for free users; the moment Pro is detected, the lock
  /// dissolves and the real number lands.
  final bool                     isPro;
  final Future<void> Function()  onRefresh;
  const _ScanHubTab({
    required this.latest,
    required this.protocol,
    required this.activeProtocols,
    required this.dayStreak,
    required this.isPro,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final hasScan = latest != null;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: onRefresh,
        color: AppColors.red,
        backgroundColor: AppColors.surface1,
        child: ListView(
          padding: const EdgeInsets.only(bottom: Sp.dock),
          children: [
            // ── Masthead — replaced the old "Looks" title with the
            //    Debloat OS wordmark and the brand subhead "The guy she
            //    can't ignore." Subhead sits tight against the
            //    wordmark so it reads as one editorial header.
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const DebloatWordmark(fontSize: 34),
                  const Spacer(),
                  if (dayStreak > 0) ...[
                    _StreakBadge(days: dayStreak),
                    const SizedBox(width: 8),
                  ],
                  // Progress chip removed — the Progress tab now owns scan
                  // history + the Face Evolution reveal.
                  _MastheadCog(
                      onTap: () => context.push('/settings')),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                'Find the face under the bloat.',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 15, height: 1.35,
                  
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            const SizedBox(height: 4),

            // ─────────────────────────────────────────────────────────────
            //  PRE-SCAN — a hard-hitting, distinct first impression. Big
            //  hook headline, a LOCKED "Debloat Read" teaser card (the
            //  same card the post-scan state reveals), what-we-read rows,
            //  then the CTA. Deliberately unlike the old looksmax pitch.
            // ─────────────────────────────────────────────────────────────
            if (!hasScan) ...[
              const SizedBox(height: Sp.lg),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.spaceGrotesk(
                      color: AppColors.textPrimary,
                      fontSize: 32, height: 1.12,
                      fontWeight: FontWeight.w800, letterSpacing: -1),
                    children: [
                      const TextSpan(text: 'Your face is\nholding '),
                      TextSpan(text: 'water.',
                        style: const TextStyle(color: AppColors.brand)),
                    ],
                  ),
                ),
              ).animate().fadeIn(duration: 400.ms),

              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: Text(
                  'Scan to see how much — and exactly where it\'s hiding '
                  'your jawline.',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 15, height: 1.4, fontWeight: FontWeight.w500),
                ),
              ),

              const SizedBox(height: Sp.lg),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: const _DebloatReadCard(
                  currentLabel: 'Facial Bloat',
                  percent: 0,
                  locked: true,
                ),
              ).animate().fadeIn(delay: 120.ms, duration: 450.ms)
                .slideY(begin: 0.03, end: 0, curve: Curves.easeOut),

              const SizedBox(height: Sp.lg),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: Column(
                  children: const [
                    _ReadRow(icon: Icons.opacity_rounded,
                      title: 'Fluid retention', body: 'How much water your face is holding.'),
                    SizedBox(height: 12),
                    _ReadRow(icon: Icons.visibility_outlined,
                      title: 'Under-eye + cheeks', body: 'Where the puffiness is softening your look.'),
                    SizedBox(height: 12),
                    _ReadRow(icon: Icons.architecture_rounded,
                      title: 'Jaw definition', body: 'The jawline hiding under the bloat.'),
                  ],
                ),
              ).animate().fadeIn(delay: 220.ms, duration: 450.ms),

              const SizedBox(height: Sp.lg),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: PrimaryCta(
                  label: 'Begin Face Scan',
                  icon: Icons.center_focus_strong_rounded,
                  meta: 'Takes 30 seconds',
                  onTap: () {
                    // ignore: discarded_futures
                    AnalyticsService.scanBegun('scan_tab');
                    context.push('/scan');
                  },
                ),
              ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
            ],

            // ─────────────────────────────────────────────────────────────
            //  POST-SCAN — the DEBLOAT READ card (current bloat →
            //  projected definition) + rescan.
            // ─────────────────────────────────────────────────────────────
            if (hasScan) ...[
              const SizedBox(height: Sp.lg),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: _DebloatReadCard(
                  // Hard line-break so the tier sits on line 1 and "Facial
                  // Bloat" on line 2 — mirrors the two-line PROJECTED side.
                  currentLabel:
                      '${DebloatStatsService.compute(latest!.geometry).tier}\nFacial Bloat',
                  percent:
                      DebloatReportService.compute(latest!.geometry).projectedPoints,
                  locked: false,
                ),
              ).animate().fadeIn(duration: 400.ms),

              const SizedBox(height: Sp.lg),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: PrimaryCta(
                  label: 'Rescan Face',
                  icon: Icons.center_focus_strong_rounded,
                  meta: 'Takes 30 seconds',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    // ignore: discarded_futures
                    AnalyticsService.scanBegun('rescan');
                    context.push('/scan');
                  },
                ),
              ).animate().fadeIn(delay: 120.ms, duration: 400.ms),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  THE DEBLOAT READ card — the Scan tab's hero. Post-scan it shows the
//  user's current bloat tier → projected sharper definition with the
//  estimated % gain. Pre-scan (locked) it teases the same card so the
//  first impression sells the read they're about to get.
// ═══════════════════════════════════════════════════════════════════════════
class _DebloatReadCard extends StatelessWidget {
  final String currentLabel; // e.g. "Moderate Facial Bloat"
  final int percent;         // estimated definition gain
  final bool locked;
  const _DebloatReadCard({
    required this.currentLabel,
    required this.percent,
    required this.locked,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(
          color: AppColors.signalGreen.withValues(alpha: 0.5), width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.signalGreen.withValues(alpha: 0.16),
            blurRadius: 26, spreadRadius: -6, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 6, height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.signalGreen, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text('THE DEBLOAT READ',
                style: AppTypography.label.copyWith(
                  color: AppColors.signalGreen,
                  fontSize: 11, letterSpacing: 2.8, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 18),
          // Two balanced bands so the card can never tilt: band 1 is the
          // eyebrow + a FIXED two-line title box on each side (long tiers
          // ellipsize instead of wrapping to a third line), band 2 is the
          // two face glyphs + the arrow on one shared centreline.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _titleCol(
                  eyebrow: 'CURRENT',
                  title: locked ? '???\nFacial Bloat' : currentLabel,
                ),
              ),
              const SizedBox(width: 32),
              Expanded(
                child: _titleCol(
                  eyebrow: 'PROJECTED',
                  title: 'Sharper\nDefinition',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Center(
                  child: _FaceGlyph(
                    color: AppColors.signalAmber, bloated: true),
                ),
              ),
              const Icon(Icons.arrow_forward_rounded,
                color: AppColors.textTertiary, size: 24),
              const Expanded(
                child: Center(
                  child: _FaceGlyph(
                    color: AppColors.signalGreen, bloated: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.signalGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: AppColors.signalGreen.withValues(alpha: 0.45))),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(locked ? Icons.lock_rounded : Icons.trending_up_rounded,
                    color: AppColors.signalGreen, size: 17),
                  const SizedBox(width: 8),
                  Text(locked
                      ? 'Scan to reveal your read'
                      : '+$percent% Facial Definition',
                    style: GoogleFonts.inter(
                      color: AppColors.signalGreen,
                      fontSize: 15, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text('Estimated improvement after protocol.',
              style: GoogleFonts.inter(
                color: AppColors.textTertiary,
                fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _titleCol({
    required String eyebrow,
    required String title,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(eyebrow,
          style: AppTypography.label.copyWith(
            color: AppColors.textTertiary,
            fontSize: 10, letterSpacing: 1.8, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        // Fixed two-line box: both sides reserve identical height, so the
        // glyph row below always sits level no matter how the copy wraps.
        SizedBox(
          height: 46,
          child: Text(title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.spaceGrotesk(
              color: AppColors.textPrimary,
              fontSize: 19, height: 1.18,
              fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        ),
      ],
    );
  }
}

/// Face-in-brackets glyph — amber (bloated) or green (defined).
class _FaceGlyph extends StatelessWidget {
  final Color color;
  final bool bloated;
  const _FaceGlyph({required this.color, required this.bloated});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88, height: 88,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.crop_free, size: 88,
            color: color.withValues(alpha: 0.9)),
          Icon(bloated ? Icons.face_rounded : Icons.face_retouching_natural,
            size: 42, color: color),
        ],
      ),
    );
  }
}

/// A "what we read" row for the pre-scan hero.
class _ReadRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _ReadRow({required this.icon, required this.title, required this.body});
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.brand.withValues(alpha: 0.3))),
          alignment: Alignment.center,
          child: Icon(icon, color: AppColors.brand, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(body,
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 13, height: 1.35, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Streak badge — a tiny flame-prefixed pill in the Looks masthead
// action row. Survives the Ascend-tab removal so the user still sees
// the daily-streak loop without scrolling to find it.
/// v303 — promoted to a solid red fill so the chip carries real
/// visual weight in the masthead row. Same shape Ascend + Rizz use.
class _StreakBadge extends StatelessWidget {
  final int days;
  const _StreakBadge({required this.days});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.brand.withValues(alpha: 0.55), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.water_drop_rounded,
              color: AppColors.brand, size: 14),
          const SizedBox(width: 5),
          Text('$days',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontSize: 15, height: 1,
              fontWeight: FontWeight.w800,
            )),
          const SizedBox(width: 4),
          Text(days == 1 ? 'DAY' : 'DAYS',
            style: GoogleFonts.inter(
              color: AppColors.textTertiary,
              fontSize: 8.5, height: 1,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w800,
            )),
        ],
      ),
    );
  }
}

// ── Progress chip — sits between the streak flame and the settings
// cog. Single circular icon, same diameter as _MastheadCog, accent
// hairline so the user reads it as "a chart you can open" rather
// than another setting. Routes to /progress.
class _ProgressIconChip extends StatelessWidget {
  final VoidCallback onTap;
  const _ProgressIconChip({required this.onTap});

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
              color: AppColors.signalAmber.withValues(alpha: 0.55),
              width: 0.8),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.show_chart_rounded,
              size: 18, color: AppColors.signalAmber),
        ),
      ),
    );
  }
}

// ── Masthead cog — small circular settings icon in the top-right of
// the Looks tab + Rizz tab mastheads. Replaces the old
// MastheadAction so we get a clean compact icon next to the brand
// wordmark without dragging the whole legacy masthead row.
class _MastheadCog extends StatelessWidget {
  final VoidCallback onTap;
  const _MastheadCog({required this.onTap});

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
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.surface3, width: 0.6),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.more_horiz_rounded,
              size: 20, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _PathFlow extends StatelessWidget {
  final bool stepDone;
  const _PathFlow({required this.stepDone});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _step(1, 'Scan', 'Measure the bloat',
            active: !stepDone, done: stepDone),
        const SizedBox(height: 18),
        _step(2, 'The system', 'The daily checklist that drains it'),
        const SizedBox(height: 18),
        _step(3, 'The mirror', 'See yourself fully drained'),
      ],
    );
  }

  Widget _step(int n, String label, String body,
      {bool active = false, bool done = false}) {
    final accent = active || done ? AppColors.red : AppColors.textTertiary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26, height: 26,
          decoration: BoxDecoration(
            color: done ? AppColors.red.withOpacity(0.18) : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: accent, width: 1.2),
          ),
          alignment: Alignment.center,
          child: done
              ? const Icon(Icons.check_rounded, size: 14, color: AppColors.red)
              : Text(
                  '$n',
                  style: AppTypography.label.copyWith(
                    color: accent,
                    fontSize: 12,
                    letterSpacing: 0,
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: AppTypography.label.copyWith(
                  color: accent,
                  letterSpacing: 2.0,
                  fontSize: 10.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Current / Optimised card — sits to the right of _PathFlow.
// Uses the existing Mirror-tab marketing assets (assets/marketing/
// before.jpg + after.jpg) for a real visual hook on the pre-scan
// screen instead of a placeholder silhouette pair.
class _OptimisedSplitCard extends StatelessWidget {
  const _OptimisedSplitCard();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Rd.lg),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface2,
          border: Border.all(color: AppColors.surface3, width: 1),
          borderRadius: BorderRadius.circular(Rd.lg),
        ),
        child: AspectRatio(
          aspectRatio: 4 / 5,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Row(
                children: const [
                  Expanded(child: _SplitFaceTile(
                    asset: 'assets/marketing/before.jpg',
                  )),
                  _SplitDivider(),
                  Expanded(child: _SplitFaceTile(
                    asset: 'assets/marketing/after.jpg',
                  )),
                ],
              ),
              // Bottom shade ramp so the lock label reads.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.55),
                        ],
                        stops: const [0.55, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 10, top: 10,
                child: Text(
                  'CURRENT',
                  style: AppTypography.label.copyWith(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 9,
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Positioned(
                right: 10, top: 10,
                child: Text(
                  'OPTIMISED',
                  style: AppTypography.label.copyWith(
                    color: AppColors.red,
                    fontSize: 9,
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Positioned(
                left: 10, right: 10, bottom: 10,
                child: Row(
                  children: [
                    const Icon(Icons.lock_rounded,
                        size: 12, color: AppColors.textTertiary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'See your strongest'.toUpperCase(),
                        style: AppTypography.label.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 9,
                          letterSpacing: 1.6,
                          height: 1.3,
                        ),
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplitFaceTile extends StatelessWidget {
  final String asset;
  const _SplitFaceTile({required this.asset});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      fit: BoxFit.cover,
      alignment: const Alignment(0, -0.2),
      errorBuilder: (_, __, ___) => Container(
        color: AppColors.surface1,
        alignment: Alignment.center,
        child: const Icon(Icons.face_outlined,
            size: 36, color: AppColors.surface3),
      ),
    );
  }
}

class _SplitDivider extends StatelessWidget {
  const _SplitDivider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, color: AppColors.surface3);
}

// ── Bottom nav ──────────────────────────────────────────────────────────────
// v57 — FLOATING DOCK. The old nav was a full-bleed bar pinned to the
// screen edge with a hairline on top. This one lifts off the edge as a
// rounded, self-contained dock: the page scrolls underneath it, the
// active tab wears a filled cyan capsule, and the whole thing sits on a
// soft brand glow. Written from scratch for Debloat OS — icons, labels,
// palette and geometry are all ours.
class _NavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  /// Paints a small cyan dot over the Progress tab icon when the user
  /// still has an open daily action. Suppressed while that tab is
  /// active — the dot has done its job once they're there.
  final bool ascendPending;

  const _NavBar({
    required this.index,
    required this.onTap,
    this.ascendPending = false,
  });

  /// Four surfaces, one promise each: the daily system, the plate,
  /// the measurement, the trend.
  static const _items = <({String label, IconData icon})>[
    (label: 'Today',    icon: Icons.water_drop_rounded),
    (label: 'Food',     icon: Icons.restaurant_rounded),
    (label: 'Scan',     icon: Icons.center_focus_strong_rounded),
    (label: 'Progress', icon: Icons.show_chart_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Container(
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.16), width: 0.8),
            boxShadow: [
              // Depth against the page + a faint brand halo so the dock
              // reads as lit, not just layered.
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 22, offset: const Offset(0, 8)),
              BoxShadow(
                color: AppColors.red.withValues(alpha: 0.09),
                blurRadius: 26, spreadRadius: -6),
            ],
          ),
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _NavBlock(
                    label: _items[i].label,
                    icon: _items[i].icon,
                    active: i == index,
                    showPendingDot: i == 3 && ascendPending && i != index,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One dock slot. The active slot fills with a soft cyan capsule and
/// turns its icon + label brand-cyan; inactive slots stay flat and
/// muted. The capsule animates in so switching tabs has weight.
///
/// The whole slot is the tap target — the user can land anywhere in
/// the column, not just on the glyph.
class _NavBlock extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final bool showPendingDot;
  final VoidCallback onTap;

  const _NavBlock({
    required this.label,
    required this.icon,
    required this.active,
    required this.showPendingDot,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppColors.red : AppColors.textSecondary;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
          decoration: BoxDecoration(
            color: active
                ? AppColors.red.withValues(alpha: 0.13)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active
                  ? AppColors.red.withValues(alpha: 0.30)
                  : Colors.transparent,
              width: 0.8,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 21, color: fg),
                  if (showPendingDot)
                    Positioned(
                      top: -2, right: -3,
                      child: Container(
                        width: 7, height: 7,
                        decoration: BoxDecoration(
                          color: AppColors.red,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.red.withValues(alpha: 0.6),
                              blurRadius: 5),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.visible,
                style: GoogleFonts.inter(
                  fontSize: 8.5,
                  height: 1.0,
                  color: fg,
                  letterSpacing: 0.6,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox(
      width: 28, height: 28,
      child: CircularProgressIndicator(color: AppColors.textSecondary, strokeWidth: 2),
    ),
  );
}
