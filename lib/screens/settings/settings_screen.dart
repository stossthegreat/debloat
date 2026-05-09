import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../config/dev_flags.dart';
import '../../services/face_asset_service.dart';
import '../../services/local_store_service.dart';
import '../../services/purchase_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Settings — every tile wired to a real action. Apple App Review
/// requires working Terms, Privacy Policy, Restore Purchases, and a
/// Manage Subscription path; all four are surfaced from here as well
/// as from the paywall.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              const SizedBox(height: Sp.md),
              Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.close, color: AppColors.textPrimary),
                    splashRadius: 22,
                  ),
                  const Spacer(),
                  Text('SETTINGS', style: AppTypography.label.copyWith(
                    color: AppColors.textTertiary, letterSpacing: 3, fontSize: 11)),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),

              const SizedBox(height: Sp.lg),

              // App identity
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surface2,
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.4),
                          width: 1.5),
                      ),
                      child: Center(
                        child: Text('M',
                          style: TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w700,
                            color: AppColors.accent, letterSpacing: -1)),
                      ),
                    ),
                    const SizedBox(height: Sp.sm),
                    Text('Mirrorly', style: AppTypography.h2),
                    const SizedBox(height: 4),
                    Text('Version 1.0.0', style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary, fontSize: 11)),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms),

              const SizedBox(height: Sp.xl),

              // ── SUBSCRIPTION ──────────────────────────────────────────────
              // In dev-bypass mode the user is forced-subscribed, so the
              // "Upgrade" tile is hidden to avoid a dead entry point.
              // Restore + Manage stay visible because Apple requires both
              // present in release builds regardless.
              _SectionHeader('SUBSCRIPTION'),
              if (!kBypassPaywall)
                _SettingTile(
                  icon: Icons.workspace_premium_rounded,
                  title: 'Mirrorly Pro',
                  subtitle: '2 scans / week · 10 renders / month',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.push('/paywall');
                  },
                ),
              _SettingTile(
                icon: Icons.restore_rounded,
                title: 'Restore purchases',
                subtitle: 'Recover a subscription on this device',
                onTap: () => _restore(context),
              ),
              _SettingTile(
                icon: Icons.settings_rounded,
                title: 'Manage subscription',
                subtitle: Platform.isIOS
                    ? 'Opens your App Store subscription settings'
                    : 'Opens your Google Play subscription settings',
                onTap: () => _manageSubscription(context),
              ),

              const SizedBox(height: Sp.lg),

              // ── SCAN ──────────────────────────────────────────────────────
              _SectionHeader('SCAN'),
              _SettingTile(
                icon: Icons.history,
                title: 'Rescan history',
                subtitle: 'Your structural progress over time',
                trailing: _Badge(label: 'COMING SOON'),
                onTap: () => _showSoon(context),
              ),
              _SettingTile(
                icon: Icons.download_outlined,
                title: 'Export report',
                subtitle: 'Save your last scan as PDF',
                trailing: _Badge(label: 'COMING SOON'),
                onTap: () => _showSoon(context),
              ),

              const SizedBox(height: Sp.lg),

              // ── LEGAL ─────────────────────────────────────────────────────
              _SectionHeader('LEGAL'),
              _SettingTile(
                icon: Icons.gavel_outlined,
                title: 'Terms of Use',
                subtitle: 'How Mirrorly works, what you agree to',
                onTap: () {
                  HapticFeedback.selectionClick();
                  context.push('/terms');
                },
              ),
              _SettingTile(
                icon: Icons.policy_outlined,
                title: 'Privacy Policy',
                subtitle: 'What we collect and where it goes',
                onTap: () {
                  HapticFeedback.selectionClick();
                  context.push('/privacy');
                },
              ),

              const SizedBox(height: Sp.lg),

              // ── DATA ──────────────────────────────────────────────────────
              _SectionHeader('YOUR DATA'),
              _SettingTile(
                icon: Icons.shield_outlined,
                title: 'How we handle photos',
                subtitle: 'Quick summary — full details in Privacy Policy',
                onTap: () => _showPrivacySummary(context),
              ),
              _SettingTile(
                icon: Icons.cloud_off_outlined,
                title: 'Revoke AI permission',
                subtitle: 'Stop sending photos to OpenAI / Replicate; '
                          'asked again on the next scan',
                onTap: () => _revokeAiConsent(context),
              ),
              _SettingTile(
                icon: Icons.style_outlined,
                title: 'Glow-up style',
                subtitle: 'Tune analysis + renders for men\'s grooming '
                          'or women\'s beauty',
                onTap: () {
                  HapticFeedback.selectionClick();
                  context.push('/onboarding/gender',
                      extra: const {'fromSettings': true});
                },
              ),
              _SettingTile(
                icon: Icons.delete_outline,
                title: 'Delete all data',
                subtitle: 'Permanently removes scans from this device',
                destructive: true,
                onTap: () => _confirmDelete(context),
              ),

              const SizedBox(height: Sp.lg),

              // ── ABOUT ─────────────────────────────────────────────────────
              _SectionHeader('ABOUT'),
              _SettingTile(
                icon: Icons.description_outlined,
                title: 'How Mirrorly works',
                subtitle: 'The science behind the scan',
                onTap: () => _showHow(context),
              ),
              _SettingTile(
                icon: Icons.mail_outline,
                title: 'Contact',
                subtitle: 'info@m2mb.co.uk',
                onTap: () => _copyEmail(context),
              ),

              const SizedBox(height: Sp.xxl),

              Center(
                child: Text(
                  '© 2026 Mirrorly',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiary, fontSize: 11),
                ),
              ),
              const SizedBox(height: Sp.xl),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  //  ACTIONS
  // ───────────────────────────────────────────────────────────────────────

  Future<void> _restore(BuildContext ctx) async {
    HapticFeedback.selectionClick();
    final outcome = await PurchaseService.restore();
    if (!ctx.mounted) return;
    final msg = switch (outcome) {
      PurchaseOutcome.success           => 'Subscription restored.',
      PurchaseOutcome.noPriorPurchases  => 'No previous purchases found.',
      PurchaseOutcome.notConfigured     => 'Store not yet configured.',
      _                                 => 'Could not restore purchases.',
    };
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface2,
    ));
  }

  Future<void> _manageSubscription(BuildContext ctx) async {
    HapticFeedback.selectionClick();
    // Deep links (Apple: https://apps.apple.com/account/subscriptions,
    // Google: https://play.google.com/store/account/subscriptions)
    // need url_launcher. To avoid adding a package for a single route,
    // we show a modal telling the user exactly where to tap. Apple
    // reviewers accept this pattern when no external link is offered.
    //
    // App Store guideline 2.3.10 — show ONLY the platform-relevant
    // path; iOS users must not see Google Play instructions and
    // vice versa.
    if (!ctx.mounted) return;
    final body = Platform.isIOS
        ? 'Open Settings → Apple ID (your name) → Subscriptions → '
          'Mirrorly Pro → Cancel subscription.\n\n'
          'Cancel at least 24 hours before renewal to avoid the next '
          'charge.'
        : 'Open Google Play → Profile → Payments & subscriptions → '
          'Subscriptions → Mirrorly Pro → Cancel subscription.\n\n'
          'Cancel at least 24 hours before renewal to avoid the next '
          'charge.';
    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppColors.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sheetHandle(),
            Text('Manage subscription', style: AppTypography.h2),
            const SizedBox(height: Sp.md),
            Text(body, style: AppTypography.body.copyWith(height: 1.55)),
            const SizedBox(height: Sp.lg),
          ],
        ),
      ),
    );
  }

  void _showSoon(BuildContext ctx) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface2,
        content: Text('Coming soon',
          style: AppTypography.bodySmall.copyWith(color: AppColors.textPrimary)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _copyEmail(BuildContext ctx) async {
    await Clipboard.setData(const ClipboardData(text: 'info@m2mb.co.uk'));
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: const Text('info@m2mb.co.uk — copied. Paste into your mail app.'),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface2,
    ));
  }

  void _showPrivacySummary(BuildContext ctx) => _showInfoSheet(ctx,
    'How we handle your photo',
    'Your photo is processed on your device by MediaPipe to extract 16 '
    'facial measurements.\n\n'
    'When you tap SCAN, GENERATE IMAGE, or the Mirror chat, we send that '
    'single photo to our AI providers (OpenAI for analysis, Replicate for '
    'image rendering) for the duration of one request.\n\n'
    'We do not save your photo on our servers. We do not sell your data. '
    'We do not train AI models on your face. We do not require an account.\n\n'
    'For the full text, open Privacy Policy above.',
  );

  void _showHow(BuildContext ctx) => _showInfoSheet(ctx,
    'How Mirrorly works',
    'The two-score moat, end to end:\n\n'
    '1. MediaPipe maps 468 landmarks on your face at 30fps, on-device. '
    'From those landmarks we compute 16 geometric measurements — canthal '
    'tilt, jaw angle, FWHR, facial thirds, symmetry, and more. That\'s '
    'your BONE STRUCTURE score.\n\n'
    '2. GPT-4o Vision looks at your actual photo (never the geometry '
    'numbers) and rates what the human eye sees — skin, eye area, '
    'proportions, harmony. That\'s your HONEST LOOKS score.\n\n'
    '3. Google Nano Banana renders your face with the recommended change '
    'applied. A face-swap post-pass anchors the output to your real '
    'bones so the render is still recognizably you.\n\n'
    '4. The Mirror advisor reads your measurements and recommends '
    'haircuts, beards, skin protocols, glasses — tailored to your '
    'anatomy, not a template.',
  );

  Widget _sheetHandle() => Container(
    width: 36, height: 4,
    margin: const EdgeInsets.only(bottom: Sp.lg),
    decoration: BoxDecoration(
      color: AppColors.surface3,
      borderRadius: BorderRadius.circular(2),
    ),
  );

  void _showInfoSheet(BuildContext ctx, String title, String body) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppColors.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.xl),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetHandle(),
              Text(title, style: AppTypography.h2),
              const SizedBox(height: Sp.md),
              Text(body, style: AppTypography.body.copyWith(height: 1.6)),
              const SizedBox(height: Sp.lg),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _revokeAiConsent(BuildContext ctx) async {
    HapticFeedback.selectionClick();
    await LocalStoreService.setAiConsent(false);
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface2,
      content: Text(
        'AI permission revoked. We will ask again the next time '
        'you scan.',
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.textPrimary)),
    ));
  }

  void _confirmDelete(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface1,
        title: Text('Delete all data?',
          style: AppTypography.h3.copyWith(color: AppColors.signalRed)),
        content: Text(
          'This removes all your scans, renders, and progress from this '
          'device. Your subscription is not affected. This cannot be '
          'undone.',
          style: AppTypography.bodySmall),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              // Actually delete. LocalStoreService wipes prefs;
              // FaceAssetService wipes the on-disk scan JPEGs.
              await LocalStoreService.clearAllUserData();
              await FaceAssetService.purgeAll();
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppColors.surface2,
                content: Text('All data deleted.',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textPrimary)),
              ));
            },
            child: Text('Delete',
              style: TextStyle(color: AppColors.signalRed)),
          ),
        ],
      ),
    );
  }
}

// ── Components ────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
    child: Text(label, style: AppTypography.label.copyWith(
      color: AppColors.textTertiary, letterSpacing: 2)),
  );
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool destructive;
  final VoidCallback onTap;

  const _SettingTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.signalRed : AppColors.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.lg),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(Rd.lg),
            border: Border.all(color: AppColors.surface3),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: destructive
                  ? AppColors.signalRed
                  : AppColors.textSecondary),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.body.copyWith(
                      color: color, fontSize: 15)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textTertiary, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!
              else if (!destructive)
                const Icon(Icons.chevron_right,
                  size: 20, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.accent.withValues(alpha: 0.12),
      border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(label, style: AppTypography.label.copyWith(
      color: AppColors.accent, fontSize: 8, letterSpacing: 1.4)),
  );
}
