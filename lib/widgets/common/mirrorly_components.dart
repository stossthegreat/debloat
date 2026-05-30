import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Mirrorly tab kit — the shared vocabulary every primary tab is built from.
//  Five primitives, used the same way across Scan, Mirror, Eyes, Game so the
//  product reads as one voice: black + white + red, Playfair italic display,
//  Inter all-caps labels, photoreal character portraits with red rim light.
//
//  Visual contract (do not break across tabs):
//   • Tab edge gutter: Sp.lg (24).
//   • Big-block vertical rhythm: Sp.lg between blocks, Sp.md inside blocks.
//   • Display headlines: AppTypography.displayXL, italic, with the bottom
//     line painted red to draw the eye down toward the proof / CTA.
//   • Subhead: italic red Inter, tracking +0.2, ≤ 2 lines.
//   • Body copy: AppTypography.body, secondary white.
//   • All cards use surface2 fill, surface3 1px border, Rd.xl (20) radius.
//   • Lock chips are 14×14 outlined squares with the lock glyph centred.
//   • Primary CTA is full-width red, height 60, italic uppercase label.
// ─────────────────────────────────────────────────────────────────────────────

/// Top-of-tab masthead. Three slots, all optional:
///   • [eyebrow]   — small red tracked label (e.g. "THE CONSIGLIERE").
///   • [title]     — big italic display (e.g. "Game.").
///   • [subtitle]  — italic red one-liner under the title.
/// [actions] sits in the top-right (settings, premium badge, …).
class MirrorlyMasthead extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  const MirrorlyMasthead({
    super.key,
    this.eyebrow,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!.toUpperCase(),
                    style: AppTypography.label.copyWith(
                      color: AppColors.red,
                      letterSpacing: 3.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                _TitleWithRedDot(title: title),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: AppColors.red,
                      letterSpacing: 0.2,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: Sp.md),
            Row(children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                actions[i],
              ],
            ]),
          ],
        ],
      ),
    );
  }
}

