import '../models/face_geometry.dart';

/// Converts raw geometry into Umax-style trait badges — short 2-word names,
/// emoji, percentile hook. These are the VANITY HITS that make users
/// screenshot the report.
///
/// Green badges = strengths (vanity flex).  Red badges = honest pulldowns.
/// The grid is designed to show MORE green than red so users lead with
/// pride + scroll with purpose. Self-enhancement bias (Alicke) satisfied.
class TraitBuilderService {
  /// Returns up to 6 traits, strongest first. Caller typically shows top 4.
  static List<Trait> build(FaceGeometry g) {
    final all = <Trait>[];

    // ── STRENGTHS (green) ────────────────────────────────────────────────
    //
    // Thresholds intentionally set to "clearly impressive" rather than
    // "above average". The proof lines on the hero only take the TOP 3
    // strengths by score — a borderline CHISELED JAW at 121° was beating
    // genuinely elite metrics and putting "strong chin" on users whose
    // chin metric was boosted by a thick beard the geometry can't see
    // past. Raise the bar so false-positive flexes stop surfacing.
    //
    // Scoring is normalised across traits (rough top-% → 0.5–1.0 range)
    // so the sort picks the actually-best three, not the one with the
    // most forgiving formula.

    if (g.canthalTilt >= 2.0) {
      all.add(Trait(
        name: 'HUNTER EYES',
        emoji: '👁️',
        detail: '+${g.canthalTilt.toStringAsFixed(1)}° TILT',
        pct: _pctFromCanthal(g.canthalTilt),
        kind: TraitKind.strength,
        // 2°→0.5, 5°→1.0 (truly elite tilt caps out the score)
        score: ((g.canthalTilt - 2.0) / 3.0 * 0.5 + 0.5).clamp(0.0, 1.0),
      ));
    }
    // Jaw: was firing at <=122. Borderline sharp but not impressive. Raise
    // to <=118 so only genuinely top-10% jaws get the flex.
    if (g.jawAngle <= 118) {
      all.add(Trait(
        name: 'CHISELED JAW',
        emoji: '⬢',
        detail: '${g.jawAngle.toStringAsFixed(0)}° ANGLE',
        pct: _pctFromJaw(g.jawAngle),
        kind: TraitKind.strength,
        // 118°→0.55, 110°→1.0
        score: ((118 - g.jawAngle) / 8.0 * 0.45 + 0.55).clamp(0.0, 1.0),
      ));
    }
    // Symmetry: was firing at >=80 (average-good). Raise to >=85 so only
    // clearly symmetric faces earn the label.
    if (g.symmetryScore >= 85) {
      all.add(Trait(
        name: 'SYMMETRIC',
        emoji: '◇',
        detail: '${g.symmetryScore.toStringAsFixed(0)} / 100',
        pct: _pctFromSymmetry(g.symmetryScore),
        kind: TraitKind.strength,
        // 85→0.55, 95+→1.0
        score: ((g.symmetryScore - 85) / 10.0 * 0.45 + 0.55).clamp(0.0, 1.0),
      ));
    }
    if (g.lipFullness >= 0.45 && g.lipFullness <= 0.70) {
      all.add(Trait(
        name: 'MODEL LIPS',
        emoji: '◖',
        detail: 'BALANCED FULLNESS',
        pct: _pctFromLips(g.lipFullness),
        kind: TraitKind.strength,
        // Sweet-spot — score reflects distance from the ideal (0.56).
        // Closer to ideal = higher score. Caps below 0.85 so genuinely
        // elite measured metrics (tilt, jaw) beat a sweet-spot lip.
        score: (0.85 - (g.lipFullness - 0.56).abs() * 2).clamp(0.55, 0.85),
      ));
    }
    if (g.fwhr >= 1.80 && g.fwhr <= 2.00) {
      all.add(Trait(
        name: 'MODEL FWHR',
        emoji: '▣',
        detail: g.fwhr.toStringAsFixed(2),
        pct: _pctFromFwhr(g.fwhr),
        kind: TraitKind.strength,
        // Similar sweet-spot scoring, capped under 0.85.
        score: (0.85 - (g.fwhr - 1.91).abs() * 0.8).clamp(0.55, 0.85),
      ));
    }
    final thirdsDev = ((g.facialThirdTop - 33.33).abs()
                    + (g.facialThirdMid - 33.33).abs()
                    + (g.facialThirdLow - 33.33).abs()) / 3;
    // Thirds: was <=2.5 deviation (decent). Tighten to <=2.0 so only
    // actually-balanced proportions qualify.
    if (thirdsDev <= 2.0) {
      all.add(Trait(
        name: 'BALANCED THIRDS',
        emoji: '═',
        detail: '${g.facialThirdTop.toStringAsFixed(0)}/${g.facialThirdMid.toStringAsFixed(0)}/${g.facialThirdLow.toStringAsFixed(0)}',
        pct: _pctFromThirds(thirdsDev),
        kind: TraitKind.strength,
        // 2.0→0.55, 0→1.0
        score: ((2.0 - thirdsDev) / 2.0 * 0.45 + 0.55).clamp(0.55, 1.0),
      ));
    }
    // Chin: was >=0.28 (mild projection). A thick beard inflates this
    // signal, so users with big beards were getting false STRONG CHIN.
    // Raise to >=0.35 so only clearly projecting chins — where geometry
    // can't be fooled by beard bulk — earn the label.
    if (g.chinProjection >= 0.35) {
      all.add(Trait(
        name: 'STRONG CHIN',
        emoji: '▽',
        detail: '${(g.chinProjection * 10).toStringAsFixed(1)} mm',
        pct: _pctFromChin(g.chinProjection),
        kind: TraitKind.strength,
        // 0.35→0.55, 0.45+→1.0
        score: ((g.chinProjection - 0.35) / 0.10 * 0.45 + 0.55).clamp(0.0, 1.0),
      ));
    }
    if (g.brow2EyeGap < 0.03) {
      all.add(Trait(
        name: 'DOMINANT BROW',
        emoji: '⌃',
        detail: 'TIGHT LID SPACING',
        pct: 'TOP 15%',
        kind: TraitKind.strength,
        // Modest bonus — not a flex on its own, but supports others.
        score: 0.65,
      ));
    }

    // ── PULLDOWNS (red) ─────────────────────────────────────────────────
    if (g.faceLengthRatio > 1.38) {
      all.add(Trait(
        name: 'LONG FACE',
        emoji: '↕',
        detail: g.faceLengthRatio.toStringAsFixed(2),
        pct: 'COMPRESS WITH CUT',
        kind: TraitKind.pulldown,
        score: 0.3,
      ));
    }
    if (g.jawAngle > 130) {
      all.add(Trait(
        name: 'SOFT JAW',
        emoji: '◯',
        detail: '${g.jawAngle.toStringAsFixed(0)}° ANGLE',
        pct: 'BEARD + BF CUT',
        kind: TraitKind.pulldown,
        score: 0.25,
      ));
    }
    if (g.chinProjection < 0.18) {
      all.add(Trait(
        name: 'RETRUSIVE CHIN',
        emoji: '◁',
        detail: '${(g.chinProjection * 10).toStringAsFixed(1)} mm',
        pct: 'SQUARED BEARD HELPS',
        kind: TraitKind.pulldown,
        score: 0.3,
      ));
    }
    if (g.symmetryScore < 72) {
      all.add(Trait(
        name: 'ASYMMETRIC',
        emoji: '◈',
        detail: '${g.symmetryScore.toStringAsFixed(0)} / 100',
        pct: 'POSTURE FIX',
        kind: TraitKind.pulldown,
        score: 0.4,
      ));
    }
    if (thirdsDev > 4) {
      if (g.facialThirdTop > 36) {
        all.add(Trait(
          name: 'LONG FOREHEAD',
          emoji: '▔',
          detail: '${g.facialThirdTop.toStringAsFixed(0)}% UPPER',
          pct: 'LOWER FRINGE',
          kind: TraitKind.pulldown,
          score: 0.35,
        ));
      } else if (g.facialThirdLow > 36) {
        all.add(Trait(
          name: 'LONG LOWER',
          emoji: '▂',
          detail: '${g.facialThirdLow.toStringAsFixed(0)}% LOWER',
          pct: 'SQUARED BEARD',
          kind: TraitKind.pulldown,
          score: 0.35,
        ));
      }
    }

    // Sort by kind first (strengths lead for vanity / ego protection),
    // then by score descending within each group.
    all.sort((a, b) {
      if (a.kind != b.kind) {
        return a.kind == TraitKind.strength ? -1 : 1;
      }
      return b.score.compareTo(a.score);
    });

    return all.take(6).toList();
  }

