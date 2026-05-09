import 'dart:math' as math;
import 'package:flutter/foundation.dart';

@immutable
class FaceGeometry {
  // Original 9 metrics
  final double canthalTilt;        // degrees, positive = hunter eyes
  final double symmetryScore;      // 0–100, 100 = perfect symmetry
  final double facialThirdTop;     // % of face height (hairline→brow)
  final double facialThirdMid;     // % of face height (brow→nose base)
  final double facialThirdLow;     // % of face height (nose base→chin)
  final double fwhr;               // facial width-to-height ratio
  final double eyeSpacingRatio;    // interocular / face width
  final double jawAngle;           // degrees
  final double chinProjection;     // chin tip relative to nose

  // Extended metrics — unlock "your head is narrow / lips are full" style
  // of face-specific advice that GPT-4o can't surface from the originals.
  final double faceLengthRatio;    // height / width. >1.35 = long/narrow.
  final double noseLengthRatio;    // nose vertical / mid-third height
  final double lipFullness;        // lip area ratio (approximate)
  final double brow2EyeGap;        // brow-to-eye vertical / face height
  final double philtrumRatio;      // philtrum / lower-third height
  final double interpupillaryRatio;// pupil-to-pupil / face width
  final String headShape;          // 'oval' | 'round' | 'square' | 'long' | 'broad'

  /// Bigonial-to-bizygomatic width ratio — jaw width at the gonial Y
  /// band divided by cheekbone width at the zygomatic Y band. THIS is
  /// what scoring uses to grade jaw definition; [jawAngle] above is
  /// kept only for descriptive text templates. Real masculine "strong
  /// wide jaw" sits at 0.85+; soft V-shape sits below 0.75. Range
  /// is roughly 0.65..0.95 in real faces.
  final double jawWidthRatio;

  final bool hasReliableData;

  const FaceGeometry({
    required this.canthalTilt,
    required this.symmetryScore,
    required this.facialThirdTop,
    required this.facialThirdMid,
    required this.facialThirdLow,
    required this.fwhr,
    required this.eyeSpacingRatio,
    required this.jawAngle,
    required this.chinProjection,
    required this.hasReliableData,
    this.faceLengthRatio      = 1.3,
    this.noseLengthRatio      = 0.3,
    this.lipFullness          = 0.5,
    this.brow2EyeGap          = 0.04,
    this.philtrumRatio        = 0.35,
    this.interpupillaryRatio  = 0.46,
    this.headShape            = 'oval',
    this.jawWidthRatio        = 0.80,
  });

  // Canthal tilt rating
  String get canthalTiltLabel {
    if (canthalTilt > 3.0) return 'Positive — hunter';
    if (canthalTilt > 0.5) return 'Neutral-positive';
    if (canthalTilt > -1.0) return 'Neutral';
    return 'Negative — drooping';
  }

  // Symmetry tier
  String get symmetryLabel {
    if (symmetryScore >= 88) return 'Exceptional';
    if (symmetryScore >= 78) return 'High';
    if (symmetryScore >= 65) return 'Average';
    return 'Below average';
  }

  // Facial thirds deviation from ideal (33/33/33)
  double get thirdsDeviation {
    final ideal = 33.33;
    return (math.pow(facialThirdTop - ideal, 2) +
            math.pow(facialThirdMid - ideal, 2) +
            math.pow(facialThirdLow - ideal, 2)) /
        3;
  }

  // FWHR interpretation
  String get fwhrLabel {
    if (fwhr >= 2.1) return 'High — dominant';
    if (fwhr >= 1.8) return 'Ideal range';
    return 'Low';
  }

  Map<String, String> get summaryMap => {
    'Canthal tilt': '${canthalTilt.toStringAsFixed(1)}° — $canthalTiltLabel',
    'Symmetry': '${symmetryScore.toStringAsFixed(0)}% — $symmetryLabel',
    'Facial thirds': '${facialThirdTop.toStringAsFixed(0)} / ${facialThirdMid.toStringAsFixed(0)} / ${facialThirdLow.toStringAsFixed(0)}',
    'FWHR': '${fwhr.toStringAsFixed(2)} — $fwhrLabel',
    'Eye spacing': '${(eyeSpacingRatio * 100).toStringAsFixed(0)}% of face width',
    'Jaw angle': '${jawAngle.toStringAsFixed(0)}°',
  };
}
