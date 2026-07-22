import 'package:flutter/material.dart';

/// Debloat OS palette — engineered ice. Deep blue-black base, electric
/// cyan brand accent (water / drainage / cold), laboratory sky for
/// measurements. Reads like a diagnostic system, not a beauty app.
abstract final class AppColors {
  // ── Base layers (blue-black to elevated) ─────────────────────────────────
  static const base       = Color(0xFF05090B); // deep blue-black
  static const surface1   = Color(0xFF0B1114); // first lift
  static const surface2   = Color(0xFF121A1E); // card
  static const surface3   = Color(0xFF1F2B31); // divider/stroke
  static const surfaceElevated = Color(0xFF18232A); // overlay cards

  // ── Accent (ice blue) ────────────────────────────────────────────────────
  static const accent     = Color(0xFF7DD3FC); // soft ice
  static const accentDeep = Color(0xFF0EA5E9);
  static const accentBorder = Color(0xFF155E75);
  static const accentGlow = Color(0x337DD3FC); // translucent glow

  // ── Measurement sky ──────────────────────────────────────────────────────
  static const measure    = Color(0xFF38BDF8);
  static const measureDim = Color(0xFF0EA5E9);
  static const measureGlow = Color(0x3338BDF8);

  // ── Brand cyan — THE Debloat OS color. Electric ice-cyan: cold water,
  // drainage, system-on. Every surface that used to carry the Debloat OS red
  // now carries this — one repaint, whole app rebrands. The `red` name
  // is kept as an alias so the existing call-sites don't churn; treat
  // `brand` as the canonical name in new code.
  static const brand      = Color(0xFF22D3EE);
  static const brandDim   = Color(0xFF0E7490);
  static const brandGlow  = Color(0x3322D3EE);
  static const red        = brand;
  static const redDim     = brandDim;
  static const redGlow    = brandGlow;

  // ── Text (high-contrast, cool-tinted) ────────────────────────────────────
  static const textPrimary   = Color(0xFFF5F9FA);
  static const textSecondary = Color(0xFFA3B1B8);
  static const textTertiary  = Color(0xFF64747D);
  static const textMuted     = Color(0xFF41505A);

  // ── Signals ──────────────────────────────────────────────────────────────
  static const signalGreen = Color(0xFF4ADE80);
  static const signalAmber = Color(0xFFFBBF24);
  static const signalRed   = Color(0xFFF87171);

  // ── Utility ──────────────────────────────────────────────────────────────
  static const divider = Color(0xFF1A252B);
  static const scrim   = Color(0xCC000000);
}
