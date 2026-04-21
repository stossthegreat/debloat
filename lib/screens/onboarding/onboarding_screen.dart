import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Two-page sexy onboarding. Black canvas, red accents, white serif.
///
/// Page 1 — WHAT WE DO       (the differentiator: real geometry, not a rating)
/// Page 2 — WHAT YOU GET     (the promise: your real face, at its peak)
///
/// Each page has a hero animated visual, a punchy headline, a 1-line sub,
/// and a CTA. Page 2's CTA pushes to /paywall.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pc = PageController();
  int _i = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.lightImpact();
    if (_i == 0) {
      _pc.animateToPage(1,
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeOutCubic);
    } else {
      context.go('/paywall');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar: wordmark + page indicator ─────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text('Mirrorly',
                        style: AppTypography.h1.copyWith(
                          fontSize: 22, letterSpacing: -0.5, height: 1)),
                      const SizedBox(width: 6),
                      Container(
                        width: 4, height: 4,
                        margin: const EdgeInsets.only(top: 9),
                        decoration: const BoxDecoration(
                          color: AppColors.red, shape: BoxShape.circle),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _PageDot(active: _i == 0),
                      const SizedBox(width: 6),
                      _PageDot(active: _i == 1),
                    ],
                  ),
                ],
              ),
            ),

            // ── Pages ──────────────────────────────────────────────────────
            Expanded(
              child: PageView(
                controller: _pc,
                physics: const ClampingScrollPhysics(),
                onPageChanged: (i) => setState(() => _i = i),
                children: const [
                  _PageMeasure(),
                  _PagePeak(),
                ],
              ),
            ),

            // ── Bottom CTA ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity, height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: _next,
                  child: Text(
                    _i == 0 ? 'CONTINUE' : 'BEGIN',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15, letterSpacing: 2.4,
                    ),
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

// ──────────────────────────────────────────────────────────────────────────
//  PAGE 1 — WHAT WE DO
// ──────────────────────────────────────────────────────────────────────────

class _PageMeasure extends StatelessWidget {
  const _PageMeasure();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text('STEP 01 · ANALYSIS',
            style: AppTypography.label.copyWith(
              color: AppColors.red,
              fontSize: 9, letterSpacing: 3.0,
              fontWeight: FontWeight.w800,
            )).animate().fadeIn(duration: 360.ms),

          const SizedBox(height: 12),

          Text('Every millimetre\nof your face.',
            style: AppTypography.h1.copyWith(
              color: Colors.white,
              fontSize: 40, letterSpacing: -1.5, height: 1.05,
            )).animate().fadeIn(delay: 120.ms, duration: 480.ms)
              .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),

          const SizedBox(height: 14),

          Text(
            'Sixteen surgical measurements pulled live from your front camera. '
            'No rating. No filter. The real numbers — sub-millimetre.',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 14, height: 1.5,
            )).animate().fadeIn(delay: 280.ms, duration: 460.ms),

          const Spacer(),

          // Hero visual: animated face mesh reticle with measurement lines
          Center(
            child: SizedBox(
              width: 260, height: 260,
              child: const _MeasureReticle(),
            ),
          ),

          const Spacer(flex: 2),

          // Three credibility chips
          _Row3Chips([
            'Canthal tilt', 'Jaw angle °', 'Symmetry %',
          ]),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Animated face-scan reticle for page 1.
class _MeasureReticle extends StatefulWidget {
  const _MeasureReticle();

  @override
  State<_MeasureReticle> createState() => _MeasureReticleState();
}

class _MeasureReticleState extends State<_MeasureReticle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(
        painter: _MeasureReticlePainter(t: _c.value),
      ),
    );
  }
}

class _MeasureReticlePainter extends CustomPainter {
  final double t;
  _MeasureReticlePainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;

    // Outer red ring (faint)
    canvas.drawCircle(c, r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.red.withValues(alpha: 0.30));

    // Inner ring
    canvas.drawCircle(c, r * 0.86,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = Colors.white.withValues(alpha: 0.10));

    // Crosshair
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy),
      Paint()..color = Colors.white.withValues(alpha: 0.10)..strokeWidth = 0.5);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r),
      Paint()..color = Colors.white.withValues(alpha: 0.10)..strokeWidth = 0.5);

    // Sweep arc (rotating red wedge)
    final sweepStart = t * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      sweepStart,
      math.pi / 3,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = AppColors.red,
    );

    // Mesh dots (pulsing alpha)
    final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.38 + 0.42 * pulse);
    final rng = math.Random(42);
    for (int i = 0; i < 64; i++) {
      final ang = rng.nextDouble() * 2 * math.pi;
      final rad = (0.20 + rng.nextDouble() * 0.62) * r;
      final p = Offset(c.dx + math.cos(ang) * rad, c.dy + math.sin(ang) * rad);
      canvas.drawCircle(p, 1.1, dotPaint);
    }

    // Center red dot
    canvas.drawCircle(c, 3, Paint()..color = AppColors.red);

    // Pulsing aura
    canvas.drawCircle(c, 6 + 3 * pulse,
      Paint()..color = AppColors.red.withValues(alpha: 0.22 * (1 - pulse)));

    // Tick marks around perimeter
    for (int i = 0; i < 24; i++) {
      final ang = i * math.pi / 12;
      final inner = Offset(
        c.dx + math.cos(ang) * (r - 8),
        c.dy + math.sin(ang) * (r - 8));
      final outer = Offset(
        c.dx + math.cos(ang) * r,
        c.dy + math.sin(ang) * r);
      canvas.drawLine(inner, outer,
        Paint()
          ..color = (i % 6 == 0 ? AppColors.red : Colors.white)
              .withValues(alpha: i % 6 == 0 ? 0.85 : 0.30)
          ..strokeWidth = i % 6 == 0 ? 1.4 : 0.6);
    }
  }

  @override
  bool shouldRepaint(_MeasureReticlePainter o) => o.t != t;
}

