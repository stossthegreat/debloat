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
import 'council/council_chat_screen.dart';
import 'freeflow/free_flow_screen.dart';

/// THE CONSIGLIERE — tab landing.
///
/// The conversion column: Lucien hero portrait, Free Flow live training,
/// a row of roleplay archetypes (each takes the user into a scene), then
/// Lucien's feedback strip at the bottom. Council still routable from the
/// footer, but no longer eats primary real estate — the mockup is built
/// around characters, not categories.
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
    // Listen for cross-app subscription changes — same pattern as Eyes.
    LocalStoreService.proNotifier.addListener(_onProChanged);
  }

  @override
  void dispose() {
    LocalStoreService.proNotifier.removeListener(_onProChanged);
    super.dispose();
  }

  void _onProChanged() {
    if (!mounted) return;
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
  // open), then paywall. The card itself never paints as locked
  // (handler does the gating) so we don't need a _freeFlowLocked
  // getter. Arenas + Council are pro-only and DO paint as locked.
  bool get _proOnlyLocked => _loaded && !_pro;

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

  void _onCouncil() {
    if (_pro) { _open(const CouncilChatScreen()); return; }
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
            // ── Masthead — Lucien hero portrait, eyebrow + display title
            //    + subhead on the left, action chips top-right. Short
            //    height (200) so the title sits high on the screen and
            //    the Free Flow card is reachable without scrolling.
            _GameMasthead(
              onSettings: () => context.push('/settings'),
            ),

            const SizedBox(height: Sp.md),

            // ── Body line under the hero.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: Text(
                'Real situations. Real feedback. Become the man she '
                'can\'t ignore.',
                style: AppTypography.body.copyWith(
                  color: AppColors.textPrimary,
                  height: 1.45,
                ),
              ),
            ),

            const SizedBox(height: Sp.md),

            // ── FREE FLOW — the main event. Always tappable (free
            //    user gets one consumed-on-open, then paywalled). The
            //    card pulses subtly so the eye lands on it as the
            //    primary action on this tab. CTA always reads "Go
            //    Live" — never "Unlock With Pro" — because the action
            //    is always to enter Free Flow, the gating happens
            //    inside the handler.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: _FreeFlowCard(
                onTap: _onFreeFlow,
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(
                  begin: const Offset(1.0, 1.0),
                  end: const Offset(1.014, 1.014),
                  duration: 1600.ms,
                  curve: Curves.easeInOut,
                ),

            const SizedBox(height: Sp.lg),

            // ── ROLEPLAY ARENAS — section header + horizontal row.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: Row(
                children: [
                  Text(
                    'Roleplay arenas'.toUpperCase(),
                    style: AppTypography.label.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      letterSpacing: 2.6,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _onArena,
                    icon: Text(
                      'See all',
                      style: AppTypography.label.copyWith(
                        color: AppColors.red,
                        fontSize: 11,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    label: const Icon(Icons.arrow_forward_rounded,
                        size: 14, color: AppColors.red),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            SizedBox(
              height: 280,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                children: [
                  RoleplayTile(
                    name: 'The Arena',
                    line: 'She tests you. You stay calm.',
                    assetPath: MirrorlyAssets.arenaWoman,
                    locked: _proOnlyLocked,
                    onTap: _onArena,
                  ),
                  const SizedBox(width: 12),
                  RoleplayTile(
                    name: 'Ice Queen',
                    line: 'Cold. Distant. Earn her warmth.',
                    assetPath: MirrorlyAssets.iceQueen,
                    locked: _proOnlyLocked,
                    onTap: _onArena,
                  ),
                  const SizedBox(width: 12),
                  RoleplayTile(
                    name: 'Shy Girl',
                    line: 'Help her open up. Lead gently.',
                    assetPath: MirrorlyAssets.shyGirl,
                    locked: _proOnlyLocked,
                    onTap: _onArena,
                  ),
                  const SizedBox(width: 12),
                  RoleplayTile(
                    name: 'Chaos Girl',
                    line: 'Unpredictable. Keep control.',
                    assetPath: MirrorlyAssets.chaosGirl,
                    locked: _proOnlyLocked,
                    onTap: _onArena,
                  ),
                  const SizedBox(width: 12),
                  RoleplayTile(
                    name: 'The Socialite',
                    line: 'High status. Filtering hard.',
                    assetPath: MirrorlyAssets.socialite,
                    locked: _proOnlyLocked,
                    onTap: _onArena,
                  ),
                  const SizedBox(width: 12),
                  RoleplayTile(
                    name: 'The Intellectual',
                    line: 'Sharp. Skeptical. Earns it slow.',
                    assetPath: MirrorlyAssets.intellectual,
                    locked: _proOnlyLocked,
                    onTap: _onArena,
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

            const SizedBox(height: Sp.lg),

            // ── Lucien's Feedback strip.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: const FeedbackStrip(
                eyebrow: "Lucien's feedback",
                headline: 'You talk. I watch.',
                body: 'I correct what kills your chances. Short. Sharp. '
                      'Uncomfortable.',
                close: "That's how you level up.",
                assetPath: MirrorlyAssets.lucienFeedback,
              ),
            ).animate().fadeIn(delay: 280.ms, duration: 400.ms),

            const SizedBox(height: Sp.md),

            // ── Council — preserved as a low-key footer entry so the
            //    private line to Lucien stays reachable without
            //    competing with the conversion column above.
            Center(
              child: TextButton.icon(
                onPressed: _onCouncil,
                icon: const Icon(Icons.forum_outlined,
                    size: 14, color: AppColors.textTertiary),
                label: Text(
                  'Open the Council',
                  style: AppTypography.label.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 10.5,
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w700,
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

// ─── Masthead ───────────────────────────────────────────────────────
// Lucien hero portrait on the right (~55% width), eyebrow + italic
// display title + red italic subhead on the left, action chips
// (paywall + tune) layered top-right over the photo.

class _GameMasthead extends StatelessWidget {
  final VoidCallback onSettings;
  const _GameMasthead({
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Compact masthead so the title sits high on the screen and the
      // Free Flow card (the main event) is reachable without scrolling.
      // Lucien still bleeds into the right side but with a tighter crop.
      height: 200,
      child: Stack(
        children: [
          // ── Lucien portrait, right half, full bleed.
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: 0.55,
                heightFactor: 1.0,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      MirrorlyAssets.lucienHero,
                      fit: BoxFit.cover,
                      alignment: const Alignment(0.15, -0.4),
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.surface1,
                        alignment: Alignment.center,
                        child: const Icon(Icons.person_rounded,
                            size: 64, color: AppColors.surface3),
                      ),
                    ),
                    // Left-edge fade so the title block reads against
                    // the photo regardless of brightness.
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              AppColors.base,
                              AppColors.base.withOpacity(0.30),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.18, 0.45],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Title block (left). Eyebrow + italic display title with
          //    red dot + italic red subhead — same vocabulary as
          //    MirrorlyMasthead so every tab reads in one voice. Pushed
          //    high (top: 12) so it doesn't sit dead-centre in empty
          //    space.
          // Title block — uses the SAME vocabulary as MirrorlyMasthead
          // on the other tabs so Game reads in one voice with the rest
          // of the app. No "THE CONSIGLIERE" eyebrow above the title
          // (no other tab has one), no premium icon in the action row
          // (the chrome stays light).
          Positioned(
            left: Sp.lg,
            top: 16,
            right: 70,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 38,
                      fontWeight: FontWeight.w700,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textPrimary,
                      letterSpacing: -1.2,
                      height: 1.0,
                    ),
                    children: [
                      const TextSpan(text: 'Game'),
                      const TextSpan(text: '  '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: AppColors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'She tests you. Lucien corrects you.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: AppColors.red,
                    height: 1.35,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),

          // ── Action chip top-right — settings only. The paywall
          // shortcut lives on Scan + Mirror where new users land; the
          // Game tab is for users already inside the experience.
          Positioned(
            top: 12, right: Sp.lg,
            child: Row(
              children: [
                MastheadAction(
                  icon: Icons.tune,
                  onTap: onSettings,
                ),
              ],
            ),
          ),
        ],
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
