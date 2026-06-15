import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_review/in_app_review.dart';

import '../../config/dev_flags.dart';
import '../../services/analytics_service.dart';
import '../../services/creator_mode_store.dart';
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
    // blurbs "How we handle photos" + "How ImHim works") are gone.
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

              // ── Get ImHim Pro — top of the list (red crown) ───────────
              if (!kBypassPaywall)
                _SettingTile(
                  icon: Icons.workspace_premium_rounded,
                  iconColor: AppColors.red,
                  title: 'Get ImHim Pro',
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

              // ── Usage tile — voice minutes this week ────────────────────
              const _VoiceCapTile(),

              // ── Glow-up style (gender pick) ────────────────────────────
              _SettingTile(
                icon: Icons.style_outlined,
                title: 'Glow-up style',
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
                  '© 2026 ImHim',
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
          'ImHim Pro → Cancel subscription.\n\n'
          'Cancel at least 24 hours before renewal to avoid the next '
          'charge.'
        : 'Open Google Play → Profile → Payments & subscriptions → '
          'Subscriptions → ImHim Pro → Cancel subscription.\n\n'
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
    'How ImHim works',
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

/// USAGE → Voice cap tile. Reads voiceMsThisWeek on build, renders the
/// remaining minutes against the 40-min monthly Pro ceiling. Tile is
/// always visible — for free users it surfaces the unused 40-minute
/// budget Pro unlocks (and routes to /paywall on tap so it doubles as
/// a soft upsell). Pro users get the live "X min left" readout so they
/// never wonder how much roleplay time they've spent.
class _VoiceCapTile extends StatefulWidget {
  const _VoiceCapTile();

  @override
  State<_VoiceCapTile> createState() => _VoiceCapTileState();
}

class _VoiceCapTileState extends State<_VoiceCapTile> {
  int _usedMs = 0;
  bool _pro   = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ms  = await LocalStoreService.voiceMsThisWeek();
    final pro = await LocalStoreService.isSubscribed();
    if (!mounted) return;
    setState(() {
      _usedMs = ms;
      _pro    = pro;
      _loaded = true;
    });
    // ignore: discarded_futures
    AnalyticsService.settingsVoiceCapViewed(
      usedMs: ms,
      capMs:  LocalStoreService.kVoiceMinutesPerWeek * 60 * 1000,
    );
  }

  String _fmt(int totalMs) {
    final s = (totalMs / 1000).floor();
    final m = (s / 60).floor();
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final capMs = LocalStoreService.kVoiceMinutesPerWeek * 60 * 1000;
    final remainingMs = (capMs - _usedMs).clamp(0, capMs);
    final pct = _loaded ? (_usedMs / capMs).clamp(0.0, 1.0) : 0.0;
    final overCap = _usedMs >= capMs;
    final color = overCap ? AppColors.signalRed : AppColors.accent;

    return _SettingTile(
      icon: Icons.mic_rounded,
      title: 'Roleplay voice — this week',
      subtitle: !_loaded
          ? 'Loading…'
          : _pro
              ? (overCap
                  ? 'Capped — resets Monday'
                  : '${_fmt(remainingMs)} left of '
                    '${LocalStoreService.kVoiceMinutesPerWeek}:00')
              : 'Pro unlocks ${LocalStoreService.kVoiceMinutesPerWeek}'
                ' minutes a week',
      trailing: SizedBox(
        width: 70,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_pro
                    ? '${_fmt(_usedMs)} / '
                      '${LocalStoreService.kVoiceMinutesPerWeek}:00'
                    : '0 / ${LocalStoreService.kVoiceMinutesPerWeek}:00',
                style: AppTypography.label.copyWith(
                  color: color,
                  fontSize: 11, letterSpacing: 0.6,
                  fontWeight: FontWeight.w900,
                )),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: _pro ? pct : 0.0,
                backgroundColor: AppColors.surface3,
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 3,
              ),
            ),
          ],
        ),
      ),
      onTap: () {
        HapticFeedback.selectionClick();
        if (!_pro) context.push('/paywall');
      },
    );
  }
}

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

