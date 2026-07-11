import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/api_config.dart';
import '../../services/paywall_gate.dart';
import '../../services/rizz_reply_service.dart' show RizzVibe, RizzVibeLabel;
import '../../services/screenshot_ocr_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/ai_consent_dialog.dart';
import '../../widgets/common/imhim_wordmark.dart';

/// CHAT WITH MIRRORLY — clean, sexy, no-bullshit dating + self-improvement
/// coach. Editorial bubbles, preset chips, screenshot upload, tap-to-
/// dismiss keyboard. Backed by /chat with mode=rizz_mentor.
class RizzChatScreen extends StatefulWidget {
  const RizzChatScreen({super.key});

  @override
  State<RizzChatScreen> createState() => _RizzChatScreenState();
}

class _RizzMsg {
  final String role; // 'user' | 'assistant'
  final String text;
  final Uint8List? image; // optional screenshot the user attached
  const _RizzMsg(this.role, this.text, {this.image});
}

class _RizzChatScreenState extends State<RizzChatScreen> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_RizzMsg> _msgs = [
    const _RizzMsg('assistant',
        // v298 — copy stripped to ONLY what the model actually does
        // well in production. Profile-pic + single-photo paths kept
        // hallucinating ("I can\'t view images") even after the v296
        // vision hardening, so we don\'t promise them in the intro
        // any more. Bro: "just take profile pic talk in the ai
        // intro on chat page — coz it don\'t fucking work. Clean
        // message about paste your chat for a breakdown or a rizz
        // line."
        'what\'s good. paste a screenshot of your chat with her '
        'and i\'ll break down what\'s working, what flopped, and '
        'the exact line to send next.\n\n'
        'or just ask me anything — "what should i open with", '
        '"how do i get her back", "tell me a banger" — i\'ll give '
        'you the line and tell you why it lands.\n\n'
        'tap any line in quotes to copy it.'),
  ];
  bool _sending = false;
  /// Active tone preset. Matches the rizz reply screen so picking
  /// SENSUAL / PLAYFUL / etc here behaves identically — the next
  /// user turn (or transform tap) routes through the chosen tone
  /// register. Default FLIRTY.
  RizzVibe _tone = RizzVibe.flirty;

  // v275 — back to the ORIGINAL 7 cold-state openers. Bro caught the
  // problem with my v265 additions: "Read her profile" and "Where
  // did I go wrong?" make no sense without an image in hand — tapping
  // either with no screenshot makes the AI politely ask the user to
  // upload one, which is the exact friction a preset is supposed to
  // skip. Both removed. The behaviour they were trying to expose is
  // already handled automatically the moment a screenshot lands (the
  // dual-mode wrapper detects PROFILE vs CHAT and routes), so the
  // dedicated chips were redundant.
  static const _presets = <String>[
    'Flirty first message',
    'Playful comeback',
    'Ask her out',
    'Plan a date',
    'Keep the convo going',
    'Recover from a bad reply',
    'Win back a ghost',
  ];

  /// v275 — full prompt sent to the backend when the user taps a
  /// preset chip. The chip LABEL is short (so the chat bubble reads
  /// clean), but the API payload is the full self-contained prompt.
  /// This is what stops the AI from replying "tell me more about her"
  /// — the prompt explicitly says "no context needed, produce a line
  /// directly." Bro: "the response comes then and there."
  static const Map<String, String> _presetPrompts = {
    'Flirty first message':
      'Give me a flirty first message I can send to a new match RIGHT '
      'NOW. No context needed — produce a banger of an opener in '
      'double quotes that would work on Hinge / Tinder / Bumble. '
      'Make it feel specific, not a generic pickup line. ONE line in '
      'quotes plus one short sentence on WHY it lands.',
    'Playful comeback':
      'Give me a playful comeback I can use when a girl is teasing me '
      'on a dating app. No context — assume she just sent something '
      'cheeky and I need to fire back. ONE line in double quotes that '
      'matches her energy without folding. One short sentence on the '
      'move underneath.',
    'Ask her out':
      'Give me a confident way to ask her out for the first date right '
      'now. No context needed — make it universal: someone I\'ve been '
      'texting on Hinge, going well, ready to lock in a date. ONE line '
      'in double quotes plus one short sentence on why it works.',
    'Plan a date':
      'Give me a specific, confident date PROPOSAL I can send. Name a '
      'place, vibe or activity. Cocky-warm, not desperate. No context — '
      'assume we\'ve been chatting and it\'s time to move it offline. '
      'ONE line in double quotes plus one short sentence on the angle.',
    'Keep the convo going':
      'Give me a line that pivots a stalling chat into something '
      'interesting. No context — assume she replied short and the convo '
      'is cooling. Use observation, intimate-probe, or compressed-cinema '
      'style. ONE line in double quotes plus one short sentence on the '
      'move.',
    'Recover from a bad reply':
      'Give me a line that recovers a chat after she replied flat / '
      'short / one-word. Acknowledge the cool-off, redirect with high '
      'agency, do not beg. ONE line in double quotes plus one short '
      'sentence on the move.',
    'Win back a ghost':
      'Give me a line that re-engages a girl who went silent on me. '
      'Confident, slightly mysterious, doesn\'t reek of effort. Could '
      'be a callback to something earlier in the chat or a fresh angle. '
      'ONE line in double quotes plus one short sentence on why it '
      'works.',
  };

  @override
  void initState() {
    super.initState();
    // Pro-only route — re-check on mount so a deep link or stale
    // navigation push from before subscription expired bounces to
    // the paywall instead of leaking the coach.
    WidgetsBinding.instance.addPostFrameCallback((_) => _gate());
  }

  Future<void> _gate() async {
    final pro = await PaywallGate.isPro();
    if (!mounted || pro) return;
    // Replace this screen with the paywall — back from paywall
    // returns to the Rizz tab, never to a locked chat surface.
    context.pushReplacement('/paywall',
        extra: {'source': 'rizz_chat_locked'});
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent + 200,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(String text, {Uint8List? image, String? apiText}) async {
    final msg = text.trim();
    if ((msg.isEmpty && image == null) || _sending) return;
    // AI consent gate (App Store 5.1.2(i)) — no chat/screenshot reaches
    // OpenAI without permission. Silent once granted.
    if (!await AiConsentDialog.ensure(context)) return;
    if (!mounted) return;
    HapticFeedback.selectionClick();
    // v275 — apiText lets the caller display a SHORT label in the
    // chat bubble while sending a LONGER, self-contained prompt to
    // the backend. Used by the preset chips so "Flirty first message"
    // shows in the user's bubble but the AI receives a full directive
    // ("produce a banger of an opener…") that triggers a direct
    // line, not a "tell me more about her" follow-up question.
    final apiOverride = apiText?.trim();
    // v265 — detect ANALYZE-ONCE-vs-ITERATE mode BEFORE we push the
    // new user turn into _msgs. The first time the user attaches an
    // image, we ship the full dual-mode coach wrapper. Every
    // subsequent turn (text-only, or even a new image) is treated
    // as ITERATION: "you've already given the analysis, just deliver
    // ONE new suggestion line in quotes — no breakdown, no markdown
    // sections, no re-explaining who she is."
    //
    // Detection: have we EVER attached an image AND received a reply
    // back? If yes, we're in iterate mode for every new turn,
    // including new uploads (user just wants the next line on the
    // updated state). Iteration prompt is much shorter — kills the
    // re-explain-every-tap problem bro flagged on the Wing AI
    // screenshots ("it only explains once").
    final hadImageBefore = _msgs.any((m) =>
        m.role == 'user' && m.image != null);
    // v296 — only iterate when NO new image arrived. A fresh image
    // upload always re-fires the full coach wrapper so the model
    // analyses what the user just dropped instead of refusing it
    // ("I can't view images directly") — the iteration wrapper
    // tells the model not to re-break-down, which gpt-4o-mini was
    // interpreting as "don't look at this new image either." Now
    // text-only follow-ups keep iterating (short, one-line replies),
    // but every new image lands on the full classifier path.
    final iterating = hadImageBefore && image == null;
    setState(() {
      _msgs.add(_RizzMsg('user', msg.isEmpty ? '(screenshot)' : msg,
          image: image));
      _sending = true;
    });
    _ctrl.clear();
    _scrollToBottom();
    // v275 — when the caller passed an apiText override, use it as
    // the base "effective" string the backend sees. The bubble in
    // _msgs already shows the short label; this swap only affects
    // the outbound API turn.
    var effective = apiOverride != null && apiOverride.isNotEmpty
        ? apiOverride
        : msg;
    if (image != null) {
      _dbg('vision path — sending image bytes (${image.length}) to backend · iterating=$iterating');
      // v273 — 10x DEEPER breakdown. Bro: "the breakdown the ai gives
      // — 10x it." Old wrapper was 3 bullets (WHAT WORKED / FELL
      // FLAT / SEND THIS) — read as a stub. New wrapper is the
      // Wing-AI-style multi-section analysis: interest level,
      // dynamic read, multiple green flags, multiple misfires,
      // her likely read of him, predicted next move, then the
      // sent line. ~5x the words, ~10x the perceived value.
      //
      // Iteration mode still gets the slim "just the next line"
      // wrapper so preset taps don't repeat the breakdown.
      final coachWrapper = iterating
        ? ''
          'I attached an updated screenshot. You already gave me '
          'the full analysis earlier in this thread. DO NOT repeat '
          'it. Just deliver ONE new suggestion line in double '
          'quotes that fits the current state of the chat / '
          'profile. No headers, no markdown sections, no '
          'preamble — one quoted line + one short sentence of '
          'context max.'
        : ''
          'I attached an image. LOOK AT IT. You have vision — '
          'use it. Classify FIRST, then respond.\n\n'
          'CLASSIFICATION (you MUST pick exactly one):\n'
          '  - PROFILE PAGE if the image shows: a person\'s NAME, '
          'age, distance, BIO TEXT, PROMPT ANSWERS like "My ideal '
          'sunday is…" / "Two truths and a lie" / "I\'m looking '
          'for…", PHOTOS arranged in a profile-card layout, '
          'dating-app profile UI (Hinge / Tinder / Bumble / Match / '
          'Coffee Meets Bagel). Any ONE of these signals is enough — '
          'if you see prompt answers OR a bio paragraph OR a stacked '
          'profile-photo layout, IT IS A PROFILE.\n'
          '  - CHAT THREAD if the image shows: speech bubbles on '
          'LEFT and RIGHT sides of the screen between two people '
          '(iMessage / SMS / Hinge chat / Bumble chat / Instagram '
          'DM / Snapchat / WhatsApp). The presence of typed message '
          'bubbles trading back and forth = CHAT.\n'
          '  - JUST A PHOTO if the image is a single picture of a '
          'person — no chat bubbles, no bio paragraph, no dating-app '
          'UI. Could be a selfie, mirror pic, candid shot, full-body '
          'photo, posed outfit pic, IG-style portrait. No text on '
          'screen besides maybe a caption. THIS IS THE FALLBACK — '
          'if it\'s a clear photo of a person and the other two '
          'don\'t fit, pick this one.\n\n'
          'Tell yourself: "This is a [PROFILE / CHAT / PHOTO]" '
          'before you write anything. Then deliver a FULL coach '
          'breakdown — long, specific, actually useful. No three-'
          'bullet stub. Match the format for the type you picked.\n\n'
          'IF CHAT THREAD: read every bubble top→bottom as '
          'chronological. The last bubble on her side is the reply '
          'target. Output these sections, IN THIS ORDER, with the '
          'exact emoji headers:\n\n'
          '  📊 INTEREST LEVEL: a single line — percent (your read) '
          'and one word ("rising" / "engaging" / "lukewarm" / '
          '"dodging"). Example: "72% · rising"\n\n'
          '  💬 DYNAMIC: 2-3 sentences on what\'s actually happening '
          'between you. Is she leaning in? Testing? Deflecting? '
          'Building? Playing? Name the move she\'s running and '
          'where she\'s at emotionally.\n\n'
          '  ✅ GREEN FLAGS: 2-3 bullet points starting with "• " '
          '— specific things SHE did that you should notice (a '
          'tease back, a fast reply, a personal disclosure, '
          'matching your tone, etc).\n\n'
          '  ❌ WHAT YOU NEED TO AVOID: 2-3 bullets — specific '
          'misfires in your last 2-3 messages OR specific traps '
          'in the moment ("don\'t go full sincere", "don\'t '
          'dodge the flirt", "don\'t over-text"). One line each.\n\n'
          '  🎯 BEST NEXT MOVE: 1-2 sentences naming the angle. '
          'Not the line — the angle. ("Lean in confidently with '
          'cocky humor, not sincerity, to keep her guessing.")\n\n'
          '  ✨ WHAT YOU DID WELL: one short sentence calling out '
          'your strongest play in the last 2-3 messages.\n\n'
          '  💡 SEND THIS: ONE line in double quotes that executes '
          'the BEST NEXT MOVE. Specific to her last bubble. Chat '
          'abbreviations (wbu, wyd, ngl) are PLAIN ENGLISH, not '
          'codes. No magician/Eiffel/pickup-line cliches.\n\n'
          'IF PROFILE PAGE: read her archetype + visible interests '
          '+ emotional vibe based on her bio + prompt answers + '
          'photo choices. Output these sections, IN THIS ORDER, '
          'with the exact emoji headers:\n\n'
          '  👤 WHO SHE IS: 2-3 sentences on her archetype, vibe, '
          'and what she\'s projecting. Be specific — "she\'s '
          'leaning into the chaotic-good art girl archetype, '
          'overshares emotionally early, wants to be SEEN as '
          'interesting." Not "she seems nice."\n\n'
          '  💭 WHAT SHE\'S INTO: 3-4 bullets starting with "• " '
          '— specific interests visible in her bio / photos / '
          'prompts. Quote the prompt answers where useful.\n\n'
          '  🎣 HOOKS: 2-3 bullets — specific things you can lean '
          'on (a prompt, a photo, a hobby). For each, one line on '
          'the angle you\'d use.\n\n'
          '  💡 THREE OPENERS: exactly 3 distinct opener options, '
          'each in double quotes, each referencing something '
          'specific she wrote or pictured. Different angles '
          '(observation / tease / future-frame). No magician/'
          'Eiffel/pickup-line cliches. No "hi beautiful" or '
          '"hey gorgeous". No body-part compliments.\n\n'
          'IF JUST A PHOTO: she shared (or I found) a single image '
          'of her — no bio, no chat history. Read every VISUAL '
          'signal you can see: outfit choices, setting, body '
          'language, vibe, style, the energy she\'s projecting. '
          'Output these sections, IN THIS ORDER, with the exact '
          'emoji headers:\n\n'
          '  👁️ WHAT THE PHOTO SAYS: 2-3 sentences on the energy '
          'she\'s projecting. Style read, setting, posture, what '
          'kind of person she\'s showing she is. Be specific — '
          '"black turtleneck + library shelves + half-smile = she '
          'wants to read as intentional and a little intimidating, '
          'not bubbly." Not "she looks nice."\n\n'
          '  🎣 VISUAL HOOKS: 2-3 bullets — concrete things in the '
          'photo you can lean on (the outfit choice, the location, '
          'an accessory, a coffee cup, a vinyl on the shelf, the '
          'lighting, a tattoo). For each, one line on the angle '
          'you\'d use.\n\n'
          '  💡 THREE OPENERS: exactly 3 distinct opener options, '
          'each in double quotes, each referencing something '
          'specific you can SEE in the photo. Different angles '
          '(observation / tease / archetype-call). No "you\'re '
          'gorgeous", no "you\'re beautiful", no body-part '
          'compliments. The reference must be SPECIFIC enough '
          'that a different girl with a different photo couldn\'t '
          'receive the same line.\n\n'
          'IMPORTANT formatting rules for ALL THREE modes:\n'
          '  - Use the emoji headers exactly as shown.\n'
          '  - Lines in double quotes are the ones the user will '
          'copy + send — make every one tight, specific, sound '
          'like a 22-year-old who knows what he\'s doing.\n'
          '  - Be honest, not brutal. Don\'t be a corporate dating '
          'coach. The user wants real game, not a self-help PDF.';
      if (effective.isEmpty) {
        effective = coachWrapper;
      } else {
        effective = '$effective\n\n$coachWrapper';
      }
    } else if (iterating) {
      // v265 — text-only iteration after a prior image upload (preset
      // tap, transform chip tap, free-text input). Wrap the user's
      // message so the model knows to deliver JUST the next reply,
      // not re-explain the analysis it already gave. Wing AI's
      // pattern: analyze once, iterate replies on demand.
      effective = '$effective\n\n(Iterating on the prior analysis. '
                  'No re-breakdown. Just deliver ONE new suggestion '
                  'line in double quotes plus one short sentence of '
                  'context — that\'s it.)';
    }
    final reply = await _ask(effective, image: image);
    // Day stamp for the Ascend RIZZ CHAT mission + the daily streak — a
    // coached exchange counts as showing up today.
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setInt(
          'rizz_chat_done_ymd', now.year * 10000 + now.month * 100 + now.day);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _msgs.add(_RizzMsg('assistant', reply));
      _sending = false;
    });
    _scrollToBottom();
  }

  /// Label the OCR transcript with alternating HER:/ME: tags from
  /// the bottom up. Kept as a DEAD-CODE FALLBACK — we now ship the
  /// screenshot directly to gpt-4o-vision instead, so this isn't
  /// called in the live path. Leaving it lets us revert to the OCR
  /// route in a single flag if the vision route ever breaks.
  // ignore: unused_element
  String _labelTranscript(String raw) {
    final lines = raw
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return raw.trim();
    final labeled = <String>[];
    var isHer = true;
    for (var i = lines.length - 1; i >= 0; i--) {
      labeled.insert(0, '${isHer ? "HER" : "ME"}: ${lines[i]}');
      isHer = !isHer;
    }
    return labeled.join('\n');
  }

  /// On-device OCR — DEAD-CODE FALLBACK now that the live path is
  /// vision (the backend reads the screenshot directly via
  /// gpt-4o-vision). Kept in tree so a single flag flip can revert
  /// to the OCR route if vision breaks.
  // ignore: unused_element
  Future<String> _ocr(Uint8List bytes) async {
    _dbg('ocr start bytes=${bytes.length}');
    final text = await ScreenshotOcrService.extractFromBytes(bytes);
    _dbg('ocr returned ${text.length} chars '
        'sample="${text.length > 60 ? "${text.substring(0, 60)}…" : text}"');
    return text;
  }

  Future<String> _ask(String text, {Uint8List? image}) async {
    // Strip the UI welcome bubble, send raw user turns. The RIZZ
    // system prompt + banned-phrase list live SERVER-SIDE on the
    // /rizz/chat route, so no client-side jailbreak preamble is
    // needed.
    //
    // BUGFIX — image upload was sending "(screenshot)" as the user
    // content instead of the OCR-enriched [text] from the caller.
    // The history loop now overrides the LAST user turn with the
    // effective text we just built (which contains the OCR if there
    // was an image). That's why the chat went silent on screenshot
    // uploads: the AI never saw the chat text we extracted.
    final history = <Map<String, dynamic>>[];
    var sawLast = false;
    for (var i = _msgs.length - 1; i >= 0; i--) {
      final m = _msgs[i];
      if (m.role != 'user') continue;
      if (!sawLast) {
        history.insert(0, {'role': 'user', 'content': text});
        sawLast = true;
      } else {
        history.insert(0, {'role': 'user', 'content': m.text});
      }
    }
    // No user messages yet → seed with the effective text.
    if (history.isEmpty) {
      history.add({'role': 'user', 'content': text});
    }
    // Mirrorly backend's dedicated /rizz/chat endpoint. Separate from
    // /chat (the face doctor) — uses the RIZZ system prompt + gpt-4o
    // with the BANNED PHRASES list baked in server-side, so no client
    // preamble jailbreak required.
    try {
      _dbg('POST /rizz/chat with ${history.length} msgs');
      final res = await http
          .post(
            Uri.parse('${ApiConfig.backendBaseUrl}/rizz/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'messages': history,
              if (image != null) 'imageBase64': base64Encode(image),
            }),
          )
          .timeout(const Duration(seconds: 45));
      _dbg('status=${res.statusCode}');
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final reply = (body['reply'] as String?)?.trim() ?? '';
        _dbg('reply len=${reply.length}');
        if (reply.isNotEmpty) return reply;
        _dbg('empty reply field');
      } else {
        _dbg('non-200 body="${res.body.length > 200 ? "${res.body.substring(0, 200)}…" : res.body}"');
      }
    } catch (e) {
      _dbg('threw $e');
    }
    return 'Try rephrasing — backend gave me nothing usable.';
  }

  /// Per-instance debug log. Same idea as RizzDebug but scoped to
  /// this chat screen so multi-turn convos accumulate context.
  final List<String> _debugLog = [];
  void _dbg(String line) {
    final stamp = DateTime.now().toIso8601String().substring(11, 23);
    final entry = '[$stamp] $line';
    _debugLog.add(entry);
    print('[RIZZ-CHAT] $entry');
    if (mounted) setState(() {});
  }

  Future<void> _attach(ImageSource source) async {
    HapticFeedback.selectionClick();
    // v265 — the silent catch was eating real failures (iOS Limited
    // Photos permission, picker init crashes, file-read 0-byte
    // returns), so users tapping + would get nothing back with no
    // indication WHY. Now every failure point is logged AND a
    // snackbar surfaces the cause inline so bro can see exactly
    // what happened.
    try {
      _dbg('picker source=${source.name} — opening…');
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, maxWidth: 1600);
      if (picked == null) {
        _dbg('picker returned null — user cancelled or no image');
        return;
      }
      if (!mounted) return;
      _dbg('picker returned path=${picked.path}');
      final file = File(picked.path);
      if (!await file.exists()) {
        _dbg('picked file does not exist on disk');
        _snack('Couldn\'t read the photo — try again.');
        return;
      }
      final bytes = await file.readAsBytes();
      _dbg('read ${bytes.length} bytes from picked file');
      if (bytes.isEmpty) {
        _snack('That photo came back empty — pick another.');
        return;
      }
      if (!mounted) return;
      await _send(_ctrl.text, image: bytes);
    } catch (e, st) {
      _dbg('picker / attach THREW: ${e.runtimeType} — $e');
      _dbg('stack first frame: ${st.toString().split('\n').first}');
      if (!mounted) return;
      _snack('Photo upload failed: $e');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
        style: GoogleFonts.inter(
          color: Colors.white, fontSize: 13.5,
          fontWeight: FontWeight.w600,
        )),
      backgroundColor: AppColors.red,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  void _showAttachSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Container(
              width: 38, height: 4,
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 16),
            _AttachRow(
              icon: Icons.photo_library_outlined,
              label: 'CHOOSE FROM GALLERY',
              onTap: () { Navigator.of(ctx).pop(); _attach(ImageSource.gallery); },
            ),
            const SizedBox(height: 8),
            _AttachRow(
              icon: Icons.camera_alt_outlined,
              label: 'TAKE A NEW PHOTO',
              onTap: () { Navigator.of(ctx).pop(); _attach(ImageSource.camera); },
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }

  /// Open the tone picker. Same five rows as the rizz reply screen.
  /// Switching tone fires a transform turn so the AI rewrites its
  /// last suggestion in the new register without the user having to
  /// re-type the question.
  Future<void> _openTonePicker() async {
    HapticFeedback.selectionClick();
    final picked = await showModalBottomSheet<RizzVibe>(
      context: context,
      backgroundColor: Colors.transparent,
      // Same scrollable fix as the screenshot screen — lift the
      // default height cap so all five tone rows are reachable.
      isScrollControlled: true,
      builder: (_) => _ChatTonePickerSheet(current: _tone),
    );
    if (picked == null || picked == _tone || !mounted) return;
    setState(() => _tone = picked);
    // If there's an existing AI reply, ask it to rewrite in the new
    // tone. Otherwise wait for the user's next turn.
    if (_msgs.length > 1 && !_sending) {
      await _send('Switch to ${picked.label} tone — rewrite your '
          'last suggestion in that register.');
    }
  }

  /// Quick-action chip handler — sends a transform turn so the AI
  /// rewrites its last suggestion with the requested flavor. Matches
  /// the screenshot screen's _ScenarioStrip behavior.
  Future<void> _useChatScenario(String scenario) async {
    if (_sending) return;
    HapticFeedback.selectionClick();
    await _send('Rewrite your last suggestion: $scenario');
  }

  @override
  Widget build(BuildContext context) {
    final fresh         = _msgs.length == 1;
    // Show the transform chips + tone pill the moment an assistant
    // reply has landed (i.e. not on the welcome bubble alone). They
    // hide while a request is in flight to avoid double-fires.
    final hasReply      = _msgs.length > 1 && !_sending;
    final lastIsAssist  = _msgs.last.role == 'assistant';
    final showTransform = hasReply && lastIsAssist;

    return Scaffold(
      backgroundColor: AppColors.base,
      // Tap anywhere outside the input to dismiss the keyboard.
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: Column(
            children: [
              _Header(onBack: () => Navigator.of(context).maybePop()),
              Expanded(
                child: ListView.separated(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  itemCount: _msgs.length + (_sending ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (_, i) {
                    if (i == _msgs.length) return const _TypingBubble();
                    return _ChatBubble(msg: _msgs[i]);
                  },
                ),
              ),
              // ── FRESH STATE: situation primers (Flirty first message
              //   / Ask her out / etc). Mirrors the rizz reply screen's
              //   "what's the situation" entry.
              if (fresh) ...[
                _PresetStrip(
                  presets: _presets,
                  // v275 — chip label is short (clean bubble), the
                  // FULL prompt rides as apiText to the backend so
                  // the AI delivers a direct line instead of asking
                  // for context.
                  onPick: (label) {
                    final full = _presetPrompts[label] ?? label;
                    _send(label, apiText: full);
                  },
                ),
                const SizedBox(height: 10),
              ],
              // ── POST-REPLY STATE: the transform chips that take the
              //   last suggestion and add a flavor (More heat, Funnier,
              //   Make a move, etc). Same chip set as the screenshot
              //   screen's _ScenarioStrip.
              if (showTransform) ...[
                // ── Transform chip strip — horizontal scroll of the
                //   "More heat / Flirty tease / Make a move / ..."
                //   actions that reshape the last AI suggestion.
                _ChatTransformStrip(
                  onTap: _useChatScenario,
                  disabled: _sending,
                ),
                const SizedBox(height: 8),
              ],
              // Debug pane commented out — flip back on by uncommenting
              // when something next stops working.
              // if (_debugLog.isNotEmpty)
              //   _ChatDebugPane(entries: _debugLog),
              // ── Input bar with the tone pill BUILT IN on the left.
              //   Bro v3: "this is a professional app not a clown show."
              //   Mirrors WingAI's pattern — one clean row carries
              //   attach + tone selector + text input + send. No more
              //   centered floating pill above the input.
              _InputBar(
                controller: _ctrl,
                sending:    _sending,
                tone:       _tone,
                onTone:     _sending ? null : _openTonePicker,
                onSend:     () => _send(_ctrl.text),
                onAttach:   _showAttachSheet,
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// In-screen debug strip — collapsed by default, tap to expand the
/// full trail of POST status codes and parsed reply lengths so we
/// can SEE what's coming back from the backend without scrolling
/// Xcode console.
class _ChatDebugPane extends StatefulWidget {
  final List<String> entries;
  const _ChatDebugPane({required this.entries});
  @override
  State<_ChatDebugPane> createState() => _ChatDebugPaneState();
}

class _ChatDebugPaneState extends State<_ChatDebugPane> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.red.withValues(alpha: 0.35), width: 0.6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => setState(() => _open = !_open),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Icon(_open
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      color: AppColors.red, size: 14),
                  const SizedBox(width: 2),
                  Text('DEBUG · ${widget.entries.length}',
                    style: GoogleFonts.inter(
                      color: AppColors.red,
                      fontSize: 9.5, letterSpacing: 2.0,
                      fontWeight: FontWeight.w800,
                    )),
                  const Spacer(),
                  if (widget.entries.isNotEmpty)
                    Text(widget.entries.last.length > 60
                            ? '${widget.entries.last.substring(0, 60)}…'
                            : widget.entries.last,
                      style: GoogleFonts.firaCode(
                        color: AppColors.textTertiary,
                        fontSize: 9,
                      )),
                ],
              ),
            ),
            if (_open) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in widget.entries.reversed)
                        Text(e,
                          style: GoogleFonts.firaCode(
                            color: AppColors.textSecondary,
                            fontSize: 9.5, height: 1.35,
                          )),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  const _Header({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 18),
          ),
          const SizedBox(width: 2),
          // v300 — wordmark replaces the old "IMHIM" pill so the
          // brand reads at full weight in any chat screenshot the
          // user posts. Same italic Playfair lockup as every other
          // Rizz surface.
          const ImHimWordmark(fontSize: 22, letterSpacing: -0.5),
          const Spacer(),
          Container(
            width: 8, height: 8,
            decoration: const BoxDecoration(
              color: AppColors.signalGreen,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text('LIVE',
            style: GoogleFonts.inter(
              color: AppColors.signalGreen,
              fontSize: 10, letterSpacing: 2.4,
              fontWeight: FontWeight.w800,
            )),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final _RizzMsg msg;
  const _ChatBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    // v274 — AI replies render LOOSE on the background. No card,
    // no border, no avatar icon — the prose fills the available
    // width and reads like a coach typing on a clean page. Quoted
    // lines still extract into their own SEND THIS copy-cards
    // underneath (the rizz lines, not the analysis prose, get
    // the card treatment). User messages keep the red-card-on-the-
    // right bubble + image attachment shape unchanged. Bro: "the
    // ai text never fuking comes in the card."
    if (!isUser) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (msg.text.trim().isNotEmpty)
            SelectableText(msg.text,
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 15.5, height: 1.5,
                fontWeight: FontWeight.w500,
              )),
          ..._extractCopyableLines(context),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.74,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (msg.image != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: Image.memory(msg.image!,
                          fit: BoxFit.contain),
                    ),
                  ),
                  if (msg.text != '(screenshot)') const SizedBox(height: 6),
                ],
                if (msg.text != '(screenshot)' || msg.image == null)
                  _userBubble(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _userBubble() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.red,
        borderRadius: const BorderRadius.only(
          topLeft:     Radius.circular(20),
          topRight:    Radius.circular(20),
          bottomLeft:  Radius.circular(20),
          bottomRight: Radius.circular(4),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withValues(alpha: 0.3),
            blurRadius: 16, spreadRadius: 0,
          ),
        ],
      ),
      child: SelectableText(msg.text,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 15, height: 1.42,
          fontWeight: FontWeight.w500,
        )),
    );
  }

  /// Pull quoted strings out of the assistant's reply ("...") and
  /// render each as its own SEND THIS card under the bubble. Lets
  /// the user tap-to-copy the line the AI told them to send instead
  /// of having to long-press-select inside the chat bubble.
  List<Widget> _extractCopyableLines(BuildContext context) {
    final out = <Widget>[];
    final matches = RegExp(r'"([^"\n]{6,160})"').allMatches(msg.text);
    final seen = <String>{};
    for (final m in matches) {
      final line = (m.group(1) ?? '').trim();
      if (line.length < 6 || seen.contains(line)) continue;
      seen.add(line);
      out.add(const SizedBox(height: 6));
      out.add(_SendThisCard(line: line));
      if (out.length > 8) break; // cap at 4 lines (each adds 2 widgets)
    }
    return out;
  }
}

