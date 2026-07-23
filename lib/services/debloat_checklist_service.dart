import 'package:flutter/material.dart' show IconData, Icons;
import 'package:shared_preferences/shared_preferences.dart';

/// THE DAILY DEBLOAT SYSTEM — the core loop of Debloat OS.
///
/// Twelve daily protocols, three time blocks, one goal: zero water
/// retention in the face. Every item is evidence-anchored:
///
///   • SODIUM / POTASSIUM — sodium is the #1 driver of facial water
///     retention; potassium is the counter-ion that helps the kidneys
///     excrete it. (~2g sodium ceiling, ~3.5g potassium target.)
///   • WATER — counter-intuitive but real: a dehydrated body HOLDS
///     water. Consistent 2.5–3L intake signals release.
///   • GLYCOGEN — every gram of stored carbohydrate binds ~3g of
///     water. Refeed nights show up in the face by morning.
///   • ALCOHOL — vasodilation + dehydration + wrecked sleep = the
///     classic morning puff. Clears in 12–24h once removed.
///   • SLEEP + ELEVATION — short sleep spikes cortisol ("cortisol
///     face"); lying flat pools fluid in the face overnight. 7–9h,
///     head slightly elevated, on your back.
///   • COLD + LYMPH + MOVEMENT — cold exposure vasoconstricts and
///     visibly de-puffs; the lymphatic system has no pump, so massage
///     and walking ARE the pump.
///
/// State: one SharedPreferences StringList per calendar day
/// (`checklist.done.<ymd>`) holding the ticked item ids. The first
/// tick of the day also stamps `looks_done_ymd` — the flag the streak
/// engine reads — so executing the system IS what keeps the flame
/// alive. Consistency (Ascend) is computed from done ÷ offered via
/// DailyMissionService, which reads this service.
class DebloatChecklistService {
  static const _kDonePrefix = 'checklist.done.'; // + ymd

