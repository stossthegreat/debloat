import '../models/face_geometry.dart';
import '../models/protocol.dart';
import '../models/scan_record.dart';
import 'local_store_service.dart';
import 'notification_service.dart';

// Canonical axis keys. One of these is what gets stored as
// Protocol.targetAxis and surfaced in UI — never the backend's prose
// pulldown sentence.
const _axisJaw         = 'Jaw definition';
const _axisHunterEyes  = 'Hunter Eyes';
const _axisSymmetry    = 'Symmetry';
const _axisChin        = 'Chin projection';
const _axisSkin        = 'Skin';
const _axisHair        = 'Hair';
const _axisPosture     = 'Posture';
const _axisDebloat     = 'Puffiness';
const _axisFoundations = 'Foundations';

/// Creates, loads, and advances the user's active 60-day protocol.
///
/// Templates are keyed to the scan's pulldown axis (the weakest measurement
/// surfaced by scoring). Each template ships a matched, time-banded daily
/// task set and milestones at day 14 / 30 / 60. Content is evidence-aware:
/// skin/neck/posture/gum/ice work is real, mewing is framed as oral posture
/// training, fin/min/tret is referenced natively but never dose-prescribed,
/// and orbital / mandibular "bone smashing" is never surfaced.
class ProtocolService {
  static Future<Protocol?> loadActive() async {
    final j = await LocalStoreService.loadProtocolJson();
    if (j == null) return null;
    try { return Protocol.fromJson(j); } catch (_) { return null; }
  }

  static Future<void> save(Protocol? p) async {
    await LocalStoreService.saveProtocolJson(p?.toJson());
    // Null means "end protocol" — tear down scheduled notifications so
    // the user isn't nudged about a routine that no longer exists.
    if (p == null) {
      await NotificationService.cancelAllProtocolNotifications();
    }
  }

  static Future<Protocol> markDayComplete(Protocol p, int day) async {
    final updated = p.withDayCompleted(day);
    await save(updated);
    // Reschedule the 8pm nudge against the NEW state — live vs at-risk vs
    // broken copy changes, and "completed today" pushes the next nudge to
    // tomorrow automatically.
    await NotificationService.scheduleStreakNudge(updated);
    return updated;
  }

  /// Start a protocol. Caller supplies the scan, the backend's pulldown
  /// prose, and the geometry — we resolve these into a canonical axis key
  /// before building the protocol. The stored targetAxis is always one of
  /// the canonical names above, never the raw pulldown sentence.
  static Future<Protocol> startForScan(
    ScanRecord scan, {
    required String pulldown,
    required FaceGeometry geometry,
  }) async {
    final axis = resolveAxis(pulldown: pulldown, geometry: geometry);
    final template = _templateFor(axis);
    final protocol = Protocol(
      id:         'proto-${DateTime.now().millisecondsSinceEpoch}',
      startedAt:  DateTime.now(),
      lengthDays: 60,
      title:      template.title,
      targetAxis: axis,
      summary:    template.summary,
      dailyTasks: template.dailyTasks,
      milestones: template.milestones,
      completedDays: const {},
    );
    await save(protocol);

    // First protocol start is the right moment to ask for notification
    // permission — the user has just committed to a 60-day run, so the
    // "we'll remind you at 8pm" value prop lands. Silent if already
    // granted or declined.
    await NotificationService.requestPermissionIfNeeded();
    await NotificationService.scheduleStreakNudge(protocol);
    await NotificationService.scheduleRescanReminders(protocol);

    return protocol;
  }

