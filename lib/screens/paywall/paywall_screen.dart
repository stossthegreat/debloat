import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../config/dev_flags.dart';
import '../../config/purchase_config.dart';
import '../../services/local_store_service.dart';
import '../../services/purchase_service.dart';
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

enum _Tier { monthly, annual, credits }

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

  /// Visual-only placeholder prices used under kBypassPaywall while
  /// RevenueCat isn't configured. Flipped off for release.
  static const _placeholderMonthly = r'$9.99';
  static const _placeholderAnnual  = r'$49.99';
  static const _placeholderCredits = r'$14.99';

  String _priceFor(_Tier t) {
    final pkg = _packageFor(t);
    if (pkg != null) return pkg.storeProduct.priceString;
    if (kBypassPaywall) {
      switch (t) {
        case _Tier.monthly: return _placeholderMonthly;
        case _Tier.annual:  return _placeholderAnnual;
        case _Tier.credits: return _placeholderCredits;
      }
    }
    return '—';
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
    // Placeholder: $49.99 / 12 ≈ $4.17
    if (kBypassPaywall) return r'$4.17';
    return '—';
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
    _Tier.credits => _offerings.credits,
  };

  // ─────────────────────────────────────────────────────────────────────────
  //  ACTIONS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _buy() async {
    if (_purchasing) return;
    final pkg = _packageFor(_selected);
    if (pkg == null) {
      // Configure-state safety net — in production the CTA is disabled
      // when no package is available, so this shouldn't fire.
      _snack('Store unavailable. Try again in a moment.');
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
        _snack('Purchase could not complete. Please try again.');
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
      return;
    }
    context.go('/home');
  }

  void _close() {
    HapticFeedback.selectionClick();
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

  // ─────────────────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // CTA is buyable when RC delivered a real Package, OR we're in
    // dev/stub modes where _buy() routes through the notConfigured
    // fallback and just sets the local subscribed flag. Without the
    // kBypassPaywall arm, every TestFlight build before the
    // RevenueCat Offering is published would see a permanently grey
    // CTA — not what we want during smoke-testing.
    final canBuy = _packageFor(_selected) != null
        || !PurchaseConfig.isConfigured
        || kBypassPaywall;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 56, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Hero logo + wordmark
                  _hero(),
                  const SizedBox(height: 26),

                  // 2. Three numbered selling points
                  const _Point(n: '1',
                    headline: 'EVERY BONE, MEASURED',
                    body: '16 surgical measurements — jawline, canthal '
                          'tilt, symmetry, thirds. Not a guess.'),
                  const SizedBox(height: 18),
                  const _Point(n: '2',
                    headline: 'YOU, MAXIMIZED — RENDERED',
                    body: 'AI renders YOUR actual face at its best. '
                          'Haircut, beard, skin. Same person, undeniable '
                          'lift.'),
                  const SizedBox(height: 18),
                  const _Point(n: '3',
                    headline: 'THE MIRROR · ON CALL',
                    body: 'An AI that knows every inch of your anatomy. '
                          'Every fix designed for your bones — not a '
                          'generic.'),

                  const SizedBox(height: 26),

                  // 3. Three price cards — real localized prices
                  Row(
                    children: [
                      Expanded(child: _PriceCard(
                        title: 'MONTHLY',
                        price: _priceFor(_Tier.monthly),
                        cadence: 'per month',
                        footnote: 'Auto-renew',
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
                        cadence: '${_perMonthForAnnual()} / mo',
                        footnote: 'Auto-renew',
                        badge: 'BEST VALUE',
                        selected: _selected == _Tier.annual,
                        available: true,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selected = _Tier.annual);
                        },
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: _PriceCard(
                        title: '20 CREDITS',
                        price: _priceFor(_Tier.credits),
                        cadence: '20 renders',
                        footnote: 'One-time',
                        selected: _selected == _Tier.credits,
                        available: true,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selected = _Tier.credits);
                        },
                      )),
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

                  // 5. Apple 3.1.2 compliant disclosure — switches per
                  //    tier; covers price, cadence, renewal, cancellation.
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
        Text('MIRRORLY',
          textAlign: TextAlign.center,
          style: AppTypography.h1.copyWith(
            color: Colors.white,
            fontSize: 22, letterSpacing: 5.0,
            fontWeight: FontWeight.w900,
          ),
        ).animate().fadeIn(delay: 180.ms, duration: 360.ms),
        const SizedBox(height: 4),
        Text('MEASURED · NOT GUESSED',
          textAlign: TextAlign.center,
          style: AppTypography.label.copyWith(
            color: AppColors.red,
            fontSize: 10, letterSpacing: 3.0,
            fontWeight: FontWeight.w800,
          ),
        ).animate().fadeIn(delay: 240.ms, duration: 360.ms),
      ],
    );
  }

  String _ctaLabel() {
    final price = _priceFor(_selected);
    switch (_selected) {
      case _Tier.monthly: return 'SUBSCRIBE · $price / MO';
      case _Tier.annual:  return 'SUBSCRIBE · $price / YR';
      case _Tier.credits: return 'BUY · $price';
    }
  }

  /// Apple 3.1.2 compliant disclosure.
  /// Must contain: title/service, length, price, auto-renewal,
  /// cancellation path, links to Terms + Privacy.
  Widget _disclosure() {
    final price  = _priceFor(_selected);
    final perMo  = _perMonthForAnnual();

    String text;
    switch (_selected) {
      case _Tier.monthly:
        text = 'Mirrorly Pro — monthly subscription. Your payment of '
               '$price will be charged to your App Store (or Google '
               'Play) account at confirmation of purchase. The '
               'subscription automatically renews each month for $price '
               'unless you cancel at least 24 hours before the end of '
               'the current period. Your account will be charged for '
               'renewal within 24 hours of the period ending. You can '
               'manage or cancel your subscription any time in your '
               'account settings. Uninstalling the app does NOT cancel '
               'the subscription.';
        break;
      case _Tier.annual:
        text = 'Mirrorly Pro — annual subscription. Your payment of '
               '$price (equivalent to $perMo per month) will be '
               'charged to your App Store (or Google Play) account at '
               'confirmation of purchase. The subscription '
               'automatically renews each year for $price unless you '
               'cancel at least 24 hours before the end of the '
               'current period. Your account will be charged for '
               'renewal within 24 hours of the period ending. You can '
               'manage or cancel your subscription any time in your '
               'account settings. Uninstalling the app does NOT '
               'cancel the subscription.';
        break;
      case _Tier.credits:
        text = '20 Render Credits — one-time purchase of $price. NOT '
               'a subscription. Your App Store (or Google Play) '
               'account will be charged $price at confirmation of '
               'purchase, once. No auto-renewal. Each credit entitles '
               'you to one AI-rendered image. Credits do not expire '
               'and are non-refundable and non-transferable. A '
               'Mirrorly Pro subscription is required to perform '
               'scans.';
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
    switch (t) {
      case _Tier.monthly:
      case _Tier.annual:
        return [
          '2 scans per week',
          '10 AI-rendered images per month',
          'The Mirror — unlimited chat advice',
          'Honest-looks score (GPT-4o Vision)',
          'Geometry score (on-device, 16 metrics)',
          'Cancel anytime in App Store or Google Play settings',
        ];
      case _Tier.credits:
        return [
          '20 AI-rendered images (one per credit)',
          'No subscription, no recurring charge',
          'Credits never expire',
          'Non-refundable, non-transferable',
          'Requires an active Mirrorly Pro subscription for scans',
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
