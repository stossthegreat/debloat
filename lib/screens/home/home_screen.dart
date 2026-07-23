import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/protocol.dart';
import '../../models/scan_record.dart';
import '../../services/analytics_service.dart';
import '../../services/local_store_service.dart';
import '../../services/notification_service.dart';
import '../../services/paywall_gate.dart';
import '../../services/protocol_service.dart';
import '../../services/review_prompt_service.dart';
import '../../services/daily_mission_service.dart';
import '../../services/streak_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/common/mirrorly_wordmark.dart';
import '../../widgets/common/mirrorly_components.dart';
// DEBLOAT OS. Four surfaces, one promise per tab:
//   SCAN / DEBLOAT / FOOD / ASCEND.
import '../debloat/debloat_tab_screen.dart';
import '../food/food_tab_screen.dart';
import 'ascend_screen.dart';

/// The hub. Four surfaces, one promise per tab:
///   0. SCAN    — face scan + bloat read
///   1. DEBLOAT — the daily checklist system
///   2. FOOD    — scan meals that cause puffiness (sodium + bloat grade)
///   3. ASCEND  — streak, daily missions, gap to potential
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
    // FOUR tabs: SCAN (0) / FOOD (1) / DEBLOAT (2) / ASCEND (3). Scan
    // leads the nav and is the default landing tab. Callers that want a
    // specific tab pass initialTab; anything out of range falls back to
    // SCAN so older deep links don't crash.
    final t = widget.initialTab ?? 0;
    _tab = (t >= 0 && t < 4) ? t : 0;
    _reload();
    // Fire the App Store review prompt if the user has now used
    // all three pillars (scan + Free Flow + eye-contact lesson).
    // No-op on every other launch — the service tracks state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ReviewPromptService.maybePrompt(context);
    });
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
    const tabNames = ['scan', 'food', 'debloat', 'ascend'];
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
      body: _loading
          ? const _Splash()
          : IndexedStack(
              index: _tab,
              // Tab roster order: SCAN (0) · FOOD (1) · DEBLOAT (2) ·
              // ASCEND (3). Scan (the face read) leads; Food sits second.
              children: [
                // Tab 0 — SCAN hub: face scan + bloat read. Streak badge
                // on the masthead keeps the loop visible.
                _ScanHubTab(
                  latest:           _latest,
                  protocol:         _protocol,
                  activeProtocols:  _activeProtocols,
                  dayStreak:        _dayStreak,
                  isPro:            _isPro,
                  onRefresh:        _reload,
                ),
                // Tab 1 — FOOD: scan a meal, grade it for facial bloat
                // (sodium load + bloat metric grid). Self-contained; owns
                // its own capture + backend call + result persistence.
                const FoodTabScreen(),
                // Tab 2 — DEBLOAT: the daily checklist system. Every
                // toggle calls back into _reload so the flame + the
                // Ascend consistency stay live.
                DebloatTabScreen(
                  dayStreak: _dayStreak,
                  onChanged: _reload,
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
          padding: const EdgeInsets.only(bottom: Sp.xl),
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
                  const MirrorlyWordmark(fontSize: 34),
                  const Spacer(),
                  if (dayStreak > 0) ...[
                    _StreakBadge(days: dayStreak),
                    const SizedBox(width: 8),
                  ],
                  _ProgressIconChip(
                      onTap: () => context.push('/progress')),
                  const SizedBox(width: 8),
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
            //  PRE-SCAN — the full conversion column: display headline +
            //  1-2-3 path + Current vs Optimised split + BEGIN SCAN CTA
            //  + AFTER UNLOCK strip. This is the first-impression sell.
            //  Hidden the moment the user has scanned — they don't need
            //  to be sold on something they've done.
            // ─────────────────────────────────────────────────────────────
            if (!hasScan) ...[
              const SizedBox(height: Sp.md),

              const DisplayBlock(
                lineOne: 'Your face.',
                lineTwo: 'De-bloated.',
                subhead: 'Real geometry. We measure how much water is '
                    'hiding your jawline.',
              ),

              const SizedBox(height: Sp.lg),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _PathFlow(stepDone: false)),
                      const SizedBox(width: Sp.md),
                      const Expanded(child: _OptimisedSplitCard()),
                    ],
                  ),
                ),
              ).animate().fadeIn(duration: 400.ms)
                .slideY(begin: 0.04, end: 0, duration: 400.ms,
                    curve: Curves.easeOut),

              const SizedBox(height: Sp.lg),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: PrimaryCta(
                  label: 'Begin Face Scan',
                  icon: Icons.center_focus_strong_rounded,
                  meta: 'Takes 30 seconds',
                  onTap: () => context.push('/scan'),
                ),
              ).animate().fadeIn(delay: 160.ms, duration: 400.ms),
            ],

            // ─────────────────────────────────────────────────────────────
            //  POST-SCAN — clean. Only the things a returning user cares
            //  about: their score, their active protocol, talk to the
            //  advisor about it, and a low-key rescan link. None of the
            //  "first impression" scaffolding above.
            // ─────────────────────────────────────────────────────────────
            if (hasScan) ...[
              const SizedBox(height: Sp.lg),

              // HOPE — the only score card on this tab. Bro: "the score
              // card ABOVE the hope card is redundant — potential now
              // shows before/after; remove it." So _LatestSnapshot is
              // gone; _HopeCard carries the read entirely.
              if (latest!.projectedDelta > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                  child: _HopeCard(
                    current:   latest!.score,
                    projected: (latest!.score + latest!.projectedDelta)
                                  .clamp(0, 100),
                    archetype: latest!.archetypeName,
                    pro:       isPro,
                  ),
                ).animate().fadeIn(duration: 400.ms),

              const SizedBox(height: Sp.lg),

              // RESCAN FACE — the obvious primary action a returning
              // user sees.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: PrimaryCta(
                  label: 'Rescan Face',
                  icon: Icons.center_focus_strong_rounded,
                  meta: 'Takes 30 seconds',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.push('/scan');
                  },
                ),
              ).animate().fadeIn(delay: 120.ms, duration: 400.ms),

              // v366 — THE MIRROR hero + the protocol streak tiles
              // moved to the TRANSFORM tab. Looks is now purely the
              // rating surface: score, rescan, done.
            ],
          ],
        ),
      ),
    );
  }
}