  /// Resolve the backend's prose pulldown into a canonical axis key.
  ///
  /// Strategy:
  ///   1. Keyword-match against the pulldown prose (richer keyword set
  ///      than the old `.contains('jaw')` — handles "mandible", "masseter",
  ///      "midface", "brow", "texture", etc.).
  ///   2. If no keyword matches, derive from geometry — whichever metric
  ///      is farthest from its typical-male ideal becomes the axis.
  ///   3. If geometry is balanced, fall back to Foundations.
  ///
  /// Exposed as a public method so the report CTA can derive the display
  /// label + eventual Protocol.targetAxis before the user commits.
  static String resolveAxis({
    required String pulldown,
    required FaceGeometry geometry,
  }) {
    final p = pulldown.toLowerCase();

    // Order matters. Broad anatomical references ("jaw", "eye") appear
    // in a lot of pulldowns even when they're not the actual topic, so
    // we check MORE SPECIFIC keywords first and fall through to the
    // broader ones only if nothing more specific matched.

    // --- Specific axes first ---
    if (_anyOf(p, ['chin', 'mental eminence', 'submental'])) {
      return _axisChin;
    }
    if (_anyOf(p, ['posture', 'neck forward', 'slouch', 'tech neck',
                   'forward head'])) {
      return _axisPosture;
    }
    if (_anyOf(p, ['puff', 'swell', 'bloat', 'water retention',
                   'sodium', 'fluid retention'])) {
      return _axisDebloat;
    }
    if (_anyOf(p, ['hairline', 'receding', 'thinning', 'norwood',
                   'hair density'])) {
      return _axisHair;
    }
    if (_anyOf(p, ['acne', 'pore', 'redness', 'pigment',
                   'skin texture', 'skin tone', 'skin quality'])) {
      return _axisSkin;
    }
    if (_anyOf(p, ['canthal', 'hunter eye', 'hooded', 'orbital',
                   'eye tilt', 'periorbital', 'under-eye'])) {
      return _axisHunterEyes;
    }
    if (_anyOf(p, ['asymmet', 'tilt head', 'head rotation',
                   'imbalanc', 'unevenly'])) {
      return _axisSymmetry;
    }

    // --- Broader / overloaded keywords last ---
    if (_anyOf(p, ['jaw', 'mandib', 'masseter', 'gonial'])) {
      return _axisJaw;
    }
    if (_anyOf(p, ['hair'])) {
      return _axisHair;
    }
    if (_anyOf(p, ['skin', 'complex'])) {
      return _axisSkin;
    }
    if (_anyOf(p, ['symmet'])) {
      return _axisSymmetry;
    }

    // ── Geometry fallback ──
    // No keyword matched the prose — derive from whatever measurement is
    // most off-ideal. Thresholds align with the copy used across the app.
    if (geometry.jawAngle > 128)     { return _axisJaw;         }
    if (geometry.canthalTilt < 1.5)  { return _axisHunterEyes;  }
    if (geometry.symmetryScore < 78) { return _axisSymmetry;    }
    if (geometry.fwhr > 2.1 ||
        geometry.faceLengthRatio > 1.38) { return _axisDebloat; }

    return _axisFoundations;
  }

  static bool _anyOf(String haystack, List<String> needles) {
    for (final n in needles) {
      if (haystack.contains(n)) return true;
    }
    return false;
  }

