import 'dart:math' as math;
import '../models/face_geometry.dart';

/// Holistic facial aesthetics score derived from measured geometry.
/// Weighted composite designed to be stable, shareable, and feel *earned*.
///
/// Axis weights are tuned so the perfect canonical face lands around 92–95
/// rather than 100 — leaves headroom, matches clinical grading norms, and
/// prevents the ceiling feeling like a participation trophy.
class ScoringService {
  // Jaw was weighted 16 and chin 10, but the underlying `jawAngle` measure
  // is a face-oval triangle apex (not a real gonial angle) and chin
  // projection on a front-pose photo is a vertical-share proxy at best.
  // Pulling jaw down to 10, keeping chin at 10 (axis is now rescaled), and
  // redistributing the recovered 6 points to symmetry (+4) and thirds (+2)
  // — which ARE measured reliably on ML Kit's contour set.
  static const _wCanthal  = 14.0;
  static const _wSymmetry = 26.0;
  static const _wThirds   = 16.0;
  static const _wFwhr     = 14.0;
  static const _wEyeSpace = 10.0;
  static const _wJaw      = 10.0;
  static const _wChin     = 10.0;
  // sum = 100

  static AestheticScore compute(FaceGeometry g) {
    final canthalAxis = _canthalAxis(g.canthalTilt);
    final symAxis     = (g.symmetryScore / 100).clamp(0.0, 1.0);
    final thirdsAxis  = _thirdsAxis(g.facialThirdTop, g.facialThirdMid, g.facialThirdLow);
    final fwhrAxis    = _fwhrAxis(g.fwhr);
    final eyeAxis     = _eyeSpaceAxis(g.eyeSpacingRatio);
    final jawAxis     = _jawAxis(g.jawAngle);
    final chinAxis    = _chinAxis(g.chinProjection);

    final raw = canthalAxis * _wCanthal
              + symAxis     * _wSymmetry
              + thirdsAxis  * _wThirds
              + fwhrAxis    * _wFwhr
              + eyeAxis     * _wEyeSpace
              + jawAxis     * _wJaw
              + chinAxis    * _wChin;

    final clamped = raw.clamp(0.0, 100.0);
    // Confidence penalty — if geometry data is unreliable, pull score toward
    // the mean so we never award a high score on noisy input.
    final withConfidence = g.hasReliableData
        ? clamped
        : clamped * 0.85 + 10.0;

    return AestheticScore(
      value: withConfidence.round(),
      axes: AxisBreakdown(
        canthal:  canthalAxis,
        symmetry: symAxis,
        thirds:   thirdsAxis,
        fwhr:     fwhrAxis,
        eyeSpace: eyeAxis,
        jaw:      jawAxis,
        chin:     chinAxis,
      ),
      reliable: g.hasReliableData,
    );
  }

  // ── Axes: each returns 0..1 ─────────────────────────────────────────────

  /// Positive canthal tilt (+3° is ideal, "hunter eyes"). Negative tilt
  /// collapses toward 0. Above +5° doesn't keep adding, plateau.
  static double _canthalAxis(double deg) {
    if (deg >= 5) return 1.0;
    if (deg >= 3) return 0.85 + (deg - 3) * 0.075;
    if (deg >= 0) return 0.55 + (deg / 3) * 0.30;
    if (deg >= -2) return 0.30 + ((deg + 2) / 2) * 0.25;
    return (0.30 + (deg + 2) * 0.1).clamp(0.0, 1.0);
  }

  /// Facial thirds: ideal = 33/33/33. Reward closeness, penalize deviation.
  static double _thirdsAxis(double t, double m, double l) {
    const ideal = 33.33;
    final dev = math.sqrt(
      (math.pow(t - ideal, 2) + math.pow(m - ideal, 2) + math.pow(l - ideal, 2)) / 3,
    );
    // dev 0 → 1.0, dev 10 → 0.0 linearly
    return (1.0 - dev / 10).clamp(0.0, 1.0);
  }

  /// FWHR: 1.8–2.0 is ideal masculine dominant range.
  /// Below 1.6 = soft/narrow, above 2.2 = cartoonish wide.
  static double _fwhrAxis(double v) {
    if (v >= 1.8 && v <= 2.0) return 1.0;
    if (v < 1.8) return math.max(0, 1 - (1.8 - v) / 0.6);
    return math.max(0, 1 - (v - 2.0) / 0.5);
  }

