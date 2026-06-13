import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../config/api_config.dart';
import '../../services/paywall_gate.dart';
import '../../services/rizz_reply_service.dart' show RizzVibe, RizzVibeLabel;
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
        'what\'s good. drop a screenshot of her chat, paste her last '
        'text, or just ask. i write the line you should send. tap any '
        'line in quotes to copy it.'),
  ];
  bool _sending = false;
  /// Active tone preset. Matches the rizz reply screen so picking
  /// SENSUAL / PLAYFUL / etc here behaves identically — the next
  /// user turn (or transform tap) routes through the chosen tone
  /// register. Default FLIRTY.
  RizzVibe _tone = RizzVibe.flirty;

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
    // If we have a screenshot, run OCR and frame the extracted text so
    // the AI treats the LAST line as what she just sent (the reply
    // target) and the rest as conversational context. Bro: "it's
    // completely off topic — needs to finish off the convo, specific
    // to the last thing said, using the rest as context."
    var effective = msg;
    if (image != null) {
      // Vision path — backend gpt-4o-vision reads the iMessage / Hinge
      // UI directly from the attached imageBase64. No OCR, no
      // transcript labeling. We just frame the request and pass the
      // image bytes through _ask. Bro: "the real fix is vision —
      // let's go." This is that path.
      _dbg('vision path — sending image bytes (${image.length}) to backend');
      if (effective.isEmpty) {
        effective = 'Here\'s a screenshot of my chat with her. Read it '
            'as a chat — messages on my side are mine, hers are hers, '
            'the most recent bubble on her side is what I need a reply '
            'for. Write me ONE line to send back, specific to her last '
            'message, continuing the convo naturally. Chat abbreviations '
            '(wbu, wyd, ngl, etc.) are plain English — not a code.';
      } else {
        effective = '$effective\n\n(I attached a chat screenshot — read '
            'it directly; her latest bubble is what to reply to.)';
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
                  onPick: (p) => _send(p),
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
                Text('IMHIM',
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
                  _bubble(context, isUser),
                // Extract any quoted lines from the assistant's reply
                // and render them as their own tap-to-copy cards so
                // the user doesn't have to long-press-select inside
                // the bubble.
                if (!isUser) ..._extractCopyableLines(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bubble(BuildContext context, bool isUser) {
    return Container(
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
      child: SelectableText(msg.text,
        style: GoogleFonts.inter(
          color: isUser ? Colors.white : AppColors.textPrimary,
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
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: AppColors.surface3, width: 0.6),
        ),
        child: Row(
          children: [
            // ── Attach (screenshot upload). Compact circle, same as
            //    before — but slightly tighter so the tone pill +
            //    text field both fit on the one row.
            Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onAttach,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 36, height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.red.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.red.withValues(alpha: 0.5),
                      width: 0.8),
                  ),
                  child: const Icon(Icons.center_focus_strong_rounded,
                      color: AppColors.red, size: 17),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // ── Tone pill — INLINE here, not on a separate row above.
            //    Bro: "this is a professional app not a clown show."
            //    Tap opens the same five-tone picker sheet.
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(99),
              child: InkWell(
                onTap: onTone,
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: AppColors.red.withValues(alpha: 0.55),
                      width: 0.9),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tone.emoji,
                        style: const TextStyle(fontSize: 13, height: 1)),
                      const SizedBox(width: 5),
                      Text(tone.label,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 12, height: 1,
                          letterSpacing: 0.2,
                          fontWeight: FontWeight.w800,
                        )),
                      const SizedBox(width: 2),
                      const Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textSecondary, size: 14),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
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
    (label: 'More heat',     emoji: '🔥', scenario: 'turn up the heat — push every line one notch hotter, more cinematic, more suggestive. Keep the structure, raise the temperature.'),
    (label: 'Flirty tease',  emoji: '😏', scenario: 'flirty tease — push-pull, light needle, make her chase. Cheeky but warm.'),
    (label: 'Make a move',   emoji: '🎯', scenario: 'make a move — pivot toward a specific, confident date proposal without sounding pushy.'),
    (label: 'Funnier',       emoji: '😂', scenario: 'funnier — keep the situation, add comedy. Screenshot-to-group-chat funny. Self-aware over earnest.'),
    (label: 'Be playful',    emoji: '😜', scenario: 'be playful — light, cheeky, low-stakes. Drop the heavy moves.'),
    (label: 'Be bolder',     emoji: '⚡️', scenario: 'be bolder — high-agency, declarative, scarce. Frame the outcome as already decided.'),
    (label: 'Sexier',        emoji: '💋', scenario: 'sexier — slow-burn sensual, suggestive without spilling. Eye-contact energy.'),
    (label: 'Keep it light', emoji: '🟡', scenario: 'keep it light and easy — no heavy moves, low-stakes charm. Friendly with a hint of flirt.'),
  ];

  @override
  Widget build(BuildContext context) {
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: AppColors.surface3, width: 0.8),
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
