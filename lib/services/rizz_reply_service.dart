import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config/api_config.dart';
import '../data/rizz_lines.dart';
import 'screenshot_ocr_service.dart';
import 'villain/villain_api.dart';

/// One rewritten reply suggestion.
class RizzReply {
  final String text;
  final String tag;
  const RizzReply({required this.text, required this.tag});
}

/// Live debug trail captured during the LAST call to [generate].
/// Surfaces in the rizz reply screen's debug panel so the user can
/// SEE exactly what OCR extracted, what was POSTed, and what the
/// backend returned — without scrolling Xcode console.
class RizzDebug {
  static final List<String> log = [];
  static String ocrText = '';
  static String lastEndpoint = '';
  static int lastStatus = 0;
  static String lastResponse = '';
  static int parsedCount = 0;

  static void reset() {
    log.clear();
    ocrText = '';
    lastEndpoint = '';
    lastStatus = 0;
    lastResponse = '';
    parsedCount = 0;
  }

  static void add(String line) {
    final stamp = DateTime.now().toIso8601String().substring(11, 23);
    log.add('[$stamp] $line');
    print('[RIZZ-DBG] $line');
  }
}

/// Default placeholder face block that gets the backend past its
/// "no measurements provided" guard. The /chat endpoint short-
/// circuits on empty geometry/archetype, never reaching the LLM —
/// the debug trace showed that hardcoded reply on every rizz call.
/// These numbers don't matter (the rizz preamble in the user message
/// overrides the face-doctor framing once the model sees them); we
/// just need them PRESENT and shaped like the real Mirror payload.
Map<String, dynamic> _placeholderFace({String? imageBase64}) => {
  'geometry': const <String, dynamic>{
    'canthalTilt':          0.0,
    'symmetryScore':        82.0,
    'facialThirdTop':       33.0,
    'facialThirdMid':       33.0,
    'facialThirdLow':       34.0,
    'fwhr':                 1.9,
    'eyeSpacingRatio':      0.46,
    'jawAngle':             125.0,
    'chinProjection':       0.0,
    'faceLengthRatio':      1.30,
    'noseLengthRatio':      0.40,
    'lipFullness':          0.10,
    'brow2EyeGap':          0.05,
    'philtrumRatio':        0.30,
    'interpupillaryRatio':  0.43,
    'headShape':            'oval',
    'jawWidthRatio':        0.80,
  },
  'score':     78,
  'tier':      'Strong',
  'archetype': 'The Modern Man',
  if (imageBase64 != null) 'imageBase64': imageBase64,
};
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
    String scenario = '',
  }) async {
    RizzDebug.reset();
    var her = herMessage.trim();
    final ctx = context.trim();
    final scn = scenario.trim();
    final hasImage = screenshotBytes != null && screenshotBytes.isNotEmpty;
    RizzDebug.add('start her_len=${her.length} hasImage=$hasImage scn="$scn"');
    if (her.isEmpty && !hasImage && scn.isEmpty) {
      RizzDebug.add('nothing to send → arsenal fallback');
      return _fallbackFromArsenal(vibe);
    }

    // ── SILENT OCR — text path, not vision path ───────────────────────
    // Backend /chat is text-in, JSON-out — no vision support. We OCR
    // the screenshot ON-DEVICE via ML Kit, then send the extracted
    // text as the user message. When OCR succeeds we DROP the image
    // from the payload entirely + tell _buildPrompt this is a text
    // case (hasScreenshot: false). That's the difference between the
    // model answering "I can't read images" and actually writing
    // three replies to what she said.
    bool ocrUsed = false;
    if (hasImage && her.isEmpty) {
      final ocrText = await _ocrSilently(screenshotBytes);
      RizzDebug.ocrText = ocrText;
      RizzDebug.add('ocr extracted ${ocrText.length} chars');
      if (ocrText.isNotEmpty) {
        her = ocrText;
        ocrUsed = true;
      }
    }

    // Only send the image bytes when OCR failed AND we still have an
    // image — that's our only shot at a reply. Otherwise the text we
    // just extracted is far more useful than the raw image.
    final imageB64 = (hasImage && !ocrUsed) ? base64Encode(screenshotBytes) : null;

    // 1) Mirrorly backend /rizz/reply — the dedicated dating-text
    // coach endpoint. Separate from /chat (the face doctor). Returns
    // { replies: [{text, tag}, …] } directly so no JSON-from-prose
    // parsing required.
    try {
      RizzDebug.lastEndpoint = '/rizz/reply';
      final res = await http
          .post(
            Uri.parse('${ApiConfig.backendBaseUrl}/rizz/reply'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'her':      her,
              'vibe':     vibe.name,
              'ctx':      ctx,
              'scenario': scn,
            }),
          )
          .timeout(const Duration(seconds: 40));
      RizzDebug.lastStatus = res.statusCode;
      RizzDebug.add('/rizz/reply status=${res.statusCode}');
      if (res.statusCode == 200) {
        RizzDebug.lastResponse = res.body;
        try {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          final raw  = body['replies'] as List<dynamic>? ?? const [];
          final parsed = raw
              .whereType<Map>()
              .map((e) => RizzReply(
                    text: ((e['text'] ?? e['line'] ?? '') as String).trim(),
                    tag:  ((e['tag']  ?? 'RIZZ') as String).toString().toUpperCase(),
                  ))
              .where((r) => r.text.isNotEmpty)
              .toList();
          RizzDebug.parsedCount = parsed.length;
          RizzDebug.add('/rizz/reply parsed ${parsed.length} replies');
          if (parsed.length >= 3) return parsed.take(3).toList();
          if (parsed.isNotEmpty) {
            final arsenal = _fallbackFromArsenal(vibe);
            while (parsed.length < 3 && arsenal.isNotEmpty) {
              parsed.add(arsenal.removeAt(0));
            }
            return parsed;
          }
        } catch (e) {
          RizzDebug.add('/rizz/reply parse threw $e');
        }
      } else {
        RizzDebug.add('/rizz/reply non-200 body="${res.body.length > 200 ? "${res.body.substring(0, 200)}…" : res.body}"');
      }
    } catch (e) {
      RizzDebug.add('/rizz/reply threw $e');
    }

    // 2) Fall back to VillainApi.council — Auralay's text-in/text-out
    // chat endpoint. CRITICAL: this is the SEPARATE Auralay backend
    // (auralayai-production-65c2.up.railway.app), not the Mirrorly
    // /chat which is hardwired for face advice. council has its own
    // system prompt + LLM and accepts arbitrary text, so the rizz
    // preamble actually runs the model instead of being short-
    // circuited by the face-doctor handler.
    try {
      RizzDebug.lastEndpoint = '/v1/villain/council';
      final messageText = _buildPrompt(her, vibe, ctx,
          scenario: scn, hasScreenshot: imageB64 != null);
      RizzDebug.add('built prompt ${messageText.length} chars');
      final turn = await VillainApi.council(
        text:    messageText,
        history: const [],
      ).timeout(const Duration(seconds: 40));
      RizzDebug.lastStatus = 200;
      final reply = turn.reply.trim();
      RizzDebug.lastResponse = reply;
      RizzDebug.add('council reply len=${reply.length} '
          'sample="${reply.length > 80 ? "${reply.substring(0, 80)}…" : reply}"');
      final parsed = _parseReplies(reply);
      RizzDebug.parsedCount = parsed.length;
      RizzDebug.add('council parsed ${parsed.length} replies');
      if (parsed.length >= 3) return parsed.take(3).toList();
      if (parsed.isNotEmpty) {
        RizzDebug.add('padding ${parsed.length} AI replies with arsenal');
        final arsenal = _fallbackFromArsenal(vibe);
        while (parsed.length < 3 && arsenal.isNotEmpty) {
          parsed.add(arsenal.removeAt(0));
        }
        return parsed;
      }
    } catch (e) {
      RizzDebug.add('council threw $e');
    }

    // 3) Final fallback — curated lines that match the vibe.
    RizzDebug.add('all paths failed → arsenal fallback');
    return _fallbackFromArsenal(vibe);
  }

  // ── Internals ─────────────────────────────────────────────────────────

  /// Write the in-memory screenshot bytes to a tmp file (ML Kit needs
  /// a path, not bytes), run text recognition on the tmp file, then
  /// delete it. Returns the joined text from the last few chat
  /// bubbles, ready to feed straight into the RIZZ GOD prompt. Any
  /// failure (no text, ML Kit error, file write fails) returns ''
  /// so the caller can fall through to the image-bytes path.
  ///
  /// Wrapped with a 12s timeout so ML Kit hanging on a bad image
  /// can't lock the whole generator UI in a spinner. The user sees
  /// the AI step kick in after at most 12s either way.
  static Future<String> _ocrSilently(Uint8List bytes) async {
    RizzDebug.add('ocr start bytes=${bytes.length}');
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/rizz_ocr_'
          '${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      RizzDebug.add('ocr wrote tmp file');
      try {
        final text = await ScreenshotOcrService.extractRecent(path)
            .timeout(const Duration(seconds: 12), onTimeout: () {
              RizzDebug.add('ML Kit TIMED OUT after 12s');
              return '';
            });
        RizzDebug.add('ocr ok extracted=${text.length} chars '
            'sample="${text.length > 60 ? "${text.substring(0, 60)}…" : text}"');
        return text;
      } finally {
        try { await file.delete(); } catch (_) {}
      }
    } catch (e) {
      RizzDebug.add('ocr THREW $e');
      return '';
    }
  }

  /// Parse the model's reply into [RizzReply]s. The /chat endpoint is
  /// a general chat surface, not a structured-output API, so models
  /// sometimes wrap the JSON in fences ("```json…```"), chat preamble
  /// ("Sure! Here are three options: …"), or fall out of JSON entirely
  /// and return a numbered list. We try every format we've seen so the
  /// UI always lands real rizz instead of falling through to the
  /// curated arsenal fallback.
  static List<RizzReply> _parseReplies(String raw) {
    if (raw.trim().isEmpty) return const [];

    // 1) Try strict JSON array — the format we ask for in the prompt.
    final jsonResult = _tryParseJsonArray(raw);
    if (jsonResult.length >= 3) return jsonResult;

    // 2) Try line-by-line — numbered list, bullets, or plain lines.
    final lineResult = _tryParseLines(raw);
    if (lineResult.length >= 3) return lineResult;

    // Return whatever we got even if < 3 — the caller falls back to
    // the curated arsenal when this list is shorter than 3.
    return jsonResult.isNotEmpty ? jsonResult : lineResult;
  }

  static List<RizzReply> _tryParseJsonArray(String raw) {
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

  /// Last-ditch parser — pull up to 3 reply lines out of WHATEVER the
  /// model returned. Layered:
  ///   1. Numbered / bulleted list, one per line
  ///   2. Quoted strings on their own lines
  ///   3. PARAGRAPH FALLBACK — if the response is one long paragraph
  ///      (which is what the face-doctor backend keeps doing), split
  ///      on sentence boundaries and grab anything that LOOKS like a
  ///      message rather than advice
  static List<RizzReply> _tryParseLines(String raw) {
    final out = <RizzReply>[];
    final stripped = raw
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();
    final numbered = RegExp(r'^(?:\s*(?:\d+[\.\)]|[-*•])\s*)?');

    bool isJunk(String l) {
      final lower = l.toLowerCase();
      if (l.isEmpty || l.length > 140) return true;
      if (lower.startsWith('here') ||
          lower.startsWith('sure') ||
          lower.startsWith('option') ||
          lower.startsWith('safest') ||
          lower.startsWith('middle') ||
          lower.startsWith('boldest') ||
          lower.startsWith('reply') ||
          lower.startsWith('let me') ||
          lower.startsWith('i\'ll')) {
        return true;
      }
      return false;
    }

    String clean(String l) {
      var line = l.trim().replaceFirst(numbered, '');
      // Drop wrapping quotes — both straight and curly.
      while (line.length >= 2 &&
          (line.startsWith('"') || line.startsWith('"') ||
           line.startsWith('\'') || line.startsWith('"')) &&
          (line.endsWith('"') || line.endsWith('"') ||
           line.endsWith('\'') || line.endsWith('"'))) {
        line = line.substring(1, line.length - 1).trim();
      }
      // Drop "Send:" / "Try:" prefixes some models add.
      final prefixMatch = RegExp(
        r'^(?:send|try|reply with|message her|say|text her)\s*[:\-—]\s*',
        caseSensitive: false,
      ).firstMatch(line);
      if (prefixMatch != null) line = line.substring(prefixMatch.end);
      return line.trim();
    }

    // PASS 1 — newline-separated lines.
    for (final rawLine in stripped.split('\n')) {
      final line = clean(rawLine);
      if (isJunk(line)) continue;
      out.add(RizzReply(text: line, tag: 'RIZZ'));
      if (out.length == 3) return out;
    }

    // PASS 2 — paragraph fallback. If we got <3 lines from Pass 1,
    // split on sentence boundaries and pick anything that reads as
    // a message. Catches the case where the model returned one long
    // paragraph instead of three line-separated replies (which is
    // exactly what the face-doctor backend keeps doing).
    if (out.length < 3) {
      // Walk the whole response, grab quoted strings first (they're
      // the model's own examples of what to send).
      final quoted = RegExp(r'"([^"\n]{4,140})"').allMatches(stripped);
      for (final m in quoted) {
        final line = clean(m.group(1) ?? '');
        if (isJunk(line)) continue;
        if (out.any((r) => r.text == line)) continue;
        out.add(RizzReply(text: line, tag: 'RIZZ'));
        if (out.length == 3) return out;
      }
    }

    if (out.length < 3) {
      // Last resort — split paragraph on sentence boundaries.
      final sentences = stripped.split(RegExp(r'(?<=[.!?])\s+'));
      for (final s in sentences) {
        final line = clean(s);
        if (isJunk(line)) continue;
        if (out.any((r) => r.text == line)) continue;
        out.add(RizzReply(text: line, tag: 'RIZZ'));
        if (out.length == 3) return out;
      }
    }

    return out;
  }

  /// THE RIZZ GOD — elite system prompt embedded as a user message
  /// (since /chat is chat-style). Treats the model as the friend who
  /// has actually slept with the prom queen, not a corporate chatbot.
  /// Gives it room to be charming, sensual, vulnerable, dominant —
  /// whatever the moment calls for — within a tight quality bar.
  ///
  /// When [hasScreenshot] is true, the model reads the attached image
  /// (Hinge/Tinder/iMessage) and identifies HER most recent bubble
  /// natively. No OCR. When [scenario] is set, that biases the move
  /// pool (PLAN A DATE → DATE PROPOSAL emphasis, etc).
  static String _buildPrompt(String her, RizzVibe vibe, String ctx,
      {String scenario = '', bool hasScreenshot = false}) {
    final taskHeader = hasScreenshot
        ? 'The attached image is a chat screenshot (Hinge / Tinder / '
          'iMessage / Instagram DM). Identify HER most recent message — '
          'the LAST bubble that is not from the user. Treat that as HER.'
        : (her.isEmpty
              ? 'No specific message yet — the user is opening cold or '
                'planning their first move.'
              : 'HER LAST MESSAGE: """$her"""');

    final scenarioLine = scenario.isEmpty
        ? ''
        : '\nSCENARIO: "$scenario" — bias your three replies toward '
          'lines that move the conversation through this scenario.';

    return '''
You are RIZZ — the man whose texts make her phone go off on the bedside
table at 11pm. Not a chatbot. Not a coach with a worksheet. The friend
who has actually slept with the prom queen, the editor of GQ, and the
girl every guy in his year wanted. He is writing the message the user
should send, NOT the message the user is brave enough to send.

THE TRUTH ABOUT WOMEN 18-30 IN 2026 (you understand this in your bones):

- She gets 40 boring openers a day. She has stopped reading the first
  six words. You have to disrupt or you are noise.
- She feels DESIRE when she catches herself smiling at her phone
  ALONE. Your job is to be the message that makes her group-chat go
  off — "girls he just said..."
- She loses interest the second she senses effort. Confidence reads
  as ease, not as edge. Tryhard kills faster than dry.
- She has a "type" she tells her friends about and a type she actually
  responds to. The second is calmer, more amused, harder to impress.
- She likes a man who doesn't NEED her to like him. Scarcity beats
  enthusiasm every time. Wanting is sexy; needing is not.
- She wants to feel SEEN, not flattered. A specific observation beats
  ten compliments.
- The SCREENSHOT TEST is everything. If she would share the line with
  her group chat with no commentary, it pulled. If she would react
  "ok", it failed.

YOUR REPERTOIRE — the moves that pull in 2026:

- COMPRESSED CINEMA       implies a whole relationship in 12 words
                          "we'd date six months, fight at a wedding,
                          write songs about each other"
- ARCHETYPE READ          tells her what kind of girl she is, accurately
                          "you give 'her parents don't approve' energy"
- INTIMATE PRESUMPTION    acts like you already know her well
                          "be honest, are you the friend everyone has
                          a crush on"
- VULNERABLE FLEX         admits a "weakness" that's actually a flex
                          "i'm normally calm but you make me text
                          like i'm 19"
- MISINTERPRETATION       misreads her in a flirty direction
                          "saying 'lol' is a marriage proposal where
                          i'm from"
- FRAME CHECK             assumes the outcome, forces her to disagree
                          "tell me you have a bf so i can move on
                          with my life"
- PUSH-PULL               playfully pushes her away, she has to chase
                          "we're not going to work out. i can't
                          promise that"
- HIGH-AGENCY             scarce, secure, decisive
                          "give me your number before i lose interest
                          in my own bit"
- DOMESTIC PROJECTION     paints a future scene she has to react to
                          "be honest — what would we fight about in
                          three months"
- INAPPROPRIATE COMPLIMENT  too-specific to be generic, almost rude
                            "your photos commit acts of psychological
                            warfare"
- DATE PROPOSAL           moves it offline directly
                          "let's argue about something over wine"

HARD RULES — the no-trash rule (your reputation is at stake):

- ≤ 14 words per line. Phone-fatigue threshold.
- No 2014 PUA. No "you'd be cute if". Negs read mean now, not bold.
- No essays. No back-to-back questions stacked together.
- No emojis unless they are load-bearing. Lowercase mostly.
- Specific > generic. Observation > question.
- Sensual is fine. Suggestive is fine if she opened that door first.
  Explicitly sexual is for AFTER the date.
- Confident, not arrogant. Charming, not slick. Direct, not desperate.
- BOLDEST line should pass this test: "if she screenshotted this to
  her group chat, would they say 'answer him RIGHT NOW' or 'block'?"
  It must be the first.

BANNED OPENINGS — never start a line with these. They scream
"corporate dating coach", not friend who pulls:
- "Hey, I've really enjoyed"     - "It's important to"
- "Let's grab coffee this week"  - "Just be yourself"
- "Confidence is key"             - "Keep it simple and direct"
- "Show her you're"               - "Let her know"
- "Hi/Hey [name]," (greetings)    - "I was wondering if you'd"

VIBE the user chose: ${vibe.directive}

$taskHeader$scenarioLine
${ctx.isEmpty ? '' : 'CONTEXT (one line of background): "$ctx"'}

WRITE THREE replies, ranked SAFEST → MIDDLE → BOLDEST.
Each gets a small-caps MOVE LABEL drawn from your repertoire
(COMPRESSED CINEMA · ARCHETYPE READ · INTIMATE PRESUMPTION ·
VULNERABLE FLEX · MISINTERPRETATION · FRAME CHECK · PUSH-PULL ·
HIGH-AGENCY · DOMESTIC PROJECTION · INAPPROPRIATE COMPLIMENT ·
DATE PROPOSAL · SELF-AWARE OPEN · META-FLIRT · REFRAME · TEASE).

OUTPUT — return ONLY this JSON array. No fences. No prose. No
commentary. The user is reading this output INSIDE an iMessage-style
bubble UI — every character that is not the line itself is noise:

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
