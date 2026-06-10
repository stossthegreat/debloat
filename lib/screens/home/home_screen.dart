import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/protocol.dart';
import '../../models/scan_record.dart';
import '../../services/local_store_service.dart';
import '../../services/protocol_service.dart';
import '../../services/review_prompt_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/common/mirrorly_components.dart';
import '../../widgets/report/aspect_protocol_cards.dart';
import '../eyes/eyes_tab_screen.dart';
import '../game/game_tab_screen.dart';
import '../rizz/rizz_tab_screen.dart';
// ASCEND tab folded — streak moved to Looks masthead. Re-import +
// re-add the IndexedStack child below to restore.
// import 'ascend_screen.dart';

/// The hub. Four surfaces, one promise per tab:
///   0. HOME (Ascend) — streak, daily missions, gap to potential
///   1. LOOKS         — face scan + report + Mirror chat link
///   2. PRESENCE      — eye contact + voice training
///   3. GAME          — Lucien roleplay + Free Flow
///
/// Mirror tab folded into LOOKS (chat reachable via a "Talk to your
/// advisor" link). Progress folded into HOME (the Ascend dashboard
/// is the progress story). Five tabs → four.
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
  Protocol?   _protocol;
  /// Every active protocol the user has committed to, keyed by axis.
  /// Bro\'s multi-commit model — SKIN, JAW, DEBLOAT, HAIR can all be
  /// running in parallel and each one surfaces as its own tile on
  /// the Looks tab.
  Map<String, Protocol> _activeProtocols = const {};
  bool _loading = true;
  // Pillar scores, each /10. Read on _reload from the same places the
  // individual tabs already write to:
  //   - LOOKS  ← latest scan.score (out of 100)
  //   - AURA   ← AuralayAppProvider auraScore SharedPref (out of 100)
  //   - GAME   ← Free Flow / Council best score SharedPref (out of 100)
  int _looksScore = 0;
  int _auraScore  = 0;
  int _gameScore  = 0;
  int _dayStreak  = 0;
  // Today\'s Ascension — which pillars have a completion logged TODAY.
  // Each session screen writes its `<pillar>_done_ymd` int (year*10000 +
  // month*100 + day) to SharedPreferences when a rep lands; here we
  // read each and compare against today\'s YMD.
  bool _looksDoneToday = false;
  bool _auraDoneToday  = false;
  bool _gameDoneToday  = false;

  static int _todayYmd() {
    final n = DateTime.now();
    return n.year * 10000 + n.month * 100 + n.day;
  }

  @override
  void initState() {
    super.initState();
    // Three tabs now: LOOKS / GAME / RIZZ. ASCEND folded in (the
    // streak badge moved onto the Looks masthead). Any legacy deep
    // link with a higher index falls back to LOOKS so older app-
    // shortcuts don't crash the app.
    final t = widget.initialTab ?? 0;
    _tab = (t >= 0 && t < 3) ? t : 0;
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

    // Bro: "why are streaks not showing when I\'ve done all three
    // lessons." Compute the TRIPLE STREAK — consecutive days where
    // all 3 pillars (LOOKS / AURA / GAME) were completed. The old
    // _dayStreak only read protocol.effectiveStreak, which is a
    // per-protocol streak — it didn\'t know about pillar completion
    // at all. We now stamp triple_streak_count on the first reload
    // each day where all 3 are done; the home masthead reads
    // max(protocol streak, triple streak) so whichever the user
    // earned is what they see.
    final today    = _todayYmd();
    final looksOk  = (prefs.getInt('looks_done_ymd') ?? 0) == today;
    final auraOk   = (prefs.getInt('aura_done_ymd')  ?? 0) == today;
    final gameOk   = (prefs.getInt('game_done_ymd')  ?? 0) == today;
    final allThree = looksOk && auraOk && gameOk;
    int tripleStreak = prefs.getInt('triple_streak_count') ?? 0;
    final lastTripleYmd = prefs.getInt('triple_streak_last_ymd') ?? 0;
    if (allThree && lastTripleYmd != today) {
      // Update once per day. If yesterday was a hit, continue;
      // otherwise reset to 1 (first day of a new streak).
      final yYesterdayDate = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayYmd = yYesterdayDate.year * 10000 +
          yYesterdayDate.month * 100 + yYesterdayDate.day;
      tripleStreak = (lastTripleYmd == yesterdayYmd) ? tripleStreak + 1 : 1;
      await prefs.setInt('triple_streak_count',   tripleStreak);
      await prefs.setInt('triple_streak_last_ymd', today);
    } else if (!allThree && lastTripleYmd != today) {
      // User hasn\'t hit 3/3 today AND yesterday wasn\'t a hit
      // either — streak is dead. Reset so we don\'t falsely
      // resurrect a stale count.
      final yYesterdayDate = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayYmd = yYesterdayDate.year * 10000 +
          yYesterdayDate.month * 100 + yYesterdayDate.day;
      if (lastTripleYmd != yesterdayYmd && lastTripleYmd != 0) {
        tripleStreak = 0;
        await prefs.setInt('triple_streak_count', 0);
      }
    }

    if (!mounted) return;
    setState(() {
      _latest          = latest;
      _protocol        = protocol;
      _activeProtocols = all;
      _loading         = false;
      // /100 → /10 across the board so the Ascend pillars read the
      // same scale the Eyes / Game share cards do. Each pillar reads
      // its SharedPreferences key written by the corresponding flow
      // — looks_score (report screen, GPT honest headline), aura_score
      // (scripted or Selene gaze sessions), game_score (Free Flow).
      // Bro: pillars must reflect the LATEST attempt. The persist
      // sites now always overwrite with the most recent score, so
      // here we just read and divide. latest?.score is the legacy
      // fallback for users whose first scan landed before the
      // looks_score key existed.
      final looksRaw = prefs.getInt('looks_score') ?? latest?.score ?? 0;
      _looksScore = (looksRaw / 10).round().clamp(0, 10);
      _auraScore  = ((prefs.getInt('aura_score')  ?? 0) / 10).round().clamp(0, 10);
      _gameScore  = ((prefs.getInt('game_score')  ?? 0) / 10).round().clamp(0, 10);
      // _dayStreak is the bigger of the protocol streak and the
      // triple-pillar streak — whichever the user actually
      // earned, that\'s what the masthead chip displays.
      final protocolStreak = protocol?.effectiveStreak ?? 0;
      _dayStreak = protocolStreak > tripleStreak ? protocolStreak : tripleStreak;
      _looksDoneToday = looksOk;
      _auraDoneToday  = auraOk;
      _gameDoneToday  = gameOk;
    });
  }

  void _switchTab(int i) {
    HapticFeedback.selectionClick();
    setState(() => _tab = i);
    // Re-read scan + pillar prefs whenever the user returns to the
    // Ascend tab — keeps LOOKS / AURA / GAME live the moment they
    // finish a lesson elsewhere in the app.
    if (i == 0) {
      // ignore: discarded_futures
      _reload();
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
              children: [
                // LOOKS — first tab now (Ascend folded). Streak badge
                // moved onto the masthead so users still see the loop.
                _ScanHubTab(
                  latest:           _latest,
                  protocol:         _protocol,
                  activeProtocols:  _activeProtocols,
                  dayStreak:        _dayStreak,
                  onRefresh:        _reload,
                ),
                const GameTabScreen(),
                const RizzTabScreen(),
                // EYES / AURA + ASCEND temporarily commented out.
                // Both screens stay in tree; restoring is a one-line
                // re-add here + uncommenting the nav item below.
                // const EyesTabScreen(),
                // AscendScreen(...),
              ],
            ),
      bottomNavigationBar: _NavBar(
        index: _tab,
        onTap: _switchTab,
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
  final Future<void> Function()  onRefresh;
  const _ScanHubTab({
    required this.latest,
    required this.protocol,
    required this.activeProtocols,
    required this.dayStreak,
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
            // ── Masthead — always visible. The brand chrome.
            //    Only the Ascend tab carries the "Mirrorly" wordmark;
            //    every other tab uses just its own name as the title.
            MirrorlyMasthead(
              title: 'Looks',
              actions: [
                if (dayStreak > 0) _StreakBadge(days: dayStreak),
                MastheadAction(
                  icon: Icons.tune,
                  onTap: () => context.push('/settings'),
                ),
              ],
            ),

            // Subtitle paired with the Rizz tab's "Hit her phone.
            // Every time." — same italic Inter, same horizontal
            // inset, same red colour. The two taglines together
            // ladder: "Looks + game = unavoidable."
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                'Looks + game = unavoidable.',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 15, height: 1.4,
                  fontStyle: FontStyle.italic,
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
                lineTwo: 'Measured.',
                subhead: 'Real geometry. Not filters. Not guesses.',
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

              const SizedBox(height: Sp.lg),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: const LockStrip(
                  label: 'After the scan, unlock',
                  highlight: 'Aura  ·  Game',
                  badges: [
                    LockBadge(
                      icon: Icons.remove_red_eye_outlined,
                      label: 'Aura',
                      color: AppColors.accent,
                    ),
                    LockBadge(
                      icon: Icons.local_fire_department_rounded,
                      label: 'Game',
                      color: AppColors.red,
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 260.ms, duration: 400.ms),
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

              const SizedBox(height: Sp.md),

              // THE MIRROR — moved up from below the protocol grid to
              // sit directly under RESCAN, above the protocol streak
              // cards. It's the most-used post-scan secondary action,
              // so it earns the slot.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: _MirrorHeroCard(
                  onTap: () => context.push('/chat', extra: {
                    'geometry':  latest!.geometry,
                    'imagePath': latest!.capturedImagePath,
                  }),
                ),
              ).animate().fadeIn(delay: 180.ms, duration: 400.ms),

              const SizedBox(height: Sp.lg),

              // SKIN / JAW / DEBLOAT / HAIR — protocol streak tiles.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: AspectProtocolCards(
                  geometry:         latest!.geometry,
                  savedImagePath:   latest!.capturedImagePath,
                  activeProtocols:  activeProtocols,
                ),
              ).animate().fadeIn(delay: 240.ms, duration: 400.ms),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Hope card — THE score card on the post-scan Looks tab. Bro: "10x
// it brutal clean energy. Potential in GREEN, NOW in WHITE."
//
// Composition (top → bottom):
//   · Small red eyebrow + archetype line  (THE READ · {ARCHETYPE})
//   · Massive NOW score (white) ─ arrow ─ POTENTIAL (green) gain pill
//   · "+15 POINTS WAITING" callout in italic Playfair
//   · One-line manifesto in red — "Bones are not the ceiling. Execution is."
//
// No filler. The whole card reads in two seconds.
class _HopeCard extends StatelessWidget {
  final int current;
  final int projected;
  final String archetype;
  const _HopeCard({
    required this.current,
    required this.projected,
    required this.archetype,
  });

  @override
  Widget build(BuildContext context) {
    final gain = (projected - current).clamp(0, 100);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(
          color: AppColors.signalGreen.withValues(alpha: 0.55),
          width: 1.0),
        boxShadow: [
          BoxShadow(
            color: AppColors.signalGreen.withValues(alpha: 0.22),
            blurRadius: 32, spreadRadius: -2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Eyebrow — RED, tracked, archetype context.
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

          const SizedBox(height: 18),

          // ── NOW → POTENTIAL row. The headline.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _bigStat(
                label: 'NOW',
                value: current,
                color: AppColors.textPrimary,
                isNow: true,
              ),
              const SizedBox(width: 18),
              Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: Icon(Icons.arrow_forward_rounded,
                    color: AppColors.textTertiary.withValues(alpha: 0.8),
                    size: 26),
              ),
              const SizedBox(width: 18),
              _bigStat(
                label: 'POTENTIAL',
                value: projected,
                color: AppColors.signalGreen,
                isNow: false,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Gain badge — italic Playfair, green pill.
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
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
                    const Icon(Icons.trending_up_rounded,
                        color: AppColors.signalGreen, size: 14),
                    const SizedBox(width: 5),
                    Text('+$gain POINTS WAITING',
                      style: AppTypography.label.copyWith(
                        color: AppColors.signalGreen,
                        fontSize: 11, letterSpacing: 2.4,
                        fontWeight: FontWeight.w900,
                      )),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Manifesto — red, italic Playfair. The mission.
          Container(width: double.infinity, height: 1,
              color: AppColors.divider.withValues(alpha: 0.5)),
          const SizedBox(height: 14),
          Text('Bones are not the ceiling.\nExecution is.',
            style: GoogleFonts.playfairDisplay(
              color: AppColors.red,
              fontSize: 15.5, height: 1.25,
              letterSpacing: -0.2,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w800,
            )),
        ],
      ),
    );
  }

  /// Big number column — label on top (tracked, tertiary), giant italic
  /// Playfair score below. NOW is white, POTENTIAL is signal green.
  Widget _bigStat({
    required String label,
    required int value,
    required Color color,
    required bool isNow,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
          style: AppTypography.label.copyWith(
            color: isNow
                ? AppColors.textTertiary
                : AppColors.signalGreen.withValues(alpha: 0.85),
            fontSize: 10, letterSpacing: 2.4,
            fontWeight: FontWeight.w900,
          )),
        const SizedBox(height: 4),
        Text('$value',
          style: GoogleFonts.playfairDisplay(
            color: color,
            fontSize: 64, height: 0.95,
            letterSpacing: -2.6,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w900,
            shadows: isNow
                ? null
                : [
                    Shadow(
                      color: AppColors.signalGreen.withValues(alpha: 0.45),
                      blurRadius: 24),
                  ],
          )),
      ],
    );
  }
}

