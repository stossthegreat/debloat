import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/rizz_reply_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/mirrorly_components.dart';

/// RIZZ tab — the sexy elite landing.
///
/// One hero card with a stylized phone preview + UPLOAD A SCREENSHOT CTA.
/// A horizontal strip of preset scenario chips ("Playful comeback",
/// "Ask her out", "Flirty first message", "Win back a ghost", …).
/// A single-line text input "Or describe your situation" with a send
/// arrow that opens the generator. A small footer link to the curated
/// pickup-line arsenal.
///
/// Every action ends at the same generator screen (/rizz) with the
/// scenario / image / text pre-routed via [RizzLaunchArgs].
class RizzTabScreen extends StatefulWidget {
  const RizzTabScreen({super.key});

  @override
  State<RizzTabScreen> createState() => _RizzTabScreenState();
}

class _RizzTabScreenState extends State<RizzTabScreen> {
  final _situationCtrl = TextEditingController();

  @override
  void dispose() {
    _situationCtrl.dispose();
    super.dispose();
  }

  void _go(RizzLaunchArgs args) {
    HapticFeedback.selectionClick();
    context.push('/rizz', extra: args);
  }

  void _openLines() {
    HapticFeedback.selectionClick();
    context.push('/lines');
  }

  void _sendSituation() {
    final txt = _situationCtrl.text.trim();
    if (txt.isEmpty) return;
    _go(RizzLaunchArgs(situation: txt));
    _situationCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            MirrorlyMasthead(
              title: 'Rizz',
              actions: [
                MastheadAction(
                  icon: Icons.menu_book_rounded,
                  onTap: _openLines,
                ),
              ],
            ),

            const SizedBox(height: 8),

            // HERO — phone preview + headline + UPLOAD CTA.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: _Hero(onUpload: () => _go(RizzLaunchArgs.upload())),
            ).animate().fadeIn(duration: 380.ms)
              .slideY(begin: 0.02, end: 0, duration: 380.ms,
                  curve: Curves.easeOut),

            const SizedBox(height: 22),

            // PRESET CHIPS — horizontal sliding row of scenario presets.
            // Each opens the generator with the scenario string baked
            // into the RIZZ GOD prompt so the AI biases its three
            // replies toward that move.
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                children: [
                  for (final p in _presets)
                    _PresetChip(
                      label: p.label,
                      onTap: () => _go(RizzLaunchArgs(scenario: p.prompt)),
                    ),
                ],
              ),
            ).animate().fadeIn(delay: 140.ms, duration: 380.ms),

            const SizedBox(height: 16),

            // "OR DESCRIBE" — bottom input row. Send-arrow opens
            // generator with the situation text routed in.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: _SituationInput(
                controller: _situationCtrl,
                onSend:     _sendSituation,
              ),
            ).animate().fadeIn(delay: 220.ms, duration: 380.ms),

            const SizedBox(height: 22),

            // Footer link — pickup-line arsenal.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: _ArsenalLink(onTap: _openLines),
            ),
          ],
        ),
      ),
    );
  }
}

/// Args passed via go_router extra to the generator screen so the
/// generator opens already biased toward the user's intent.
class RizzLaunchArgs {
  /// When true, the generator opens and triggers the image picker
  /// immediately.
  final bool launchUpload;
  /// Pre-set scenario string baked into the RIZZ GOD prompt
  /// (e.g. "playful comeback", "first flirty message", "win her back
  /// after she ghosted").
  final String scenario;
  /// Free-text situation the user typed into the tab input.
  final String situation;
  const RizzLaunchArgs({
    this.launchUpload = false,
    this.scenario     = '',
    this.situation    = '',
  });
  factory RizzLaunchArgs.upload() => const RizzLaunchArgs(launchUpload: true);
}

class _Preset {
  final String label;
  final String prompt;
  const _Preset(this.label, this.prompt);
}

const _presets = <_Preset>[
  _Preset('Playful comeback',
      'She just teased you and you need to volley with a playful comeback.'),
  _Preset('Flirty first message',
      'First message ever — open her with a flirty, screenshot-worthy line.'),
  _Preset('Ask her out',
      'Time to ask her on a real date. Bold but easy.'),
  _Preset('Plan a date',
      'Plan the actual logistics — propose place + day, keep it light.'),
  _Preset('Keep the convo going',
      'Convo was flowing then stalled. Re-ignite without restarting.'),
  _Preset('Recover from a bad reply',
      'Last thing you sent landed flat. Recover with grace and a smirk.'),
  _Preset('Win back a ghost',
      'She ghosted. Re-engage with one line that\'s impossible to ignore.'),
  _Preset('Match her energy',
      'She\'s being warm and flirty. Match her energy without spilling it.'),
];