class _SendThisCard extends StatelessWidget {
  final String line;
  const _SendThisCard({required this.line});

  Future<void> _copy(BuildContext context) async {
    HapticFeedback.mediumImpact();
    await Clipboard.setData(ClipboardData(text: line));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Copied. Send it.',
        style: GoogleFonts.inter(
          color: Colors.white, fontSize: 14,
          fontWeight: FontWeight.w600, letterSpacing: 0.3,
        )),
      backgroundColor: AppColors.red,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _copy(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            color: AppColors.red.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.55),
              width: 0.8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text('"$line"',
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 14, height: 1.35,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                  )),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.red,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.copy_rounded,
                        color: Colors.white, size: 11),
                    const SizedBox(width: 4),
                    Text('SEND THIS',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 9, letterSpacing: 1.6,
                        fontWeight: FontWeight.w900,
                      )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: AppColors.red,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.red.withValues(alpha: 0.3),
                blurRadius: 10, spreadRadius: 0,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.auto_awesome_rounded,
              color: Colors.white, size: 16),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: const BorderRadius.only(
              topLeft:     Radius.circular(20),
              topRight:    Radius.circular(20),
              bottomLeft:  Radius.circular(4),
              bottomRight: Radius.circular(20),
            ),
            border: Border.all(color: AppColors.surface3, width: 0.6),
          ),
          child: const SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.8, color: AppColors.red),
          ),
        ),
      ],
    );
  }
}

