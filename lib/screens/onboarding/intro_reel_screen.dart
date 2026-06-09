import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';

/// Cinematic intro reel — the first thing a brand-new user sees before
/// the proper onboarding. Black surface, italic Playfair serif, sharp
/// red accents, one beat per second, boom-boom-boom like a movie cold-
/// open. Promise the whole product in 10 seconds:
///
///   1. brand dot
///   2. LOOKS                (face icon)
///   3. "get her attention."
///   4. GAME                 (flame icon)
///   5. "closes the deal."
///   6. (breath)
///   7. "maxx your looks."
///   8. "train the rizz."
///   9. "live voice roleplay."
///  10. "until you're unavoidable."  (red)
///  11. CTA — begin
///
/// Pushed before /onboarding (the existing three-page onboard) or
/// straight to /scan depending on first-launch state.
class IntroReelScreen extends StatefulWidget {
  /// Where to go when the user taps BEGIN or the reel finishes. Defaults
  /// to the gender picker → scan flow.
  final String next;
  const IntroReelScreen({
    super.key,
    this.next = '/onboarding/gender',
  });

  @override
  State<IntroReelScreen> createState() => _IntroReelScreenState();
}

class _IntroReelScreenState extends State<IntroReelScreen> {
  int _beat = 0;
  Timer? _timer;

  // Timing for each beat. Tight — every beat 800-900ms with the last
  // settling longer so the CTA can land. The whole reel runs ~9s.
  static const _beatMs = 850;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _timer = Timer.periodic(const Duration(milliseconds: _beatMs), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_beat >= _beats.length - 1) {
        t.cancel();
        return;
      }
      setState(() => _beat++);
      // Subtle haptic on the climactic red line + the CTA so the body
      // matches the boom.
      if (_beats[_beat].haptic) HapticFeedback.lightImpact();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _begin() {
    HapticFeedback.mediumImpact();
    context.go(widget.next);
  }

  void _skip() {
    HapticFeedback.selectionClick();
    context.go(widget.next);
  }

  @override
  Widget build(BuildContext context) {
    final beat = _beats[_beat];
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Skip pill — top right.
            Positioned(
              top: 14, right: 18,
              child: GestureDetector(
                onTap: _skip,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('SKIP',
                    style: GoogleFonts.inter(
                      color: AppColors.textTertiary,
                      fontSize: 11, letterSpacing: 2.6,
                      fontWeight: FontWeight.w800,
                    )),
                ),
              ),
            ),

            // Centred beat content.
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve:  Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) {
                    return FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.08),
                          end:   Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    );
                  },
                  child: _BeatView(
                    key:  ValueKey(_beat),
                    beat: beat,
                  ),
                ),
              ),
            ),

            // Beat dot progress at the bottom.
            Positioned(
              bottom: 26, left: 0, right: 0,
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _beats.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 280),
                          width:  i == _beat ? 16 : 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: i <= _beat
                              ? AppColors.red
                              : AppColors.surface3,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // CTA — appears only on the last beat.
            if (_beats[_beat].isCta)
              Positioned(
                bottom: 60, left: 28, right: 28,
                child: _BeginButton(onTap: _begin)
                    .animate()
                    .fadeIn(duration: 360.ms, delay: 80.ms)
                    .slideY(begin: 0.18, end: 0, duration: 360.ms,
                        curve: Curves.easeOut),
              ),
          ],
        ),
      ),
    );
  }
}

class _BeatView extends StatelessWidget {
  final _Beat beat;
  const _BeatView({super.key, required this.beat});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (beat.icon != null) ...[
          Icon(beat.icon,
            color: beat.iconColor ?? AppColors.red,
            size: beat.iconSize),
          const SizedBox(height: 24),
        ],
        if (beat.eyebrow != null) ...[
          Text(beat.eyebrow!,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: AppColors.textTertiary,
              fontSize: 12, letterSpacing: 3.8,
              fontWeight: FontWeight.w800,
            )),
          const SizedBox(height: 14),
        ],
        Text(beat.text,
          textAlign: TextAlign.center,
          style: GoogleFonts.playfairDisplay(
            color: beat.color,
            fontSize: beat.size,
            height: 1.0,
            letterSpacing: -1.4,
            fontStyle: beat.italic ? FontStyle.italic : FontStyle.normal,
            fontWeight: FontWeight.w800,
          ))
            .animate()
            .fadeIn(duration: 360.ms)
            .scale(
              begin: const Offset(0.94, 0.94),
              end:   const Offset(1.0, 1.0),
              duration: 360.ms,
              curve: Curves.easeOutCubic,
            ),
      ],
    );
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
          padding: const EdgeInsets.symmetric(vertical: 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.red.withValues(alpha: 0.45),
                blurRadius: 32, spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('BEGIN',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 15, letterSpacing: 4.0,
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

class _Beat {
  final String text;
  final String? eyebrow;
  final IconData? icon;
  final double iconSize;
  final Color? iconColor;
  final Color color;
  final double size;
  final bool italic;
  final bool haptic;
  final bool isCta;
  const _Beat({
    required this.text,
    this.eyebrow,
    this.icon,
    this.iconSize = 56,
    this.iconColor,
    this.color  = Colors.white,
    this.size   = 56,
    this.italic = true,
    this.haptic = false,
    this.isCta  = false,
  });
}

// The reel. Each entry is one beat; they swap every ~850ms.
const _beats = <_Beat>[
  _Beat(
    text: 'Mirrorly.',
    color: AppColors.red,
    size: 56,
    italic: true,
    haptic: true,
  ),
  _Beat(
    text: 'LOOKS',
    icon: Icons.face_retouching_natural_outlined,
    iconColor: Colors.white,
    iconSize: 56,
    size: 72,
    italic: false,
  ),
  _Beat(
    text: 'get her attention.',
    color: AppColors.red,
    size: 38,
    italic: true,
  ),
  _Beat(
    text: 'GAME',
    icon: Icons.local_fire_department_rounded,
    iconColor: AppColors.red,
    iconSize: 60,
    size: 72,
    italic: false,
    haptic: true,
  ),
  _Beat(
    text: 'closes the deal.',
    color: AppColors.red,
    size: 38,
    italic: true,
  ),
  _Beat(
    text: 'Maxx your looks.',
    icon: Icons.face_retouching_natural_outlined,
    iconColor: Colors.white,
    iconSize: 36,
    size: 48,
    italic: true,
  ),
  _Beat(
    text: 'Train the rizz.',
    icon: Icons.bolt_rounded,
    iconColor: AppColors.red,
    iconSize: 40,
    size: 48,
    italic: true,
  ),
  _Beat(
    text: 'Live voice roleplay.',
    icon: Icons.graphic_eq_rounded,
    iconColor: AppColors.red,
    iconSize: 40,
    size: 48,
    italic: true,
  ),
  _Beat(
    text: 'Until you\'re\nunavoidable.',
    color: AppColors.red,
    size: 56,
    italic: true,
    haptic: true,
  ),
  _Beat(
    text: 'Looks + game.',
    eyebrow: 'YOUR ARSENAL',
    icon: Icons.favorite_rounded,
    iconColor: AppColors.red,
    iconSize: 36,
    size: 44,
    italic: true,
    isCta: true,
  ),
];
