import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Debloat OS typography — engineered. Space Grotesk for display (system /
/// diagnostic energy), Inter for body (modern, clinical), Space Grotesk
/// for measurements (scanner readout feel).
abstract final class AppTypography {
  // ── System display (grotesk) ─────────────────────────────────────────────
  // Space Grotesk — engineered, technical, reads like a diagnostic OS.

  static TextStyle get displayXL => GoogleFonts.spaceGrotesk(
    fontSize: 60, fontWeight: FontWeight.w700,
    letterSpacing: -2.2, color: AppColors.textPrimary, height: 1.02,
  );

  static TextStyle get display => GoogleFonts.spaceGrotesk(
    fontSize: 46, fontWeight: FontWeight.w700,
    letterSpacing: -1.6, color: AppColors.textPrimary, height: 1.06,
  );

  static TextStyle get h1 => GoogleFonts.spaceGrotesk(
    fontSize: 32, fontWeight: FontWeight.w700,
    letterSpacing: -0.8, color: AppColors.textPrimary, height: 1.1,
  );

  /// Kept for call-site compatibility — same face as [h1], lighter weight.
  static TextStyle get h1Italic => GoogleFonts.spaceGrotesk(
    fontSize: 32, fontWeight: FontWeight.w500,
    letterSpacing: -0.6, color: AppColors.textPrimary, height: 1.1,
  );

  // ── Sans (body / UI) — Inter ─────────────────────────────────────────────

  static TextStyle get h2 => GoogleFonts.inter(
    fontSize: 22, fontWeight: FontWeight.w600,
    letterSpacing: -0.5, color: AppColors.textPrimary, height: 1.25,
  );

  static TextStyle get h3 => GoogleFonts.inter(
    fontSize: 16, fontWeight: FontWeight.w600,
    letterSpacing: 0.1, color: AppColors.textPrimary, height: 1.3,
  );

  static TextStyle get body => GoogleFonts.inter(
    fontSize: 15, fontWeight: FontWeight.w400,
    letterSpacing: -0.05, color: AppColors.textSecondary, height: 1.6,
  );

  static TextStyle get bodySmall => GoogleFonts.inter(
    fontSize: 13, fontWeight: FontWeight.w400,
    color: AppColors.textSecondary, height: 1.55,
  );

  // ── Label / mono ─────────────────────────────────────────────────────────
  // All-caps labels with strong tracking — editorial typography signal.

  static TextStyle get label => GoogleFonts.inter(
    fontSize: 10, fontWeight: FontWeight.w600,
    letterSpacing: 2.4, color: AppColors.textTertiary,
  );

  static TextStyle get labelBold => GoogleFonts.inter(
    fontSize: 11, fontWeight: FontWeight.w700,
    letterSpacing: 3.2, color: AppColors.textPrimary,
  );

  static TextStyle get mono => GoogleFonts.spaceGrotesk(
    fontSize: 13, fontWeight: FontWeight.w500,
    letterSpacing: 0.2, color: AppColors.textSecondary,
  );

  static TextStyle get measurement => GoogleFonts.spaceGrotesk(
    fontSize: 11, fontWeight: FontWeight.w600,
    letterSpacing: 0.5, color: AppColors.measure,
  );
}

abstract final class Sp {
  static const double xs  = 4;
  static const double sm  = 8;
  static const double md  = 16;
  static const double lg  = 24;
  static const double xl  = 32;
  static const double xxl = 48;
  static const double xxxl = 72;
}

abstract final class Rd {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
  static const double xl = 20;
  static const double xxl = 28;
}