/// v250 — settings rows redesigned to match bro's reference (LooksMax
/// AI settings screen). Light dark-grey rounded rectangles, colored
/// icon left, single-line title, no chevron, no subtitle by default.
/// Follows our style: AppColors.surface palette, optional red accent
/// on the icon, ImHim Inter typography.
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

// ═══════════════════════════════════════════════════════════════════════════
//  CREATOR tile — password-gated Lucien-unchained switch (Auralay graft)
// ═══════════════════════════════════════════════════════════════════════════
class _CreatorTile extends StatefulWidget {
  const _CreatorTile();
  @override
  State<_CreatorTile> createState() => _CreatorTileState();
}

class _CreatorTileState extends State<_CreatorTile> {
  bool _active = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final v = await CreatorModeStore.isActive();
    if (!mounted) return;
    setState(() {
      _active = v;
      _loading = false;
    });
  }

  Future<void> _promptUnlock() async {
    HapticFeedback.selectionClick();
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface1,
        title: Text('Unlock Creator',
          style: AppTypography.h3.copyWith(color: AppColors.red)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Switches Lucien, the Arena women, and the Council into the '
              'savage roasting persona. Free Flow runs unchained. Diablo '
              'content unlocks.\n\n'
              'Still policy-bounded server-side. Lock it again any time.',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary, height: 1.5)),
            const SizedBox(height: Sp.md),
            TextField(
              controller: controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimary, letterSpacing: 0.4,
                fontFeatures: const []),
              decoration: InputDecoration(
                hintText: 'PASSWORD',
                hintStyle: AppTypography.label.copyWith(
                  color: AppColors.textTertiary, letterSpacing: 2),
                filled: true,
                fillColor: AppColors.surface2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Rd.md),
                  borderSide: BorderSide(color: AppColors.divider)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Rd.md),
                  borderSide: BorderSide(color: AppColors.red)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final ok = await CreatorModeStore.tryActivate(controller.text);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop(ok);
            },
            child: Text('Unlock',
              style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (result == true) {
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface2,
        content: Text('Lucien · Unchained · Active',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.red, fontWeight: FontWeight.w700)),
      ));
    } else if (result == false && controller.text.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface2,
        content: Text('Wrong password.',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textPrimary)),
      ));
    }
  }

  Future<void> _lock() async {
    HapticFeedback.selectionClick();
    await CreatorModeStore.deactivate();
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface2,
      content: Text('Re-locked to store-safe persona.',
        style: AppTypography.bodySmall.copyWith(color: AppColors.textPrimary)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(height: 60);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _active ? _lock : _promptUnlock,
        borderRadius: BorderRadius.circular(Rd.lg),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(Rd.lg),
            border: Border.all(
              color: _active
                  ? AppColors.red.withValues(alpha: 0.55)
                  : AppColors.surface3,
              width: _active ? 1.2 : 1.0,
            ),
            boxShadow: _active
                ? [BoxShadow(
                    color: AppColors.red.withValues(alpha: 0.12),
                    blurRadius: 18, spreadRadius: 0)]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                _active
                    ? Icons.local_fire_department
                    : Icons.lock_outline_rounded,
                size: 22,
                color: _active ? AppColors.red : AppColors.textSecondary),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _active ? 'Lucien · Unchained' : 'Lucien · Locked',
                      style: AppTypography.body.copyWith(
                        color: _active ? AppColors.red : AppColors.textPrimary,
                        fontSize: 15,
                        fontStyle: _active ? FontStyle.italic : FontStyle.normal,
                        fontWeight: _active ? FontWeight.w800 : FontWeight.w600,
                      )),
                    const SizedBox(height: 2),
                    Text(
                      _active
                          ? 'Free Flow / Arena / Council in savage persona'
                          : 'Tap to enter the password and unleash',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textTertiary, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _active
                      ? AppColors.red.withValues(alpha: 0.18)
                      : AppColors.surface2,
                  border: Border.all(
                    color: _active
                        ? AppColors.red.withValues(alpha: 0.55)
                        : AppColors.divider),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(_active ? 'ACTIVE' : 'LOCKED',
                  style: AppTypography.label.copyWith(
                    color: _active ? AppColors.red : AppColors.textTertiary,
                    fontSize: 8.5, letterSpacing: 1.6,
                    fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
