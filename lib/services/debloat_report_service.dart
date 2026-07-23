import '../models/face_geometry.dart';
import 'debloat_stats_service.dart';

/// One "what's causing it" bar.
class BloatCause {
  final String emoji;
  final String label;
  final int pct; // 0..100
  const BloatCause({required this.emoji, required this.label, required this.pct});
}

/// The full new debloat score-card payload. Everything the results card
/// needs beyond the hero render + gauges: the AI verdict lines, the
/// projected-improvement points, and the "what's causing it" bars.
class DebloatReport {
  final String verdictHolding;   // "Your face is holding water around ..."
  final String verdictEffect;    // "This is softening your jawline ..."
  final int projectedPoints;     // "+31 Points"
  final List<BloatCause> causes; // Water Retention / Sleep / Sodium / ...

  const DebloatReport({
    required this.verdictHolding,
    required this.verdictEffect,
    required this.projectedPoints,
    required this.causes,
  });
}

/// Computes the debloat score-card entirely on-device from the scan
/// geometry (via DebloatStatsService), so the results screen always has a
/// personalised, sensible read even before the GPT verdict lands. The
/// backend can override the verdict text + cause percentages when present.
class DebloatReportService {
  static DebloatReport compute(FaceGeometry g) {
    final r = DebloatStatsService.compute(g);
    final overall = r.overall; // higher = more drained (less bloat)
    final bloat = (100 - overall).clamp(0, 100); // how bloated

    // Worst-scoring zone → drives the verdict copy.
    final worst = [...r.stats]..sort((a, b) => a.score.compareTo(b.score));
    final zone = worst.isNotEmpty ? worst.first.label.toLowerCase() : 'midface';
    final holding = _holdingLine(zone);
    const effect = 'This is softening your jawline and reducing your '
        'overall facial definition.';

    // Projected improvement after the full protocol — more bloat now means
    // more visible upside. Lands in a believable 14–44 range.
    final projected = (bloat * 0.42).round().clamp(14, 44);

    // Deterministic per-face spread so the bars look real and differ
    // between users without random noise. Seeded off stable geometry.
    int seedFrom(double v, int mod) => (v.abs() * 1000).round() % mod;
    final s1 = seedFrom(g.fwhr, 13);
    final s2 = seedFrom(g.symmetryScore, 17);
    final s3 = seedFrom(g.jawWidthRatio, 11);

    final waterRetention = (bloat + 22 + s1).clamp(35, 94);
    final sleep          = (58 + s2).clamp(40, 90);
    final sodium         = (bloat + 12 + s3).clamp(40, 88);
    final hydration      = (52 + s1 + s3).clamp(35, 85);
    final cortisol       = (30 + s2 + s3).clamp(25, 75);

    final causes = <BloatCause>[
      BloatCause(emoji: '💧', label: 'Water Retention', pct: waterRetention),
      BloatCause(emoji: '😴', label: 'Sleep',           pct: sleep),
      BloatCause(emoji: '🥡', label: 'Sodium',          pct: sodium),
      BloatCause(emoji: '🥤', label: 'Hydration',       pct: hydration),
      BloatCause(emoji: '😰', label: 'Cortisol',        pct: cortisol),
    ];

    return DebloatReport(
      verdictHolding: holding,
      verdictEffect: effect,
      projectedPoints: projected,
      causes: causes,
    );
  }

  static String _holdingLine(String zone) {
    if (zone.contains('eye')) {
      return 'Your face is holding water around the under-eye and '
          'midface area.';
    }
    if (zone.contains('jaw') || zone.contains('submental')) {
      return 'Your face is holding water around the jawline and under '
          'the chin.';
    }
    if (zone.contains('cheek')) {
      return 'Your face is holding water across the cheeks and midface.';
    }
    return 'Your face is holding water around the midface and under-eye '
        'area.';
  }
}
