import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/dev_flags.dart';
import '../../services/local_store_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/common/mirrorly_components.dart';
import 'arena/arena_scenes_screen.dart';
import 'freeflow/free_flow_screen.dart';

/// GAME tab — minimal IA. Editorial masthead + two cards:
///
///   1. FREE FLOW — open-ended live voice conversation, the main event
///   2. ARENA      — opens the scene picker (was a 6-girl grid, now one
///                    card so the page reads as cards, not portraits)
///
/// "Chat with Lucien" and the 6-girl portrait row were intentionally
/// removed — the Game tab now sells cleanly with two actions, not a
/// scroll of character art that competed for attention. The screens
/// themselves stay live (ArenaScenesScreen, FreeFlowScreen).
class GameTabScreen extends StatefulWidget {
  const GameTabScreen({super.key});

  @override
  State<GameTabScreen> createState() => _GameTabScreenState();
}

class _GameTabScreenState extends State<GameTabScreen> {
  // Paywall entitlement state. Free users get one Free Flow live
  // conversation (consumed on open); arenas + council are pro-only.
  // `_loaded` gates the locked visual so a paid user never sees a lock
  // flash on launch.
  bool _pro      = false;
  bool _gameUsed = false;
  bool _loaded   = false;

  @override
  void initState() {
    super.initState();
    _loadEntitlements();
  }

  Future<void> _loadEntitlements() async {
    final pro      = kBypassPaywall ? true : await LocalStoreService.isSubscribed();
    final gameUsed = await LocalStoreService.gameFreeUsed();
    if (!mounted) return;
    setState(() {
      _pro      = pro;
      _gameUsed = gameUsed;
      _loaded   = true;
    });
  }

  // Free Flow: pro = unlimited; free = exactly one convo (consumed on
  // open), then paywall. Cards never paint as locked — the handlers
  // do all gating, so the surface stays clean across pro and free.

  Future<void> _toPaywall() async {
    await context.push('/paywall');
    if (!mounted) return;
    _loadEntitlements();
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => screen),
    );
    if (!mounted) return;
    _loadEntitlements();
  }

  Future<void> _onFreeFlow() async {
    if (_pro) { _open(const FreeFlowScreen()); return; }
    if (!_gameUsed) {
      await LocalStoreService.markGameFreeUsed();
      if (!mounted) return;
      setState(() => _gameUsed = true);
      _open(const FreeFlowScreen());
      return;
    }
    _toPaywall();
  }

  void _onArena() {
    if (_pro) { _open(const ArenaScenesScreen()); return; }
    _toPaywall();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: Sp.xxl),
          children: [
            // Editorial masthead — italic Playfair "Game" + brand dot.
            // No Lucien portrait, no chip strip, no extra chrome — the
            // page sells with the cards, not the hero. Free Flow card
            // sits high enough that ARENA is visible above the fold.
            MirrorlyMasthead(
              title: 'Game',
              actions: [
                MastheadAction(
                  icon: Icons.tune,
                  onTap: () => context.push('/settings'),
                ),
              ],
            ),

            const SizedBox(height: Sp.sm),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: Text(
                'Practice real-time game until you\'re unstoppable.',
                style: AppTypography.body.copyWith(
                  color: AppColors.textPrimary,
                  height: 1.45,
                ),
              ),
            ),

            // Larger spacer above FREE FLOW so the card sits lower on
            // the screen, breathing room around the main action.
            const SizedBox(height: Sp.xl),

            // FREE FLOW — main event. Always tappable; paywall gating
            // happens inside the handler. Pulses softly so the eye
            // lands on it first.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: _FreeFlowCard(onTap: _onFreeFlow),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(
                  begin: const Offset(1.0, 1.0),
                  end: const Offset(1.014, 1.014),
                  duration: 1600.ms,
                  curve: Curves.easeInOut,
                ),

            const SizedBox(height: Sp.md),

            // ARENA — ONE card, not the 6-woman portrait grid. Same
            // editorial composition as the rest of the new IA: italic
            // headline, small-caps eyebrow, chevron CTA. Opens the
            // arena picker on tap (where the woman selection still
            // lives — just hidden until the user explicitly enters).
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: _ArenaCard(onTap: _onArena),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Arena card ─────────────────────────────────────────────────────
// One clean card that opens the scene picker. Replaces the old
// 6-portrait horizontal grid that competed with the Free Flow card
// for attention.
class _ArenaCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ArenaCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(Rd.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.lg),
        splashColor: AppColors.red.withValues(alpha: 0.06),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Rd.lg),
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.32), width: 0.9),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('THE ARENA',
                      style: AppTypography.label.copyWith(
                        color: AppColors.red,
                        fontSize: 11, letterSpacing: 3.0,
                        fontWeight: FontWeight.w800,
                      )),
                    const SizedBox(height: 8),
                    Text('Scripted scenes.\nReal pressure.',
                      style: GoogleFonts.playfairDisplay(
                        color: AppColors.textPrimary,
                        fontSize: 26, height: 1.1,
                        letterSpacing: -0.5,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w800,
                      )),
                    const SizedBox(height: 8),
                    Text('Pick a scene. Hold the frame.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 13.5, height: 1.4,
                      )),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              const Icon(Icons.arrow_forward_ios_rounded,
                color: AppColors.red, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Free Flow card ─────────────────────────────────────────────────
// Horizontal layout: left column carries the eyebrow + title + body
// + CTA; right column carries the woman portrait. Locked state shows
// "UNLOCK WITH PRO" in the CTA slot.

class _FreeFlowCard extends StatelessWidget {
  final VoidCallback onTap;
  const _FreeFlowCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(color: AppColors.surface3, width: 1),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Text + CTA, left.
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.all(Sp.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 6, height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Live training'.toUpperCase(),
                          style: AppTypography.label.copyWith(
                            color: AppColors.red,
                            fontSize: 10.5,
                            letterSpacing: 2.6,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'FREE FLOW',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 30,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        height: 1.0,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Any type of woman. Real-time replies. Lucien steps '
                      'in the moment you slip.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // CTA always reads "Go Live" — never "Unlock With
                    // Pro". The handler does the gating: first tap on
                    // free tier consumes the free session and opens
                    // Free Flow; subsequent taps route to the paywall.
                    // Painting the button as locked would just kill
                    // the tap intent on the main event of the tab.
                    PrimaryCta(
                      label: 'Go Live',
                      icon: Icons.graphic_eq_rounded,
                      locked: false,
                      onTap: onTap,
                    ),
                  ],
                ),
              ),
            ),
            // ── Woman portrait, right.
            Expanded(
              flex: 4,
              child: SizedBox(
                height: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      MirrorlyAssets.freeFlowHer,
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.2),
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.surface1,
                        alignment: Alignment.center,
                        child: const Icon(Icons.face_3_rounded,
                            size: 48, color: AppColors.surface3),
                      ),
                    ),
                    // Left-edge fade so text never reads against a
                    // bright patch of the portrait.
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              AppColors.surface2.withOpacity(0.85),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.35],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
