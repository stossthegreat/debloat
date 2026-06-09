import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/rizz_reply_service.dart';
import '../../../theme/app_colors.dart';

/// Debug pane visibility — flip false before final shipping.
const _kRizzDebug = true;

/// RIZZ — clean, two-state generator.
///
/// INPUT STATE — no results yet:
///   · italic Playfair headline + back arrow
///   · single tap UPLOAD A SCREENSHOT pill (auto-fires on entry
///     when the screen was launched from the Rizz tab "Upload" card)
///   · "or type her message" expand → text field + GENERATE
///
/// RESULTS STATE — once the AI has spoken:
///   · screenshot rendered FULL-WIDTH at the top so the user can see
///     what got read (and that OCR worked)
///   · three red iMessage bubbles below, tap to copy each
///   · GIMME MORE pill at the bottom to re-roll
///   · ⊕ icon in the top-right to start a fresh image / clear state
class RizzReplyScreen extends StatefulWidget {
  /// True when opened from the "Upload a screenshot" tab card — fires
  /// the photo picker immediately so the user lands in the iOS sheet.
  final bool launchUpload;
  const RizzReplyScreen({super.key, this.launchUpload = false});

  @override
  State<RizzReplyScreen> createState() => _RizzReplyScreenState();
}

class _RizzReplyScreenState extends State<RizzReplyScreen> {
  final _herCtrl = TextEditingController();
  bool _generating = false;
  Uint8List? _screenshotBytes;
  List<RizzReply>? _replies;
  bool _showTextEntry = false;

