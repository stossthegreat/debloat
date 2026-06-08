import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/rizz_reply_service.dart';
import '../../../services/screenshot_ocr_service.dart';
import '../../../theme/app_colors.dart';

/// RIZZ — paste her text or drop a screenshot, get three replies ranked
/// safest → boldest. Editorial card composition: red eyebrow, italic
/// Playfair headline, segmented type/screenshot toggle, vibe chips,
/// big red generate, 3 result cards with tag + tap-to-copy.
class RizzReplyScreen extends StatefulWidget {
  const RizzReplyScreen({super.key});

  @override
  State<RizzReplyScreen> createState() => _RizzReplyScreenState();
}

enum _InputMode { type, screenshot }

class _RizzReplyScreenState extends State<RizzReplyScreen> {
  final _herCtrl = TextEditingController();
  final _ctxCtrl = TextEditingController();
  _InputMode _mode = _InputMode.type;
  RizzVibe _vibe = RizzVibe.auto;
  bool _ctxOpen = false;
  bool _generating = false;
  bool _ocrRunning = false;
  String? _screenshotPath;
  String _ocrText = '';
  List<RizzReply>? _replies;

  @override
  void dispose() {
    _herCtrl.dispose();
    _ctxCtrl.dispose();
    super.dispose();
  }

  String get _herInput =>
      _mode == _InputMode.type ? _herCtrl.text.trim() : _ocrText.trim();

  bool get _canGenerate => _herInput.isNotEmpty && !_generating && !_ocrRunning;

  Future<void> _pickScreenshot(ImageSource source) async {
    HapticFeedback.selectionClick();
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1600,
      );
      if (picked == null || !mounted) return;
      setState(() {
        _screenshotPath = picked.path;
        _ocrText = '';
        _ocrRunning = true;
        _replies = null;
      });
      final text = await ScreenshotOcrService.extractRecent(picked.path);
      if (!mounted) return;
      setState(() {
        _ocrText = text;
        _ocrRunning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _ocrRunning = false);
      _snack('Couldn\'t read that screenshot — try a cleaner crop.');
    }
  }

  Future<void> _generate() async {
    if (!_canGenerate) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _generating = true;
      _replies = null;
    });
    final result = await RizzReplyService.generate(
      herMessage: _herInput,
      vibe:       _vibe,
      context:    _ctxCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _replies = result;
      _generating = false;
    });
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28, minHeight: 28),
                  ),
                  const SizedBox(width: 6),
                  Text('RIZZ',
                    style: GoogleFonts.inter(
                      color: AppColors.red,
                      fontSize: 12, letterSpacing: 3.6,
                      fontWeight: FontWeight.w800,
                    )),
                ],
              ),
              const SizedBox(height: 10),
              Text(_mode == _InputMode.type
                      ? 'Drop her text.\nGet 3 hits.'
                      : 'Drop a screenshot.\nGet 3 hits.',
                style: GoogleFonts.playfairDisplay(
                  color: Colors.white,
                  fontSize: 38, height: 1.05,
                  letterSpacing: -0.8,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w800,
                )),
              const SizedBox(height: 10),
              Text(_mode == _InputMode.type
                      ? 'Paste what she said. Pick a vibe. Get three replies '
                        'ranked safest → boldest. 2026 Gen-Z. No 2014 cringe.'
                      : 'Hinge. Tinder. WhatsApp. Anything. We read the last '
                        'few messages and hand you three replies that hit — '
                        'safest to boldest.',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 14, height: 1.45,
                  fontWeight: FontWeight.w500,
                )),

              const SizedBox(height: 22),

              // ── Type / Screenshot segmented toggle ──────────────────
              _ModeToggle(
                mode: _mode,
                onChange: (m) {
                  HapticFeedback.selectionClick();
                  setState(() => _mode = m);
                },
              ),

              const SizedBox(height: 18),

              // ── Input area ──────────────────────────────────────────
              if (_mode == _InputMode.type)
                _TypeInput(controller: _herCtrl, onChanged: (_) => setState(() {}))
              else
                _ScreenshotInput(
                  imagePath:   _screenshotPath,
                  ocrText:     _ocrText,
                  ocrRunning:  _ocrRunning,
                  onChoose:    () => _pickScreenshot(ImageSource.gallery),
                  onTake:      () => _pickScreenshot(ImageSource.camera),
                ),

              const SizedBox(height: 22),

              // ── Vibe chips ──────────────────────────────────────────
              Text('PICK A VIBE',
                style: GoogleFonts.inter(
                  color: AppColors.textTertiary,
                  fontSize: 11, letterSpacing: 2.8,
                  fontWeight: FontWeight.w800,
                )),
              const SizedBox(height: 10),
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: RizzVibe.values
                      .map((v) => _VibeChip(
                            label:    v.label,
                            selected: _vibe == v,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _vibe = v);
                            },
                          ))
                      .toList(),
                ),
              ),

              const SizedBox(height: 16),

              // ── Optional context ────────────────────────────────────
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _ctxOpen = !_ctxOpen);
                },
                child: Row(
                  children: [
                    Icon(_ctxOpen
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.red, size: 20),
                    const SizedBox(width: 4),
                    Text('ADD CONTEXT (OPTIONAL)',
                      style: GoogleFonts.inter(
                        color: AppColors.red,
                        fontSize: 11, letterSpacing: 2.4,
                        fontWeight: FontWeight.w800,
                      )),
                  ],
                ),
              ),
              if (_ctxOpen) ...[
                const SizedBox(height: 10),
                _ContextInput(controller: _ctxCtrl),
              ],

              const SizedBox(height: 22),

              // ── GENERATE button ─────────────────────────────────────
              _GenerateButton(
                enabled:    _canGenerate,
                generating: _generating,
                onTap:      _generate,
              ),

              const SizedBox(height: 20),

              // ── Results ─────────────────────────────────────────────
              if (_replies != null) ...[
                const SizedBox(height: 8),
                Text('TAP A REPLY TO COPY',
                  style: GoogleFonts.inter(
                    color: AppColors.textTertiary,
                    fontSize: 11, letterSpacing: 2.8,
                    fontWeight: FontWeight.w800,
                  )),
                const SizedBox(height: 12),
                for (var i = 0; i < _replies!.length; i++) ...[
                  _ReplyCard(
                    reply:    _replies![i],
                    safeness: i,
                    onTap:    () => _copy(_replies![i]),
                  ),
                  const SizedBox(height: 10),
                ],
              ] else if (!_generating) ...[
                _ThePlayCard(mode: _mode),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Mode toggle (TYPE / SCREENSHOT) ─────────────────────────────────
class _ModeToggle extends StatelessWidget {
  final _InputMode mode;
  final ValueChanged<_InputMode> onChange;
  const _ModeToggle({required this.mode, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surface3, width: 0.6),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(child: _seg('TYPE TEXT',     _InputMode.type)),
          Expanded(child: _seg('SCREENSHOT',    _InputMode.screenshot)),
        ],
      ),
    );
  }

  Widget _seg(String label, _InputMode val) {
    final selected = mode == val;
    return GestureDetector(
      onTap: () => onChange(val),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.red : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Text(label,
          style: GoogleFonts.inter(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontSize: 12, letterSpacing: 2.4,
            fontWeight: FontWeight.w800,
          )),
      ),
    );
  }
}

