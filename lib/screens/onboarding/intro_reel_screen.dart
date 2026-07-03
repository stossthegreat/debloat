import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';

/// Cinematic onboarding reel — an 8-screen cold-open that plays like a
/// movie. Each screen reveals its lines one at a time (fade + rise), with
/// deliberate holds: the gut-punch lines sit longer so they land. Screens
/// 4-7 carry a visual asset (glow-up / roleplay / message rewrite / the
/// future) that fades in after the copy; assets degrade to a clean
/// placeholder so the reel runs before the files are dropped in.
///
/// Tap anywhere to move to the next screen; SKIP (top-right) exits to the
/// flow. The last screen reveals BEGIN.
class IntroReelScreen extends StatefulWidget {
  /// Route to advance to when the user taps BEGIN or SKIP.
  final String next;
  const IntroReelScreen({super.key, this.next = '/onboarding/gender'});

  @override
  State<IntroReelScreen> createState() => _IntroReelScreenState();
}

class _IntroReelScreenState extends State<IntroReelScreen> {
  int  _screen = 0;
  int  _revealed = 0;     // how many lines of the current screen are visible
  bool _showAsset = false;
  bool _showCaption = false;
  bool _showBegin = false;
  Timer? _t;

  // Every line fades in over this long; each line then holds for its own
  // `holdMs` before the next drops. Movie pacing: unhurried, with air.
  static const _beatFade = 560;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _play();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  // ── Playback ────────────────────────────────────────────────────────
  void _play() => _revealBeat(0);

  void _revealBeat(int i) {
    final s = _screens[_screen];
    if (i >= s.beats.length) {
      _afterBeats();
      return;
    }
    setState(() => _revealed = i + 1);
    _t = Timer(Duration(milliseconds: _beatFade + s.beats[i].holdMs), () {
      if (mounted) _revealBeat(i + 1);
    });
  }

  void _afterBeats() {
    final s = _screens[_screen];
    if (s.asset != null && !_showAsset) {
      setState(() => _showAsset = true);
      _t = Timer(const Duration(milliseconds: 1300),
          () { if (mounted) _afterAsset(); });
      return;
    }
    _afterAsset();
  }

  void _afterAsset() {
    final s = _screens[_screen];
    if (s.caption != null && !_showCaption) {
      setState(() => _showCaption = true);
      _t = Timer(const Duration(milliseconds: 1500),
          () { if (mounted) _afterCaption(); });
      return;
    }
    _afterCaption();
  }

  void _afterCaption() {
    if (_screen >= _screens.length - 1) {
      setState(() => _showBegin = true);
      return;
    }
    _t = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        _screen++;
        _revealed = 0;
        _showAsset = false;
        _showCaption = false;
      });
      _play();
    });
  }

  /// Tap anywhere → hurry to the next screen (or, on the last screen,
  /// reveal everything + the BEGIN button).
  void _tapAdvance() {
    HapticFeedback.selectionClick();
    _t?.cancel();
    if (_screen >= _screens.length - 1) {
      final s = _screens[_screen];
      setState(() {
        _revealed     = s.beats.length;
        _showAsset    = s.asset != null;
        _showCaption  = s.caption != null;
        _showBegin    = true;
      });
      return;
    }
    setState(() {
      _screen++;
      _revealed = 0;
      _showAsset = false;
      _showCaption = false;
      _showBegin = false;
    });
    _play();
  }

  void _go() {
    HapticFeedback.mediumImpact();
    context.go(widget.next);
  }

  // ── Build ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _showBegin ? null : _tapAdvance,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // Faint red halo behind the copy — cinematic depth.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.25),
                    radius: 1.1,
                    colors: [
                      AppColors.red.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            SafeArea(
              child: Stack(
                children: [
                  // SKIP — top-right.
                  Positioned(
                    top: 6, right: 12,
                    child: GestureDetector(
                      onTap: _go,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text('SKIP',
                          style: GoogleFonts.inter(
                            color: AppColors.textTertiary,
                            fontSize: 11, letterSpacing: 2.6,
                            fontWeight: FontWeight.w800,
                          )),
                      ),
                    ),
                  ),

                  // The reel body — cross-fades between screens.
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(30, 40, 30, 90),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 480),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: _ScreenView(
                          key:         ValueKey(_screen),
                          screen:      _screens[_screen],
                          revealed:    _revealed,
                          showAsset:   _showAsset,
                          showCaption: _showCaption,
                        ),
                      ),
                    ),
                  ),

                  // BEGIN — only once the finale has fully landed.
                  if (_showBegin)
                    Positioned(
                      bottom: 54, left: 28, right: 28,
                      child: _BeginButton(onTap: _go)
                          .animate()
                          .fadeIn(duration: 460.ms)
                          .slideY(begin: 0.2, end: 0,
                              duration: 460.ms, curve: Curves.easeOut),
                    ),

                  // Progress dashes.
                  Positioned(
                    bottom: 22, left: 0, right: 0,
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < _screens.length; i++)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2.5),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 240),
                                width:  i == _screen ? 14 : 4,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: i <= _screen
                                      ? AppColors.red
                                      : AppColors.surface3,
                                  borderRadius: BorderRadius.circular(3),
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
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  One screen — eyebrow, stacked lines, optional asset, optional caption.
// ══════════════════════════════════════════════════════════════════════
class _ScreenView extends StatelessWidget {
  final _Screen screen;
  final int  revealed;
  final bool showAsset;
  final bool showCaption;
  const _ScreenView({
    super.key,
    required this.screen,
    required this.revealed,
    required this.showAsset,
    required this.showCaption,
  });

