import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Debloat OS tab kit — the shared vocabulary every primary tab is built from.
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
    // Display sizes scaled down from the mockup so longer headlines
    // ("Knows your bones to the millimetre.") fit on a phone in TWO
    // lines max. BOTH lines live inside ONE FittedBox so they scale
    // proportionally together — if "to the millimetre." needs to
    // shrink to fit, "knows your bones" shrinks the same amount and
    // the block stays visually consistent. Previously each line had
    // its own FittedBox which let one line stay big while the other
    // wrapped mid-word — the bug in the Mirror screenshot.
    final display = GoogleFonts.spaceGrotesk(
      fontSize: 34,
      fontWeight: FontWeight.w800,
      
      letterSpacing: -1.2,
      height: 1.05,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
      child: Column(
        crossAxisAlignment: align,
        children: [
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    lineOne.toUpperCase(),
                    maxLines: 1,
                    softWrap: false,
                    style: display.copyWith(color: AppColors.textPrimary),
                  ),
                  Text(
                    lineTwo.toUpperCase(),
                    maxLines: 1,
                    softWrap: false,
                    style: display.copyWith(color: AppColors.red),
                  ),
                ],
              ),
            ),
          ),
          if (subhead != null) ...[
            const SizedBox(height: Sp.md),
            Text(
              subhead!,
              style: GoogleFonts.inter(
                fontSize: 15,
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

// ─────────────────────────────────────────────────────────────────────────────
//  Character card — the big cinema card with a photoreal portrait, an
//  italic title, body copy, and an optional inline panel (the Eyes "Lesson 01
//  · The Lock" sub-card sits inside this). Top-right lock chip when gated.
//
//  Image is loaded via Image.asset(assetPath) with a graceful errorBuilder
//  so the layout looks correct before any JPEGs are dropped in. The whole
//  card is tappable when [onTap] is provided.
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
//  Lesson list — used inside the Eyes Part 1 card.
//  Highlighted top row (current lesson), then up to four locked rows, then
//  a "+N more lessons" toggle.
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
//  Roleplay tile — small portrait card used in the Game tab "Roleplay
//  Arenas" row. Portrait fills the top 75%, lower stripe carries the
//  archetype name and the one-line line. Lock at bottom-right when gated.
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
//  Hook line — the bold/italic single line that sits right above the
//  primary CTA. White by default, accent red when the line is the close.
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
//  Feedback strip — the "Lucien's Feedback" composition at the bottom of the
//  Game tab. Small portrait on the left, italic copy on the right, flame
//  glyph trailing. Reusable for any "voice from a character" callout.
// ─────────────────────────────────────────────────────────────────────────────

