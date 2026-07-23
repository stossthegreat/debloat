import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/app_colors.dart';

/// ─────────────────────────────────────────────────────────────────────────
///  ONBOARDING DESIGN KIT
///  Shared building blocks for the DePuff-style funnel. One violet accent
///  system on the app's blue-black base so every step reads as one flow.
/// ─────────────────────────────────────────────────────────────────────────

/// Funnel accent palette — violet, layered on the app's existing base.
abstract final class Onb {
  static const bg          = AppColors.base;         // #05090B
  static const primary     = Color(0xFF6C4CF5);      // violet CTA / fills
  static const primaryLite = Color(0xFFA78BFA);      // big stats / emphasis
  static const danger      = Color(0xFFFF5F5F);      // "before" / negative
  static const success     = Color(0xFF4ADE9B);      // "after" / positive
  static const card        = Color(0xFF16132A);      // option / info card
  static const cardBorder  = Color(0xFF2A2444);
  static const cardSel     = Color(0xFF241C4A);      // selected card fill
  static const grey        = Color(0xFF9A9AB0);      // sub-copy
}

/// Full-screen scaffold: base bg, optional top bar (back arrow + progress),
/// scrollable body with generous bottom padding, and a pinned CTA area.
class OnbScaffold extends StatelessWidget {
  /// 0..1 progress; null hides the bar (interstitials).
  final double? progress;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget child;
  /// Pinned bottom widget (usually an OnbCta). Null = no pinned footer.
  final Widget? footer;
  final EdgeInsets padding;

  const OnbScaffold({
    super.key,
    this.progress,
    this.showBack = true,
    this.onBack,
    required this.child,
    this.footer,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 24),
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Onb.bg,
      body: SafeArea(
        child: Column(
          children: [
            if (showBack || progress != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 20, 6),
                child: Row(
                  children: [
                    if (showBack)
                      _BackBtn(onTap: onBack ?? () => Navigator.maybePop(context))
                    else
                      const SizedBox(width: 4),
                    const SizedBox(width: 8),
                    if (progress != null)
                      Expanded(child: _ProgressBar(value: progress!))
                    else
                      const Spacer(),
                  ],
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: padding,
                physics: const BouncingScrollPhysics(),
                child: child,
              ),
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: footer!,
              ),
          ],
        ),
      ),
    );
  }
}

class _BackBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _BackBtn({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      customBorder: const CircleBorder(),
      child: const Padding(
        padding: EdgeInsets.all(4),
        child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 26),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double value;
  const _ProgressBar({required this.value});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(100),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: 8,
        backgroundColor: Onb.card,
        valueColor: const AlwaysStoppedAnimation(Onb.primary),
      ),
    );
  }
}

/// Big centred (or left) headline with an optional violet-emphasised tail
/// and a grey sub-line.
class OnbHeadline extends StatelessWidget {
  final String text;
  /// Optional trailing fragment rendered in [Onb.primaryLite].
  final String? emphasis;
  final String? sub;
  final TextAlign align;
  final double size;
  const OnbHeadline({
    super.key,
    required this.text,
    this.emphasis,
    this.sub,
    this.align = TextAlign.center,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    final cross = align == TextAlign.center
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: cross,
      children: [
        RichText(
          textAlign: align,
          text: TextSpan(
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: size, height: 1.12,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
            children: [
              TextSpan(text: text),
              if (emphasis != null)
                TextSpan(text: emphasis,
                  style: const TextStyle(color: Onb.primaryLite)),
            ],
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 12),
          Text(sub!,
            textAlign: align,
            style: GoogleFonts.inter(
              color: Onb.grey,
              fontSize: 16, height: 1.4,
              fontWeight: FontWeight.w500,
            )),
        ],
      ],
    );
  }
}

/// Full-width violet pill CTA, ~62pt tall.
class OnbCta extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  const OnbCta({super.key, required this.label, required this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final on = enabled && onTap != null;
    return Opacity(
      opacity: on ? 1 : 0.4,
      child: Material(
        color: Onb.primary,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: on ? () { HapticFeedback.mediumImpact(); onTap!(); } : null,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 62,
            alignment: Alignment.center,
            child: Text(label,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

/// Single-select row: violet icon tile, label, chevron. Tap advances.
class OnbOptionRow extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;
  const OnbOptionRow({
    super.key,
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Onb.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Onb.cardBorder, width: 1),
          ),
          child: Row(
            children: [
              _EmojiTile(emoji: emoji),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 16.5, height: 1.25,
                    fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded,
                color: Onb.grey, size: 26),
            ],
          ),
        ),
      ),
    );
  }
}

