import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import 'fullscreen_image.dart';

/// Before/After reveal — the viral proof-shot.
///
/// Upgrade: MAXED side arrives blurred. On first tap/swipe the blur clears.
/// This is variable-reward UX (Eyal) — the anticipation of the reveal
/// drives interaction, and once revealed it lands harder than if it had
/// always been visible. A "+N POTENTIAL" gold chip floats on the maxed
/// side as a loss-aversion hook ("you're leaving this much on the table").
class BeforeAfterCard extends StatefulWidget {
  final Uint8List? beforeBytes;
  final String? beforeUrl;
  final String? afterUrl;
  final String? caption;
  final String beforeLabel;
  final String afterLabel;
  final int? potentialDelta; // e.g. 14 for "+14 POTENTIAL"

  const BeforeAfterCard({
    super.key,
    this.beforeBytes,
    this.beforeUrl,
    required this.afterUrl,
    this.caption,
    this.beforeLabel = 'NOW',
    this.afterLabel  = 'MAXED',
    this.potentialDelta,
  });

  @override
  State<BeforeAfterCard> createState() => _BeforeAfterCardState();
}

class _BeforeAfterCardState extends State<BeforeAfterCard> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: AppColors.divider, width: 0.8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Rd.lg),
        child: AspectRatio(
          aspectRatio: 3 / 4,
          child: Stack(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _ImageHalf(
                      bytes: widget.beforeBytes,
                      url: widget.beforeUrl,
                      blurred: false,
                      onTap: () => FullscreenImage.open(context,
                        bytes: widget.beforeBytes,
                        url: widget.beforeUrl,
                        caption: widget.beforeLabel),
                    ),
                  ),
                  Container(width: 1, color: AppColors.divider),
                  Expanded(
                    child: _ImageHalf(
                      url: widget.afterUrl,
                      blurred: !_revealed,
                      onTap: () {
                        if (!_revealed) {
                          setState(() => _revealed = true);
                        } else {
                          FullscreenImage.open(context,
                            url: widget.afterUrl,
                            caption: widget.afterLabel);
                        }
                      },
                    ),
                  ),
                ],
              ),

              // Top labels
              Positioned(
                left: 0, right: 0, top: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.72),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(widget.beforeLabel,
                        style: AppTypography.label.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 10, letterSpacing: 2.6,
                          fontWeight: FontWeight.w900))),
                      Expanded(child: Text(widget.afterLabel,
                        textAlign: TextAlign.right,
                        style: AppTypography.label.copyWith(
                          color: AppColors.red,
                          fontSize: 10, letterSpacing: 2.6,
                          fontWeight: FontWeight.w900))),
                    ],
                  ),
                ),
              ),

              // Potential chip (top-right on the maxed side)
              if (widget.potentialDelta != null && widget.potentialDelta! > 0)
                Positioned(
                  top: 12, right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: [BoxShadow(
                        color: AppColors.red.withValues(alpha: 0.55),
                        blurRadius: 10)],
                    ),
                    child: Text('+${widget.potentialDelta} POTENTIAL',
                      style: AppTypography.label.copyWith(
                        color: AppColors.base,
                        fontSize: 9.5, letterSpacing: 1.8,
                        fontWeight: FontWeight.w900)),
                  ),
                )
                .animate().fadeIn(delay: 400.ms, duration: 400.ms)
                .scaleXY(begin: 0.8, end: 1, delay: 400.ms, duration: 400.ms,
                  curve: Curves.elasticOut),

              // "TAP TO REVEAL" overlay on right half while still blurred
              if (!_revealed)
                Positioned(
                  right: 0, top: 0, bottom: 0,
                  width: MediaQuery.of(context).size.width * 0.5 - 24,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: AppColors.red.withValues(alpha: 0.8),
                            width: 0.9),
                        ),
                        child: Text('TAP TO REVEAL',
                          style: AppTypography.label.copyWith(
                            color: AppColors.red,
                            fontSize: 10, letterSpacing: 2.4,
                            fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),
                ).animate(onPlay: (c) => c.repeat(reverse: true))
                  .fadeIn(duration: 900.ms),

              // Bottom caption
              if (widget.caption != null)
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.85),
                        ],
                      ),
                    ),
                    child: Text(widget.caption!,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textPrimary, fontSize: 11.5, height: 1.4,
                        fontStyle: FontStyle.italic)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageHalf extends StatelessWidget {
  final Uint8List? bytes;
  final String? url;
  final bool blurred;
  final VoidCallback onTap;
  const _ImageHalf({this.bytes, this.url, required this.blurred, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget img = bytes != null
        ? Image.memory(bytes!, fit: BoxFit.cover,
            width: double.infinity, height: double.infinity,
            gaplessPlayback: true)
        : (url != null && url!.isNotEmpty
            ? Image.network(url!, fit: BoxFit.cover,
                width: double.infinity, height: double.infinity,
                loadingBuilder: (_, child, p) => p == null ? child
                  : const Center(child: SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(
                        color: AppColors.red, strokeWidth: 2))),
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: Color(0xFF0E0E12)))
            : const ColoredBox(color: Color(0xFF0E0E12)));

    if (blurred) {
      img = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: img,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.expand(child: img),
      ),
    );
  }
}