  /// Maps the canonical axis key → template. Exact-match: callers MUST
  /// resolve their axis via [resolveAxis] first.
  static _Template _templateFor(String axis) {
    switch (axis) {
      case _axisJaw:         return _jaw;
      case _axisHunterEyes:  return _hunterEyes;
      case _axisSymmetry:    return _symmetry;
      case _axisChin:        return _chin;
      case _axisSkin:        return _skin;
      case _axisHair:        return _hair;
      case _axisPosture:     return _posture;
      case _axisDebloat:     return _debloat;
      default:               return _foundations;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Content library — 9 axes, 5-7 tasks each, time-banded.
// ═══════════════════════════════════════════════════════════════════════════

const _jaw = _Template(
  title: 'Sharpen the Jaw',
  summary: 'Sixty days of oral posture, masseter work, neck load, and a '
           'body-comp pull. Fat pad retracts, masseter thickens, platysma '
           'frames the mandible. Visible shift by day 45 on most builds.',
  dailyTasks: [
    DailyTask(
      title: 'Mewing — full-tongue posture',
      detail: 'Whole tongue flat on the palate, teeth light-touching, lips '
              'sealed, nasal breath. Three phone reminders through the day.',
      duration: 'ongoing', category: TaskCategory.habit,
      timeBand: TimeBand.ongoing),
    DailyTask(
      title: 'Ice-water face dunk',
      detail: 'Bowl, ice, water. Face to the hairline, 30 s. Vasoconstricts '
              'the lower third and drops overnight fluid in the masseter.',
      duration: '30 s', category: TaskCategory.skin,
      timeBand: TimeBand.am),
    DailyTask(
      title: 'Falim gum — masseter load',
      detail: 'Turkish sugar-free. 30 min chewing. Real masseter hypertrophy '
              'over 8 weeks — mastic gum is the upgrade option. Stop at any '
              'TMJ click.',
      duration: '30 min', category: TaskCategory.exercise,
      timeBand: TimeBand.midday),
    DailyTask(
      title: 'Masseter isometrics',
      detail: '3 × 30 s controlled clench, 60 s rest. Activates the muscle '
              'without grinding wear. Stop if you feel joint click.',
      duration: '6 min', category: TaskCategory.exercise,
      timeBand: TimeBand.pm),
    DailyTask(
      title: 'Neck-maxx — chin tucks + curls',
      detail: '3 × 15 chin tucks against a wall, then 3 × 10 neck curls with '
              'a small plate on the forehead if you have one. Thickens the '
              'bracket around the jaw.',
      duration: '8 min', category: TaskCategory.exercise,
      timeBand: TimeBand.pm),
    DailyTask(
      title: 'Mouth tape — nasal breath lock',
      detail: '3M micropore across the lips. Keeps tongue on palate + nasal '
              'breath through sleep. Skip if sleep apnea.',
      duration: 'all night', category: TaskCategory.habit,
      timeBand: TimeBand.night),
    DailyTask(
      title: 'Lean-maxx — body fat under 14 %',
      detail: 'Face fat pad responds first. 0.5 lb/week cut above 16 %, '
              'protein 1 g/lb, 10 k steps. Jaw gains compound with leanness.',
      duration: 'daily', category: TaskCategory.nutrition,
      timeBand: TimeBand.ongoing),
  ],
);

const _hunterEyes = _Template(
  title: 'Hunter Eyes',
  summary: 'Canthal tilt is bone-dominant, but orbital fluid, brow line, and '
           'upper-lid exposure all read as tilt. Target what you control: '
           'depuff the lower pad, recruit orbicularis, shape the brow.',
  dailyTasks: [
    DailyTask(
      title: 'Hard mew — upward palate pressure',
      detail: 'Active mewing, tongue pushed UP into the palate (not just '
              'forward). Frames the eye socket from below. All-day habit.',
      duration: 'ongoing', category: TaskCategory.habit,
      timeBand: TimeBand.ongoing),
    DailyTask(
      title: 'Cold roller + caffeine eye serum',
      detail: 'Caffeine 5 % (The Ordinary) under-eye, then cold jade/steel '
              'roller 2 min. Shrinks the lower fat pad, the fastest visible '
              'win for hunter-eye reading.',
      duration: '5 min', category: TaskCategory.skin,
      timeBand: TimeBand.am),
    DailyTask(
      title: 'Sunmaxx — 10 min direct AM light',
      detail: 'No sunglasses, no screen. Vitamin D, skin tone, and the squint '
              'itself trains the orbicularis lateral lift.',
      duration: '10 min', category: TaskCategory.habit,
      timeBand: TimeBand.am),
    DailyTask(
      title: 'Squint isometrics',
      detail: '3 × 20 firm squints, 2 s hold each. Orbicularis oculi pulls '
              'the lateral canthus up — low-yield but free.',
      duration: '3 min', category: TaskCategory.exercise,
      timeBand: TimeBand.midday),
    DailyTask(
      title: 'Brow lift — trim + brush',
      detail: 'Clear brow gel, brush up-and-out. Trim length, preserve the '
              'tail arch. A lifted brow reads as positive tilt even when the '
              'bone itself is neutral.',
      duration: '3 min', category: TaskCategory.grooming,
      timeBand: TimeBand.pm),
    DailyTask(
      title: 'Sodium cut after 6pm',
      detail: 'Under 1 g after dinner. Sodium is 90 % of morning under-eye '
              'puff. Hold 30 days to see the difference in your rescan.',
      duration: 'ongoing', category: TaskCategory.nutrition,
      timeBand: TimeBand.night),
    DailyTask(
      title: 'Back-sleep, head elevated 15°',
      detail: 'Silk pillowcase, small wedge. Prone sleep pools fluid in the '
              'lower lid — the #1 cause of morning bags.',
      duration: 'all night', category: TaskCategory.habit,
      timeBand: TimeBand.night),
  ],
);

const _symmetry = _Template(
  title: 'Rebalance',
  summary: 'Asymmetry is ~80 % habitual — chewing side, sleep side, '
           'posture rotation. Bone asymmetry holds; soft-tissue and tension '
           'distribution respond to sixty days of corrective habits.',
  dailyTasks: [
    DailyTask(
      title: 'Weak-side chewing — gum',
      detail: 'Falim or mastic, 15 min/day, ONLY on the thinner cheek. '
              'Balances masseter hypertrophy on the underdeveloped side.',
      duration: '15 min', category: TaskCategory.habit,
      timeBand: TimeBand.midday),
    DailyTask(
      title: 'Posture reset — hourly chime',
      detail: 'Phone alarm every hour. Head over shoulders, shoulders over '
              'hips. Asymmetric tension in the scalenes rotates the face.',
      duration: '5 s × hourly', category: TaskCategory.habit,
      timeBand: TimeBand.ongoing),
    DailyTask(
      title: 'Thoracic rotations + scalene stretch',
      detail: 'Each side 8 reps thoracic windmill, 30 s scalene hold. '
              'Releases the cervical twist that\'s pulling your face off-axis.',
      duration: '8 min', category: TaskCategory.exercise,
      timeBand: TimeBand.pm),
    DailyTask(
      title: 'Gua sha — unilateral',
      detail: 'Oil + stone, 20 upward strokes only on the fuller (softer) '
              'side. Drains lymph asymmetrically toward balance.',
      duration: '6 min', category: TaskCategory.skin,
      timeBand: TimeBand.pm),
    DailyTask(
      title: 'Back-sleep only',
      detail: 'Side-sleep compresses one cheek for 8 h a night. This is the '
              'single biggest lever on surface asymmetry — non-negotiable.',
      duration: 'all night', category: TaskCategory.habit,
      timeBand: TimeBand.night),
    DailyTask(
      title: 'Photo log — same angle, same light',
      detail: 'Front-facing selfie every morning, same window, chin level. '
              'Asymmetry shifts slow — you need the file.',
      duration: '30 s', category: TaskCategory.habit,
      timeBand: TimeBand.ongoing),
  ],
);

const _chin = _Template(
  title: 'Push the Chin Forward',
  summary: 'The mental eminence reads forward when the tongue holds the '
           'palate, the platysma is trained, and the submental fluid drops. '
           'Three levers, sixty days, measurable delta.',
  dailyTasks: [
    DailyTask(
      title: 'Forward mewing — tongue + lower jaw',
      detail: 'Tongue high on the palate, lower jaw relaxed forward. You '
              'should feel engagement at the chin without clench.',
      duration: 'ongoing', category: TaskCategory.habit,
      timeBand: TimeBand.ongoing),
    DailyTask(
      title: 'Ice dunk — chin-up tilt',
      detail: '30 s face dunk, chin slightly up. Tightens the submental skin '
              '— the soft/strong chin difference is often fluid.',
      duration: '30 s', category: TaskCategory.skin,
      timeBand: TimeBand.am),
    DailyTask(
      title: 'Platysma jut — 3 × 30',
      detail: 'Jut the lower jaw forward, hold 2 s, release. 30 reps × 3. '
              'You\'ll feel the platysma cord fire down the neck.',
      duration: '5 min', category: TaskCategory.exercise,
      timeBand: TimeBand.midday),
    DailyTask(
      title: 'Falim gum — forward bite',
      detail: 'Chew 15 min with the jaw held slightly forward, not neutral. '
              'Trains the lateral pterygoids that project the mandible.',
      duration: '15 min', category: TaskCategory.exercise,
      timeBand: TimeBand.midday),
    DailyTask(
      title: 'Neck curls — plate or band',
      detail: '3 × 15 flat-back neck curls with a small plate on the forehead '
              'or banded resistance. Thickens the SCM + platysma frame.',
      duration: '8 min', category: TaskCategory.exercise,
      timeBand: TimeBand.pm),
    DailyTask(
      title: 'Mouth tape + back sleep',
      detail: 'Locks tongue posture and prevents the jaw collapsing backward '
              'at night. Wake with the jaw forward, not tucked.',
      duration: 'all night', category: TaskCategory.habit,
      timeBand: TimeBand.night),
  ],
);

const _skin = _Template(
  title: 'Glass Skin',
  summary: 'The highest-evidence axis in the whole stack. SPF, a retinoid, '
           'and barrier care take 80 % of the faces you see online. Sixty '
           'days is the first real rescan; six months is transformation.',
  dailyTasks: [
    DailyTask(
      title: 'SPF 50 — non-negotiable',
      detail: 'Korean or Japanese formulation (Beauty of Joseon, Anessa) over '
              'a light moisturiser. Daily, even indoors. UV is 80 % of '
              'facial ageing.',
      duration: '2 min', category: TaskCategory.skin,
      timeBand: TimeBand.am),
    DailyTask(
      title: 'Vitamin C — 10-15 % L-ascorbic',
      detail: 'Morning antioxidant under SPF. Brightens, protects, stacks '
              'with sunscreen for real photo-damage defence.',
      duration: '1 min', category: TaskCategory.skin,
      timeBand: TimeBand.am),
    DailyTask(
      title: 'Water + AM sun — the glow stack',
      detail: '2 L through the day, 10 min direct morning sun. Vitamin D + '
              'flush is the "came back from a week away" face.',
      duration: 'ongoing', category: TaskCategory.habit,
      timeBand: TimeBand.midday),
    DailyTask(
      title: 'Skincycle — retinoid nights',
      detail: 'Night 1 exfoliate (BHA). Night 2 retinoid (tretinoin 0.025 % '
              '2×/wk titrating up — clinician for the Rx). Nights 3-4 recover '
              '(ceramide moisturiser). Rotates to spare the barrier.',
      duration: '4 min', category: TaskCategory.skin,
      timeBand: TimeBand.pm),
    DailyTask(
      title: 'Niacinamide 10 % — pores + oil',
      detail: 'After serum, before moisturiser. Tightens pore appearance, '
              'controls sebum. Pairs cleanly with retinoid nights.',
      duration: '1 min', category: TaskCategory.skin,
      timeBand: TimeBand.pm),
    DailyTask(
      title: 'Pillowcase — flip or change 2×/week',
      detail: 'Bacteria + sebum drive the one-sided acne pattern most people '
              'have. Free intervention, real effect.',
      duration: '1 min', category: TaskCategory.habit,
      timeBand: TimeBand.night),
    DailyTask(
      title: 'Hands off the face',
      detail: 'Touching, propping, picking. 90 % of adult inflammatory acne '
              'is mechanical — catch yourself.',
      duration: 'ongoing', category: TaskCategory.habit,
      timeBand: TimeBand.ongoing),
  ],
);

const _hair = _Template(
  title: 'Crown',
  summary: 'Density, line, and style — three separate game-pieces. '
           'Microneedling + topical + shampoo hold the line; the creator-'
           'matched cut in The Mirror handles the frame. Pharma paths are '
           'named but clinician-gated.',
  dailyTasks: [
    DailyTask(
      title: 'Dermaroll scalp — 0.5 mm daily',
      detail: 'Clean device, clean scalp. Micro-injury triggers collagen + '
              'improves topical absorption. Alternative: 1.5 mm once weekly. '
              'Not both.',
      duration: '5 min', category: TaskCategory.grooming,
      timeBand: TimeBand.am),
    DailyTask(
      title: 'Minoxidil — topical or oral',
      detail: 'Community standard for density. Topical 5 % 1 ml 2×/day is '
              'OTC; oral micro-dose 1.25–2.5 mg is clinician-prescribed. '
              'Book the appointment.',
      duration: '1 min', category: TaskCategory.grooming,
      timeBand: TimeBand.am),
    DailyTask(
      title: 'Rosemary oil — the natural path',
      detail: 'One study showed parity with 2 % minoxidil over 6 months. '
              '5 drops into scalp, leave 1 h, rinse. Lower-risk alternative.',
      duration: '5 min + rinse', category: TaskCategory.grooming,
      timeBand: TimeBand.midday),
    DailyTask(
      title: 'Ketoconazole shampoo — 2×/week',
      detail: 'Nizoral or equivalent. DHT at the scalp + anti-inflammatory. '
              'Lather 5 min, rinse. Pairs cleanly with topical minoxidil.',
      duration: '5 min', category: TaskCategory.grooming,
      timeBand: TimeBand.pm),
    DailyTask(
      title: 'Creator-cut match — run in The Mirror',
      detail: 'Ten named cuts ranked for your face shape — edgar, curtains, '
              'low taper, textured fringe. Render on your face before you '
              'sit in the chair.',
      duration: '3 min', category: TaskCategory.grooming,
      timeBand: TimeBand.pm),
    DailyTask(
      title: 'Protein + iron — the hair diet',
      detail: '1 g/lb protein, iron from red meat or liver 2×/wk. '
              'Deficiency stalls every topical you stack.',
      duration: 'daily', category: TaskCategory.nutrition,
      timeBand: TimeBand.ongoing),
  ],
);

const _posture = _Template(
  title: 'Mog Stance',
  summary: 'Posture dominates perceived dominance. Chin-up-the-world, '
           'shoulders packed, thoracic extended. Traps and rear delts frame '
           'the neck; the jaw follows. Eight weeks resets the baseline.',
  dailyTasks: [
    DailyTask(
      title: 'Chin-up-the-world — 1° tilt',
      detail: 'Head stacked on shoulders, chin parallel or slightly up. '
              'Neck-forward reads as ogre; neck-back reads as mog. Check '
              '10× a day.',
      duration: 'ongoing', category: TaskCategory.habit,
      timeBand: TimeBand.ongoing),
    DailyTask(
      title: 'Wall test — 60 s',
      detail: 'Heels, glutes, shoulders, head against a wall for 60 s. '
              'Resets the postural chain. Phone alarm daily.',
      duration: '1 min', category: TaskCategory.exercise,
      timeBand: TimeBand.am),
    DailyTask(
      title: 'Trap-maxx — shrugs + face pulls',
      detail: '5 × 15 heavy shrugs, 3 × 15 banded face pulls. Traps build '
              'the neck frame, face pulls yank the shoulders back where they '
              'belong.',
      duration: '12 min', category: TaskCategory.exercise,
      timeBand: TimeBand.midday),
    DailyTask(
      title: 'Thoracic extension — foam roll',
      detail: '5 min foam-roll the upper back, arms overhead. Unlocks the '
              'desk slouch that rotates your chin toward the floor.',
      duration: '5 min', category: TaskCategory.exercise,
      timeBand: TimeBand.pm),
    DailyTask(
      title: 'Phone up to eye level',
      detail: 'Tech-neck is the #1 posture killer for this generation. '
              'Phone up, laptop riser, desk stand. Non-negotiable.',
      duration: 'ongoing', category: TaskCategory.habit,
      timeBand: TimeBand.ongoing),
  ],
);

const _debloat = _Template(
  title: 'Depuff',
  summary: 'Water retention reads as softness, weakness, and age. '
           'Vasoconstriction + lymph drainage + sodium audit drops the '
           'whole face one visual grade in 14 days. The fastest-moving '
           'axis in the stack.',
  dailyTasks: [
    DailyTask(
      title: 'Ice-water face dunk — 30 s',
      detail: 'Bowl + ice + water, face to the hairline. Vasoconstriction '
              'drops overnight fluid. The 30 seconds that set the whole day.',
      duration: '30 s', category: TaskCategory.skin,
      timeBand: TimeBand.am),
    DailyTask(
      title: 'Gua sha — 8 min lymph',
      detail: 'Facial oil, stone. Upward + outward strokes: jaw → ear, cheek '
              '→ temple, brow → hairline. Lymph clears, face sharpens.',
      duration: '8 min', category: TaskCategory.skin,
      timeBand: TimeBand.am),
    DailyTask(
      title: 'Sodium audit — under 2 g/day',
      detail: 'Restaurants, sauces, and bread hide 80 % of it. Read labels '
              'for 14 days. Most faces lose a full grade of puff.',
      duration: 'ongoing', category: TaskCategory.nutrition,
      timeBand: TimeBand.midday),
    DailyTask(
      title: 'Hydrate — 3 L through the day',
      detail: 'Counter-intuitive: dehydration is what drives retention. '
              '3 L signals the body to flush, not hold.',
      duration: 'ongoing', category: TaskCategory.nutrition,
      timeBand: TimeBand.midday),
    DailyTask(
      title: 'Cold shower — 2 min finish',
      detail: 'Last 2 min of your shower, cold. Whole-body vasoconstriction, '
              'inflammation drop, tonic skin shift.',
      duration: '2 min', category: TaskCategory.habit,
      timeBand: TimeBand.pm),
    DailyTask(
      title: 'Cut alcohol + dairy — 14 days',
      detail: 'Both are inflammatory for most people. Remove for two weeks, '
              'rescan, reintroduce one at a time. Your face will tell you '
              'which one matters for you.',
      duration: '14 days', category: TaskCategory.nutrition,
      timeBand: TimeBand.pm),
    DailyTask(
      title: 'Back-sleep, head elevated 15°',
      detail: 'Small wedge under the pillow. Face drains into the neck at '
              'night instead of pooling in cheeks and under-eyes.',
      duration: 'all night', category: TaskCategory.habit,
      timeBand: TimeBand.night),
  ],
);

const _foundations = _Template(
  title: 'Foundations',
  summary: 'The stack every other intervention multiplies off. Skin, sleep, '
           'sun, protein, and steps. If you only run this one, you still '
           'win most of the delta.',
  dailyTasks: [
    DailyTask(
      title: 'Core AM — SPF + Vitamin C + moisturiser',
      detail: 'Three products, two minutes. If you do nothing else in the '
              'stack, do these three.',
      duration: '2 min', category: TaskCategory.skin,
      timeBand: TimeBand.am),
    DailyTask(
      title: 'Sunmaxx — 10 min direct AM light',
      detail: 'No screen, no sunglasses, outside. Circadian reset + vitamin '
              'D + skin tone. Non-negotiable for 8 weeks.',
      duration: '10 min', category: TaskCategory.habit,
      timeBand: TimeBand.am),
    DailyTask(
      title: 'Walk — 10 k steps',
      detail: 'NEAT burns 2-3 % body fat per month without training '
              'fatigue. Face fat responds first. Free, daily.',
      duration: 'ongoing', category: TaskCategory.habit,
      timeBand: TimeBand.midday),
    DailyTask(
      title: 'Retinoid — 3 nights a week',
      detail: 'Tretinoin 0.025 % to start, 2-3 nights titrating up. Gold '
              'standard for texture, acne, long-term glow. Clinician for '
              'the Rx.',
      duration: '1 min', category: TaskCategory.skin,
      timeBand: TimeBand.pm),
    DailyTask(
      title: 'Protein — 1 g per lb body weight',
      detail: 'Face mass and hair density both collapse under-protein. '
              'Meat, eggs, dairy (if tolerated), whey. Daily, no exceptions.',
      duration: 'across meals', category: TaskCategory.nutrition,
      timeBand: TimeBand.pm),
    DailyTask(
      title: 'Sleep — 8 h, dark room, 18 °C',
      detail: 'Cortisol baseline IS facial baseline. No screens 60 min pre-'
              'bed, blackout room, cool air. Non-negotiable.',
      duration: '8 h', category: TaskCategory.habit,
      timeBand: TimeBand.night),
    DailyTask(
      title: 'Mouth tape — nasal breath lock',
      detail: '3M micropore across the lips. Forces nasal breath + tongue '
              'on palate all night. Skip if sleep apnea.',
      duration: 'all night', category: TaskCategory.habit,
      timeBand: TimeBand.night),
  ],
);

// ═══════════════════════════════════════════════════════════════════════════
//  Template scaffolding
// ═══════════════════════════════════════════════════════════════════════════

class _Template {
  final String title;
  final String summary;
  final List<DailyTask> dailyTasks;
  List<ProtocolMilestone> get milestones => const [
    ProtocolMilestone(day: 7,  title: 'Week 1',    action: 'First photo log entry. No rescan — you\'re still warming up.'),
    ProtocolMilestone(day: 14, title: 'Check-in',  action: 'Re-scan. Compare to baseline. Small deltas expected.'),
    ProtocolMilestone(day: 30, title: 'Midpoint',  action: 'Re-scan. Adjust the axis if one has stalled.'),
    ProtocolMilestone(day: 60, title: 'Completion', action: 'Final scan. Before / after reveal.'),
  ];
  const _Template({
    required this.title, required this.summary, required this.dailyTasks,
  });
}
