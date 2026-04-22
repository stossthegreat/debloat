import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../models/face_geometry.dart';
import '../../services/archetype_service.dart';
import '../../services/chat_service.dart';
import '../../services/face_asset_service.dart';
import '../../services/scoring_service.dart';
import '../../services/share_service.dart';
import '../../services/trait_builder_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/common/before_after_card.dart';

/// THE FACE DOCTOR.
///
/// The moat: this is not a preset generator. The advisor has already
/// measured the user's face to the millimetre (16 geometry metrics).
/// Every reply opens with a measurement citation and a recommendation
/// that follows from their specific anatomy. When a visual helps, GPT
/// proposes a style_request and the UI shows a GENERATE IMAGE button.
/// One tap = one render = one charge. No preset chip row, no default
/// spam.
///
/// Layout:
///   1. Header (Advisor title + score badge)
///   2. Expandable FaceStatsCard — closed by default; tap opens to
///      reveal the user's 16 measurements. Closed state reads
///      "I know your face to the millimetre. Tap to see what I see."
///   3. Message list — assistant messages with pending style_request
///      render a GENERATE IMAGE row under the bubble.
///   4. Input bar.
class ChatScreen extends StatefulWidget {
  final FaceGeometry geometry;
  final String? imagePath;
  final bool embedded;
  /// If provided, auto-sends this string as the first user turn on mount.
  final String? autoSend;

  const ChatScreen({
    super.key,
    required this.geometry,
    this.imagePath,
    this.embedded = false,
    this.autoSend,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messages = <ChatMessage>[];
  final _input = TextEditingController();
  final _scrollCtl = ScrollController();
  bool _sending = false;
  late final AestheticScore _score;
  late final ArchetypeMatch _match;

  /// User's scan image bytes, loaded once from disk. Needed to render the
  /// big before/after card inline whenever a GENERATE IMAGE button is
  /// tapped. This is the retention loop — every chat turn that produces a
  /// visual becomes a shareable before/after moment.
  Uint8List? _scanBytes;

  @override
  void initState() {
    super.initState();
    _score = ScoringService.compute(widget.geometry);
    _match = ArchetypeService.bestMatch(widget.geometry);
    _messages.add(ChatMessage(ChatRole.assistant, _openingLine()));
    _loadScanBytes();
    if (widget.autoSend != null && widget.autoSend!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _send(widget.autoSend!);
      });
    }
  }

  Future<void> _loadScanBytes() async {
    if (widget.imagePath == null) return;
    final bytes = await FaceAssetService.loadScanImageBytes(widget.imagePath!);
    if (!mounted) return;
    setState(() => _scanBytes = bytes);
  }

  int _percentile(int s) {
    if (s >= 92) return 2;
    if (s >= 85) return 8;
    if (s >= 78) return 16;
    if (s >= 70) return 28;
    if (s >= 60) return 44;
    return 62;
  }
  int _potentialDelta(int s) {
    final headroom = (100 - s).clamp(0, 40);
    return (headroom * 0.55).round();
  }

  /// The welcome line — the moat statement. This is the first thing the
  /// user sees when they open the advisor. It's not "ask me about
  /// haircuts", it's "I know you better than your barber does."
  String _openingLine() {
    return "I've measured every millimetre of your face — 16 metrics, "
        "every angle, every ratio. I know your proportions better than "
        "your barber does. Better than you do.\n\n"
        "Ask me anything about haircuts, beards, glasses, skin, body comp, "
        "or what suits you and why. I'll answer against your actual "
        "numbers — not a preset. When a visual helps, I'll ask and you "
        "can tap to render it.";
  }

  Future<void> _send([String? prefilled]) async {
    final text = (prefilled ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _messages.add(ChatMessage(ChatRole.user, text));
      _sending = true;
      _input.clear();
    });
    _scrollToEnd();
    HapticFeedback.lightImpact();

    final reply = await ChatService.send(
      history:   _messages,
      geometry:  widget.geometry,
      imagePath: widget.imagePath,
    );