  static int _ymd(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
  static int todayYmd() => _ymd(DateTime.now());

  // ── The system ─────────────────────────────────────────────────────

  /// All items, in render order. Stable ids — persisted, never rename.
  static const List<DebloatItem> items = [
    // ── MORNING FLUSH ──
    DebloatItem(
      id:    'ice_dunk',
      block: DebloatBlock.morning,
      title: 'Ice-water face dunk',
      why:   '30–60s, face to the hairline. Vasoconstriction flushes '
             'the overnight fluid — the fastest visible de-puff there is.',
      metric: '30–60s',
      icon:  Icons.ac_unit_rounded,
    ),
    DebloatItem(
      id:    'lymph_massage',
      block: DebloatBlock.morning,
      title: 'Lymphatic drainage massage',
      why:   'Gua sha or knuckles, light pressure: jaw → ear, cheek → '
             'temple, brow → hairline. The lymph system has no pump — '
             'this is the pump.',
      metric: '3 min',
      icon:  Icons.spa_rounded,
    ),
    DebloatItem(
      id:    'wake_water',
      block: DebloatBlock.morning,
      title: '500ml water on waking',
      why:   'You wake dehydrated, and a dehydrated body holds water. '
             'Rehydrate first, before the coffee.',
      metric: '500 ml',
      icon:  Icons.local_drink_rounded,
    ),
    DebloatItem(
      id:    'morning_walk',
      block: DebloatBlock.morning,
      title: 'Morning walk',
      why:   'Movement drives lymph and circulation. Ten minutes outside '
             'also anchors the circadian clock that runs cortisol.',
      metric: '10+ min',
      icon:  Icons.directions_walk_rounded,
    ),

    // ── INTAKE CONTROL ──
    DebloatItem(
      id:    'sodium_cap',
      block: DebloatBlock.day,
      title: 'Sodium under 2g',
      why:   'The #1 driver of facial water retention. Restaurants, '
             'sauces and bread hide most of it — read the labels.',
      metric: '< 2 g',
      icon:  Icons.grain,
    ),
    DebloatItem(
      id:    'potassium_target',
      block: DebloatBlock.day,
      title: 'Hit the potassium target',
      why:   'Potassium helps the kidneys excrete sodium. Banana, '
             'avocado, potato, spinach — food first.',
      metric: '~3.5 g',
      icon:  Icons.eco_rounded,
    ),
    DebloatItem(
      id:    'water_3l',
      block: DebloatBlock.day,
      title: '2.5–3L water across the day',
      why:   'Consistent intake signals the body to release retained '
             'fluid and flushes sodium. The cheapest lever you have.',
      metric: '2.5–3 L',
      icon:  Icons.water_drop_rounded,
    ),
    DebloatItem(
      id:    'carb_control',
      block: DebloatBlock.day,
      title: 'Carbs controlled — no refeed',
      why:   'Every gram of glycogen binds ~3g of water. A binge night '
             'shows in your face for two to three days.',
      metric: 'no spikes',
      icon:  Icons.bakery_dining_rounded,
    ),
    DebloatItem(
      id:    'zero_alcohol',
      block: DebloatBlock.day,
      title: 'Zero alcohol',
      why:   'Vasodilation, dehydration and broken sleep — the classic '
             'morning puff. Skipping it clears the face in 24h.',
      metric: '0',
      icon:  Icons.no_drinks_rounded,
    ),

    // ── NIGHT DRAIN ──
    DebloatItem(
      id:    'kitchen_close',
      block: DebloatBlock.night,
      title: 'Kitchen closes 3h before bed',
      why:   'Late sodium and insulin are what your morning face is made '
             'of. Your morning face starts at dinner.',
      metric: '−3 h',
      icon:  Icons.no_meals_rounded,
    ),
    DebloatItem(
      id:    'sleep_elevated',
      block: DebloatBlock.night,
      title: 'Back-sleep, head elevated',
      why:   'Flat, face-down sleep pools fluid in the cheeks and '
             'under-eyes. A slight wedge drains it into the neck instead.',
      metric: '~15°',
      icon:  Icons.bed_rounded,
    ),
    DebloatItem(
      id:    'sleep_hours',
      block: DebloatBlock.night,
      title: 'Sleep 7–9h, cool dark room',
      why:   'Short sleep spikes cortisol and impairs lymphatic '
             'clearance — "cortisol face" is real. Sleep is the drain '
             'cycle.',
      metric: '7–9 h',
      icon:  Icons.dark_mode_rounded,
    ),
  ];

  static List<DebloatItem> itemsFor(DebloatBlock block) =>
      items.where((i) => i.block == block).toList();

  // ── Daily state ────────────────────────────────────────────────────

  /// Ids ticked today.
  static Future<Set<String>> loadToday() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList('$_kDonePrefix${todayYmd()}') ?? const [])
        .toSet();
  }

  /// Toggle one item for today. Returns the new done-set. The first
  /// tick of the day stamps `looks_done_ymd` so the streak engine
  /// counts the day the moment the user starts executing.
  static Future<Set<String>> toggle(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final key   = '$_kDonePrefix${todayYmd()}';
    final done  = (prefs.getStringList(key) ?? const []).toSet();
    if (!done.remove(id)) done.add(id);
    await prefs.setStringList(key, done.toList());
    if (done.isNotEmpty) {
      await prefs.setInt('looks_done_ymd', todayYmd());
    }
    return done;
  }

  /// (done, total) for today — the progress ring + Ascend row.
  static Future<(int done, int total)> progressToday() async {
    final done = await loadToday();
    return (done.length, items.length);
  }
}

/// Time block a checklist item belongs to.
enum DebloatBlock { morning, day, night }

/// One item of the daily debloat system.
class DebloatItem {
  final String id;
  final DebloatBlock block;
  final String title;
  /// The one-breath explanation of WHY this moves the face.
  final String why;
  /// Compact target shown on the row's trailing chip ("< 2 g", "3 min").
  final String metric;
  /// Leading glyph for the row — one icon that suits each protocol.
  final IconData icon;
  const DebloatItem({
    required this.id,
    required this.block,
    required this.title,
    required this.why,
    required this.metric,
    required this.icon,
  });
}
