import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/face_geometry.dart';
import '../models/mirror_analysis.dart';
import 'local_store_service.dart';

class MirrorApiService {
  static Map<String, dynamic> _geometryToJson(FaceGeometry g) => {
    // Original 9 — stable contract with existing backend
    'canthalTilt':          g.canthalTilt,
    'symmetryScore':        g.symmetryScore,
    'facialThirdTop':       g.facialThirdTop,
    'facialThirdMid':       g.facialThirdMid,
    'facialThirdLow':       g.facialThirdLow,
    'fwhr':                 g.fwhr,
    'eyeSpacingRatio':      g.eyeSpacingRatio,
    'jawAngle':             g.jawAngle,
    'chinProjection':       g.chinProjection,
    // Extended 8 — unlocks "head shape", "lip fullness", etc. in advice
    'faceLengthRatio':      g.faceLengthRatio,
    'noseLengthRatio':      g.noseLengthRatio,
    'lipFullness':          g.lipFullness,
    'brow2EyeGap':          g.brow2EyeGap,
    'philtrumRatio':        g.philtrumRatio,
    'interpupillaryRatio':  g.interpupillaryRatio,
    'headShape':            g.headShape,
    // Real frontal-photo jaw-strength proxy (bigonial / bizygomatic).
    // ≥0.85 = wide square strong jaw; ≤0.75 = soft / V-shape. Replaces
    // the old chin-apex `jawAngle` as the score driver — `jawAngle`
    // above is kept for backward-compatible prose templates.
    'jawWidthRatio':        g.jawWidthRatio,
  };

  /// Serializable form, callable from chat_service.dart.
  static Map<String, dynamic> geometryToJson(FaceGeometry g) => _geometryToJson(g);

  /// Run ONLY the GPT analysis stage. Skips the slow Replicate maximize
  /// call so the report screen can render the moment GPT lands (typical
  /// /analyse latency is 6–12s, vs 60–90s for the full /scan that
  /// chains Replicate behind it). The hero card fires /maximize itself
  /// when the user taps the on-image GENERATE button.
  ///
  /// Same retry contract as [scan] — never gives up. The returned
  /// [MirrorAnalysis] has an empty `maximizedImageUrl`; the caller is
  /// expected to backfill it via [maximizeOnly] on user demand.
  static Future<MirrorAnalysis> analyseOnly({
    required Uint8List imageBytes,
    required FaceGeometry geometry,
    List<Uint8List> extraImages = const [],
  }) async {
    // Glow-up style flag — drives whether the backend's GPT prompt
    // tunes the analysis prose and the rendered preview for men's
    // grooming or women's beauty. Sent as 'm' / 'f' / null; when
    // null the backend falls back to its legacy default behaviour
    // so users who never picked aren't broken.
    final gender = await LocalStoreService.userGender();
    final payload = <String, dynamic>{
      'imageBase64': base64Encode(imageBytes),
      'geometry':    _geometryToJson(geometry),
      if (gender != null) 'gender': gender,
    };
    if (extraImages.isNotEmpty) {
      payload['extraImagesBase64'] =
          extraImages.map((b) => base64Encode(b)).toList();
    }
    final body = jsonEncode(payload);

    return _retryForever<MirrorAnalysis>(
      label: 'analyse',
      run: () async {
        final response = await http.post(
          Uri.parse('${ApiConfig.backendBaseUrl}/analyse'),
          headers: {'Content-Type': 'application/json'},
          body: body,
        ).timeout(const Duration(seconds: 60));

        if (response.statusCode != 200) {
          throw Exception('Backend ${response.statusCode}: ${response.body}');
        }
        // /analyse returns the bare report object — wrap it into the
        // MirrorAnalysis envelope with an empty maximized payload so
        // the rest of the app keeps the same contract.
        final report = jsonDecode(response.body) as Map<String, dynamic>;
        return MirrorAnalysis.fromJson({
          'report':    report,
          'maximized': {'url': ''},
        });
      },
    );
  }

