import 'dart:io' show Platform;

import 'package:purchases_flutter/purchases_flutter.dart';

import '../config/purchase_config.dart';
import 'local_store_service.dart';

/// Single front-door for all billing operations.
///
/// Owns three things:
///   1. Initialising the RevenueCat SDK at app start with the right
///      platform key.
///   2. Loading the current Offering and surfacing localized prices +
///      the Package objects the paywall needs to call purchase().
///   3. Mirroring RevenueCat's entitlement state into our local
///      subscribed flag (LocalStoreService.setSubscribed) so the rest
///      of the app can keep using its existing synchronous check
///      points without awaiting a network round-trip.
///
/// RevenueCat is the source of truth — LocalStore is just a cache the
/// non-billing code reads. On every launch we refresh the cache from
/// the RC customer info, so a subscription cancelled from App Store
/// settings will correctly drop the user out of pro on next launch.
class PurchaseService {
  static bool _initialized = false;
  static PurchaseOfferings? _cached;

  // ─────────────────────────────────────────────────────────────────────────
  //  INITIALISATION
  // ─────────────────────────────────────────────────────────────────────────

  /// Call once at app start (main.dart). Safe to call even when no
  /// RevenueCat keys are configured yet — in that case this is a
  /// no-op and the rest of the app works as a dev stub.
  static Future<void> init() async {
    if (_initialized) return;
    if (!PurchaseConfig.isConfigured) return;

    final apiKey = Platform.isIOS
        ? PurchaseConfig.iosApiKey
        : PurchaseConfig.androidApiKey;
    if (apiKey.isEmpty) return;

    await Purchases.setLogLevel(LogLevel.error);
    await Purchases.configure(PurchasesConfiguration(apiKey));
    _initialized = true;

    // Mirror current entitlement state into the local cache so a
    // cancellation-from-App-Store-settings correctly flips the app to
    // locked the next time it opens.
    await _refreshEntitlementCache();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  OFFERINGS (prices + packages)
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetch the current RevenueCat Offering. Returns a snapshot the
  /// paywall can render without re-hitting the network. Cached for the
  /// lifetime of the process.
  ///
  /// When the SDK isn't configured or the fetch fails, returns the
  /// shape expected by the paywall with nulls in the price slots so
  /// the UI renders "—" (never a hardcoded price — we never ship a
  /// price to the store).
  static Future<PurchaseOfferings> loadOfferings() async {
    if (_cached != null) return _cached!;
    if (!_initialized) return PurchaseOfferings.empty();

    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null) return PurchaseOfferings.empty();

      Package? monthly;
      Package? annual;
      Package? credits;

      for (final pkg in current.availablePackages) {
        final id = pkg.identifier;
        if (id == PurchaseConfig.offering.monthlyPackage || id == r'$rc_monthly') {
          monthly = pkg;
        } else if (id == PurchaseConfig.offering.annualPackage || id == r'$rc_annual') {
          annual = pkg;
        } else if (id == PurchaseConfig.offering.creditsPackage) {
          credits = pkg;
        }
      }

      _cached = PurchaseOfferings(
        monthly: monthly,
        annual:  annual,
        credits: credits,
      );
      return _cached!;
    } catch (_) {
      return PurchaseOfferings.empty();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  PURCHASE / RESTORE
  // ─────────────────────────────────────────────────────────────────────────

  /// Kick off the platform purchase sheet. Returns [PurchaseOutcome] —
  /// the caller translates that into UI feedback (success → route
  /// forward, cancelled → nothing, error → toast).
  static Future<PurchaseOutcome> purchase(Package pkg) async {
    if (!_initialized) return PurchaseOutcome.notConfigured;
    try {
      final result = await Purchases.purchasePackage(pkg);
      final isPro = result.entitlements.all[PurchaseConfig.proEntitlementId]?.isActive ?? false;
      // Credit packs aren't a subscription entitlement — they're
      // consumable. For those, treat any successful purchase as a
      // credit grant. The subscription flag only flips for pro.
      final isCreditPack =
          pkg.identifier == PurchaseConfig.offering.creditsPackage;
      if (isPro) {
        await LocalStoreService.setSubscribed(true);
      }
      if (isPro || isCreditPack) {
        return PurchaseOutcome.success;
      }
      return PurchaseOutcome.error;
    } on PurchasesErrorCode catch (_) {
      return PurchaseOutcome.error;
    } catch (err) {
      final code = PurchasesErrorHelper.getErrorCode(err as dynamic);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return PurchaseOutcome.cancelled;
      }
      return PurchaseOutcome.error;
    }
  }

  /// Restore previously-purchased entitlements. Required by App Store
  /// review. Same return type as [purchase].
  static Future<PurchaseOutcome> restore() async {
    if (!_initialized) return PurchaseOutcome.notConfigured;
    try {
      final info = await Purchases.restorePurchases();
      final isPro = info.entitlements.all[PurchaseConfig.proEntitlementId]?.isActive ?? false;
      await LocalStoreService.setSubscribed(isPro);
      return isPro ? PurchaseOutcome.success : PurchaseOutcome.noPriorPurchases;
    } catch (_) {
      return PurchaseOutcome.error;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  INTERNAL
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> _refreshEntitlementCache() async {
    try {
      final info = await Purchases.getCustomerInfo();
      final isPro = info.entitlements.all[PurchaseConfig.proEntitlementId]?.isActive ?? false;
      await LocalStoreService.setSubscribed(isPro);
    } catch (_) {
      // Network fail on launch is not fatal — the cached flag stands.
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  DTOs
// ═══════════════════════════════════════════════════════════════════════════

enum PurchaseOutcome { success, cancelled, error, noPriorPurchases, notConfigured }

/// Snapshot of the three products the paywall needs. Nulls are OK —
/// means the package isn't in the current offering yet, paywall shows
/// that slot as unavailable.
class PurchaseOfferings {
  final Package? monthly;
  final Package? annual;
  final Package? credits;

  const PurchaseOfferings({
    required this.monthly,
    required this.annual,
    required this.credits,
  });

  factory PurchaseOfferings.empty() => const PurchaseOfferings(
    monthly: null, annual: null, credits: null,
  );
}
