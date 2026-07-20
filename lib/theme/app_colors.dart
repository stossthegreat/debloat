import 'package:flutter/material.dart';

/// ImHim Looks palette — editorial black, surgical indigo, laboratory sky.
/// Reads like an analysis report from a high-end cosmetic surgery clinic.
abstract final class AppColors {
  // ── Base layers (near-black to elevated) ─────────────────────────────────
  static const base       = Color(0xFF07070A); // deeper than black
  static const surface1   = Color(0xFF0E0E12); // first lift
  static const surface2   = Color(0xFF16161B); // card
  static const surface3   = Color(0xFF23232A); // divider/stroke
  static const surfaceElevated = Color(0xFF1D1D24); // overlay cards

  // ── Accent (indigo) ──────────────────────────────────────────────────────
  static const accent     = Color(0xFF8B94F5); // softer indigo
  static const accentDeep = Color(0xFF6366F1);
  static const accentBorder = Color(0xFF3730A3);
  static const accentGlow = Color(0x338B94F5); // translucent glow

  // ── Measurement sky ──────────────────────────────────────────────────────
  static const measure    = Color(0xFF38BDF8);
  static const measureDim = Color(0xFF0EA5E9);
  static const measureGlow = Color(0x3338BDF8);

  // ── Red — primary brand accent (replaced gold). Saturated cinnabar — the
  // same red the share-card and result hero numbers already use; promoted to
  // the app-wide secondary color so the palette reads as one consistent voice
  // (black + white + red) across every surface.
  static const red        = Color(0xFFE8222A);
  static const redDim     = Color(0xFFA61419);
  static const redGlow    = Color(0x33E8222A);

  // ── Text (high-contrast editorial) ───────────────────────────────────────
  static const textPrimary   = Color(0xFFF7F7F9);
  static const textSecondary = Color(0xFFA8A8B2);
  static const textTertiary  = Color(0xFF6D6D78);
  static const textMuted     = Color(0xFF4A4A55);

  // ── Signals ──────────────────────────────────────────────────────────────
  static const signalGreen = Color(0xFF4ADE80);
  static const signalAmber = Color(0xFFFBBF24);
  static const signalRed   = Color(0xFFF87171);

  // ── Utility ──────────────────────────────────────────────────────────────
  static const divider = Color(0xFF1F1F26);
  static const scrim   = Color(0xCC000000);
}