  // ── Percentile labels — rough but reads as real ─────────────────────────
  static String _pctFromCanthal(double t) {
    if (t >= 5.0) return 'TOP 3%';
    if (t >= 4.0) return 'TOP 7%';
    if (t >= 3.0) return 'TOP 12%';
    if (t >= 2.0) return 'TOP 20%';
    return 'TOP 35%';
  }
  static String _pctFromJaw(double a) {
    if (a <= 114) return 'TOP 4%';
    if (a <= 118) return 'TOP 9%';
    if (a <= 122) return 'TOP 18%';
    return 'TOP 30%';
  }
  static String _pctFromSymmetry(double s) {
    if (s >= 90) return 'TOP 5%';
    if (s >= 85) return 'TOP 13%';
    if (s >= 80) return 'TOP 24%';
    return 'TOP 40%';
  }
  static String _pctFromLips(double l) => 'TOP 18%';
  static String _pctFromFwhr(double f) {
    if (f >= 1.87 && f <= 1.95) return 'TOP 8%';
    return 'TOP 22%';
  }
  static String _pctFromThirds(double dev) {
    if (dev <= 1.5) return 'TOP 6%';
    return 'TOP 18%';
  }
  static String _pctFromChin(double c) {
    if (c >= 0.35) return 'TOP 8%';
    if (c >= 0.28) return 'TOP 17%';
    return 'TOP 28%';
  }
}

enum TraitKind { strength, pulldown }

class Trait {
  final String name;      // "HUNTER EYES"
  final String emoji;     // "👁️"
  final String detail;    // "+3.1° TILT"
  final String pct;       // "TOP 12%"
  final TraitKind kind;
  final double score;     // 0..1 — for sorting + visual intensity

  const Trait({
    required this.name,
    required this.emoji,
    required this.detail,
    required this.pct,
    required this.kind,
    required this.score,
  });
}
