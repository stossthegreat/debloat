import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../config/dev_flags.dart';
import '../../config/purchase_config.dart';
import '../../services/analytics_service.dart';
import '../../services/local_store_service.dart';
import '../../widgets/common/imhim_wordmark.dart';
import '../../services/purchase_service.dart';
import '../../services/review_prompt_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Mirrorly paywall.
///
/// Scrollable, close-X at top-left, real localized StoreKit prices
/// pulled through RevenueCat (never hardcoded), Apple 3.1.2 compliant
/// disclosure directly under the CTA, benefits bullet list moved
/// BELOW the CTA so the purchase button is always visible without
/// scrolling.
///
/// Routing contract:
///   - `/paywall`                                 → standalone entry (from
///                                                   onboarding, home chip)
///   - `/paywall` with extra `{afterPurchase: '/report', imageBytes,
///     geometry, extraImages}` → scan-gated entry. On successful
///     purchase we forward to /report with the captured scan data so
///     the user's MediaPipe work isn't lost.
///
/// Close X behaviour: if we can pop (arrived as a push), pop; else
/// go /home. Either way, abandoning the paywall does not re-trigger
/// onboarding because isOnboarded was already persisted.
class PaywallScreen extends StatefulWidget {
  /// Optional context forwarded from the scan gate. Kept opaque here —
  /// the keys the scan screen set get read back on purchase success.
  final Map<String, dynamic>? context;

  const PaywallScreen({super.key, this.context});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

enum _Tier { monthly, annual, rescue }

class _PaywallScreenState extends State<PaywallScreen> {
  _Tier _selected = _Tier.annual;
  PurchaseOfferings _offerings = PurchaseOfferings.empty();
  bool _purchasing = false;

