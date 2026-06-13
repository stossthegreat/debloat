import 'gaze_lesson.dart';

/// THE GAZE — Lucien's seductive-eye masterclass.
///
/// Twelve named eye MOVES taught the way a real charisma coach teaches: ONE
/// punch of WHY this move works on her, then a VIVID anatomy-named
/// HOW (her LEFT eye, your top lid, her top lip, slow, heavy, dead
/// brow). No CEO talk, no general "be confident" — every line names
/// the part of the face, the speed, the feeling. That's how a man
/// actually learns to look at a woman.
///
/// Flow per lesson:  WHY → HOW (vivid) → trigger → drill → correction
/// → drill (graded) → score.
///
/// Grounded in real research: ~3.2s is the most comfortable
/// mutual-gaze length (Binetti 2016); mutual gaze manufactures
/// closeness (Aron 1997); hard stare trips the threat circuit, soft
/// eyes read as warmth; the anxious man breaks down/away inside a
/// second, the confident man owns it.
abstract final class GazeSyllabus {
  static const all = <GazeLesson>[
    // ── LESSON 1 — THE LOCK ─────────────────────────────────────────
    GazeLesson(
      id: 'the_lock',
      number: 1,
      name: 'THE LOCK',
      oneLine: 'Four seconds. One iris. You break first.',
      objective: 'Four seconds on one iris. Brow dead. You break.',
      story: [
        'This is the look every woman remembers. The hooded eye.',
        'Half-lid, dead brow, hunter stare.',
        'Men with bone structure get this look free. The rest of us learn it.',
      ],
      demo: [
        'Look at me. Pick my left eye.',
        'First — drop every muscle in your forehead. Dead.',
        'Now drop your upper lid. Twenty percent down.',
        'Heavy. Like you\'re tired but not sleepy.',
        'Lift your lower lid a hair. Just a hair. That\'s hunter.',
        'Mouth relaxed. Don\'t smile yet.',
        'Hold four seconds. Don\'t blink.',
        'The dead brow is what makes it dangerous.',
      ],
      instruct: [
        'Hood the lids. Find my eye. Begin.',
      ],
      // Binetti 2016: 3.3s mean preferred mutual gaze (95% CI 3.2-3.4)
      // across 498 participants from 56 countries. Moore 1985:
      // female-solicitation glance pattern is 2-3s × 3 bouts. Four
      // seconds sits at the upper edge of comfortable for THE LOCK —
      // first contact, decisive, not creepy.
      drillSeconds: 4,
      targetBlinks: 1,
      weights: {
        // No smileControl on THE LOCK — this drill is pure hold, the
        // mouth is irrelevant. Re-distributed across the three axes
        // that actually matter for an unflinching stare.
        GazeDimension.eyeStability: 0.55,
        GazeDimension.blinkControl: 0.20,
        GazeDimension.rhythm:       0.00,
        GazeDimension.tension:      0.25,
        GazeDimension.smileControl: 0.00,
      },
      isRhythmLesson: false,
      correction: [
        'Your brow lifted — that\'s surprised, not seductive.',
        'Forehead dead. Lids heavy. Lower lid up. Again.',
      ],
    ),

    // ── LESSON 2 — THE DROP ─────────────────────────────────────────
    GazeLesson(
      id: 'the_drop',
      number: 2,
      name: 'THE DROP',
      oneLine: 'When you break, break down. Never up.',
      objective: 'Lock. Then drop slow to her mouth. Down only.',
      story: [
        'When you look at her mouth while she\'s talking — even for one second — her brain registers it as desire.',
        'This is the most powerful covert signal in eye contact.',
        'It\'s called the eye-lip drop.',
      ],
      demo: [
        'Lock my eye. The iris.',
        'Hold one beat.',
        'Now let your eyes fall. SLOW.',
        'Drop to my top lip.',
        'Stay there — one full second.',
        'Don\'t flick. Don\'t dart. Slow.',
        'Now climb back to my eye.',
        'That signal just hit her like a drug.',
      ],
      instruct: [
        'Lock. Drop slow to her lips. Climb back. Begin.',
      ],
      // 5s = lock-to-her-eye for ~2s, slow drop down to mouth for ~1s,
      // ~2s on the lip, climb back. The journey is the move; rushing
      // kills it. 12s was holding-style stare-off territory.
      drillSeconds: 5,
      targetBlinks: 2,
      weights: {
        GazeDimension.eyeStability: 0.35,
        GazeDimension.blinkControl: 0.10,
        GazeDimension.rhythm:       0.25,
        GazeDimension.tension:      0.25,
        GazeDimension.smileControl: 0.05,
      },
      isRhythmLesson: true,
      correction: [
        'You flicked — that\'s a tic, not desire.',
        'The drop must be slow enough to feel. Again.',
      ],
    ),

    // ── LESSON 3 — SOFT EYES (SMOULDER) ─────────────────────────────
    GazeLesson(
      id: 'soft_eyes',
      number: 3,
      name: 'SOFT EYES',
      oneLine: 'Brow dead. Top lid down a hair. The smoulder.',
      objective: 'Drop the brow. Half-lid. Smile in the mouth only.',
      story: [
        'Hollywood actors train this for years. The smolder.',
        'Heavy lids, asymmetric mouth, total stillness.',
        'Brando. Bardem. Idris Elba.',
        'The look that says I\'ve already decided.',
      ],
      demo: [
        'Find stillness first. Don\'t move at all.',
        'Drop everything above your eyes — brow, forehead.',
        'Upper lid — thirty percent down.',
        'Lower lid — five percent up. Hunter base.',
        'Now — one corner of your mouth lifts. ONE.',
        'Don\'t move anything else.',
        'Hold five seconds. Eyes don\'t blink.',
        'This is the smolder.',
      ],
      instruct: [
        'Smolder. Hold. Begin.',
      ],
      // 5s is enough to set the smoulder and hold it — past that it
      // tips into "less trustworthy" territory (Tracy / Live Science:
      // heavy-lid gaze reads as sexually-interested AND less
      // trustworthy at sustained durations).
      drillSeconds: 5,
      targetBlinks: 2,
      weights: {
        GazeDimension.eyeStability: 0.35,
        GazeDimension.blinkControl: 0.10,
        GazeDimension.rhythm:       0.00,
        GazeDimension.tension:      0.20,
        GazeDimension.smileControl: 0.35,
      },
      isRhythmLesson: false,
      correction: [
        'Both mouth corners moved — that\'s a grin, not a smolder.',
        'One side only. Half-lid heavy. Again.',
      ],
    ),

    // ── LESSON 4 — CAUGHT ───────────────────────────────────────────
    GazeLesson(
      id: 'caught',
      number: 4,
      name: 'CAUGHT',
      oneLine: 'She caught you. Don\'t flinch. Smile.',
      objective: 'Hold half a beat past comfort. One mouth corner. Slow.',
      story: [
        'She turned. She caught you looking.',
        'This is the moment that defines whether you\'re a boy or a man.',
        'The boy looks away. The man holds her eye and smiles.',
      ],
      demo: [
        'She just turned to you. Don\'t move.',
        'Don\'t flinch. Don\'t blink.',
        'Hold her eye half a beat past comfortable.',
        'Now — one corner of your mouth pulls up.',
        'Slow. Confident.',
        'Like you meant to be looking at her all along.',
      ],
      instruct: [
        'She caught you. Hold. Smile one side. Begin.',
      ],
      // CAUGHT is by definition a brief beat — she catches you, you
      // hold past comfortable (~2-3s past the catch instant) and the
      // smile arrives. 3s captures the whole micro-arc.
      drillSeconds: 3,
      targetBlinks: 1,
      weights: {
        GazeDimension.eyeStability: 0.40,
        GazeDimension.blinkControl: 0.10,
        GazeDimension.rhythm:       0.00,
        GazeDimension.tension:      0.20,
        GazeDimension.smileControl: 0.30,
      },
      isRhythmLesson: false,
      correction: [
        'You looked away — you apologised with your eyes.',
        'Never apologise for looking. Own it. Again.',
      ],
    ),

    // ── LESSON 5 — THE SILENT HOLD ──────────────────────────────────
    GazeLesson(
      id: 'silent_hold',
      number: 5,
      name: 'THE SILENT HOLD',
      oneLine: 'Lock. Say nothing. Let it press into her.',
      objective: 'Hold the look through silence. Don\'t fill the gap.',
      story: [
        'Two strangers who hold eye contact for sixty seconds report falling in love at higher rates than controls.',
        'There is something primal in it.',
        'Most men crack at ten. You\'re learning to hold twenty-five.',
      ],
      demo: [
        'Lock my left eye. Soft, not hard.',
        'Mouth closed. Throat soft.',
        'Don\'t say a word. Don\'t smile.',
        'Breathe slow through your nose.',
        'Let the silence get heavy.',
        'Twenty-five seconds.',
        'If it gets uncomfortable — that\'s the moment most men crack.',
        'Stay. Watch what happens.',
      ],
      instruct: [
        'Stare through. Don\'t blink. Begin.',
      ],
      drillSeconds: 25,
      targetBlinks: 6,
      weights: {
        GazeDimension.eyeStability: 0.45,
        GazeDimension.blinkControl: 0.15,
        GazeDimension.rhythm:       0.00,
        GazeDimension.tension:      0.30,
        GazeDimension.smileControl: 0.10,
      },
      isRhythmLesson: false,
      correction: [
        'You broke first — said something with your face.',
        'Let her be the one who can\'t take it. Again.',
      ],
    ),

    // ── LESSON 6 — THE SLOW BLINK ───────────────────────────────────
    GazeLesson(
      id: 'slow_blink',
      number: 6,
      name: 'THE SLOW BLINK',
      oneLine: 'Eyelids fall slow, open slow. Like waking from a nap.',
      objective: 'Long lazy blinks. No flutter. No twitch.',
      story: [
        'Watch a confident cat or lion blink. SLOW. Heavy. Deliberate.',
        'Fast blinking screams anxiety to her primal brain.',
        'Slow blinking says I\'m safe and I\'m not going anywhere.',
        'Easiest move to master. One of the most powerful.',
      ],
      demo: [
        'Lock my eye.',
        'Now — let your top lid fall.',
        'Like a curtain dropping. Slow.',
        'Closed for one full second.',
        'Now open. JUST AS SLOW.',
        'Lock again. Hold.',
        'One more blink. Same speed.',
        'The slower you blink, the more dangerous you read.',
      ],
      instruct: [
        'Lock. Slow blink. Two of them. Begin.',
      ],
      // 6s = lock + two slow blinks with the lock held between. Long
      // enough to practise the cadence, short enough not to be a
      // stare-off.
      drillSeconds: 6,
      targetBlinks: 2,
      weights: {
        GazeDimension.eyeStability: 0.35,
        GazeDimension.blinkControl: 0.40,
        GazeDimension.rhythm:       0.00,
        GazeDimension.tension:      0.20,
        GazeDimension.smileControl: 0.05,
      },
      isRhythmLesson: false,
      correction: [
        'Your eyes were a strobe — that screamed nerves.',
        'Half the speed. Deliberate. Again.',
      ],
    ),

    // ── LESSON 7 — THE TRIANGLE ─────────────────────────────────────
    GazeLesson(
      id: 'the_triangle',
      number: 7,
      name: 'THE TRIANGLE',
      oneLine: 'Left eye. Right eye. Mouth. Back up. Slow.',
      objective: 'Travel slow eye → eye → mouth → eye. No flicks.',
      story: [
        'This is Sophie Rose Lloyd\'s seventeen-million-view move. The lip triangle.',
        'Left eye, slow to lips, slow to right eye.',
        'The journey is the magnetism.',
        'They know exactly what you\'re thinking.',
      ],
      demo: [
        'Find my left eye. Hold one beat.',
        'Now — slow descent to my lips.',
        'Stay on my mouth two beats. Like you\'re thinking.',
        'Now slow climb to my right eye. Hold one beat.',
        'Smooth like water. No flicks.',
        'She felt every inch of that journey.',
      ],
      instruct: [
        'Left eye. Lips. Right eye. Slow. Begin.',
      ],
      // Sophie Rose Lloyd 17M-view canonical timing: left eye ~1s →
      // lips ~2s → right eye ~1s. Plus a half-beat re-entry. 5s is
      // the budget for one clean triangle.
      drillSeconds: 5,
      targetBlinks: 1,
      weights: {
        GazeDimension.eyeStability: 0.30,
        GazeDimension.blinkControl: 0.10,
        GazeDimension.rhythm:       0.30,
        GazeDimension.tension:      0.25,
        GazeDimension.smileControl: 0.05,
      },
      isRhythmLesson: true,
      correction: [
        'You flicked — that\'s a tic, not presence.',
        'Half the speed. Make the room wait. Again.',
      ],
    ),

    // ── LESSON 8 — THE RETURN ───────────────────────────────────────
    GazeLesson(
      id: 'the_return',
      number: 8,
      name: 'THE RETURN',
      oneLine: 'Drift away calm. Return slower than you left.',
      objective: 'Lock. Drift. Come back slower than you went.',
      story: [
        'The man who never looks away looks desperate.',
        'The man who looks away and never returns looks bored.',
        'The master looks away calm and returns SLOWER than he left.',
        'This says: nothing here is more interesting than you. Just confirming.',
      ],
      demo: [
        'Lock my eye.',
        'Hold three seconds.',
        'Now drift away. Calm. To the side.',
        'Like you noticed something casual.',
        'Stay gone two seconds.',
        'Now come back — SLOWER than you left.',
        'Don\'t snap. Don\'t flick. Drift.',
        'Like you keep deciding to look at her.',
      ],
      instruct: [
        'Lock. Drift. Return slower. Begin.',
      ],
      drillSeconds: 20,
      targetBlinks: 5,
      weights: {
        GazeDimension.eyeStability: 0.30,
        GazeDimension.blinkControl: 0.10,
        GazeDimension.rhythm:       0.35,
        GazeDimension.tension:      0.20,
        GazeDimension.smileControl: 0.05,
      },
      isRhythmLesson: true,
      correction: [
        'Your return snapped — looked guilty, like you got caught.',
        'Drift back. Slower than you left. Again.',
      ],
    ),

    // ── LESSON 9 — THE ENTRANCE ─────────────────────────────────────
    GazeLesson(
      id: 'the_entrance',
      number: 9,
      name: 'THE ENTRANCE',
      oneLine: 'Find her across the room. Hold past comfort. You break.',
      objective: 'Find. Hold one beat too long. Break first — slow.',
      story: [
        'Across a room, with strangers, you have three seconds to tell her \'I see you\' without a single word.',
        'Most men send the wrong signal — fast glances, broken contact.',
        'You\'re learning the right one — locked, calm, you break on YOUR timing.',
      ],
      demo: [
        'Across the room. Find her.',
        'Lock her eye from distance.',
        'Don\'t lift your brow. Don\'t smile yet.',
        'Hold three seconds.',
        'She just felt you see her.',
        'Now — YOU break first.',
        'Slow. To the side. Not down.',
        'Your timing. Not her permission.',
      ],
      instruct: [
        'Find her. Lock. Break first. Begin.',
      ],
      // ENTRANCE is a cross-room initiation — Moore 1985\'s ≤3s
      // glance is the documented signal. 4s gives a half-beat past
      // comfortable before you break first.
      drillSeconds: 4,
      targetBlinks: 1,
      weights: {
        GazeDimension.eyeStability: 0.40,
        GazeDimension.blinkControl: 0.10,
        GazeDimension.rhythm:       0.15,
        GazeDimension.tension:      0.30,
        GazeDimension.smileControl: 0.05,
      },
      isRhythmLesson: true,
      correction: [
        'You let her break first — you handed her control.',
        'You break. Your timing. Again.',
      ],
    ),

    // ── LESSON 10 — THE LISTENING GAZE ──────────────────────────────
    GazeLesson(
      id: 'listening_gaze',
      number: 10,
      name: 'THE LISTENING GAZE',
      oneLine: 'Hold her eyes while SHE talks. Almost no one does.',
      objective: 'Hold the gaze while she speaks. Don\'t drift.',
      story: [
        'Tyra Banks named this. The smize — smile with your eyes only.',
        'Most men can\'t isolate the muscle.',
        'When THEY are talking and you smize while listening, the speaker feels seen, understood, chosen.',
        'Most underrated move in presence.',
      ],
      demo: [
        'She\'s talking. Lock her left eye.',
        'Mouth completely neutral — don\'t smile with your mouth.',
        'Now — lift the muscle at the OUTER corner of each eye. Just a hair.',
        'That\'s smize.',
        'Tiny nod when she hits a key word.',
        'Slow blink every few breaths.',
        'Don\'t look at your phone. Her drink. Her hair.',
        'Stay for twenty-five seconds.',
        'Be the only man who didn\'t look away.',
      ],
      instruct: [
        'She\'s talking. Smize. Stay. Begin.',
      ],
      drillSeconds: 25,
      targetBlinks: 7,
      weights: {
        GazeDimension.eyeStability: 0.45,
        GazeDimension.blinkControl: 0.10,
        GazeDimension.rhythm:       0.00,
        GazeDimension.tension:      0.20,
        GazeDimension.smileControl: 0.25,
      },
      isRhythmLesson: false,
      correction: [
        'Your eyes wandered — she noticed.',
        'Stay locked. Smize. Outclass every man she\'s met. Again.',
      ],
    ),

    // ── SOCIALS 1 — THE REEL ────────────────────────────────────────
    GazeLesson(
      id: 'the_reel',
      number: 11,
      name: 'THE REEL',
      oneLine: 'Five moves on camera. Soft. Smoulder. Drop. Return. Smile.',
      objective: 'Hit every move as I call it. Slow between beats.',
      story: [
        'This is the boss lesson.',
        'Every move from the first ten — chained together in one take.',
        'Lock. Hood. Slow blink. Drop. Climb. Smolder. Head tilt. Drift. Return slower. Half-smile. Break.',
        'This is the reel girls save to their camera roll.',
      ],
      demo: [
        'Phone at eye level. Stillness first. Don\'t move.',
        'Lock the lens. Find her in it.',
        'Hood the lids — that\'s the lesson-one move. Twenty percent down.',
        'Now — one slow blink. Cat-trust. Like a curtain.',
        'Open. Lock again. Don\'t smile yet.',
        'Drop. SLOW. To the bottom of the frame — her lips.',
        'Stay there two beats. Like you\'re thinking about them.',
        'Climb back. Smooth. No flicks.',
        'Now hit the smolder. Lower lid up. Asymmetric mouth, one corner.',
        'Head tilt — five degrees. To the right.',
        'Drift to the side. Calm. Like you noticed something casual.',
        'Two seconds gone.',
        'Now come back. SLOWER than you left.',
        'Lock heavy. One full beat.',
        'Half-smile. One corner only.',
        'Now — break. Down, not sideways.',
        'Save that clip. That one goes viral.',
      ],
      instruct: [
        'Phone at eye level. Run the sequence. Begin.',
      ],
      sequenceCues: [
        'Lock the lens.',
        'Soft eyes. Smoulder.',
        'Drop — slow — to the mouth.',
        'Climb back to the eyes.',
        'Drift away — slow, to the side.',
        'Drift back — slower than you left.',
        'Now. Half a smile. One corner.',
      ],
      drillSeconds: 24,
      targetBlinks: 7,
      weights: {
        GazeDimension.eyeStability: 0.20,
        GazeDimension.blinkControl: 0.10,
        GazeDimension.rhythm:       0.35,
        GazeDimension.tension:      0.15,
        GazeDimension.smileControl: 0.20,
      },
      isRhythmLesson: true,
      correction: [
        'You rushed it — the moves bled into each other.',
        'Half the speed. Let each move land for the camera. Again.',
      ],
    ),

    // ── SOCIALS 2 — THE SLOW BURN ───────────────────────────────────
    GazeLesson(
      id: 'the_slow_burn_reel',
      number: 12,
      name: 'THE SLOW BURN',
      oneLine: 'Heavier than the reel. The look that already decided.',
      objective: 'Hold the heat. Hit each move slow as I call it.',
      story: [
        'Same sequence. Half the speed. Twice the heat.',
        'This is the look that says \'I\'ve already decided.\'',
        'The look that gets screenshotted and sent to her friends.',
      ],
      demo: [
        'Lens at eyebrow level. Stillness. Don\'t move.',
        'Brow dead. Top lid forty percent down — heavier than the smolder.',
        'Breathe slow through your nose. Drop the shoulders.',
        'Lock the lens. Hold three full seconds.',
        'Slow blink — slower than last time. Two beats closed.',
        'Open slow. Don\'t lock yet — let your eyes drift open.',
        'Now drop. Slowest move yet. Three beats down.',
        'Stay on the lips four full seconds. Make the room wait.',
        'Climb back. Smooth like syrup. No flick.',
        'Hold heavy. Don\'t blink.',
        'Tilt your head — barely. Three degrees.',
        'Look away — like the camera wasn\'t there. Calm.',
        'Now come back. Slowest move yet. Drift in.',
        'Lock heavy.',
        'Half-smile. One corner only. Don\'t show teeth.',
        'Now — break. Slow. Down.',
      ],
      instruct: [
        'Lens. Slow burn. Begin.',
      ],
      sequenceCues: [
        'Find the lens. Hold it heavy.',
        'Top lid down a hair.',
        'Drop — slow — to the mouth.',
        'Drag it back to the eyes.',
        'Head tilt — barely.',
        'Look away like it was your choice.',
        'Back. Slow half-smile.',
      ],
      drillSeconds: 28,
      targetBlinks: 7,
      weights: {
        GazeDimension.eyeStability: 0.25,
        GazeDimension.blinkControl: 0.10,
        GazeDimension.rhythm:       0.30,
        GazeDimension.tension:      0.15,
        GazeDimension.smileControl: 0.20,
      },
      isRhythmLesson: true,
      correction: [
        'Too fast — it read as nervous, not hungry.',
        'Half the speed. Smolder every single move. Again.',
      ],
    ),
  ];

  static GazeLesson byId(String id) =>
      all.firstWhere((l) => l.id == id, orElse: () => all.first);
}
