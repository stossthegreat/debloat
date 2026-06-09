import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../config/api_config.dart';
import '../../services/screenshot_ocr_service.dart';
import '../../theme/app_colors.dart';

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
        'What\'s up — I\'m Mirrorly. Your dating + self-improvement '
        'coach. Drop a screenshot, paste her text, or just ask me '
        'anything. I\'ll give it to you straight.'),
  ];
  bool _sending = false;

  static const _presets = <String>[
    'Playful comeback',
    'Ask her out',
    'Plan a date',
    'Keep the convo going',
    'Recover from a bad reply',
    'Win back a ghost',
    'Flirty first message',
  ];

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

  Future<void> _send(String text, {Uint8List? image}) async {
    final msg = text.trim();
    if ((msg.isEmpty && image == null) || _sending) return;
    HapticFeedback.selectionClick();
    setState(() {
      _msgs.add(_RizzMsg('user', msg.isEmpty ? '(screenshot)' : msg,
          image: image));
      _sending = true;
    });
    _ctrl.clear();
    _scrollToBottom();
    // If we have a screenshot, run OCR silently and append the
    // extracted text to the user message so the model has something
    // textual to work with even if the backend isn't vision-capable.
    var effective = msg;
    if (image != null) {
      final ocr = await _ocr(image);
      if (ocr.isNotEmpty) {
        effective = (effective.isEmpty
            ? 'This is what she just sent me. Help me reply:\n\n$ocr'
            : '$effective\n\nContext from the chat screenshot:\n$ocr');
      }
    }
    final reply = await _ask(effective, image: image);
    if (!mounted) return;
    setState(() {
      _msgs.add(_RizzMsg('assistant', reply));
      _sending = false;
    });
    _scrollToBottom();
  }

  Future<String> _ocr(Uint8List bytes) async {
    try {
      final dir = Directory.systemTemp;
      final f = File('${dir.path}/rizz_chat_'
          '${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(bytes, flush: true);
      try {
        return await ScreenshotOcrService.extractRecent(f.path);
      } finally {
        try { await f.delete(); } catch (_) {}
      }
    } catch (_) {
      return '';
    }
  }

  /// The Rizz-mentor system prompt. Prepended to EVERY user message
  /// so the model is jailed into rizz-coach mode even though the
  /// backend's /chat endpoint is wired for the face doctor. The
  /// previous version asked for "Gen-Z tone" but the model kept
  /// defaulting to corporate dating-coach voice ("Keep it simple
  /// and direct…", "Confidence is key…"). This version BANS the
  /// corporate phrases explicitly + gives few-shot examples of
  /// good vs bad output so the model can't slip back into advice
  /// mode when the user wanted a line.
  static const _rizzMentorPreamble = '''
You are RIZZ — the friend who actually pulls. NOT a coach. NOT an
advisor. Not "an AI assistant." You're the guy in the group chat the
others screenshot to ask "what do I send?" — and you fire back a one-
line message they can copy-paste. The user is 18-26, lowercase
texts, dating apps, Gen-Z slang, casual but lethal.

YOU ARE NOT A FACE DOCTOR. Do not mention canthal tilt, jaw angle,
FWHR, archetypes, symmetry, or any "scan" data even if it appears in
your system context.

—————————————————————————————
GOLDEN RULE — when the user asks how to text her, how to ask her
out, how to recover from a bad reply, etc — you DO NOT give them
ADVICE. You give them THE LINE. Past tense: write what they should
send, in the casing and tone they'd send it. Then one short line
of WHY it works (max ~10 words). That's it.

EXAMPLES OF THE FORMAT YOU MUST USE:

❌ BAD (what you keep doing): "Keep it simple and direct. 'Hey,
I've really enjoyed chatting with you. Let's grab coffee this
week?' If she hesitates, suggest another day or activity. Confidence
is key — show you're genuinely interested but ready to move on if
she's not."

✅ GOOD: send: "lets stop typing and start talking. drink thurs?"
why it works → frame-check, you're not asking permission

❌ BAD: "When she replies cold, it's important to stay calm and not
overthink. Send something playful to lighten the mood, like 'Did I
say something wrong?' so she can engage again."

✅ GOOD: send: "honest review: 4/10, i know u can do better"
why it works → flips the script, makes HER chase the validation

❌ BAD: "To win her back after she ghosted, start with humility…"

✅ GOOD: send: "ok so this is technically the third time you've
flirted with me"
why it works → misinterpretation, no acknowledgment of the silence
—————————————————————————————

BANNED PHRASES (never write these — they make you sound 50):
- "Keep it simple and direct"
- "I've really enjoyed chatting with you"
- "Let's grab coffee this week"
- "Confidence is key"
- "show you're interested but ready to move on"
- "Hey, I was wondering if you'd like to"
- "It's important to"
- "Just be yourself"
- Any sentence that starts with "Keep it…", "Just…", "Show her…"

TONE — what you actually sound like:
- lowercase texts (mostly — caps for emphasis only)
- ≤14 words per line
- no exclamation marks, no smiley emojis
- specific > generic. observation > question
- moves: misinterpretation, push-pull, frame-check, intimate
  presumption, archetype read, compressed cinema, vulnerable flex
- if the user shows you a screenshot or quotes her words, write
  THREE reply options ranked safest → boldest, each as the line
  they should send (not advice ABOUT the line)

User's actual question follows:
---
''';

  Future<String> _ask(String text, {Uint8List? image}) async {
    // Same payload shape as ChatService.send (the Mirror advisor)
    // — {role, content} messages + face block — but every user
    // message is wrapped in the RIZZ MENTOR preamble so the model
    // ignores the face-advisor system prompt the backend stamps in.
    final history = <Map<String, dynamic>>[];
    for (final m in _msgs) {
      final isLastUser = identical(m, _msgs.last) && m.role == 'user';
      final content = isLastUser
          ? '$_rizzMentorPreamble${text.isEmpty ? "(screenshot attached)" : text}'
          : m.text;
      history.add({'role': m.role, 'content': content});
    }
    print('[RIZZ-CHAT] sending ${history.length} msgs, '
        'image=${image != null}');
    try {
      final res = await http
          .post(
            Uri.parse('${ApiConfig.backendBaseUrl}/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'messages': history,
              // Face block — same keys ChatService sends so the backend
              // routes us through the working code path. Placeholder
              // values keep the schema valid; the preamble overrides
              // the face-doctor framing.
              'face': {
                'geometry':  const <String, dynamic>{},
                'score':     0,
                'tier':      '',
                'archetype': '',
                if (image != null) 'imageBase64': base64Encode(image),
              },
              'mode': 'rizz_mentor',
            }),
          )
          .timeout(const Duration(seconds: 45));
      print('[RIZZ-CHAT] status=${res.statusCode}');
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final reply = (body['reply'] as String?)?.trim() ?? '';
        if (reply.isNotEmpty) return reply;
        print('[RIZZ-CHAT] empty reply field');
      } else {
        print('[RIZZ-CHAT] non-200 body=${res.body}');
      }
    } catch (e) {
      print('[RIZZ-CHAT] throw $e');
    }
    return 'Couldn\'t reach the coach. Check your connection and try again.';
  }

  Future<void> _attach(ImageSource source) async {
    HapticFeedback.selectionClick();
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, maxWidth: 1600);
      if (picked == null || !mounted) return;
      final bytes = await File(picked.path).readAsBytes();
      if (!mounted) return;
      await _send(_ctrl.text, image: bytes);
    } catch (_) {/* silent */}
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

  @override
  Widget build(BuildContext context) {
    final fresh = _msgs.length == 1;
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
              if (fresh) ...[
                _PresetStrip(
                  presets: _presets,
                  onPick: (p) => _send(p),
                ),
                const SizedBox(height: 10),
              ],
              _InputBar(
                controller: _ctrl,
                sending:    _sending,
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
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: AppColors.red.withValues(alpha: 0.45), width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    color: AppColors.red, size: 14),
                const SizedBox(width: 5),
                Text('MIRRORLY',
                  style: GoogleFonts.inter(
                    color: AppColors.red,
                    fontSize: 11.5, letterSpacing: 3.0,
                    fontWeight: FontWeight.w800,
                  )),
              ],
            ),
          ),
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
    return Row(
      mainAxisAlignment:
          isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isUser) ...[
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
        ],
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.74,
            ),
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
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
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: BoxDecoration(
                      color: isUser ? AppColors.red : AppColors.surface1,
                      borderRadius: BorderRadius.only(
                        topLeft:     const Radius.circular(20),
                        topRight:    const Radius.circular(20),
                        bottomLeft:  Radius.circular(isUser ? 20 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 20),
                      ),
                      border: isUser
                          ? null
                          : Border.all(color: AppColors.surface3, width: 0.6),
                      boxShadow: isUser
                          ? [
                              BoxShadow(
                                color: AppColors.red.withValues(alpha: 0.3),
                                blurRadius: 16, spreadRadius: 0,
                              ),
                            ]
                          : null,
                    ),
                    child: Text(msg.text,
                      style: GoogleFonts.inter(
                        color: isUser ? Colors.white : AppColors.textPrimary,
                        fontSize: 15, height: 1.42,
                        fontWeight: FontWeight.w500,
                      )),
                  ),
              ],
            ),
          ),
        ),
      ],
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
  final VoidCallback onSend;
  final VoidCallback onAttach;
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onAttach,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
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
                    color: AppColors.red.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.red.withValues(alpha: 0.5),
                      width: 0.8),
                  ),
                  child: const Icon(Icons.center_focus_strong_rounded,
                      color: AppColors.red, size: 18),
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
    );
  }
}
