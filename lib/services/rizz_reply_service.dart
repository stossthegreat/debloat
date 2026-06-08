import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../data/rizz_lines.dart';

/// One rewritten reply suggestion. [tag] is the small-caps move
/// label that explains WHY the line works — SELF-AWARE OPEN,
/// FRAME CHECK, PUSH-PULL, MISINTERPRETATION, etc. Mirrors the
/// labels on the curated arsenal cards so the user learns the
/// move, not just the words.
class RizzReply {
  final String text;
  final String tag;
  const RizzReply({required this.text, required this.tag});
}

/// Five tonal vibes the user can request. AUTO lets the model pick
/// based on her cadence. The other four are hard pulls.
enum RizzVibe { auto, funny, flirty, smooth, bold }

extension RizzVibeLabel on RizzVibe {
  String get label => switch (this) {
        RizzVibe.auto   => 'AUTO',
        RizzVibe.funny  => 'FUNNY',
        RizzVibe.flirty => 'FLIRTY',
        RizzVibe.smooth => 'SMOOTH',
        RizzVibe.bold   => 'BOLD',
      };

  String get directive => switch (this) {
        RizzVibe.auto   => 'auto — pick whichever move actually pulls best',
        RizzVibe.funny  => 'funny — short, witty, makes her screenshot it',
        RizzVibe.flirty => 'flirty — push-pull / heat, never thirsty',
        RizzVibe.smooth => 'smooth — high-agency, confident, scarce',
        RizzVibe.bold   => 'bold — frame-check / disqualifier, calls her out',
      };
}

/// Rizz God — generates 3 ranked reply options for a message she sent.
///
/// Strategy:
///   1. Calls /rizz/reply on the Mirrorly backend with {her, vibe, ctx}.
///   2. If the route doesn't exist yet (404) or returns malformed JSON,
///      falls back to /chat with a heavy system preamble that instructs
///      GPT to output ONLY the JSON shape we need.
///   3. If both backend paths fail, returns three lines from the curated
///      arsenal matched against the requested vibe — guarantees the
///      "no trash" rule even on a dead backend.
class RizzReplyService {
  static Future<List<RizzReply>> generate({
    String herMessage = '',
    Uint8List? screenshotBytes,
    required RizzVibe vibe,
    String context = '',
  }) async {
    final her = herMessage.trim();
    final ctx = context.trim();
    final hasImage = screenshotBytes != null && screenshotBytes.isNotEmpty;
    if (her.isEmpty && !hasImage) return _fallbackFromArsenal(vibe);

    final imageB64 = hasImage ? base64Encode(screenshotBytes) : null;

    // 1) Try the dedicated rizz endpoint first. Future-route; the
    // payload here is the clean shape that backend ought to expose.
    try {
      final res = await http
          .post(
            Uri.parse('${ApiConfig.backendBaseUrl}/rizz/reply'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'her':   her,
              'vibe':  vibe.name,
              'ctx':   ctx,
              if (imageB64 != null) 'imageBase64': imageB64,
            }),
          )
          .timeout(const Duration(seconds: 40));
      if (res.statusCode == 200) {
        final parsed = _parseReplies(res.body);
        if (parsed.length >= 3) return parsed.take(3).toList();
      }
    } catch (_) {/* fall through */}