// ── Hope card — THE score card on the post-scan Looks tab.
//
// v3 — bro: "put the title full length across the top, number at each
// END, +18 pill in the middle, card SHORTER side-to-side stays."
//
// Composition is now THREE balanced bands:
//   1. Header strip — THE READ · {ARCHETYPE} runs the full width with
//      a tiny live dot on the left.
//   2. Score row — NOW (white) on the LEFT edge, +XX pts pill in the
//      MIDDLE, POTENTIAL (green) on the RIGHT edge. spaceBetween, so
//      whatever screen width we're on the two numbers anchor to the
//      ends and the gain badge centres on its own.
//   3. Manifesto — italic Playfair red, one line, no divider needed.
//
// Card height shrunk ~35% vs the previous version.
class _HopeCard extends StatelessWidget {
  final int current;
  final int projected;
  final String archetype;
  /// v302 — Pro state. When false, the POTENTIAL number is
  /// blacked-out and shows a lock pill; tap routes to /paywall.
  /// Flips to true the moment the user upgrades and the card
  /// rebuilds → real number reveals.
  final bool pro;
  const _HopeCard({
    required this.current,
    required this.projected,
    required this.archetype,
    this.pro = false,
  });

  @override
  Widget build(BuildContext context) {
    final gain = (projected - current).clamp(0, 100);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(
          color: AppColors.signalGreen.withValues(alpha: 0.55),
          width: 1.0),
        boxShadow: [
          BoxShadow(
            color: AppColors.signalGreen.withValues(alpha: 0.22),
            blurRadius: 26, spreadRadius: -4,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header — full-width, red, tracked. Live dot left-anchored.
          Row(
            children: [
              Container(
                width: 5, height: 5,
                decoration: const BoxDecoration(
                  color: AppColors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('THE READ · ${archetype.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(
                    color: AppColors.red,
                    fontSize: 10.5, letterSpacing: 3.2,
                    fontWeight: FontWeight.w900,
                  )),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 2. Score row — NOW edge · +XX pill centre · POTENTIAL edge.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _edgeStat(
                label: 'NOW',
                value: current,
                color: AppColors.textPrimary,
                isNow: true,
                locked: false,
              ),
              _gainPill(gain, locked: !pro),
              _edgeStat(
                label: 'POTENTIAL',
                value: projected,
                color: AppColors.signalGreen,
                isNow: false,
                locked: !pro,
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 3. Manifesto — single line, red italic Playfair, the mission.
          Text('Bloat is not your face. Drain it.',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.spaceGrotesk(
              color: AppColors.red,
              fontSize: 14, height: 1.15,
              letterSpacing: -0.2,
              
              fontWeight: FontWeight.w800,
            )),
        ],
      ),
    );
  }

  /// Edge-anchored score column. Label sits ON TOP of the number, with
  /// the side it anchors to (NOW left-aligns, POTENTIAL right-aligns)
  /// so the gain pill in the middle reads symmetric.
  Widget _edgeStat({
    required String label,
    required int value,
    required Color color,
    required bool isNow,
    required bool locked,
  }) {
    final shown = locked ? '??' : '$value';
    final mainColor = locked ? AppColors.textTertiary : color;
    final body = _edgeStatBody(
      label: label, shown: shown, mainColor: mainColor,
      isNow: isNow, locked: locked);
    // v302 — locked POTENTIAL becomes tap-to-unlock so the gate
    // reads as an obvious upgrade affordance, not a dead pill.
    if (locked && !isNow) {
      return Builder(builder: (ctx) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            ctx.push('/paywall', extra: {'source': 'home_potential_lock'});
          },
          borderRadius: BorderRadius.circular(8),
          child: body,
        ),
      ));
    }
    return body;
  }