class _PresetStrip extends StatelessWidget {
  final List<String> presets;
  final ValueChanged<String> onPick;
  const _PresetStrip({required this.presets, required this.onPick});

  @override
  Widget build(BuildContext context) {
    // v274 — back to a SIDEWAYS horizontal scroll strip directly
    // above the input bar (the original placement). Bro: "put the
    // beginning presets back to wat they was and where they fuking
    // was — sideways like before." Wrap (v273) went downwards;
    // restored ListView goes sideways. All 9 chips still in the
    // list — they just scroll horizontally instead of wrapping.
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final p in presets)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _PresetChip(label: p, onTap: () => onPick(p)),
            ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PresetChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.4), width: 0.8),
          ),
          alignment: Alignment.center,
          child: Text(label,
            style: GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontSize: 13, height: 1,
              fontWeight: FontWeight.w600,
            )),
        ),
      ),
    );
  }
}

class _AttachRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _AttachRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.red.withValues(alpha: 0.32), width: 0.8),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.red, size: 20),
                const SizedBox(width: 14),
                Text(label,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 13, letterSpacing: 2.4,
                    fontWeight: FontWeight.w800,
                  )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final RizzVibe tone;
  /// Null when the tone selector should be disabled (mid-send) — we
  /// still render it so the user can SEE the current tone, but the
  /// tap is a no-op.
  final VoidCallback? onTone;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.tone,
    required this.onTone,
    required this.onSend,
    required this.onAttach,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      // v274 — INPUT ROW LEADS, tone pill BELOW. Bro: "put the
      // dropdown with flirty etc under the fuking text tab." Tap
      // the pill → showModalBottomSheet slides up from the bottom
      // edge (natural iOS pattern, so "opens upwards" is intrinsic).
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
            decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: AppColors.surface3, width: 0.6),
            ),
            child: Row(
              children: [
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: onAttach,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 38, height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.surface3, width: 0.8),
                      ),
                      child: const Icon(
                          Icons.add_photo_alternate_outlined,
                          color: Colors.white, size: 19),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onSubmitted: (_) => onSend(),
                    maxLines: 1,
                    cursorColor: AppColors.red,
                    style: GoogleFonts.inter(
                      color: AppColors.textPrimary,
                      fontSize: 15, height: 1.3,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Ask anything…',
                      hintStyle: GoogleFonts.inter(
                        color: AppColors.textTertiary,
                        fontSize: 15, height: 1.3,
                        fontWeight: FontWeight.w400,
                      ),
                      border:           InputBorder.none,
                      enabledBorder:    InputBorder.none,
                      focusedBorder:    InputBorder.none,
                      contentPadding:   const EdgeInsets.symmetric(vertical: 12),
                      isDense:          true,
                    ),
                  ),
                ),
                Material(
                  color: AppColors.red,
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: sending ? null : onSend,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 40, height: 40,
                      alignment: Alignment.center,
                      child: sending
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.arrow_upward_rounded,
                              color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 0, 0),
            child: Row(
              children: [
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                  child: InkWell(
                    onTap: onTone,
                    borderRadius: BorderRadius.circular(99),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface1,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: AppColors.red.withValues(alpha: 0.55),
                          width: 0.9),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(tone.emoji,
                            style: const TextStyle(fontSize: 14, height: 1)),
                          const SizedBox(width: 6),
                          Text(tone.label,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 12.5, height: 1,
                              letterSpacing: 0.4,
                              fontWeight: FontWeight.w800,
                            )),
                          const SizedBox(width: 3),
                          const Icon(Icons.keyboard_arrow_up_rounded,
                            color: AppColors.textSecondary, size: 15),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  TONE PILL · TRANSFORM CHIPS · PICKER SHEET — chat surface mirror of
//  the rizz reply screen. Bro: "make the chat with mirrorly look and
//  work like wat you've done with the screenshot one. but the chat one
//  had extra little prompts" — kept the existing _PresetStrip on the
//  fresh state for those primers, and added these three widgets to
//  carry the tone + transform UX after a reply lands.
// ═══════════════════════════════════════════════════════════════════════

// _ChatTonePill removed in v157 — the tone pill is now rendered
// INLINE inside _InputBar, between the attach button and the text
// field, matching WingAI's clean single-row pattern.

class _ChatTonePickerSheet extends StatelessWidget {
  final RizzVibe current;
  const _ChatTonePickerSheet({required this.current});

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    return Container(
      constraints: BoxConstraints(maxHeight: screenH * 0.78),
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 38, height: 4,
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text('SELECT TONE',
                    style: GoogleFonts.inter(
                      color: AppColors.red,
                      fontSize: 12, letterSpacing: 3.0,
                      fontWeight: FontWeight.w800,
                    )),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                      color: AppColors.textSecondary, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final v in RizzVibeLabel.canonical) ...[
                      _ChatTonePickerRow(
                        tone:     v,
                        selected: v == current,
                        onTap:    () => Navigator.of(context).pop(v),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatTonePickerRow extends StatelessWidget {
  final RizzVibe     tone;
  final bool         selected;
  final VoidCallback onTap;
  const _ChatTonePickerRow({
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final border = selected ? AppColors.red : AppColors.surface3;
    return Material(
      color: selected
          ? AppColors.red.withValues(alpha: 0.10)
          : AppColors.surface1,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: selected ? 1.2 : 0.6),
          ),
          child: Row(
            children: [
              Text(tone.emoji,
                style: const TextStyle(fontSize: 22, height: 1)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tone.label,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 16, height: 1.2,
                        letterSpacing: -0.2,
                        fontWeight: FontWeight.w900,
                      )),
                    const SizedBox(height: 3),
                    Text(tone.blurb,
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 12.5, height: 1.35,
                        fontWeight: FontWeight.w500,
                      )),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? AppColors.red : AppColors.textTertiary,
                    width: 1.6),
                ),
                alignment: Alignment.center,
                child: selected
                    ? Container(
                        width: 11, height: 11,
                        decoration: const BoxDecoration(
                          color: AppColors.red,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal transform-chip strip — identical chip set to the
/// screenshot screen so the two surfaces feel like one product. Each
/// chip sends a rewrite turn to the AI rather than starting a new
/// conversation, so the previous suggestion is reshaped in place.
class _ChatTransformStrip extends StatelessWidget {
  final Future<void> Function(String scenario) onTap;
  final bool disabled;
  const _ChatTransformStrip({required this.onTap, required this.disabled});

  static const _chips = <({String label, String emoji, String scenario})>[
    // v275 — the "What went wrong" and "Read her profile" coach
    // transforms were dropped. Bro: "the AI does that when you send
    // a screenshot." Right — the dual-mode wrapper now auto-runs
    // both the WHAT FELL FLAT diagnostic (CHAT mode) and the WHO SHE
    // IS profile read (PROFILE mode) on every fresh image, so these
    // chips were duplicating work the cold path already does. The
    // remaining 8 tone-shift chips iterate on tone, which the
    // wrapper does NOT auto-handle, so they earn their slot.
    (label: 'More heat',     emoji: '🔥', scenario: 'turn up the heat — push every line one notch hotter, more cinematic, more suggestive. Keep the structure, raise the temperature.'),
    (label: 'Flirty tease',  emoji: '😏', scenario: 'flirty tease — push-pull, light needle. Cheeky but warm. Keeps the conversation moving.'),
    (label: 'Make a move',   emoji: '🎯', scenario: 'make a move — pivot toward a specific, confident date proposal without sounding pushy.'),
    (label: 'Funnier',       emoji: '😂', scenario: 'funnier — keep the situation, add comedy. Screenshot-to-group-chat funny. Self-aware over earnest.'),
    (label: 'Be playful',    emoji: '😜', scenario: 'be playful — light, cheeky, low-stakes. Drop the heavy moves.'),
    (label: 'Be bolder',     emoji: '⚡️', scenario: 'be bolder — high-agency, declarative, scarce. Frame the outcome as already decided.'),
    (label: 'Sexier',        emoji: '💋', scenario: 'sexier — slow-burn sensual, suggestive without spilling. Eye-contact energy.'),
    (label: 'Keep it light', emoji: '🟡', scenario: 'keep it light and easy — no heavy moves, low-stakes charm. Friendly with a hint of flirt.'),
  ];

  @override
  Widget build(BuildContext context) {
    // v274 — back to SIDEWAYS horizontal scroll. Same restore as
    // _PresetStrip — Wrap (v273) was wrong, Wing-AI / our previous
    // chat both used a horizontal strip directly above the input.
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = _chips[i];
          return Material(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(100),
            child: InkWell(
              onTap: disabled ? null : () => onTap(c.scenario),
              borderRadius: BorderRadius.circular(100),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                      color: AppColors.surface3, width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(c.emoji,
                      style: const TextStyle(fontSize: 14, height: 1)),
                    const SizedBox(width: 7),
                    Text(c.label,
                      style: GoogleFonts.inter(
                        color: disabled
                            ? AppColors.textTertiary
                            : Colors.white,
                        fontSize: 13, height: 1,
                        letterSpacing: 0.1,
                        fontWeight: FontWeight.w700,
                      )),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
