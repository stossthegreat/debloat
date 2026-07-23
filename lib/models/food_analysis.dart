import 'package:flutter/foundation.dart';

/// One graded food metric (Bloating Potential, Inflammation, Digestion,
/// Skin Health, Fluid Balance, Sodium Risk). The [rating] — not the raw
/// score — drives the colour, because a LOW "Bloating Potential" is good
/// while a HIGH "Digestion" is good. The backend decides the rating so the
/// UI never has to know which direction is good per metric.
@immutable
class FoodStat {
  final String label;
  final int score;      // 0..100, natural value of the metric
  final String rating;  // 'bad' | 'moderate' | 'good' | 'great'

  const FoodStat({required this.label, required this.score, required this.rating});

  factory FoodStat.fromJson(Map<String, dynamic> j) => FoodStat(
        label: j['label'] as String? ?? '',
        score: (j['score'] as num?)?.toInt() ?? 0,
        rating: (j['rating'] as String? ?? 'moderate').toLowerCase(),
      );

  Map<String, dynamic> toJson() => {'label': label, 'score': score, 'rating': rating};
}

/// A lower-bloat substitution the user could make.
@immutable
class BetterSwap {
  final String from;
  final String to;
  const BetterSwap({required this.from, required this.to});

  factory BetterSwap.fromJson(Map<String, dynamic> j) => BetterSwap(
        from: j['from'] as String? ?? '',
        to: j['to'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'from': from, 'to': to};
}

/// The full food-scan result rendered on the Food tab result card.
@immutable
class FoodAnalysis {
  final String name;
  final String verdict;       // "Great choice" / "High bloat risk" ...
  final int overallScore;     // 0..100, higher = less bloating
  final int sodiumMg;
  final int sodiumPctDaily;   // % of 2300mg
  final String puffinessRisk; // "Low" | "Moderate" | "High"
  final List<FoodStat> stats;
  final BetterSwap? betterSwap;
  final String tip;
  /// Epoch millis the scan was taken — for history ordering. Not from the
  /// backend; stamped on-device when the result lands.
  final int takenAtMs;

  const FoodAnalysis({
    required this.name,
    required this.verdict,
    required this.overallScore,
    required this.sodiumMg,
    required this.sodiumPctDaily,
    required this.puffinessRisk,
    required this.stats,
    required this.betterSwap,
    required this.tip,
    this.takenAtMs = 0,
  });

  bool get isEmpty => overallScore == 0 && name.toLowerCase().contains('no food');

  factory FoodAnalysis.fromJson(Map<String, dynamic> j) => FoodAnalysis(
        name: j['name'] as String? ?? 'Your meal',
        verdict: j['verdict'] as String? ?? 'Moderate',
        overallScore: (j['overallScore'] as num?)?.toInt() ?? 0,
        sodiumMg: (j['sodiumMg'] as num?)?.toInt() ?? 0,
        sodiumPctDaily: (j['sodiumPctDaily'] as num?)?.toInt() ?? 0,
        puffinessRisk: j['puffinessRisk'] as String? ?? 'Moderate',
        stats: ((j['stats'] as List?) ?? const [])
            .map((e) => FoodStat.fromJson(e as Map<String, dynamic>))
            .toList(),
        betterSwap: j['betterSwap'] is Map<String, dynamic>
            ? BetterSwap.fromJson(j['betterSwap'] as Map<String, dynamic>)
            : null,
        tip: j['tip'] as String? ?? '',
        takenAtMs: (j['takenAtMs'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'verdict': verdict,
        'overallScore': overallScore,
        'sodiumMg': sodiumMg,
        'sodiumPctDaily': sodiumPctDaily,
        'puffinessRisk': puffinessRisk,
        'stats': stats.map((s) => s.toJson()).toList(),
        if (betterSwap != null) 'betterSwap': betterSwap!.toJson(),
        'tip': tip,
        'takenAtMs': takenAtMs,
      };

  FoodAnalysis copyWith({int? takenAtMs}) => FoodAnalysis(
        name: name,
        verdict: verdict,
        overallScore: overallScore,
        sodiumMg: sodiumMg,
        sodiumPctDaily: sodiumPctDaily,
        puffinessRisk: puffinessRisk,
        stats: stats,
        betterSwap: betterSwap,
        tip: tip,
        takenAtMs: takenAtMs ?? this.takenAtMs,
      );
}
