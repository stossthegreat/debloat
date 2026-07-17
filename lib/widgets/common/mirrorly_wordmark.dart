import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';

/// The Mirrorly wordmark. "Mirror" in white, "ly" in red, italic
/// editorial Playfair — the same letterforms the rest of the app uses
/// for its title display. Splash, paywall, settings, share card,
/// masthead, intro reel, onboarding manifesto all render this.
///
/// Why italic Playfair: it's the existing brand voice (luxury
/// fragrance / editorial). The red tail keeps the two-tone brand
/// punch the Mirrorly-era mark had.
class MirrorlyWordmark extends StatelessWidget {
  final double fontSize;
  final double letterSpacing;
  final FontWeight fontWeight;
  final TextAlign? textAlign;
  /// When true the wordmark renders without italic — the only place
  /// we'd want that is small-caps tracking labels. Default: italic.
  final bool italic;

  const MirrorlyWordmark({
    super.key,
    this.fontSize       = 36,
    this.letterSpacing  = -1.0,
    this.fontWeight     = FontWeight.w800,
    this.textAlign,
    this.italic         = true,
  });

  @override
  Widget build(BuildContext context) {
    final base = GoogleFonts.playfairDisplay(
      fontSize:    fontSize,
      height:      1.0,
      letterSpacing: letterSpacing,
      fontStyle:   italic ? FontStyle.italic : FontStyle.normal,
      fontWeight:  fontWeight,
    );
    return RichText(
      textAlign: textAlign ?? TextAlign.left,
      text: TextSpan(
        style: base.copyWith(color: Colors.white),
        children: [
          const TextSpan(text: 'Mirror'),
          TextSpan(
            text: 'ly',
            style: base.copyWith(color: AppColors.red),
          ),
        ],
      ),
    );
  }
}