    // 2) Fall back to /chat. GPT-4o vision reads the screenshot
    // directly when imageBase64 is included — no OCR step needed.
    try {
      final messageText = _buildPrompt(her, vibe, ctx,
          hasScreenshot: hasImage);
      final res = await http
          .post(
            Uri.parse('${ApiConfig.backendBaseUrl}/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'messages': [
                {'role': 'user', 'text': messageText},
              ],
              'face': const <String, dynamic>{},
              'mode': 'rizz_reply',
              if (imageB64 != null) 'imageBase64': imageB64,
            }),
          )
          .timeout(const Duration(seconds: 40));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final reply = (body['reply'] as String?) ?? '';
        final parsed = _parseReplies(reply);
        if (parsed.length >= 3) return parsed.take(3).toList();
      }
    } catch (_) {/* fall through */}

    // 3) Final fallback — curated lines that match the vibe so the
    // user is never stranded on a dead backend.
    return _fallbackFromArsenal(vibe);
  }

  // ── Internals ─────────────────────────────────────────────────────────

  static List<RizzReply> _parseReplies(String raw) {
    if (raw.trim().isEmpty) return const [];
    // The backend may wrap the JSON in fences or chatty text. Find the
    // first `[` and last `]` and try parsing just that slice.
    final start = raw.indexOf('[');
    final end   = raw.lastIndexOf(']');
    if (start < 0 || end <= start) return const [];
    final slice = raw.substring(start, end + 1);
    try {
      final decoded = jsonDecode(slice) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((e) => RizzReply(
                text: ((e['text'] ?? e['line'] ?? e['reply']) as String?)
                        ?.trim() ??
                    '',
                tag: ((e['tag'] ?? e['move'] ?? 'RIZZ') as String?)
                        ?.toString()
                        .toUpperCase() ??
                    'RIZZ',
              ))
          .where((r) => r.text.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// The Rizz God system + few-shot prompt. Embedded as a single user
  /// message because /chat is a chat-style endpoint, not a system role
  /// endpoint. The trick: front-load the persona and constraints, then
  /// state the task, then demand a tight JSON-only response.
  ///
  /// When [hasScreenshot] is true, the prompt instructs the model to
  /// READ the attached image (Hinge/Tinder/iMessage chat screenshot),
  /// identify HER most recent message, then write three replies. No
  /// OCR step required — GPT-4o vision parses the chat UI natively.
  static String _buildPrompt(String her, RizzVibe vibe, String ctx,
      {bool hasScreenshot = false}) {
    final taskHeader = hasScreenshot
        ? 'The attached image is a chat screenshot. Identify HER most '
          'recent message in it (the LAST bubble that is not from the '
          'user). Treat that as HER MESSAGE.'
        : 'HER MESSAGE: """$her"""';

    return '''
You are RIZZ GOD — the 2026 Gen-Z reply coach for men aged 18-26.

TONE — what works in 2026:
- Self-aware (breaks the 4th wall about the awkward dating-app moment)
- Frame-check (assumes the outcome; high agency)
- Misinterpretation (willfully misreads her in a flirty direction)
- Push-pull (playful disqualifier that hooks)
- Specific observation > generic compliment

HARD RULES — the no-trash rule:
- Maximum 14 words per line
- No physical compliments without context ("u r hot" is banned)
- No 2014 PUA neg-and-recover. No "you'd be cute if..." cringe
- No essays, no questions stacked back-to-back
- No emojis unless absolutely necessary
- Must pass THE SCREENSHOT TEST: a 22-year-old would save this to her
  group chat and laugh

VIBE: ${vibe.directive}

$taskHeader
${ctx.isEmpty ? '' : 'CONTEXT (one line): """$ctx"""'}

TASK: write THREE reply options ranked safest → boldest.
Each reply must include a small-caps MOVE LABEL: one of
SELF-AWARE OPEN · NOTICED COMPLIMENT · FRAME CHECK · MISINTERPRETATION ·
PUSH-PULL · HIGH-AGENCY · DISQUALIFIER · META-FLIRT · DATE PROPOSAL ·
PROXIMITY · REFRAME · TEASE.

OUTPUT — return ONLY this JSON array. No prose. No fences. No commentary:
[
  {"text": "...", "tag": "MOVE LABEL"},
  {"text": "...", "tag": "MOVE LABEL"},
  {"text": "...", "tag": "MOVE LABEL"}
]
''';
  }

  /// Final fallback when the backend is down. Picks three lines from the
  /// curated arsenal that match the vibe. Guarantees the "no trash" rule
  /// because everything here was hand-picked.
  static List<RizzReply> _fallbackFromArsenal(RizzVibe vibe) {
    // Map vibe → which two categories to draw from.
    final slugs = switch (vibe) {
      RizzVibe.funny  => ['tease', 'openers'],
      RizzVibe.flirty => ['heat', 'tease'],
      RizzVibe.smooth => ['heat', 'close'],
      RizzVibe.bold   => ['cold', 'close'],
      RizzVibe.auto   => ['openers', 'tease'],
    };
    final pool = <RizzLine>[];
    for (final cat in RizzArsenal.categories) {
      if (slugs.contains(cat.slug)) pool.addAll(cat.lines);
    }
    pool.shuffle();
    return pool
        .take(3)
        .map((l) => RizzReply(text: l.text, tag: l.tag))
        .toList();
  }
}
