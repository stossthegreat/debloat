import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/rizz_lines.dart';
import '../../../services/paywall_gate.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/common/imhim_wordmark.dart';

/// v298 — PICKUP LINE.
///
/// Bro: "kill lines. instead make a tab that you press pickup line
/// and it gives you one at a time then you press regenerate or
/// different presets. only the greatest littlest rizz lines u know
/// — rizz lines just one at a time."
///
/// Replaces the v1 LinesScreen (tabbed grid of all categories) with
/// a single-card, one-at-a-time slot machine. Big italic Playfair
/// hero, MOVE LABEL underneath, REGENERATE + COPY pinned. Preset
/// chips along the bottom filter the pool — ALL by default, then
/// OPENERS / TEASE / HEAT / COLD / CLOSE / CHEESY / CHARM.
///
/// Lives at /lines (kept the route so existing deep links from
/// the Rizz tab card don't break).
class PickupLineScreen extends StatefulWidget {
  const PickupLineScreen({super.key});

  @override
  State<PickupLineScreen> createState() => _PickupLineScreenState();
}

class _PickupLineScreenState extends State<PickupLineScreen> {
  final _rng = math.Random();

  /// Category slug currently selected. Empty string = ALL (every
  /// category's lines flatten into one pool). Slug values match
  /// RizzArsenal.categories[i].slug so the filter is a direct
  /// lookup.
  String _activeSlug = '';

  /// The line currently on screen. Null at first build until
  /// [_roll] picks one. Stored separately from the pool so we can
  /// animate the rotation without re-deriving the filter set.
  RizzLine? _current;

  /// Track the last few lines we showed so consecutive REGENERATE
  /// taps never re-show the same one and (when the pool is big
  /// enough) don't repeat recently. Capped at 12 entries.
  final _recent = <String>[];
  static const _recentMax = 12;

  @override
  void initState() {
    super.initState();
    // Bounce non-pro deep links to paywall on mount. Same gate the
    // old LinesScreen had — pickup lines are Pro-only.
    WidgetsBinding.instance.addPostFrameCallback((_) => _gate());
    _roll();
  }

  Future<void> _gate() async {
    final pro = await PaywallGate.isPro();
    if (!mounted || pro) return;
    context.pushReplacement('/paywall',
        extra: {'source': 'rizz_lines_locked'});
  }

  /// Flatten the arsenal into the active pool. ALL = every line,
  /// otherwise just the chosen category. Returns at least one line
  /// even if the pool somehow ends up empty (defensive — the
  /// arsenal ships with ≥ 5 lines per category).
  List<RizzLine> _pool() {
    if (_activeSlug.isEmpty) {
      return [
        for (final c in RizzArsenal.categories) ...c.lines,
      ];
    }
    final cat = RizzArsenal.categories.firstWhere(
      (c) => c.slug == _activeSlug,
      orElse: () => RizzArsenal.categories.first,
    );
    return cat.lines;
  }

  /// Pick a new line from the active pool, avoiding the recent
  /// rotation. Sets state to animate the swap.
  void _roll() {
    final pool = _pool();
    if (pool.isEmpty) return;
    // Build the candidate set — anything not in the recent history.
    final fresh = pool.where((l) => !_recent.contains(l.text)).toList();
    final pick = (fresh.isEmpty ? pool : fresh)[_rng.nextInt(
        (fresh.isEmpty ? pool : fresh).length)];
    setState(() => _current = pick);
    _recent.add(pick.text);
    while (_recent.length > _recentMax) {
      _recent.removeAt(0);
    }
  }

