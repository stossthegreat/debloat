/// Named, creator-recognisable haircut styles — the library The Mirror picks
/// from when rendering hair try-ons. Each style carries a Nano Banana +
/// face-swap identity-lock prompt tuned by a stylist, a short "why" line
/// the user can read at a glance, and a set of face-shape affinities the
/// picker scores against the user's geometry.
///
/// Rendering still fires the same /tryon endpoint. The creator library is
/// purely an *upgrade to the prompt surface* — richer, named, shareable —
/// without changing the backend contract.
class CreatorStyle {
  final String id;
  final String name;    // "Edgar", "Broccoli", "Low taper + textured top"
  final String tag;     // Short cultural tag line
  final String why;     // One line on why this suits the matched shape
  final String prompt;  // Full prompt fired into /tryon
  final List<FaceCue> suits;

  const CreatorStyle({
    required this.id,
    required this.name,
    required this.tag,
    required this.why,
    required this.prompt,
    required this.suits,
  });
}

/// Coarse face-shape cues the picker uses to rank styles. Not a formal
/// classification — just five bins derived from the measurements we already
/// have. Multiple cues can apply to the same face.
enum FaceCue { oval, long, broad, softJaw, sharpJaw }

/// The seed library. Ordered by descending curation confidence — ties in
/// scoring resolve by this order, so the universally-good "low taper" sits
/// high, experimental shapes (buzz+beard, Elordi) sit low.
const creatorStyles = <CreatorStyle>[
  CreatorStyle(
    id: 'low-taper-textured',
    name: 'Low taper + textured top',
    tag: '2025 universal · the safe mog',
    why: 'The single most-requested cut of 2025. Works on nearly every face '
         'shape and hair type — neutral, flattering, never dated.',
    prompt: 'Low taper fade on the sides and back, 4-5 cm textured top styled '
            'side-swept, clean neckline, natural hair colour and texture, '
            'preserve identity exactly',
    suits: [FaceCue.oval, FaceCue.long, FaceCue.broad,
            FaceCue.sharpJaw, FaceCue.softJaw],
  ),
  CreatorStyle(
    id: 'middle-part',
    name: 'Middle-part curtains',
    tag: 'Timothée Chalamet · K-pop',
    why: 'Parted curtain framing plays off a sharp jaw and a neutral-to-long '
         'face. Softens the top third without hiding the structure underneath.',
    prompt: 'Middle-part curtain haircut: 10-12 cm of hair parted down the '
            'middle, sides sweeping outward and back, soft natural texture, '
            'preserve identity',
    suits: [FaceCue.long, FaceCue.sharpJaw, FaceCue.oval],
  ),
  CreatorStyle(
    id: 'edgar',
    name: 'Edgar',
    tag: 'Latino TikTok · still strong',
    why: 'Blunt forward fringe squares off a broad forehead and adds an '
         'angular top that reads confident and modern.',
    prompt: 'Edgar cut: blunt straight forward fringe cut sharply across the '
            'forehead, 3-4 cm length, very short tapered sides and back, '
            'clean squared hairline, preserve identity',
    suits: [FaceCue.oval, FaceCue.broad, FaceCue.softJaw],
  ),
  CreatorStyle(
    id: 'broccoli',
    name: 'Broccoli',
    tag: 'Gen Z default',
    why: 'Voluminous curly top adds height and width without hiding the jaw. '
         'Best read on oval or mildly angular faces.',
    prompt: 'Broccoli cut: 6-8 cm curly/textured top with high volume, skin '
            'fade on the sides and back, messy natural curls, preserve '
            'identity',
    suits: [FaceCue.oval, FaceCue.sharpJaw],
  ),
  CreatorStyle(
    id: 'textured-fringe',
    name: 'Textured fringe',
    tag: '2024-25 · forehead cover',
    why: 'Forward-swept texture breaks a long face vertically and softens a '
         'high forehead without flattening the silhouette.',
    prompt: 'Textured fringe cut: 3-4 cm forward-swept textured fringe over '
            'the forehead, short-to-medium length sides and back, natural '
            'movement, preserve identity',
    suits: [FaceCue.long],
  ),
  CreatorStyle(
    id: 'modern-mullet',
    name: 'Modern mullet',
    tag: '2024-26 · fashion-forward',
    why: 'Short on top plus length in the back softens a sharp jaw and adds '
         'motion without fully modernising the shape away.',
    prompt: 'Modern mullet haircut: short on top and sides, 7-9 cm tapered '
            'mid-length back, textured and naturally swept, preserve identity',
    suits: [FaceCue.oval, FaceCue.sharpJaw],
  ),
  CreatorStyle(
    id: 'burst-fade-mullet',
    name: 'Burst-fade mullet',
    tag: 'Latino TikTok · Edgar-mullet hybrid',
    why: 'Burst fade curves around the ears and opens the cheekbones; the '
         'mullet back keeps motion without hiding the jaw.',
    prompt: 'Burst fade mullet: burst fade curving around the ears, medium '
            'textured top, 6-8 cm tapered mullet back, preserve identity',
    suits: [FaceCue.oval, FaceCue.sharpJaw, FaceCue.broad],
  ),
  CreatorStyle(
    id: 'slick-back',
    name: 'Slick-back (middy)',
    tag: '2025-26 rising',
    why: 'Slick-back shows the full face — high-reward for sharp jaws and '
         'defined cheekbones, unforgiving of a weak hairline.',
    prompt: 'Slick-back haircut: 6-8 cm medium-length hair slicked straight '
            'back with a glossy finish, tight sides and back, preserve '
            'identity',
    suits: [FaceCue.sharpJaw, FaceCue.oval],
  ),
  CreatorStyle(
    id: 'buzz-plus-beard',
    name: 'Buzz + full beard',
    tag: 'Ogre-mog · Zyzz combo',
    why: 'Removes the hair variable entirely, doubles the beard frame. '
         'Maximum jaw and skull emphasis — high-risk, high-reward.',
    prompt: 'Buzz cut 3-5 mm all over the scalp, combined with a thick 20-30 '
            'mm full beard shaped tight to the jawline, preserve identity',
    suits: [FaceCue.sharpJaw, FaceCue.broad],
  ),
  CreatorStyle(
    id: 'elordi-curtains',
    name: 'Elordi curtains',
    tag: 'Jacob Elordi · 2024-26',
    why: 'Long soft curtains play against a strong bone structure — reads '
         'dominant without effort on long or sharp faces.',
    prompt: 'Long soft curtain haircut: 14-16 cm wavy hair parted down the '
            'middle, falling past the cheekbones with soft natural texture, '
            'preserve identity',
    suits: [FaceCue.long, FaceCue.sharpJaw],
  ),
];

/// Score the library against a user's geometry cues and return the top N.
/// Matches count; ties resolve by curation order (library index).
List<CreatorStyle> rankForGeometry({
  required double jawAngle,
  required double faceLengthRatio,
  required double fwhr,
  required String headShape,
  int take = 5,
}) {
  final cues = <FaceCue>{FaceCue.oval}; // oval is the neutral fallback
  if (headShape == 'long'  || faceLengthRatio > 1.35) cues.add(FaceCue.long);
  if (headShape == 'broad' || fwhr > 2.0)             cues.add(FaceCue.broad);
  if (jawAngle > 128) cues.add(FaceCue.softJaw);
  if (jawAngle < 122) cues.add(FaceCue.sharpJaw);

  final scored = <(CreatorStyle, int)>[
    for (final s in creatorStyles)
      (s, s.suits.where(cues.contains).length),
  ]..sort((a, b) => b.$2.compareTo(a.$2));

  return scored
      .where((r) => r.$2 > 0)
      .map((r) => r.$1)
      .take(take)
      .toList();
}