    if (!mounted) return;
    setState(() {
      _messages.add(ChatMessage(
        ChatRole.assistant, reply.text,
        styleRequest: reply.styleRequest,
        category:     reply.category,
      ));
      _sending = false;
    });
    _scrollToEnd();
  }

  /// Fire /tryon for this assistant message. One tap = one render = one
  /// charge. Mutates the message instance in place so the button flips to
  /// the rendered image on return.
  Future<void> _generateImage(ChatMessage msg) async {
    if (msg.rendering || msg.imageUrl != null) return;
    if (msg.styleRequest == null || widget.imagePath == null) return;

    setState(() => msg.rendering = true);
    HapticFeedback.mediumImpact();

    final url = await TryOnService.render(
      imagePath:    widget.imagePath!,
      styleRequest: msg.styleRequest!,
      category:     msg.category ?? 'generic',
      geometry:     widget.geometry,
    );

    if (!mounted) return;
    setState(() {
      msg.rendering = false;
      if (url != null) msg.imageUrl = url;
    });

    if (url == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t render that just now. Try again?')),
      );
    } else {
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtl.hasClients) return;
      _scrollCtl.animateTo(
        _scrollCtl.position.maxScrollExtent + 200,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: ListView.builder(
                controller: _scrollCtl,
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.md),
                // +1 for the stats card that lives at the top of the scroll.
                itemCount: _messages.length + 1 + (_sending ? 1 : 0),
                itemBuilder: (c, i) {
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: Sp.md),
                      child: _FaceStatsCard(geometry: widget.geometry),
                    );
                  }
                  final msgIndex = i - 1;
                  if (msgIndex == _messages.length) return const _TypingIndicator();
                  final m = _messages[msgIndex];
                  return _MessageBubble(
                    message:        m,
                    isFirst:        msgIndex == 0 && m.role == ChatRole.assistant,
                    scanBytes:      _scanBytes,
                    score:          _score,
                    match:          _match,
                    percentile:     _percentile(_score.value),
                    potentialDelta: _potentialDelta(_score.value),
                    traits:         TraitBuilderService.build(widget.geometry),
                    onGenerate:     () => _generateImage(m),
                  );
                },
              ),
            ),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, Sp.md),
      child: Row(
        children: [
          if (!widget.embedded)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => context.pop(),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.surface1, shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.3), width: 0.8),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 14, color: AppColors.textSecondary),
                ),
              ),
            ),
          if (!widget.embedded) const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('The Mirror',
                      style: AppTypography.h1.copyWith(
                        fontSize: 24, letterSpacing: -0.6, height: 1)),
                    const SizedBox(width: 8),
                    Container(
                      width: 4, height: 4, margin: const EdgeInsets.only(top: 6),
                      decoration: const BoxDecoration(
                        color: AppColors.red, shape: BoxShape.circle),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text('FACE DOCTOR · ANSWERS FROM YOUR NUMBERS',
                  style: AppTypography.label.copyWith(
                    color: AppColors.textMuted, fontSize: 8, letterSpacing: 2.6)),
              ],
            ),
          ),
          _scoreBadge(),
        ],
      ),
    );
  }

  Widget _scoreBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        children: [
          Text('${_score.value}',
            style: AppTypography.measurement.copyWith(
              color: AppColors.red, fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(width: 4),
          Text('/ 100',
            style: AppTypography.label.copyWith(
              color: AppColors.textTertiary, fontSize: 8, letterSpacing: 1.4)),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Sp.md, Sp.sm, Sp.md,
        MediaQuery.of(context).viewInsets.bottom > 0 ? Sp.sm : Sp.md,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(Sp.md, 4, 4, 4),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.24), width: 0.8),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                style: AppTypography.body.copyWith(
                  color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Ask about your face…',
                  hintStyle: AppTypography.body.copyWith(
                    color: AppColors.textMuted, fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _sending ? null : () => _send(),
                borderRadius: BorderRadius.circular(100),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: _sending
                      ? AppColors.surface3
                      : AppColors.red,
                    shape: BoxShape.circle,
                    boxShadow: _sending ? null : [
                      BoxShadow(
                        color: AppColors.divider,
                        blurRadius: 12),
                    ],
                  ),
                  child: Icon(
                    _sending ? Icons.more_horiz : Icons.arrow_upward_rounded,
                    size: 18,
                    color: _sending ? AppColors.textTertiary : AppColors.base,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  FACE STATS CARD
//
//  Closed state is a one-line claim: "I know your face to the millimetre.
//  Tap to see what I see." The user taps, it opens to reveal 16 live
//  measurements from their scan. This is the moat made visible — proof
//  that the advisor above isn't reading generic tea leaves.
// ═══════════════════════════════════════════════════════════════════════════
class _FaceStatsCard extends StatefulWidget {
  final FaceGeometry geometry;
  const _FaceStatsCard({required this.geometry});

  @override
  State<_FaceStatsCard> createState() => _FaceStatsCardState();
}

class _FaceStatsCardState extends State<_FaceStatsCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.geometry;
    final stats = _buildStats(g);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _open = !_open);
        },
        borderRadius: BorderRadius.circular(Rd.lg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(Rd.lg),
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.22), width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Red measurement tick glyph.
                  Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.red.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppColors.red.withValues(alpha: 0.6), width: 0.8),
                    ),
                    child: const Center(
                      child: Icon(Icons.straighten_rounded,
                        size: 13, color: AppColors.red),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('YOUR FACE · MEASURED',
                          style: AppTypography.label.copyWith(
                            color: AppColors.textTertiary,
                            letterSpacing: 2.6, fontSize: 9,
                            fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(
                          _open
                            ? '${stats.length} live metrics from your scan'
                            : 'I know your face to the millimetre. Tap to see what I see.',
                          style: AppTypography.body.copyWith(
                            color: AppColors.textPrimary, fontSize: 13, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 240),
                    turns: _open ? 0.5 : 0,
                    child: const Icon(Icons.expand_more_rounded,
                      size: 20, color: AppColors.textSecondary),
                  ),
                ],
              ),
              if (_open) ...[
                const SizedBox(height: 12),
                Container(height: 1, color: AppColors.divider),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in stats) _StatPill(label: s.$1, value: s.$2),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Build the list of live measurements — same set the backend cites,
  /// rendered visually here as proof.
  List<(String, String)> _buildStats(FaceGeometry g) {
    String n(double v, [int d = 1]) => v.toStringAsFixed(d);
    final items = <(String, String)>[];
    items.add(('CANTHAL',  '${n(g.canthalTilt)}°'));
    items.add(('SYMMETRY', '${n(g.symmetryScore, 0)}/100'));
    items.add(('THIRDS',
      '${n(g.facialThirdTop, 0)}/${n(g.facialThirdMid, 0)}/${n(g.facialThirdLow, 0)}'));
    items.add(('FWHR',     n(g.fwhr, 2)));
    items.add(('EYE GAP',  n(g.eyeSpacingRatio, 2)));
    items.add(('JAW',      '${n(g.jawAngle, 0)}°'));
    items.add(('CHIN',     n(g.chinProjection, 2)));
    items.add(('LENGTH',   n(g.faceLengthRatio, 2)));
    items.add(('NOSE',     n(g.noseLengthRatio, 2)));
    items.add(('LIPS',     n(g.lipFullness, 2)));
    items.add(('BROW GAP', n(g.brow2EyeGap, 2)));
    if (g.headShape.isNotEmpty) {
      items.add(('SHAPE', g.headShape.toUpperCase()));
    }
    return items;
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  const _StatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.base,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
            style: AppTypography.label.copyWith(
              color: AppColors.textTertiary,
              fontSize: 8, letterSpacing: 1.8, fontWeight: FontWeight.w800)),
          const SizedBox(width: 7),
          Text(value,
            style: AppTypography.measurement.copyWith(
              color: AppColors.textPrimary,
              fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isFirst;
  final Uint8List? scanBytes;
  final AestheticScore score;
  final ArchetypeMatch match;
  final int percentile;
  final int potentialDelta;
  final List<Trait> traits;
  final VoidCallback onGenerate;

  const _MessageBubble({
    required this.message,
    required this.score,
    required this.match,
    required this.percentile,
    required this.potentialDelta,
    required this.traits,
    required this.onGenerate,
    this.scanBytes,
    this.isFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) _avatarDot(),
          if (!isUser) const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser ? AppColors.accent.withValues(alpha: 0.14) : AppColors.surface1,
                    borderRadius: BorderRadius.only(
                      topLeft:  Radius.circular(isUser ? 18 : 6),
                      topRight: Radius.circular(isUser ? 6 : 18),
                      bottomLeft: const Radius.circular(18),
                      bottomRight: const Radius.circular(18),
                    ),
                    border: Border.all(
                      color: (isUser ? AppColors.accent : AppColors.divider)
                          .withValues(alpha: isFirst ? 0.4 : 0.6),
                      width: 0.8,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isFirst)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('THE MIRROR',
                            style: AppTypography.label.copyWith(
                              color: AppColors.red, letterSpacing: 2.6, fontSize: 8.5,
                              fontWeight: FontWeight.w800)),
                        ),
                      Text(message.content,
                        style: AppTypography.body.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 14.5,
                          height: 1.55)),
                    ],
                  ),
                ),

                // ── GENERATE IMAGE button — pending visual, not yet rendered ──
                if (message.hasPendingRender) ...[
                  const SizedBox(height: 10),
                  _GenerateImageButton(
                    styleRequest: message.styleRequest!,
                    rendering:    message.rendering,
                    onTap:        onGenerate,
                  ),
                ],

                // ── Inline BIG before/after — appears after GENERATE IMAGE ──
                if (!isUser && message.imageUrl != null) ...[
                  const SizedBox(height: 12),
                  _InlineBeforeAfter(
                    beforeBytes: scanBytes,
                    afterUrl:    message.imageUrl!,
                    caption:     message.styleRequest,
                    traits:      traits,
                  ),
                ],
              ],
            ).animate().fadeIn(duration: 260.ms).slideY(
              begin: 0.08, end: 0, duration: 260.ms, curve: Curves.easeOut),
          ),
        ],
      ),
    );
  }

  Widget _avatarDot() {
    return Container(
      width: 28, height: 28, margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.divider, width: 0.8),
      ),
      child: const Center(
        child: Icon(Icons.auto_awesome, size: 13, color: AppColors.textSecondary)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  GENERATE IMAGE — the user-intent button. Shown under any assistant
//  message where the advisor proposed a visual but has NOT rendered it.
//  One tap = one render. The button flips to a rendering state while
//  /tryon runs, then disappears when imageUrl populates.
// ═══════════════════════════════════════════════════════════════════════════
class _GenerateImageButton extends StatelessWidget {
  final String styleRequest;
  final bool rendering;
  final VoidCallback onTap;

  const _GenerateImageButton({
    required this.styleRequest,
    required this.rendering,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: rendering ? null : onTap,
        borderRadius: BorderRadius.circular(Rd.md),
        child: Ink(
          decoration: BoxDecoration(
            gradient: rendering ? null : const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFFE8222A), Color(0xFFB31018)],
            ),
            color: rendering ? AppColors.surface2 : null,
            borderRadius: BorderRadius.circular(Rd.md),
            border: Border.all(
              color: rendering
                ? AppColors.divider
                : AppColors.red.withValues(alpha: 0.6),
              width: 0.8,
            ),
            boxShadow: rendering ? null : [
              BoxShadow(
                color: AppColors.red.withValues(alpha: 0.35),
                blurRadius: 18, offset: const Offset(0, 4)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (rendering)
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      valueColor: AlwaysStoppedAnimation(AppColors.textSecondary),
                    ),
                  )
                else
                  const Icon(Icons.auto_fix_high_rounded,
                    size: 15, color: Colors.white),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    rendering ? 'RENDERING YOUR FACE…' : 'GENERATE IMAGE',
                    style: AppTypography.label.copyWith(
                      color: rendering ? AppColors.textSecondary : Colors.white,
                      fontSize: 12, letterSpacing: 2.2,
                      fontWeight: FontWeight.w900),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Inline BIG before/after — fires under any assistant reply whose
//  GENERATE IMAGE button has been tapped. Every visual answer becomes a
//  shareable transformation moment.
// ═══════════════════════════════════════════════════════════════════════════
class _InlineBeforeAfter extends StatelessWidget {
  final Uint8List? beforeBytes;
  final String afterUrl;
  final String? caption;
  final List<Trait> traits;

  const _InlineBeforeAfter({
    required this.beforeBytes,
    required this.afterUrl,
    required this.traits,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BeforeAfterCard(
          beforeBytes:    beforeBytes,
          afterUrl:       afterUrl,
          caption:        caption,
          beforeLabel:    'NOW',
          afterLabel:     'AFTER',
          potentialDelta: null,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.divider),
                    foregroundColor: AppColors.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Rd.md)),
                  ),
                  onPressed: () => ShareService.shareComposed(
                    context:        context,
                    beforeBytes:    beforeBytes,
                    afterUrl:       afterUrl,
                    currentScore:   0,
                    projectedScore: 0,
                    tagline:        caption ?? 'Same face. Better execution.',
                    microProofs:    _proofsFromTraits(traits),
                    text: 'Same face. mirrorly.app',
                  ),
                  icon: const Icon(Icons.ios_share_rounded, size: 14),
                  label: Text('SHARE',
                    style: AppTypography.label.copyWith(
                      color: AppColors.textTertiary, letterSpacing: 2.0,
                      fontSize: 10, fontWeight: FontWeight.w900)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Build the 3 micro-proof one-liners shared by chat + report.
List<String> _proofsFromTraits(List<Trait> traits) {
  final strengths = traits
      .where((t) => t.kind == TraitKind.strength)
      .take(3)
      .toList();
  final lines = <String>[];
  for (final t in strengths) {
    final pct = t.pct.trim();
    if (pct.toUpperCase().startsWith('TOP ')) {
      lines.add('$pct ${t.name}');
    } else if (pct.isNotEmpty &&
        !pct.contains(RegExp(r'[A-Z]{2,} [A-Z]{2,}'))) {
      lines.add('${t.name} · $pct');
    } else {
      lines.add(t.name);
    }
  }
  while (lines.length < 3) {
    lines.add(const ['MEASURED PROFILE', 'BALANCED FRAME',
                      'STRUCTURED ARCHETYPE'][lines.length]);
  }
  return lines;
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;
  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat();
  }
  @override
  void dispose() { _ac.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, left: 38),
      child: AnimatedBuilder(
        animation: _ac,
        builder: (_, __) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              Opacity(
                opacity: _dotOpacity(i, _ac.value),
                child: Container(
                  width: 6, height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.red, shape: BoxShape.circle),
                ),
              ),
              if (i < 2) const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }
  double _dotOpacity(int i, double t) {
    final phase = (t - i * 0.15) % 1.0;
    if (phase < 0.5) return 0.3 + phase * 1.4;
    return 1.0 - (phase - 0.5) * 1.4;
  }
}