  Widget _edgeStatBody({
    required String label,
    required String shown,
    required Color mainColor,
    required bool isNow,
    required bool locked,
  }) {
    return Column(
      crossAxisAlignment:
          isNow ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (locked && !isNow) ...[
              Icon(Icons.lock_rounded,
                color: AppColors.signalGreen.withValues(alpha: 0.85),
                size: 11),
              const SizedBox(width: 4),
            ],
            Text(label,
              style: AppTypography.label.copyWith(
                color: isNow
                    ? AppColors.textTertiary
                    : AppColors.signalGreen.withValues(alpha: 0.85),
                fontSize: 9.5, letterSpacing: 2.4,
                fontWeight: FontWeight.w900,
              )),
          ],
        ),
        const SizedBox(height: 2),
        // Bro: "push the left number up slightly so it's in line with
        // the right number." Italic Playfair has uneven visual tops
        // across digits — 8 / 6 reach higher than 7 / 0 even at the
        // same font size — so NOW visually sits lower than POTENTIAL.
        // A 4px upward translate on the NOW glyph re-aligns the
        // visual tops without touching POTENTIAL's glow shadow.
        Transform.translate(
          offset: Offset(0, isNow ? -4 : 0),
          child: Text(shown,
            style: GoogleFonts.spaceGrotesk(
              color: mainColor,
              fontSize: 48, height: 0.95,
              letterSpacing: -2.0,
              
              fontWeight: FontWeight.w900,
              shadows: isNow || locked
                  ? null
                  : [
                      Shadow(
                        color: AppColors.signalGreen.withValues(alpha: 0.4),
                        blurRadius: 18),
                    ],
            )),
        ),
      ],
    );
  }

  /// +XX pill that sits centred between NOW and POTENTIAL.
  /// v302 — `locked` swaps the gain digits for ??? so the page
  /// doesn't leak the projected delta to free users.
  Widget _gainPill(int gain, {bool locked = false}) {
    final label = locked ? '+??' : '+$gain';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.signalGreen.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: AppColors.signalGreen.withValues(alpha: 0.55),
          width: 0.9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(locked ? Icons.lock_rounded : Icons.trending_up_rounded,
              color: AppColors.signalGreen, size: 13),
          const SizedBox(width: 4),
          Text(label,
            style: AppTypography.label.copyWith(
              color: AppColors.signalGreen,
              fontSize: 13, letterSpacing: 0.4,
              fontWeight: FontWeight.w900,
            )),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.red,
        borderRadius: BorderRadius.circular(99),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withValues(alpha: 0.45),
            blurRadius: 14, spreadRadius: 0),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded,
              color: Colors.white, size: 18),
          const SizedBox(width: 5),
          Text('$days',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 14, height: 1,
              letterSpacing: 0.2,
              fontWeight: FontWeight.w900,
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
// wordmark without dragging the whole legacy MirrorlyMasthead row.
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
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.surface3, width: 0.6),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.tune,
              size: 18, color: AppColors.textSecondary),
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
class _NavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  /// v298 — when true, paints a small red dot over the Ascend tab
  /// icon (index 3) so the user knows there's an unhandled action
  /// inside. Suppressed while the Ascend tab is the active tab —
  /// the dot has done its job once they're there.
  final bool ascendPending;
  const _NavBar({
    required this.index,
    required this.onTap,
    this.ascendPending = false,
  });

  @override
  Widget build(BuildContext context) {
    // ── Tab roster ────────────────────────────────────────────────────────
    // Four tabs: SCAN / DEBLOAT / MIRROR / ASCEND. Each tab does ONE
    // thing — the reading, the daily system, the render, the program.
    final items = const <({String label, IconData icon, bool italic})>[
      (label: 'Scan',    icon: Icons.center_focus_strong_rounded,   italic: false),
      (label: 'Food',    icon: Icons.restaurant_rounded,            italic: false),
      (label: 'Debloat', icon: Icons.water_drop_outlined,           italic: false),
      (label: 'Ascend',  icon: Icons.local_fire_department_rounded, italic: false),
    ];
    // v303 — bottom nav rebuilt in the Skeletal-PT pattern bro
    // pointed at: each tab is its own block, the ACTIVE block fills
    // with the brand red and stays filled, inactive tabs render
    // flat. Bigger icons + bigger labels, and the whole block is
    // the tap target (no more tiny icon-only hit area).
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 0.6)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _NavBlock(
                      label: items[i].label,
                      icon: items[i].icon,
                      active: i == index,
                      showPendingDot:
                          i == 3 && ascendPending && i != index,
                      onTap: () => onTap(i),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// v303 — Bottom-nav block. Active tab fills with brand red and
/// stays filled; inactive tabs render flat. Whole block is the tap
/// target so the user can land anywhere on the rectangle. Big
/// icon (24pt) + big label (12pt italic Playfair) so the chrome
/// reads as confident, not crowded.
///
/// `showPendingDot` rides a small red dot at the top-right of the
/// icon when this tab has an outstanding action (currently only
/// the Ascend tab uses it). Suppressed on the active tab — the dot
/// has served its purpose once the user is there.
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
    // v306 — red fill on the active pill dropped per bro's note;
    // active state is now just the icon + label going red, no
    // block highlight. New size + new block tap-target retained
    // so anywhere on the rectangle still routes.
    final fg = active ? AppColors.red : AppColors.textSecondary;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 24, color: fg),
                  if (showPendingDot)
                    Positioned(
                      right: -5, top: -3,
                      child: Container(
                        width: 9, height: 9,
                        decoration: BoxDecoration(
                          color: AppColors.red,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.surface1, width: 1.4),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(label,
                style: AppTypography.h1.copyWith(
                  color: fg,
                  fontSize: 13, height: 1,
                  letterSpacing: -0.2,
                  
                  fontWeight: FontWeight.w800,
                )),
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