  @override
  Widget build(BuildContext context) {
    final maxAssetH = MediaQuery.of(context).size.height * 0.30;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (screen.label != null) ...[
          Text(screen.label!,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: AppColors.red,
              fontSize: 12, letterSpacing: 4.2,
              fontWeight: FontWeight.w900,
            )).animate().fadeIn(duration: 360.ms),
          const SizedBox(height: 22),
        ],

        // Stacked lines — each revealed one keeps a stable key so it
        // animates in exactly once and never replays on rebuild.
        for (var i = 0; i < revealed; i++) ...[
          if (i > 0) SizedBox(height: screen.beats[i].gapBefore),
          _BeatView(key: ValueKey('b$i'), beat: screen.beats[i]),
        ],

        // Visual asset (screens 4-7).
        if (showAsset && screen.asset != null) ...[
          const SizedBox(height: 26),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxAssetH),
            child: _AssetView(path: screen.asset!),
          ),
        ],

        // Bottom caption.
        if (showCaption && screen.caption != null) ...[
          const SizedBox(height: 22),
          Text(screen.caption!,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 15, height: 1.4, letterSpacing: 0.2,
              fontWeight: FontWeight.w700,
            )).animate().fadeIn(duration: 520.ms)
              .slideY(begin: 0.2, end: 0, duration: 520.ms,
                  curve: Curves.easeOut),
        ],
      ],
    );
  }
}

class _BeatView extends StatelessWidget {
  final _Beat beat;
  const _BeatView({super.key, required this.beat});

  @override
  Widget build(BuildContext context) {
    return Text(beat.text,
      textAlign: TextAlign.center,
      style: GoogleFonts.playfairDisplay(
        color: beat.red ? AppColors.red : Colors.white,
        fontSize: beat.size,
        height: 1.15,
        letterSpacing: -0.8,
        fontStyle: FontStyle.italic,
        fontWeight: beat.red ? FontWeight.w900 : FontWeight.w700,
      ),
    )
        .animate()
        .fadeIn(duration: _IntroReelScreenState._beatFade.ms,
            curve: Curves.easeOutCubic)
        .slideY(begin: 0.28, end: 0,
            duration: _IntroReelScreenState._beatFade.ms,
            curve: Curves.easeOutCubic);
  }
}

class _AssetView extends StatelessWidget {
  final String path;
  const _AssetView({required this.path});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Image.asset(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.28), width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 44),
          child: const Center(
            child: Icon(Icons.play_circle_outline_rounded,
              color: Colors.white24, size: 54),
          ),
        ),
      ),
    ).animate()
      .fadeIn(duration: 620.ms)
      .scale(begin: const Offset(0.96, 0.96), end: const Offset(1, 1),
          duration: 620.ms, curve: Curves.easeOut);
  }
}

