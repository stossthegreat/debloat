import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/analytics_service.dart';
import '../../services/paywall_gate.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/mirrorly_components.dart';

/// RIZZ tab — three red cards, three flood-gate states.
///
/// Bro: "they only get ONE free use of the roleplay [game tab] and ONE
/// use of screenshot rizz; the other two rizz cards i.e LINES and CHAT
/// are LOCKED. Get this right, there's no room for mistakes."
///
/// Free-tier matrix on this tab:
///   · UPLOAD A SCREENSHOT  — 1 free pass, then paywall on every tap.
///   · GIMME A PICKUP LINE  — locked outright (paywall on every tap).
///   · CHAT WITH MIRRORLY   — locked outright (paywall on every tap).
///
/// Subscribers / kBypassPaywall ignore every lock here. The actual
/// per-card gate is re-checked inside each destination screen too, so
/// a deep link to /lines or /rizz-chat can never bypass the wall.
class RizzTabScreen extends StatefulWidget {
  const RizzTabScreen({super.key});

  @override
  State<RizzTabScreen> createState() => _RizzTabScreenState();
}

class _RizzTabScreenState extends State<RizzTabScreen> {
  bool _pro = false;
  bool _screenshotUsed = false;
  bool _loaded = false;
  /// Mirrors the Looks-tab masthead streak — the bigger of the
  /// triple-pillar streak (LOOKS+AURA+GAME hit on consecutive days)
  /// and whatever protocol streak the user is currently riding.
  /// Triple streak is the primary signal; we just read its
  /// SharedPref directly so the Rizz tab doesn't need to spin up
  /// ProtocolService.
  int _dayStreak = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final pro = await PaywallGate.isPro();
    final ssUsed = await PaywallGate.rizzScreenshotCapReached();
    final prefs = await SharedPreferences.getInstance();
    final streak = prefs.getInt('triple_streak_count') ?? 0;
    if (!mounted) return;
    setState(() {
      _pro = pro;
      _screenshotUsed = ssUsed;
      _dayStreak = streak;
      _loaded = true;
    });
  }

  Future<void> _openPaywall(String source) async {
    HapticFeedback.mediumImpact();
    await context.push('/paywall', extra: {'source': source});
    if (mounted) _refresh();
  }

  Future<void> _tapScreenshot() async {
    HapticFeedback.selectionClick();
    // ignore: discarded_futures
    AnalyticsService.rizzCardTapped('screenshot');
    if (!_pro && _screenshotUsed) {
      // ignore: discarded_futures
      AnalyticsService.rizzBlockedFreeCap('screenshot');
      await _openPaywall('rizz_screenshot_capped');
      return;
    }
    await context.push('/rizz', extra: const RizzCardAction.upload());
    if (mounted) _refresh();
  }

  Future<void> _tapLines() async {
    HapticFeedback.selectionClick();
    // ignore: discarded_futures
    AnalyticsService.rizzCardTapped('lines');
    if (!_pro) {
      // ignore: discarded_futures
      AnalyticsService.rizzBlockedFreeCap('lines');
      await _openPaywall('rizz_lines_locked');
      return;
    }
    await context.push('/lines');
  }

  Future<void> _tapChat() async {
    HapticFeedback.selectionClick();
    // ignore: discarded_futures
    AnalyticsService.rizzCardTapped('chat');
    if (!_pro) {
      // ignore: discarded_futures
      AnalyticsService.rizzBlockedFreeCap('chat');
      await _openPaywall('rizz_chat_locked');
      return;
    }
    await context.push('/rizz-chat');
  }

  @override
  Widget build(BuildContext context) {
    // Lock badges only paint for non-pro users. _LatestSnapshot-style
    // identical pattern to the game tab — load state then render.
    final showScreenshotLock = _loaded && !_pro && _screenshotUsed;
    final showLinesLock      = _loaded && !_pro;
    final showChatLock       = _loaded && !_pro;

    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            // Bro v5: "take rizz title and subtitle off — add settings
            // top right of screen like looks tab." Settings cog sits
            // in a thin top row; the cards begin immediately under.
            // v7 graft: streak flame + progress chart icon riding the
            // same row to the LEFT of the cog so the user can jump to
            // Progress and feel their streak from anywhere in the app.
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
              child: Row(
                children: [
                  const Spacer(),
                  if (_dayStreak > 0) ...[
                    _RizzStreakBadge(days: _dayStreak),
                    const SizedBox(width: 8),
                  ],
                  _RizzProgressChip(
                      onTap: () => context.push('/progress')),
                  const SizedBox(width: 8),
                  _RizzSettingsCog(
                      onTap: () => context.push('/settings')),
                ],
              ),
            ),
            const SizedBox(height: 36),

            // Bro v9: ImHim Keyboard hero. The "rizz from anywhere"
            // surface — install the iOS keyboard extension and any
            // screenshot in any app generates three replies inline.
            // Lives ABOVE the three legacy cards because it's the
            // bigger product story; the cards are still here as the
            // fallback flow when the user hasn't installed the
            // keyboard yet (or is on Android).
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: _KeyboardHeroCard(
                onTap: () {
                  HapticFeedback.selectionClick();
                  // ignore: discarded_futures
                  AnalyticsService.keyboardInstallTileTapped('rizz_tab');
                  context.push('/keyboard-install');
                },
              ),
            ).animate().fadeIn(duration: 360.ms)
              .slideY(begin: 0.02, end: 0, duration: 360.ms,
                  curve: Curves.easeOut),

            const SizedBox(height: 28),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: _RizzCard(
                icon:     Icons.center_focus_strong_rounded,
                title:    'Upload a screenshot',
                subtitle: showScreenshotLock
                    ? 'Free preview used — unlock with Pro'
                    : 'Get rizz on how to respond',
                onTap:    _tapScreenshot,
                locked:   showScreenshotLock,
              ),
            ).animate().fadeIn(delay: 80.ms, duration: 360.ms)
              .slideY(begin: 0.02, end: 0, duration: 360.ms,
                  curve: Curves.easeOut),

            const SizedBox(height: 28),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: _RizzCard(
                icon:     Icons.chat_bubble_outline_rounded,
                title:    'Gimme a pickup line',
                subtitle: showLinesLock
                    ? 'Pro only — unlock the arsenal'
                    : 'Curated arsenal of killer rizz',
                onTap:    _tapLines,
                locked:   showLinesLock,
              ),
            ).animate().fadeIn(delay: 120.ms, duration: 360.ms)
              .slideY(begin: 0.02, end: 0, duration: 360.ms,
                  curve: Curves.easeOut),

            const SizedBox(height: 28),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: _RizzCard(
                icon:     Icons.auto_awesome_rounded,
                title:    'Rizz Chat',
                subtitle: showChatLock
                    ? 'Pro only — unlock the coach'
                    : 'Ask anything. We coach.',
                onTap:    _tapChat,
                locked:   showChatLock,
                badge:    showChatLock ? null : 'NEW',
              ),
            ).animate().fadeIn(delay: 240.ms, duration: 360.ms)
              .slideY(begin: 0.02, end: 0, duration: 360.ms,
                  curve: Curves.easeOut),
          ],
        ),
      ),
    );
  }
}