/// Hero card. Black surface with a soft red glow, a tilted "phone
/// preview" mocked up from a woman portrait and red iMessage bubbles,
/// then the headline copy + big white UPLOAD A SCREENSHOT CTA.
class _Hero extends StatelessWidget {
  final VoidCallback onUpload;
  const _Hero({required this.onUpload});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A0608),
            AppColors.red,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withValues(alpha: 0.42),
            blurRadius: 38, spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      child: Column(
        children: [
          // Phone mock — fixed-height stage.
          SizedBox(
            height: 230,
            child: _PhoneMock(),
          ),
          const SizedBox(height: 14),
          Text('Drop her chat. Get hits.',
            textAlign: TextAlign.center,
            style: GoogleFonts.playfairDisplay(
              color: Colors.white,
              fontSize: 26, height: 1.15,
              letterSpacing: -0.5,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w800,
            )),
          const SizedBox(height: 14),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(99),
            child: InkWell(
              onTap: () { HapticFeedback.selectionClick(); onUpload(); },
              borderRadius: BorderRadius.circular(99),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.photo_library_outlined,
                      color: AppColors.red, size: 18),
                    const SizedBox(width: 10),
                    Text('UPLOAD A SCREENSHOT',
                      style: GoogleFonts.inter(
                        color: AppColors.red,
                        fontSize: 13, letterSpacing: 2.4,
                        fontWeight: FontWeight.w900,
                      )),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small stylized "phone preview" used in the hero card. Tilted
/// woman portrait + a few red iMessage bubbles overlaid. Pure widget
/// composition — no static screenshot asset needed.
class _PhoneMock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Background woman portrait — tilted, behind the chat tile.
        Positioned(
          left: 0, top: 8,
          child: Transform.rotate(
            angle: -0.12,
            child: Container(
              width: 130, height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 18, offset: const Offset(0, 6),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/characters/women/intellectual.png',
                fit: BoxFit.cover,
                alignment: const Alignment(0, -0.4),
                errorBuilder: (_, __, ___) =>
                    Container(color: AppColors.surface3),
              ),
            ),
          ),
        ),

        // Foreground "chat tile" — white card with red bubbles inside.
        Positioned(
          right: 0, top: 18,
          child: Transform.rotate(
            angle: 0.06,
            child: Container(
              width: 178,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F9),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.32),
                    blurRadius: 22, offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header row.
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 9,
                        backgroundImage: const AssetImage(
                            'assets/characters/women/intellectual.png'),
                        backgroundColor: Colors.grey.shade300,
                        onBackgroundImageError: (_, __) {},
                      ),
                      const SizedBox(width: 6),
                      Text('Julia',
                        style: GoogleFonts.inter(
                          color: Colors.black,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        )),
                      const Spacer(),
                      const Icon(Icons.signal_cellular_alt_rounded,
                        size: 8, color: Colors.black54),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Her bubble (grey, left).
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _MockBubble(
                      text: '"causing trouble? me? never"',
                      color: Colors.grey.shade200,
                      textColor: Colors.black87,
                      pointLeft: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Your bubble (red, right) — the rizz reply.
                  Align(
                    alignment: Alignment.centerRight,
                    child: _MockBubble(
                      text: "we'll see about that after a glass of wine",
                      color: AppColors.red,
                      textColor: Colors.white,
                      pointLeft: false,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Her short reply.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _MockBubble(
                      text: "i'm down",
                      color: Colors.grey.shade200,
                      textColor: Colors.black87,
                      pointLeft: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MockBubble extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;
  final bool  pointLeft;
  const _MockBubble({
    required this.text,
    required this.color,
    required this.textColor,
    required this.pointLeft,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 130),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.only(
            topLeft:     const Radius.circular(10),
            topRight:    const Radius.circular(10),
            bottomLeft:  Radius.circular(pointLeft ? 3 : 10),
            bottomRight: Radius.circular(pointLeft ? 10 : 3),
          ),
        ),
        child: Text(text,
          style: GoogleFonts.inter(
            color: textColor,
            fontSize: 8.5, height: 1.25,
            fontWeight: FontWeight.w600,
          )),
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
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: AppColors.red.withValues(alpha: 0.32), width: 0.8),
            ),
            alignment: Alignment.center,
            child: Text(label,
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 13.5, height: 1,
                fontWeight: FontWeight.w700,
              )),
          ),
        ),
      ),
    );
  }
}

class _SituationInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  const _SituationInput({
    required this.controller,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.surface3, width: 0.6),
      ),
      child: Row(
        children: [
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
                hintText: 'Or describe your situation…',
                hintStyle: GoogleFonts.inter(
                  color: AppColors.textTertiary,
                  fontSize: 15, height: 1.3,
                  fontWeight: FontWeight.w400,
                ),
                border:           InputBorder.none,
                enabledBorder:    InputBorder.none,
                focusedBorder:    InputBorder.none,
                contentPadding:   const EdgeInsets.symmetric(vertical: 14),
                isDense:          true,
              ),
            ),
          ),
          Material(
            color: AppColors.red,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onSend,
              customBorder: const CircleBorder(),
              child: Container(
                width: 44, height: 44,
                alignment: Alignment.center,
                child: const Icon(Icons.arrow_upward_rounded,
                  color: Colors.white, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArsenalLink extends StatelessWidget {
  final VoidCallback onTap;
  const _ArsenalLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: AppColors.surface3, width: 0.6),
        ),
        child: Row(
          children: [
            const Icon(Icons.menu_book_rounded,
              color: AppColors.red, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Or browse the pickup-line arsenal',
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 14, height: 1.3,
                  fontWeight: FontWeight.w600,
                )),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
              color: AppColors.textSecondary, size: 14),
          ],
        ),
      ),
    );
  }
}