/// "Title •" — the brand signature: italic display with a small red dot
/// trailing the title. Used in every masthead.
class _TitleWithRedDot extends StatelessWidget {
  final String title;
  const _TitleWithRedDot({required this.title});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.playfairDisplay(
          fontSize: 38,
          fontWeight: FontWeight.w700,
          fontStyle: FontStyle.italic,
          letterSpacing: -1.2,
          color: AppColors.textPrimary,
          height: 1.0,
        ),
        children: [
          TextSpan(text: title),
          const TextSpan(text: '  '),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: AppColors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular outlined icon button — settings, premium badge, etc. Sits in the
/// [MirrorlyMasthead] actions slot.
class MastheadAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color borderColor;
  final Color iconColor;

  const MastheadAction({
    super.key,
    required this.icon,
    required this.onTap,
    this.borderColor = AppColors.surface3,
    this.iconColor = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surface1,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Display block — italic two-line headline + subhead + body.
//  The bottom display line is painted red; the eye lands there, then drops
//  to the subhead, then to the body. This is the conversion column.
// ─────────────────────────────────────────────────────────────────────────────

class DisplayBlock extends StatelessWidget {
  final String lineOne;
  final String lineTwo;
  final String? subhead;
  final String? body;
  final CrossAxisAlignment align;

  const DisplayBlock({
    super.key,
    required this.lineOne,
    required this.lineTwo,
    this.subhead,
    this.body,
    this.align = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final display = GoogleFonts.playfairDisplay(
      fontSize: 54,
      fontWeight: FontWeight.w800,
      fontStyle: FontStyle.italic,
      letterSpacing: -2.0,
      height: 1.0,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(
            lineOne.toUpperCase(),
            style: display.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            lineTwo.toUpperCase(),
            style: display.copyWith(color: AppColors.red),
          ),
          if (subhead != null) ...[
            const SizedBox(height: Sp.md),
            Text(
              subhead!,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: AppColors.textPrimary,
                height: 1.35,
              ),
            ),
          ],
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(body!, style: AppTypography.body),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Stat strip — three side-by-side number tiles with an icon, value, label.
//  Used under hero photos for the credibility proof (16 / 0.1mm / AI render).
// ─────────────────────────────────────────────────────────────────────────────

class StatPoint {
  final IconData icon;
  final String value;
  final String label;
  const StatPoint({required this.icon, required this.value, required this.label});
}

class StatStrip extends StatelessWidget {
  final List<StatPoint> stats;
  const StatStrip({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: AppColors.surface3, width: 1),
      ),
      padding: const EdgeInsets.symmetric(vertical: Sp.md, horizontal: Sp.md),
      child: Row(
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0)
              Container(width: 1, height: 36, color: AppColors.surface3),
            Expanded(child: _statTile(stats[i])),
          ],
        ],
      ),
    );
  }

  Widget _statTile(StatPoint p) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(p.icon, size: 18, color: AppColors.red),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              p.value,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            Text(
              p.label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textTertiary,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Primary CTA — the full-width red button used to start a scan, lesson,
//  conversation. Optional [meta] line under it ("Takes 30 seconds").
// ─────────────────────────────────────────────────────────────────────────────

class PrimaryCta extends StatelessWidget {
  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final VoidCallback onTap;
  final String? meta;
  final bool locked;

  const PrimaryCta({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.trailingIcon,
    this.meta,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final isRed = !locked;
    final bg = isRed ? AppColors.red : AppColors.surface2;
    final fg = isRed ? Colors.black : AppColors.textPrimary;
    final border = isRed ? null : Border.all(color: AppColors.surface3);
    return Column(
      children: [
        InkWell(
          onTap: () { HapticFeedback.mediumImpact(); onTap(); },
          borderRadius: BorderRadius.circular(Rd.lg),
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(Rd.lg),
              border: border,
              boxShadow: isRed
                  ? [
                      BoxShadow(
                        color: AppColors.red.withOpacity(0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (locked) ...[
                  Icon(Icons.lock_rounded, size: 18, color: fg),
                  const SizedBox(width: 10),
                ] else if (icon != null) ...[
                  Icon(icon, size: 22, color: fg),
                  const SizedBox(width: 12),
                ],
                Text(
                  label.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: fg,
                    letterSpacing: 1.6,
                  ),
                ),
                if (trailingIcon != null) ...[
                  const SizedBox(width: 12),
                  Icon(trailingIcon, size: 18, color: fg),
                ],
              ],
            ),
          ),
        ),
        if (meta != null) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.schedule_rounded,
                  size: 14, color: AppColors.textTertiary),
              const SizedBox(width: 6),
              Text(
                meta!,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Lock strip — the bottom card on Scan / Mirror with the "after the scan
//  unlock X · Y" line and trailing icon badges.
// ─────────────────────────────────────────────────────────────────────────────

class LockStrip extends StatelessWidget {
  final String label;
  final String highlight;
  final List<LockBadge> badges;
  final VoidCallback? onTap;

  const LockStrip({
    super.key,
    required this.label,
    required this.highlight,
    required this.badges,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap == null
          ? null
          : () { HapticFeedback.selectionClick(); onTap!(); },
      borderRadius: BorderRadius.circular(Rd.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Sp.md, vertical: Sp.md),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(Rd.lg),
          border: Border.all(color: AppColors.surface3, width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: AppTypography.label.copyWith(letterSpacing: 2.4),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    highlight.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Sp.md),
            for (var i = 0; i < badges.length; i++) ...[
              if (i > 0) const SizedBox(width: Sp.md),
              badges[i],
            ],
          ],
        ),
      ),
    );
  }
}

class LockBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const LockBadge({
    super.key,
    required this.icon,
    required this.label,
    this.color = AppColors.red,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(height: 4),
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Character card — the big cinema card with a photoreal portrait, an
//  italic title, body copy, and an optional inline panel (the Eyes "Lesson 01
//  · The Lock" sub-card sits inside this). Top-right lock chip when gated.
//
//  Image is loaded via Image.asset(assetPath) with a graceful errorBuilder
//  so the layout looks correct before any JPEGs are dropped in. The whole
//  card is tappable when [onTap] is provided.
// ─────────────────────────────────────────────────────────────────────────────

class CharacterCard extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final String? body;
  final String assetPath;
  final bool locked;
  final Widget? inlinePanel;
  final Widget? footer;
  final double imageWidthFactor;
  final VoidCallback? onTap;
  final IconData fallbackIcon;

  const CharacterCard({
    super.key,
    this.eyebrow,
    required this.title,
    this.body,
    required this.assetPath,
    this.locked = false,
    this.inlinePanel,
    this.footer,
    this.imageWidthFactor = 0.48,
    this.onTap,
    this.fallbackIcon = Icons.person_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap == null
          ? null
          : () { HapticFeedback.selectionClick(); onTap!(); },
      borderRadius: BorderRadius.circular(Rd.xl),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(Rd.xl),
          border: Border.all(color: AppColors.surface3, width: 1),
        ),
        child: Column(
          children: [
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 11,
                  child: _CharacterImage(
                    assetPath: assetPath,
                    fallbackIcon: fallbackIcon,
                    alignFactor: imageWidthFactor,
                  ),
                ),
                Positioned(
                  left: Sp.md,
                  right: Sp.md,
                  bottom: Sp.md,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (eyebrow != null)
                        Text(
                          eyebrow!.toUpperCase(),
                          style: AppTypography.label.copyWith(
                            color: AppColors.red,
                            letterSpacing: 2.8,
                          ),
                        ),
                      const SizedBox(height: 6),
                      Text(
                        title.toUpperCase(),
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          fontStyle: FontStyle.italic,
                          color: AppColors.textPrimary,
                          height: 1.0,
                          letterSpacing: -0.8,
                        ),
                      ),
                      if (body != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          body!,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (locked)
                  const Positioned(
                    top: Sp.md,
                    right: Sp.md,
                    child: _LockChip(),
                  ),
              ],
            ),
            if (inlinePanel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, 0),
                child: inlinePanel!,
              ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.all(Sp.md),
                child: footer!,
              ),
          ],
        ),
      ),
    );
  }
}

class _LockChip extends StatelessWidget {
  const _LockChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.surface3),
      ),
      child: const Icon(Icons.lock_rounded,
          size: 14, color: AppColors.textSecondary),
    );
  }
}

