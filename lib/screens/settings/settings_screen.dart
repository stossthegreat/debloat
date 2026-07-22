import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_review/in_app_review.dart';

import '../../config/dev_flags.dart';
import '../../services/analytics_service.dart';
import '../../services/face_asset_service.dart';
import '../../services/local_store_service.dart';
import '../../services/purchase_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Settings — every tile wired to a real action. Apple App Review
/// requires working Terms, Privacy Policy, Restore Purchases, and a
/// Manage Subscription path; all four are surfaced from here as well
/// as from the paywall.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    AnalyticsService.settingsScreenViewed();
  }

  @override
  Widget build(BuildContext context) {
    // v240 — settings rebuilt to bro's spec: clean single-list of
    // ONLY the settings that actually do something. Dead tiles
    // ("Rescan history → COMING SOON", "Export report → COMING SOON",
    // "Rizz from anywhere" duplicated by the Rizz tab, the marketing
    // blurbs "How we handle photos" + "How Debloat OS works") are gone.
    // "Rate us" sits at the top and deep-links to the App Store
    // listing via in_app_review's openStoreListing (uses the App
    // Store ID 6762532788 from
    // apps.apple.com/gb/app/mirrorly-looksmax-and-rizz/id6762532788).
    // Privacy + Terms drop to a single horizontal row at the bottom
    // matching the screenshot bro sent.
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header — "Settings" + close X ───────────────────────────
              const SizedBox(height: Sp.md),
              Row(
                children: [
                  Expanded(
                    child: Text('Settings',
                      style: AppTypography.h1.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 30, letterSpacing: -0.8,
                        fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textPrimary),
                    splashRadius: 22,
                  ),
                ],
              ).animate().fadeIn(duration: 360.ms),

              const SizedBox(height: Sp.lg),

              // v250 — tile list redesigned to match the reference
              // (LooksMax AI settings): single-line titles, colored
              // icons, no subtitles, no chevrons. The action / detail
              // each one used to spell out moves into the sheet or
              // toast the tile fires on tap, so the list reads as
              // tall clean rectangles like the reference image.

              // ── Get Debloat Pro — top of the list (red crown) ───────────
              if (!kBypassPaywall)
                _SettingTile(
                  icon: Icons.workspace_premium_rounded,
                  iconColor: AppColors.red,
                  title: 'Get Debloat Pro',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.push('/paywall', extra: {'force': true});
                  },
                ),

              // ── Rate us ─────────────────────────────────────────────────
              _SettingTile(
                icon: Icons.star_rounded,
                iconColor: AppColors.signalAmber,
                title: 'Rate us',
                onTap: () => _rateUs(context),
              ),

              // ── Restore + Manage subscription ──────────────────────────
              _SettingTile(
                icon: Icons.restore_rounded,
                title: 'Restore purchases',
                onTap: () => _restore(context),
              ),
              _SettingTile(
                icon: Icons.credit_card_rounded,
                title: 'Manage subscription',
                onTap: () => _manageSubscription(context),
              ),

              // ── AI render profile (male / female pick) ─────────────────
              _SettingTile(
                icon: Icons.style_outlined,
                title: 'AI render profile',
                onTap: () {
                  HapticFeedback.selectionClick();
                  context.push('/onboarding/gender',
                      extra: const {'fromSettings': true});
                },
              ),

              // ── Privacy / AI consent ────────────────────────────────────
              _SettingTile(
                icon: Icons.cloud_off_outlined,
                title: 'Revoke AI permission',
                onTap: () => _revokeAiConsent(context),
              ),

              // ── Contact ─────────────────────────────────────────────────
              _SettingTile(
                icon: Icons.mail_outline_rounded,
                title: 'Contact support',
                onTap: () => _copyEmail(context),
              ),

              // ── Delete all data — destructive, sits low ────────────────
              _SettingTile(
                icon: Icons.close_rounded,
                iconColor: AppColors.signalRed,
                title: 'Delete my account',
                destructive: true,
                onTap: () => _confirmDelete(context),
              ),

              const SizedBox(height: Sp.xl),

              // ── Footer: Privacy · Terms horizontal row ─────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      context.push('/privacy');
                    },
                    child: Text('Privacy',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 36),
                  TextButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      context.push('/terms');
                    },
                    child: Text('Terms',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                  ),
                ],
              ),

              const SizedBox(height: Sp.md),
              Center(
                child: Text(
                  '© 2026 Debloat OS',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiary.withValues(alpha: 0.6),
                    fontSize: 11),
                ),
              ),
              const SizedBox(height: Sp.xl),
            ],
          ),
        ),
      ),
    );
  }

  /// v240 — opens the live App Store listing using the App Store ID
  /// from the URL bro provided
  /// (apps.apple.com/gb/app/mirrorly-looksmax-and-rizz/id6762532788).
  /// On Android it falls back to the in-app review request which
  /// resolves the bundle id automatically. Either way the user lands
  /// where they can leave a star rating.
  Future<void> _rateUs(BuildContext ctx) async {
    HapticFeedback.selectionClick();
    // ignore: discarded_futures
    AnalyticsService.reviewNativeOpened();
    try {
      final reviewer = InAppReview.instance;
      if (Platform.isIOS) {
        await reviewer.openStoreListing(appStoreId: '6762532788');
      } else {
        if (await reviewer.isAvailable()) {
          await reviewer.requestReview();
        } else {
          await reviewer.openStoreListing();
        }
      }
    } catch (_) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: const Text("Couldn't open the App Store — try again."),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface2,
      ));
    }
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
          'Debloat Pro → Cancel subscription.\n\n'
          'Cancel at least 24 hours before renewal to avoid the next '
          'charge.'
        : 'Open Google Play → Profile → Payments & subscriptions → '
          'Subscriptions → Debloat Pro → Cancel subscription.\n\n'
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

  Widget _sheetHandle() => Container(
    width: 36, height: 4,
    margin: const EdgeInsets.only(bottom: Sp.lg),
    decoration: BoxDecoration(
      color: AppColors.surface3,
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Future<void> _copyEmail(BuildContext ctx) async {
    await Clipboard.setData(const ClipboardData(text: 'info@m2mb.co.uk'));
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: const Text('info@m2mb.co.uk — copied. Paste into your mail app.'),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface2,
    ));
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
              // FaceAssetService wipes the on-disk scan JPEGs
              // (GDPR Article 17 compliance).
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

/// v250 — settings rows redesigned to match bro's reference (LooksMax
/// AI settings screen). Light dark-grey rounded rectangles, colored
/// icon left, single-line title, no chevron, no subtitle by default.
/// Follows our style: AppColors.surface palette, optional red accent
/// on the icon, Debloat OS Inter typography.
///
/// `subtitle` is still accepted so the voice-cap tile and the email
/// tile can carry an extra line — but the default callsite passes
/// title only so the list reads clean and tall like the reference.
class _SettingTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool destructive;
  final VoidCallback onTap;

  const _SettingTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.iconColor,
    this.subtitle,
    this.trailing,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.signalRed : AppColors.textPrimary;
    final resolvedIconColor = iconColor ??
        (destructive ? AppColors.signalRed : AppColors.textPrimary);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: resolvedIconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.body.copyWith(
                      color: color, fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!, style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textTertiary, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

