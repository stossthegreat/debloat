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

  Future<String> _ask(String text, {Uint8List? image}) async {
    // Strip the UI welcome bubble, send raw user turns. The RIZZ
    // system prompt + banned-phrase list live SERVER-SIDE on the
    // /rizz/chat route, so no client-side jailbreak preamble is
    // needed.
    final history = <Map<String, dynamic>>[];
    for (final m in _msgs) {
      if (m.role != 'user') continue;
      history.add({'role': 'user', 'content': m.text});
    }
    if (history.isEmpty || history.last['content'] != text) {
      // The send() flow already appended the user message before
      // calling _ask, but be defensive.
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
              // Debug pane commented out — flip back on by uncommenting
              // when something next stops working.
              // if (_debugLog.isNotEmpty)
              //   _ChatDebugPane(entries: _debugLog),
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
