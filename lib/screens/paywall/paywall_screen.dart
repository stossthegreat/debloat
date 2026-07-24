import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../config/dev_flags.dart';
import '../../services/analytics_service.dart';
import '../../services/local_store_service.dart';
import '../../services/purchase_service.dart';
import '../../services/review_prompt_service.dart';
import '../../theme/app_colors.dart';

/// Debloat OS paywall — "paywall-final" carousel.
///
/// v376 — THE LOOKS-APP STORY. A swipeable four-panel story
/// (Looks → Body → Protocols → Him). The Game orb panel and the Rizz
/// cards panel were removed with the looks pivot (both features are
/// parked out of the nav); the new BODY panel sells the body
/// transformation — before/after with the NOW → POTENTIAL score,
/// 3 AI renders a week. The header copy + classified progress tracker
/// change per panel, the CTA / price / legal row stay pinned at the
/// bottom.
///
/// Auto-tour behaviour (matches the mock): on open the carousel
/// advances one panel every 6 s, plays through all four, returns to
/// panel 1 (the photo) and then STOPS — from there the user swipes
/// manually. Any manual touch also stops the tour immediately.
///
/// Weekly-only. The annual tier is commented out (see `_Tier` /
/// `_priceLine`); only the weekly package is ever purchased.
///
/// Apple 3.1.2: the full auto-renewal + cancellation disclosure now
/// lives in Terms of Use (SUBSCRIPTIONS & AUTO-RENEWAL) rather than
/// bloating the paywall. The paywall keeps the required essentials —
/// price, billing cadence, an "auto-renews · cancel anytime" line, and
/// functional Terms / Privacy / Restore links directly under the CTA.
///
/// Routing contract (unchanged):
///   - `/paywall`                                 → standalone entry.
///   - `/paywall` with extra `{afterPurchase:'/report', imageBytes,
///     geometry, extraImages}`                    → scan-gated entry.
///   - `/paywall` with extra `{unlockInPlace:true}`→ locked-report teaser.
class PaywallScreen extends StatefulWidget {
  /// Optional context forwarded from the scan gate / report teaser.
  final Map<String, dynamic>? context;

  const PaywallScreen({super.key, this.context});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

// Weekly is the only sellable tier now. Annual + rescue remain in the
// enum so the offerings plumbing / analytics stay intact, but the UI
// only ever surfaces and purchases weekly.
enum _Tier { weekly, annual, rescue }

// Per-panel header copy — (headline, subhead). Every pair sells an
// OUTCOME, not a feature.
const List<(String, String)> _copy = [
  ('Meet the face under the bloat.', 'Same bones. Zero retention.'),
  ('Fix what can actually be fixed.', 'Bloat clears in 24–72 hours. We remove the cause.'),
  ('60 days. One decision.', 'The drained face becomes the default face.'),
];

// Classified progress-tracker section labels, one per panel.
const List<String> _sections = ['SCAN', 'SYSTEM', 'DRAINED'];

// Neon green used for the projected score + the final HIM pulse. The
// mock uses a brighter green than the app's signalGreen, so it's local.
const Color _neon = Color(0xFF2EE87A);
const Color _tile = Color(0xFF111113);

class _PaywallScreenState extends State<PaywallScreen> {
  PurchaseOfferings _offerings = PurchaseOfferings.empty();
  bool _purchasing = false;

  final PageController _pager = PageController();
  static const int _panelCount = 3;
  int _page = 0;
  final Set<int> _visited = {0};

  // Auto-tour state.
  Timer? _tourTimer;
  bool _interacted = false;

  // Drives the ladder climb on the final panel — bumped each time that
  // panel becomes visible so the sub-widget restarts its animation.
  int _ladderRun = 0;

  // 'm' | 'f' | null — picked up from onboarding so the hero split
  // shows a transformation that matches the user.
  String? _gender;