class _TypeInput extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _TypeInput({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surface3, width: 0.6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        maxLines: 5,
        minLines: 4,
        maxLength: 420,
        cursorColor: AppColors.red,
        style: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontSize: 15, height: 1.4,
          fontWeight: FontWeight.w500,
          fontStyle: FontStyle.italic,
        ),
        decoration: InputDecoration(
          hintText: '"so what brings u to hinge"  ·  "u\'re weirdly forward lol"  ·  "lol ok"',
          hintStyle: GoogleFonts.inter(
            color: AppColors.textTertiary,
            fontSize: 14, height: 1.4,
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

class _ScreenshotInput extends StatelessWidget {
  final String? imagePath;
  final String  ocrText;
  final bool    ocrRunning;
  final VoidCallback onChoose;
  final VoidCallback onTake;
  const _ScreenshotInput({
    required this.imagePath,
    required this.ocrText,
    required this.ocrRunning,
    required this.onChoose,
    required this.onTake,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Primary action — choose screenshot
        Material(
          color: AppColors.red,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: ocrRunning ? null : onChoose,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.photo_library_outlined,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Text('CHOOSE SCREENSHOT',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 13, letterSpacing: 2.6,
                      fontWeight: FontWeight.w900,
                    )),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Secondary action — take a new photo (outline)
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: ocrRunning ? null : onTake,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.red.withValues(alpha: 0.6), width: 1.4),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.camera_alt_outlined,
                      color: AppColors.red, size: 18),
                  const SizedBox(width: 10),
                  Text('TAKE A NEW PHOTO',
                    style: GoogleFonts.inter(
                      color: AppColors.red,
                      fontSize: 13, letterSpacing: 2.6,
                      fontWeight: FontWeight.w800,
                    )),
                ],
              ),
            ),
          ),
        ),

        if (ocrRunning) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              const SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6, color: AppColors.red),
              ),
              const SizedBox(width: 10),
              Text('READING THE BUBBLES…',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 11, letterSpacing: 2.4,
                  fontWeight: FontWeight.w700,
                )),
            ],
          ),
        ] else if (imagePath != null && ocrText.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surface3, width: 0.6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('READ',
                  style: GoogleFonts.inter(
                    color: AppColors.red,
                    fontSize: 10, letterSpacing: 2.4,
                    fontWeight: FontWeight.w800,
                  )),
                const SizedBox(height: 6),
                Text(ocrText,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 14, height: 1.4,
                    fontWeight: FontWeight.w500,
                    fontStyle: FontStyle.italic,
                  )),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ContextInput extends StatelessWidget {
  final TextEditingController controller;
  const _ContextInput({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surface3, width: 0.6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        controller: controller,
        maxLines: 3,
        minLines: 2,
        maxLength: 200,
        cursorColor: AppColors.red,
        style: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontSize: 14, height: 1.4,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'One line: "she went cold yesterday", "first reply", etc.',
          hintStyle: GoogleFonts.inter(
            color: AppColors.textTertiary,
            fontSize: 13, fontWeight: FontWeight.w400,
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

class _VibeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _VibeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.red : AppColors.surface1,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected
                  ? AppColors.red
                  : AppColors.surface3,
              width: 0.8,
            ),
          ),
          child: Text(label,
            style: GoogleFonts.inter(
              color: selected ? Colors.white : AppColors.textSecondary,
              fontSize: 12, letterSpacing: 2.4,
              fontWeight: FontWeight.w800,
            )),
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
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
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
                    Text('GENERATE 3 LINES',
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

class _ReplyCard extends StatelessWidget {
  final RizzReply reply;
  final int safeness; // 0 = safest, 1 = mid, 2 = boldest
  final VoidCallback onTap;
  const _ReplyCard({
    required this.reply,
    required this.safeness,
    required this.onTap,
  });

  String get _label => switch (safeness) {
        0 => 'SAFEST',
        1 => 'MIDDLE',
        _ => 'BOLDEST',
      };

  @override
  Widget build(BuildContext context) {
    final isBold = safeness == 2;
    return Material(
      color: isBold ? AppColors.surface1 : AppColors.surface1,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: AppColors.red.withValues(alpha: 0.08),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isBold
                  ? AppColors.red.withValues(alpha: 0.4)
                  : AppColors.surface3,
              width: isBold ? 1.0 : 0.6,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(_label,
                    style: GoogleFonts.inter(
                      color: AppColors.textTertiary,
                      fontSize: 10, letterSpacing: 2.6,
                      fontWeight: FontWeight.w800,
                    )),
                  const Spacer(),
                  Icon(Icons.copy_rounded,
                      size: 16,
                      color: AppColors.textTertiary.withValues(alpha: 0.7)),
                ],
              ),
              const SizedBox(height: 10),
              Text('"${reply.text}"',
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 17, height: 1.32,
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.italic,
                )),
              const SizedBox(height: 12),
              Text(reply.tag,
                style: GoogleFonts.inter(
                  color: AppColors.red,
                  fontSize: 10.5, letterSpacing: 2.2,
                  fontWeight: FontWeight.w800,
                )),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThePlayCard extends StatelessWidget {
  final _InputMode mode;
  const _ThePlayCard({required this.mode});

  @override
  Widget build(BuildContext context) {
    final body = mode == _InputMode.type
        ? 'Paste her exact words. Don\'t summarise. The model writes '
          'sharper when it sees the real cadence.\n\nAUTO usually wins. '
          'Pick BOLD only when you\'re fine getting left on read.'
        : 'Crop tight on the LAST 4-5 messages. We don\'t need the '
          'whole convo — just the last beat. Less context = sharper '
          'lines.';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surface3, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('THE PLAY',
            style: GoogleFonts.inter(
              color: AppColors.red,
              fontSize: 11, letterSpacing: 2.6,
              fontWeight: FontWeight.w800,
            )),
          const SizedBox(height: 10),
          Text(body,
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 14, height: 1.5,
              fontWeight: FontWeight.w500,
            )),
        ],
      ),
    );
  }
}
