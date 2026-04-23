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