// ── Streak badge — a tiny flame-prefixed pill in the Looks masthead
// action row. Survives the Ascend-tab removal so the user still sees
// the daily-streak loop without scrolling to find it.
class _StreakBadge extends StatelessWidget {
  final int days;
  const _StreakBadge({required this.days});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: AppColors.red.withValues(alpha: 0.45), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded,
              color: AppColors.red, size: 16),
          const SizedBox(width: 5),
          Text('$days',
            style: GoogleFonts.inter(
              color: AppColors.red,
              fontSize: 13.5, height: 1,
              letterSpacing: 0.2,
              fontWeight: FontWeight.w900,
            )),
        ],
      ),
    );
  }
}

// ── Mirror hero card — compact, with the before/after image inline
// so the card SHOWS the AI advisor's value at a glance. The right
// half is a tight split image (current ↔ optimised); the left half
// carries the headline copy. Smaller than the previous full-bleed
// red card — just enough to read and tap.
class _MirrorHeroCard extends StatelessWidget {
  final VoidCallback onTap;
  const _MirrorHeroCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(Rd.lg),
      child: InkWell(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        borderRadius: BorderRadius.circular(Rd.lg),
        splashColor: AppColors.red.withValues(alpha: 0.06),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Rd.lg),
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.42), width: 0.9),
            boxShadow: [
              BoxShadow(
                color: AppColors.red.withValues(alpha: 0.18),
                blurRadius: 22, spreadRadius: 0,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Rd.lg),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left — copy block.
                  Expanded(
                    flex: 5,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 8, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('THE MIRROR',
                            style: AppTypography.label.copyWith(
                              color: AppColors.red,
                              fontSize: 10.5, letterSpacing: 2.8,
                              fontWeight: FontWeight.w800,
                            )),
                          const SizedBox(height: 8),
                          Text('See what could\nchange.',
                            style: GoogleFonts.playfairDisplay(
                              color: AppColors.textPrimary,
                              fontSize: 20, height: 1.1,
                              letterSpacing: -0.4,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w800,
                            )),
                          const SizedBox(height: 6),
                          Text(
                            'AI that knows your face.',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 12.5, height: 1.35,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Right — before / after split image.
                  Expanded(
                    flex: 4,
                    child: SizedBox(
                      height: 130,
                      child: Row(
                        children: [
                          Expanded(child: _half(
                            asset: 'assets/marketing/before.jpg',
                            label: 'NOW',
                          )),
                          Container(width: 1, color: Colors.white),
                          Expanded(child: _half(
                            asset: 'assets/marketing/after.jpg',
                            label: 'FIXED',
                          )),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _half({required String asset, required String label}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(asset,
          fit: BoxFit.cover,
          alignment: const Alignment(0, -0.25),
          errorBuilder: (_, __, ___) => Container(
            color: AppColors.surface2,
            alignment: Alignment.center,
            child: const Icon(Icons.face_retouching_natural,
                size: 32, color: AppColors.surface3),
          ),
        ),
        // Bottom scrim for the corner label.
        Positioned(
          left: 0, right: 0, bottom: 0, height: 36,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.58),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Text(label,
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 9, letterSpacing: 2.4,
                fontWeight: FontWeight.w800,
              )),
          ),
        ),
      ],
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
        _step(1, 'Face first', 'Maxx your looks',
            active: !stepDone, done: stepDone),
        const SizedBox(height: 18),
        _step(2, 'Aura next', 'Train eye contact & voice'),
        const SizedBox(height: 18),
        _step(3, 'Game after', 'Real roleplay with Lucien'),
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

// ── Active protocol card ────────────────────────────────────────────────────
class _ActiveProtocolCard extends StatelessWidget {
  final Protocol protocol;
  const _ActiveProtocolCard({required this.protocol});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        // Pass the axis so the protocol screen loads THIS specific
        // run (not whichever legacy "active" comes back first). Each
        // tile maps to one axis-keyed protocol slot.
        onTap: () => context.push('/protocol', extra: {
          'pulldown': protocol.targetAxis,
        }),
        borderRadius: BorderRadius.circular(Rd.xl),
        child: Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(Rd.xl),
            border: Border.all(color: AppColors.divider, width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('PROTOCOL · DAY ${protocol.currentDay} / ${protocol.lengthDays}',
                    style: AppTypography.label.copyWith(
                      color: AppColors.textTertiary, letterSpacing: 2.4, fontSize: 9)),
                  const Spacer(),
                  // Streak chip — colour follows live / at-risk / broken so
                  // the home hub reflects whether the run is live without
                  // having to open the protocol screen.
                  _StreakChip(protocol: protocol),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded,
                    size: 14, color: AppColors.textSecondary),
                ],
              ),
              const SizedBox(height: 6),
              Text(protocol.title,
                style: AppTypography.h1.copyWith(fontSize: 22, letterSpacing: -0.4)),
              const SizedBox(height: 4),
              Text('Targeting ${protocol.targetAxis.toLowerCase()}. '
                   '${protocol.completedDays.length} days logged.',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary, fontSize: 12.5)),
              const SizedBox(height: Sp.sm),
              Stack(
                children: [
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: AppColors.surface3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: protocol.progress,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          AppColors.divider,
                          AppColors.red,
                        ]),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
              if (!protocol.completedToday) ...[
                const SizedBox(height: Sp.sm),
                Text('• Today\'s check-in pending',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.signalAmber, fontSize: 11.5,
                    fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


// ── Streak chip — miniature flame+number lockup for the home protocol card ─
class _StreakChip extends StatelessWidget {
  final Protocol protocol;
  const _StreakChip({required this.protocol});

  @override
  Widget build(BuildContext context) {
    final streak = protocol.effectiveStreak;
    if (streak <= 0 && protocol.streakStatus == StreakStatus.fresh) {
      return const SizedBox.shrink();
    }
    final color = switch (protocol.streakStatus) {
      StreakStatus.live    => AppColors.red,
      StreakStatus.atRisk  => AppColors.signalAmber,
      StreakStatus.broken  => AppColors.textMuted,
      StreakStatus.fresh   => AppColors.textTertiary,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.local_fire_department, size: 13, color: color),
        const SizedBox(width: 2),
        Text('$streak',
          style: AppTypography.measurement.copyWith(
            color: color, fontSize: 12, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

// ── Bottom nav ──────────────────────────────────────────────────────────────
class _NavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _NavBar({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // ── Tab roster ────────────────────────────────────────────────────────
    // Four tabs. HOME is the Ascend dashboard (streak + missions + gap).
    // LOOKS is the renamed Scan tab (Mirror chat folded inside it).
    // PRESENCE is the renamed Eyes tab. GAME is unchanged. Each tab does
    // ONE thing — no five-tab sprawl, no shouting for attention.
    // Three tabs: LOOKS / GAME / RIZZ. ASCEND folded (streak badge
    // moved to the Looks masthead). AURA stays commented — easy
    // restore later by adding the entry back here + un-commenting
    // the EyesTabScreen line in the IndexedStack.
    final items = const <({String label, IconData icon, bool italic})>[
      (label: 'Looks', icon: Icons.face_retouching_natural_outlined, italic: true),
      (label: 'Game',  icon: Icons.chat_bubble_outline_rounded,       italic: true),
      (label: 'Rizz',  icon: Icons.bolt_rounded,                      italic: true),
    ];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 0.6)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(items[i].icon,
                          size: 20,
                          color: i == index
                              ? AppColors.red
                              : AppColors.textTertiary),
                        const SizedBox(height: 3),
                        // GAME renders italic Playfair to match how the
                        // Auralay tab used to brand Lucien — the editorial
                        // serif italic against the all-caps tracked sans.
                        Text(
                          items[i].italic
                              ? items[i].label    // mixed case for italic serif
                              : items[i].label.toUpperCase(),
                          style: (items[i].italic
                                  ? AppTypography.h1.copyWith(
                                      fontStyle: FontStyle.italic,
                                      fontWeight: FontWeight.w700)
                                  : AppTypography.label)
                              .copyWith(
                                color: i == index
                                    ? AppColors.red
                                    : AppColors.textTertiary,
                                fontSize: items[i].italic ? 11 : 8.5,
                                letterSpacing: items[i].italic ? -0.2 : 1.8,
                                height: 1,
                              ),
                        ),
                      ],
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
