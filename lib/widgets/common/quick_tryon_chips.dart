import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/face_geometry.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import 'creator_styles_sheet.dart';

/// Chip row of instant tryon prompts. Each chip is pre-wired with a smart
/// default built from the user's measurements — so "Haircut" doesn't ask
/// "what kind?", it fires a specific, measurement-aware prompt at Flux.
///
/// onTap(styleRequest, category) — consumer decides whether to send to chat
/// or directly fire tryon.
class QuickTryonChips extends StatelessWidget {
  final FaceGeometry geometry;
  final void Function(String styleRequest, String category) onTap;
  final bool compact;

  const QuickTryonChips({
    super.key,
    required this.geometry,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final actions = _buildActions(geometry);
    return SizedBox(
      height: compact ? 40 : 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final action = actions[i];
          return _Chip(
            label:    action.label,
            icon:     action.icon,
            compact:  compact,
            onTap: () {
              HapticFeedback.lightImpact();
              // Haircut opens the creator-styles picker — the user chooses
              // a named cut (edgar, curtains, low-taper…) ranked for their
              // face shape. The sheet's selection still fires through the
              // same onTap(prompt, category) contract, so /tryon wiring in
              // the consumer doesn't change.
              if (action.opensPicker) {
                showCreatorStylesSheet(
                  context: context,
                  geometry: geometry,
                  onPick: (prompt, category, _) => onTap(prompt, category),
                );
              } else {
                onTap(action.prompt, action.category);
              }
            },
          );
        },
      ),
    );
  }

  /// Smart defaults — each action's prompt is BUILT from the user's
  /// measurements so Flux renders something specifically suited to them.
  List<_QuickAction> _buildActions(FaceGeometry g) {
    final long   = g.headShape == 'long'   || g.faceLengthRatio > 1.35;
    final broad  = g.headShape == 'broad'  || g.fwhr > 2.0;
    final softJaw = g.jawAngle > 128;

    final haircutPrompt = long
      ? 'mid-fade haircut, 3-4 cm textured crop on top, side-parted, compresses vertical face length'
      : broad
        ? 'taller textured top, 5-6 cm swept upward, mid-to-low taper sides, adds vertical balance'
        : 'mid-fade with 4 cm textured top, side-parted off the stronger cheekbone';

    final beardPrompt = softJaw
      ? 'short squared beard 5-7 mm, shaped high on cheekbone, squared corners at chin, rebuilds jaw angle'
      : 'short 2-3 mm stubble, tight neckline under jaw curve, preserve jaw definition';

    final glassesPrompt = long
      ? 'rectangular matte-tortoise acetate glasses, narrower than face width, strong top bar'
      : broad
        ? 'medium round titanium glasses, proportional to cheekbone width'
        : 'medium rectangular tortoise-shell acetate glasses';

    return [
      // Haircut chip opens the creator-styles picker instead of firing a
      // single generic prompt — the prompt arg is unused for pickers, kept
      // only as a defensive fallback if the sheet ever fails to surface.
      _QuickAction(
        label: 'Haircut',
        icon: Icons.content_cut,
        category: 'haircut',
        prompt: haircutPrompt,
        opensPicker: true),
      _QuickAction(label: 'Beard',       icon: Icons.face_retouching_natural, category: 'beard', prompt: beardPrompt),
      _QuickAction(label: 'Glasses',     icon: Icons.remove_red_eye_outlined, category: 'glasses', prompt: glassesPrompt),
      _QuickAction(label: 'Clean shave', icon: Icons.face_outlined,     category: 'facial_hair', prompt: 'clean shave, smooth skin, preserve jawline exactly'),
      _QuickAction(label: 'Leaner',      icon: Icons.trending_down,     category: 'weight',      prompt: 'subtle 6-8% body fat reduction, sharper jaw and cheek contours, natural'),
      _QuickAction(label: 'Darker hair', icon: Icons.palette_outlined,  category: 'hair_color',  prompt: 'deep warm brown hair colour, preserve style and length'),
      _QuickAction(label: 'Longer hair', icon: Icons.north,             category: 'haircut',     prompt: 'medium-length hair 8 cm, natural texture, side-swept'),
    ];
  }
}

class _QuickAction {
  final String label;
  final IconData icon;
  final String category;
  final String prompt;
  /// When true, the chip opens the creator-styles picker sheet instead of
  /// firing its own `prompt` directly. Used for the Haircut chip.
  final bool opensPicker;
  _QuickAction({
    required this.label, required this.icon,
    required this.category, required this.prompt,
    this.opensPicker = false,
  });
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool compact;
  const _Chip({
    required this.label, required this.icon,
    required this.onTap, required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(100),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 14,
              vertical: compact ? 7 : 9,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface1,
              border: Border.all(color: AppColors.divider, width: 0.8),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: compact ? 12 : 13, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(label,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: compact ? 10 : 11,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
