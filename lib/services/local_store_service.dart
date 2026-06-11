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
  /// Per-session Lucien scorecard history. Each entry is the score
  /// the AI returned at the end of a Free Flow session, with the
  /// epoch-millis timestamp of when it was scored. Powers the
  /// "GAME · OVER TIME" chart on the Progress page so the user can
  /// see their roleplay arc, not just the latest number.
  static const _kGameScores   = 'game.scores.v1';
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
  /// Free-tier RIZZ allowance — ONE screenshot rizz upload before paywall.
  /// LINES + CHAT cards are LOCKED for free users entirely; only the
  /// screenshot generator gets a single free preview.
  static const _kRizzScreenshotFreeUsed = 'rizz.screenshot.free.used.v1';

  // ── Usage caps (paywall flood gates) ──────────────────────────────────
  // Bro: "two scans a week and 10 mirror tab image renders a month.
  // That's what we had working before — now it's like the flood gates
  // are open. Nothing for free."
  //
  // Scans are bucketed by ISO week (Mon-Sun) so the limit resets cleanly
  // every Monday. Mirror renders are bucketed by calendar month so the
  // limit resets on the 1st. Subscribers / kBypassPaywall bypass both.
  static const int  kScansPerWeek      = 2;
  static const int  kRendersPerMonth   = 10;
  /// Bro v5: "40 mins roleplay time for monthly every month regardless
  /// of weather yearly or monthly just every month." Pro voice ceiling
  /// — tracked as elapsed milliseconds so a 30-second hold counts at
  /// real granularity, not as a full minute.
  static const int  kVoiceMinutesPerMonth = 40;
  static const _kScanWeekBucket    = 'caps.scan.week_bucket.v1';
  static const _kScanWeekCount     = 'caps.scan.week_count.v1';
  static const _kVoiceMonthBucket  = 'caps.voice.month_bucket.v1';
  static const _kVoiceMonthMs      = 'caps.voice.month_ms.v1';
  static const _kRenderMonthBucket = 'caps.render.month_bucket.v1';
  static const _kRenderMonthCount  = 'caps.render.month_count.v1';

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

  // ── Game scores (Lucien scorecards over time) ────────────────────────────
  static Future<List<GameScoreEntry>> loadGameScores() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kGameScores) ?? const [];
    return list.map((s) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        return GameScoreEntry(
          score:   (m['score']  as num).toInt(),
          takenAt: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
        );
      } catch (_) { return null; }
    }).whereType<GameScoreEntry>().toList()
      ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  }

  static Future<void> saveGameScore(int score) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kGameScores) ?? const <String>[];
    final entry = jsonEncode({
      'score': score.clamp(0, 100),
      'ts':    DateTime.now().millisecondsSinceEpoch,
    });
    final updated = [...list, entry];
    final trimmed = updated.length > 200
        ? updated.sublist(updated.length - 200)
        : updated;
    await prefs.setStringList(_kGameScores, trimmed);
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

  /// True once the user has consumed their ONE free Free Flow live
  /// conversation. Flips when _endAndScore runs the post-session
  /// upsell modal (60-second timer expiry OR user-pressed end button
  /// OR voice-cap), which is the only legitimate "session ended" beat.
  /// Mid-session bails (back-tap, tab switch, brief press) do NOT
  /// flip this flag — see free_flow_screen.dart's dispose() which
  /// intentionally no longer writes it.
  ///
  /// v179 misadventure: I changed this to read the scored-session
  /// list and made markGameFreeUsed a no-op. That worked for pro
  /// users (whose _persistGame path writes a real scorecard), but
  /// free users skip _persistGame entirely — their session-end
  /// branch (line ~845 of free_flow_screen.dart) returns BEFORE
  /// the scoring call so it can show the Lucien upsell modal
  /// instead. Net result: free users could replay forever, no
  /// paywall ever fired, the 60-second timer never started ticking
  /// on the second character pick. v181 reverts to the bool flag
  /// and explicitly stops marking it on dispose().
  static Future<bool> gameFreeUsed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kGameFreeUsed) ?? false;
  }

  static Future<void> markGameFreeUsed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGameFreeUsed, true);
  }

  /// One-shot v181 migration — clears the gameFreeUsed bool ONCE
  /// for users coming off v171..v178 builds, where the dispose()
  /// path inside FreeFlowScreen over-eagerly marked the flag on any
  /// brief orb-press + tab switch. Those users were never able to
  /// kick off a free session again until v179 (which broke the
  /// other direction). v181 reverts the gate to the bool while
  /// flushing the stale value once so honest first-time users on
  /// the new build still get their 60-second pass.
  ///
  /// Safe to call on every launch — it persists its own
  /// "already migrated" marker and is a no-op on subsequent boots.
  static const _kGameFreeUsedV181Migrated = 'caps.game.flag_migrated_v181.v1';
  static Future<void> migrateGameFreeUsedFlagOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kGameFreeUsedV181Migrated) ?? false) return;
    await prefs.remove(_kGameFreeUsed);
    await prefs.setBool(_kGameFreeUsedV181Migrated, true);
  }

  /// True once the free Rizz screenshot generation has been consumed.
  /// One free screenshot rizz per non-pro user; LINES and CHAT cards
  /// are paywalled outright with no free preview.
  static Future<bool> rizzScreenshotFreeUsed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kRizzScreenshotFreeUsed) ?? false;
  }

  static Future<void> markRizzScreenshotFreeUsed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRizzScreenshotFreeUsed, true);
  }

  // ── Weekly scan cap ─────────────────────────────────────────────────────
  /// ISO-style week bucket key: year * 100 + ISO week number. Stable
  /// across timezones, rolls over Monday → Monday automatically.
  static int _weekBucket(DateTime now) {
    // Dart's `DateTime.weekday` is Mon=1..Sun=7. ISO week 1 is the week
    // containing the first Thursday. Use a simple approximation that's
    // close enough for paywall bucketing (off by 1 in edge weeks is fine
    // — the cap still resets weekly, just possibly on a different day).
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final jan1 = DateTime(monday.year, 1, 1);
    final weekNum = ((monday.difference(jan1).inDays) / 7).floor() + 1;
    return monday.year * 100 + weekNum;
  }

  /// How many scans the free user has consumed THIS week. Auto-resets
  /// to zero on bucket rollover (next Monday).
  static Future<int> scansThisWeek() async {
    final prefs = await SharedPreferences.getInstance();
    final bucket = _weekBucket(DateTime.now());
    final stored = prefs.getInt(_kScanWeekBucket) ?? 0;
    if (stored != bucket) return 0;
    return prefs.getInt(_kScanWeekCount) ?? 0;
  }

  /// Increment the weekly scan count. Resets bucket + count if the week
  /// rolled over since the last write.
  static Future<void> markScanUsed() async {
    final prefs = await SharedPreferences.getInstance();
    final bucket = _weekBucket(DateTime.now());
    final stored = prefs.getInt(_kScanWeekBucket) ?? 0;
    final count  = stored == bucket
        ? (prefs.getInt(_kScanWeekCount) ?? 0) + 1
        : 1;
    await prefs.setInt(_kScanWeekBucket, bucket);
    await prefs.setInt(_kScanWeekCount,  count);
  }

  // ── Monthly Mirror-render cap ──────────────────────────────────────────
  static int _monthBucket(DateTime now) => now.year * 100 + now.month;

  /// How many Mirror-tab image renders (`/maximize` + `/tryon`) the free
  /// user has consumed THIS calendar month. Auto-resets on the 1st.
  static Future<int> mirrorRendersThisMonth() async {
    final prefs = await SharedPreferences.getInstance();
    final bucket = _monthBucket(DateTime.now());
    final stored = prefs.getInt(_kRenderMonthBucket) ?? 0;
    if (stored != bucket) return 0;
    return prefs.getInt(_kRenderMonthCount) ?? 0;
  }

  static Future<void> markMirrorRenderUsed() async {
    final prefs = await SharedPreferences.getInstance();
    final bucket = _monthBucket(DateTime.now());
    final stored = prefs.getInt(_kRenderMonthBucket) ?? 0;
    final count  = stored == bucket
        ? (prefs.getInt(_kRenderMonthCount) ?? 0) + 1
        : 1;
    await prefs.setInt(_kRenderMonthBucket, bucket);
    await prefs.setInt(_kRenderMonthCount,  count);
  }

  // ── Monthly voice-time cap (Pro AI roleplay) ───────────────────────────
  /// Total voice elapsed THIS month, in milliseconds. Resets on the 1st.
  static Future<int> voiceMsThisMonth() async {
    final prefs = await SharedPreferences.getInstance();
    final bucket = _monthBucket(DateTime.now());
    final stored = prefs.getInt(_kVoiceMonthBucket) ?? 0;
    if (stored != bucket) return 0;
    return prefs.getInt(_kVoiceMonthMs) ?? 0;
  }

  /// Add to the voice elapsed-ms bucket for THIS month. Caller passes
  /// the duration of the just-completed session segment; the bucket
  /// auto-resets if we've crossed into a new month.
  static Future<void> addVoiceMs(int deltaMs) async {
    if (deltaMs <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final bucket = _monthBucket(DateTime.now());
    final stored = prefs.getInt(_kVoiceMonthBucket) ?? 0;
    final base = stored == bucket
        ? (prefs.getInt(_kVoiceMonthMs) ?? 0)
        : 0;
    await prefs.setInt(_kVoiceMonthBucket, bucket);
    await prefs.setInt(_kVoiceMonthMs,     base + deltaMs);
  }

  /// True when the Pro user has used up their monthly voice allowance.
  static Future<bool> voiceCapReached() async {
    final ms = await voiceMsThisMonth();
    return ms >= kVoiceMinutesPerMonth * 60 * 1000;
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
