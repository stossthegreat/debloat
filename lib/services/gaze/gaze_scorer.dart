import 'dart:math' as math;

import '../../models/face_metrics.dart';
import '../../models/gaze/gaze_lesson.dart';

/// Scores one Gaze drill window into a [GazeResult].
///
/// Inputs:
///   - the lesson (defines weights, blink target, whether rhythm matters)
///   - the per-frame [FaceMetrics] samples collected during the drill
///   - the manually-tracked blink count for the drill window (we
///     edge-detect on eye aperture in the camera frame callback rather
///     than trusting [FaceMetrics.blinkRate], which is windowed across
///     60s and over-counts on short drills)
///
/// Output: a [GazeResult] with six dimensions, each in 0..1.
///
/// Design notes for the user spec — "deadly accurate" — that matter:
///
///   - eyeStability is the fraction of frames with eyeContactScore
///     above the lock threshold (0.5). NOT the average — averages get
///     dragged up by half-locked frames. A binary "locked or not" per
///     frame matches how the apprentice will read the result.
///
///   - blinkControl is a soft penalty around the lesson's target.
///     Stillness has target=4 over 15s — that's ~16/min, which is
///     within normal resting blink range. Each blink over target
///     costs 0.18.
///
///   - tension uses [FaceMetrics.headStability], which is already
///     0..1 (inverse of euler-angle variance over the detector's
///     rolling window). We average it across the drill samples; high
///     average = head genuinely held still.
///
///   - smileControl branches on the lesson's intent. Most lessons
///     want a neutral mouth — score is 1 - average smile strength.
///     The handful of lessons that want a SMALL deliberate smile
///     (smile_calibration, flirty_eye_contact, dangerous_eye_contact)
///     score the proximity to an ideal smile-strength around 0.30 —
///     too much = grinning, too little = stone face, only the band
///     around the ideal scores high.
///
///   - rhythm is meaningful only on rhythm lessons. We compute the
///     standard deviation of eyeContactScore across the drill window
///     and reward the band around an ideal stdDev of 0.15 — that
///     corresponds to one or two controlled look-away/return arcs in
///     a 12-second drill. Flat-lined high contact gets stdDev near 0
///     (low rhythm); chaotic random gets stdDev near 0.30+ (also low
///     rhythm). Only the controlled middle wins.
///
///   - magneticPresence is the weighted composite. Per-lesson weights
///     are pinned in [GazeLesson.weights] and emphasise different
///     dimensions per lesson — Stillness loads on eyeStability +
///     tension + smileControl; Smile Calibration loads on
///     smileControl; etc.
abstract final class GazeScorer {
  /// Eye-contact threshold for "locked on" per frame. Bumped from
  /// 0.7 to 0.82 — the user reported scoring a perfect 10/10 on
  /// their first attempt at THE LOCK, which is impossible if the
  /// metric is honest. At 0.7 the threshold was passing on any
  /// "looking-at-the-screen" frame including drift. 0.82 requires
  /// a true lock — eyes centred on the camera, not glancing past.
  static const double _lockThreshold = 0.82;

  /// Blink-over-target soft penalty per extra blink. Each blink
  /// beyond the lesson's target costs this much, capped at 0 floor.
  /// Bumped from 0.22 → 0.30 so a single over-blink shows up in
  /// the dial instead of barely registering.
  static const double _blinkPenalty = 0.30;

  /// Ideal smile strength for lessons that want a SMALL deliberate
  /// smile. Both higher and lower than this lose points; the curve
  /// is tight — at ±0.20 from ideal you lose half.
  static const double _idealSmallSmile = 0.30;

  /// Ideal stdDev of eyeContactScore for rhythm lessons.
  static const double _idealRhythmStdDev = 0.15;

  /// IDs of lessons where a SMALL deliberate smile is part of the
  /// move. Anywhere else, smileControl rewards a neutral mouth.
  static const _smallSmileLessons = {
    'soft_eyes',       // the smolder — warmth in the eyes
    'caught',          // get caught, let a half-smile start
    'listening_gaze',  // present, soft, while she talks
  };

