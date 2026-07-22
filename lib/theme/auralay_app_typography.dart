import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

abstract final class AppTypography {
  // ── Display (hero text, aura score) ───────────────────────────────────────
  // Playfair Display — high-contrast serif. Used on the share card score +
  // any moment we want luxury/editorial weight.
  static TextStyle display = GoogleFonts.spaceGrotesk(
    fontSize: 48,
    fontWeight: FontWeight.w900,
    color: AppColors.textPrimary,
    letterSpacing: -1.5,
    height: 1.0,
  );

  // Italic Playfair — the "voice" line on the share card + verdicts.
  static TextStyle h1Italic = GoogleFonts.spaceGrotesk(
    fontSize: 24,
    fontWeight: FontWeight.w500,
    
    color: AppColors.textPrimary,
    letterSpacing: -0.4,
    height: 1.25,
  );

  // ── Headings ──────────────────────────────────────────────────────────────
  static TextStyle h1 = GoogleFonts.inter(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.8,
    height: 1.15,
  );

  static TextStyle h2 = GoogleFonts.inter(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.4,
    height: 1.2,
  );

  static TextStyle h3 = GoogleFonts.inter(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
    height: 1.3,
  );

  // ── Body ──────────────────────────────────────────────────────────────────
  static TextStyle body = GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    letterSpacing: -0.1,
    height: 1.5,
  );

  static TextStyle bodySmall = GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    letterSpacing: 0,
    height: 1.5,
  );

  // ── Labels ─────────────────────────────────────────────────────────────────
  static TextStyle label = GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    letterSpacing: 1.2,
    height: 1.0,
  );

  // ── Live HUD coaching text (large, impactful) ─────────────────────────────
  static TextStyle hudCoach = GoogleFonts.inter(
    fontSize: 20,
    fontWeight: FontWeight.w300,
    color: AppColors.textPrimary,
    letterSpacing: 0.5,
    height: 1.0,
  );

  // ── Aura score number ─────────────────────────────────────────────────────
  static TextStyle auraScore = GoogleFonts.inter(
    fontSize: 72,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -3,
    height: 1.0,
  );

  // ── Metric delta ("+0.3s") ─────────────────────────────────────────────────
  static TextStyle delta = GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.signalGreen,
    letterSpacing: 0,
    height: 1.0,
  );

  // ── Technique name (capslock feel) ────────────────────────────────────────
  static TextStyle techniqueName = GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.accent,
    letterSpacing: 2.0,
    height: 1.0,
  );
}
