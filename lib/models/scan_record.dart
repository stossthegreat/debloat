import 'face_geometry.dart';

/// Immutable record of a single scan. Persisted locally so the user's
/// history survives reinstalls-until-clear, feeds the progress charts, and
/// primes the AI advisor with their most recent measurements.
class ScanRecord {
  final String id;                 // local UUID-ish timestamp id
  final DateTime takenAt;
  final FaceGeometry geometry;
  final int score;                 // 0..100 — computed from geometry at save time
  final String tierLabel;          // "Apex", "Elite", ...
  final String archetypeName;      // "Nordic Apex", etc.
  final int archetypeMatchPct;     // 0..100
  final String? capturedImagePath; // local path — null if not persisted to disk
  final String? maximizedImageUrl; // backend-returned Flux twin

  /// AI-projected lift to the user's LOOKS score from completing all of
  /// the fixes the backend surfaced on this scan's report. Sum of the
  /// per-fix `points` (1-8 each, sum lands 12-22 by prompt design).
  /// 0 when the report didn't return points (older scans).
  final int projectedDelta;

  /// Headline copy for each recommended fix — used by the Ascend
  /// POTENTIAL card so the user sees WHAT the AI actually said, not
  /// just an aggregate. Each entry is the user-facing fix title from
  /// the report (e.g. "Lean to 13% body fat", "Push hair off forehead",
  /// "Tretinoin 0.025% nightly"). Empty list for legacy / pre-prompt
  /// reports.
  final List<ScanFixSummary> fixHeadlines;

  const ScanRecord({
    required this.id,
    required this.takenAt,
    required this.geometry,
    required this.score,
    required this.tierLabel,
    required this.archetypeName,
    required this.archetypeMatchPct,
    this.capturedImagePath,
    this.maximizedImageUrl,
    this.projectedDelta = 0,
    this.fixHeadlines = const [],
  });

  Map<String, dynamic> toJson() => {
    'id':                 id,
    'takenAt':            takenAt.toIso8601String(),
    'canthalTilt':        geometry.canthalTilt,
    'symmetryScore':      geometry.symmetryScore,
    'facialThirdTop':     geometry.facialThirdTop,
    'facialThirdMid':     geometry.facialThirdMid,
    'facialThirdLow':     geometry.facialThirdLow,
    'fwhr':               geometry.fwhr,
    'eyeSpacingRatio':    geometry.eyeSpacingRatio,
    'jawAngle':           geometry.jawAngle,
    'chinProjection':     geometry.chinProjection,
    'hasReliableData':    geometry.hasReliableData,
    'score':              score,
    'tierLabel':          tierLabel,
    'archetypeName':      archetypeName,
    'archetypeMatchPct':  archetypeMatchPct,
    'capturedImagePath':  capturedImagePath,
    'maximizedImageUrl':  maximizedImageUrl,
    'projectedDelta':     projectedDelta,
    'fixHeadlines':       fixHeadlines.map((f) => f.toJson()).toList(),
  };

  factory ScanRecord.fromJson(Map<String, dynamic> j) => ScanRecord(
    id:       j['id'] as String,
    takenAt:  DateTime.parse(j['takenAt'] as String),
    geometry: FaceGeometry(
      canthalTilt:      (j['canthalTilt']     as num).toDouble(),
      symmetryScore:    (j['symmetryScore']   as num).toDouble(),
      facialThirdTop:   (j['facialThirdTop']  as num).toDouble(),
      facialThirdMid:   (j['facialThirdMid']  as num).toDouble(),
      facialThirdLow:   (j['facialThirdLow']  as num).toDouble(),
      fwhr:             (j['fwhr']            as num).toDouble(),
      eyeSpacingRatio:  (j['eyeSpacingRatio'] as num).toDouble(),
      jawAngle:         (j['jawAngle']        as num).toDouble(),
      chinProjection:   (j['chinProjection']  as num).toDouble(),
      hasReliableData:  j['hasReliableData'] as bool? ?? true,
    ),
    score:              (j['score'] as num).toInt(),
    tierLabel:          j['tierLabel']          as String? ?? 'Foundation',
    archetypeName:      j['archetypeName']      as String? ?? 'Classical Greek',
    archetypeMatchPct:  (j['archetypeMatchPct'] as num?)?.toInt() ?? 0,
    capturedImagePath:  j['capturedImagePath'] as String?,
    maximizedImageUrl:  j['maximizedImageUrl'] as String?,
    projectedDelta:     (j['projectedDelta']     as num?)?.toInt() ?? 0,
    fixHeadlines: ((j['fixHeadlines'] as List?) ?? [])
        .map((e) => ScanFixSummary.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// Slim summary of a single AI-recommended fix, persisted alongside the
/// scan so the Ascend POTENTIAL card can render the headline + points
/// without having to round-trip the report endpoint.
class ScanFixSummary {
  final String title;
  /// Projected delta to the LOOKS score from completing this fix
  /// (0..8, per the analyse.js prompt).
  final int points;
  /// Time window the fix is realistic in — "30 days", "2 weeks", …
  final String timeline;

  const ScanFixSummary({
    required this.title,
    required this.points,
    required this.timeline,
  });

  Map<String, dynamic> toJson() => {
    'title':    title,
    'points':   points,
    'timeline': timeline,
  };

  factory ScanFixSummary.fromJson(Map<String, dynamic> j) => ScanFixSummary(
    title:    (j['title']    as String?) ?? '',
    points:   ((j['points']   as num?)?.toInt()) ?? 0,
    timeline: (j['timeline'] as String?) ?? '',
  );
}

/// A single AI-generated image (Flux Kontext result) attached to a user
/// prompt / context so the Gallery tab can re-scroll them.
class GenerationRecord {
  final String id;
  final DateTime createdAt;
  final String prompt;        // "fade haircut with texture on top"
  final String imageUrl;
  final String? relatedScanId;

  const GenerationRecord({
    required this.id,
    required this.createdAt,
    required this.prompt,
    required this.imageUrl,
    this.relatedScanId,
  });

  Map<String, dynamic> toJson() => {
    'id':             id,
    'createdAt':      createdAt.toIso8601String(),
    'prompt':         prompt,
    'imageUrl':       imageUrl,
    'relatedScanId':  relatedScanId,
  };

  factory GenerationRecord.fromJson(Map<String, dynamic> j) => GenerationRecord(
    id:            j['id'] as String,
    createdAt:     DateTime.parse(j['createdAt'] as String),
    prompt:        j['prompt'] as String? ?? '',
    imageUrl:      j['imageUrl'] as String,
    relatedScanId: j['relatedScanId'] as String?,
  );
}

/// One row in the Lucien game-score timeline. Written at the end of
/// every Free Flow session; read by the Progress page chart.
class GameScoreEntry {
  final int      score;   // 0..100 session score (legacy field)
  final DateTime takenAt;
  const GameScoreEntry({required this.score, required this.takenAt});
}