  @override
  void initState() {
    super.initState();
    if (widget.launchUpload) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pick(ImageSource.gallery);
      });
    }
  }

  @override
  void dispose() {
    _herCtrl.dispose();
    super.dispose();
  }

  bool get _canGenerate {
    if (_generating) return false;
    if (_screenshotBytes != null) return true;
    return _herCtrl.text.trim().isNotEmpty;
  }

  Future<void> _pick(ImageSource source) async {
    HapticFeedback.selectionClick();
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, maxWidth: 1800);
      if (picked == null || !mounted) return;
      final bytes = await File(picked.path).readAsBytes();
      if (!mounted) return;
      setState(() {
        _screenshotBytes = bytes;
        _replies = null;
        _herCtrl.clear();
        _showTextEntry = false;
      });
      // Auto-generate the moment the image lands — saves a tap. The
      // user picked a screenshot precisely because they want rizz.
      await _generate();
    } catch (_) {
      if (!mounted) return;
      _snack('Couldn\'t load that image. Try another.');
    }
  }

  void _reset() {
    HapticFeedback.selectionClick();
    setState(() {
      _screenshotBytes = null;
      _replies = null;
      _herCtrl.clear();
      _showTextEntry = false;
    });
  }

  Future<void> _generate() async {
    if (!_canGenerate) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _generating = true;
      _replies = null;
    });
    print('[RIZZ-SCREEN] _generate start hasImage=${_screenshotBytes != null} '
        'textLen=${_herCtrl.text.trim().length}');
    // Hard 45s ceiling — even if the backend hangs, the spinner
    // clears + the user sees a clear "try again" snack instead of
    // forever-stuck "READING THE CHAT…".
    try {
      final result = await RizzReplyService.generate(
        herMessage:       _herCtrl.text.trim(),
        screenshotBytes:  _screenshotBytes,
        vibe:             RizzVibe.auto,
      ).timeout(const Duration(seconds: 45));
      print('[RIZZ-SCREEN] _generate got ${result.length} replies');
      if (!mounted) return;
      setState(() {
        _replies = result;
        _generating = false;
      });
    } on TimeoutException {
      print('[RIZZ-SCREEN] _generate timed out');
      if (!mounted) return;
      setState(() => _generating = false);
      _snack('Took too long — try a clearer screenshot.');
    } catch (e) {
      print('[RIZZ-SCREEN] _generate throw $e');
      if (!mounted) return;
      setState(() => _generating = false);
      _snack('Couldn\'t generate — try again.');
    }
  }

  Future<void> _copy(RizzReply r) async {
    HapticFeedback.mediumImpact();
    await Clipboard.setData(ClipboardData(text: r.text));
    if (!mounted) return;
    _snack('Copied. Send it.');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 14, fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        )),
      backgroundColor: AppColors.red,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hasResults = _replies != null;
    final hasImage   = _screenshotBytes != null;
    return Scaffold(
      backgroundColor: Colors.black,
      // Tap anywhere outside the text field to dismiss the keyboard.
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: Column(
            children: [
              _Header(
                onBack:  () => Navigator.of(context).maybePop(),
                onReset: hasImage || hasResults ? _reset : null,
              ),
              Expanded(
                child: hasResults
                    ? _resultsLayout()
                    : _inputLayout(hasImage),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── INPUT STATE ────────────────────────────────────────────────────
  Widget _inputLayout(bool hasImage) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Drop her chat.',
            style: GoogleFonts.playfairDisplay(
              color: Colors.white,
              fontSize: 36, height: 1.05,
              letterSpacing: -0.7,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w800,
            )),
          Text('Get 3 hits.',
            style: GoogleFonts.playfairDisplay(
              color: AppColors.red,
              fontSize: 36, height: 1.05,
              letterSpacing: -0.7,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w800,
            )),

          const SizedBox(height: 28),

          if (_generating)
            _GeneratingPanel(bytes: _screenshotBytes)
          else ...[
            _BigUploadButton(
              onTap: () => _pick(ImageSource.gallery),
              icon: Icons.photo_library_outlined,
              label: 'UPLOAD A SCREENSHOT',
              filled: true,
            ),
            const SizedBox(height: 18),
            if (!_showTextEntry)
              Center(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _showTextEntry = true);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('or type her message  ›',
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 13, letterSpacing: 0.4,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                      )),
                  ),
                ),
              )
            else ...[
              _TextInput(
                controller: _herCtrl,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              _GenerateButton(
                enabled:    _canGenerate,
                generating: _generating,
                onTap:      _generate,
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ── RESULTS STATE ──────────────────────────────────────────────────
  Widget _resultsLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Full screenshot preview (or typed-text card if no image).
          if (_screenshotBytes != null)
            _ScreenshotFull(bytes: _screenshotBytes!)
          else if (_herCtrl.text.trim().isNotEmpty)
            _TypedHerCard(text: _herCtrl.text.trim()),

          const SizedBox(height: 18),

          Center(
            child: Text('TAP A REPLY TO COPY',
              style: GoogleFonts.inter(
                color: AppColors.textTertiary,
                fontSize: 11, letterSpacing: 2.8,
                fontWeight: FontWeight.w800,
              )),
          ),
          const SizedBox(height: 14),

          for (var i = 0; i < _replies!.length; i++) ...[
            _ReplyBubble(
              reply:    _replies![i],
              safeness: i,
              onTap:    () => _copy(_replies![i]),
            ),
            const SizedBox(height: 14),
          ],

          const SizedBox(height: 8),

          _GimmeMoreButton(
            generating: _generating,
            onTap:      _generate,
          ),

          if (_kRizzDebug) ...[
            const SizedBox(height: 18),
            const _RizzDebugPane(),
          ],
        ],
      ),
    );
  }
}

/// In-screen debug pane that surfaces the live RizzDebug trail. Sits
/// at the bottom of the results layout so we can SEE every stage of
/// the OCR → API → parse pipeline without scrolling Xcode console.
/// Tap to expand the raw response.
class _RizzDebugPane extends StatefulWidget {
  const _RizzDebugPane();
  @override
  State<_RizzDebugPane> createState() => _RizzDebugPaneState();
}

