import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/creator_styles.dart';
import '../../models/face_geometry.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Bottom-sheet picker that shows creator-named haircut styles ranked for
/// the user's face shape. Tapping a style dismisses the sheet and calls
/// [onPick] with the pre-tuned Nano Banana + face-swap prompt and the
/// 'haircut' category. The consumer (chat or report) fires /tryon from
/// there — this sheet is presentation-only.
Future<void> showCreatorStylesSheet({
  required BuildContext context,
  required FaceGeometry geometry,
  required void Function(String styleRequest, String category, String styleName) onPick,
}) {
  final ranked = rankForGeometry(
    jawAngle:        geometry.jawAngle,
    faceLengthRatio: geometry.faceLengthRatio,
    fwhr:            geometry.fwhr,
    headShape:       geometry.headShape,
    take: 5,
  );
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _CreatorStylesSheet(styles: ranked, onPick: onPick),
  );
}

class _CreatorStylesSheet extends StatelessWidget {
  final List<CreatorStyle> styles;
  final void Function(String, String, String) onPick;
  const _CreatorStylesSheet({required this.styles, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.base,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24)),
            border: Border.all(color: AppColors.divider, width: 0.6),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: Sp.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CUTS THAT MOG',
                      style: AppTypography.label.copyWith(
                        color: AppColors.red,
                        letterSpacing: 2.8, fontSize: 10)),
                    const SizedBox(height: 4),
                    Text('Ranked for your face shape.',
                      style: AppTypography.h1.copyWith(
                        fontSize: 22, letterSpacing: -0.5, height: 1.1)),
                    const SizedBox(height: 4),
                    Text('Each cut is a Nano Banana render on your actual face — '
                         'pick one to see it.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 12, height: 1.4)),
                  ],
                ),
              ),
              const SizedBox(height: Sp.md),
              Expanded(
                child: ListView.separated(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(
                    Sp.lg, 0, Sp.lg, Sp.xl),
                  itemCount: styles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: Sp.sm),
                  itemBuilder: (_, i) => _StyleCard(
                    style: styles[i],
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      Navigator.pop(context);
                      onPick(styles[i].prompt, 'haircut', styles[i].name);
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StyleCard extends StatelessWidget {
  final CreatorStyle style;
  final VoidCallback onTap;
  const _StyleCard({required this.style, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.lg),
        child: Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(Rd.lg),
            border: Border.all(color: AppColors.divider, width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(style.name,
                      style: AppTypography.h3.copyWith(
                        fontSize: 16, letterSpacing: -0.2)),
                  ),
                  Icon(Icons.arrow_forward_rounded,
                    size: 16, color: AppColors.textTertiary),
                ],
              ),
              const SizedBox(height: 3),
              Text(style.tag.toUpperCase(),
                style: AppTypography.label.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 8.5, letterSpacing: 1.8)),
              const SizedBox(height: 8),
              Text(style.why,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12.5, height: 1.45)),
            ],
          ),
        ),
      ),
    );
  }
}
