import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

import '../config/purchase_config.dart';
import 'analytics_service.dart';
import 'local_store_service.dart' show LocalStoreService, ProTier;

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

  /// Diagnostic snapshot of the last RevenueCat fetch. Populated by
  /// loadOfferings() and surfaced via diagnose() so the paywall can show
  /// *exactly* what RC returned on this device — useful when "it works
  /// on iOS but not Android" and the user can't read adb logcat.
  static String? lastDiagnostic;

  /// Walk RevenueCat end-to-end and produce a one-paragraph summary of
  /// the SDK state on this device. Safe to call any time. The output
  /// is intentionally short so it fits in a snackbar.
  static Future<String> diagnose() async {
    final lines = <String>[];
    lines.add('Platform: ${Platform.isIOS ? "iOS" : "Android"}');
    lines.add('Configured: ${PurchaseConfig.isConfigured}');
    lines.add('Initialised: $_initialized');
    if (!_initialized) {
      lines.add('→ Init never ran. Check API key in purchase_config.dart.');
      return lines.join('\n');
    }
    try {
      final offerings = await Purchases.getOfferings();
      final cur = offerings.current;
      lines.add('Offerings.all keys: ${offerings.all.keys.toList()}');
      if (cur == null) {
        lines.add('→ No CURRENT offering. Publish a Default Offering in '
                  'RevenueCat dashboard and mark it Current.');
      } else {
        lines.add('Current offering: "${cur.identifier}"');
        lines.add('Packages: ${cur.availablePackages.length}');
        for (final p in cur.availablePackages) {
          lines.add('  · pkg "${p.identifier}" → '
                    '${p.storeProduct.identifier} '
                    '(${p.storeProduct.priceString})');
        }
        if (cur.availablePackages.isEmpty) {
          lines.add('→ Offering exists but has 0 packages. Attach products '
                    'in dashboard → Offerings → Default Offering.');
        }
      }
    } catch (err) {
      lines.add('getOfferings threw: $err');
    }
    try {
      final info = await Purchases.getCustomerInfo();
      lines.add('Active entitlements: '
                '${info.entitlements.active.keys.toList()}');
      lines.add('Active subscriptions: ${info.activeSubscriptions.toList()}');
      lines.add('All purchased products: '
                '${info.allPurchasedProductIdentifiers.toList()}');
      lines.add('App user id: ${info.originalAppUserId}');
      final pro = info.entitlements.all[PurchaseConfig.proEntitlementId];
      lines.add('"pro" entitlement: '
                '${pro == null ? "NOT FOUND" : "active=${pro.isActive}, "
                    "product=${pro.productIdentifier}"}');
    } catch (err) {
      lines.add('getCustomerInfo threw: $err');
    }
    final out = lines.join('\n');
    lastDiagnostic = out;
    return out;
  }

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

  /// Fetch the current RevenueCat Offering. By default re-hits RC every
  /// call so dashboard changes (newly published Offering, package
  /// added, product attached) show up the next time the paywall opens
  /// without needing an app restart. Pass `useCache: true` only when
  /// you've genuinely got a fresh load and want to skip the network.
  ///
  /// When the SDK isn't configured or the fetch fails, returns empty
  /// nulls for every slot so the paywall falls back to placeholder
  /// prices (real RC prices replace them whenever a real Offering
  /// arrives).
  static Future<PurchaseOfferings> loadOfferings({bool useCache = false}) async {
    if (useCache && _cached != null) return _cached!;
    if (!_initialized) return PurchaseOfferings.empty();

    try {
      final offerings = await Purchases.getOfferings();
      // Prefer the dashboard-marked Current offering. If nothing is
      // marked Current (common when the project has a single
      // non-default offering like the Android-only "Month/Apk"
      // offering visible in the RC dashboard), fall back to the
      // first offering in `offerings.all` so the paywall still gets
      // packages instead of leaving every price as "—".
      final current = offerings.current
          ?? (offerings.all.isNotEmpty ? offerings.all.values.first : null);
      if (current == null) {
        // Don't cache "no offerings at all" — let the next open retry.
        _cached = null;
        return PurchaseOfferings.empty();
      }

      Package? weekly;
      Package? annual;
      Package? rescue;
      // v284 — pass 2 holding bucket. Anything that doesn't match a
      // canonical slot on the first pass lands here so we can claim
      // it as weekly if the matcher missed (bro's iOS weekly product
      // was set up after annual and the SKU id didn't contain the
      // word "weekly", so the strict matcher rejected it). Annual is
      // assumed working — that's the one bro confirmed live.
      final leftovers = <Package>[];

      // Two paid tiers + the Android rescue IAP. Weekly is the
      // entry tier ($6.99/wk), Annual ($139.99/yr) is the lock-in.
      // Match by canonical RC slot first ($rc_weekly / $rc_annual +
      // the custom `rescue` slot), with fallback to bare strings and
      // underlying store-product ids so a misnamed dashboard package
      // still gets picked up.
      for (final pkg in current.availablePackages) {
        final pkgId = pkg.identifier.toLowerCase();
        final prodId = pkg.storeProduct.identifier.toLowerCase();

        final isRescue =
               pkgId == PurchaseConfig.offering.rescuePackage.toLowerCase()
            || pkgId.contains('rescue')
            || prodId.contains('rescue');

        // v284 — broadened from `weekly` only to also catch `week`,
        // `7day`, `7d`, and the canonical $rc_weekly slot. Same
        // lenient policy annual already enjoys via the `yearly`
        // alias. Bro's TestFlight weekly SKU was approved but the
        // strict matcher rejected it — broadening fixes it without
        // changing the dashboard config.
        final isWeekly = !isRescue && (
               pkgId == r'$rc_weekly'
            || pkgId == 'weekly'
            || pkgId.contains('week')
            || prodId.contains('week')
            || prodId.contains('7day')
            || prodId.contains('7d'));

        final isAnnual = !isRescue && !isWeekly && (
               pkgId == r'$rc_annual'
            || pkgId == 'annual' || pkgId == 'yearly'
            || pkgId.contains('annual')
            || pkgId.contains('year')
            || prodId.contains('annual')
            || prodId.contains('yearly')
            || prodId.contains('year'));

        if (isRescue && rescue == null) {
          rescue = pkg;
        } else if (isWeekly && weekly == null) {
          weekly = pkg;
        } else if (isAnnual && annual == null) {
          annual = pkg;
        } else if (!isRescue) {
          leftovers.add(pkg);
        }
      }

      // v284 — last-resort fallback. If the dashboard registered the
      // weekly product under a custom name the strict matcher missed
      // (e.g. `mirrorly_starter` or `pro_intro`), claim the first
      // remaining non-rescue, non-annual subscription as weekly. The
      // priceString the SDK returns is still the real StoreKit /
      // Play Billing price, so we ship the user the right number —
      // we just stop showing "—" for a SKU bro already has live.
      if (weekly == null && leftovers.isNotEmpty) {
        weekly = leftovers.first;
      }

      _cached = PurchaseOfferings(
        weekly: weekly,
        annual: annual,
        rescue: rescue,
      );
      return _cached!;
    } catch (err) {
      // ignore: avoid_print
      print('[PurchaseService] loadOfferings failed: $err');
      _cached = null;
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
    AnalyticsService.purchaseStarted(pkg.identifier);
    try {
      final result = await Purchases.purchasePackage(pkg);
      // Primary signal: the `pro` entitlement flipped active. FALLBACK:
      // the purchase produced an active subscription even though the
      // entitlement didn't flip — happens when a product (e.g. the
      // weekly SKU) isn't mapped to the `pro` entitlement in the
      // RevenueCat dashboard, or the mapping lags a beat behind the
      // StoreKit transaction. A completed subscription purchase IS a
      // paying user, so we must unlock either way — otherwise a real
      // payment unlocks nothing.
      final entActive = result.entitlements.all[PurchaseConfig.proEntitlementId]
          ?.isActive ?? false;
      // Belt-and-suspenders: unlock on the `pro` entitlement, OR any
      // active entitlement (covers a differently-named entitlement in
      // the dashboard), OR any active subscription (covers no entitlement
      // mapping at all). A completed subscription purchase must unlock.
      final isPro = entActive ||
          result.entitlements.active.isNotEmpty ||
          result.activeSubscriptions.isNotEmpty;
      // The rescue one-time IAP is a consumable in Play Console — it
      // may grant credits (and in the user's RC config, also activates
      // the `pro` entitlement) but treat any successful rescue
      // purchase as a success even if the entitlement hasn't flipped
      // yet, so the paywall doesn't surface a misleading
      // "entitlement didn't activate" toast on a completed purchase.
      final isRescue =
             pkg.identifier.toLowerCase() ==
                 PurchaseConfig.offering.rescuePackage.toLowerCase()
          || pkg.identifier.toLowerCase().contains('rescue')
          || pkg.storeProduct.identifier.toLowerCase().contains('rescue');
      if (isPro) {
        await LocalStoreService.setSubscribed(true);
      }
      if (isPro || isRescue) {
        AnalyticsService.purchaseCompleted(pkg.identifier);
        return PurchaseOutcome.success;
      }
      lastErrorMessage = 'Entitlement did not activate.';
      AnalyticsService.purchaseFailed(pkg.identifier, 'entitlement_inactive');
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
        AnalyticsService.purchaseCancelled(pkg.identifier);
        return PurchaseOutcome.cancelled;
      }
      lastErrorMessage = _humanise(code, err.message);
      AnalyticsService.purchaseFailed(pkg.identifier, code?.name ?? 'unknown');
      return PurchaseOutcome.error;
    } catch (err) {
      // ignore: avoid_print
      print('[PurchaseService] purchase failed (unknown): $err');
      lastErrorMessage = err.toString();
      AnalyticsService.purchaseFailed(pkg.identifier, 'exception');
      return PurchaseOutcome.error;
    }
  }

  /// Restore previously-purchased entitlements. Required by App Store
  /// review. Same return type as [purchase].
  static Future<PurchaseOutcome> restore() async {
    if (!_initialized) return PurchaseOutcome.notConfigured;
    try {
      final info = await Purchases.restorePurchases();
      // Entitlement OR any active subscription — same resilience as
      // purchase()/isProLive() so a weekly SKU that isn't mapped to the
      // `pro` entitlement still restores.
      final entActive = info.entitlements.all[PurchaseConfig.proEntitlementId]
          ?.isActive ?? false;
      final isPro = entActive ||
          info.entitlements.active.isNotEmpty ||
          info.activeSubscriptions.isNotEmpty;
      await LocalStoreService.setSubscribed(isPro);
      AnalyticsService.restoreCompleted(isPro);
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
      // Entitlement OR active subscription (see purchase()/isProLive()).
      final entActive = info.entitlements.all[PurchaseConfig.proEntitlementId]
          ?.isActive ?? false;
      final isPro = entActive ||
          info.entitlements.active.isNotEmpty ||
          info.activeSubscriptions.isNotEmpty;
      await LocalStoreService.setSubscribed(isPro);
    } catch (_) {
      // Network fail on launch is not fatal — the cached flag stands.
    }
  }

  /// Hit RevenueCat live for the *current* entitlement state. The
  /// cached `LocalStoreService.isSubscribed` flag exists for fast
  /// synchronous reads, but it can lag behind RevenueCat — sandbox /
  /// TestFlight purchases sometimes flip the entitlement only after a
  /// retry, and a paid user who opens the app on a cold network goes
  /// through the catch path in init(). Bro: "I've got a sub and it's
  /// locking me out." This call queries RC directly and as a side
  /// effect repaints the local cache so subsequent synchronous reads
  /// agree.
  ///
  /// v279 — currently-active subscription tier. Used by the cap logic
  /// so annual subscribers get a 30-day rolling reset window while
  /// weekly subscribers get the standard 7-day window. Cached locally
  /// after each RevenueCat hit so cap reads stay synchronous.
  static Future<ProTier> liveTier() async {
    if (!_initialized) return ProTier.none;
    try {
      final info = await Purchases.getCustomerInfo()
          .timeout(const Duration(seconds: 2));
      // The `activeSubscriptions` set contains store product
      // identifiers — match by canonical RC slot name first, then by
      // contains() on the legacy `mirrorly_pro_yearly` / similar.
      for (final sub in info.activeSubscriptions) {
        final lower = sub.toLowerCase();
        if (lower.contains('annual') ||
            lower.contains('yearly') ||
            lower.contains('year')) {
          await LocalStoreService.setCachedTier(ProTier.annual);
          return ProTier.annual;
        }
        if (lower.contains('weekly') || lower.contains('week')) {
          await LocalStoreService.setCachedTier(ProTier.weekly);
          return ProTier.weekly;
        }
      }
      await LocalStoreService.setCachedTier(ProTier.none);
      return ProTier.none;
    } catch (_) {
      return ProTier.none;
    }
  }

  /// Returns null when RC isn't initialised or the call failed — the
  /// caller falls back to the cached flag in that case.
  static Future<bool?> isProLive() async {
    if (!_initialized) return null;
    try {
      final info = await Purchases.getCustomerInfo();
      // Same resilience as purchase(): treat an active subscription as
      // pro even when the `pro` entitlement hasn't flipped (weekly SKU
      // not mapped to the entitlement, or RC lag). An active sub = a
      // paying user, so the whole app must unlock.
      final entActive = info.entitlements.all[PurchaseConfig.proEntitlementId]
          ?.isActive ?? false;
      final isPro = entActive ||
          info.entitlements.active.isNotEmpty ||
          info.activeSubscriptions.isNotEmpty;
      await LocalStoreService.setSubscribed(isPro);
      // v279 — also detect tier (weekly vs annual) and cache it so
      // the cap window helpers can read it synchronously without
      // hitting RC. Both calls share the same RC payload so it's a
      // single network round-trip.
      ProTier tier = ProTier.none;
      if (isPro) {
        for (final sub in info.activeSubscriptions) {
          final lower = sub.toLowerCase();
          if (lower.contains('annual') ||
              lower.contains('yearly') ||
              lower.contains('year')) {
            tier = ProTier.annual;
            break;
          }
          if (lower.contains('weekly') || lower.contains('week')) {
            tier = ProTier.weekly;
            break;
          }
        }
      }
      await LocalStoreService.setCachedTier(tier);
      return isPro;
    } catch (_) {
      return null;
    }
  }

  /// Map a RevenueCat error code + raw message into something a user
  /// (and a reviewer, and us) can read. Store names are
  /// platform-gated — Apple rejects copy that names "Google Play"
  /// and vice versa, even in error toasts.
  static String _humanise(PurchasesErrorCode? code, String? raw) {
    final store      = Platform.isIOS ? 'App Store'         : 'Play Store';
    final account    = Platform.isIOS ? 'Apple ID'          : 'Google account';
    final sideloadFix = Platform.isIOS
        ? 'install via TestFlight.'
        : 'install via Play Store internal testing track.';
    switch (code) {
      case PurchasesErrorCode.productNotAvailableForPurchaseError:
        return 'Product not available in your store. The offering may '
               'not be live yet.';
      case PurchasesErrorCode.productAlreadyPurchasedError:
        return 'You already own this. Try Restore Purchases.';
      case PurchasesErrorCode.storeProblemError:
        return 'The $store reported a problem. Try again.';
      case PurchasesErrorCode.purchaseNotAllowedError:
        return 'Purchases are blocked on this device — check parental '
               'controls or sign in to a $account that has IAP enabled.';
      case PurchasesErrorCode.purchaseInvalidError:
        return 'The store rejected the purchase as invalid.';
      case PurchasesErrorCode.networkError:
        return 'Network error. Check your connection and try again.';
      case PurchasesErrorCode.configurationError:
        return 'Billing not configured on this build — $sideloadFix';
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

/// Snapshot of the three products the paywall needs:
///   weekly / annual subscriptions + the rescue one-time IAP.
/// Nulls = package isn't in the current offering yet; the paywall
/// shows a dash for that slot until RC delivers it.
class PurchaseOfferings {
  final Package? weekly;
  final Package? annual;
  final Package? rescue;

  const PurchaseOfferings({
    required this.weekly,
    required this.annual,
    required this.rescue,
  });

  factory PurchaseOfferings.empty() => const PurchaseOfferings(
    weekly: null, annual: null, rescue: null,
  );
}