class _RizzDebugPaneState extends State<_RizzDebugPane> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.red.withValues(alpha: 0.4), width: 0.6),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                    color: AppColors.red, size: 16),
                const SizedBox(width: 4),
                Text('DEBUG TRAIL',
                  style: GoogleFonts.inter(
                    color: AppColors.red,
                    fontSize: 10.5, letterSpacing: 2.4,
                    fontWeight: FontWeight.w800,
                  )),
                const Spacer(),
                Text('${RizzDebug.log.length} entries',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 10.5, fontWeight: FontWeight.w600,
                  )),
              ],
            ),
          ),
          if (_open) ...[
            const SizedBox(height: 10),
            if (RizzDebug.ocrText.isNotEmpty) ...[
              _row('OCR (${RizzDebug.ocrText.length}c):',
                  RizzDebug.ocrText),
              const SizedBox(height: 6),
            ],
            _row('Endpoint:', RizzDebug.lastEndpoint),
            _row('Status:',   RizzDebug.lastStatus.toString()),
            _row('Parsed:',   '${RizzDebug.parsedCount} replies'),
            if (RizzDebug.lastResponse.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Raw response:',
                style: GoogleFonts.inter(
                  color: AppColors.red,
                  fontSize: 9.5, letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                )),
              const SizedBox(height: 4),
              SelectableText(RizzDebug.lastResponse,
                style: GoogleFonts.firaCode(
                  color: AppColors.textPrimary,
                  fontSize: 10, height: 1.4,
                )),
            ],
            const SizedBox(height: 8),
            Text('Trail:',
              style: GoogleFonts.inter(
                color: AppColors.red,
                fontSize: 9.5, letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
              )),
            const SizedBox(height: 4),
            for (final l in RizzDebug.log)
              Text(l,
                style: GoogleFonts.firaCode(
                  color: AppColors.textSecondary,
                  fontSize: 9.5, height: 1.35,
                )),
          ],
        ],
      ),
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(text: '$k ',
              style: GoogleFonts.inter(
                color: AppColors.red,
                fontSize: 10, fontWeight: FontWeight.w800,
              )),
            TextSpan(text: v,
              style: GoogleFonts.firaCode(
                color: AppColors.textPrimary,
                fontSize: 10,
              )),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onReset;
  const _Header({required this.onBack, required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 14, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 4),
          Text('RIZZ',
            style: GoogleFonts.inter(
              color: AppColors.red,
              fontSize: 12, letterSpacing: 3.6,
              fontWeight: FontWeight.w800,
            )),
          const Spacer(),
          if (onReset != null)
            Material(
              color: AppColors.red,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onReset,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 38, height: 38,
                  alignment: Alignment.center,
                  child: const Icon(Icons.add_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScreenshotFull extends StatelessWidget {
  final Uint8List bytes;
  const _ScreenshotFull({required this.bytes});

  @override
  Widget build(BuildContext context) {
    // Cap the screenshot at HALF the screen height. The rest of the
    // page (rizz bubbles + GIMME MORE) needs room to breathe; an
    // unconstrained Image.memory was filling the whole viewport and
    // pushing the results off the bottom.
    final maxH = MediaQuery.of(context).size.height * 0.42;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.red.withValues(alpha: 0.32), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withValues(alpha: 0.14),
            blurRadius: 22, offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            alignment: Alignment.topCenter,
          ),
        ),
      ),
    );
  }
}

class _TypedHerCard extends StatelessWidget {
  final String text;
  const _TypedHerCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surface3, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('HER',
            style: GoogleFonts.inter(
              color: AppColors.red,
              fontSize: 10, letterSpacing: 2.6,
              fontWeight: FontWeight.w800,
            )),
          const SizedBox(height: 6),
          Text('"$text"',
            style: GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontSize: 15, height: 1.4,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
            )),
        ],
      ),
    );
  }
}

class _GeneratingPanel extends StatelessWidget {
  final Uint8List? bytes;
  const _GeneratingPanel({required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bytes != null)
          _ScreenshotFull(bytes: bytes!),
        const SizedBox(height: 22),
        Center(
          child: Column(
            children: [
              const SizedBox(
                width: 28, height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6, color: AppColors.red),
              ),
              const SizedBox(height: 14),
              Text('READING THE CHAT…',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 12, letterSpacing: 2.8,
                  fontWeight: FontWeight.w800,
                )),
            ],
          ),
        ),
      ],
    );
  }
}

