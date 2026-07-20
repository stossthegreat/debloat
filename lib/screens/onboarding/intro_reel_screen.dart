import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';

/// Cinematic onboarding reel. Black surface, italic Playfair serif,
/// red accents. Words reveal left-to-right inside each sentence
/// (140ms per word) — sentence holds for ~600ms — next sentence drops.
/// Reads like a movie cold-open. Total runtime ≈ 14s, then the CTA.
///
/// Script (final):
///   Every man knows that guy.
///   The guy the room notices.
///   The guy the room remembers.
///   The guy the room follows.
///   ─ beat ─
///   Most men think it\'s luck.
///   It\'s not.
///   ─ beat ─
///   LOOKS get attention.
///   GAME decides.
///   ─ beat ─
///   ImHim Looks gives you both. 🔥❤️
///   [BEGIN]
class IntroReelScreen extends StatefulWidget {
  /// Route to advance to when the user taps BEGIN or SKIP.
  final String next;
  const IntroReelScreen({super.key, this.next = '/onboarding/gender'});

  @override
  State<IntroReelScreen> createState() => _IntroReelScreenState();
}

class _IntroReelScreenState extends State<IntroReelScreen> {
  int _i = 0;
  Timer? _t;

  static const _wordMs   = 130;   // gap between word reveals
  static const _wordFade = 320;   // each word fades in over this long
  static const _holdMs   = 620;   // sentence sits for this long after last word
  static const _gapMs    = 220;   // visual pause when [_Line.bigBreath] is true

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _queueNext();
  }

  void _queueNext() {
    if (_i >= _lines.length - 1) return;
    final line = _lines[_i];
    // Total runtime for this line = all word reveals + last word fade in + hold.
    final words = line.words.length;
    final lifetimeMs = (words - 1) * _wordMs + _wordFade + _holdMs
        + (line.bigBreath ? _gapMs : 0);
    _t?.cancel();
    _t = Timer(Duration(milliseconds: lifetimeMs), () {
      if (!mounted) return;
      setState(() => _i++);
      _queueNext();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _go() {
    HapticFeedback.mediumImpact();
    context.go(widget.next);
  }

  @override
  Widget build(BuildContext context) {
    final line = _lines[_i];
    final isLast = _i == _lines.length - 1;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // SKIP — top right, calm grey.
            Positioned(
              top: 14, right: 18,
              child: GestureDetector(
                onTap: _go,
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

            // Centred sentence — words reveal in sequence.
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve:  Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) {
                    return FadeTransition(opacity: anim, child: child);
                  },
                  child: _SentenceView(
                    key:      ValueKey(_i),
                    line:     line,
                    wordMs:   _wordMs,
                    wordFade: _wordFade,
                    iconsRow: line.icons,
                  ),
                ),
              ),
            ),

            // BEGIN CTA — appears only on the last line.
            if (isLast)
              Positioned(
                bottom: 56, left: 28, right: 28,
                child: _BeginButton(onTap: _go)
                    .animate()
                    .fadeIn(duration: 400.ms, delay: 1100.ms)
                    .slideY(begin: 0.18, end: 0, duration: 400.ms,
                        delay: 1100.ms, curve: Curves.easeOut),
              ),

            // Progress dashes at the bottom.
            Positioned(
              bottom: 22, left: 0, right: 0,
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _lines.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.5),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          width:  i == _i ? 14 : 4,
                          height: 3,
                          decoration: BoxDecoration(
                            color: i <= _i ? AppColors.red : AppColors.surface3,
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
    );
  }
}