  @override
  void initState() {
    super.initState();
    // Dev-flag bypass: auto-redirect back UNLESS the caller passed
    // `force: true` in the extras. That flag is how the home-header
    // upgrade chip opens the paywall for manual preview/testing — every
    // OTHER path (post-scan gate, onboarding end, stale deep link)
    // bounces straight back so the user stays in-flow.
    final ctx   = widget.context ?? const <String, dynamic>{};
    final force = ctx['force'] == true;
    if (kBypassPaywall && !force) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final after = ctx['afterPurchase'] as String?;
        if (after != null && ctx.isNotEmpty) {
          context.go(after, extra: ctx);
        } else {
          context.go('/home');
        }
      });
      return;
    }
    AnalyticsService.paywallShown(
      (widget.context?['afterPurchase'] as String?) ?? 'standalone');
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    final off = await PurchaseService.loadOfferings();
    if (!mounted) return;
    setState(() => _offerings = off);
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  PRICE HELPERS — everything the user sees as currency comes from
  //  the StoreKit / Play Billing SDK via RevenueCat. Never hardcoded.
  //
  //  Exception: under kBypassPaywall we fall back to visual-only
  //  placeholder numbers so the paywall can be previewed before
  //  RevenueCat keys are pasted. The moment the SDK returns a real
  //  package these placeholders are ignored and the store price wins —
  //  so a release build (kBypassPaywall = false) can NEVER ship
  //  hardcoded prices, even if the offering is misconfigured.
  // ─────────────────────────────────────────────────────────────────────────

  /// Visual-only placeholder used while RevenueCat hasn't returned a
  /// real Offering. NEVER show invented hardcoded numbers — show a
  /// dash so the user (and reviewers) immediately see "store not
  /// loaded yet" instead of a fake price. Real RC-delivered prices
  /// replace this dash the moment a Package arrives.
  static const _placeholderDash = '—';

  String _priceFor(_Tier t) {
    final pkg = _packageFor(t);
    if (pkg != null) return pkg.storeProduct.priceString;
    // No live Package yet → dash, never an invented number.
    return _placeholderDash;
  }

  /// Monthly equivalent for the annual plan — computed from the real
  /// annual price divided by 12 in the SAME currency the store returned.
  /// If store returned £89.99, this is £7.50 etc.
  String _perMonthForAnnual() {
    final annual = _offerings.annual;
    if (annual != null) {
      final p = annual.storeProduct;
      final perMonth = p.price / 12.0;
      return _formatPrice(perMonth, p.currencyCode, p.priceString);
    }
    // No Annual Package loaded → dash. Real per-month derived from
    // the actual store price once RC delivers it.
    return _placeholderDash;
  }

  /// Format with the same currency symbol the store used — we steal
  /// the non-digit prefix off `priceString` so we match whatever the
  /// user's locale shows (£, $, €, ₹, kr, etc.) without having to keep
  /// a currency table.
  String _formatPrice(double amount, String currencyCode, String example) {
    final symbolMatch = RegExp(r'^[^\d,\.\-]+').firstMatch(example);
    final symbol = symbolMatch?.group(0) ?? (currencyCode.isNotEmpty ? '$currencyCode ' : '');
    return '$symbol${amount.toStringAsFixed(2)}';
  }

  Package? _packageFor(_Tier t) => switch (t) {
    _Tier.monthly => _offerings.monthly,
    _Tier.annual  => _offerings.annual,
    _Tier.rescue  => _offerings.rescue,
  };

  /// The rescue one-time IAP is only configured on the Play Store
  /// (App Store Connect rescue product is "Not found" in RevenueCat
  /// per the dashboard). Hide the rescue card on iOS so users don't
  /// tap a permanently-empty third tile.
  bool get _showRescueCard => Platform.isAndroid;

  // ─────────────────────────────────────────────────────────────────────────
  //  ACTIONS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _buy() async {
    if (_purchasing) return;
    final pkg = _packageFor(_selected);
    if (pkg == null) {
      // No live Package on this platform — almost always Android, where
      // Play Billing / RevenueCat hasn't returned an Offering. Run the
      // diagnostic so the user sees exactly what RC saw on this device
      // (which Offering is current, which packages it has, which
      // entitlements are active) instead of a generic "store
      // unavailable" with zero info.
      HapticFeedback.mediumImpact();
      setState(() => _purchasing = true);
      final diag = await PurchaseService.diagnose();
      if (!mounted) return;
      setState(() => _purchasing = false);
      _showDiagnostic(diag);
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _purchasing = true);

    final outcome = await PurchaseService.purchase(pkg);

    if (!mounted) return;
    setState(() => _purchasing = false);

    switch (outcome) {
      case PurchaseOutcome.success:
        await LocalStoreService.setOnboarded(true);
        if (!mounted) return;
        _forwardOnSuccess();
        break;

      case PurchaseOutcome.cancelled:
        // Silent — user backed out intentionally, no toast spam.
        break;

      case PurchaseOutcome.noPriorPurchases:
        _snack('No previous purchases found.');
        break;

      case PurchaseOutcome.notConfigured:
        // Dev stub — no RC keys yet. Fall back to the pre-RC stub so
        // the dev flow still lets you see /home.
        await LocalStoreService.setSubscribed(true);
        await LocalStoreService.setOnboarded(true);
        if (mounted) _forwardOnSuccess();
        break;

      case PurchaseOutcome.error:
        // Show the actual cause from RevenueCat so the user (and we, in
        // bug reports) know whether Play Billing said "product
        // unavailable", "billing service disconnected", "sideloaded
        // APK can't purchase", etc. — instead of the old generic
        // message that hid every Android-side cause.
        final detail = PurchaseService.lastErrorMessage;
        _snack(detail != null && detail.isNotEmpty
            ? detail
            : 'Purchase could not complete. Please try again.');
        break;
    }
  }

  Future<void> _restore() async {
    HapticFeedback.selectionClick();
    final outcome = await PurchaseService.restore();
    if (!mounted) return;
    switch (outcome) {
      case PurchaseOutcome.success:
        _snack('Subscription restored.');
        if (mounted) _forwardOnSuccess();
        break;
      case PurchaseOutcome.noPriorPurchases:
        _snack('No previous purchases found.');
        break;
      case PurchaseOutcome.notConfigured:
        _snack('Store not yet configured.');
        break;
      case PurchaseOutcome.cancelled:
      case PurchaseOutcome.error:
        _snack('Could not restore purchases.');
        break;
    }
  }

  void _forwardOnSuccess() {
    final ctx = widget.context;
    // Scan-gated entry: forward to /report with the captured scan data
    // so the user's MediaPipe work isn't thrown away.
    if (ctx != null && ctx['afterPurchase'] == '/report') {
      context.go('/report', extra: {
        'imageBytes':  ctx['imageBytes'],
        'geometry':    ctx['geometry'],
        'extraImages': ctx['extraImages'] ?? const <dynamic>[],
      });
    } else {
      context.go('/home');
    }
    // Bro v7: "the rating prompt should show after our wow moments
    // after a conversion." THIS is the wow moment. We've just routed
    // the user to /report or /home; ReviewPromptService will let the
    // destination's first paint settle (1.4s) then slide the 5-star
    // dialog over it. One-prompt-per-device ceiling means a user who
    // already saw the triple-milestone version won't get re-asked.
    //
    // After the context.go call so the destination is mounted by the
    // time the dialog reads the new BuildContext via root navigator.
    // ignore: discarded_futures
    ReviewPromptService.maybePromptAfterPurchase(context);
  }

  void _close() {
    HapticFeedback.selectionClick();
    AnalyticsService.paywallDismissed(
      (widget.context?['afterPurchase'] as String?) ?? 'standalone');
    // If we arrived as a push, pop returns to whatever was underneath
    // (home, scan, etc). If there's nothing to pop (launched directly
    // from onboarding / splash), land on home. Onboarding is already
    // persisted-complete so they won't loop back.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.black,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Show the RevenueCat diagnostic in a scrollable dialog. Built for
  /// when "iOS works but Android paywall buttons do nothing" — taps the
  /// SDK on this device, reports back current offering id, package
  /// list, and active entitlements, so we know whether Android is
  /// missing the Offering, missing packages, or has products with the
  /// wrong identifiers.
  void _showDiagnostic(String diag) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text('Store status',
          style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: SelectableText(diag,
            style: const TextStyle(
              color: Colors.white, fontSize: 12,
              fontFamily: 'monospace', height: 1.4)),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: diag));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Copied. Paste into chat for help.')));
            },
            child: const Text('COPY'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // CTA is always tappable. If RC delivered a real Package the buy
    // path runs the live store sheet; otherwise PurchaseService.purchase
    // returns notConfigured and the paywall falls back to setting the
    // local subscribed flag (forwards to /report with the scan payload).
    // This guarantees the CTA never sits permanently grey on a build
    // where the RevenueCat Offering hasn't been published yet — same
    // pattern users expect from the bypass mode while iterating.
    final canBuy = true;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              // v232 — top padding back to 56 (was 36 in v229a). Bro
              // wants the CTA "back where it was, lower down, still
              // fully visible but lower." Restoring the v228 padding
              // pushes the whole stack down so the CTA lands at the
              // pre-glowup-lift position.
              padding: const EdgeInsets.fromLTRB(22, 56, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. v228 paywall — dropped the 80×80 app-icon hero
                  //    + ImHimWordmark + Playfair-italic subhead per
                  //    bro: "big converters don't have logos and app
                  //    names on the paywall, it distracts. Straight
                  //    nice header good size underlined, then bullets
                  //    under it to the left in smaller writing."
                  //
                  //    v228a — same shape, glowup-aware copy. The
                  //    glowup variant catches the user at the
                  //    post-scan emotional peak: "you saw the verdict,
                  //    here's exactly how to gain those points."
                  //    Different header + different bullets but the
                  //    layout stays identical.
                  _Header(glowup: _isGlowupVariant),
                  // v232 — header → bullets gap pushed from 20 → 28
                  // to balance the bigger underlined hero. Bullets
                  // themselves now run 22px apart (was 12) so the
                  // four-line stack fills the available height.
                  const SizedBox(height: 28),
                  _Bullets(glowup: _isGlowupVariant),

                  const SizedBox(height: 30),

                  // 3. Price cards — real localized prices. Three on
                  //    Android (Monthly / Annual / Rescue one-time),
                  //    two on iOS where the rescue product isn't yet
                  //    approved in App Store Connect.
                  //
                  //    Google Play Subscriptions Policy compliance:
                  //    each card MUST clearly state how often the
                  //    user will be charged (monthly vs yearly) and
                  //    whether the subscription auto-renews. The
                  //    annual card therefore shows "billed yearly"
                  //    as primary cadence, with the monthly-equiv
                  //    only as a small parenthetical — never the
                  //    headline number.
                  // 3. Price cards — real localized prices. Three on
                  //    Android (Monthly / Annual / Rescue one-time),
                  //    two on iOS where the rescue product isn't yet
                  //    approved in App Store Connect.
                  //
                  //    Google Play Subscriptions Policy compliance:
                  //    each card MUST clearly state how often the
                  //    user will be charged (monthly vs yearly) and
                  //    whether the subscription auto-renews. The
                  //    annual card therefore shows "billed yearly"
                  //    as primary cadence, with the monthly-equiv
                  //    only as a small parenthetical — never the
                  //    headline number.
                  //
                  // v227 — Weekly card was wired in v224 but parked
                  // here pending final paywall structure decision.
                  // Restoring 2-card iOS / 3-card Android layout.
                  Row(
                    children: [
                      Expanded(child: _PriceCard(
                        title: 'MONTHLY',
                        price: _priceFor(_Tier.monthly),
                        cadence: 'Billed monthly',
                        footnote: 'Auto-renews until cancelled',
                        selected: _selected == _Tier.monthly,
                        available: true,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selected = _Tier.monthly);
                        },
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: _PriceCard(
                        title: 'ANNUAL',
                        price: _priceFor(_Tier.annual),
                        cadence: 'Billed yearly (${_perMonthForAnnual()}/mo)',
                        footnote: 'Auto-renews until cancelled',
                        badge: 'BEST VALUE',
                        selected: _selected == _Tier.annual,
                        available: true,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selected = _Tier.annual);
                        },
                      )),
                      if (_showRescueCard) ...[
                        const SizedBox(width: 8),
                        Expanded(child: _PriceCard(
                          title: 'RESCUE',
                          price: _priceFor(_Tier.rescue),
                          cadence: 'One-time · 20 renders',
                          footnote: 'No subscription',
                          selected: _selected == _Tier.rescue,
                          available: true,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selected = _Tier.rescue);
                          },
                        )),
                      ],
                    ],
                  ).animate().fadeIn(delay: 600.ms, duration: 400.ms),

                  const SizedBox(height: 14),

                  // 4. CTA — sits high on the screen; disclosure sits
                  //    immediately below, benefits under that.
                  SizedBox(
                    width: double.infinity, height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canBuy ? AppColors.red : AppColors.surface3,
                        disabledBackgroundColor: AppColors.surface3,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: (canBuy && !_purchasing) ? _buy : null,
                      child: _purchasing
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.white)),
                            )
                          : Text(
                              _ctaLabel(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15, letterSpacing: 2.4,
                              ),
                            ),
                    ),
                  ).animate().fadeIn(delay: 720.ms, duration: 400.ms),

                  const SizedBox(height: 10),

                  // 5a. Short headline summary — Google Play
                  //     Subscriptions Policy requires the price, the
                  //     billing frequency, the auto-renewal terms,
                  //     and the "subscription required" notice to be
                  //     called out clearly in the offer (not buried
                  //     in fine print). This single line carries
                  //     all four facts in plain English; the long
                  //     disclosure below adds the cancellation path.
                  _summaryLine(),

                  const SizedBox(height: 8),

                  // 5b. Long-form disclosure — Apple 3.1.2 compliant.
                  //     Covers price, cadence, renewal, cancellation
                  //     in full sentences for each tier.
                  _disclosure(),

                  const SizedBox(height: 16),

                  // 6. Benefits panel — NOW UNDER the CTA per user
                  //    feedback. Still per-tier, still spells out what
                  //    each tier actually delivers.
                  _BenefitsPanel(bullets: _bulletsFor(_selected)),

                  const SizedBox(height: 16),

                  // 7. Legal + restore row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _LinkButton(
                        label: 'TERMS',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          context.push('/terms');
                        },
                      ),
                      _LinkButton(
                        label: 'PRIVACY',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          context.push('/privacy');
                        },
                      ),
                      _LinkButton(label: 'RESTORE', onTap: _restore),
                    ],
                  ),

                  const SizedBox(height: 18),
                ],
              ),
            ),

            // 8. Close X — top-left. Always visible, always works.
            Positioned(
              left: 10, top: 10,
              child: _CloseX(onTap: _close),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero() {
    return Column(
      children: [
        Center(
          child: Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.red.withValues(alpha: 0.35),
                  blurRadius: 24),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/icons/appstore.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        ).animate()
          .fadeIn(duration: 460.ms)
          .scale(begin: const Offset(0.85, 0.85),
            curve: Curves.easeOutBack, duration: 540.ms),
        const SizedBox(height: 10),
        const Center(
          child: ImHimWordmark(fontSize: 38, letterSpacing: -1.2),
        ).animate().fadeIn(delay: 180.ms, duration: 360.ms),
        const SizedBox(height: 4),
        Text(_isGlowupVariant
              ? 'Your glow-up is ready.'
              : 'Become the guy who owns every room',
          textAlign: TextAlign.center,
          style: AppTypography.h1.copyWith(
            color: Colors.white,
            fontSize: 20, letterSpacing: -0.3,
            height: 1.2,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w800,
          ),
        ).animate().fadeIn(delay: 240.ms, duration: 360.ms),
      ],
    );
  }

  /// Bro v3: "On the CTA button put BECOME UNAVOIDABLE." The price
  /// + cadence still live on the package cards directly above and in
  /// the legally-required summary line directly below, so dropping
  /// them from the button itself doesn't violate Google Play / Apple
  /// disclosure rules.
  /// True when the user landed here from the post-scan locked teaser
  /// — any 'source' starting with 'glowup'. Drives a different
  /// subtitle ("Your glow-up is ready."), the four-line glow-up
  /// pitch, and a "UNLOCK PRO" CTA label.
  bool get _isGlowupVariant {
    final src = (widget.context?['source'] as String?)?.toLowerCase() ?? '';
    return src.startsWith('glowup');
  }

  String _ctaLabel() =>
      _isGlowupVariant ? 'UNLOCK PRO' : 'BECOME UNAVOIDABLE';

  /// Short above-the-fold summary required by the Google Play
  /// Subscriptions Policy. Must clearly state, in one line:
  ///   - the exact price
  ///   - how often the user will be charged (monthly vs yearly)
  ///   - that the subscription auto-renews
  ///   - that a ImHim Pro subscription is required to use the
  ///     scan / advisor features
  /// Sits directly under the CTA so it's impossible to miss.
  Widget _summaryLine() {
    final price = _priceFor(_selected);
    String text;
    switch (_selected) {
      case _Tier.monthly:
        text = '$price billed monthly. Auto-renews until cancelled. '
               'ImHim Pro subscription required for scans, AI '
               'renders, streaks, AI roleplay, and all rizz features.';
        break;
      case _Tier.annual:
        text = '$price billed once per year (${_perMonthForAnnual()}/'
               'mo equivalent). Auto-renews yearly until cancelled. '
               'ImHim Pro subscription required for scans, AI '
               'renders, streaks, AI roleplay, and all rizz features.';
        break;
      case _Tier.rescue:
        text = '$price one-time charge. NOT a subscription. '
               'Grants 20 AI render credits. An active ImHim Pro '
               'subscription is required to perform the underlying '
               'scans.';
        break;
    }
    return Text(
      text,
      textAlign: TextAlign.center,
      style: AppTypography.bodySmall.copyWith(
        color: Colors.white,
        fontSize: 11.5, height: 1.45,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  /// Apple 3.1.2 compliant long-form disclosure.
  /// Must contain: title/service, length, price, auto-renewal,
  /// cancellation path, links to Terms + Privacy.
  Widget _disclosure() {
    final price  = _priceFor(_selected);
    final perMo  = _perMonthForAnnual();
    // App Store guideline 2.3.10 — the iOS binary may not contain
    // user-facing references to other platforms' billing systems.
    // Swap "App Store / Apple ID" on iOS, "Google Play" on Android.
    final storeAccount = Platform.isIOS ? 'App Store account'
                                        : 'Google Play account';

    String text;
    switch (_selected) {
      case _Tier.monthly:
        text = 'ImHim Pro — monthly subscription. Your payment of '
               '$price will be charged to your $storeAccount at '
               'confirmation of purchase. The subscription '
               'automatically renews each month for $price unless you '
               'cancel at least 24 hours before the end of the current '
               'period. Your account will be charged for renewal '
               'within 24 hours of the period ending. You can manage '
               'or cancel your subscription any time in your account '
               'settings. Uninstalling the app does NOT cancel the '
               'subscription.';
        break;
      case _Tier.annual:
        text = 'ImHim Pro — annual subscription. Your payment of '
               '$price (equivalent to $perMo per month) will be '
               'charged to your $storeAccount at confirmation of '
               'purchase. The subscription automatically renews each '
               'year for $price unless you cancel at least 24 hours '
               'before the end of the current period. Your account '
               'will be charged for renewal within 24 hours of the '
               'period ending. You can manage or cancel your '
               'subscription any time in your account settings. '
               'Uninstalling the app does NOT cancel the subscription.';
        break;
      case _Tier.rescue:
        // Rescue is Android-only today (_showRescueCard gates it),
        // but route store wording through the same Platform.isIOS
        // helper as the subs above — defence-in-depth so if the
        // iOS rescue SKU ever lights up the copy stays clean.
        text = 'ImHim Rescue Pack — one-time purchase of $price. '
               'NOT a subscription. Your $storeAccount will be '
               'charged $price at confirmation of purchase, once. No '
               'auto-renewal. Each credit entitles you to one '
               'AI-rendered "after" image. Credits do not expire and '
               'are non-refundable and non-transferable.';
        break;
    }

    return Text(
      text,
      textAlign: TextAlign.center,
      style: AppTypography.bodySmall.copyWith(
        color: AppColors.textTertiary,
        fontSize: 10.5, height: 1.5,
      ),
    );
  }

  List<String> _bulletsFor(_Tier t) {
    // App Store guideline 2.3.10 — strip "Google Play" from the
    // iOS binary. Cancel-instructions tell the user where to go;
    // the right answer differs per platform.
    final cancelLine = Platform.isIOS
        ? 'Cancel anytime in App Store settings'
        : 'Cancel anytime in Google Play settings';
    switch (t) {
      case _Tier.monthly:
      case _Tier.annual:
        // Bro v5: monthly/annual share the same monthly entitlement
        // ceiling. 40 min of voice every month regardless of tier.
        // Rizz Chat unlimited. Rizz screenshots vision-powered.
        return [
          '2 scans per week',
          '10 AI-rendered images per month',
          '40 minutes of Live AI roleplay every month',
          'Unlimited Rizz Chat — ask anything, every day',
          'Unlimited rizz screenshot replies',
          'Streaks + 60-day protocols — Skin, Jaw, Debloat, Hair',
          'The Mirror — unlimited chat advice',
          'Two-score rating — geometry + honest-looks (Vision)',
          cancelLine,
        ];
      case _Tier.rescue:
        return const [
          '20 AI-rendered images (one per credit)',
          'No subscription, no recurring charge',
          'Credits never expire',
          'Non-refundable, non-transferable',
          'Requires an active ImHim Pro subscription for scans',
        ];
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  SUB-WIDGETS
// ══════════════════════════════════════════════════════════════════════════

class _CloseX extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseX({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22), width: 0.8),
          ),
          child: const Icon(Icons.close_rounded,
            size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

// v228 paywall — replaces the logo-image + wordmark + italic Playfair
// subhead hero block. Clean white Inter title sized so it commands the
// top of the screen, a thin red rule under it as the underline bro
// asked for, then a single subhead line, then the bullets via
// _Bullets. No red body text, no logos, no app-name. Sits at the same
// vertical position the old _hero() did so the CTA + price cards
// underneath don't move.
class _Header extends StatelessWidget {
  /// True when the paywall was opened from the post-scan locked
  /// teaser — every `source` that starts with `glowup`. Swaps in a
  /// promise that meets the user at the emotional peak right after
  /// they saw their scan score get teased: "your glow-up is ready."
  final bool glowup;
  const _Header({this.glowup = false});

  @override
  Widget build(BuildContext context) {
    // v232 — old "Become the guy that owns every room." line is gone.
    // Bro: "take the header off. The header is the line underneath
    // it — Looks get attention. Game keeps it. Way bigger writing,
    // underlined. No red lines. That's the hero."
    //
    // Now ONE line. Hero text, way bigger than the old subhead,
    // text-decoration underline (not a separate red bar), Inter w800
    // white. Glowup variant keeps its own hero line.
    final headline = glowup
        ? 'Your glow-up is ready.'
        : 'Looks get attention. Game keeps it.';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        headline,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 32, height: 1.18,
          letterSpacing: -0.6,
          fontWeight: FontWeight.w800,
        ),
      ).animate().fadeIn(duration: 380.ms)
        .slideY(begin: 0.04, end: 0, curve: Curves.easeOut),
    );
  }
}

/// Four left-aligned outcome bullets. Inter, white, smaller than the
/// header, generous line spacing. The bullet glyph is the red app
/// accent so the eye scans straight down the list.
///
/// v232 — bullet spacing pushed from 12 → 22 per bro: "better space
/// between the bullet points so it fills space perfectly." With the
/// old big header gone the bullet stack needs to carry more vertical
/// presence; the extra 10px per gap balances the page.
class _Bullets extends StatelessWidget {
  final bool glowup;
  const _Bullets({this.glowup = false});

  static const _items = <String>[
    'Discover the fastest gains for your face.',
    'See your AI glow-up before you build it.',
    'Practice real conversations with pushback.',
    'Get coached until it becomes natural.',
  ];

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7, right: 12),
                child: Container(
                  width: 6, height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.red, shape: BoxShape.circle),
                ),
              ),
              Expanded(
                child: Text(
                  items[i],
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 16, height: 1.4,
                    letterSpacing: 0.1,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ).animate(delay: Duration(milliseconds: 280 + i * 80))
            .fadeIn(duration: 360.ms)
            .slideX(begin: -0.03, end: 0, curve: Curves.easeOut),
        ],
      ],
    );
  }
}

