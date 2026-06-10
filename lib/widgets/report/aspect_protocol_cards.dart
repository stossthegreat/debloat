import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/face_geometry.dart';
import '../../models/protocol.dart';
import '../../services/paywall_gate.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// ASPECT PROTOCOL CARDS — four small, clean tiles. SKIN / JAW /
/// DEBLOAT / HAIR. Each tile renders in one of two states:
///
///   • COMMITTED → user has tapped to start this axis. Tile shows
///                 "DAY X / 60" + day count + tap to open the
///                 routine.
///   • AVAILABLE → no run for this axis yet. Tile shows the
///                 one-line hook + tap to commit (which starts
///                 the protocol via /protocol).
///
/// Bro: "if they commit only one fucking shows" — the two-section
/// duplicate (active-tile-on-top + available-tile-below) is gone.
/// Each axis renders exactly once, in whichever state it\'s in.
class AspectProtocolCards extends StatelessWidget {
  final FaceGeometry         geometry;
  final String?              savedImagePath;
  /// Every active protocol the user has committed to, keyed by
  /// canonical axis. When present, the matching aspect tile
  /// renders in its COMMITTED state; absent axes render AVAILABLE.
  final Map<String, Protocol> activeProtocols;
  const AspectProtocolCards({
    super.key,
    required this.geometry,
    this.savedImagePath,
    this.activeProtocols = const {},
  });

