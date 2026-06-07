import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

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
import 'ascend_screen.dart';

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
    // Tabs collapsed 5 → 4 (Progress folded into Home). Any legacy
    // deep link asking for tab 4 falls back to Home so the app
    // doesn't crash with an index out of bounds.
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
                AscendScreen(
                  onJumpToTab:    _switchTab,
                  latest:         _latest,
                  dayStreak:      _dayStreak,
                  looksScore:     _looksScore,
                  auraScore:      _auraScore,
                  gameScore:      _gameScore,
                  looksDoneToday: _looksDoneToday,
                  auraDoneToday:  _auraDoneToday,
                  gameDoneToday:  _gameDoneToday,
                ),
                _ScanHubTab(
                  latest:           _latest,
                  protocol:         _protocol,
                  activeProtocols:  _activeProtocols,
                  onRefresh:        _reload,
                ),
                const EyesTabScreen(),
                const GameTabScreen(),
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
  final Future<void> Function()  onRefresh;
  const _ScanHubTab({
    required this.latest,
    required this.protocol,
    required this.activeProtocols,
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
                MastheadAction(
                  icon: Icons.tune,
                  onTap: () => context.push('/settings'),
                ),
              ],
            ),

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

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: _LatestSnapshot(scan: latest!),
              ).animate().fadeIn(duration: 400.ms),

              const SizedBox(height: Sp.lg),

              // RESCAN FACE moved UP so it is the obvious primary
              // action a returning user sees — not buried under
              // protocol cards. Bro: "you've hidden the scan button
              // under these cards."
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
              ).animate().fadeIn(delay: 80.ms, duration: 400.ms),

              const SizedBox(height: Sp.lg),

              // SKIN / JAW / DEBLOAT / HAIR — single section. Each
              // tile renders COMMITTED (day count, streak) or
              // AVAILABLE (one-liner hook) depending on whether the
              // user has started that axis. Bro: "if they commit
              // only one fucking shows" — no separate active-tile-
              // on-top + available-tile-below sections anymore;
              // each axis renders exactly once in whichever state
              // it is in.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: AspectProtocolCards(
                  geometry:         latest!.geometry,
                  savedImagePath:   latest!.capturedImagePath,
                  activeProtocols:  activeProtocols,
                ),
              ).animate().fadeIn(delay: 140.ms, duration: 400.ms),

              const SizedBox(height: Sp.md),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: _AdvisorLink(
                  onTap: () => context.push('/chat', extra: {
                    'geometry':  latest!.geometry,
                    'imagePath': latest!.capturedImagePath,
                  }),
                ),
              ).animate().fadeIn(delay: 240.ms, duration: 400.ms),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Before / After preview for the Scan tab. Two face renders
// (assets/marketing/before.jpg + after.jpg) shown side by side under
// the CURRENT / OPTIMISED labels. Sits below the CTA for pre-scan
// ── 1-2-3 path used on the Scan tab — numbered circles, current
// step painted red, subsequent steps muted. Vertical column, sits
// beside _OptimisedSplitCard.
// ── Mirror chat link — sits on the Looks tab so the Mirror surface
// is reachable without its own bottom-nav tab. Subtle row, taps
// route to /chat which loads the embedded ChatScreen primed with
// the latest scan geometry.
class _AdvisorLink extends StatelessWidget {
  final VoidCallback onTap;
  const _AdvisorLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      borderRadius: BorderRadius.circular(Rd.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Sp.md, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(Rd.lg),
          border: Border.all(color: AppColors.surface3, width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded,
                size: 18, color: AppColors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'THE MIRROR',
                    style: AppTypography.label.copyWith(
                      color: AppColors.red,
                      fontSize: 10,
                      letterSpacing: 2.4,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Talk to your advisor about your scan',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded,
                size: 16, color: AppColors.textTertiary),
          ],
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

// ── Latest snapshot preview ─────────────────────────────────────────────────
class _LatestSnapshot extends StatelessWidget {
  final ScanRecord scan;
  const _LatestSnapshot({required this.scan});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('${scan.score}',
                style: AppTypography.display.copyWith(
                  fontSize: 44, color: AppColors.red,
                  letterSpacing: -2.2, height: 1)),
              Text('/ 100',
                style: AppTypography.label.copyWith(
                  color: AppColors.textTertiary, fontSize: 9, letterSpacing: 1.8)),
            ],
          ),
          const SizedBox(width: Sp.md),
          Container(width: 1, height: 56, color: AppColors.divider),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(scan.tierLabel.toUpperCase(),
                  style: AppTypography.label.copyWith(
                    color: AppColors.textTertiary, letterSpacing: 2.4, fontSize: 10)),
                const SizedBox(height: 3),
                Text(scan.archetypeName,
                  style: AppTypography.h1.copyWith(
                    fontSize: 18, letterSpacing: -0.3, height: 1.2)),
                const SizedBox(height: 2),
                Text('${scan.archetypeMatchPct}% match · '
                     '${_relative(scan.takenAt)}',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiary, fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24)   return '${diff.inHours} h ago';
    if (diff.inDays < 7)     return '${diff.inDays} d ago';
    return '${(diff.inDays / 7).floor()} wk ago';
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
    final items = const <({String label, IconData icon, bool italic})>[
      (label: 'Ascend',   icon: Icons.keyboard_double_arrow_up_rounded, italic: false),
      (label: 'Looks',    icon: Icons.face_retouching_natural_outlined, italic: false),
      (label: 'Aura',     icon: Icons.visibility_outlined,               italic: false),
      (label: 'Game',     icon: Icons.chat_bubble_outline_rounded,       italic: true),
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