  /// Run full scan: analyse + maximize in one round-trip.
  /// `extraImages` are additional angles (left 3/4, right 3/4). The backend
  /// can use these for richer vision analysis via GPT-4o; Nano Banana still
  /// uses only the front image (imageBytes) for identity-locked rendering.
  ///
  /// RETRY CONTRACT — this method never gives up.
  /// Any transport error, any 5xx, any 4xx, any timeout: we retry forever
  /// with exponential backoff (3s → 60s cap). The user never sees a
  /// failure screen; the report page stays in its loading state and
  /// cycles copy until we succeed. See [_retryForever] below.
  ///
  /// If the caller wants to give up (e.g. user navigated away), they can
  /// cancel by unmounting — the next `setState` will be ignored.
  static Future<MirrorAnalysis> scan({
    required Uint8List imageBytes,
    required FaceGeometry geometry,
    List<Uint8List> extraImages = const [],
  }) async {
    final gender = await LocalStoreService.userGender();
    final payload = <String, dynamic>{
      'imageBase64': base64Encode(imageBytes),
      'geometry':    _geometryToJson(geometry),
      if (gender != null) 'gender': gender,
    };
    if (extraImages.isNotEmpty) {
      payload['extraImagesBase64'] =
          extraImages.map((b) => base64Encode(b)).toList();
    }
    final body = jsonEncode(payload);

    return _retryForever<MirrorAnalysis>(
      label: 'scan',
      run: () async {
        final response = await http.post(
          Uri.parse('${ApiConfig.backendBaseUrl}/scan'),
          headers: {'Content-Type': 'application/json'},
          body: body,
        ).timeout(const Duration(seconds: 120));

        if (response.statusCode != 200) {
          throw Exception('Backend ${response.statusCode}: ${response.body}');
        }
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return MirrorAnalysis.fromJson(decoded);
      },
    );
  }

  /// Re-run ONLY the hero render (Nano Banana edit + face-swap), without
  /// re-doing GPT analysis. Also retries forever until it gets a
  /// non-empty URL back. If the backend returns 200 with an empty url
  /// field, that's treated as a retryable failure (Replicate may have
  /// glitched). User never sees "Render returned empty URL" — we just
  /// try again.
  static Future<String> maximizeOnly({
    required Uint8List imageBytes,
    required List<String> improve,
  }) async {
    final gender = await LocalStoreService.userGender();
    final body = jsonEncode({
      'imageBase64': base64Encode(imageBytes),
      'brief':       {'improve': improve},
      if (gender != null) 'gender': gender,
    });

    return _retryForever<String>(
      label: 'maximize',
      run: () async {
        final response = await http.post(
          Uri.parse('${ApiConfig.backendBaseUrl}/maximize'),
          headers: {'Content-Type': 'application/json'},
          body: body,
        ).timeout(const Duration(seconds: 120));

        if (response.statusCode != 200) {
          throw Exception('Backend ${response.statusCode}: ${response.body}');
        }
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final url = (decoded['url'] as String? ?? '').trim();
        if (url.isEmpty) {
          // Treat as retryable — empty URL means Replicate hiccupped
          // on our backend. Throwing here kicks us into the next retry
          // of the outer _retryForever loop.
          throw Exception('empty url');
        }
        return url;
      },
    );
  }

  /// Infinite retry with exponential backoff.
  ///
  /// Waits: 3s, 6s, 12s, 24s, 48s, 60s, 60s, 60s… (capped at 60s).
  /// Under realistic Replicate outages a few minutes of retries resolve
  /// 100% of failures. Under a sustained upstream outage this will burn
  /// forever — that's the user's explicit ask ("never fail"). If a user
  /// wants to bail they can navigate away; the consumer is expected to
  /// check `mounted` before applying results.
  ///
  /// Every failure is logged to the Flutter debug console so the dev
  /// flow still surfaces what's going wrong — we just don't surface it
  /// to the user.
  static Future<T> _retryForever<T>({
    required String label,
    required Future<T> Function() run,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        return await run();
      } catch (err) {
        final seconds = _backoffSeconds(attempt);
        // ignore: avoid_print
        print('[$label] attempt $attempt failed: $err — retry in ${seconds}s');
        await Future.delayed(Duration(seconds: seconds));
      }
    }
  }

  static int _backoffSeconds(int attempt) {
    if (attempt <= 1) return 3;
    if (attempt == 2) return 6;
    if (attempt == 3) return 12;
    if (attempt == 4) return 24;
    if (attempt == 5) return 48;
    return 60; // cap
  }
}
