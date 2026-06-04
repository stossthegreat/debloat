import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scan_record.dart';

/// Single source of truth for everything persisted on-device.
///
/// Retention depends on this layer being stable — the progress chart, the
/// generation gallery, the active-protocol check-in card, and the AI
/// advisor's memory of "last scan" all read from here. Keep writes atomic.
class LocalStoreService {
  static const _kScans        = 'scans.v1';
  static const _kGenerations  = 'generations.v1';
  static const _kActiveProto  = 'protocol.active.v1';
  static const _kSubscribed   = 'subscription.active.v1';
  static const _kOnboarded    = 'onboarded.v1';
  /// AI third-party data sharing consent (App Store guideline 5.1.2(i)).
  /// User must explicitly tap ALLOW in [AiConsentDialog] before the
  /// scan flow transmits the selfie photo to OpenAI / Replicate.
  static const _kAiConsent    = 'ai.consent.v1';
  /// User's chosen "glow-up style" — drives whether analysis prose,
  /// rendered previews, and Mirror-tab thumbnails are tuned for men's
  /// grooming, women's beauty, or general/either. Stored as one-letter
  /// codes so it round-trips cleanly through the API JSON payload.
  ///   'm' → men's grooming
  ///   'f' → women's beauty
  ///   null → unspecified (backend defaults to general)
  static const _kUserGender   = 'user.gender.v1';
  /// Free-tier allowance flags for the Auralay Eyes + Game tabs. A
  /// non-subscribed user gets exactly ONE eye-contact lesson and ONE
  /// Free Flow live conversation; both are consumed on first open and
  /// thereafter route to the paywall. Subscribers / kBypassPaywall
  /// ignore these entirely.
  static const _kEyesFreeUsed = 'eyes.free.used.v1';
  static const _kGameFreeUsed = 'game.free.used.v1';

