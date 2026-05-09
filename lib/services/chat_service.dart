import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/face_geometry.dart';
import 'face_asset_service.dart';
import 'local_store_service.dart';
import 'mirror_api_service.dart';
import 'scoring_service.dart';
import 'archetype_service.dart';

/// A single turn in the advisor chat.
///
/// An assistant message can carry a **pending** style_request — the
/// advisor recommended a visual (e.g. "mid-fade with 4cm textured crop")
/// but has NOT rendered it. The UI shows a GENERATE IMAGE button. Tap
/// fires /tryon → the rendered URL is attached to this same message by
/// mutating the instance the screen holds.
class ChatMessage {
  final ChatRole role;
  final String content;

  /// Rendered tryon result (populated AFTER the user taps GENERATE IMAGE).
  String? imageUrl;
  /// The visual descriptor used / proposed — shown as caption over image
  /// or as the body of the GENERATE IMAGE button row.
  final String? styleRequest;
  /// Zone of change: haircut|beard|hair_color|glasses|facial_hair|weight.
  final String? category;
  /// True while /tryon is in flight for this message.
  bool rendering;

  ChatMessage(
    this.role,
    this.content, {
    this.imageUrl,
    this.styleRequest,
    this.category,
    this.rendering = false,
  });

  /// True when the advisor proposed a visual but the user hasn't yet
  /// tapped GENERATE IMAGE. The button shows in this state.
  bool get hasPendingRender =>
      role == ChatRole.assistant &&
      imageUrl == null &&
      styleRequest != null &&
      styleRequest!.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'role': role == ChatRole.user ? 'user' : 'assistant',
    'content': content,
  };
}

enum ChatRole { user, assistant }

/// Response from /chat — text reply + optional visual ASK to render.
/// Backend no longer auto-renders; the UI shows GENERATE IMAGE when
/// styleRequest is set, user taps to fire /tryon.
class ChatReply {
  final String text;
  final String? styleRequest;
  final String? category;
  const ChatReply({
    required this.text,
    this.styleRequest,
    this.category,
  });
}