/// Multi-select row: violet icon tile, label, checkbox. Toggle; CTA advances.
class OnbMultiRow extends StatelessWidget {
  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const OnbMultiRow({
    super.key,
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Onb.cardSel : Onb.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? Onb.primary : Onb.cardBorder,
              width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              _EmojiTile(emoji: emoji),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 16.5, height: 1.25,
                    fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              _Check(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmojiTile extends StatelessWidget {
  final String emoji;
  const _EmojiTile({required this.emoji});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46, height: 46,
      decoration: BoxDecoration(
        color: Onb.primary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(emoji, style: const TextStyle(fontSize: 22)),
    );
  }
}

class _Check extends StatelessWidget {
  final bool selected;
  const _Check({required this.selected});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26, height: 26,
      decoration: BoxDecoration(
        color: selected ? Onb.primary : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? Onb.primary : Onb.grey, width: 2),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
          : null,
    );
  }
}

/// Interactive BEFORE/AFTER comparison slider. Drag the handle to reveal
/// the "after" (debloated) over the "before" (bloated). Reused on the
/// shock-stat screen, the identity fork, and anywhere the transformation
/// needs to be felt, not just seen.
class BeforeAfterSlider extends StatefulWidget {
  final String beforeAsset;
  final String afterAsset;
  final String beforeLabel;
  final String afterLabel;
  final double aspectRatio;
  const BeforeAfterSlider({
    super.key,
    this.beforeAsset = 'assets/marketing/before.jpg',
    this.afterAsset  = 'assets/marketing/after.jpg',
    this.beforeLabel = 'Bloated',
    this.afterLabel  = 'Debloated',
    this.aspectRatio = 3 / 4,
  });

  @override
  State<BeforeAfterSlider> createState() => _BeforeAfterSliderState();
}

class _BeforeAfterSliderState extends State<BeforeAfterSlider> {
  double _t = 0.5; // 0=all before, 1=all after

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            return GestureDetector(
              onHorizontalDragUpdate: (d) {
                setState(() => _t = (d.localPosition.dx / w).clamp(0.0, 1.0));
              },
              onTapDown: (d) {
                setState(() => _t = (d.localPosition.dx / w).clamp(0.0, 1.0));
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // BEFORE (base)
                  _img(widget.beforeAsset, Onb.danger),
                  // AFTER (clipped to the right of the handle)
                  ClipRect(
                    clipper: _RightClipper(_t),
                    child: _img(widget.afterAsset, Onb.success),
                  ),
                  // labels
                  Positioned(
                    left: 12, top: 12,
                    child: _tag(widget.beforeLabel, Onb.danger),
                  ),
                  Positioned(
                    right: 12, top: 12,
                    child: _tag(widget.afterLabel, Onb.success),
                  ),
                  // handle
                  Positioned(
                    left: w * _t - 1, top: 0, bottom: 0,
                    child: Container(width: 2.5, color: Colors.white),
                  ),
                  Positioned(
                    left: w * _t - 20,
                    top: 0, bottom: 0,
                    child: Center(
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 8),
                          ],
                        ),
                        child: const Icon(Icons.unfold_more_rounded,
                          color: Onb.primary, size: 22),
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 0, right: 0, bottom: 12,
                    child: Center(child: _DragChip()),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _img(String asset, Color fallback) => Image.asset(
        asset,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: Onb.card,
          alignment: Alignment.center,
          child: Icon(Icons.face_rounded, color: fallback, size: 64),
        ),
      );

  Widget _tag(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: color.withValues(alpha: 0.7), width: 1),
        ),
        child: Text(label.toUpperCase(),
          style: GoogleFonts.inter(
            color: color, fontSize: 10.5, letterSpacing: 1.2,
            fontWeight: FontWeight.w800)),
      );
}

class _DragChip extends StatelessWidget {
  const _DragChip();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 15),
          const SizedBox(width: 6),
          Text('Drag to compare',
            style: GoogleFonts.inter(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _RightClipper extends CustomClipper<Rect> {
  final double t;
  const _RightClipper(this.t);
  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(size.width * t, 0, size.width, size.height);
  @override
  bool shouldReclip(_RightClipper old) => old.t != t;
}
