import 'package:flutter/foundation.dart';

@immutable
class Fix {
  final String title;
  final String reason;
  final String action;
  /// The VISUAL phrase used to feed Flux Kontext when the user taps "See
  /// it" on this fix. Separate from [action] because [action] is protocol
  /// ("Tretinoin 0.025% nightly, moisturize with CeraVe") and a text-to-
  /// image model renders protocol literally (cream on the face). This
  /// field describes the END STATE of the face only.
  final String visualRequest;
  final String timeline;
  final int rescanDay;

  const Fix({
    required this.title,
    required this.reason,
    required this.action,
    required this.visualRequest,
    required this.timeline,
    required this.rescanDay,
  });

  factory Fix.fromJson(Map<String, dynamic> j) => Fix(
    title:         j['title']         as String? ?? '',
    reason:        j['reason']        as String? ?? '',
    action:        j['action']        as String? ?? '',
    visualRequest: j['visualRequest'] as String? ?? '',
    timeline:      j['timeline']      as String? ?? '',
    rescanDay:    (j['rescanDay']     as num?)?.toInt() ?? 14,
  );
}

@immutable
class Report {
  /// One-sentence hero line. Screenshot-worthy. Cites a specific measurement,
  /// names strongest + pulldown in one breath. Rendered at the top of the
  /// report in hero typography.
  final String oneLineVerdict;
  final String strongest;
  final String pulldown;
  final String boneReading;   // human translation of measured geometry
  final List<Fix> fixes;
  final String verdict;

  const Report({
    required this.oneLineVerdict,
    required this.strongest,
    required this.pulldown,
    required this.boneReading,
    required this.fixes,
    required this.verdict,
  });

  factory Report.fromJson(Map<String, dynamic> j) => Report(
    oneLineVerdict: j['oneLineVerdict'] as String? ?? '',
    strongest:      j['strongest']      as String? ?? '',
    pulldown:       j['pulldown']       as String? ?? '',
    boneReading:    j['boneReading']    as String? ?? '',
    fixes: ((j['fixes'] as List?) ?? [])
        .map((e) => Fix.fromJson(e as Map<String, dynamic>))
        .toList(),
    verdict: j['verdict'] as String? ?? '',
  );
}

@immutable
class MirrorAnalysis {
  final Report report;
  final String maximizedImageUrl;
  /// Optional pre-rendered per-fix images.
  ///
  /// The backend does NOT currently populate this — the maximize endpoint
  /// now runs a single combined Flux call and returns only the hero URL,
  /// so fix cards fall back to live `/tryon` rendering when the user
  /// taps "See it." The field is kept for forward compatibility in case
  /// the backend later exposes per-fix precomputed images (e.g. via
  /// background generation or caching).
  final List<String> intermediateUrls;

  const MirrorAnalysis({
    required this.report,
    required this.maximizedImageUrl,
    this.intermediateUrls = const [],
  });

  factory MirrorAnalysis.fromJson(Map<String, dynamic> j) {
    final maxed = j['maximized'] as Map<String, dynamic>? ?? {};
    final raw   = maxed['intermediateUrls'] as List?;
    return MirrorAnalysis(
      report: Report.fromJson(j['report'] as Map<String, dynamic>),
      maximizedImageUrl: maxed['url'] as String? ?? '',
      intermediateUrls: (raw ?? const [])
          .map((e) => e.toString())
          .where((s) => s.isNotEmpty)
          .toList(),
    );
  }
}
