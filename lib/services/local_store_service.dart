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

  // ── Subscription stub (wired to real IAP later) ─────────────────────────
  static Future<bool> isSubscribed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSubscribed) ?? false;
  }

  static Future<void> setSubscribed(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSubscribed, v);
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
