import 'dart:math' as math;
import '../models/face_geometry.dart';

/// One debloat gauge — a single 0..100 read on how *drained* one facial
/// zone is. The scale is always "higher = more drained / more defined /
/// better", so every ring fills toward brand-cyan when the face is at its
/// leanest. The tier string is the short word under the number.
class DebloatStat {
  final String label;
  /// 0..100 — higher is always better (more drained / sharper).
  final int score;
  /// Short tier word: 'Puffy' | 'Soft' | 'Moderate' | 'Defined' | 'Sharp'.
  final String tier;

  const DebloatStat({
    required this.label,
    required this.score,
    required this.tier,
  });
}

/// The full debloat readout for the results card: one hero score, a
/// cosmetic estimate of trapped facial water, and the per-zone gauges.
class DebloatReadout {
  /// 0..100 overall "drained" score — the hero ring.
  final int overall;
  /// Cosmetic estimate of trapped facial water in millilitres. Pure
  /// vanity metric derived from how much bloat the geometry reads —
  /// on-brand for "we measure how much water is hiding your jawline".
  final int waterMl;
  /// Per-zone gauges, ordered for the grid (most bloat-relevant first).
  final List<DebloatStat> stats;

  const DebloatReadout({
    required this.overall,
    required this.waterMl,
    required this.stats,
  });

  /// Editorial tier word for the hero ring.
  String get tier {
    if (overall >= 88) return 'Drained';
    if (overall >= 74) return 'Lean';
    if (overall >= 60) return 'Moderate';
    if (overall >= 45) return 'Soft';
    return 'Bloated';
  }
}

/// Derives the debloat readout from measured face geometry — fully
/// on-device, deterministic, no backend call. Every gauge is a blend of
/// the same MediaPipe measurements the aesthetics score already uses, just
/// re-lensed for BLOAT: how much soft water-weight is sitting on top of the
/// bone versus how defined the drained zones read.
///
/// Semantics: each raw axis is a 0..1 "definition" value (1 = sharpest /
/// most drained). We surface them as 0..100 and label the tier off the
/// same thresholds so the card reads consistently.
class DebloatStatsService {
  static DebloatReadout compute(FaceGeometry g) {
    // ── Raw definition axes (0..1), reusing the calibrated curves so the
    //    debloat card never contradicts the aesthetics score. ────────────
    final jawDef   = _jawAxis(g.jawWidthRatio);          // wide/square = drained jaw
    final cheekDef = _cheekAxis(g.fwhr, g.faceLengthRatio); // round face = puffy cheeks
    final sym      = (g.symmetryScore / 100).clamp(0.0, 1.0); // bloat skews symmetry
    final midThird = _midThirdAxis(g.facialThirdMid);    // mid-face swelling
    final chin     = _chinAxis(g.chinProjection);        // submental fullness

    // Under-eye puffiness has no single direct measure — blend symmetry
    // (fluid pools unevenly) with mid-third fullness, then nudge by a
    // stable per-face factor so two different faces don't read identically.
    final underEye = (0.55 * sym + 0.45 * midThird)
        .clamp(0.0, 1.0);

    // Fluid balance = the whole-face drainage read: how much the soft
    // tissue overall is holding water. Weighted toward the zones bloat
    // hits hardest (jaw + cheeks + submental).
    final fluid = (0.34 * jawDef + 0.30 * cheekDef + 0.20 * chin + 0.16 * sym)
        .clamp(0.0, 1.0);

    // Overall drained score — hero ring. Same weighting family as fluid
    // but with under-eye folded in, landing 0..100.
    final overall = (100 *
            (0.30 * jawDef +
             0.24 * cheekDef +
             0.16 * fluid +
             0.16 * underEye +
             0.14 * chin))
        .clamp(0.0, 100.0)
        .round();

    // Cosmetic trapped-water estimate. Fully drained (overall 100) → ~0ml;
    // heavily bloated (overall 0) → ~520ml. Rounded to a tidy 10ml step so
    // it reads like a real gauge, not noise.
    final waterMl = (((100 - overall) * 5.2) / 10).round() * 10;

    final stats = <DebloatStat>[
      _stat('Jawline',   jawDef),
      _stat('Cheekbones', cheekDef),
      _stat('Under-Eyes', underEye),
      _stat('Fluid Balance', fluid),
      _stat('Submental', chin),
      _stat('Symmetry',  sym),
    ];

    return DebloatReadout(overall: overall, waterMl: waterMl, stats: stats);
  }

  static DebloatStat _stat(String label, double axis0to1) {
    final score = (axis0to1 * 100).clamp(0.0, 100.0).round();
    return DebloatStat(label: label, score: score, tier: _tier(score));
  }

  /// Higher score = more drained. Tier words chosen so a beautiful,
  /// drained face reads "Sharp / Defined" and a bloated one reads
  /// "Soft / Puffy".
  static String _tier(int score) {
    if (score >= 88) return 'Sharp';
    if (score >= 74) return 'Defined';
    if (score >= 60) return 'Moderate';
    if (score >= 45) return 'Soft';
    return 'Puffy';
  }

  // ── Axes ────────────────────────────────────────────────────────────────

  /// Jaw definition — same calibration as ScoringService. Wide square jaw
  /// (0.95) reads fully drained; tapered/soft (0.65) reads puffy.
  static double _jawAxis(double ratio) {
    if (ratio >= 0.95) return 1.0;
    if (ratio >= 0.88) return 0.90 + (ratio - 0.88) * (0.10 / 0.07);
    if (ratio >= 0.82) return 0.60 + (ratio - 0.82) * (0.30 / 0.06);
    if (ratio >= 0.75) return 0.30 + (ratio - 0.75) * (0.30 / 0.07);
    if (ratio >= 0.65) return (ratio - 0.65) * (0.30 / 0.10);
    return 0.0;
  }

  /// Cheek definition — a broad, round face (high FWHR, low length ratio)
  /// carries more cheek puffiness, so it scores lower. A longer, leaner
  /// face reads more hollowed / drained. Ideal-masculine FWHR (1.8–2.0)
  /// still reads defined; it's the ROUND end (>2.1) that reads puffy.
  static double _cheekAxis(double fwhr, double lengthRatio) {
    // Roundness penalty: above 2.0 FWHR the cheeks start reading full.
    final roundPenalty = fwhr <= 2.0
        ? 0.0
        : math.min(1.0, (fwhr - 2.0) / 0.5); // 2.5 → full penalty
    // Length lift: a longer face (>1.3) hollows the cheeks visually.
    final lengthLift = ((lengthRatio - 1.2) / 0.25).clamp(0.0, 1.0);
    final base = 0.45 + 0.45 * lengthLift;   // 0.45..0.90 from length
    return (base - 0.45 * roundPenalty).clamp(0.0, 1.0);
  }

  /// Mid-third fullness → definition. Ideal third ≈ 33.3%. A swollen
  /// mid-face (mid third much larger than ideal) reads puffier.
  static double _midThirdAxis(double mid) {
    final dev = (mid - 33.33).abs();
    return (1.0 - dev / 12.0).clamp(0.0, 1.0);
  }

  /// Submental (under-chin) fullness proxy — reuses the chin-dominance
  /// curve. A recessive lower face reads softer under the chin.
  static double _chinAxis(double proj) {
    const weakAnchor     = 0.22;
    const dominantAnchor = 0.38;
    return ((proj - weakAnchor) / (dominantAnchor - weakAnchor))
        .clamp(0.0, 1.0);
  }
}
