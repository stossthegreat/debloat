import 'gaze_lesson.dart';

/// THE GAZE — Lucien's seductive-eye masterclass.
///
/// Twelve named eye MOVES taught the way a real seducer teaches: ONE
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
      oneLine: 'Twelve seconds. One iris. You break first.',
      objective: 'Twelve seconds on one iris. Brow dead. You break.',
      story: [
        'Most men crack at second three. The one who holds twelve '
            'without flinching is the one she remembers — power before '
            'a single word is spoken. That is the entire game.',
      ],
      demo: [
        'Her LEFT eye — the iris, the dark wet centre. Not both eyes, '
            'not a wide stare. ONE iris. Drop every muscle in your '
            'brow until it goes dead like you just woke up. Top lid '
            'down a millimetre — heavy, not closed. Jaw unclenched. '
            'Throat soft. Now don\'t move. Twelve seconds. Breathe '
            'slow through your nose into your chest, not your '
            'shoulders. The second it gets heavy is the second she '
            'feels it — that is when you stay. You break when YOU '
            'decide. Never sooner.',
      ],
      instruct: [
        'One iris. Brow dead. Four seconds. Go.',
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
        'You blinked the second it got heavy — she felt the flinch '
            'before your eyelid hit the bottom.',
        'Hold it like you were always going to. Again.',
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
        'How you BREAK says more than the look. Down reads as desire. '
            'Up and away reads as bored.',
      ],
      demo: [
        'Lock her eye. Then let your eyes fall — slow, heavy — to the '
            'tiny dip above her top lip. Stay there one full beat. Then '
            'climb back to her eye. No darting. No flick. The journey '
            'down is the move; rushing kills it.',
      ],
      instruct: [
        'Lock. Drop slow. Down only. Go.',
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
        'You broke up and away — you read like you were scanning for the exit.',
        'Eyes fall slow, like they\'re heavy. Down. Again.',
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
        'A hard wide stare trips an alarm in her brain. Soft eyes read '
            'as "I like what I see and I\'ve got all night." That\'s '
            'the smoulder.',
      ],
      demo: [
        'Drop every muscle above your eyes — brow goes dead, like you '
            'just woke up. Pull the top lid down a hair — half-lidded, '
            'not closed. Mouth corner lifts a single millimetre. The '
            'smile is in the MOUTH, never the eyes. Eyes stay heavy '
            'and locked. That contradiction is the smoulder.',
      ],
      instruct: [
        'Brow dead. Lids half. Mouth corner. Lock. Go.',
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
        'That was a hard stare — wide, tense, winning a fight no one started.',
        'Half the tension. Want her, don\'t hunt her. Again.',
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
        'She WILL catch you. The boy snaps away ashamed. The man holds '
            'and lets a slow smile start. Owning the look is the entire move.',
      ],
      demo: [
        'Your eyes meet hers — DO NOT BREAK. Hold half a second past '
            'comfortable. Now ONE corner of your mouth pulls up — not '
            'both, one. Eyes stay locked while it happens. The smile '
            'arrives like you were going to look at her anyway.',
      ],
      instruct: [
        'Caught. Hold. One mouth corner. Go.',
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
        'You looked away fast — you apologised with your whole face.',
        'Never apologise for looking. Hold, smile. Again.',
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
        'Two strangers who hold gaze in silence feel closer than two '
            'who talked for an hour — that\'s a real study. The silence '
            'is the weapon most men are too scared to use.',
      ],
      demo: [
        'Lock onto her eye. Mouth closed, not pinched. Throat soft. '
            'Breathe slow through your nose. Don\'t fill the silence '
            'with a smile, a sound, a sip of your drink. Let the gap '
            'get heavy. She breaks first, every time.',
      ],
      instruct: [
        'Lock. No words. Hold. Go.',
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
        'You cracked first — looked away to make the silence stop.',
        'Let HER be the one who can\'t take it. Again.',
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
        'Fast fluttering eyes scream anxiety — she feels it before she '
            'knows why. Slow lazy eyes say: I am not nervous and I\'m '
            'not going anywhere.',
      ],
      demo: [
        'Lock her eye. When the blink comes, let the top lid FALL — '
            'slow, heavy, like a curtain. Count one full beat with the '
            'eyes closed. Then open them — just as slow. No flutter, '
            'no twitch. The slower you blink, the more dangerous you read.',
      ],
      instruct: [
        'Lock. Slow blink. Heavy. Go.',
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
        'Your eyes were a strobe light — every blink screamed nerves.',
        'Slow them on purpose until the calm becomes real. Again.',
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
        'Friends hold eye to eye. Lovers travel to the mouth and back. '
            'The journey is the move — and it tells her exactly what '
            'this is, with zero words.',
      ],
      demo: [
        'Her LEFT eye — one beat. Her RIGHT eye — one beat. Now drop, '
            'slow, to her LIPS — stay there a full second, like you\'re '
            'thinking about them. Climb back to her eyes. Smooth like '
            'pouring water. A flick is a nervous tic. Slow is intent.',
      ],
      instruct: [
        'Left eye. Right eye. Mouth — slow. Back up. Go.',
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
        'You flicked down too fast — it read as a tic, not intent.',
        'Half the speed. Let her feel the journey. Again.',
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
        'A non-stop laser stare is exhausting, not magnetic. The power '
            'is in the RETURN — slower than the exit, telling her she '
            'was still the most interesting thing in the room.',
      ],
      demo: [
        'Lock her eye. Now drift away — calm, casual, like you noticed '
            'something at the bar. Two seconds gone. Now come BACK — '
            'slower than you left. Don\'t snap. Drift. Like you keep '
            'arriving at her, deciding to.',
      ],
      instruct: [
        'Lock. Drift. Return slower. Go.',
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
        'Your return was a snap — like you got caught and rushed back.',
        'Return is always slower than exit. Again.',
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
        'Before you say a word, the look across the room has already '
            'told her who you are. The man who holds and breaks first '
            'doesn\'t wait for permission.',
      ],
      demo: [
        'Find her eyes from distance. Lock. Hold ONE beat past '
            'comfortable — let her feel that you saw her. Then YOU '
            'break first — slow, to the side. Not down, not away in '
            'panic. Side. Your beat, your timing, your call.',
      ],
      instruct: [
        'Find her. Hold past comfort. Break first. Go.',
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
        'You let HER break first — you handed her control before you crossed the room.',
        'You break. Your beat. Again.',
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
        'Every man holds eye contact while HE talks. The second she '
            'speaks, his eyes wander. Hold while SHE talks and you '
            'become the rarest thing in her week — a man who is fully, '
            'dangerously present.',
      ],
      demo: [
        'She\'s speaking. Pick her left eye. Soft brow. Tiny slow nods '
            'on her key words. A slow blink every few breaths. Eyes do '
            'not drift to her hair, her drink, your phone, the room. '
            'Stay there. Be the only man who didn\'t look away.',
      ],
      instruct: [
        'She\'s talking. Lock soft. Stay. Go.',
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
        'Your eyes wandered the moment it was her turn. She noticed.',
        'Stay locked while she speaks. Outclass every man she\'s met. Again.',
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
        'This is the look influencers built whole feeds on. Move by '
            'move, on camera.',
      ],
      demo: [
        'Lock onto the lens like it\'s her. Brow dead. I call each '
            'move; you hit it on the beat. Slow between every cue. '
            'Let the camera roll the entire way through. Don\'t '
            'rush the last smile — that\'s the one that gets saved.',
      ],
      instruct: [
        'Lock the lens. I call, you move. Slow. Begin.',
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
        'Stiff. You rushed the beats and the smile came too early.',
        'Slower between moves. Let each one land for the camera. Again.',
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
        'Same shape, more heat. This is the look that says you\'ve '
            'already decided — and the camera catches every second.',
      ],
      demo: [
        'Lens at lid-level. Brow dead, top lid half-down. Breathe slow '
            'through your nose. Heavier than the reel — every move at '
            'half speed. Like you\'re looking at the last thing you '
            'want before you take it.',
      ],
      instruct: [
        'Eyes on the lens. Heavy. I call. Begin.',
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
        'Half the speed. Let every move smoulder. Again.',
      ],
    ),
  ];

  static GazeLesson byId(String id) =>
      all.firstWhere((l) => l.id == id, orElse: () => all.first);
}
