import 'package:flutter/material.dart';
import '../../models/face_geometry.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import 'measurement_grid.dart';

/// The 16-metric deep-dive. Previously a tap-to-expand disclosure — now
/// rendered directly, inline with the rest of the full breakdown. Small
/// section header still present so it reads as a distinct block of the
/// report rather than a random measurement dump.
class HiddenDepthPanel extends StatelessWidget {
  final FaceGeometry geometry;
  const HiddenDepthPanel({super.key, required this.geometry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(
          color: AppColors.measure.withValues(alpha: 0.26), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: AppColors.measure.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.measure.withValues(alpha: 0.55),
                    width: 0.8),
                ),
                child: const Icon(Icons.data_usage_rounded,
                  size: 16, color: AppColors.measure),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FULL MEASUREMENT GRID',
                      style: AppTypography.label.copyWith(
                        color: AppColors.measure,
                        letterSpacing: 2.6, fontSize: 10)),
                    const SizedBox(height: 3),
                    Text('All 16 measurements · every angle, every ratio',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 11.5, height: 1.3)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          MeasurementGrid(g: geometry),
        ],
      ),
    );
  }
}
