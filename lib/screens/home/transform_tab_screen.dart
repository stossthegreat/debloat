import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/protocol.dart';
import '../../models/scan_record.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/common/mirrorly_wordmark.dart';
import '../../widgets/common/mirrorly_components.dart';
import '../../widgets/report/aspect_protocol_cards.dart';

/// TRANSFORM tab — the change engine, tab index 1.
///
/// The looks-app pivot: LOOKS rates you, TRANSFORM changes you. Two
/// moves live here:
///
///   1. THE MIRROR — the AI glow-up. See what could change, rendered
///      on YOUR face (routes to /chat with the latest scan geometry).
///   2. THE 60-DAY PROTOCOLS — Skin / Jaw / Eyes / Debloat / Hair.
///      Commit, log daily, watch the number move.
///
/// Needs a scan to work from; before the first scan it sells the path
/// and routes to /scan.
class TransformTabScreen extends StatelessWidget {
  final ScanRecord? latest;
  final Map<String, Protocol> activeProtocols;
  final int dayStreak;
  final Future<void> Function() onRefresh;
  const TransformTabScreen({
    super.key,
    required this.latest,
    required this.activeProtocols,
    required this.dayStreak,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final hasScan = latest != null;
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: onRefresh,
          color: AppColors.red,
          backgroundColor: AppColors.surface1,
          child: ListView(
            padding: const EdgeInsets.only(bottom: Sp.xl),
            children: [
              // ── Masthead — same chrome language as the Looks tab.
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const MirrorlyWordmark(fontSize: 34),
                    const Spacer(),
                    if (dayStreak > 0) ...[
                      _StreakBadge(days: dayStreak),
                      const SizedBox(width: 8),
                    ],
                    _CircleIcon(
                      icon: Icons.show_chart_rounded,
                      border: AppColors.signalAmber.withValues(alpha: 0.55),
                      color: AppColors.signalAmber,
                      onTap: () => context.push('/progress'),
                    ),
                    const SizedBox(width: 8),
                    _CircleIcon(
                      icon: Icons.tune,
                      border: AppColors.surface3,
                      color: AppColors.textSecondary,
                      onTap: () => context.push('/settings'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Text(
                  'See the after. Then build it.',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 15, height: 1.35,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              const SizedBox(height: Sp.lg),

              if (!hasScan) ...[
                // ── Pre-scan — the Transform tab needs a face to work
                //    from. One card, one action.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                  child: _ScanFirstCard(
                    onTap: () => context.push('/scan'),
                  ),
                ).animate().fadeIn(duration: 400.ms),
              ] else ...[
                // ── THE MIRROR — the glow-up hero.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                  child: _MirrorHeroCard(
                    onTap: () => context.push('/chat', extra: {
                      'geometry':  latest!.geometry,
                      'imagePath': latest!.capturedImagePath,
                    }),
                  ),
                ).animate().fadeIn(duration: 400.ms),

                const SizedBox(height: Sp.lg),

                // ── THE 60-DAY PROTOCOLS.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                  child: AspectProtocolCards(
                    geometry:         latest!.geometry,
                    savedImagePath:   latest!.capturedImagePath,
                    activeProtocols:  activeProtocols,
                  ),
                ).animate().fadeIn(delay: 140.ms, duration: 400.ms),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pre-scan prompt card ────────────────────────────────────────────
class _ScanFirstCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ScanFirstCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(Rd.xl),
      child: InkWell(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        borderRadius: BorderRadius.circular(Rd.xl),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Rd.xl),
            border: Border.all(
                color: AppColors.red.withValues(alpha: 0.42), width: 0.9),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('STEP ONE',
                  style: AppTypography.label.copyWith(
                    color: AppColors.red,
                    fontSize: 10.5, letterSpacing: 2.8,
                    fontWeight: FontWeight.w800,
                  )),
              const SizedBox(height: 10),
              Text('Scan first.\nThen we transform it.',
                  style: GoogleFonts.playfairDisplay(
                    color: AppColors.textPrimary,
                    fontSize: 26, height: 1.15,
                    letterSpacing: -0.5,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w800,
                  )),
              const SizedBox(height: 8),
              Text(
                'The glow-up render and the 60-day protocols are built '
                'from your face scan. Thirty seconds.',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 13, height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.center_focus_strong_rounded,
                      size: 16, color: AppColors.red),
                  const SizedBox(width: 8),
                  Text('BEGIN FACE SCAN',
                      style: AppTypography.label.copyWith(
                        color: AppColors.red,
                        fontSize: 12, letterSpacing: 2.4,
                        fontWeight: FontWeight.w900,
                      )),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Mirror hero card — moved from the Looks tab. The right half is a
// tight before/after split; the left carries the headline.
class _MirrorHeroCard extends StatelessWidget {
  final VoidCallback onTap;
  const _MirrorHeroCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(Rd.lg),
      child: InkWell(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        borderRadius: BorderRadius.circular(Rd.lg),
        splashColor: AppColors.red.withValues(alpha: 0.06),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Rd.lg),
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.42), width: 0.9),
            boxShadow: [
              BoxShadow(
                color: AppColors.red.withValues(alpha: 0.18),
                blurRadius: 22, spreadRadius: 0,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Rd.lg),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 8, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('THE MIRROR',
                            style: AppTypography.label.copyWith(
                              color: AppColors.red,
                              fontSize: 10.5, letterSpacing: 2.8,
                              fontWeight: FontWeight.w800,
                            )),
                          const SizedBox(height: 8),
                          Text('See what could\nchange.',
                            style: GoogleFonts.playfairDisplay(
                              color: AppColors.textPrimary,
                              fontSize: 20, height: 1.1,
                              letterSpacing: -0.4,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w800,
                            )),
                          const SizedBox(height: 6),
                          Text(
                            'AI that knows your face.',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 12.5, height: 1.35,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: SizedBox(
                      height: 130,
                      child: Row(
                        children: [
                          Expanded(child: _half(
                            asset: 'assets/marketing/before.jpg',
                            label: 'NOW',
                          )),
                          Container(width: 1, color: Colors.white),
                          Expanded(child: _half(
                            asset: 'assets/marketing/after.jpg',
                            label: 'FIXED',
                          )),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _half({required String asset, required String label}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(asset,
          fit: BoxFit.cover,
          alignment: const Alignment(0, -0.25),
          errorBuilder: (_, __, ___) => Container(
            color: AppColors.surface2,
            alignment: Alignment.center,
            child: const Icon(Icons.face_retouching_natural,
                size: 32, color: AppColors.surface3),
          ),
        ),
        Positioned(
          left: 0, right: 0, bottom: 0, height: 36,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.58),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Text(label,
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 9, letterSpacing: 2.4,
                fontWeight: FontWeight.w800,
              )),
          ),
        ),
      ],
    );
  }
}

// ── Masthead chrome (same shapes as the Looks tab) ──────────────────
class _StreakBadge extends StatelessWidget {
  final int days;
  const _StreakBadge({required this.days});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.red,
        borderRadius: BorderRadius.circular(99),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withValues(alpha: 0.45),
            blurRadius: 14, spreadRadius: 0),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded,
              color: Colors.white, size: 18),
          const SizedBox(width: 5),
          Text('$days',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 14, height: 1,
                letterSpacing: 0.2,
                fontWeight: FontWeight.w900,
              )),
        ],
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final Color border;
  final Color color;
  final VoidCallback onTap;
  const _CircleIcon({
    required this.icon,
    required this.border,
    required this.color,
    required this.onTap,
  });
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
            border: Border.all(color: border, width: 0.8),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
