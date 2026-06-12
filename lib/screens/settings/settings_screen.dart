import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../config/dev_flags.dart';
import '../../services/creator_mode_store.dart';
import '../../services/face_asset_service.dart';
import '../../services/local_store_service.dart';
import '../../services/purchase_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/common/imhim_wordmark.dart';

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
                        child: Text('IH',
                          style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800,
                            color: AppColors.accent, letterSpacing: -0.5)),
                      ),
                    ),
                    const SizedBox(height: Sp.sm),
                    const ImHimWordmark(fontSize: 30, letterSpacing: -0.8),
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
                  title: 'ImHim Pro',
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

              // ── USAGE ────────────────────────────────────────────────────
              // Live readout of this month's Pro voice-time allowance
              // (40 minutes of Free Flow / Council per calendar month,
              // resets on the 1st). Reads voiceMsThisMonth straight
              // from prefs each build, so a long roleplay session is
              // reflected the moment the user returns here.
              _SectionHeader('USAGE'),
              const _VoiceCapTile(),

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
                subtitle: 'How ImHim works, what you agree to',
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

              // ── CREATOR ───────────────────────────────────────────────────
              // The single master switch for the Lucien-unchained pipeline
              // grafted from Auralay. Password-gated, persisted via
              // [CreatorModeStore]. Live state shown so the user always
              // knows whether Free Flow / Arena / Council are running the
              // store-safe persona or the savage roasting persona. Still
              // policy-bounded server-side regardless.
              _SectionHeader('CREATOR'),
              const _CreatorTile(),

              const SizedBox(height: Sp.lg),

              // ── ABOUT ─────────────────────────────────────────────────────
              _SectionHeader('ABOUT'),
              _SettingTile(
                icon: Icons.description_outlined,
                title: 'How ImHim works',
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
                  '© 2026 ImHim',
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

/// USAGE → Voice cap tile. Reads voiceMsThisMonth on build, renders the
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
    final ms  = await LocalStoreService.voiceMsThisMonth();
    final pro = await LocalStoreService.isSubscribed();
    if (!mounted) return;
    setState(() {
      _usedMs = ms;
      _pro    = pro;
      _loaded = true;
    });
  }

  String _fmt(int totalMs) {
    final s = (totalMs / 1000).floor();
    final m = (s / 60).floor();
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final capMs = LocalStoreService.kVoiceMinutesPerMonth * 60 * 1000;
    final remainingMs = (capMs - _usedMs).clamp(0, capMs);
    final pct = _loaded ? (_usedMs / capMs).clamp(0.0, 1.0) : 0.0;
    final overCap = _usedMs >= capMs;
    final color = overCap ? AppColors.signalRed : AppColors.accent;

    return _SettingTile(
      icon: Icons.mic_rounded,
      title: 'Roleplay voice — monthly',
      subtitle: !_loaded
          ? 'Loading…'
          : _pro
              ? (overCap
                  ? 'Capped — resets on the 1st'
                  : '${_fmt(remainingMs)} left of '
                    '${LocalStoreService.kVoiceMinutesPerMonth}:00')
              : 'Pro unlocks ${LocalStoreService.kVoiceMinutesPerMonth}'
                ' minutes a month',
      trailing: SizedBox(
        width: 70,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_pro
                    ? '${_fmt(_usedMs)} / '
                      '${LocalStoreService.kVoiceMinutesPerMonth}:00'
                    : '0 / ${LocalStoreService.kVoiceMinutesPerMonth}:00',
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
