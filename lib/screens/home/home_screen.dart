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
import '../chat/chat_screen.dart';
import '../progress/progress_screen.dart';

/// The hub. Three deep surfaces — not six shallow ones:
///   0. Scan — trigger a fresh scan / see latest report
///   1. Advisor — AI chat, always primed with latest scan
///   2. Progress — history charts + generation gallery + active protocol
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  ScanRecord? _latest;
  Protocol?   _protocol;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
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
    if (_latest == null) return const _NoScanYet(forTab: 'Advisor');
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
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: onRefresh,
        color: AppColors.red,
        backgroundColor: AppColors.surface1,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.xxl),
          children: [
            // Masthead
            Row(
              children: [
                Text('Mirrorly',
                  style: AppTypography.h1.copyWith(
                    fontSize: 28, letterSpacing: -0.8, height: 1)),
                const SizedBox(width: 10),
                Container(
                  width: 5, height: 5, margin: const EdgeInsets.only(top: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.red, shape: BoxShape.circle),
                ),
                const Spacer(),
                _IconBtn(
                  icon: Icons.tune,
                  onTap: () => context.push('/settings'),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('THE FACE · MEASURED · MAXIMIZED',
              style: AppTypography.label.copyWith(
                color: AppColors.textMuted, fontSize: 8.5, letterSpacing: 3.0)),

            const SizedBox(height: Sp.xl),

            _CheckInCard(latest: latest)
              .animate().fadeIn(duration: 400.ms)
              .slideY(begin: 0.04, end: 0, duration: 400.ms, curve: Curves.easeOut),

            const SizedBox(height: Sp.md),

            if (protocol != null) ...[
              _ActiveProtocolCard(protocol: protocol!)
                .animate().fadeIn(delay: 160.ms, duration: 400.ms),
              const SizedBox(height: Sp.md),
            ],

            if (latest != null) ...[
              _LatestSnapshot(scan: latest!)
                .animate().fadeIn(delay: 260.ms, duration: 400.ms),
              const SizedBox(height: Sp.md),
            ],

            _PrimaryScanCta(hasPrior: latest != null)
              .animate().fadeIn(delay: 360.ms, duration: 400.ms),
          ],
        ),
      ),
    );
  }
}

// ── Check-in card ───────────────────────────────────────────────────────────
class _CheckInCard extends StatelessWidget {
  final ScanRecord? latest;
  const _CheckInCard({required this.latest});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final (title, body, accent) = _state(now);

    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(color: accent.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: 0.5), width: 0.8),
            ),
            child: Icon(Icons.auto_awesome, color: accent, size: 18),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                  style: AppTypography.label.copyWith(
                    color: accent, letterSpacing: 2.5, fontSize: 9)),
                const SizedBox(height: 4),
                Text(body,
                  style: AppTypography.body.copyWith(
                    color: AppColors.textPrimary, fontSize: 14, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (String, String, Color) _state(DateTime now) {
    if (latest == null) {
      return (
        'START HERE',
        'Scan once. Real measurements — not a guess, not a rating.',
        AppColors.red,
      );
    }
    final daysSince = now.difference(latest!.takenAt).inDays;
    if (daysSince >= 7) {
      return (
        'RESCAN · $daysSince DAYS',
        'Jawline, skin, body comp — something\'s shifted. See what.',
        AppColors.signalAmber,
      );
    }
    if (daysSince >= 3) {
      return (
        'CHECK-IN',
        'Ask the advisor one thing you\'ve been wondering about your face.',
        AppColors.accent,
      );
    }
    return (
      'ACTIVE',
      '${latest!.score}/100 · ${latest!.tierLabel} · ${latest!.archetypeName}.',
      AppColors.signalGreen,
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

// ── Primary scan CTA ────────────────────────────────────────────────────────
class _PrimaryScanCta extends StatelessWidget {
  final bool hasPrior;
  const _PrimaryScanCta({required this.hasPrior});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, height: 58,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.red,
          foregroundColor: AppColors.base,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rd.lg)),
        ),
        onPressed: () {
          HapticFeedback.mediumImpact();
          context.push('/scan');
        },
        child: Text(hasPrior ? 'Begin new scan' : 'Begin first scan',
          style: const TextStyle(
            fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 0.4)),
      ),
    );
  }
}

class _NoScanYet extends StatelessWidget {
  final String forTab;
  const _NoScanYet({required this.forTab});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Sp.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 42,
                  color: AppColors.textSecondary.withValues(alpha: 0.65)),
                const SizedBox(height: Sp.md),
                Text('Scan first.',
                  style: AppTypography.h1.copyWith(fontSize: 28, letterSpacing: -0.6)),
                const SizedBox(height: 6),
                Text('$forTab reads from your geometry. '
                     'You need at least one scan before we can advise.',
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary, fontSize: 14)),
                const SizedBox(height: Sp.xl),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: AppColors.base,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Rd.lg)),
                    ),
                    onPressed: () => context.push('/scan'),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 26),
                      child: Text('Start scan',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
    final items = const [
      ('Scan',     Icons.center_focus_strong_rounded),
      ('Advisor',  Icons.auto_awesome),
      ('Progress', Icons.show_chart_rounded),
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
                        Icon(items[i].$2,
                          size: 20,
                          color: i == index
                              ? AppColors.red
                              : AppColors.textTertiary),
                        const SizedBox(height: 3),
                        Text(items[i].$1.toUpperCase(),
                          style: AppTypography.label.copyWith(
                            color: i == index
                                ? AppColors.red
                                : AppColors.textTertiary,
                            fontSize: 8.5, letterSpacing: 1.8)),
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

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.divider, width: 0.8),
          ),
          child: Icon(icon, size: 16, color: AppColors.textSecondary),
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
