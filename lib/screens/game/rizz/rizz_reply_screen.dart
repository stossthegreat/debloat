import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/rizz_reply_service.dart';
import '../../../theme/app_colors.dart';

/// RIZZ — clean one-page generator. ONE input area, two entry modes
/// (paste her text or upload a screenshot — picked from a single tile
/// row not a tab toggle), vibe chips, generate, iMessage-style result
/// bubbles. Vision-direct: when a screenshot is supplied, the image
/// itself is sent to the backend so GPT-4o reads the chat natively —
/// no scattered OCR preview, no extra steps for the user.
class RizzReplyScreen extends StatefulWidget {
  const RizzReplyScreen({super.key});

  @override
  State<RizzReplyScreen> createState() => _RizzReplyScreenState();
}

class _RizzReplyScreenState extends State<RizzReplyScreen> {
  final _herCtrl = TextEditingController();
  RizzVibe _vibe = RizzVibe.auto;
  bool _generating = false;
  Uint8List? _screenshotBytes;
  List<RizzReply>? _replies;

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
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1800,
      );
      if (picked == null || !mounted) return;
      final bytes = await File(picked.path).readAsBytes();
      if (!mounted) return;
      setState(() {
        _screenshotBytes = bytes;
        _replies = null;
        _herCtrl.clear();
      });
    } catch (_) {
      if (!mounted) return;
      _snack('Couldn\'t load that image. Try another.');
    }
  }

  void _clearImage() {
    HapticFeedback.selectionClick();
    setState(() => _screenshotBytes = null);
  }

  Future<void> _generate() async {
    if (!_canGenerate) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _generating = true;
      _replies = null;
    });
    final result = await RizzReplyService.generate(
      herMessage:       _herCtrl.text.trim(),
      screenshotBytes:  _screenshotBytes,
      vibe:             _vibe,
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
    final hasImage = _screenshotBytes != null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header.
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
              Text('Drop her text.\nGet 3 hits.',
                style: GoogleFonts.playfairDisplay(
                  color: Colors.white,
                  fontSize: 38, height: 1.05,
                  letterSpacing: -0.8,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w800,
                )),
              const SizedBox(height: 24),

              // Input area — single unified card. When no image is
              // attached: a multiline text field on top + an "upload
              // screenshot" tile row beneath. When an image is
              // attached: the image preview replaces the text area
              // and the row collapses to a single "change image" tile.
              if (hasImage)
                _ScreenshotPreview(
                  bytes: _screenshotBytes!,
                  onClear: _clearImage,
                  onChange: () => _pick(ImageSource.gallery),
                )
              else
                _TextInput(controller: _herCtrl, onChanged: (_) => setState(() {})),

              const SizedBox(height: 12),

              // OR + screenshot tiles. The OR divider only renders
              // when no image is attached; once the user has uploaded
              // a screenshot the text field is hidden so the OR is
              // redundant.
              if (!hasImage) ...[
                _OrDivider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _UploadTile(
                      icon: Icons.photo_library_outlined,
                      label: 'UPLOAD',
                      onTap: () => _pick(ImageSource.gallery),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _UploadTile(
                      icon: Icons.camera_alt_outlined,
                      label: 'TAKE PHOTO',
                      onTap: () => _pick(ImageSource.camera),
                    )),
                  ],
                ),
              ],

              const SizedBox(height: 24),

              // Vibe chips.
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: RizzVibe.values
                      .map((v) => _VibeChip(
                            label: v.label,
                            selected: _vibe == v,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _vibe = v);
                            },
                          ))
                      .toList(),
                ),
              ),

              const SizedBox(height: 22),

              _GenerateButton(
                enabled:    _canGenerate,
                generating: _generating,
                onTap:      _generate,
              ),

              const SizedBox(height: 24),

              // Results — iMessage-style bubble cards.
              if (_replies != null) ...[
                Text('TAP A BUBBLE TO COPY',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: AppColors.textTertiary,
                    fontSize: 11, letterSpacing: 2.8,
                    fontWeight: FontWeight.w800,
                  )),
                const SizedBox(height: 16),
                for (var i = 0; i < _replies!.length; i++) ...[
                  _ReplyBubble(
                    reply:    _replies![i],
                    safeness: i,
                    onTap:    () => _copy(_replies![i]),
                  ),
                  const SizedBox(height: 14),
                ],
              ],
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
        maxLines: 5,
        minLines: 4,
        maxLength: 420,
        cursorColor: AppColors.red,
        style: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontSize: 16, height: 1.45,
          fontWeight: FontWeight.w500,
          fontStyle: FontStyle.italic,
        ),
        decoration: InputDecoration(
          hintText: 'Type what she said …',
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

class _ScreenshotPreview extends StatelessWidget {
  final Uint8List   bytes;
  final VoidCallback onClear;
  final VoidCallback onChange;
  const _ScreenshotPreview({
    required this.bytes,
    required this.onClear,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.red.withValues(alpha: 0.4), width: 0.9),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.image_rounded,
                  color: AppColors.red, size: 16),
              const SizedBox(width: 8),
              Text('SCREENSHOT READY',
                style: GoogleFonts.inter(
                  color: AppColors.red,
                  fontSize: 11, letterSpacing: 2.6,
                  fontWeight: FontWeight.w800,
                )),
              const Spacer(),
              GestureDetector(
                onTap: onChange,
                child: Text('CHANGE',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 11, letterSpacing: 2.4,
                    fontWeight: FontWeight.w800,
                  )),
              ),
              const SizedBox(width: 14),
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close_rounded,
                    color: AppColors.textSecondary, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: Image.memory(bytes,
                  fit: BoxFit.contain),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Container(
          height: 0.6, color: AppColors.surface3)),
        const SizedBox(width: 10),
        Text('OR',
          style: GoogleFonts.inter(
            color: AppColors.textTertiary,
            fontSize: 10.5, letterSpacing: 2.4,
            fontWeight: FontWeight.w800,
          )),
        const SizedBox(width: 10),
        Expanded(child: Container(
          height: 0.6, color: AppColors.surface3)),
      ],
    );
  }
}

class _UploadTile extends StatelessWidget {
  final IconData icon;
  final String   label;
  final VoidCallback onTap;
  const _UploadTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: AppColors.red.withValues(alpha: 0.08),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.4), width: 0.9),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.red, size: 22),
              const SizedBox(height: 8),
              Text(label,
                style: GoogleFonts.inter(
                  color: AppColors.red,
                  fontSize: 11, letterSpacing: 2.4,
                  fontWeight: FontWeight.w800,
                )),
            ],
          ),
        ),
      ),
    );
  }
}

class _VibeChip extends StatelessWidget {
  final String label;
  final bool   selected;
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
              color: selected ? AppColors.red : AppColors.surface3,
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

/// iMessage-style result bubble. Each reply renders as a chat bubble
/// pointed right (i.e. "from you"), in Mirrorly red. The MOVE LABEL
/// + SAFENESS tier sits as a small footer beneath each bubble so the
/// teaching layer stays visible without competing with the line.
class _ReplyBubble extends StatelessWidget {
  final RizzReply reply;
  final int safeness; // 0 = safest, 1 = mid, 2 = boldest
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
          // Right-aligned bubble.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
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