  // ── Scans ────────────────────────────────────────────────────────────────
  static Future<List<ScanRecord>> loadScans() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kScans) ?? const [];
    return list.map((s) {
      try {
        return ScanRecord.fromJson(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) { return null; }
    }).whereType<ScanRecord>().toList()
      ..sort((a, b) => b.takenAt.compareTo(a.takenAt));
  }

  static Future<void> saveScan(ScanRecord r) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kScans) ?? const <String>[];
    final updated = [...list, jsonEncode(r.toJson())];
    // Cap at 200 records — covers multi-year weekly rescans with headroom.
    final trimmed = updated.length > 200
        ? updated.sublist(updated.length - 200)
        : updated;
    await prefs.setStringList(_kScans, trimmed);
  }

  static Future<ScanRecord?> latestScan() async {
    final all = await loadScans();
    return all.isEmpty ? null : all.first;
  }

  static Future<void> clearScans() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kScans);
  }

  // ── Generations (AI-rendered images) ─────────────────────────────────────
  static Future<List<GenerationRecord>> loadGenerations() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kGenerations) ?? const [];
    return list.map((s) {
      try {
        return GenerationRecord.fromJson(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) { return null; }
    }).whereType<GenerationRecord>().toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static Future<void> saveGeneration(GenerationRecord g) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kGenerations) ?? const <String>[];
    final updated = [...list, jsonEncode(g.toJson())];
    final trimmed = updated.length > 500
        ? updated.sublist(updated.length - 500)
        : updated;
    await prefs.setStringList(_kGenerations, trimmed);
  }

  // ── Protocol (active 60-day program) ─────────────────────────────────────
  //
  // Two storage shapes coexist:
  //   • _kActiveProto  : SINGLE-PROTOCOL legacy key (one active at a time).
  //                      Kept for backward compat with installed builds.
  //   • protocol.active.<axis> : per-axis keys so the user can run multiple
  //                              protocols in parallel — SKIN + JAW + DEBLOAT
  //                              + HAIR all live as independent runs each
  //                              with their own day counter, streak, and
  //                              completion log. Bro: "they should be able
  //                              to commit them all."
  //
  // First call to loadAllProtocols() migrates the legacy single-protocol
  // value into its targetAxis-keyed slot so existing users don\'t lose
  // their run.

  static String _protocolKeyFor(String axis) =>
      'protocol.active.${axis.toLowerCase().replaceAll(' ', '_')}';

  static Future<Map<String, dynamic>?> loadProtocolJson() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_kActiveProto);
    if (s == null) return null;
    try { return jsonDecode(s) as Map<String, dynamic>; } catch (_) { return null; }
  }

  static Future<void> saveProtocolJson(Map<String, dynamic>? j) async {
    final prefs = await SharedPreferences.getInstance();
    if (j == null) {
      await prefs.remove(_kActiveProto);
    } else {
      await prefs.setString(_kActiveProto, jsonEncode(j));
    }
  }

  /// Read the per-axis active protocol slot. Falls back to the legacy
  /// single-active value if the per-axis slot is empty AND the legacy
  /// value\'s targetAxis matches — one-time migration on read.
  static Future<Map<String, dynamic>?> loadProtocolJsonFor(String axis) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _protocolKeyFor(axis);
    final s = prefs.getString(key);
    if (s != null) {
      try { return jsonDecode(s) as Map<String, dynamic>; } catch (_) {}
    }
    // Legacy migration — if the old single-active slot holds a run for
    // THIS axis, copy it under the new per-axis key.
    final legacy = await loadProtocolJson();
    if (legacy != null && legacy['targetAxis'] == axis) {
      await prefs.setString(key, jsonEncode(legacy));
      await prefs.remove(_kActiveProto);
      return legacy;
    }
    return null;
  }

  /// Write a protocol into its per-axis slot. Passing null removes the
  /// slot. Does not touch other axes.
  static Future<void> saveProtocolJsonFor(
      String axis, Map<String, dynamic>? j) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _protocolKeyFor(axis);
    if (j == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, jsonEncode(j));
    }
  }

  /// Load every active protocol the user has committed to. Returns a
  /// map keyed by canonical axis name. Empty when no protocols are
  /// running. Also performs the legacy migration: if the old
  /// single-active slot is populated, it\'s lifted into the new
  /// per-axis storage on first call and removed from the legacy key.
  static Future<Map<String, Map<String, dynamic>>> loadAllProtocols() async {
    final prefs  = await SharedPreferences.getInstance();
    final result = <String, Map<String, dynamic>>{};

    // Migrate legacy single-active value if present and not already
    // copied across.
    final legacy = await loadProtocolJson();
    if (legacy != null) {
      final axis = legacy['targetAxis'] as String?;
      if (axis != null) {
        final key = _protocolKeyFor(axis);
        if (prefs.getString(key) == null) {
          await prefs.setString(key, jsonEncode(legacy));
        }
        await prefs.remove(_kActiveProto);
      }
    }

    // Scan every key beginning with the per-axis prefix.
    for (final k in prefs.getKeys()) {
      if (!k.startsWith('protocol.active.')) continue;
      final raw = prefs.getString(k);
      if (raw == null) continue;
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final axis = j['targetAxis'] as String?;
        if (axis != null) result[axis] = j;
      } catch (_) {/* skip corrupted slot */}
    }
    return result;
  }

  // ── Subscription stub (wired to real IAP later) ─────────────────────────
  static Future<bool> isSubscribed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSubscribed) ?? false;
  }

  static Future<void> setSubscribed(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSubscribed, v);
  }

  // ── Free-tier allowance: Eyes + Game (Auralay tabs) ─────────────────────
  /// True once the free eye-contact lesson has been opened. Set the
  /// moment the session screen is pushed so a free user gets exactly
  /// one, even if they back out.
  static Future<bool> eyesFreeUsed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEyesFreeUsed) ?? false;
  }

  static Future<void> markEyesFreeUsed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEyesFreeUsed, true);
  }

  /// True once the free Free Flow live conversation has been opened.
  static Future<bool> gameFreeUsed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kGameFreeUsed) ?? false;
  }

  static Future<void> markGameFreeUsed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGameFreeUsed, true);
  }

  // ── Onboarding (has the user completed first-run?) ──────────────────────
  static Future<bool> isOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboarded) ?? false;
  }

  static Future<void> setOnboarded(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboarded, v);
  }

  // ── AI third-party data sharing consent ─────────────────────────────────
  /// True once the user has tapped ALLOW in the AI consent dialog
  /// disclosing that the selfie photo is transmitted to OpenAI and
  /// Replicate. Persisted across launches so we ask once, not every
  /// scan. Required by App Store guideline 5.1.2(i): explicit
  /// permission must be obtained before sharing personal data with
  /// third-party AI services.
  static Future<bool> hasAiConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAiConsent) ?? false;
  }

  static Future<void> setAiConsent(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAiConsent, v);
  }

  // ── Glow-up style (gender preference) ───────────────────────────────────
  /// Returns 'm', 'f', or null (unspecified). When null the rest of
  /// the app behaves identically to the pre-gender version — the
  /// backend treats absence of `gender` in the request body the same
  /// as its old default. So a user who never picks one isn't broken.
  static Future<String?> userGender() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kUserGender);
    if (raw == 'm' || raw == 'f') return raw;
    return null;
  }

  static Future<void> setUserGender(String? code) async {
    final prefs = await SharedPreferences.getInstance();
    if (code == null) {
      await prefs.remove(_kUserGender);
    } else {
      assert(code == 'm' || code == 'f',
          'userGender must be "m", "f", or null');
      await prefs.setString(_kUserGender, code);
    }
  }

  // ── Nuke ────────────────────────────────────────────────────────────────
  /// Wipe every on-device user-generated key (scans, generations,
  /// protocol). Subscription and onboarding flags are preserved —
  /// subscription is the source of truth from RevenueCat anyway, and
  /// forgetting onboarding would throw a paid user back onto the
  /// onboarding flow which is worse UX than honouring their purchase.
  /// Used by Settings → Delete all data.
  static Future<void> clearAllUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kScans);
    await prefs.remove(_kGenerations);
    await prefs.remove(_kActiveProto);
  }
}
