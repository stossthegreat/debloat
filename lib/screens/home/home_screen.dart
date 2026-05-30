import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../models/protocol.dart';
import '../../models/scan_record.dart';
import '../../services/local_store_service.dart';
import '../../services/protocol_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/common/mirrorly_components.dart';
import '../chat/chat_screen.dart';
import '../eyes/eyes_tab_screen.dart';
import '../game/game_tab_screen.dart';
import '../progress/progress_screen.dart';

/// The hub. Five deep surfaces — Mirrorly's three plus Auralay's two:
///   0. Scan    — trigger a fresh scan / see latest report   (Mirrorly)
///   1. Mirror  — AI chat, always primed with latest scan    (Mirrorly)
///   2. Eyes    — gaze + presence drills                     (Auralay graft)
///   3. Game    — Lucien · Arena / Council / Free Flow       (Auralay graft, renamed)
///   4. Progress— history + protocol + Aura score + streaks  (blended)
class HomeScreen extends StatefulWidget {
  /// Optional initial tab. Pushed by `/you` from Auralay screens so they
  /// land on the merged profile (tab 4 = Progress).
  final int? initialTab;
  const HomeScreen({super.key, this.initialTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _tab;
  ScanRecord? _latest;
  Protocol?   _protocol;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab ?? 0;
    _reload();
  }

  Future<void> _reload() async {
    final latest   = await LocalStoreService.latestScan();
    final protocol = await ProtocolService.loadActive();
    if (!mounted) return;
    setState(() {
      _latest   = latest;
      _protocol = protocol;
      _loading  = false;
    });
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
                _ScanHubTab(latest: _latest, protocol: _protocol, onRefresh: _reload),
                _advisorTab(),
                const EyesTabScreen(),
                const GameTabScreen(),
                ProgressScreen(latest: _latest, protocol: _protocol, onReload: _reload),
              ],
            ),
      bottomNavigationBar: _NavBar(
        index: _tab,
        onTap: (i) { HapticFeedback.selectionClick(); setState(() => _tab = i); },
      ),
    );
  }

  Widget _advisorTab() {
    if (_latest == null) return const _MirrorLocked();
    return ChatScreen(
      geometry:  _latest!.geometry,
      imagePath: _latest!.capturedImagePath,
      embedded:  true,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Tab 0 — Scan hub
// ═══════════════════════════════════════════════════════════════════════════
class _ScanHubTab extends StatelessWidget {
  final ScanRecord? latest;
  final Protocol?   protocol;
  final Future<void> Function() onRefresh;
  const _ScanHubTab({required this.latest, required this.protocol, required this.onRefresh});

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
            // ── Masthead — Mirrorly + tab thesis + actions
            MirrorlyMasthead(
              title: 'Mirrorly',
              subtitle: 'Face. Presence. Game.',
              actions: [
                MastheadAction(
                  icon: Icons.workspace_premium_rounded,
                  iconColor: AppColors.red,
                  borderColor: AppColors.red.withOpacity(0.55),
                  onTap: () => context.push(
                      '/paywall', extra: const {'force': true}),
                ),
                MastheadAction(
                  icon: Icons.tune,
                  onTap: () => context.push('/settings'),
                ),
              ],
            ),

            const SizedBox(height: Sp.md),

            // ── Display headline — italic "YOUR FACE. MEASURED.".
            const DisplayBlock(
              lineOne: 'Your face.',
              lineTwo: 'Measured.',
              subhead: 'Real geometry. Not filters. Not guesses.',
            ),

            const SizedBox(height: Sp.lg),

            // ── 1-2-3 path as a single horizontal row. Each step
            // carries its own lock state so we don't need a separate
            // "after the scan unlock" strip below — the path tells the
            // same story tighter.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: _PathRow(stepDone: hasScan),
            ).animate().fadeIn(duration: 400.ms)
              .slideY(begin: 0.04, end: 0, duration: 400.ms,
                  curve: Curves.easeOut),

            const SizedBox(height: Sp.lg),

            // ── Primary CTA — full-width red, 30-second meta.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: PrimaryCta(
                label: hasScan ? 'Rescan Face' : 'Begin Face Scan',
                icon: Icons.center_focus_strong_rounded,
                meta: 'Takes 30 seconds',
                onTap: () => context.push('/scan'),
              ),
            ).animate().fadeIn(delay: 160.ms, duration: 400.ms),

            // ── Before / After preview for first-time users. Fills the
            // empty lower half with REAL face transformation proof
            // (reusing the marketing renders) so the user sees what
            // "see your strongest version" actually means before the
            // scan, not just a promise. Hidden once they've scanned —
            // the snapshot below carries the same load with their own
            // score.
            if (!hasScan) ...[
              const SizedBox(height: Sp.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: const _ScanPreviewHero(),
              ).animate().fadeIn(delay: 260.ms, duration: 400.ms),
            ],

            // ── Returning-user extras. Score snapshot + active protocol.
            // Hidden on first impression so the conversion column above
            // owns the screen for new users.
            if (hasScan) ...[
              const SizedBox(height: Sp.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: _LatestSnapshot(scan: latest!),
              ).animate().fadeIn(delay: 260.ms, duration: 400.ms),
            ],
            if (protocol != null) ...[
              const SizedBox(height: Sp.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: _ActiveProtocolCard(protocol: protocol!),
              ).animate().fadeIn(delay: 320.ms, duration: 400.ms),
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
// users so the empty lower half carries real transformation proof
// instead of dead black space. Falls back to a face glyph if either
// asset is missing — never crashes the layout.
class _ScanPreviewHero extends StatelessWidget {
  const _ScanPreviewHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(color: AppColors.surface3, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, 8),
            child: Text(
              'See your strongest face'.toUpperCase(),
              style: AppTypography.label.copyWith(
                color: AppColors.red,
                fontSize: 10.5,
                letterSpacing: 2.6,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          AspectRatio(
            aspectRatio: 16 / 10,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [
                Expanded(child: _ScanPreviewTile(
                  asset: 'assets/marketing/before.jpg',
                  label: 'CURRENT',
                  labelColor: AppColors.textSecondary,
                )),
                SizedBox(width: 1),
                Expanded(child: _ScanPreviewTile(
                  asset: 'assets/marketing/after.jpg',
                  label: 'OPTIMISED',
                  labelColor: AppColors.red,
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanPreviewTile extends StatelessWidget {
  final String asset;
  final String label;
  final Color labelColor;
  const _ScanPreviewTile({
    required this.asset,
    required this.label,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          asset,
          fit: BoxFit.cover,
          alignment: const Alignment(0, -0.2),
          errorBuilder: (_, __, ___) => Container(
            color: AppColors.surface1,
            alignment: Alignment.center,
            child: const Icon(Icons.face_outlined,
                size: 36, color: AppColors.surface3),
          ),
        ),
        Positioned(
          left: 10, bottom: 10,
          child: Text(
            label,
            style: AppTypography.label.copyWith(
              color: labelColor,
              fontSize: 10,
              letterSpacing: 2.0,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

// ── 1-2-3 path as a horizontal row of three tiles. Each tile carries
// its own lock state, so we don't need a separate "after the scan
// unlock" strip below — the path IS the unlock story.
class _PathRow extends StatelessWidget {
  final bool stepDone;
  const _PathRow({required this.stepDone});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _PathTile(
              n: 1,
              label: 'Face',
              body: 'Scan your face',
              active: !stepDone,
              done: stepDone,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _PathTile(
              n: 2,
              label: 'Presence',
              body: 'Train eye contact',
              locked: true,
              icon: Icons.remove_red_eye_outlined,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _PathTile(
              n: 3,
              label: 'Game',
              body: 'Roleplay with Lucien',
              locked: true,
              icon: Icons.local_fire_department_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _PathTile extends StatelessWidget {
  final int n;
  final String label;
  final String body;
  final bool active;
  final bool done;
  final bool locked;
  final IconData? icon;
  const _PathTile({
    required this.n,
    required this.label,
    required this.body,
    this.active = false,
    this.done = false,
    this.locked = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isLive = active || done;
    final accent = isLive ? AppColors.red : AppColors.textTertiary;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(
          color: isLive
              ? AppColors.red.withOpacity(0.55)
              : AppColors.surface3,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: done
                      ? AppColors.red.withOpacity(0.18)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 1.2),
                ),
                alignment: Alignment.center,
                child: done
                    ? const Icon(Icons.check_rounded,
                        size: 12, color: AppColors.red)
                    : Text(
                        '$n',
                        style: AppTypography.label.copyWith(
                          color: accent,
                          fontSize: 11,
                          letterSpacing: 0,
                        ),
                      ),
              ),
              const Spacer(),
              if (locked)
                const Icon(Icons.lock_rounded,
                    size: 12, color: AppColors.textTertiary)
              else if (icon != null)
                Icon(icon, size: 14, color: accent),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            label.toUpperCase(),
            style: AppTypography.label.copyWith(
              color: accent,
              letterSpacing: 1.8,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
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
        onTap: () => context.push('/protocol'),
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

// ═══════════════════════════════════════════════════════════════════════════
//  Mirror locked — the Advisor sell page, shown until the user has scanned
// ═══════════════════════════════════════════════════════════════════════════
//
// This isn't a "go scan first" page — it's the pitch for the most valuable
// surface in the app. Users tap the Mirror tab expecting *something*; give
// them a concrete promise of what arrives post-scan: creator-matched cuts,
// beard shape, frames, before/afters rendered onto their own face.
class _MirrorLocked extends StatelessWidget {
  const _MirrorLocked();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: Sp.xxl),
          children: [
            // ── Masthead — italic display name + tab thesis + tune action.
            MirrorlyMasthead(
              title: 'The Mirror',
              subtitle: 'Same face. Different lane.',
              actions: [
                MastheadAction(
                  icon: Icons.tune,
                  onTap: () => context.push('/settings'),
                ),
              ],
            ),

            const SizedBox(height: Sp.lg),

            // ── Display headline — italic two-line "KNOWS YOUR BONES /
            // TO THE MILLIMETRE" with the bottom line in red.
            const DisplayBlock(
              lineOne: 'Knows your bones',
              lineTwo: 'to the millimetre.',
              subhead: 'Picks the cut. Renders it on you.',
            ),

            const SizedBox(height: Sp.lg),

            // ── Before / After hero pair — existing tiles, asset-safe.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: const _BeforeAfterPairs(),
            ).animate().fadeIn(delay: 120.ms, duration: 400.ms),

            const SizedBox(height: Sp.lg),

            // ── Stat strip — the credibility proof. Reads as a lab report.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: const StatStrip(stats: [
                StatPoint(
                  icon: Icons.architecture_outlined,
                  value: '16',
                  label: 'Measurements',
                ),
                StatPoint(
                  icon: Icons.gps_fixed_rounded,
                  value: '0.1mm',
                  label: 'Precision',
                ),
                StatPoint(
                  icon: Icons.auto_awesome_rounded,
                  value: 'AI',
                  label: 'Photoreal',
                ),
              ]),
            ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

            const SizedBox(height: Sp.lg),

            // ── Primary CTA — full-width red, 30s meta.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: PrimaryCta(
                label: 'Begin First Scan',
                icon: Icons.auto_awesome_rounded,
                trailingIcon: Icons.arrow_forward_rounded,
                meta: 'Takes 30 seconds',
                onTap: () => context.push('/scan'),
              ),
            ).animate().fadeIn(delay: 300.ms, duration: 400.ms),

            const SizedBox(height: Sp.lg),

            // ── Lock strip — what unlocks with the first scan.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: LockStrip(
                label: 'First scan unlocks',
                highlight: 'Looks  ·  Presence  ·  Game',
                badges: const [],
                onTap: () => context.push('/scan'),
              ),
            ).animate().fadeIn(delay: 400.ms, duration: 400.ms),

            const SizedBox(height: Sp.md),

            // ── Compliance link, kept tiny.
            Center(
              child: TextButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  context.push('/privacy');
                },
                child: Text(
                  'Privacy',
                  style: AppTypography.label.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                    letterSpacing: 1.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mirror-tab pre-scan stack — one BEFORE photo and one AFTER photo
/// side-by-side. Two files total, no categories.
///
/// Source images live at:
///   assets/marketing/before.jpg
///   assets/marketing/after.jpg
/// See assets/marketing/README.md. If either is missing the tile
/// falls back to a tasteful placeholder so the build never breaks.
class _BeforeAfterPairs extends StatelessWidget {
  const _BeforeAfterPairs();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: Row(
        children: const [
          Expanded(child: _BeforeAfterTile(
              asset: 'assets/marketing/before.jpg',
              caption: 'BEFORE')),
          SizedBox(width: 10),
          Expanded(child: _BeforeAfterTile(
              asset: 'assets/marketing/after.jpg',
              caption: 'AFTER')),
        ],
      ),
    );
  }
}

class _BeforeAfterTile extends StatelessWidget {
  final String asset;
  final String caption;
  const _BeforeAfterTile({required this.asset, required this.caption});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Rd.lg),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            asset,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: AppColors.surface2,
              child: const Center(
                child: Icon(Icons.face_outlined,
                  size: 36, color: AppColors.textTertiary),
              ),
            ),
          ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 22, 12, 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.78)],
                ),
              ),
              child: Text(caption,
                style: AppTypography.label.copyWith(
                  color: caption == 'AFTER' ? AppColors.red : Colors.white,
                  fontSize: 10, letterSpacing: 2.4,
                  fontWeight: FontWeight.w800)),
            ),
          ),
        ],
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
    // Five tabs. Three Mirrorly originals + two Auralay imports. The Game
    // tab is the renamed "Lucien" / "Villain" surface from Auralay; user
    // explicitly asked for the label to land as "GAME" in the same italic
    // Playfair voice that Auralay used for "LUCIEN". We pass an italic flag
    // per item so the nav bar can swap fonts on that one entry.
    final items = const <({String label, IconData icon, bool italic})>[
      (label: 'Scan',     icon: Icons.center_focus_strong_rounded, italic: false),
      (label: 'Mirror',   icon: Icons.auto_awesome,                italic: false),
      (label: 'Eyes',     icon: Icons.visibility_outlined,         italic: false),
      (label: 'Game',     icon: Icons.local_fire_department_outlined, italic: true),
      (label: 'Progress', icon: Icons.show_chart_rounded,          italic: false),
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
