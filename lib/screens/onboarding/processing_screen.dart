import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/analytics_service.dart';
import '../../services/paywall_gate.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// THE PROCESSING THEATRE — sits between the first scan and the paywall.
///
/// Bro's flow: "scan them, then pretend done — big loading screen,
/// loading AI debloated face render, then your in-depth bloat scores
/// spinning spinning, then the paywall. They pay, THEN they see the
/// scan results."
///
/// Nothing network-bound happens here — it's pure anticipation. Three
/// staged beats over ~9 seconds:
///   1. RENDERING YOUR DEBLOATED FACE   (big % climbing)
///   2. COMPUTING YOUR BLOAT SCORES     (zone rings spinning in)
///   3. LOCKING YOUR DRAIN PLAN         (final tick)
/// then routes with the scan payload intact:
///   · Pro user  → /report (analysis fires there as always)
///   · Free user → /paywall {afterPurchase: '/report', payload}
class ProcessingScreen extends StatefulWidget {
  /// The scan payload — imageBytes / geometry / extraImages, exactly
  /// what /report and /paywall already accept.
  final Map<String, dynamic> payload;
  const ProcessingScreen({super.key, required this.payload});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t;
  bool _routed = false;

  static const _totalMs = 9000;

  // Stage windows as fractions of the full run.
  static const _s1End = 0.42; // render
  static const _s2End = 0.86; // scores

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    AnalyticsService.onbStep('processing_theatre');
    _t = AnimationController(
        vsync: this, duration: const Duration(milliseconds: _totalMs))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _route();
      })
      ..forward();
  }

  Future<void> _route() async {
    if (_routed) return;
    _routed = true;
    HapticFeedback.mediumImpact();
    final pro = await PaywallGate.isPro();
    if (!mounted) return;
    if (pro) {
      context.go('/report', extra: widget.payload);
    } else {
      context.go('/paywall', extra: {
        ...widget.payload,
        'afterPurchase': '/report',
        'source': 'post_scan_processing',
      });
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  int get _stage {
    final v = _t.value;
    if (v < _s1End) return 0;
    if (v < _s2End) return 1;
    return 2;
  }

  /// 0..1 progress within the current stage.
  double get _stageT {
    final v = _t.value;
    return switch (_stage) {
      0 => (v / _s1End).clamp(0.0, 1.0),
      1 => ((v - _s1End) / (_s2End - _s1End)).clamp(0.0, 1.0),
      _ => ((v - _s2End) / (1 - _s2End)).clamp(0.0, 1.0),
    };
  }

  static const _titles = [
    'RENDERING YOUR\nDEBLOATED FACE',
    'COMPUTING YOUR\nBLOAT SCORES',
    'LOCKING YOUR\nDRAIN PLAN',
  ];
  static const _subs = [
    'The AI is drawing the leaner, sharper you — the face under the bloat.',
    'Jawline · cheeks · under-eye · fluid balance · trapped water.',
    'Matching your answers to the routine that drains fastest.',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _t,
          builder: (context, _) {
            final overallPct = (_t.value * 100).round();
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const Spacer(flex: 2),

                  // ── The big ring — overall progress + % ────────────
                  SizedBox(
                    width: 210, height: 210,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(210, 210),
                          painter: _TheatreRingPainter(
                            progress: _t.value,
                            spin: _t.value * 6.28318,
                            stage: _stage,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$overallPct%',
                              style: GoogleFonts.spaceGrotesk(
                                color: Colors.white,
                                fontSize: 52, height: 1,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -2)),
                            const SizedBox(height: 4),
                            Text('DO NOT CLOSE',
                              style: AppTypography.label.copyWith(
                                color: AppColors.textTertiary,
                                fontSize: 8.5, letterSpacing: 2.6,
                                fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // ── Stage title + sub ──────────────────────────────
                  Text(_titles[_stage],
                    key: ValueKey(_stage),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 24, height: 1.2,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Text(_subs[_stage],
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 13.5, height: 1.5,
                      fontWeight: FontWeight.w500)),

                  const Spacer(flex: 2),

                  // ── Stage checklist ────────────────────────────────
                  _StageRow(
                    label: 'AI debloated render',
                    state: _stage > 0 ? 2 : 1,
                    localT: _stage == 0 ? _stageT : 1),
                  const SizedBox(height: 12),
                  _StageRow(
                    label: 'In-depth bloat scores',
                    state: _stage > 1 ? 2 : (_stage == 1 ? 1 : 0),
                    localT: _stage == 1 ? _stageT : (_stage > 1 ? 1 : 0)),
                  const SizedBox(height: 12),
                  _StageRow(
                    label: 'Personal drain plan',
                    state: _stage == 2 ? 1 : 0,
                    localT: _stage == 2 ? _stageT : 0),

                  const SizedBox(height: 48),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One stage line: dot/spinner/check + label + thin progress track.
class _StageRow extends StatelessWidget {
  final String label;
  final int state; // 0 pending · 1 running · 2 done
  final double localT;
  const _StageRow({
    required this.label, required this.state, required this.localT});

  @override
  Widget build(BuildContext context) {
    final active = state >= 1;
    return Row(
      children: [
        SizedBox(
          width: 22, height: 22,
          child: state == 2
              ? const Icon(Icons.check_circle_rounded,
                  color: AppColors.brand, size: 20)
              : state == 1
                  ? const Padding(
                      padding: EdgeInsets.all(2),
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.brand))
                  : Icon(Icons.circle_outlined,
                      color: AppColors.surface3, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                style: GoogleFonts.inter(
                  color: active ? Colors.white : AppColors.textTertiary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: localT,
                  minHeight: 3,
                  backgroundColor: AppColors.surface3.withValues(alpha: 0.5),
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.brand),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Progress arc + a counter-spinning comet arc so it reads "working",
/// not just filling.
class _TheatreRingPainter extends CustomPainter {
  final double progress;
  final double spin;
  final int stage;
  const _TheatreRingPainter({
    required this.progress, required this.spin, required this.stage});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 10;

    // Track
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = AppColors.surface3.withValues(alpha: 0.5));

    // Overall progress arc
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2, math.pi * 2 * progress.clamp(0.0, 1.0), false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: -math.pi / 2 + math.pi * 2,
          colors: const [AppColors.accentDeep, AppColors.brand],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(Rect.fromCircle(center: c, radius: r)));

    // Inner comet — spins the other way, faster during stage 1.
    final innerR = r - 18;
    final sweepStart = -spin * (stage == 1 ? 2.2 : 1.4);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: innerR),
      sweepStart, math.pi * 0.45, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = AppColors.brand.withValues(alpha: 0.75));
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: innerR),
      sweepStart, math.pi * 0.45, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = AppColors.brand.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
  }

  @override
  bool shouldRepaint(_TheatreRingPainter old) =>
      old.progress != progress || old.spin != spin || old.stage != stage;
}