// ──────────────────────────────────────────────────────────────────────────
//  PAGE 2 — WHAT YOU GET
// ──────────────────────────────────────────────────────────────────────────

class _PagePeak extends StatelessWidget {
  const _PagePeak();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text('STEP 02 · TRANSFORM',
            style: AppTypography.label.copyWith(
              color: AppColors.red,
              fontSize: 9, letterSpacing: 3.0,
              fontWeight: FontWeight.w800,
            )).animate().fadeIn(duration: 360.ms),

          const SizedBox(height: 12),

          Text('You.\nAt your peak.',
            style: AppTypography.h1.copyWith(
              color: Colors.white,
              fontSize: 40, letterSpacing: -1.5, height: 1.05,
            )).animate().fadeIn(delay: 120.ms, duration: 480.ms)
              .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),

          const SizedBox(height: 14),

          Text(
            'Your real face, rendered at its best. Hairstyles, beard, skin, glasses '
            '— shaped by your bones, not a template.',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 14, height: 1.5,
            )).animate().fadeIn(delay: 280.ms, duration: 460.ms),

          const Spacer(),

          // Hero visual: NOW | MAXED card animation
          Center(
            child: SizedBox(
              width: 280, height: 220,
              child: const _BeforeAfterAnimation(),
            ),
          ),

          const Spacer(flex: 2),

          _Row3Chips([
            'Maximized', 'Try haircuts', 'Face doctor',
          ]),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Animated NOW | MAXED reveal for page 2.
class _BeforeAfterAnimation extends StatefulWidget {
  const _BeforeAfterAnimation();

  @override
  State<_BeforeAfterAnimation> createState() => _BeforeAfterAnimationState();
}

class _BeforeAfterAnimationState extends State<_BeforeAfterAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      duration: const Duration(milliseconds: 2400),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        // Sweep the divider from 35% → 65% and back
        final t = _c.value;
        final sweep = 0.35 + 0.30 * (0.5 - 0.5 * math.cos(t * 2 * math.pi));
        return CustomPaint(painter: _BeforeAfterPainter(split: sweep));
      },
    );
  }
}

class _BeforeAfterPainter extends CustomPainter {
  final double split;
  _BeforeAfterPainter({required this.split});

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size, const Radius.circular(16));
    canvas.save();
    canvas.clipRRect(r);

    // NOW side — muted greys
    canvas.drawRect(
      Rect.fromLTRB(0, 0, size.width * split, size.height),
      Paint()..color = const Color(0xFF1B1B1B));
    // Faint face silhouette on NOW
    _drawSilhouette(canvas, size, lr: -1, color: Colors.white.withValues(alpha: 0.12));

    // MAXED side — red wash + brighter silhouette
    canvas.drawRect(
      Rect.fromLTRB(size.width * split, 0, size.width, size.height),
      Paint()..shader = LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [
          AppColors.red.withValues(alpha: 0.18),
          const Color(0xFF1B1B1B),
        ],
      ).createShader(
          Rect.fromLTRB(size.width * split, 0, size.width, size.height)));
    _drawSilhouette(canvas, size, lr: 1, color: AppColors.red.withValues(alpha: 0.85));

    // Divider line
    canvas.drawLine(
      Offset(size.width * split, 0),
      Offset(size.width * split, size.height),
      Paint()..color = AppColors.red..strokeWidth = 1.4);

    // Labels
    _drawLabel(canvas, 'NOW',
      Offset(10, 10), Colors.white60);
    _drawLabel(canvas, 'MAXED',
      Offset(size.width - 60, 10), AppColors.red, bold: true);

    canvas.restore();

    // Border
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.red.withValues(alpha: 0.55));
  }

  void _drawSilhouette(Canvas canvas, Size size,
      {required int lr, required Color color}) {
    // Simple oval head silhouette in each half
    final half = size.width / 2;
    final cx = lr < 0 ? half * 0.5 : size.width - half * 0.5;
    final cy = size.height * 0.55;
    final w = size.width * 0.18;
    final h = size.height * 0.55;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: w, height: h),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color);
    // Inner mesh dots
    final rng = math.Random(lr < 0 ? 7 : 21);
    for (int i = 0; i < 14; i++) {
      final ang = rng.nextDouble() * 2 * math.pi;
      final rad = rng.nextDouble() * w / 2 * 0.85;
      canvas.drawCircle(
        Offset(cx + math.cos(ang) * rad, cy + math.sin(ang) * rad * 1.6),
        1.1,
        Paint()..color = color);
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset at, Color color,
      {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 10, letterSpacing: 2.4,
          fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_BeforeAfterPainter o) => o.split != split;
}

// ──────────────────────────────────────────────────────────────────────────
//  SHARED
// ──────────────────────────────────────────────────────────────────────────

class _Row3Chips extends StatelessWidget {
  final List<String> labels;
  const _Row3Chips(this.labels);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final l in labels) _Chip(l),
      ],
    ).animate().fadeIn(delay: 600.ms, duration: 400.ms);
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.redGlow,
        border: Border.all(color: AppColors.red.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label.toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontSize: 9.5, letterSpacing: 1.6,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PageDot extends StatelessWidget {
  final bool active;
  const _PageDot({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: active ? 18 : 6, height: 6,
      decoration: BoxDecoration(
        color: active ? AppColors.red : Colors.white.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
