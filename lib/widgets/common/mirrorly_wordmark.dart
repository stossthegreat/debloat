import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';

/// The Debloat OS wordmark. "Debloat" in white, "OS" in brand cyan —
/// Space Grotesk, tight tracking, no italic. Reads like a system boot
/// logo. Splash, paywall, settings, share cards, masthead, intro reel,
/// onboarding all render this.
class DebloatWordmark extends StatelessWidget {
  final double fontSize;
  final double letterSpacing;
  final FontWeight fontWeight;
  final TextAlign? textAlign;
  /// Kept for call-site compatibility — the mark never italicises.
  final bool italic;

  const DebloatWordmark({
    super.key,
    this.fontSize       = 36,
    this.letterSpacing  = -1.2,
    this.fontWeight     = FontWeight.w700,
    this.textAlign,
    this.italic         = false,
  });

  @override
  Widget build(BuildContext context) {
    final base = GoogleFonts.spaceGrotesk(
      fontSize:    fontSize,
      height:      1.0,
      letterSpacing: letterSpacing,
      fontWeight:  fontWeight,
    );
    return RichText(
      textAlign: textAlign ?? TextAlign.left,
      text: TextSpan(
        style: base.copyWith(color: Colors.white),
        children: [
          const TextSpan(text: 'Debloat'),
          TextSpan(
            text: ' OS',
            style: base.copyWith(
              color: AppColors.brand,
              shadows: [
                Shadow(
                  color: AppColors.brand.withValues(alpha: 0.55),
                  blurRadius: fontSize * 0.45,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Legacy alias — every pre-rebrand call-site referenced
/// [MirrorlyWordmark]; keep the old name resolving to the new mark so
/// nothing churns. New code should use [DebloatWordmark].
typedef MirrorlyWordmark = DebloatWordmark;
