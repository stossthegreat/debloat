import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';
import '../../widgets/common/mirrorly_components.dart';

/// RIZZ tab — two clean cards. No portraits. No subtext stack.
/// Each card has a short title + one-line subtitle and that's it.
/// Reads in two seconds.
class RizzTabScreen extends StatelessWidget {
  const RizzTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            MirrorlyMasthead(
              title: 'Rizz',
              actions: [
                MastheadAction(
                  icon: Icons.tune,
                  onTap: () => context.push('/settings'),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // SCREENSHOT / REPLY — the AI generator. Vision-direct:
            // upload a chat screenshot OR type her last message.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: _RizzCard(
                eyebrow:  'THE GENERATOR',
                title:    'Upload a screenshot.',
                subtitle: 'AI reads it. Writes 3 replies that hit.',
                solid:    true,
                onTap:    () => context.push('/rizz'),
              ),
            ).animate().fadeIn(duration: 380.ms)
              .slideY(begin: 0.02, end: 0, duration: 380.ms,
                  curve: Curves.easeOut),

            const SizedBox(height: 22),

            // ARSENAL — the curated library.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: _RizzCard(
                eyebrow:  'THE ARSENAL',
                title:    'Pickup lines.',
                subtitle: '125 hand-picked. Tap any line to copy.',
                solid:    false,
                onTap:    () => context.push('/lines'),
              ),
            ).animate().fadeIn(delay: 140.ms, duration: 380.ms)
              .slideY(begin: 0.02, end: 0, duration: 380.ms,
                  curve: Curves.easeOut),
          ],
        ),
      ),
    );
  }
}

/// One Rizz card. Solid red (the generator) or outline red (the
/// library). Editorial composition — small-caps eyebrow, italic
/// Playfair headline, one-line subtitle, chevron CTA.
class _RizzCard extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final bool   solid;
  final VoidCallback onTap;
  const _RizzCard({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.solid,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg          = solid ? AppColors.red : AppColors.surface1;
    final titleColor  = solid ? Colors.white  : AppColors.textPrimary;
    final eyebrowColor = solid
        ? Colors.white.withValues(alpha: 0.85)
        : AppColors.red;
    final subColor    = solid
        ? Colors.white.withValues(alpha: 0.82)
        : AppColors.textSecondary;
    final chevColor   = solid ? Colors.white : AppColors.red;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: (solid ? Colors.white : AppColors.red)
            .withValues(alpha: 0.08),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 22, 28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: solid
                ? null
                : Border.all(
                    color: AppColors.red.withValues(alpha: 0.32),
                    width: 0.9),
            boxShadow: solid
                ? [
                    BoxShadow(
                      color: AppColors.red.withValues(alpha: 0.4),
                      blurRadius: 32, spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(eyebrow,
                      style: GoogleFonts.inter(
                        color: eyebrowColor,
                        fontSize: 11, letterSpacing: 3.0,
                        fontWeight: FontWeight.w800,
                      )),
                    const SizedBox(height: 12),
                    Text(title,
                      style: GoogleFonts.playfairDisplay(
                        color: titleColor,
                        fontSize: 28, height: 1.1,
                        letterSpacing: -0.5,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w800,
                      )),
                    const SizedBox(height: 10),
                    Text(subtitle,
                      style: GoogleFonts.inter(
                        color: subColor,
                        fontSize: 13.5, height: 1.4,
                        fontWeight: FontWeight.w500,
                      )),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Icon(Icons.arrow_forward_ios_rounded,
                color: chevColor, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