class ChatService {
  /// Send the conversation to the face-aware backend /chat endpoint. The
  /// user's scan image is included so the advisor can trigger Flux Kontext
  /// tryon renders inline when a visual would help the answer.
  ///
  /// Falls back to a rich local stub if the endpoint is unreachable.
  static Future<ChatReply> send({
    required List<ChatMessage> history,
    required FaceGeometry geometry,
    String? imagePath,
  }) async {
    final score = ScoringService.compute(geometry);
    final match = ArchetypeService.bestMatch(geometry);

    // Load image bytes if we have a path — backend uses for inline tryon.
    String? imageBase64;
    if (imagePath != null) {
      final bytes = await FaceAssetService.loadScanImageBytes(imagePath);
      if (bytes != null) imageBase64 = base64Encode(bytes);
    }

    final face = {
      'geometry':  MirrorApiService.geometryToJson(geometry),
      'score':     score.value,
      'tier':      score.tierLabel,
      'archetype': match.archetype.name,
      if (imageBase64 != null) 'imageBase64': imageBase64,
    };

    try {
      final gender = await LocalStoreService.userGender();
      final res = await http.post(
        Uri.parse('${ApiConfig.backendBaseUrl}/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'messages': history.map((m) => m.toJson()).toList(),
          'face':     face,
          if (gender != null) 'gender': gender,
        }),
      ).timeout(const Duration(seconds: 90));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        final reply = decoded['reply'] as String?;
        if (reply != null && reply.isNotEmpty) {
          return ChatReply(
            text:         reply,
            styleRequest: decoded['style_request'] as String?,
            category:     decoded['category']     as String?,
          );
        }
      }
    } catch (_) {
      // Fall through to local stub.
    }

    return ChatReply(
      text: _localFallback(
        history.isNotEmpty ? history.last.content : '', score, match, geometry),
    );
  }

  /// Deterministic local stub. More specific than the previous version —
  /// covers 12 common topics, always cites the user's actual numbers.
  static String _localFallback(
      String userMsg, AestheticScore s, ArchetypeMatch m, FaceGeometry g) {
    final lower = userMsg.toLowerCase();
    final weak   = s.weakestAxis.$1;
    final strong = s.strongestAxis.$1;

    String n(double v, [int d = 1]) => v.toStringAsFixed(d);

    bool has(List<String> needles) => needles.any((w) => lower.contains(w));

    if (has(['hair', 'cut', 'fade', 'crop', 'undercut', 'buzz'])) {
      if (g.headShape == 'long' || g.faceLengthRatio > 1.35) {
        return 'Your head shape is long (ratio ${n(g.faceLengthRatio, 2)}). '
            'Long hair will drag your face even longer — skip it. Go for '
            'volume on the sides, flatter on top: textured mid-fade, side '
            'part off the stronger cheekbone, crop length 3–4cm. That '
            'compresses the vertical axis and makes your jaw read sharper.';
      }
      if (g.headShape == 'broad' || g.fwhr > 2.0) {
        return 'Your face is broad (FWHR ${n(g.fwhr, 2)}). Wide cuts will '
            'make you look blocky — don\'t do crops or buzz cuts. Go '
            'taller on top: textured 5–6cm swept up, tighter sides, mid '
            'to low taper. That adds vertical balance.';
      }
      return 'Given your ${g.headShape} face and jaw angle ${n(g.jawAngle, 0)}°, '
          'a mid-fade with a 4cm textured top side-parted is your lane. '
          'Avoid heavy fringe — your strong ${strong.toLowerCase()} wants '
          'to be visible, not covered.';
    }

    if (has(['glasses', 'frame', 'eyewear', 'specs'])) {
      if (g.headShape == 'long' || g.faceLengthRatio > 1.35) {
        return 'Long/narrow head (${n(g.faceLengthRatio, 2)} ratio) — big '
            'round or oversized frames will not suit you, they\'ll swamp '
            'your face. Go rectangular, narrower than your face width, '
            'with a strong top bar. Acetate in matte tortoise or black.';
      }
      if (g.headShape == 'broad' || g.fwhr > 2.0) {
        return 'Broad face (FWHR ${n(g.fwhr, 2)}) — tiny rectangular '
            'frames disappear on you. You can carry larger, rounder '
            'frames — but pick ones that sit within your cheekbone width, '
            'not beyond. Tortoise, titanium, or clear.';
      }
      return 'Your face length is balanced. Go medium-sized — avoid '
          'bottom-heavy frames (weaken the ${strong.toLowerCase()}). '
          'Rectangular or subtle aviator works.';
    }

    if (has(['beard', 'stubble', 'facial hair', 'goatee'])) {
      if (g.jawAngle > 128) {
        return 'Your jaw angle is ${n(g.jawAngle, 0)}° — softer side. A '
            'short squared beard (5–7mm) will rebuild your mandibular '
            'edge from the outside. Keep the cheek line high, squared '
            'corners at the chin. Don\'t go pointy — that elongates.';
      }
      return 'Jaw at ${n(g.jawAngle, 0)}° is already sharp — heavy beard '
          'will cover what\'s working. Stay to 2–3mm stubble, tight '
          'neckline under the jaw curve. Preserve the line, don\'t '
          'smother it.';
    }

    if (has(['skin', 'acne', 'routine', 'skincare', 'cream'])) {
      return 'Non-negotiable base: gentle cleanser AM+PM, SPF 50 daily, '
          'tretinoin 0.025% 3×/week (ramp slow), azelaic acid 10% daily. '
          'Eight weeks of that, nothing else, before any add-ons. Your '
          'symmetry (${n(g.symmetryScore, 0)}/100) reads stronger when '
          'skin texture is uniform.';
    }

    if (has(['surgery', 'genioplasty', 'implant', 'filler', 'bichectomy'])) {
      return 'Surgical consults should target your lowest axis — '
          'currently $weak. Before scheduling anything, exhaust: mewing '
          '(12 weeks), body-fat to 12–14%, dental alignment. Those three '
          'alone shift measurable metrics enough to re-run this scan and '
          'inform the decision properly.';
    }

    if (has(['gym', 'lose', 'fat', 'body', 'weight', 'cut'])) {
      return 'Body fat is the highest-leverage facial intervention '
          'that isn\'t a scalpel. Below 14% body fat, jaw angle sharpens '
          'visibly and zygomatic shelf (FWHR ${n(g.fwhr, 2)}) reads '
          'harder. If you\'re above 18% now, cut takes priority over '
          'any styling move.';
    }

    if (has(['score', 'rating', 'why', 'tier'])) {
      return 'You scored ${s.value} (${s.tierLabel}). Strongest axis: '
          '$strong. Weakest: $weak. Archetype: ${m.archetype.name} '
          '(${(m.match * 100).round()}% match). The fastest lift is '
          'targeting $weak — everything else compounds off it.';
    }

    if (has(['makeup', 'concealer', 'foundation'])) {
      return 'For your canthal tilt of ${n(g.canthalTilt)}°, a subtle '
          'outer-eye shadow lift (warm brown, pulled outward) '
          'emphasizes your ${g.canthalTilt > 2 ? 'already-positive' : 'neutral'} '
          'tilt. Under-eye concealer warmer than your skin to kill '
          'shadow, not lighter.';
    }

    if (has(['archetype', 'match', 'look like'])) {
      return '${m.archetype.name} at ${(m.match * 100).round()}%. '
          '${m.archetype.tagline}. ${m.archetype.story}';
    }

    if (has(['protocol', 'program', 'plan'])) {
      return 'Your pulldown is $weak. Ask me to "start protocol" and '
          'I\'ll prescribe a 60-day program with daily check-ins and '
          'rescan milestones at day 14 / 30 / 60.';
    }

    return 'Tell me what you\'re thinking about: haircut, beard, skin, '
        'glasses, body comp, surgery, or what your score means. I\'ll '
        'answer against your actual numbers, not generic advice.';
  }
}

/// Standalone TryOn service — called from report recommendation cards
/// ("See me with this fade") and as explicit quick-actions in chat.
class TryOnService {
  static Future<String?> render({
    required String imagePath,
    required String styleRequest,
    required String category,
    required FaceGeometry geometry,
  }) async {
    final bytes = await FaceAssetService.loadScanImageBytes(imagePath);
    if (bytes == null) return null;

    try {
      final gender = await LocalStoreService.userGender();
      final res = await http.post(
        Uri.parse('${ApiConfig.backendBaseUrl}/tryon'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'imageBase64':  base64Encode(bytes),
          'styleRequest': styleRequest,
          'category':     category,
          'geometry':     MirrorApiService.geometryToJson(geometry),
          if (gender != null) 'gender': gender,
        }),
      ).timeout(const Duration(seconds: 120));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        return decoded['url'] as String?;
      }
    } catch (_) {}
    return null;
  }
}