  static GazeResult score({
    required GazeLesson lesson,
    required List<FaceMetrics> samples,
    required int blinks,
  }) {
    if (samples.isEmpty) {
      return _emptyResult(lesson);
    }

    // ── 1. EYE STABILITY ────────────────────────────────────────
    final lockedFrames =
        samples.where((m) => m.eyeContactScore > _lockThreshold).length;
    final eyeStability = lockedFrames / samples.length;

    // ── 2. BLINK CONTROL ───────────────────────────────────────
    final target = lesson.targetBlinks;
    final overshoot = (blinks - target).clamp(0, 1000);
    final blinkControl = (1.0 - overshoot * _blinkPenalty).clamp(0.0, 1.0);

    // ── 3. TENSION ─────────────────────────────────────────────
    // headStability is per-frame 0..1 (1 = perfectly still). Compute
    // the average over the drill window AND a deterministic motion
    // penalty from raw head-pose variance — the MLKit smoother
    // sometimes pins headStability near 1.0 even when the apprentice
    // is moving, so we cross-check with the actual variance.
    final tensionAvg = samples
            .map((m) => m.headStability)
            .reduce((a, b) => a + b) /
        samples.length;
    double meanYaw = 0, meanPitch = 0, meanRoll = 0;
    for (final m in samples) {
      meanYaw   += m.headYaw;
      meanPitch += m.headPitch;
      meanRoll  += m.headRoll;
    }
    meanYaw   /= samples.length;
    meanPitch /= samples.length;
    meanRoll  /= samples.length;
    double varYaw = 0, varPitch = 0, varRoll = 0;
    for (final m in samples) {
      varYaw   += (m.headYaw   - meanYaw)   * (m.headYaw   - meanYaw);
      varPitch += (m.headPitch - meanPitch) * (m.headPitch - meanPitch);
      varRoll  += (m.headRoll  - meanRoll)  * (m.headRoll  - meanRoll);
    }
    varYaw   /= samples.length;
    varPitch /= samples.length;
    varRoll  /= samples.length;
    // 1° of stdDev across the window = 0.10 penalty; collapses at 10°.
    final stillness = (1.0 -
            ((varYaw + varPitch + varRoll) / 3.0) / 100.0)
        .clamp(0.0, 1.0);
    final tension = ((tensionAvg + stillness) / 2.0).clamp(0.0, 1.0);

    // ── 4. SMILE CONTROL ───────────────────────────────────────
    // Tightened — at avg-smile 0.3 the old curve gave neutral-mouth
    // lessons a 70% score; that's too generous when the apprentice
    // is visibly grinning. Now: each 0.1 of smile costs 0.20.
    final avgSmile = samples
            .map((m) => m.smileAuthenticity)
            .reduce((a, b) => a + b) /
        samples.length;
    final double smileControl;
    if (_smallSmileLessons.contains(lesson.id)) {
      // Reward proximity to the ideal small smile band. ±0.20 from
      // ideal halves the score; ±0.40 collapses it.
      smileControl = (1.0 - (avgSmile - _idealSmallSmile).abs() * 2.5)
          .clamp(0.0, 1.0);
    } else {
      // Reward a neutral mouth — steeper penalty than before.
      smileControl = (1.0 - avgSmile * 2.0).clamp(0.0, 1.0);
    }

    // ── 5. RHYTHM ──────────────────────────────────────────────
    final double rhythm;
    if (lesson.isRhythmLesson) {
      final mean = samples
              .map((m) => m.eyeContactScore)
              .reduce((a, b) => a + b) /
          samples.length;
      final variance = samples
              .map((m) => (m.eyeContactScore - mean) *
                  (m.eyeContactScore - mean))
              .reduce((a, b) => a + b) /
          samples.length;
      final stdDev = math.sqrt(variance);
      rhythm = (1.0 -
              (stdDev - _idealRhythmStdDev).abs() * 3.0)
          .clamp(0.0, 1.0);
    } else {
      // Non-rhythm lessons don't measure rhythm — pin to 1.0 so the
      // weighted composite isn't dragged down by an irrelevant axis.
      rhythm = 1.0;
    }

    // ── 6. MAGNETIC PRESENCE (composite) ───────────────────────
    final w = lesson.weights;
    double composite = 0;
    composite += (w[GazeDimension.eyeStability] ?? 0) * eyeStability;
    composite += (w[GazeDimension.blinkControl] ?? 0) * blinkControl;
    composite += (w[GazeDimension.rhythm]       ?? 0) * rhythm;
    composite += (w[GazeDimension.tension]      ?? 0) * tension;
    composite += (w[GazeDimension.smileControl] ?? 0) * smileControl;

    // Renormalise if the weights don't sum to 1 (defensive).
    final weightSum = (w[GazeDimension.eyeStability] ?? 0) +
        (w[GazeDimension.blinkControl] ?? 0) +
        (w[GazeDimension.rhythm]       ?? 0) +
        (w[GazeDimension.tension]      ?? 0) +
        (w[GazeDimension.smileControl] ?? 0);
    if (weightSum > 0 && (weightSum - 1.0).abs() > 0.02) {
      composite = composite / weightSum;
    }
    final magneticPresence = composite.clamp(0.0, 1.0);

    return GazeResult(
      lessonId:     lesson.id,
      lessonNumber: lesson.number,
      lessonName:   lesson.name,
      dims: {
        GazeDimension.eyeStability:     eyeStability,
        GazeDimension.blinkControl:     blinkControl,
        GazeDimension.rhythm:           rhythm,
        GazeDimension.tension:          tension,
        GazeDimension.smileControl:     smileControl,
        GazeDimension.magneticPresence: magneticPresence,
      },
      blinks:       blinks,
      drillSeconds: lesson.drillSeconds,
      timestampMs:  DateTime.now().millisecondsSinceEpoch,
    );
  }

  static GazeResult _emptyResult(GazeLesson lesson) => GazeResult(
        lessonId:     lesson.id,
        lessonNumber: lesson.number,
        lessonName:   lesson.name,
        dims: { for (final d in GazeDimension.values) d: 0.0 },
        blinks:       0,
        drillSeconds: lesson.drillSeconds,
        timestampMs:  DateTime.now().millisecondsSinceEpoch,
      );
}
