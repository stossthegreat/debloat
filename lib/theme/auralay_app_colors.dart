import 'package:flutter/material.dart';

/// AURALAY — black + seductive red. The whole brand reads off this file.
abstract final class AppColors {
  // ── Surfaces ───────────────────────────────────────────────────────────────
  static const base     = Color(0xFF000000); // pure black — share card prints flush against any feed
  static const surface1 = Color(0xFF0A0A0C); // cards
  static const surface2 = Color(0xFF14141A); // elevated
  static const surface3 = Color(0xFF1F1F26); // modals / borders

  // ── Text ──────────────────────────────────────────────────────────────────
  static const textPrimary   = Color(0xFFF7F5EE); // warm white
  static const textSecondary = Color(0xFFA0A0AA); // muted
  static const textTertiary  = Color(0xFF55555F); // labels
  static const textMuted     = Color(0xFF35353D); // barely there

  // ── SEDUCTIVE RED — primary accent (use everywhere a brand mark lands) ───
  // Saturated cinnabar — the share card + hero numbers + CTA all use this.
  // Same hex ImHim's hero numbers / share card use, so the brand colour
  // family carries across both apps in the user's portfolio.
  static const accent       = Color(0xFFE8222A); // primary
  static const accentBright = Color(0xFFFF3D45); // hover / lift
  static const accentDim    = Color(0xFFA61419); // pressed / dim
  static const accentBorder = Color(0x55E8222A); // 33% — visible borders
  static const accentGlow   = Color(0x22E8222A); // 13% — fill / glow bg
  static const accentSoft   = Color(0x10E8222A); //  6% — subtle washes

  // Aliases used widely across train/you screens (kept for code reuse).
  static const red          = accent;
  static const redBright    = accentBright;
  static const redDim       = accentDim;
  static const redGlow      = accentGlow;

  // ── Cold blue — scan overlay ONLY (live mesh feedback) ───────────────────
  static const scanBlue       = Color(0xFF60A5FA);
  static const scanBlueDim    = Color(0xFF1D4ED8);
  static const scanBlueBorder = Color(0x2060A5FA);
  static const scanLineColor  = Color(0x4060A5FA);

  // ── Signal (live coaching feedback) ───────────────────────────────────────
  static const signalGreen       = Color(0xFF22C55E);
  static const signalAmber       = Color(0xFFF59E0B);
  static const signalRed         = Color(0xFFEF4444);
  static const signalGreenBorder = Color(0x4022C55E);
  static const signalAmberBorder = Color(0x40F59E0B);
  static const signalRedBorder   = Color(0x40EF4444);

  // ── UI chrome ─────────────────────────────────────────────────────────────
  static const divider = Color(0xFF14141B);
  static const scrim   = Color(0xCC000000);
}
