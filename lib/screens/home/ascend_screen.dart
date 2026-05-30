import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/scan_record.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/common/mirrorly_components.dart';

/// ASCEND — the home tab. One screen, one daily ritual.
///
/// Consistent masthead with every other tab (small "Mirrorly •" +
/// "Ascend" subtitle), streak chip only (no level — the user called
/// it bullshit), three pillar scores out of 10 (Looks / Presence /
/// Game, all zero until the user actually uses the surface), three
/// daily missions compact, and the potential card blurred until the
/// first scan exists.
class AscendScreen extends StatelessWidget {
  /// Switch the bottom-nav to a specific tab. Wired from HomeScreen
  /// so tapping a mission row jumps to the correct surface.
  final ValueChanged<int> onJumpToTab;

  /// Latest scan, if any. Drives whether the Potential card unlocks.
  final ScanRecord? latest;

  /// Streak count. Mocked for now — wire to real ProtocolService
  /// streak engine when ready.
  final int dayStreak;

  /// Pillar scores 0..10. Default zero until the user has done a
  /// scan / lesson / session in each.
  final int looksScore;
  final int presenceScore;
  final int gameScore;

  const AscendScreen({
    super.key,
    required this.onJumpToTab,
    this.latest,
    this.dayStreak = 0,
    this.looksScore = 0,
    this.presenceScore = 0,
    this.gameScore = 0,
  });

  @override
  Widget build(BuildContext context) {
    final hasScan = latest != null;
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: Sp.xl),
          children: [
            // ── Masthead — consistent with every other tab.
            MirrorlyMasthead(
              title: 'Mirrorly',
              subtitle: 'Ascend',
              actions: [
                MastheadAction(
                  icon: Icons.tune,
                  onTap: () => context.push('/settings'),
                ),
              ],
            ),

            const SizedBox(height: Sp.md),

            // ── Streak chip (no level).
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: Row(
                children: [
                  _StreakPill(days: dayStreak),
                ],
              ),
            ),

            const SizedBox(height: Sp.md),

            // ── Three pillar scores. /10 each. Zero until used.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: Row(
                children: [
                  Expanded(child: _PillarScore(
                    label: 'LOOKS',
                    score: looksScore,
                    color: AppColors.red,
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _PillarScore(
                    label: 'PRESENCE',
                    score: presenceScore,
                    color: AppColors.accent,
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _PillarScore(
                    label: 'GAME',
                    score: gameScore,
                    color: AppColors.signalAmber,
                  )),
                ],
              ),
            ),

            const SizedBox(height: Sp.md),

            // ── Today's Ascension — 3 compact missions.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: _TodaysAscension(onJumpToTab: onJumpToTab),
            ).animate().fadeIn(delay: 120.ms, duration: 400.ms),

            const SizedBox(height: Sp.md),

            // ── Potential card. Blurred + locked until a scan exists,
            //    then unblurs to show the real looksmax targets the AI
            //    extracted from the report.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: _PotentialCard(unlocked: hasScan),
            ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
          ],
        ),
      ),
    );
  }
}

// ─── Streak pill ───────────────────────────────────────────────────

class _StreakPill extends StatelessWidget {
  final int days;
  const _StreakPill({required this.days});

