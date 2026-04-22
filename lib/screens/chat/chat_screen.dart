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
import '../../widgets/common/quick_tryon_chips.dart';

/// Face-aware advisor chat. Text replies + inline Flux Kontext renders
/// showing the user with the suggested change applied.
///
/// `embedded=true` when used as a tab in the home hub — hides the back
/// button (tab nav replaces it) so it doesn't pop the entire home stack.
/// `imagePath` is the local scan image path used for identity-preserved tryon.
class ChatScreen extends StatefulWidget {
  final FaceGeometry geometry;
  final String? imagePath;
  final bool embedded;
  /// If provided, auto-sends this string as the first user turn on mount.
  /// Used when a QuickTryonChip is tapped on the report screen.
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
  /// big before/after card inline whenever the advisor triggers a Flux
  /// render. This is the retention loop — every chat turn that produces a
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

  String _openingLine() {
    return "I've read your face. You scored ${_score.value} (${_score.tierLabel}), "
        "closest archetype ${_match.archetype.name} at ${(_match.match * 100).round()}%. "
        "Your strongest read: ${_score.strongestAxis.$1.toLowerCase()}. "
        "Your pulldown: ${_score.weakestAxis.$1.toLowerCase()}. "
        "Ask me what to do — haircut, beard, skin, glasses, surgery, whatever. "
        "I'll answer against your actual numbers and, when it helps, show you the change on your face.";
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
        imageUrl:      reply.imageUrl,
        imageCaption:  reply.styleRequest,
      ));
      _sending = false;
    });
    _scrollToEnd();
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
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.md),
                itemCount: _messages.length + (_sending ? 1 : 0),
                itemBuilder: (c, i) {
                  if (i == _messages.length) return const _TypingIndicator();
                  final m = _messages[i];
                  return _MessageBubble(
                    message:        m,
                    isFirst:        i == 0 && m.role == ChatRole.assistant,
                    scanBytes:      _scanBytes,
                    score:          _score,
                    match:          _match,
                    percentile:     _percentile(_score.value),
                    potentialDelta: _potentialDelta(_score.value),
                    traits:         TraitBuilderService.build(widget.geometry),
                  );
                },
              ),
            ),
            // Persistent smart-tryon chips — always visible above the input
            QuickTryonChips(
              geometry: widget.geometry,
              compact: true,
              onTap: (style, _) => _send(style),
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
                    Text('Advisor',
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
                Text('KNOWS YOUR BONES · ANSWERS FROM YOUR NUMBERS',
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

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isFirst;
  // Share-card context — passed down so inline before/after can fire share.
  final Uint8List? scanBytes;
  final AestheticScore score;
  final ArchetypeMatch match;
  final int percentile;
  final int potentialDelta;
  final List<Trait> traits;

  const _MessageBubble({
    required this.message,
    required this.score,
    required this.match,
    required this.percentile,
    required this.potentialDelta,
    required this.traits,
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
                          child: Text('YOUR ANALYSIS',
                            style: AppTypography.label.copyWith(
                              color: AppColors.textTertiary, letterSpacing: 2.4, fontSize: 8)),
                        ),
                      Text(message.content,
                        style: AppTypography.body.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 14.5,
                          height: 1.55)),
                    ],
                  ),
                ),
                // Inline BIG before/after — the retention loop. Every time
                // the advisor fires a Flux render, user gets a shareable
                // before/after card + one-tap share button.
                if (!isUser && message.imageUrl != null) ...[
                  const SizedBox(height: 12),
                  _InlineBeforeAfter(
                    beforeBytes: scanBytes,
                    afterUrl:    message.imageUrl!,
                    caption:     message.imageCaption,
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
//  Inline BIG before/after — fires under any assistant reply that carries
//  a Flux tryon URL. This is the retention loop: every visual answer is a
//  shareable transformation moment, not just a static image.
// ═══════════════════════════════════════════════════════════════════════════
class _InlineBeforeAfter extends StatelessWidget {
  final Uint8List? beforeBytes;
  final String afterUrl;
  final String? caption;
  // Traits are kept here ONLY to derive micro-proofs for the share card —
  // the score/percentile/archetype the previous version took are no longer
  // surfaced anywhere in the new viral share format.
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
          potentialDelta: null, // no potential chip in chat context
        ),
        const SizedBox(height: 8),
        // Share CTA — one tap, same composed share card as the report,
        // with the NEW tryon render as the "maxed" side
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
                    // Chat tryon doesn't have the CURRENT/PROJECTED score
                    // pair — pass 0/0 and the share card hides the score
                    // row, showing the "Mirrorly" wordmark at the top
                    // instead. Tagline falls back to the tryon caption
                    // (e.g. "short squared beard, tight neckline").
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

/// Build the 3 micro-proof one-liners shared by chat + report. Pulls top-3
/// strength traits and renders them as compact viral-card lines. Mirrors the
/// helper in report_screen.dart so the share card reads identically from
/// either entry point.
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