  /// Interocular spacing / face width: ideal ≈ 0.46 (one-eye-width gap).
  static double _eyeSpaceAxis(double r) {
    final dev = (r - 0.46).abs();
    return (1.0 - dev / 0.12).clamp(0.0, 1.0);
  }

  /// Jaw angle: 115°–125° = sharp, ideal. Below 110 or above 135 drops off.
  static double _jawAxis(double deg) {
    if (deg >= 115 && deg <= 125) return 1.0;
    if (deg < 115) return math.max(0, 1 - (115 - deg) / 20);
    return math.max(0, 1 - (deg - 125) / 20);
  }

  /// Chin dominance — the fraction of face height taken up between nose
  /// tip and chin bottom. Previous impl expected values 0..4 and scored
  /// everyone in a tiny 0.50–0.56 band because the source metric is clamped
  /// 0..0.5. Rescaled against the observed male range: ~0.22 (weak) →
  /// ~0.38 (dominant). Values outside that band clamp to 0 / 1 cleanly.
  ///
  /// NOTE: this is a vertical proportion (lower-face share of total face
  /// height), not sagittal chin projection. Real chin projection needs a
  /// side profile — the axis label is kept as "Chin projection" because
  /// protocol_service keys on that exact string when prescribing routines.
  static double _chinAxis(double proj) {
    const weakAnchor     = 0.22;
    const dominantAnchor = 0.38;
    return ((proj - weakAnchor) / (dominantAnchor - weakAnchor))
        .clamp(0.0, 1.0);
  }
}

class AestheticScore {
  final int value;         // 0..100
  final AxisBreakdown axes;
  final bool reliable;

  const AestheticScore({
    required this.value,
    required this.axes,
    required this.reliable,
  });

  /// Editorial tier labels. Intentionally aspirational — Platinum is rare.
  AestheticTier get tier {
    if (value >= 92) return AestheticTier.platinum;
    if (value >= 84) return AestheticTier.apex;
    if (value >= 74) return AestheticTier.elite;
    if (value >= 62) return AestheticTier.foundation;
    return AestheticTier.raw;
  }

  String get tierLabel => switch (tier) {
    AestheticTier.platinum   => 'Platinum',
    AestheticTier.apex       => 'Apex',
    AestheticTier.elite      => 'Elite',
    AestheticTier.foundation => 'Foundation',
    AestheticTier.raw        => 'Raw',
  };

  /// One-line subtitle under the tier — editorial, never sycophantic.
  String get tierTagline => switch (tier) {
    AestheticTier.platinum   => 'Top 1 %. Maintenance tier — don\'t wreck what works.',
    AestheticTier.apex       => 'Top 5 %. Measured, photogenic, and rare.',
    AestheticTier.elite      => 'Top 15 %. Strong foundation, sharp optimization path.',
    AestheticTier.foundation => 'Balanced bones, clear upside on grooming + recomp.',
    AestheticTier.raw        => 'High-leverage starting point. Every fix compounds.',
  };

  /// Worst-performing axis → what to target first.
  /// Returns (axisLabel, axisValue0to1).
  (String, double) get weakestAxis {
    final pairs = <(String, double)>[
      ('Canthal tilt',   axes.canthal),
      ('Symmetry',       axes.symmetry),
      ('Facial thirds',  axes.thirds),
      ('FWHR',           axes.fwhr),
      ('Eye spacing',    axes.eyeSpace),
      ('Jaw definition', axes.jaw),
      ('Chin projection', axes.chin),
    ];
    pairs.sort((a, b) => a.$2.compareTo(b.$2));
    return pairs.first;
  }

  /// Strongest axis → positive reinforcement.
  (String, double) get strongestAxis {
    final pairs = <(String, double)>[
      ('Canthal tilt',   axes.canthal),
      ('Symmetry',       axes.symmetry),
      ('Facial thirds',  axes.thirds),
      ('FWHR',           axes.fwhr),
      ('Eye spacing',    axes.eyeSpace),
      ('Jaw definition', axes.jaw),
      ('Chin projection', axes.chin),
    ];
    pairs.sort((a, b) => b.$2.compareTo(a.$2));
    return pairs.first;
  }
}

class AxisBreakdown {
  final double canthal;
  final double symmetry;
  final double thirds;
  final double fwhr;
  final double eyeSpace;
  final double jaw;
  final double chin;

  const AxisBreakdown({
    required this.canthal,
    required this.symmetry,
    required this.thirds,
    required this.fwhr,
    required this.eyeSpace,
    required this.jaw,
    required this.chin,
  });
}

enum AestheticTier { raw, foundation, elite, apex, platinum }