/// The paywall pitch. Three outcome lines under the wordmark.
/// Bro v3 copy: "Looks get you noticed / Game makes her fall /
/// Mirrorly gives you both." Drops the old PRESENCE line — the
/// product is two halves now (Looks + Game), and the third line
/// is the synthesis that names the brand as the answer.
///
/// Bro v6 — when [glowup] is true, the pitch swaps in the four
/// post-scan conversion lines instead. Same vertical real estate;
/// the per-line font size + spacing shrinks proportionally so the
/// paywall doesn't grow.
class _Pitch extends StatelessWidget {
  final bool glowup;
  const _Pitch({this.glowup = false});

  @override
  Widget build(BuildContext context) {
    if (glowup) {
      // Four full-sentence lines — no LEAD/TAIL split. Italic Playfair
      // for the editorial register that matches the score reveal the
      // user just came from.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _full('AI shows you your future look.',     delayMs: 320),
          const SizedBox(height: 12),
          _full('Discover exactly what to fix.',      delayMs: 420),
          const SizedBox(height: 12),
          _full('Practice roleplay until it lands.',  delayMs: 520),
          const SizedBox(height: 12),
          _full('Never run out of things to say.',    delayMs: 620),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _line('LOOKS',    'GET YOU NOTICED.',    delayMs: 320),
        const SizedBox(height: 18),
        _line('PRESENCE', 'HOLDS ATTENTION.',    delayMs: 460),
        const SizedBox(height: 18),
        _line('GAME',     'ALWAYS DECIDES.',     delayMs: 600),
      ],
    );
  }

  Widget _full(String text, {required int delayMs}) {
    return Text(text,
      style: GoogleFonts.playfairDisplay(
        color: Colors.white,
        fontSize: 20, height: 1.25,
        letterSpacing: -0.3,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w700,
      ),
    ).animate(delay: Duration(milliseconds: delayMs))
      .fadeIn(duration: 420.ms)
      .slideX(begin: -0.04, end: 0, curve: Curves.easeOut);
  }

  Widget _line(String lead, String tail, {required int delayMs}) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$lead ',
            style: AppTypography.h1.copyWith(
              color: AppColors.red,
              fontSize: 26, letterSpacing: 0.6,
              fontWeight: FontWeight.w900, height: 1.15,
            ),
          ),
          TextSpan(
            text: tail,
            style: AppTypography.h1.copyWith(
              color: Colors.white,
              fontSize: 26, letterSpacing: 0.4,
              fontWeight: FontWeight.w800, height: 1.15,
            ),
          ),
        ],
      ),
    ).animate(delay: Duration(milliseconds: delayMs))
      .fadeIn(duration: 420.ms)
      .slideX(begin: -0.04, end: 0, curve: Curves.easeOut);
  }
}

