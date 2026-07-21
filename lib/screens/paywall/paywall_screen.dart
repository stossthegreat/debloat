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

/// ImHim Looks paywall — "paywall-final" carousel.
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
  ("Meet the man you're capable of becoming.", 'Same genetics. Better decisions.'),
  ('Your body. One committed year from now.',
      'Rendered from your own photo · 3 AI renders a week, face or body.'),
  ('Fix what can actually be fixed.', 'Your highest-impact improvements. Ranked.'),
  ('60 days. One decision.', 'Become the man you met on day one.'),
];

// Classified progress-tracker section labels, one per panel.
const List<String> _sections = ['LOOKS', 'BODY', 'PROTOCOLS', 'HIM'];

// Neon green used for the projected score + the final HIM pulse. The
// mock uses a brighter green than the app's signalGreen, so it's local.
const Color _neon = Color(0xFF2EE87A);
const Color _tile = Color(0xFF111113);

class _PaywallScreenState extends State<PaywallScreen> {
  PurchaseOfferings _offerings = PurchaseOfferings.empty();
  bool _purchasing = false;

  final PageController _pager = PageController();
  static const int _panelCount = 4;
  int _page = 0;
  final Set<int> _visited = {0};

  // Auto-tour state.
  Timer? _tourTimer;
  bool _interacted = false;

  // Drives the ladder climb on the final panel — bumped each time that
  // panel becomes visible so the sub-widget restarts its animation.
  int _ladderRun = 0;

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
    _startTour();
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: true,
        bottom: true,
        child: Column(
          children: [
            // Close X — top-left.
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 0, 0),
                child: _CloseX(onTap: _close),
              ),
            ),

            // Header copy — cross-fades on panel change.
            _Header(page: _page),

            // Carousel — takes all remaining vertical space.
            Expanded(
              child: Listener(
                // Any finger-down on the carousel ends the auto-tour,
                // exactly like the mock's touchstart handler.
                onPointerDown: (_) => _stopTour(),
                child: PageView(
                  controller: _pager,
                  onPageChanged: _onPageChanged,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    const _PhotoPanel(),
                    const _BodyPanel(),
                    const _ProtoPanel(),
                    _LadderPanel(
                        runToken:
                            _page == _panelCount - 1 ? _ladderRun : -1),
                  ],
                ),
              ),
            ),

            // Classified progress tracker.
            _Brief(page: _page, visited: _visited),

            // CTA + price + legal.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 62,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.red.withValues(alpha: 0.45),
                            blurRadius: 30,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        onPressed: _purchasing ? null : _buy,
                        child: _purchasing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation(Colors.white)),
                              )
                            : Text(
                                'BECOME HIM',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  letterSpacing: 2.6,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _priceLine(),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _LinkButton(
                          label: 'Terms of Use',
                          onTap: () {
                            HapticFeedback.selectionClick();
                            context.push('/terms');
                          }),
                      _LinkButton(label: 'Restore Purchase', onTap: _restore),
                      _LinkButton(
                          label: 'Privacy Policy',
                          onTap: () {
                            HapticFeedback.selectionClick();
                            context.push('/privacy');
                          }),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Single price line under the CTA. Carries the three Apple-required
  /// essentials in one glance — real store price, weekly cadence, and
  /// the auto-renew / cancel notice. Full disclosure lives in Terms.
  /// (The on-device build tag was removed for launch — check the build
  /// number in Settings → TestFlight instead.)
  Widget _priceLine() {
    final price = _priceFor(_Tier.weekly);
    return Text(
      '$price per week · auto-renews · cancel anytime',
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        color: AppColors.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
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
//  PANEL 2 — BODY BEFORE/AFTER
// ══════════════════════════════════════════════════════════════════════

/// The body transformation panel. The bundled graphic
/// (assets/marketing/body_beforeafter.jpg, 914×778 — the SAME crop as
/// the face slide's beforeafter.jpg) is the full Body-tab verdict
/// composition supplied by the founder: before/after pair with baked
/// NOW / COMMITTED labels, the 62 → +28 → 90 score strip and the
/// verdict line. Everything is IN the image, so this panel draws no
/// overlays of its own — just the image at the exact size/rounding of
/// the face slide before it.
class _BodyPanel extends StatelessWidget {
  const _BodyPanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Center(
        child: AspectRatio(
          aspectRatio: 914 / 778,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              'assets/marketing/body_beforeafter.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(
                color: _tile,
                child: Center(
                  child: Icon(Icons.fitness_center_rounded,
                      size: 56, color: Color(0xFF3A3A40)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  PANEL 3 — PROTOCOL LIST
// ══════════════════════════════════════════════════════════════════════

class _ProtoPanel extends StatelessWidget {
  const _ProtoPanel();

  static const _rows = <(String, String, String)>[
    ('🔥', 'Debloat', 'Less puffiness. Visible changes can begin within days.'),
    ('🗿', 'Jaw', 'Build a sharper, more defined profile.'),
    ('👁', 'Eye Area', 'Look more awake, healthier and more attractive.'),
    ('✨', 'Skin', 'Clearer skin. Better texture. Better first impressions.'),
    ('💇', 'Hair', 'The right cut, style and long-term hair plan.'),
    ('💪', 'Body', 'Shred, build or recomp — the frame under the face.'),
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
//  PANEL 4 — ASCENSION LADDER
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
  static const _rungs = [
    'OBSERVER',
    'INITIATE',
    'CONTENDER',
    'DANGEROUS',
    'HIM'
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
