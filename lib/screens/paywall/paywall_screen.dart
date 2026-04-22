import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../services/local_store_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Mirrorly paywall — single screen, no scroll, three identical price cards.
///
/// Ported from AURALAY's polished design on 2026-04-22: app icon hero at
/// top, AURALAY-style numbered selling points with italic numerals + bigger
/// body type, identical 132pt price cards, big red CTA, Apple-compliant
/// disclosure row. Mirrorly-specific: product IDs + wordmark + pricing.
///
/// Apple's review process rejects vague "free trial" language so the trial
/// is not offered here; honest, up-front monthly/annual/credit tiers only.
///
/// IAP product IDs (must match App Store Connect / Play Console):
///   mirrorly_pro_monthly  £9.99/mo   (auto-renew)
///   mirrorly_pro_yearly   £89.99/yr  (auto-renew, "save 25%" badge)
///   mirrorly_pro_rescue   £8.99      (one-time → 20 image credits)
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  String _selected = 'mirrorly_pro_yearly';

  static const _tiers = <_Tier>[
    _Tier(
      id: 'mirrorly_pro_monthly',
      title: 'MONTHLY',
      price: '£9.99',
      cadence: 'per month',
      footnote: 'Cancel anytime',
      badge: null,
    ),
    _Tier(
      id: 'mirrorly_pro_yearly',
      title: 'ANNUAL',
      price: '£89.99',
      cadence: 'per year · £7.50/mo',
      footnote: 'Best value',
      badge: 'SAVE 25%',
    ),
    _Tier(
      id: 'mirrorly_pro_rescue',
      title: '20 CREDITS',
      price: '£8.99',
      cadence: 'one-time · no sub',
      footnote: '1 image per credit',
      badge: null,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 1. Icon (centre top) — hero brand
              Center(
                child: Container(
                  width: 84, height: 84,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.red.withValues(alpha: 0.35),
                        blurRadius: 24, spreadRadius: 0),
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

              Center(
                child: Text('MIRRORLY',
                  style: AppTypography.h1.copyWith(
                    color: Colors.white,
                    fontSize: 22, letterSpacing: 5.0,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ).animate().fadeIn(delay: 180.ms, duration: 360.ms),

              const SizedBox(height: 4),

              Center(
                child: Text('MEASURED · NOT GUESSED',
                  style: AppTypography.label.copyWith(
                    color: AppColors.red,
                    fontSize: 10, letterSpacing: 3.0,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ).animate().fadeIn(delay: 240.ms, duration: 360.ms),

              const SizedBox(height: 26),

              // ── 2. Three numbered selling points (AURALAY's sizes — bigger + sexier)
              const _Point(
                n: '1',
                headline: 'EVERY BONE, MEASURED',
                body: '16 surgical measurements — jawline, canthal tilt, symmetry, thirds. Not a guess.',
              ),
              const SizedBox(height: 18),
              const _Point(
                n: '2',
                headline: 'YOU, MAXIMIZED — RENDERED',
                body: 'Flux Kontext renders YOUR actual face at its best. Haircut, beard, skin. Same person, undeniable lift.',
              ),
              const SizedBox(height: 18),
              const _Point(
                n: '3',
                headline: 'FACE DOCTOR, ON CALL',
                body: 'AI advisor that knows every inch of your anatomy. Every fix designed for your bones — not a generic.',
              ),

              const Spacer(),

              // ── 3. Three identical price cards
              Row(
                children: [
                  for (final t in _tiers) ...[
                    Expanded(
                      child: _PriceCard(
                        tier: t,
                        selected: _selected == t.id,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selected = t.id);
                        },
                      ),
                    ),
                    if (t != _tiers.last) const SizedBox(width: 8),
                  ],
                ],
              ).animate().fadeIn(delay: 600.ms, duration: 400.ms),

              const SizedBox(height: 12),

              // ── 4. Big red CTA
              SizedBox(
                width: double.infinity, height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                    shadowColor: AppColors.redGlow,
                  ).copyWith(
                    overlayColor: WidgetStateProperty.all(
                      AppColors.redDim.withValues(alpha: 0.3)),
                  ),
                  onPressed: () => _purchase(context, _selected),
                  child: Text(
                    _selected == 'mirrorly_pro_rescue'
                        ? 'BUY 20 CREDITS — £8.99'
                        : 'CONTINUE',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15, letterSpacing: 2.4,
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 720.ms, duration: 400.ms),

              const SizedBox(height: 14),

              // ── 5. Terms / privacy / restore
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _LinkButton(
                    label: 'TERMS',
                    onTap: () => _showLegal(context, 'Terms of Use',
                        'mirrorly.app/terms'),
                  ),
                  _LinkButton(
                    label: 'PRIVACY',
                    onTap: () => _showLegal(context, 'Privacy Policy',
                        'mirrorly.app/privacy'),
                  ),
                  _LinkButton(label: 'RESTORE', onTap: _restore),
                ],
              ),

              if (_selected != 'mirrorly_pro_rescue')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Subscription auto-renews. Cancel anytime in App Store settings.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 10, height: 1.4,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _purchase(BuildContext context, String productId) async {
    HapticFeedback.mediumImpact();
    // STUB — wire to in_app_purchase here. For now, mark as subscribed and
    // proceed to home so flow can be tested.
    await LocalStoreService.setSubscribed(true);
    await LocalStoreService.setOnboarded(true);
    if (context.mounted) context.go('/home');
  }

  Future<void> _restore() async {
    HapticFeedback.selectionClick();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('No previous purchases found.'),
      backgroundColor: Colors.black,
    ));
  }

  void _showLegal(BuildContext context, String title, String url) {
    HapticFeedback.selectionClick();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(
          'Read the full document at $url',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close',
              style: TextStyle(
                color: AppColors.red, fontWeight: FontWeight.w700,
                letterSpacing: 1.5)),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  WIDGETS
// ──────────────────────────────────────────────────────────────────────────

class _Tier {
  final String id, title, price, cadence, footnote;
  final String? badge;
  const _Tier({
    required this.id, required this.title, required this.price,
    required this.cadence, required this.footnote, this.badge,
  });
}

/// Selling-point row — italic 30pt red Playfair numeral + bold 13.5pt
/// headline + 14pt body. Ported verbatim from AURALAY's polished paywall
/// so the two apps feel like the same brand family.
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
  final _Tier tier;
  final bool selected;
  final VoidCallback onTap;
  const _PriceCard({
    required this.tier, required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? AppColors.red : Colors.white24;
    final priceColor  = selected ? AppColors.red : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 180.ms,
        height: 132,  // identical across all 3 cards
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
                  child: Text(tier.title,
                    style: AppTypography.label.copyWith(
                      color: Colors.white,
                      fontSize: 9, letterSpacing: 1.6,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (tier.badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(tier.badge!,
                      style: const TextStyle(
                        color: Colors.white, fontSize: 7.5,
                        letterSpacing: 0.8, fontWeight: FontWeight.w900,
                      )),
                  ),
              ],
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(tier.price,
                style: AppTypography.display.copyWith(
                  color: priceColor,
                  fontSize: 26, height: 1, letterSpacing: -1.0,
                  fontWeight: FontWeight.w800,
                )),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tier.cadence,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 9, fontWeight: FontWeight.w600, height: 1.2,
                  ),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(tier.footnote,
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