class _Point extends StatelessWidget {
  final String n, headline, body;
  const _Point({required this.n, required this.headline, required this.body});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 28,
          child: Text(n,
            style: AppTypography.h1.copyWith(
              color: AppColors.red, fontSize: 30,
              fontWeight: FontWeight.w900, height: 1, letterSpacing: -0.6,
              fontStyle: FontStyle.italic,
            )),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(headline,
                style: AppTypography.label.copyWith(
                  color: Colors.white,
                  fontSize: 13.5, letterSpacing: 1.6,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                )),
              const SizedBox(height: 5),
              Text(body,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 14, height: 1.45,
                  fontWeight: FontWeight.w500,
                )),
            ],
          ),
        ),
      ],
    ).animate(delay: Duration(milliseconds: 320 + int.parse(n) * 80))
      .fadeIn(duration: 400.ms)
      .slideX(begin: -0.04, end: 0, curve: Curves.easeOut);
  }
}

class _PriceCard extends StatelessWidget {
  final String title, price, cadence, footnote;
  final String? badge;
  final bool selected;
  final bool available;
  final VoidCallback onTap;

  const _PriceCard({
    required this.title,
    required this.price,
    required this.cadence,
    required this.footnote,
    required this.selected,
    required this.available,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? AppColors.red : Colors.white24;
    final priceColor = selected
      ? AppColors.red
      : (available ? Colors.white : Colors.white54);
    return GestureDetector(
      onTap: available ? onTap : null,
      child: AnimatedContainer(
        duration: 180.ms,
        height: 140,
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.redGlow : Colors.transparent,
          border: Border.all(color: borderColor, width: selected ? 1.5 : 0.8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(title,
                    style: AppTypography.label.copyWith(
                      color: Colors.white,
                      fontSize: 9, letterSpacing: 1.6,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(badge!,
                      style: const TextStyle(
                        color: Colors.white, fontSize: 7,
                        letterSpacing: 0.6, fontWeight: FontWeight.w900,
                      )),
                  ),
              ],
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(price,
                style: AppTypography.display.copyWith(
                  color: priceColor,
                  fontSize: 26, height: 1, letterSpacing: -1.0,
                  fontWeight: FontWeight.w800,
                )),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cadence,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 9.5, fontWeight: FontWeight.w600, height: 1.2,
                  ),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(footnote,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 8.5, fontWeight: FontWeight.w500, height: 1.2,
                  ),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BenefitsPanel extends StatelessWidget {
  final List<String> bullets;
  const _BenefitsPanel({required this.bullets});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('WHAT YOU GET',
            style: AppTypography.label.copyWith(
              color: AppColors.red,
              fontSize: 9, letterSpacing: 2.6,
              fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (var i = 0; i < bullets.length; i++) ...[
            _BenefitRow(bullet: bullets[i]),
            if (i != bullets.length - 1) const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final String bullet;
  const _BenefitRow({required this.bullet});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 8),
          child: Container(
            width: 4, height: 4,
            decoration: const BoxDecoration(
              color: AppColors.red, shape: BoxShape.circle),
          ),
        ),
        Expanded(
          child: Text(bullet,
            style: AppTypography.bodySmall.copyWith(
              color: Colors.white,
              fontSize: 12.5, height: 1.4,
              fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}

class _LinkButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _LinkButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text(label,
        style: TextStyle(
          color: AppColors.textTertiary, fontSize: 10,
          letterSpacing: 1.5, fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
