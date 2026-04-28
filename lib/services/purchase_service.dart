import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart' show PlatformException;
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

  /// Most recent purchase / restore failure, in human-readable form.
  /// Surfaced by the paywall as a toast so users (and reviewers, and us)
  /// know whether Android Play Billing said "product unavailable",
  /// "billing service disconnected", "item already owned", etc., instead
  /// of the old generic "Purchase could not complete" message that hid
  /// every Android-side cause.
  static String? lastErrorMessage;

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

    // Verbose logging in debug builds + on Android specifically. Android
    // Play Billing has a long list of failure modes (product not in any
    // active offering, sideloaded APK, test account not licensed, etc.)
    // and the only way to find out which one fired is the RC log line
    // tagged "[Purchases]" in adb logcat. iOS StoreKit fails much more
    // cleanly — keep its log noise low.
    final verbose = kDebugMode || Platform.isAndroid;
    await Purchases.setLogLevel(verbose ? LogLevel.debug : LogLevel.error);
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
  ///
  /// On error, [lastErrorMessage] is set with a human-readable cause so
  /// the paywall can show it. Vital for Android — Play Billing has many
  /// failure modes (sideloaded APK, product not in any active offering,
  /// test account not licensed, item already owned, billing service
  /// disconnected) and the user / reviewer needs to see which one.
  static Future<PurchaseOutcome> purchase(Package pkg) async {
    lastErrorMessage = null;
    if (!_initialized) {
      lastErrorMessage = 'Store not configured.';
      return PurchaseOutcome.notConfigured;
    }
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
      lastErrorMessage = 'Entitlement did not activate.';
      return PurchaseOutcome.error;
    } on PlatformException catch (err) {
      // purchases_flutter throws PlatformException with the underlying
      // RevenueCat error code attached as `details`. Surface both the
      // user-friendly message and the code so we can grep logs.
      final code = PurchasesErrorHelper.getErrorCode(err);
      // ignore: avoid_print
      print('[PurchaseService] purchase failed: code=$code msg=${err.message}');
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        lastErrorMessage = null;
        return PurchaseOutcome.cancelled;
      }
      lastErrorMessage = _humanise(code, err.message);
      return PurchaseOutcome.error;
    } catch (err) {
      // ignore: avoid_print
      print('[PurchaseService] purchase failed (unknown): $err');
      lastErrorMessage = err.toString();
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

  /// Map a RevenueCat error code + raw message into something a user
  /// (and a reviewer, and us) can read. Most of these only fire on
  /// Android because Play Billing is more chatty than StoreKit.
  static String _humanise(PurchasesErrorCode? code, String? raw) {
    switch (code) {
      case PurchasesErrorCode.productNotAvailableForPurchaseError:
        return 'Product not available in your store. The Offering may '
               'not be live yet on Play Console / App Store Connect.';
      case PurchasesErrorCode.productAlreadyPurchasedError:
        return 'You already own this. Try Restore Purchases.';
      case PurchasesErrorCode.storeProblemError:
        return 'Play Store / App Store reported a problem. Try again.';
      case PurchasesErrorCode.purchaseNotAllowedError:
        return 'Purchases are blocked on this device — check parental '
               'controls or sign in to a Play / Apple account that has '
               'IAP enabled.';
      case PurchasesErrorCode.purchaseInvalidError:
        return 'The store rejected the purchase as invalid.';
      case PurchasesErrorCode.networkError:
        return 'Network error. Check your connection and try again.';
      case PurchasesErrorCode.configurationError:
        return 'Billing not configured. Sideloaded APKs cannot purchase '
               '— install via Play Store internal testing track.';
      case PurchasesErrorCode.unsupportedError:
        return 'Billing isn\'t supported on this device or build.';
      case PurchasesErrorCode.invalidReceiptError:
        return 'The store returned an invalid receipt.';
      case PurchasesErrorCode.invalidAppUserIdError:
        return 'Invalid app user ID.';
      default:
        return raw ?? 'Purchase failed (${code?.name ?? "unknown"}).';
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