/// Routing payload for the upload-screenshot card. Reuses the same
/// /rizz generator route; the boolean tells it to fire the image
/// picker on first frame so the user lands inside the iOS photo
/// sheet without an extra tap.
class RizzCardAction {
  final bool launchUpload;
  const RizzCardAction.upload() : launchUpload = true;
}

/// Local settings-cog widget — circular, surface1 background, matches
/// the Looks tab _MastheadCog so both tabs read as the same chrome
/// language.
class _RizzStreakBadge extends StatelessWidget {
  final int days;
  const _RizzStreakBadge({required this.days});

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

class _RizzProgressChip extends StatelessWidget {
  final VoidCallback onTap;
  const _RizzProgressChip({required this.onTap});

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

class _RizzSettingsCog extends StatelessWidget {
  final VoidCallback onTap;
  const _RizzSettingsCog({required this.onTap});

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

/// One of the three red cards. Big icon-on-the-left layout — the
/// composition matches PlugAI / Rizz exactly but in the Mirrorly
/// black + red + white voice. Italic Playfair title to keep brand
/// consistency with the rest of the app's editorial cards.
///
/// `locked` flips the surface to a desaturated, lock-iconned variant
/// so a free user instantly reads "paywall" before they tap.
class _RizzCard extends StatelessWidget {
  final IconData     icon;
  final String       title;
  final String       subtitle;
  final VoidCallback onTap;
  final String?      badge;
  final bool         locked;
  const _RizzCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final surface = locked
        ? AppColors.surface1
        : AppColors.red;
    final iconColor = locked
        ? AppColors.textSecondary
        : Colors.white;
    final titleColor = locked
        ? AppColors.textPrimary
        : Colors.white;
    final subtitleColor = locked
        ? AppColors.textTertiary
        : Colors.white.withValues(alpha: 0.82);
    final shadowColor = locked
        ? Colors.black.withValues(alpha: 0.0)
        : AppColors.red.withValues(alpha: 0.4);

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            splashColor: Colors.white.withValues(alpha: 0.08),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 26, 22, 26),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: locked
                    ? Border.all(
                        color: AppColors.red.withValues(alpha: 0.32),
                        width: 0.9)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 30, spreadRadius: 0,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Icon(icon, color: iconColor, size: 54),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                          style: GoogleFonts.playfairDisplay(
                            color: titleColor,
                            fontSize: 24, height: 1.1,
                            letterSpacing: -0.4,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w800,
                          )),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (locked) ...[
                              Icon(Icons.lock_rounded,
                                  size: 13,
                                  color: AppColors.red.withValues(alpha: 0.85)),
                              const SizedBox(width: 5),
                            ],
                            Expanded(
                              child: Text(subtitle,
                                style: GoogleFonts.inter(
                                  color: subtitleColor,
                                  fontSize: 14, height: 1.35,
                                  fontWeight: FontWeight.w500,
                                )),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // NEW or PRO badge — small pill in the top-left corner.
          if (badge != null)
            Positioned(
              top: -8, left: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 10, offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(badge!,
                  style: GoogleFonts.inter(
                    color: AppColors.red,
                    fontSize: 10, letterSpacing: 2.4,
                    fontWeight: FontWeight.w900,
                  )),
              ),
            ),
          // PRO lock pill (top-right) when locked — adds a second
          // visual cue so the free user reads "wall" instantly.
          if (locked)
            Positioned(
              top: -8, right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.red,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text('PRO',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 10, letterSpacing: 2.4,
                    fontWeight: FontWeight.w900,
                  )),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Keyboard hero — the elite "rizz from anywhere" card. Slightly taller
//  than the legacy Rizz cards and lit with a soft red glow so the eye
//  lands on it before the three smaller cards below. Italic Playfair
//  headline, downward chevron hint.
// ═══════════════════════════════════════════════════════════════════════════
class _KeyboardHeroCard extends StatelessWidget {
  final VoidCallback onTap;
  const _KeyboardHeroCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [
                AppColors.red.withValues(alpha: 0.28),
                AppColors.red.withValues(alpha: 0.10),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.55), width: 1.0),
            boxShadow: [
              BoxShadow(
                color: AppColors.red.withValues(alpha: 0.22),
                blurRadius: 30, spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.red.withValues(alpha: 0.20),
                  border: Border.all(
                    color: AppColors.red.withValues(alpha: 0.6), width: 0.9),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.keyboard_alt_rounded,
                    color: AppColors.red, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rizz from anywhere.',
                      style: GoogleFonts.playfairDisplay(
                        color: Colors.white,
                        fontSize: 19, height: 1.08,
                        letterSpacing: -0.5,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Install the ImHim keyboard — three replies on any '
                      'screenshot, inside iMessage, Hinge, Tinder.',
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 12.5, height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