class _BigUploadButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final bool filled;
  const _BigUploadButton({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? AppColors.red : Colors.transparent,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: filled
                ? null
                : Border.all(
                    color: AppColors.red.withValues(alpha: 0.6), width: 1.2),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: AppColors.red.withValues(alpha: 0.4),
                      blurRadius: 24, offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                color: filled ? Colors.white : AppColors.red, size: 20),
              const SizedBox(width: 10),
              Text(label,
                style: GoogleFonts.inter(
                  color: filled ? Colors.white : AppColors.red,
                  fontSize: 13.5, letterSpacing: 2.6,
                  fontWeight: FontWeight.w900,
                )),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextInput extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _TextInput({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surface3, width: 0.6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        maxLines: 4,
        minLines: 3,
        maxLength: 420,
        cursorColor: AppColors.red,
        style: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontSize: 16, height: 1.45,
          fontWeight: FontWeight.w500,
          fontStyle: FontStyle.italic,
        ),
        decoration: InputDecoration(
          hintText: 'What did she say?',
          hintStyle: GoogleFonts.inter(
            color: AppColors.textTertiary,
            fontSize: 16, height: 1.45,
            fontWeight: FontWeight.w400,
            fontStyle: FontStyle.italic,
          ),
          counterText: '',
          border:           InputBorder.none,
          enabledBorder:    InputBorder.none,
          focusedBorder:    InputBorder.none,
          contentPadding:   EdgeInsets.zero,
          isDense:          true,
        ),
      ),
    );
  }
}

class _GenerateButton extends StatelessWidget {
  final bool enabled;
  final bool generating;
  final VoidCallback onTap;
  const _GenerateButton({
    required this.enabled,
    required this.generating,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? AppColors.red : AppColors.surface3,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          alignment: Alignment.center,
          child: generating
              ? const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: Colors.white))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bolt_rounded,
                      color: enabled
                          ? Colors.white
                          : AppColors.textTertiary,
                      size: 22),
                    const SizedBox(width: 8),
                    Text('GENERATE',
                      style: GoogleFonts.inter(
                        color: enabled
                            ? Colors.white
                            : AppColors.textTertiary,
                        fontSize: 14, letterSpacing: 2.8,
                        fontWeight: FontWeight.w900,
                      )),
                  ],
                ),
        ),
      ),
    );
  }
}

class _GimmeMoreButton extends StatelessWidget {
  final bool generating;
  final VoidCallback onTap;
  const _GimmeMoreButton({
    required this.generating,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.red,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: generating ? null : onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            boxShadow: [
              BoxShadow(
                color: AppColors.red.withValues(alpha: 0.4),
                blurRadius: 24, offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: generating
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.refresh_rounded,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text('GIMME MORE',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 14, letterSpacing: 2.8,
                        fontWeight: FontWeight.w900,
                      )),
                  ],
                ),
        ),
      ),
    );
  }
}

/// iMessage-style result bubble — right-aligned red, with a small
/// footer pair "SAFEST · MOVE LABEL" beneath each.
class _ReplyBubble extends StatelessWidget {
  final RizzReply reply;
  final int safeness;
  final VoidCallback onTap;
  const _ReplyBubble({
    required this.reply,
    required this.safeness,
    required this.onTap,
  });

  String get _safenessLabel => switch (safeness) {
        0 => 'SAFEST',
        1 => 'MIDDLE',
        _ => 'BOLDEST',
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            child: Container(
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
                    color: AppColors.red.withValues(alpha: 0.28),
                    blurRadius: 18, spreadRadius: 0,
                  ),
                ],
              ),
              child: Text(reply.text,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 15.5, height: 1.35,
                  fontWeight: FontWeight.w600,
                )),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_safenessLabel,
                  style: GoogleFonts.inter(
                    color: AppColors.textTertiary,
                    fontSize: 10, letterSpacing: 2.4,
                    fontWeight: FontWeight.w800,
                  )),
                Text(' · ',
                  style: TextStyle(color: AppColors.textTertiary)),
                Text(reply.tag,
                  style: GoogleFonts.inter(
                    color: AppColors.red,
                    fontSize: 10, letterSpacing: 2.0,
                    fontWeight: FontWeight.w800,
                  )),
                const SizedBox(width: 6),
                Icon(Icons.copy_rounded,
                  size: 12,
                  color: AppColors.textTertiary.withValues(alpha: 0.6)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