  @override
  Widget build(BuildContext context) {
    final active = days > 0;
    final color = active ? AppColors.red : AppColors.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.45), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            '$days',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'DAY STREAK',
            style: AppTypography.label.copyWith(
              color: AppColors.textTertiary,
              fontSize: 9.5,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Pillar score card ────────────────────────────────────────────

class _PillarScore extends StatelessWidget {
  final String label;
  final int score;
  final Color color;
  const _PillarScore({
    required this.label,
    required this.score,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final live = score > 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(
            color: live ? color.withOpacity(0.55) : AppColors.surface3,
            width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.label.copyWith(
              color: color,
              fontSize: 10,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$score',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    fontStyle: FontStyle.italic,
                    color: live ? color : AppColors.textPrimary,
                    height: 1.0,
                    letterSpacing: -0.6,
                  ),
                ),
                TextSpan(
                  text: ' / 10',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textTertiary,
                    height: 1.0,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Today's Ascension — 3 missions, compact ─────────────────────

class _TodaysAscension extends StatelessWidget {
  final ValueChanged<int> onJumpToTab;
  const _TodaysAscension({required this.onJumpToTab});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(color: AppColors.surface3, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'TODAY\'S ASCENSION',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
              Text(
                '0 / 3',
                style: AppTypography.label.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _MissionRow(
            color: AppColors.red,
            icon: Icons.face_retouching_natural_outlined,
            category: 'LOOKS',
            title: 'Jaw Posture',
            minutes: 3,
            state: _MissionState.current,
            onTap: () => onJumpToTab(1),
          ),
          const _MissionDivider(),
          _MissionRow(
            color: AppColors.accent,
            icon: Icons.remove_red_eye_outlined,
            category: 'PRESENCE',
            title: 'Eye Contact Drill',
            minutes: 5,
            state: _MissionState.current,
            onTap: () => onJumpToTab(2),
          ),
          const _MissionDivider(),
          _MissionRow(
            color: AppColors.signalAmber,
            icon: Icons.chat_bubble_outline_rounded,
            category: 'GAME',
            title: 'Free Flow',
            minutes: 3,
            state: _MissionState.current,
            onTap: () => onJumpToTab(3),
          ),
        ],
      ),
    );
  }
}

enum _MissionState { done, current, locked }

class _MissionDivider extends StatelessWidget {
  const _MissionDivider();
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: AppColors.surface3,
          margin: const EdgeInsets.symmetric(vertical: 2));
}

class _MissionRow extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String category;
  final String title;
  final int minutes;
  final _MissionState state;
  final VoidCallback onTap;
  const _MissionRow({
    required this.color,
    required this.icon,
    required this.category,
    required this.title,
    required this.minutes,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      borderRadius: BorderRadius.circular(Rd.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.45), width: 1),
              ),
              child: Icon(icon, color: color, size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category,
                    style: AppTypography.label.copyWith(
                      color: color,
                      fontSize: 9.5,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.2,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$minutes MIN',
              style: AppTypography.label.copyWith(
                color: AppColors.textTertiary,
                fontSize: 9.5,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            _MissionStatusGlyph(state: state, color: color),
          ],
        ),
      ),
    );
  }
}

class _MissionStatusGlyph extends StatelessWidget {
  final _MissionState state;
  final Color color;
  const _MissionStatusGlyph({required this.state, required this.color});

  @override
  Widget build(BuildContext context) {
    final (icon, fg, border) = switch (state) {
      _MissionState.done => (
          Icons.check_rounded,
          color,
          color,
        ),
      _MissionState.current => (
          Icons.arrow_forward_rounded,
          color,
          color,
        ),
      _MissionState.locked => (
          Icons.lock_rounded,
          AppColors.textTertiary,
          AppColors.surface3,
        ),
    };
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 1.4),
      ),
      child: Icon(icon, color: fg, size: 14),
    );
  }
}

// ─── Potential card — blurred until the user scans ───────────────
// Same layout as before; ImageFilter.blur wrapper makes the inside
// illegible (placeholder data) until a scan exists. After the first
// scan we swap in real looksmax targets from the report.

class _PotentialCard extends StatelessWidget {
  final bool unlocked;
  const _PotentialCard({required this.unlocked});

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(color: AppColors.surface3, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YOUR POTENTIAL',
                  style: AppTypography.label.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '+18',
                        style: GoogleFonts.inter(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: AppColors.red,
                          letterSpacing: -1.4,
                          height: 1.0,
                        ),
                      ),
                      TextSpan(
                        text: ' POINTS',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: 1.0,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You\'re leaving points on the table. We fix that.',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: const [
                _TraitDelta(label: 'JAWLINE', delta: 4),
                SizedBox(height: 5),
                _TraitDelta(label: 'FACE FAT', delta: 6),
                SizedBox(height: 5),
                _TraitDelta(label: 'SKIN', delta: 3),
                SizedBox(height: 5),
                _TraitDelta(label: 'POSTURE', delta: 2),
                SizedBox(height: 5),
                _TraitDelta(label: 'HAIR', delta: 3),
              ],
            ),
          ),
        ],
      ),
    );

    if (unlocked) return card;

    // Pre-scan: the card sits behind a blur overlay + a single CTA
    // "Scan to unlock your potential" pill. We blur the card itself
    // so the silhouette of the layout is visible (creating curiosity)
    // but the numbers are unreadable.
    return Stack(
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Opacity(opacity: 0.55, child: card),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Rd.xl),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.10),
                  Colors.black.withOpacity(0.40),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.red.withOpacity(0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_rounded,
                      size: 14, color: Colors.black),
                  const SizedBox(width: 8),
                  Text(
                    'SCAN TO UNLOCK',
                    style: AppTypography.label.copyWith(
                      color: Colors.black,
                      fontSize: 11,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TraitDelta extends StatelessWidget {
  final String label;
  final int delta;
  const _TraitDelta({required this.label, required this.delta});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.label.copyWith(
            color: AppColors.textSecondary,
            fontSize: 9.5,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '+$delta',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: AppColors.red,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}