class _CharacterImage extends StatelessWidget {
  final String assetPath;
  final IconData fallbackIcon;
  final double alignFactor;
  const _CharacterImage({
    required this.assetPath,
    required this.fallbackIcon,
    required this.alignFactor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          assetPath,
          fit: BoxFit.cover,
          alignment: Alignment(alignFactor * 2 - 1, -0.3),
          errorBuilder: (_, __, ___) => Container(
            color: AppColors.surface1,
            child: Center(
              child: Icon(fallbackIcon,
                  size: 56, color: AppColors.surface3),
            ),
          ),
        ),
        // Bottom shade ramp so the title + body always reads against
        // the photo regardless of its brightness.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.20),
                  Colors.black.withOpacity(0.85),
                ],
                stops: const [0.30, 0.60, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Lesson list — used inside the Eyes Part 1 card.
//  Highlighted top row (current lesson), then up to four locked rows, then
//  a "+N more lessons" toggle.
// ─────────────────────────────────────────────────────────────────────────────

class LessonListPanel extends StatelessWidget {
  final List<LessonRowSpec> rows;
  final String? currentSubtitle;
  final String? currentCta;
  final VoidCallback? onStart;
  final int extraCount;
  final bool currentLocked;

  const LessonListPanel({
    super.key,
    required this.rows,
    this.currentSubtitle,
    this.currentCta,
    this.onStart,
    this.extraCount = 0,
    this.currentLocked = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: AppColors.red.withOpacity(0.30), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rows.isNotEmpty) _currentRow(rows.first),
          if (rows.length > 1) const SizedBox(height: Sp.md),
          for (var i = 1; i < rows.length; i++) ...[
            if (i > 1)
              Container(
                  height: 1, color: AppColors.surface3,
                  margin: const EdgeInsets.symmetric(vertical: 4)),
            _lockedRow(rows[i]),
          ],
          if (extraCount > 0) ...[
            const SizedBox(height: Sp.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '+$extraCount more lessons',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more_rounded,
                    size: 18, color: AppColors.textTertiary),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _currentRow(LessonRowSpec r) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    r.label.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 3, height: 3,
                    decoration: const BoxDecoration(
                      color: AppColors.textTertiary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      r.title.toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
              if (currentSubtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  currentSubtitle!,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: AppColors.red,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: Sp.md),
        InkWell(
          onTap: onStart == null
              ? null
              : () { HapticFeedback.mediumImpact(); onStart!(); },
          borderRadius: BorderRadius.circular(28),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: currentLocked ? AppColors.surface2 : AppColors.red,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  (currentCta ?? (currentLocked ? 'LOCKED' : 'START LESSON')),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: currentLocked
                        ? AppColors.textSecondary
                        : Colors.black,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  currentLocked
                      ? Icons.lock_rounded
                      : Icons.play_arrow_rounded,
                  size: 14,
                  color: currentLocked
                      ? AppColors.textSecondary
                      : Colors.black,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _lockedRow(LessonRowSpec r) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            r.label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 3, height: 3,
            decoration: const BoxDecoration(
              color: AppColors.textMuted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              r.title.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textTertiary,
                letterSpacing: 1.6,
              ),
            ),
          ),
          const Icon(Icons.lock_rounded,
              size: 14, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class LessonRowSpec {
  final String label;
  final String title;
  const LessonRowSpec({required this.label, required this.title});
}

// ─────────────────────────────────────────────────────────────────────────────
//  Roleplay tile — small portrait card used in the Game tab "Roleplay
//  Arenas" row. Portrait fills the top 75%, lower stripe carries the
//  archetype name and the one-line line. Lock at bottom-right when gated.
// ─────────────────────────────────────────────────────────────────────────────

class RoleplayTile extends StatelessWidget {
  final String name;
  final String line;
  final String assetPath;
  final bool locked;
  final VoidCallback onTap;

  const RoleplayTile({
    super.key,
    required this.name,
    required this.line,
    required this.assetPath,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      borderRadius: BorderRadius.circular(Rd.lg),
      child: Container(
        width: 168,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(Rd.lg),
          border: Border.all(color: AppColors.surface3, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: _CharacterImage(
                assetPath: assetPath,
                fallbackIcon: Icons.face_3_rounded,
                alignFactor: 0.5,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.md, 10, Sp.md, Sp.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    line,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(
                      locked
                          ? Icons.lock_rounded
                          : Icons.play_circle_outline_rounded,
                      size: 16,
                      color: locked
                          ? AppColors.textTertiary
                          : AppColors.red,
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

// ─────────────────────────────────────────────────────────────────────────────
//  Hook line — the bold/italic single line that sits right above the
//  primary CTA. White by default, accent red when the line is the close.
// ─────────────────────────────────────────────────────────────────────────────

class HookLine extends StatelessWidget {
  final String text;
  final bool emphasised;
  const HookLine(this.text, {super.key, this.emphasised = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          fontStyle: FontStyle.italic,
          color: emphasised ? AppColors.red : AppColors.textPrimary,
          letterSpacing: 0.1,
          height: 1.45,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Feedback strip — the "Lucien's Feedback" composition at the bottom of the
//  Game tab. Small portrait on the left, italic copy on the right, flame
//  glyph trailing. Reusable for any "voice from a character" callout.
// ─────────────────────────────────────────────────────────────────────────────

class FeedbackStrip extends StatelessWidget {
  final String eyebrow;
  final String headline;
  final String body;
  final String close;
  final String assetPath;
  final IconData trailingIcon;

  const FeedbackStrip({
    super.key,
    required this.eyebrow,
    required this.headline,
    required this.body,
    required this.close,
    required this.assetPath,
    this.trailingIcon = Icons.local_fire_department_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: AppColors.surface3, width: 1),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            height: 156,
            child: _CharacterImage(
              assetPath: assetPath,
              fallbackIcon: Icons.person_rounded,
              alignFactor: 0.5,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(Sp.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    eyebrow.toUpperCase(),
                    style: AppTypography.label
                        .copyWith(color: AppColors.red, letterSpacing: 2.8),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    headline,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    close,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                      color: AppColors.red,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: Sp.md),
            child: Icon(trailingIcon, size: 32, color: AppColors.red),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Asset path constants — single source of truth so every tab references
//  the same filenames. Update HERE if a folder moves; nothing else changes.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class MirrorlyAssets {
  // One Lucien render covers every Lucien role for now — hero, speaking
  // turn, feedback strip — all three paths point at the same file. When
  // you have dedicated speaking / feedback variants, replace just those
  // two constants and the rest of the code keeps working unchanged.
  static const lucien         = 'assets/characters/lucien/lucien.png';
  static const lucienHero     = lucien;
  static const lucienSpeaking = lucien;
  static const lucienFeedback = lucien;

  static const arenaWoman     = 'assets/characters/women/arena.png';
  static const iceQueen       = 'assets/characters/women/ice_queen.png';
  static const shyGirl        = 'assets/characters/women/shy_girl.png';
  static const chaosGirl      = 'assets/characters/women/chaos_girl.png';
  static const socialite      = 'assets/characters/women/socialite.png';
  static const intellectual   = 'assets/characters/women/intellectual.png';

  static const gazeNeutral    = 'assets/eyes/partners/neutral.jpg';
  static const gazeSharp      = 'assets/eyes/partners/sharp.jpg';
  static const gazePlayful    = 'assets/eyes/partners/playful.jpg';

  static const freeFlowHer    = 'assets/game/free_flow_her.png';
  static const optimisedSplit = 'assets/scan/optimised_split.jpg';
}