  @override
  void initState() {
    super.initState();

    // Dev-flag bypass: auto-redirect unless the caller passed
    // `force:true` (the manual preview path). Every other entry bounces
    // straight through so the user stays in-flow.
    final ctx = widget.context ?? const <String, dynamic>{};
    final force = ctx['force'] == true;
    if (kBypassPaywall && !force) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ctx['unlockInPlace'] == true) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/home');
          }
          return;
        }
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
    // Gender-aware hero — women see the female before/after split.
    // ignore: discarded_futures
    LocalStoreService.userGender().then((g) {
      if (mounted && g != null) setState(() => _gender = g);
    });
    // (Auto-tour removed with the old carousel — the new paywall is a
    // single static screen, so there's no PageView to animate.)
    _autoUnlockIfAlreadyPro();
  }

  /// SELF-HEALING GATE. If this user ALREADY has an active subscription
  /// (bought on an earlier build whose strict entitlement check rejected
  /// it, or on another device), the paywall recognises it the moment it
  /// opens and forwards as a success — no re-buy, no restore tap needed.
  /// This rescues the doom-loop where Apple says "you're currently
  /// subscribed" but the app never flipped the local flag. Silent no-op
  /// for genuinely free users.
  Future<void> _autoUnlockIfAlreadyPro() async {
    try {
      final live = await PurchaseService.isProLive()
          .timeout(const Duration(seconds: 5));
      if (live != true) return;
      if (!mounted || _purchasing) return;
      // isProLive already repainted the local cache to true. Forward
      // exactly like a fresh purchase so scan-gated / unlock-in-place
      // context is honoured.
      await LocalStoreService.setOnboarded(true);
      if (!mounted) return;
      _snack('Subscription active — unlocked.');
      _forwardOnSuccess();
    } catch (_) {
      // Network / timeout — stay on the paywall, normal flow applies.
    }
  }

  @override
  void dispose() {
    _tourTimer?.cancel();
    _pager.dispose();
    super.dispose();
  }

  Future<void> _loadOfferings() async {
    final off = await PurchaseService.loadOfferings();
    if (!mounted) return;
    setState(() => _offerings = off);
  }

  // ── Auto-tour ─────────────────────────────────────────────────────
  //
  // Advance one panel every 6 s. Play through all four, wrap back to
  // panel 0 (the photo), then stop — from there it's swipe-only. Any
  // manual touch cancels the tour early (see the Listener in build()).
  void _startTour() {
    _tourTimer = Timer.periodic(const Duration(seconds: 6), (t) {
      if (_interacted || !mounted) {
        t.cancel();
        return;
      }
      final next = _page + 1;
      if (next >= _panelCount) {
        // One full loop done → return to the photo and stop.
        _pager.animateToPage(0,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic);
        t.cancel();
      } else {
        _pager.animateToPage(next,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic);
      }
    });
  }

  void _stopTour() {
    if (_interacted) return;
    _interacted = true;
    _tourTimer?.cancel();
  }

  void _onPageChanged(int i) {
    setState(() {
      _page = i;
      _visited.add(i);
      if (i == _panelCount - 1) _ladderRun++;
    });
    // Only buzz on manual swipes — the auto-tour should stay silent.
    if (_interacted) HapticFeedback.selectionClick();
  }

  // ── Purchase actions (weekly only) ────────────────────────────────

  Package? _packageFor(_Tier t) => switch (t) {
        _Tier.weekly => _offerings.weekly,
        _Tier.annual => _offerings.annual,
        _Tier.rescue => _offerings.rescue,
      };

  static const _placeholderDash = '—';

  String _priceFor(_Tier t) {
    final pkg = _packageFor(t);
    if (pkg != null) return pkg.storeProduct.priceString;
    return _placeholderDash;
  }

  Future<void> _buy() async {
    if (_purchasing) return;
    final pkg = _packageFor(_Tier.weekly);
    if (pkg == null) {
      // No live weekly Package — almost always Android where RC hasn't
      // returned an Offering. Surface the diagnostic instead of a dead
      // button so we can see exactly what the SDK saw on-device.
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

    // v285 WATCHDOG — covers the TestFlight failure where the StoreKit
    // sheet completes ("Done") but the Flutter purchase future hangs or
    // resolves as cancelled, so none of the outcome handling below ever
    // runs. The customer-info listener in PurchaseService.init() flips
    // the local subscribed flag the moment RevenueCat registers the
    // transaction; poll it while the future is in flight so a completed
    // payment ALWAYS routes the user forward. Skipped when the user was
    // already subscribed before tapping (nothing to detect).
    var settled = false;
    final wasSubscribed = await LocalStoreService.isSubscribed();
    if (!wasSubscribed) {
      Timer.periodic(const Duration(seconds: 2), (t) async {
        if (settled || !mounted) {
          t.cancel();
          return;
        }
        if (await LocalStoreService.isSubscribed()) {
          t.cancel();
          if (settled || !mounted) return;
          settled = true;
          await LocalStoreService.setOnboarded(true);
          if (!mounted) return;
          setState(() => _purchasing = false);
          _forwardOnSuccess();
        }
      });
    }

    final outcome = await PurchaseService.purchase(pkg);

    if (settled) return; // watchdog already routed forward
    settled = true;
    if (!mounted) return;
    setState(() => _purchasing = false);

    switch (outcome) {
      case PurchaseOutcome.success:
        // Belt-and-suspenders: force the local subscribed flag true here
        // too (purchase() already does, but this guarantees it's on disk
        // before _forwardOnSuccess pops and the report re-reads isPro).
        await LocalStoreService.setSubscribed(true);
        await LocalStoreService.setOnboarded(true);
        if (!mounted) return;
        _forwardOnSuccess();
        break;
      case PurchaseOutcome.cancelled:
        // Never silent — if StoreKit misreports a completed sheet as a
        // cancel we need to SEE it on-device instead of guessing. The
        // watchdog above still unlocks if the transaction actually went
        // through. Harmless for a genuine cancel.
        _snack('Purchase cancelled — you were not charged.');
        break;
      case PurchaseOutcome.noPriorPurchases:
        _snack('No previous purchases found.');
        break;
      case PurchaseOutcome.notConfigured:
        await LocalStoreService.setSubscribed(true);
        await LocalStoreService.setOnboarded(true);
        if (mounted) _forwardOnSuccess();
        break;
      case PurchaseOutcome.error:
        // Last chance: the RC listener may have registered the
        // transaction even though the purchase call errored. If the
        // flag flipped, the user PAID — forward, don't scare them.
        if (await LocalStoreService.isSubscribed()) {
          await LocalStoreService.setOnboarded(true);
          if (mounted) _forwardOnSuccess();
          break;
        }
        // Purchase didn't unlock. Surface the FULL RevenueCat state so we
        // can see exactly what the store returned (offering, weekly
        // product id, active subs, "pro" entitlement) instead of a vague
        // toast — this is how we diagnose "paid but nothing unlocked".
        final diag = await PurchaseService.diagnose();
        if (!mounted) return;
        final detail = PurchaseService.lastErrorMessage;
        _showDiagnostic('${detail ?? 'Purchase could not complete.'}'
            '\n\n──────────\n$diag');
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
    if (ctx != null && ctx['afterPurchase'] == '/report') {
      context.go('/report', extra: {
        'imageBytes': ctx['imageBytes'],
        'geometry': ctx['geometry'],
        'extraImages': ctx['extraImages'] ?? const <dynamic>[],
      });
    } else if (ctx != null && ctx['unlockInPlace'] == true) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
    } else {
      context.go('/home');
    }
    // ignore: discarded_futures
    ReviewPromptService.maybePromptAfterPurchase(context);
  }

  void _close() {
    HapticFeedback.selectionClick();
    AnalyticsService.paywallDismissed(
        (widget.context?['afterPurchase'] as String?) ?? 'standalone');
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      // Explicit white text — default snackbar styling rendered this
      // black-on-black (invisible strip) on the black background.
      content: Text(msg,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.35)),
      backgroundColor: const Color(0xFF16161B),
      behavior: SnackBarBehavior.floating,
    ));
  }

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
                  color: Colors.white,
                  fontSize: 12,
                  fontFamily: 'monospace',
                  height: 1.4)),
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

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final raw = _priceFor(_Tier.weekly);
    final price = raw == _placeholderDash ? '\$4.99' : raw;
    return Scaffold(
      backgroundColor: _pvBg,
      body: Column(
        children: [
          // ── Hero: our before/after, split by a violet beam, DAY 1 /
          //    WEEK 8 chips, close X overlaid. ─────────────────────────
          Stack(
            children: [
              _heroSplit(),
              SafeArea(
                bottom: false,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 2, 0, 0),
                    child: _CloseX(onTap: _close),
                  ),
                ),
              ),
            ],
          ),

          // ── Scrollable middle: logo + headline + features + plan ────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset('assets/icons/appstore.png',
                      width: 40, height: 40,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.face_rounded, color: Colors.white, size: 34)),
                  ),
                  const SizedBox(height: 14),
                  Text('Debloat your face.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.white, fontSize: 28, height: 1.1,
                      fontWeight: FontWeight.w500)),
                  Text('Define your jawline.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.white, fontSize: 28, height: 1.1,
                      fontWeight: FontWeight.w900)),
                  const SizedBox(height: 20),
                  // Three outcomes — the whole promise, sold hard.
                  Column(
                    children: const [
                      _OutcomeRow(
                        icon: Icons.face_retouching_natural,
                        title: 'See your face debloated',
                        body: 'AI renders the leaner, sharper you — the face under the bloat.'),
                      SizedBox(height: 12),
                      _OutcomeRow(
                        icon: Icons.restaurant_rounded,
                        title: 'Scan any meal for bloat',
                        body: 'Point your camera at food — catch the hidden sodium before it puffs you up.'),
                      SizedBox(height: 12),
                      _OutcomeRow(
                        icon: Icons.water_drop_rounded,
                        title: 'Unlock your drain plan',
                        body: 'The exact daily routine to get there, built for your face.'),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _WeeklyPlanCard(price: price),
                  const SizedBox(height: 10),
                  Text('$price per week · auto-renews · cancel anytime',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),

          // ── Pinned CTA + footer ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity, height: 62,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: _pvViolet.withValues(alpha: 0.45),
                          blurRadius: 28, spreadRadius: 1),
                      ],
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _pvViolet,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                        elevation: 0,
                      ),
                      onPressed: _purchasing ? null : _buy,
                      child: _purchasing
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.white)))
                          : Text('Continue',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800, fontSize: 18)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _LinkButton(label: 'Terms',
                      onTap: () { HapticFeedback.selectionClick(); context.push('/terms'); }),
                    _dot(),
                    _LinkButton(label: 'Privacy',
                      onTap: () { HapticFeedback.selectionClick(); context.push('/privacy'); }),
                    _dot(),
                    _LinkButton(label: 'Restore', onTap: _restore),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Text('·', style: GoogleFonts.inter(
      color: Colors.white.withValues(alpha: 0.4), fontSize: 16)),
  );

  /// The full-bleed before/after hero — our beforeafter.jpg, split down
  /// the middle by a glowing violet beam, with DAY 1 / WEEK 8 chips.
  Widget _heroSplit() {
    return SizedBox(
      height: 380,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            _gender == 'f'
                ? 'assets/marketing/beforeafter_f.jpg'
                : 'assets/marketing/beforeafter.jpg',
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.3),
            errorBuilder: (_, __, ___) => Container(color: _pvCard,
              alignment: Alignment.center,
              child: const Icon(Icons.face_rounded, color: _pvViolet, size: 72))),
          // Fade the bottom into the page background.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, _pvBg],
                  stops: const [0.55, 1.0]),
              ),
            ),
          ),
          // Central violet beam.
          Center(
            child: Container(
              width: 2.5,
              decoration: BoxDecoration(
                color: _pvVioletLite,
                boxShadow: [BoxShadow(
                  color: _pvVioletLite.withValues(alpha: 0.8), blurRadius: 16)]),
            ),
          ),
          // DAY 1 chip (left)
          Positioned(
            left: 16, bottom: 96,
            child: _dayChip('DAY 1', filled: false),
          ),
          // WEEK 8 chip (right)
          Positioned(
            right: 16, bottom: 96,
            child: _dayChip('WEEK 8', filled: true),
          ),
        ],
      ),
    );
  }

  Widget _dayChip(String label, {required bool filled}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: filled ? _pvViolet : Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: filled ? _pvViolet : Colors.white.withValues(alpha: 0.35),
          width: 1.4),
        boxShadow: filled
            ? [BoxShadow(color: _pvViolet.withValues(alpha: 0.6), blurRadius: 18)]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(filled ? Icons.auto_awesome : Icons.circle_outlined,
            color: Colors.white, size: 15),
          const SizedBox(width: 7),
          Text(label,
            style: GoogleFonts.inter(
              color: Colors.white, fontSize: 15,
              letterSpacing: 1, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

// ── Violet paywall palette (matches the target mock) ────────────────────────
const _pvBg         = Color(0xFF0D0B1A);
const _pvViolet     = Color(0xFF6C4CF5);
const _pvVioletLite = Color(0xFFA78BFA);
const _pvCard       = Color(0xFF16132A);

/// One of the three hard-hitting outcomes sold under the headline.
/// A violet icon tile, a bold promise, and the grey benefit line beneath it.
class _OutcomeRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _OutcomeRow({
    required this.icon, required this.title, required this.body});
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: _pvViolet.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: _pvViolet.withValues(alpha: 0.4), width: 1),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: _pvVioletLite, size: 23),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                style: GoogleFonts.inter(
                  color: Colors.white, fontSize: 15.5,
                  height: 1.15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(body,
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.62),
                  fontSize: 12.5, height: 1.3, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The single WEEKLY plan card — selected/violet by default (only option).
class _WeeklyPlanCard extends StatelessWidget {
  final String price;
  const _WeeklyPlanCard({required this.price});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 20, 16),
      decoration: BoxDecoration(
        color: _pvViolet.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _pvViolet, width: 2),
        boxShadow: [BoxShadow(
          color: _pvViolet.withValues(alpha: 0.3), blurRadius: 22, spreadRadius: -4)],
      ),
      child: Row(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: _pvViolet.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(14)),
            alignment: Alignment.center,
            child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('WEEKLY',
                style: GoogleFonts.inter(
                  color: Colors.white, fontSize: 19,
                  letterSpacing: 1, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text('billed weekly',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(price,
                style: GoogleFonts.inter(
                  color: Colors.white, fontSize: 28, height: 1,
                  fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text('per week',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  HEADER
// ══════════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  final int page;
  const _Header({required this.page});

  @override
  Widget build(BuildContext context) {
    final (headline, sub) = _copy[page];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 96),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: Column(
            key: ValueKey(page),
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                headline,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 27,
                  height: 1.15,
                  letterSpacing: -0.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                sub,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  PANEL 1 — PHOTO + SCORE
// ══════════════════════════════════════════════════════════════════════

class _PhotoPanel extends StatelessWidget {
  const _PhotoPanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      // Center the whole [numbers + image] group as ONE unit so the
      // numbers hug the image's top ledge instead of floating away from it.
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // NUMBERS sit on the black ledge directly above the image, one
            // centered over each half (54 over current, 84 over projected).
            // A tiny 3px gap keeps the digits right on the top ledge —
            // close, but never overlapping under the image edge.
            Row(
              children: const [
                Expanded(
                    child: _ScoreNum(n: '54', color: Color(0xFFC4C4CB))),
                Expanded(
                    child: _ScoreNum(n: '84', color: _neon, glow: true)),
              ],
            ),
            const SizedBox(height: 3),
            // Aspect ratio matches the cropped before/after asset (914×778)
            // so the baked-in NOW / FIXED labels never get clipped. Width-
            // constrained, so its height is fixed — no Flexible/Center gap.
            AspectRatio(
              aspectRatio: 914 / 778,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/marketing/beforeafter.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const ColoredBox(color: _tile),
                    ),
                    // LABELS ride ON the image at the very top, centered
                    // over each half, on a subtle scrim for legibility.
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.only(top: 8, bottom: 16),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xB3000000), Color(0x00000000)],
                          ),
                        ),
                        child: Row(
                          children: const [
                            Expanded(
                                child: _ScoreLabel(
                                    'CURRENT', Color(0xFFC4C4CB))),
                            Expanded(
                                child:
                                    _ScoreLabel('PROJECTED', Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One big score number, centered in its half. Sits on the black ledge
/// directly above the before/after image.
class _ScoreNum extends StatelessWidget {
  final String n;
  final Color color;
  final bool glow;
  const _ScoreNum({required this.n, required this.color, this.glow = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      n,
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        color: color,
        fontSize: 46,
        height: 1,
        fontWeight: FontWeight.w900,
        shadows: glow
            ? [Shadow(color: _neon.withValues(alpha: 0.6), blurRadius: 30)]
            : null,
      ),
    );
  }
}

/// One score label (CURRENT / PROJECTED), centered in its half, overlaid
/// on the top edge of the image.
class _ScoreLabel extends StatelessWidget {
  final String label;
  final Color color;
  const _ScoreLabel(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        color: color,
        fontSize: 11,
        letterSpacing: 3,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  PANEL 2 — PROTOCOL LIST
// ══════════════════════════════════════════════════════════════════════

class _ProtoPanel extends StatelessWidget {
  const _ProtoPanel();

  static const _rows = <(String, String, String)>[
    ('🧊', 'Morning flush', 'Ice dunk + lymph drain. Visible within days.'),
    ('🧂', 'Sodium control', 'The #1 driver of facial water retention, capped.'),
    ('🥑', 'Potassium target', 'The counter-ion that flushes the sodium out.'),
    ('💧', 'Hydration engine', '2.5–3L daily — the flush signal.'),
    ('🍞', 'Glycogen watch', 'Every gram of carbs binds 3g of water. Managed.'),
    ('😴', 'Night drain', 'Elevated back-sleep + 7–9h. Cortisol face, gone.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Center(
        child: AspectRatio(
          // Taller than the original 680/538 — the list grew to six
          // rows when Body joined the protocols.
          aspectRatio: 680 / 650,
          child: Column(
            children: [
              for (var i = 0; i < _rows.length; i++) ...[
                if (i > 0) const SizedBox(height: 7),
                Expanded(child: _ProtoRow(row: _rows[i])),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProtoRow extends StatelessWidget {
  final (String, String, String) row;
  const _ProtoRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final (emoji, title, body) = row;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: _tile,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 17)),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 1),
                Text(body,
                    style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 10.5,
                        height: 1.25,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  PANEL 3 — ASCENSION LADDER
// ══════════════════════════════════════════════════════════════════════

class _LadderPanel extends StatefulWidget {
  /// Bumped whenever this panel becomes visible so the climb restarts.
  /// -1 while the panel is off-screen.
  final int runToken;
  const _LadderPanel({required this.runToken});

  @override
  State<_LadderPanel> createState() => _LadderPanelState();
}

class _LadderPanelState extends State<_LadderPanel> {
  // The debloat identity ladder — mirrors AscensionService's ranks
  // (the Ascend tab's "THE MAN YOU ARE BUILDING" progression) so the
  // paywall promises the exact journey the app delivers.
  static const _rungs = [
    'BOOTED',
    'FLUSHING',
    'DRAINING',
    'DEFINED',
    'CHISELED',
    'DRAINED',
  ];

  int _lit = 0; // number of rungs currently lit
  bool _pulse = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.runToken >= 0) _climb();
  }

  @override
  void didUpdateWidget(covariant _LadderPanel old) {
    super.didUpdateWidget(old);
    if (widget.runToken != old.runToken && widget.runToken >= 0) {
      _climb();
    }
  }

  void _climb() {
    _timer?.cancel();
    setState(() {
      _lit = 1;
      _pulse = false;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 650), (t) {
      if (!mounted) return;
      if (_lit >= _rungs.length) {
        t.cancel();
        return;
      }
      setState(() => _lit++);
      if (_lit >= _rungs.length) {
        t.cancel();
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) setState(() => _pulse = true);
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < _rungs.length; i++) {
      final on = i < _lit;
      final isHim = i == _rungs.length - 1;
      children.add(_rung(_rungs[i], on: on, isHim: isHim));
      if (i != _rungs.length - 1) {
        // Arrow i (between rung i and i+1) lights once rung i+1 is lit.
        children.add(_arrow(on: i < _lit - 1));
      }
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _rung(String label, {required bool on, required bool isHim}) {
    Color color;
    double size;
    List<Shadow>? shadows;
    if (isHim && on && _pulse) {
      color = _neon;
      size = 22;
      shadows = [Shadow(color: _neon.withValues(alpha: 0.9), blurRadius: 40)];
    } else if (isHim && on) {
      color = AppColors.red;
      size = 22;
      shadows = [
        Shadow(color: AppColors.red.withValues(alpha: 0.8), blurRadius: 24)
      ];
    } else if (on) {
      color = Colors.white;
      size = 16;
    } else {
      color = const Color(0xFF3A3A40);
      size = 16;
    }

    Widget text = AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 400),
      style: GoogleFonts.inter(
        color: color,
        fontSize: size,
        letterSpacing: 3,
        fontWeight: FontWeight.w800,
        shadows: shadows,
      ),
      child: Text(label),
    );

    Widget scaled = AnimatedScale(
      duration: const Duration(milliseconds: 400),
      scale: on ? 1.06 : 1.0,
      child: text,
    );

    if (isHim && on && _pulse) {
      scaled = scaled
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(begin: 1.0, end: 1.18, duration: 700.ms, curve: Curves.easeInOut);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: scaled,
    );
  }

  Widget _arrow({required bool on}) {
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 400),
      style: TextStyle(
        color: on ? AppColors.red : const Color(0xFF3A3A40),
        fontSize: 12,
        height: 1,
      ),
      child: const Text('↓'),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  CLASSIFIED PROGRESS TRACKER
// ══════════════════════════════════════════════════════════════════════

class _Brief extends StatelessWidget {
  final int page;
  final Set<int> visited;
  const _Brief({required this.page, required this.visited});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var k = 0; k < _sections.length; k++) ...[
            if (k > 0) const SizedBox(width: 8),
            _briefItem(k),
          ],
        ],
      ),
    );
  }

  Widget _briefItem(int k) {
    final no = '0${k + 1}';
    const noStyleBase = TextStyle(fontSize: 10, fontWeight: FontWeight.w800);
    if (k == page) {
      // Current: red number + white expanded section name.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(no,
              style: GoogleFonts.inter(
                  textStyle: noStyleBase, color: AppColors.red)),
          const SizedBox(width: 5),
          Text(_sections[k],
              style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w800)),
        ],
      );
    }
    final done = visited.contains(k);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(no,
            style: GoogleFonts.inter(
                textStyle: noStyleBase,
                color: done ? AppColors.textSecondary : const Color(0xFF3F3F45))),
        const SizedBox(width: 5),
        done
            ? const Icon(Icons.check_rounded, size: 12, color: _neon)
            : const Icon(Icons.lock, size: 10, color: Color(0xFF3F3F45)),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  SHARED
// ══════════════════════════════════════════════════════════════════════

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
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.22), width: 0.8),
          ),
          child: const Icon(Icons.close_rounded, size: 20, color: Colors.white),
        ),
      ),
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
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label,
          style: GoogleFonts.inter(
            color: const Color(0xFFC9C9D0),
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          )),
    );
  }
}