  @override
  Widget build(BuildContext context) {
    final aspects = _aspects;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('60-DAY PROTOCOLS',
          style: AppTypography.label.copyWith(
            color: AppColors.textTertiary,
            letterSpacing: 2.6,
            fontSize: 10.5,
            fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text('Pick one. Tap to start.',
          style: GoogleFonts.inter(
            color: AppColors.textTertiary,
            fontSize: 11.5,
            height: 1.4,
            fontStyle: FontStyle.italic,
          )),
        const SizedBox(height: 12),
        for (int i = 0; i < aspects.length; i++) ...[
          _AspectTile(
            aspect:    aspects[i],
            committed: activeProtocols[aspects[i].pulldownString],
            onTap: () async {
              HapticFeedback.mediumImpact();
              // Bro v4: "they can't use the streaks for looks unless
              // they pay." The 60-day protocol IS the streak system —
              // gate it here so non-pro users land on the paywall
              // instead of starting / continuing a protocol.
              if (await PaywallGate.streaksLocked()) {
                if (!context.mounted) return;
                context.push('/paywall',
                    extra: {'source': 'streaks_locked'});
                return;
              }
              if (!context.mounted) return;
              context.push(
                '/protocol',
                extra: {
                  'pulldown':       aspects[i].pulldownString,
                  'axis':           aspects[i].axisKey,
                  'geometry':       geometry,
                  'savedImagePath': savedImagePath,
                },
              );
            },
          ),
          if (i < aspects.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  // The four aspect protocols. One-liner is what shows on the tile —
  // plain English, no jargon. The full daily plan (morning / midday
  // / evening) is inside /protocol.
  List<_Aspect> get _aspects => const [
    _Aspect(
      axisKey:        'skin',
      pulldownString: 'Skin',
      title:          'Skin',
      oneLiner:       'Cleaner skin in 4 weeks.',
      color:          AppColors.signalGreen,
    ),
    _Aspect(
      axisKey:        'jaw',
      pulldownString: 'Jaw definition',
      title:          'Jaw',
      oneLiner:       'Sharper jaw in 60 days.',
      color:          AppColors.red,
    ),
    _Aspect(
      axisKey:        'debloat',
      pulldownString: 'Puffiness',
      title:          'Debloat',
      oneLiner:       'Less puffy face by tomorrow.',
      color:          AppColors.signalAmber,
    ),
    _Aspect(
      axisKey:        'hair',
      pulldownString: 'Hair',
      title:          'Hair',
      oneLiner:       'Hold the hairline. 6-month plan.',
      color:          AppColors.measure,
    ),
  ];
}

class _Aspect {
  final String axisKey;
  final String pulldownString;
  final String title;
  final String oneLiner;
  final Color  color;
  const _Aspect({
    required this.axisKey,
    required this.pulldownString,
    required this.title,
    required this.oneLiner,
    required this.color,
  });
}

class _AspectTile extends StatelessWidget {
  final _Aspect       aspect;
  final Protocol?     committed; // non-null when the user has started this axis
  final VoidCallback  onTap;
  const _AspectTile({
    required this.aspect,
    required this.committed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCommitted = committed != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.xl),
        child: Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(Rd.xl),
            border: Border.all(
              color: isCommitted
                ? aspect.color.withValues(alpha: 0.55)
                : AppColors.divider,
              width: isCommitted ? 1.0 : 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Eyebrow row — axis tag in colour + status (day count
              // for committed, "60-day plan" for available) + arrow.
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: aspect.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: aspect.color.withValues(alpha: 0.55),
                        width: 0.8),
                    ),
                    child: Text(aspect.title.toUpperCase(),
                      style: AppTypography.label.copyWith(
                        color: aspect.color,
                        fontSize: 9.5,
                        letterSpacing: 1.8,
                        fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isCommitted
                      ? 'Day ${committed!.currentDay} / ${committed!.lengthDays}'
                      : '60-day plan',
                    style: AppTypography.label.copyWith(
                      color: isCommitted
                        ? aspect.color
                        : AppColors.textTertiary,
                      fontSize: 9,
                      letterSpacing: 2.0,
                      fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Icon(Icons.arrow_forward_rounded,
                    size: 14, color: AppColors.textSecondary),
                ],
              ),
              const SizedBox(height: 8),
              // Title + sub-line. Available tile shows the hook;
              // committed tile shows the day-count + streak so the
              // user sees momentum without opening the routine.
              Text(aspect.title,
                style: AppTypography.h1.copyWith(
                  fontSize: 20, letterSpacing: -0.4)),
              const SizedBox(height: 4),
              // Sub-line. Available tile shows the hook. Committed
              // tile shows a flame icon + streak count + days-logged
              // so momentum reads at a glance.
              if (isCommitted)
                Row(
                  children: [
                    Icon(Icons.local_fire_department_rounded,
                        color: aspect.color, size: 14),
                    const SizedBox(width: 3),
                    Text('${committed!.effectiveStreak}',
                      style: AppTypography.label.copyWith(
                        color: aspect.color,
                        fontSize: 12.5, letterSpacing: 0.2,
                        fontWeight: FontWeight.w900,
                      )),
                    const SizedBox(width: 8),
                    Text('${committed!.completedDays.length} days logged',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12.5)),
                  ],
                )
              else
                Text(aspect.oneLiner,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary, fontSize: 12.5)),

              // Visual progress bar — only when committed. Makes
              // momentum legible at a glance without opening the
              // protocol detail. Tinted in the axis colour so each
              // tile reads as its own track.
              if (isCommitted) ...[
                const SizedBox(height: 10),
                _ProgressBar(
                  fraction: committed!.lengthDays == 0
                      ? 0
                      : (committed!.currentDay / committed!.lengthDays)
                          .clamp(0.0, 1.0),
                  color: aspect.color,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Thin axis-colored progress bar shown under committed protocol
/// tiles. Background is a faint version of the axis color; fill is
/// solid. No animation on first paint — just the static state, so
/// the bar reads as data, not chrome.
class _ProgressBar extends StatelessWidget {
  final double fraction;
  final Color  color;
  const _ProgressBar({required this.fraction, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Stack(
        children: [
          Container(
            height: 5,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
            ),
          ),
          FractionallySizedBox(
            widthFactor: fraction,
            child: Container(
              height: 5,
              decoration: BoxDecoration(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
