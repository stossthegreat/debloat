import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scan_record.dart';

/// v279 — active Pro subscription type. Lives here (not in
/// PurchaseService) so LocalStoreService can read it for cap-window
/// decisions without creating a circular import.
enum ProTier { none, weekly, annual }

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
  /// Free-tier SCAN allowance — ONE scan, period. The onboarding
  /// face-scan is the only free scan a non-pro user will ever do;
  /// every subsequent scan attempt routes straight to the paywall
  /// regardless of how many weeks have passed. Marked at the
  /// SUCCESS path of /scan after the geometry lands.
  static const _kScanFreeUsed = 'scan.free.used.v1';

  // ── Usage caps (paywall flood gates) ──────────────────────────────────
  // All caps live on a per-user rolling weekly window so the
  // entitlements match the Weekly + Annual SKU pair. Both Weekly
  // and Annual subscribers see the SAME per-week caps (annual just
  // pays once for a year of weekly access at a discount).
  //
  // Final spec bro locked in v238:
  //   · 2 scans per week
  //   · 3 mirror renders per week
  //   · 30 screenshot rizz analyses per week
  //   · 10 minutes of live AI roleplay per week
  //     (= 5 sessions × 2 min, the "game lessons")
  //   · 3 eye-contact lessons per week
  //   · Unlimited AI chat rizz (text is cheap, no cap)
  //   · Per-session voice cap of 2 min (free_flow_screen.dart enforces)
  // v279 — Pro cap numbers tuned for Month-1 cash flow (Apple's
  // ~33-45 day payout lag means OpenAI / Replicate get paid before
  // we do). Voice 18 → 15 saved ~$0.15/wk per heavy user. Screenshots
  // 15 → 30 costs ~$0.045/wk extra but reads as abundance on the
  // App Store screenshots. Net Month-1 burn drops ~$1,500 at 5K
  // Pro converts. See UNIT_ECONOMICS.md Scenario B.
  //
  // v350 — bro reworked the Game tab into 2-minute "lessons": voice
  // dropped 15 → 10 min/week (5 sessions × 2 min) and the roleplay
  // per-session ceiling dropped 3 → 2 min. Eye-contact training
  // graduated into its own tab (replacing Rizz) with a 3-lesson
  // weekly Pro allowance folded into the ascension plan.
  //
  // Annual subscribers get the SAME per-period numbers but on a
  // 30-day rolling window instead of 7 days. Same yearly total,
  // smoother consumption for committed users.
  static const int  kScansPerWeek        = 2;
  static const int  kRendersPerWeek      = 3;
  static const int  kScreenshotsPerWeek  = 30;
  static const int  kVoiceMinutesPerWeek = 10;
  static const int  kEyeLessonsPerWeek   = 4;

  static const _kScanWeekBucket        = 'caps.scan.week_bucket.v1';
  static const _kScanWeekCount         = 'caps.scan.week_count.v1';
  // Voice + render + screenshot caps live in weekly buckets.
  // Legacy month-bucket keys stay defined below so the existing
  // read paths keep returning sensible values for old data, but
  // the new gates use the week-bucket keys exclusively.
  static const _kVoiceWeekBucket       = 'caps.voice.week_bucket.v1';
  static const _kVoiceWeekMs           = 'caps.voice.week_ms.v1';
  static const _kRenderWeekBucket      = 'caps.render.week_bucket.v1';
  static const _kRenderWeekCount       = 'caps.render.week_count.v1';
  static const _kScreenshotWeekBucket  = 'caps.screenshot.week_bucket.v1';
  static const _kScreenshotWeekCount   = 'caps.screenshot.week_count.v1';
  // v350 — eye-contact lessons: 3 per rolling window (Pro allowance,
  // folded into the ascension plan). Same per-user anchor + window as
  // every other cap.
  static const _kEyeWeekBucket         = 'caps.eyes.week_bucket.v1';
  static const _kEyeWeekCount          = 'caps.eyes.week_count.v1';

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

  /// True once the user has consumed their ONE free face scan. The
  /// onboarding scan is the only free scan; after that every scan
  /// attempt by a non-pro user routes to the paywall. Marked at the
  /// /scan SUCCESS path, never on entry, so a user who bails before
  /// the geometry lands isn't penalised.
  static Future<bool> scanFreeUsed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kScanFreeUsed) ?? false;
  }

  static Future<void> markScanFreeUsed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kScanFreeUsed, true);
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

  // ── Cached subscription tier ───────────────────────────────────────────
  /// v279 — last known ProTier, written by PurchaseService whenever a
  /// RevenueCat customer-info refresh resolves. Read by the cap
  /// helpers below to pick the right reset window (weekly = 7 days,
  /// annual = 30 days). Synchronous-friendly so the cap surface
  /// doesn't have to await a network round-trip every check.
  static const _kCachedTier = 'sub.tier.v1';
  static Future<void> setCachedTier(ProTier tier) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCachedTier, tier.name);
  }
  static Future<ProTier> cachedTier() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kCachedTier);
    return ProTier.values.firstWhere(
      (t) => t.name == stored,
      orElse: () => ProTier.none,
    );
  }

  // ── Per-user rolling cap window ────────────────────────────────────────
  /// v278 — REPLACES the ISO-style _weekBucket that reset every Monday
  /// across all users. The Monday reset was exploitable: a user could
  /// subscribe Sunday 11pm, burn the full 18-min voice cap, then get
  /// the cap RESET 60 minutes later at Monday 00:00 and burn ANOTHER
  /// 18 minutes — 36 minutes of OpenAI Realtime time on one week's
  /// payment. Bro: "roleplay is the one place I can bleed."
  ///
  /// v279 — plan-aware window. Weekly subscribers reset every 7 days
  /// from anchor; annual subscribers reset every 30 days. Annual gets
  /// the same per-period cap numbers (15 voice min etc.) so they bank
  /// roughly 4× the per-window allowance — the trade-off for paying
  /// $139.99 up front instead of weekly.
  ///
  /// The fix: each user gets their OWN window anchored to the
  /// first time they ever hit a capped feature. Subscribe Monday →
  /// reset every Monday. Subscribe Thursday → reset every Thursday.
  /// Subscribe at 11pm Sunday → reset at 11pm Sunday seven days
  /// later. No global rollover, no Sunday/Monday double-dip.
  ///
  /// Applied uniformly to all four caps (scans / Mirror renders /
  /// screenshot rizz / voice minutes) — same code path, same anchor,
  /// same rolling 7-day window. Annual subscribers stay on the same
  /// 18min/week / 3 renders/week / 15 rizz/week / 2 scans/week
  /// numbers for now (separate decision; if bro picks new annual
  /// numbers later we add a plan-aware window helper).
  static const _kCapAnchorMs = 'caps.anchor_ms.v1';
  static const int _kWeekMs   = 7  * 24 * 60 * 60 * 1000;
  static const int _kMonthMs  = 30 * 24 * 60 * 60 * 1000;

  /// Read-or-stamp the cap anchor. The very first time ANY cap is
  /// touched, the anchor is set to now and persisted; every call
  /// thereafter returns the stable anchor so all four caps share the
  /// same per-user window.
  static Future<int> _capAnchor(SharedPreferences prefs) async {
    var anchor = prefs.getInt(_kCapAnchorMs) ?? 0;
    if (anchor == 0) {
      anchor = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(_kCapAnchorMs, anchor);
    }
    return anchor;
  }

  /// v279 — window length for the current Pro tier. Annual subs reset
  /// every 30 days, everyone else (weekly + free) every 7. Reads the
  /// cached tier so this stays synchronous.
  static Future<int> _windowMs(SharedPreferences prefs) async {
    final tier = await cachedTier();
    return tier == ProTier.annual ? _kMonthMs : _kWeekMs;
  }

  /// Rolling bucket index. Bucket 0 = first window-length after the
  /// anchor, bucket 1 = next window, etc. Window length is plan-
  /// aware (7 days for weekly, 30 days for annual).
  static int _rollingBucket(int anchorMs, int windowMs) {
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - anchorMs;
    return elapsedMs ~/ windowMs;
  }

  /// Wall-clock timestamp when the NEXT bucket starts. Used by the
  /// settings voice-cap tile to render "Resets 27 Jun" instead of
  /// the broken "resets Monday" hardcoded copy.
  static Future<DateTime> nextCapResetAt() async {
    final prefs = await SharedPreferences.getInstance();
    final anchor = await _capAnchor(prefs);
    final window = await _windowMs(prefs);
    final bucket = _rollingBucket(anchor, window);
    return DateTime.fromMillisecondsSinceEpoch(
      anchor + (bucket + 1) * window,
    );
  }

  // ── Weekly scan cap ─────────────────────────────────────────────────────
  /// How many scans the free user has consumed THIS window. Auto-
  /// resets to zero on the user's own 7-day rollover.
  static Future<int> scansThisWeek() async {
    final prefs = await SharedPreferences.getInstance();
    final bucket = _rollingBucket(await _capAnchor(prefs), await _windowMs(prefs));
    final stored = prefs.getInt(_kScanWeekBucket) ?? 0;
    if (stored != bucket) return 0;
    return prefs.getInt(_kScanWeekCount) ?? 0;
  }

  /// Increment the weekly scan count. Resets bucket + count if the
  /// user's 7-day window rolled over since the last write.
  static Future<void> markScanUsed() async {
    final prefs = await SharedPreferences.getInstance();
    final bucket = _rollingBucket(await _capAnchor(prefs), await _windowMs(prefs));
    final stored = prefs.getInt(_kScanWeekBucket) ?? 0;
    final count  = stored == bucket
        ? (prefs.getInt(_kScanWeekCount) ?? 0) + 1
        : 1;
    await prefs.setInt(_kScanWeekBucket, bucket);
    await prefs.setInt(_kScanWeekCount,  count);
  }

  // ── Weekly Mirror-render cap ───────────────────────────────────────────
  /// v238 — Mirror renders 3 per rolling 7-day window from the user's
  /// own anchor (v278 fixed the cross-user Monday rollover bleed).
  ///
  /// How many Mirror-tab image renders (`/maximize` + `/tryon`) the
  /// pro user has consumed THIS window.
  static Future<int> mirrorRendersThisWeek() async {
    final prefs = await SharedPreferences.getInstance();
    final bucket = _rollingBucket(await _capAnchor(prefs), await _windowMs(prefs));
    final stored = prefs.getInt(_kRenderWeekBucket) ?? 0;
    if (stored != bucket) return 0;
    return prefs.getInt(_kRenderWeekCount) ?? 0;
  }

  static Future<void> markMirrorRenderUsed() async {
    final prefs = await SharedPreferences.getInstance();
    final bucket = _rollingBucket(await _capAnchor(prefs), await _windowMs(prefs));
    final stored = prefs.getInt(_kRenderWeekBucket) ?? 0;
    final count  = stored == bucket
        ? (prefs.getInt(_kRenderWeekCount) ?? 0) + 1
        : 1;
    await prefs.setInt(_kRenderWeekBucket, bucket);
    await prefs.setInt(_kRenderWeekCount,  count);
    // Day stamp for the Ascend MIRROR mission + the daily streak — a
    // render counts as showing up today.
    final now = DateTime.now();
    await prefs.setInt(
        'render_done_ymd', now.year * 10000 + now.month * 100 + now.day);
  }

  // ── Weekly screenshot-rizz cap ─────────────────────────────────────────
  /// v238 — Pro users get 15 screenshot rizz analyses per rolling
  /// 7-day window from the user's own anchor.
  static Future<int> screenshotRizzThisWeek() async {
    final prefs = await SharedPreferences.getInstance();
    final bucket = _rollingBucket(await _capAnchor(prefs), await _windowMs(prefs));
    final stored = prefs.getInt(_kScreenshotWeekBucket) ?? 0;
    if (stored != bucket) return 0;
    return prefs.getInt(_kScreenshotWeekCount) ?? 0;
  }

  static Future<void> markScreenshotRizzUsed() async {
    final prefs = await SharedPreferences.getInstance();
    final bucket = _rollingBucket(await _capAnchor(prefs), await _windowMs(prefs));
    final stored = prefs.getInt(_kScreenshotWeekBucket) ?? 0;
    final count  = stored == bucket
        ? (prefs.getInt(_kScreenshotWeekCount) ?? 0) + 1
        : 1;
    await prefs.setInt(_kScreenshotWeekBucket, bucket);
    await prefs.setInt(_kScreenshotWeekCount,  count);
  }

  // ── Weekly voice-time cap (Pro AI roleplay) ────────────────────────────
  /// v238 — voice cap moved from 40 min/month to 18 min/week. Tracked
  /// as elapsed milliseconds so a 30-second hold counts at real
  /// granularity, not as a full minute.
  ///
  /// v278 — bucket switched from the global ISO-week (Monday reset)
  /// to a per-user rolling 7-day window. Same 18min cap, but resets
  /// 7 days after each user's anchor — not at every global Monday
  /// midnight. Closes the most expensive bleed in the app:
  /// OpenAI Realtime at ~$0.04-0.05/min meant the Sunday-to-Monday
  /// double-dip cost ~$1.60+ per week per exploiter.
  static Future<int> voiceMsThisWeek() async {
    final prefs = await SharedPreferences.getInstance();
    final bucket = _rollingBucket(await _capAnchor(prefs), await _windowMs(prefs));
    final stored = prefs.getInt(_kVoiceWeekBucket) ?? 0;
    if (stored != bucket) return 0;
    return prefs.getInt(_kVoiceWeekMs) ?? 0;
  }

  /// Add to the voice elapsed-ms bucket for THIS window. Caller
  /// passes the duration of the just-completed session segment; the
  /// bucket auto-resets if the user's 7-day window rolled over.
  static Future<void> addVoiceMs(int deltaMs) async {
    if (deltaMs <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final bucket = _rollingBucket(await _capAnchor(prefs), await _windowMs(prefs));
    final stored = prefs.getInt(_kVoiceWeekBucket) ?? 0;
    final base = stored == bucket
        ? (prefs.getInt(_kVoiceWeekMs) ?? 0)
        : 0;
    await prefs.setInt(_kVoiceWeekBucket, bucket);
    await prefs.setInt(_kVoiceWeekMs,     base + deltaMs);
  }

  /// True when the Pro user has used up their weekly voice allowance.
  static Future<bool> voiceCapReached() async {
    final ms = await voiceMsThisWeek();
    return ms >= kVoiceMinutesPerWeek * 60 * 1000;
  }

  /// True when the Pro user has used up their weekly screenshot rizz
  /// allowance. Used by the Rizz tab's screenshot-upload gate.
  static Future<bool> screenshotRizzCapReached() async {
    final used = await screenshotRizzThisWeek();
    return used >= kScreenshotsPerWeek;
  }

  // ── Weekly eye-contact lesson cap (Pro) ────────────────────────────────
  /// v350 — how many eye-contact lessons the Pro user has completed
  /// THIS window. Resets on the user's own rolling window rollover.
  static Future<int> eyeLessonsThisWeek() async {
    final prefs = await SharedPreferences.getInstance();
    final bucket = _rollingBucket(await _capAnchor(prefs), await _windowMs(prefs));
    final stored = prefs.getInt(_kEyeWeekBucket) ?? 0;
    if (stored != bucket) return 0;
    return prefs.getInt(_kEyeWeekCount) ?? 0;
  }

  /// Increment the weekly eye-contact lesson count AND stamp today as
  /// the last eye-contact completion day (drives the Ascend "EYE
  /// CONTACT" mission tick + the daily streak). Called once per scored
  /// gaze session from EyesSessionScreen.
  static Future<void> markEyeLessonUsed() async {
    final prefs = await SharedPreferences.getInstance();
    final bucket = _rollingBucket(await _capAnchor(prefs), await _windowMs(prefs));
    final stored = prefs.getInt(_kEyeWeekBucket) ?? 0;
    final count  = stored == bucket
        ? (prefs.getInt(_kEyeWeekCount) ?? 0) + 1
        : 1;
    await prefs.setInt(_kEyeWeekBucket, bucket);
    await prefs.setInt(_kEyeWeekCount,  count);
    final now = DateTime.now();
    await prefs.setInt(
        'eyes_done_ymd', now.year * 10000 + now.month * 100 + now.day);
  }

  /// True when the Pro user has used up their weekly eye-contact
  /// lesson allowance (3/week).
  static Future<bool> eyeLessonsCapReached() async {
    final used = await eyeLessonsThisWeek();
    return used >= kEyeLessonsPerWeek;
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