  Future<void> _copy() async {
    final line = _current;
    if (line == null) return;
    HapticFeedback.mediumImpact();
    await Clipboard.setData(ClipboardData(text: line.text));
    // v301 — stamp the pickup-line daily flag the moment the user
    // actually copies a line. Drives the Ascend tab's "DROP A
    // LINE" daily mission tick. Same shape as looks_done_ymd /
    // rizz_done_ymd / game_done_ymd.
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setInt(
        'pickup_line_done_ymd',
        now.year * 10000 + now.month * 100 + now.day,
      );
    } catch (_) {/* best-effort */}
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Copied. Send it.',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 14, fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          )),
      backgroundColor: AppColors.red,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 1600),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ));
  }

  void _selectSlug(String slug) {
    if (_activeSlug == slug) return;
    HapticFeedback.selectionClick();
    setState(() => _activeSlug = slug);
    _recent.clear();
    _roll();
  }

  void _regenerate() {
    HapticFeedback.lightImpact();
    _roll();
  }

  @override
  Widget build(BuildContext context) {
    final line = _current;
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header strip — v300 carries the ImHim wordmark
            // so the screen reads as branded the moment the user
            // screenshots a line for their group chat.
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28, minHeight: 28),
                  ),
                  const SizedBox(width: 6),
                  const ImHimWordmark(fontSize: 22, letterSpacing: -0.5),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.red.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('PICKUP LINE',
                      style: GoogleFonts.inter(
                        color: AppColors.red,
                        fontSize: 9, letterSpacing: 2.4,
                        fontWeight: FontWeight.w900,
                      )),
                  ),
                  const Spacer(),
                  Text(_activeSlug.isEmpty
                      ? 'ALL'
                      : _activeSlug.toUpperCase(),
                    style: GoogleFonts.inter(
                      color: AppColors.textTertiary,
                      fontSize: 10, letterSpacing: 2.4,
                      fontWeight: FontWeight.w800,
                    )),
                ],
              ),
            ),

            // ── Hero line. Vertically centred. Tap-to-copy. Italic
            //    Playfair for the texter-quote feel.
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: GestureDetector(
                    onTap: _copy,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, anim) =>
                          FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.04),
                                end:   Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          ),
                      child: line == null
                          ? const SizedBox.shrink(key: ValueKey('empty'))
                          : Column(
                              key: ValueKey(line.text),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // The opening quotation mark sits as a
                                // muted dropped glyph so the line reads
                                // as a quote without competing with the
                                // copy itself.
                                Text('"',
                                  style: GoogleFonts.playfairDisplay(
                                    color: AppColors.red.withValues(
                                        alpha: 0.55),
                                    fontSize: 80, height: 0.5,
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w900,
                                  )),
                                const SizedBox(height: 8),
                                Text(line.text,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.playfairDisplay(
                                    color: Colors.white,
                                    fontSize: 30, height: 1.25,
                                    letterSpacing: -0.6,
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w700,
                                  )),
                                const SizedBox(height: 26),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.red.withValues(
                                        alpha: 0.16),
                                    borderRadius:
                                        BorderRadius.circular(99),
                                    border: Border.all(
                                      color: AppColors.red.withValues(
                                          alpha: 0.5),
                                      width: 0.8),
                                  ),
                                  child: Text(line.tag.toUpperCase(),
                                    style: GoogleFonts.inter(
                                      color: AppColors.red,
                                      fontSize: 10, letterSpacing: 2.4,
                                      fontWeight: FontWeight.w900,
                                    )),
                                ),
                                const SizedBox(height: 14),
                                Text('TAP THE LINE TO COPY',
                                  style: GoogleFonts.inter(
                                    color: AppColors.textTertiary,
                                    fontSize: 9.5, letterSpacing: 2.4,
                                    fontWeight: FontWeight.w800,
                                  )),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),

            // ── REGENERATE + COPY action pair
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _ActionButton(
                      label: 'REGENERATE',
                      icon: Icons.refresh_rounded,
                      filled: true,
                      onTap: _regenerate,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: _ActionButton(
                      label: 'COPY',
                      icon: Icons.copy_rounded,
                      filled: false,
                      onTap: _copy,
                    ),
                  ),
                ],
              ),
            ),

            // ── Preset chip strip
            SizedBox(
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                children: [
                  _PresetChip(
                    label:  'ALL',
                    active: _activeSlug.isEmpty,
                    onTap:  () => _selectSlug(''),
                  ),
                  const SizedBox(width: 8),
                  for (final c in RizzArsenal.categories) ...[
                    _PresetChip(
                      label:  c.label,
                      active: _activeSlug == c.slug,
                      onTap:  () => _selectSlug(c.slug),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : AppColors.red;
    final bg = filled ? AppColors.red : Colors.transparent;
    final border = filled
        ? null
        : Border.all(color: AppColors.red, width: 1.2);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(99),
            border: border,
            boxShadow: filled
                ? [BoxShadow(
                    color: AppColors.red.withValues(alpha: 0.42),
                    blurRadius: 18, spreadRadius: 0)]
                : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: fg, size: 17),
              const SizedBox(width: 8),
              Text(label,
                style: GoogleFonts.inter(
                  color: fg,
                  fontSize: 12.5, letterSpacing: 2.4,
                  fontWeight: FontWeight.w900,
                )),
            ],
          ),
        )
        .animate(target: filled ? 1 : 0)
        .scale(begin: const Offset(1, 1), end: const Offset(1, 1)),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _PresetChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? AppColors.red.withValues(alpha: 0.18)
                : AppColors.surface1,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: active
                  ? AppColors.red.withValues(alpha: 0.7)
                  : AppColors.divider,
              width: active ? 1.2 : 0.6),
          ),
          child: Text(label,
            style: GoogleFonts.inter(
              color: active ? AppColors.red : AppColors.textSecondary,
              fontSize: 11, letterSpacing: 2.0,
              fontWeight: FontWeight.w900,
            )),
        ),
      ),
    );
  }
}
