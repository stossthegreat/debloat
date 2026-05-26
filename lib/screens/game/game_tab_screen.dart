import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../config/dev_flags.dart';
import '../../services/local_store_service.dart';
import '../../theme/auralay_app_colors.dart';
import '../../theme/auralay_app_typography.dart';
import 'arena/arena_scenes_screen.dart';
import 'council/council_chat_screen.dart';
import 'freeflow/free_flow_screen.dart';

/// THE CONSIGLIERE — tab landing.
///
/// Two cards. One promise per card. Nothing else.
///
///   THE ARENA   — walk into a scene with a woman. He cuts in when
///                 you fold.
///   THE COUNCIL — private line to Lucien. Ask him what you cannot
///                 ask anyone else.
class GameTabScreen extends StatefulWidget {
  const GameTabScreen({super.key});

  @override
  State<GameTabScreen> createState() => _GameTabScreenState();
}

class _GameTabScreenState extends State<GameTabScreen> {
  // Paywall entitlement state. Free users get one Free Flow live
  // conversation (the top card, consumed on open); The Arena and The
  // Council are pro-only. `_loaded` gates the locked visual so a paid
  // user never sees a lock flash on launch.
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
  // open), then paywall. The Arena + The Council are pro-only.
  bool get _freeFlowLocked => _loaded && !_pro && _gameUsed;
  bool get _proOnlyLocked  => _loaded && !_pro;

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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('THE CONSIGLIERE',
                    style: AppTypography.label.copyWith(
                      color: AppColors.accent,
                      fontSize: 11,
                      letterSpacing: 3.6,
                      fontWeight: FontWeight.w900,
                    )),
              ),
              const SizedBox(height: 14),
              // Rebrand from LUCIEN → Game, italic Playfair to match the
              // nav-bar label. Lucien stays the in-app character voice
              // (system prompts, coaching cards), but the tab landing now
              // reads as a section of Mirrorly, not its own app.
              Text('Game',
                  style: AppTypography.display.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 64,
                    letterSpacing: -2.2,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  )),
              const SizedBox(height: 10),
              Text('She tests you. Lucien corrects you.',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.accent,
                    fontSize: 15,
                    height: 1.4,
                    fontStyle: FontStyle.italic,
                  )),
              const SizedBox(height: 32),

              // ── FREE FLOW (live) — one free convo, then paywall ──
              _ConsigliereCard(
                topLabel:  'LIVE · REAL-TIME',
                title:     'FREE FLOW',
                subtitle:
                    'Pick who she is. Then just talk — she answers '
                    'instantly, back and forth, no waiting. Tap Lucien '
                    'to have him step in and read it.',
                cta:       'GO LIVE',
                primary:   true,
                locked:    _freeFlowLocked,
                onTap:     _onFreeFlow,
              ),
              const SizedBox(height: 14),

              // ── THE ARENA — pro only ─────────────────────────────
              _ConsigliereCard(
                topLabel:  'ROLEPLAY',
                title:     'THE ARENA',
                subtitle:
                    'Walk into a scene with a woman. She tests you. '
                    'Lucien watches. He cuts in when you fold.',
                cta:       'ENTER A SCENE',
                primary:   true,
                locked:    _proOnlyLocked,
                onTap:     _onArena,
              ),
              const SizedBox(height: 14),

              // ── THE COUNCIL — pro only ───────────────────────────
              _ConsigliereCard(
                topLabel:  'CHAT',
                title:     'THE COUNCIL',
                subtitle:
                    'A private line to Lucien. He already knows what '
                    'you are about to say. Ask him anyway.',
                cta:       'OPEN THE LINE',
                primary:   true,
                locked:    _proOnlyLocked,
                onTap:     _onCouncil,
              ),

              const SizedBox(height: 28),

              // ── The thesis ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: AppColors.surface1,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider, width: 0.6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('THE LOOP',
                        style: AppTypography.label.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 9.5,
                          letterSpacing: 2.6,
                          fontWeight: FontWeight.w900,
                        )),
                    const SizedBox(height: 8),
                    Text(
                      'Scene → mistake → Lucien cuts in → sharper move '
                      '→ retry.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 13.5,
                        height: 1.5,
                        fontStyle: FontStyle.italic,
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

class _ConsigliereCard extends StatelessWidget {
  final String topLabel;
  final String title;
  final String subtitle;
  final String cta;
  final bool primary;
  final bool locked;
  final VoidCallback onTap;

  const _ConsigliereCard({
    required this.topLabel,
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.primary,
    this.locked = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      // Material wrapper guarantees the InkWell ripple and ensures the
      // tap target is real and live. The previous GestureDetector-only
      // approach sometimes lost taps inside scroll views on iOS.
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(16),
            // Locked (pro-gated) cards drop to a flat grey border with
            // no glow so they visibly read as "blacked out".
            border: Border.all(
              color: locked
                  ? AppColors.divider
                  : (primary ? AppColors.accent : AppColors.accentBorder),
              width: locked ? 0.8 : (primary ? 1.4 : 0.8),
            ),
            boxShadow: (primary && !locked)
                ? const [
                    BoxShadow(
                      color: AppColors.accentGlow,
                      blurRadius: 36,
                      spreadRadius: -4,
                    ),
                  ]
                : const [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(topLabel,
                      style: AppTypography.label.copyWith(
                        color: locked ? AppColors.textTertiary : AppColors.accent,
                        fontSize: 10,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w900,
                      )),
                  const Spacer(),
                  Icon(locked ? Icons.lock_rounded : Icons.arrow_forward_rounded,
                      color: locked
                          ? AppColors.textTertiary
                          : (primary ? AppColors.accent : AppColors.textTertiary),
                      size: 18),
                ],
              ),
              const SizedBox(height: 12),
              Text(title,
                  style: AppTypography.display.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 32,
                    letterSpacing: -1.2,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  )),
              const SizedBox(height: 12),
              Text(subtitle,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                    height: 1.5,
                  )),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: locked
                      ? AppColors.surface3
                      : (primary
                          ? AppColors.accent.withValues(alpha: 0.16)
                          : AppColors.surface3),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                      color: locked
                          ? AppColors.divider
                          : (primary ? AppColors.accentBorder : AppColors.divider),
                      width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (locked) ...[
                      const Icon(Icons.lock_rounded,
                          color: AppColors.textSecondary, size: 13),
                      const SizedBox(width: 7),
                    ],
                    Text(locked ? 'UNLOCK WITH PRO' : cta,
                        style: AppTypography.label.copyWith(
                          color: locked
                              ? AppColors.textSecondary
                              : AppColors.accent,
                          fontSize: 10.5,
                          letterSpacing: 2.8,
                          fontWeight: FontWeight.w900,
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 280.ms).slideY(begin: 0.04, end: 0);
  }
}
