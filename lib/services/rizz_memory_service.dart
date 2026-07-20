import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// v271 — RIZZ MEMORY.
///
/// All three named rizz competitors (Rizz AI, Plug AI, Wing AI) get
/// hammered in their App Store reviews for one specific gap:
///
///   *"didn't know 12 hours had passed, didn't know how to link
///    previous talking points"*  — Wing AI 1★ review
///
/// Users upload TWO screenshots from the same conversation hours
/// apart, and the model treats each as a fresh thread. No memory of
/// "she went cold yesterday" or "we matched last week, third date
/// next Friday" carries forward. Each call is a blank slate.
///
/// ImHim Looks closes the gap with a tiny on-device memory layer. After
/// every successful rizz generate we stash a compact entry (vibe +
/// context blurb + scenario + timestamp). On the next generate we
/// build a short "RECENT THREADS" prefix from the last 3 entries
/// and prepend it to the `ctx` field the backend already accepts.
///
/// Zero backend changes — the prefix rides inside the existing ctx
/// payload. Zero added cost — same /rizz/reply call, same model,
/// ~50-80 extra prompt tokens on subsequent calls (rounding error
/// at gpt-4o-mini's $0.15/1M input rate).
///
/// Storage: one SharedPreferences key, JSON list. Capped at 5
/// entries so the prompt prefix stays compact and we don't surface
/// stale 3-week-old context that's no longer relevant. Per-device
/// only — no account, no server sync, GDPR-clean.
class RizzMemoryService {
  static const _key = 'rizz_thread_memory_v1';

  /// Hard cap on stored entries. Keep this small — older entries
  /// stop being useful past 1-2 weeks and just bloat the prompt.
  static const _maxEntries = 5;

  /// How many of the most-recent entries actually get serialized
  /// into the prompt prefix. We stash 5 so the cap survives a
  /// fast-tap re-roll without losing history, but only the most
  /// recent 3 ride into the next call's ctx (anything older is
  /// noise that hurts more than it helps).
  static const _maxIncludedInPrompt = 3;

  /// Auto-evict entries older than this. A 14-day-old "she's my
  /// hinge match from last week" line is misleading by the time
  /// the user opens rizz again — they're probably texting someone
  /// else by then.
  static const _maxAgeDays = 14;

  /// Record one successful rizz interaction. Fire-and-forget after
  /// the backend returns 3 replies cleanly. Empty `ctx` is fine —
  /// we still log the vibe + scenario, which on their own help the
  /// next call match the user's voice.
  static Future<void> recordInteraction({
    required String vibe,        // tone preset (flirty, sensual, …)
    String ctx = '',             // user-typed context blurb
    String scenario = '',        // active scenario chip ("Make a move", …)
    bool hadImage = false,       // whether this was a screenshot call
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = _readList(prefs);

    final entry = <String, dynamic>{
      'ts':       DateTime.now().millisecondsSinceEpoch,
      'vibe':     vibe,
      'ctx':      ctx.trim(),
      'scenario': scenario.trim(),
      'hadImage': hadImage,
    };

    list.insert(0, entry);
    while (list.length > _maxEntries) {
      list.removeLast();
    }

    await prefs.setString(_key, json.encode(list));
  }

  /// Build the prefix block we prepend to the backend `ctx` param
  /// on the next generate. Returns empty string when there's no
  /// usable memory (fresh device, all entries expired, etc.) so
  /// the caller can concat unconditionally.
  static Future<String> buildContextPrefix() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _readList(prefs);
    if (list.isEmpty) return '';

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final cutoff = nowMs - (_maxAgeDays * 24 * 60 * 60 * 1000);
    final fresh = list
        .where((e) => (e['ts'] as int? ?? 0) >= cutoff)
        .take(_maxIncludedInPrompt)
        .toList();
    if (fresh.isEmpty) return '';

    final buf = StringBuffer();
    buf.writeln('RECENT RIZZ THREADS (most recent first — use only '
                'when they\'re clearly the same conversation):');
    for (final e in fresh) {
      final ts = e['ts'] as int? ?? 0;
      final ageMins = ((nowMs - ts) / 60000).round();
      final ageStr = _humanAge(ageMins);
      final ctx = (e['ctx'] as String? ?? '').trim();
      final vibe = (e['vibe'] as String? ?? '').trim();
      final scn = (e['scenario'] as String? ?? '').trim();
      final parts = <String>[
        if (ctx.isNotEmpty)  'ctx="$ctx"',
        if (vibe.isNotEmpty) 'tone=$vibe',
        if (scn.isNotEmpty)  'angle="$scn"',
      ];
      buf.writeln('  - $ageStr ago · ${parts.join(" · ")}');
    }
    return buf.toString();
  }

  /// Wipe the lot — wired through Settings → Delete my account so
  /// account-deletion is genuinely complete.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static List<Map<String, dynamic>> _readList(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String _humanAge(int minutes) {
    if (minutes < 1) return 'just now';
    if (minutes < 60) return '${minutes}m';
    final hours = minutes / 60;
    if (hours < 24) return '${hours.round()}h';
    final days = hours / 24;
    return '${days.round()}d';
  }
}
