import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/analytics_service.dart';
import '../../services/paywall_gate.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/imhim_wordmark.dart';
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
            // v274 — keep ImHim wordmark + right-side chip stack.
            // Subheader ("Looks get attention. Game keeps it.")
            // removed per bro: "take the sub header out of rizz
            // tab not the ImHim, just the sub header." The Looks
            // tab keeps its subhead because it carries the brand
            // pitch on first impression; the Rizz tab doesn't need
            // it (the three cards already say what the tab is).
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const ImHimWordmark(fontSize: 34),
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
            // v275 — gap to first card pushed 36 → 80 per bro:
            // "push these three cards down a bit." With the subhead
            // gone (v274) the wordmark was floating alone right
            // above the first card; the new gap puts the cards in
            // the lower 2/3 of the screen where the thumb naturally
            // sits.
            const SizedBox(height: 80),

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
                icon:     Icons.bolt_rounded,
                title:    'Pickup line',
                subtitle: showLinesLock
                    ? 'Pro only — one banger at a time'
                    : 'One at a time. Regenerate. Done.',
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