class _BeginButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BeginButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.red,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: Colors.white.withValues(alpha: 0.1),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.red.withValues(alpha: 0.45),
                blurRadius: 36, spreadRadius: 2,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('BEGIN',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 15, letterSpacing: 4.2,
                  fontWeight: FontWeight.w900,
                )),
              const SizedBox(width: 10),
              const Icon(Icons.arrow_forward_rounded,
                color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  Script model
// ══════════════════════════════════════════════════════════════════════
class _Beat {
  final String text;
  final bool   red;
  final double size;
  /// Pause after this line lands, before the next drops (ms).
  final int    holdMs;
  /// Vertical space above this line when stacked under the previous.
  final double gapBefore;
  const _Beat(
    this.text, {
    this.red = false,
    this.size = 29,
    this.holdMs = 820,
    this.gapBefore = 14,
  });
}

class _Screen {
  final String? label;
  final List<_Beat> beats;
  final String? asset;
  final String? caption;
  const _Screen({this.label, required this.beats, this.asset, this.caption});
}

// Hold tuning: … suspense lines breathe (~1.1s); the gut-punch lines sit
// ~1.8-2.0s so they land like a movie beat.
const _screens = <_Screen>[
  // 1 — THE PAIN
  _Screen(
    beats: [
      _Beat('Ever watched another guy…', holdMs: 1150),
      _Beat('…become everything you\nwanted to be?', size: 33, holdMs: 1500),
      _Beat('He walks in.\nEvery eye turns.',
          size: 20, holdMs: 1400, gapBefore: 26),
    ],
  ),

  // 2 — THE WOUND
  _Screen(
    beats: [
      _Beat('Meanwhile…', holdMs: 1100),
      _Beat('You get ignored.', holdMs: 900),
      _Beat('Left on read.', holdMs: 900),
      _Beat('Passed over.', holdMs: 1150),
      _Beat('Eventually…', size: 26, holdMs: 1050, gapBefore: 22),
      _Beat('you stop believing.', size: 26, holdMs: 1250),
      _Beat('"Maybe I\'m just not him."',
          red: true, size: 32, holdMs: 2000, gapBefore: 24),
    ],
  ),

  // 3 — THE REVEAL
  _Screen(
    beats: [
      _Beat('You weren\'t fixing\nthe whole problem.', size: 31, holdMs: 1500),
      _Beat('It isn\'t one skill.', holdMs: 1050),
      _Beat('It\'s two.', red: true, size: 48, holdMs: 1700),
      _Beat('Looks.', size: 40, holdMs: 900, gapBefore: 30),
      _Beat('Game.', red: true, size: 40, holdMs: 1500),
    ],
  ),

  // 4 — LOOKS
  _Screen(
    label: 'LOOKS',
    beats: [
      _Beat('Imagine walking\ninto a room…', size: 31, holdMs: 1250),
      _Beat('…and finally\nbeing noticed.', size: 31, holdMs: 1400),
      _Beat('Not because you got lucky.', size: 22, holdMs: 950, gapBefore: 22),
      _Beat('Because you became\nthe best version of you.',
          size: 24, holdMs: 1200),
    ],
    asset: 'assets/onboarding/looks.jpg',
    caption: 'Know exactly what to change. Then become him.',
  ),

  // 5 — GAME
  _Screen(
    label: 'GAME',
    beats: [
      _Beat('Imagine never\nfreezing again.', size: 31, holdMs: 1300),
      _Beat('Walking over.', holdMs: 850),
      _Beat('Making her laugh.', holdMs: 850),
      _Beat('Leading the conversation.', size: 26, holdMs: 1000),
      _Beat('Like you\'ve done it\na thousand times.', size: 26, holdMs: 1300),
    ],
    asset: 'assets/onboarding/game.jpg',
    caption: 'Practice until confidence becomes natural.',
  ),

  // 6 — MESSAGES
  _Screen(
    label: 'MESSAGES',
    beats: [
      _Beat('Imagine opening\nher message…', size: 31, holdMs: 1200),
      _Beat('…and smiling.', size: 31, holdMs: 1400),
      _Beat('Because you already\nknow what to say.', size: 26, holdMs: 1300),
      _Beat('No guessing. No overthinking.',
          size: 20, holdMs: 1100, gapBefore: 22),
    ],
    asset: 'assets/onboarding/messages.jpg',
    caption: 'Become the conversation she remembers.',
  ),

  // 7 — THE FUTURE
  _Screen(
    beats: [
      _Beat('Six months from now…', holdMs: 1300),
      _Beat('You won\'t be asking…', size: 26, holdMs: 1050),
      _Beat('"Why him?"', size: 30, holdMs: 1500, gapBefore: 18),
      _Beat('You\'ll be hearing…', size: 26, holdMs: 1050, gapBefore: 28),
      _Beat('"What changed?"', red: true, size: 42, holdMs: 1900, gapBefore: 18),
    ],
    asset: 'assets/onboarding/future.jpg',
  ),

  // 8 — CLOSE
  _Screen(
    beats: [
      _Beat('The man you\'ve imagined\nyour whole life…', size: 30, holdMs: 1500),
      _Beat('starts today.', red: true, size: 46, holdMs: 1500),
      _Beat('Welcome to ImHim.', size: 30, holdMs: 800, gapBefore: 34),
    ],
  ),
];
