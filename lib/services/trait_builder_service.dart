import '../models/face_geometry.dart';

/// Converts raw geometry into Umax-style trait badges — short 2-word names
/// for the grid, emotional shareable one-liners for the hero proof lines.
///
/// Green badges = strengths (vanity flex).  Red badges = honest pulldowns.
///
/// TRAIT SELECTION POLICY
/// ──────────────────────
/// Every trait surfaced here is backed by a geometry rule MediaPipe can
/// measure reliably on a front-pose scan. We deliberately exclude:
///
///   · JAW ANGLE traits — MediaPipe's jaw landmarks drift on users with
///     beards / rounder light (the model reads beard front as jaw line).
///     Can't stake a "chiseled jaw" flex on a signal that's noisy.
///   · CHIN PROJECTION traits — same root cause: a thick beard inflates
///     the read so users with full beards got false STRONG CHIN flags.
///   · SKIN traits — MediaPipe gives no skin-quality signal at all.
///     Skin is a GPT-Vision feature, not a geometry one.
///
/// Every surviving trait is a real geometric measurement, not a gimmick.
class TraitBuilderService {
  /// Returns up to 6 traits, strongest first. Caller typically shows top 4
  /// on the grid and top 3 on the hero proof lines.
  static List<Trait> build(FaceGeometry g) {
    final all = <Trait>[];

    // ── STRENGTHS (green) — measured, reliable, emotional ───────────────

    // Canthal tilt — positive = "hunter eyes". MediaPipe reads this well
    // (lateral canthus landmark is very stable).
    if (g.canthalTilt >= 2.0) {
      final (pct, beats) = _tierFromCanthal(g.canthalTilt);
      all.add(Trait(
        name: 'HUNTER EYES',
        emoji: '👁️',
        detail: '+${g.canthalTilt.toStringAsFixed(1)}° TILT',
        pct: pct,
        heroLine: 'Your hunter eyes beat $beats of men',
        kind: TraitKind.strength,
        score: ((g.canthalTilt - 2.0) / 3.0 * 0.5 + 0.5).clamp(0.0, 1.0),
      ));
    }

    // Facial symmetry — derived from mirrored landmark distances. Stable
    // enough to surface, but we raise the bar to >=85 so only genuinely
    // symmetric faces earn the flex.
    if (g.symmetryScore >= 85) {
      final (pct, beats) = _tierFromSymmetry(g.symmetryScore);
      all.add(Trait(
        name: 'RARE SYMMETRY',
        emoji: '◇',
        detail: '${g.symmetryScore.toStringAsFixed(0)} / 100',
        pct: pct,
        heroLine: 'Symmetry rarer than $beats of men',
        kind: TraitKind.strength,
        score: ((g.symmetryScore - 85) / 10.0 * 0.45 + 0.55).clamp(0.0, 1.0),
      ));
    }

    // Lip fullness — sweet-spot signal. Area ratio from upper-lip +
    // lower-lip landmarks; stable across lighting.
    if (g.lipFullness >= 0.45 && g.lipFullness <= 0.70) {
      all.add(Trait(
        name: 'MODEL LIPS',
        emoji: '◖',
        detail: 'BALANCED FULLNESS',
        pct: 'TOP 18%',
        heroLine: 'Proportioned lips — golden ratio',
        kind: TraitKind.strength,
        // Closer to ideal 0.56 = higher score, capped at 0.85 so measured
        // elite metrics (tilt, symmetry) can still beat a sweet-spot trait.
        score: (0.85 - (g.lipFullness - 0.56).abs() * 2).clamp(0.55, 0.85),
      ));
    }

    // Face width-to-height ratio — "dominance" signal. Measured across
    // zygomatic width and bizygomatic-to-lower-lip height. Reliable.
    if (g.fwhr >= 1.80 && g.fwhr <= 2.00) {
      final pct = g.fwhr >= 1.87 && g.fwhr <= 1.95 ? 'TOP 8%' : 'TOP 22%';
      all.add(Trait(
        name: 'DOMINANT FRAME',
        emoji: '▣',
        detail: g.fwhr.toStringAsFixed(2),
        pct: pct,
        heroLine: 'Dominant face frame — $pct',
        kind: TraitKind.strength,
        score: (0.85 - (g.fwhr - 1.91).abs() * 0.8).clamp(0.55, 0.85),
      ));
    }

    // Facial thirds — golden-ratio proportion. Each third lands near
    // 33.33% of total face height. Very stable signal (landmarks at
    // hairline, brow, nose base, chin are all well-anchored).
    final thirdsDev = ((g.facialThirdTop - 33.33).abs()
                    + (g.facialThirdMid - 33.33).abs()
                    + (g.facialThirdLow - 33.33).abs()) / 3;
    if (thirdsDev <= 2.0) {
      final pct = thirdsDev <= 1.5 ? 'TOP 6%' : 'TOP 18%';
      all.add(Trait(
        name: 'GOLDEN THIRDS',
        emoji: '═',
        detail: '${g.facialThirdTop.toStringAsFixed(0)}/${g.facialThirdMid.toStringAsFixed(0)}/${g.facialThirdLow.toStringAsFixed(0)}',
        pct: pct,
        heroLine: 'Golden-ratio thirds — $pct',
        kind: TraitKind.strength,
        score: ((2.0 - thirdsDev) / 2.0 * 0.45 + 0.55).clamp(0.55, 1.0),
      ));
    }

    // Brow-to-eye gap — tight spacing reads as masculine/dominant.
    // Landmarks here are stable.
    if (g.brow2EyeGap < 0.03) {
      all.add(Trait(
        name: 'DOMINANT BROW',
        emoji: '⌃',
        detail: 'TIGHT LID SPACING',
        pct: 'TOP 15%',
        heroLine: 'Dominant brow — top 15%',
        kind: TraitKind.strength,
        score: 0.65,
      ));
    }

    // Eye spacing — ideal inter-canthal at roughly 0.46 of face width.
    // Reliable, adds a strength path when others miss.
    if (g.eyeSpacingRatio >= 0.44 && g.eyeSpacingRatio <= 0.48) {
      all.add(Trait(
        name: 'IDEAL EYE SPACING',
        emoji: '◉',
        detail: g.eyeSpacingRatio.toStringAsFixed(2),
        pct: 'TOP 20%',
        heroLine: 'Ideal eye spacing — top 20%',
        kind: TraitKind.strength,
        score: 0.62,
      ));
    }

    // ── PULLDOWNS (red) — also rephrased for emotional punch ────────────

    if (g.faceLengthRatio > 1.38) {
      all.add(Trait(
        name: 'LONG FACE',
        emoji: '↕',
        detail: g.faceLengthRatio.toStringAsFixed(2),
        pct: 'COMPRESS WITH CUT',
        heroLine: 'Long face proportions — compress vertically',
        kind: TraitKind.pulldown,
        score: 0.3,
      ));
    }
    if (g.symmetryScore < 72) {
      all.add(Trait(
        name: 'SLIGHT ASYMMETRY',
        emoji: '◈',
        detail: '${g.symmetryScore.toStringAsFixed(0)} / 100',
        pct: 'POSTURE FIX',
        heroLine: 'Slight asymmetry — posture fixes most of it',
        kind: TraitKind.pulldown,
        score: 0.4,
      ));
    }
    if (thirdsDev > 4) {
      if (g.facialThirdTop > 36) {
        all.add(Trait(
          name: 'HIGH FOREHEAD',
          emoji: '▔',
          detail: '${g.facialThirdTop.toStringAsFixed(0)}% UPPER',
          pct: 'LOWER FRINGE',
          heroLine: 'High forehead — a lower fringe rebalances',
          kind: TraitKind.pulldown,
          score: 0.35,
        ));
      } else if (g.facialThirdLow > 36) {
        all.add(Trait(
          name: 'LONG LOWER',
          emoji: '▂',
          detail: '${g.facialThirdLow.toStringAsFixed(0)}% LOWER',
          pct: 'SQUARED BEARD',
          heroLine: 'Long lower third — squared beard frame balances',
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

  // ── Emotional tier helpers ──────────────────────────────────────────────
  //
  // Each returns (percentile-label, "beats Y%-of-men" string) so the hero
  // proof line can render "Your hunter eyes beat 97% of men" directly. Tiers
  // are intentionally coarse — readers want a round number, not decimals.

  static (String, String) _tierFromCanthal(double t) {
    if (t >= 5.0) return ('TOP 3%',  '97%');
    if (t >= 4.0) return ('TOP 7%',  '93%');
    if (t >= 3.0) return ('TOP 12%', '88%');
    if (t >= 2.5) return ('TOP 18%', '82%');
    return          ('TOP 25%', '75%');
  }

  static (String, String) _tierFromSymmetry(double s) {
    if (s >= 92) return ('TOP 3%',  '97%');
    if (s >= 88) return ('TOP 8%',  '92%');
    if (s >= 85) return ('TOP 15%', '85%');
    return         ('TOP 25%', '75%');
  }
}

enum TraitKind { strength, pulldown }

class Trait {
  final String name;       // "HUNTER EYES" — short grid label
  final String emoji;      // "👁️"
  final String detail;     // "+3.1° TILT" — measurement under the name
  final String pct;        // "TOP 12%" — percentile badge
  /// Ready-to-render emotional one-liner for the hero proof lines.
  /// "Your hunter eyes beat 88% of men." — punchier + more shareable than
  /// "TOP 12% HUNTER EYES" and meant to be screenshot-worthy on its own.
  final String heroLine;
  final TraitKind kind;
  final double score;      // 0..1 — for sorting + visual intensity

  const Trait({
    required this.name,
    required this.emoji,
    required this.detail,
    required this.pct,
    required this.heroLine,
    required this.kind,
    required this.score,
  });
}