/// A single sentence. Words slide in left-to-right with a small
/// fade. Optional icon row (🔥 ❤️) renders below when supplied.
class _SentenceView extends StatelessWidget {
  final _Line line;
  final int wordMs;
  final int wordFade;
  final List<IconData> iconsRow;
  const _SentenceView({
    super.key,
    required this.line,
    required this.wordMs,
    required this.wordFade,
    required this.iconsRow,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (line.eyebrow != null) ...[
          Text(line.eyebrow!,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: AppColors.textTertiary,
              fontSize: 11, letterSpacing: 3.6,
              fontWeight: FontWeight.w800,
            ))
              .animate().fadeIn(duration: 320.ms),
          const SizedBox(height: 18),
        ],
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: line.tightSpacing ? 10 : 12,
          runSpacing: 8,
          children: [
            for (var i = 0; i < line.words.length; i++)
              _Word(
                text:  line.words[i],
                color: line.colorFor(i),
                size:  line.size,
                italic: line.italicFor(i),
                weight: line.weightFor(i),
                delayMs: i * wordMs,
                fadeMs:  wordFade,
              ),
          ],
        ),
        if (iconsRow.isNotEmpty) ...[
          const SizedBox(height: 22),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < iconsRow.length; i++) ...[
                if (i > 0) const SizedBox(width: 18),
                Icon(iconsRow[i],
                  size: 38,
                  color: i == 0 ? AppColors.red : Colors.white,
                )
                  .animate()
                  .fadeIn(
                    duration: 360.ms,
                    delay: Duration(milliseconds:
                        line.words.length * wordMs + 240 + i * 220),
                  )
                  .scale(
                    begin: const Offset(0.6, 0.6),
                    end:   const Offset(1.0, 1.0),
                    duration: 360.ms,
                    delay: Duration(milliseconds:
                        line.words.length * wordMs + 240 + i * 220),
                    curve: Curves.easeOutBack,
                  ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _Word extends StatelessWidget {
  final String text;
  final Color color;
  final double size;
  final bool italic;
  final FontWeight weight;
  final int delayMs;
  final int fadeMs;
  const _Word({
    required this.text,
    required this.color,
    required this.size,
    required this.italic,
    required this.weight,
    required this.delayMs,
    required this.fadeMs,
  });

  @override
  Widget build(BuildContext context) {
    return Text(text,
      textAlign: TextAlign.center,
      style: GoogleFonts.playfairDisplay(
        color: color,
        fontSize: size,
        height: 1.05,
        letterSpacing: -1.2,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        fontWeight: weight,
      ),
    )
        .animate()
        .fadeIn(
          duration: Duration(milliseconds: fadeMs),
          delay:    Duration(milliseconds: delayMs),
          curve:    Curves.easeOutCubic,
        )
        .slideY(
          begin: 0.22, end: 0,
          duration: Duration(milliseconds: fadeMs),
          delay:    Duration(milliseconds: delayMs),
          curve:    Curves.easeOutCubic,
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

/// One sentence + its styling. [words] is the flat list of words
/// that reveal one by one. Per-word colour / weight overrides via
/// [redIndices] (those render in brand red) and [boldIndices] (those
/// render extra-heavy non-italic — used for LOOKS / GAME / ImHim Looks).
class _Line {
  final List<String> words;
  /// Optional small-caps eyebrow above the line.
  final String? eyebrow;
  final double size;
  final bool italic;
  /// Word indices that render in brand red instead of white.
  final List<int> redIndices;
  /// Word indices that render bold non-italic (LOOKS / GAME / ImHim Looks).
  final List<int> boldIndices;
  /// Trailing icons that pop after the last word — 🔥 ❤️ on the
  /// finale line.
  final List<IconData> icons;
  /// True for sentences that end a thought — extra breath after them.
  final bool bigBreath;
  /// Tighter inter-word spacing for short, punchy lines.
  final bool tightSpacing;

  const _Line(
    this.words, {
    this.eyebrow,
    this.size = 38,
    this.italic = true,
    this.redIndices  = const [],
    this.boldIndices = const [],
    this.icons       = const [],
    this.bigBreath   = false,
    this.tightSpacing = false,
  });

  Color colorFor(int i) =>
      redIndices.contains(i) ? AppColors.red : Colors.white;

  bool italicFor(int i) =>
      boldIndices.contains(i) ? false : italic;

  FontWeight weightFor(int i) =>
      boldIndices.contains(i) ? FontWeight.w900 : FontWeight.w800;
}

const _lines = <_Line>[
  // 1. The hook.
  _Line(
    ['Every', 'man', 'knows', 'that', 'guy.'],
    size: 38,
    bigBreath: true,
  ),

  // 2-4. The triplet — what every guy wants to BE.
  _Line(
    ['The', 'guy', 'she', 'notices.'],
    size: 42,
    redIndices: [3], // "notices."
  ),
  _Line(
    ['The', 'guy', 'she', 'remembers.'],
    size: 42,
    redIndices: [3], // "remembers."
  ),
  _Line(
    ['The', 'guy', 'she', 'chooses.'],
    size: 46,
    redIndices: [3], // "chooses."
    bigBreath: true,
  ),

  // 5-6. The reframe — luck vs trained.
  _Line(
    ['Most', 'men', 'think', 'it\'s', 'luck.'],
    size: 36,
  ),
  _Line(
    ['It\'s', 'not.'],
    size: 56,
    redIndices: [0, 1],
    bigBreath: true,
  ),

  // 7-8. The product — LOOKS + GAME.
  _Line(
    ['LOOKS', 'get', 'attention.'],
    size: 50,
    boldIndices: [0],          // LOOKS bold non-italic
    tightSpacing: true,
  ),
  _Line(
    ['GAME', 'keeps', 'it.'],
    size: 50,
    boldIndices: [0],          // GAME bold non-italic
    redIndices:  [0],          // GAME in brand red
    tightSpacing: true,
    bigBreath: true,
  ),

  // 9. The promise + icons + CTA.
  _Line(
    ['ImHim Looks', 'gives', 'you', 'both.'],
    eyebrow: 'BOTH AT ONCE',
    size: 44,
    boldIndices: [0],
    redIndices:  [0],
    icons: [
      Icons.local_fire_department_rounded,
      Icons.favorite_rounded,
    ],
  ),
];
