/// 12 + 12 + 12 lessons. Each one drives ONE session.
///
/// Each lesson is exactly: a name + 2–3 target lines the user repeats,
/// each with one delivery cue. The teacher walks the apprentice through
/// the lines via the OpenAI Realtime API; the system prompt has the
/// whole syllabus pinned at the top.
///
/// Eyes lessons follow a different shape — see [EyeLesson] below.

class TargetLine {
  final String line;
  final String cue;       // ONE delivery instruction (drop pitch on X)
  const TargetLine({required this.line, required this.cue});

  Map<String, dynamic> toJson() => {'line': line, 'cue': cue};
}

class Lesson {
  final String id;
  final int    number;     // 1..12
  final String name;
  final String oneLine;    // one-sentence what the move IS
  final List<TargetLine> targetLines;

  const Lesson({
    required this.id,
    required this.number,
    required this.name,
    required this.oneLine,
    required this.targetLines,
  });
}

// ─── RHETORIC — taught by Lucien ─────────────────────────────────────

abstract final class RhetoricSyllabus {
  static const all = <Lesson>[
    Lesson(
      id: 'conviction', number: 1, name: 'CONVICTION',
      oneLine: 'Drop the pitch. Slow the pace. Say it like you know.',
      targetLines: [
        TargetLine(
          line: 'I am the right person for this.',
          cue:  'drop the pitch on "right"; pause where the comma would be',
        ),
        TargetLine(
          line: 'I am the right person for this. I have done it before. I will do it again.',
          cue:  'three sentences, three periods — pause between each, end on silence after "again"',
        ),
      ],
    ),
    Lesson(
      id: 'pause_for_power', number: 2, name: 'PAUSE FOR POWER',
      oneLine: 'After the loaded word — stop. Let it land.',
      targetLines: [
        TargetLine(
          line: 'I told her — exactly what I thought.',
          cue:  'long pause on the dash; drop the pitch on "thought"',
        ),
        TargetLine(
          line: 'The last lesson life taught me — was that confidence is the willingness to wait.',
          cue:  'pause on the dash; let two beats sit after "wait" before you stop',
        ),
      ],
    ),
    Lesson(
      id: 'end_on_the_strong_word', number: 3, name: 'END ON THE STRONG WORD',
      oneLine: 'The last word of a sentence is the loudest place in the language.',
      targetLines: [
        TargetLine(
          line: 'She left, and that — was devastating.',
          cue:  'land "devastating" with the pitch dropped; nothing after',
        ),
        TargetLine(
          line: 'I paid. I walked out. I never called her again. And I felt — relieved.',
          cue:  'each sentence ends on a charged word; "relieved" is the closer',
        ),
      ],
    ),
    Lesson(
      id: 'specificity', number: 4, name: 'SPECIFICITY',
      oneLine: 'Concrete beats abstract. Named beats vague.',
      targetLines: [
        TargetLine(
          line: 'Last March I broke my foot in three places.',
          cue:  'hit "March"; drop the pitch on "three places"',
        ),
        TargetLine(
          line: 'A bowl of pho at a market in Hanoi. Six in the morning. Plastic stool. Twenty thousand dong.',
          cue:  'four sentences, four specifics — each one a piece of evidence',
        ),
      ],
    ),
    Lesson(
      id: 'brevity', number: 5, name: 'BREVITY',
      oneLine: 'Say less. The silence is your weight.',
      targetLines: [
        TargetLine(
          line: 'It is the strongest option.',
          cue:  'five words, period — nothing after',
        ),
        TargetLine(
          line: 'It rains for ten months. The buildings are honest. You can still afford to live there.',
          cue:  'three short sentences; stop the moment the third one ends',
        ),
      ],
    ),
    Lesson(
      id: 'hook_first', number: 6, name: 'HOOK FIRST',
      oneLine: 'Lead with the most charged sentence. Backstory comes second.',
      targetLines: [
        TargetLine(
          line: 'I once spent eighteen hours in an airport with a woman I had just met.',
          cue:  'land "eighteen hours" and "just met" — the hook is the math',
        ),
        TargetLine(
          line: 'I almost drowned on my honeymoon.',
          cue:  'seven words; the hook is the contrast between "drowned" and "honeymoon"',
        ),
      ],
    ),
    Lesson(
      id: 'take_a_position', number: 7, name: 'TAKE A POSITION',
      oneLine: 'Pick a side. The wrong call beats no call.',
      targetLines: [
        TargetLine(
          line: 'Coffee. Every time.',
          cue:  'two sentences, two periods, no hedge before either',
        ),
        TargetLine(
          line: 'Coffee. Every time. Tea is what you serve someone you do not trust.',
          cue:  'drop the pitch on "trust"; let the silence after sit for a beat',
        ),
      ],
    ),
    Lesson(
      id: 'frame_the_question', number: 8, name: 'FRAME THE QUESTION',
      oneLine: 'Whoever asks the question shapes the answer.',
      targetLines: [
        TargetLine(
          line: 'What is the one thing you do alone that you have never told anyone else you do?',
          cue:  'slow down; let the question hang at the end, do not fill the silence',
        ),
        TargetLine(
          line: 'Where do you go when you want a drink that actually matters?',
          cue:  'land "actually matters"; drop the pitch on the final word',
        ),
      ],
    ),
    Lesson(
      id: 'the_pivot', number: 9, name: 'THE PIVOT',
      oneLine: 'When pushed, do not defend. Reframe.',
      targetLines: [
        TargetLine(
          line: 'Quiet is what I do when I am listening. What did you want me to hear?',
          cue:  'two sentences; the second one moves the question back to them',
        ),
        TargetLine(
          line: 'I notice you have thought about me a lot to land on that. Tell me what you actually wanted to say.',
          cue:  'amused on the first half; sharper on "actually"',
        ),
      ],
    ),
    Lesson(
      id: 'story_over_opinion', number: 10, name: 'STORY OVER OPINION',
      oneLine: 'Do not tell me what you think. Tell me what happened.',
      targetLines: [
        TargetLine(
          line: 'There was a winter I lost everything. Three months I lived on a friend\'s sofa.',
          cue:  '"everything" is the load-bearing word — drop the pitch on it',
        ),
        TargetLine(
          line: 'I did not work hard because I wanted to. I worked hard because the alternative was the sofa.',
          cue:  'antithesis — slow on "alternative was the sofa"',
        ),
      ],
    ),
    Lesson(
      id: 'callback', number: 11, name: 'THE CALLBACK',
      oneLine: 'Reference something they said earlier. Show you noticed.',
      targetLines: [
        TargetLine(
          line: 'You said your favourite bar in Lisbon was the one with the broken jukebox.',
          cue:  'said as if the memory just arrived — slight slow on "broken jukebox"',
        ),
        TargetLine(
          line: 'Every place you have told me about tonight has been a place where something was broken. That is a type.',
          cue:  'land "that is a type" on a dropped pitch; pause before saying it',
        ),
      ],
    ),
    Lesson(
      id: 'the_synthesis', number: 12, name: 'THE SYNTHESIS',
      oneLine: 'Combine all eleven. Make a 60-second case for yourself.',
      targetLines: [
        TargetLine(
          line: 'I built three businesses by the time I was thirty. Two failed. One did not.',
          cue:  'the hook + specificity + tricolon — three numbered claims back-to-back',
        ),
        TargetLine(
          line: 'You do not bet on people who have never lost. You bet on people who lost twice, did not fold, and came back the third time with a quieter version of the same fire.',
          cue:  'antithesis + tricolon + end on "fire" — the closer of the whole curriculum',
        ),
      ],
    ),
  ];

  static Lesson byId(String id) =>
      all.firstWhere((l) => l.id == id, orElse: () => all.first);
}

// ─── EYES — taught by Diabla, the silent way ─────────────────────────────
//
// Different shape from rhetoric / rizz. The user doesn't say lines; he
// performs eye behaviours while Diabla coaches over voice. Each lesson
// is a sequence of MOVES — a beat she names, a duration, and a metric
// the local engine checks against MediaPipe's per-frame signal.

enum EyeMetric {
  /// User must hold eye contact (gaze locked on target) for the duration.
  holdContact,
  /// Slow blink — closing eyes for 1+ seconds, opening slowly.
  slowBlink,
  /// Look away then return.
  lookAwayReturn,
  /// Half-lidded soft focus.
  softFocus,
  /// Head tilt (5-15°).
  slightTilt,
  /// No blink for the duration.
  noBlink,
}

/// One move inside an eye-contact lesson. Drives the five-beat teaching
/// loop the screen walks through: NAME → WHY → DEMO → YOU GO → JUDGE.
///
/// Diabla speaks every beat. The apprentice never reads — he watches
/// the ghost face, listens, and performs. Each beat has its own line so
/// the rhythm of a real teacher is preserved (not one giant monologue).
class EyeMove {
  /// Short capitalised title of the move. Spoken aloud + shown on screen
  /// during the NAME beat. Example: "THE LOCK".
  final String name;

  /// One-line reason this move matters. Spoken in the WHY beat.
  /// Example: "Whoever looks away first loses. So you don't look away
  /// first."
  final String why;

  /// What Diabla says while DEMONSTRATING the move in voice. Usually
  /// narrates her own performance — the ghost face animates alongside.
  /// Example: "Watch. I lock onto you. I hold. I don't blink to win."
  final String demoSays;

  /// What she says when handing the attempt to the apprentice. The
  /// hold timer starts when this line finishes.
  /// Example: "Now. Eyes on mine. Six seconds. Don't break first."
  final String youGoSays;

  /// Verdict if the local engine scored the attempt as a pass.
  final String passSays;

  /// Verdict if the attempt failed.
  final String failSays;

  /// On-screen hint card during the apprentice's attempt. Short, all-
  /// caps. Example: "HOLD HER EYES · 6 SECONDS".
  final String onScreenHint;

  /// What MediaPipe must observe.
  final EyeMetric metric;

  /// How long the apprentice must hold the behavior (seconds).
  final int holdSeconds;

  const EyeMove({
    required this.name,
    required this.why,
    required this.demoSays,
    required this.youGoSays,
    required this.passSays,
    required this.failSays,
    required this.onScreenHint,
    required this.metric,
    required this.holdSeconds,
  });
}

class EyeLesson {
  final String id;
  final int number;
  final String name;
  final String oneLine;
  final List<EyeMove> moves;

  const EyeLesson({
    required this.id,
    required this.number,
    required this.name,
    required this.oneLine,
    required this.moves,
  });
}

// ─── RIZZ ROLEPLAY SCENARIOS ─────────────────────────────────────────────
// The scenes Diabla plays. Same realtime infrastructure as the lesson
// flow, but the persona is "roleplay" — Diabla in scene + Lucien
// cutting in as [COACH].

class Scenario {
  final String id;
  final String name;
  final String setting;     // 1-2 sentence scene setup, fed to the prompt
  final String oneLineCard; // what the picker tile says
  const Scenario({
    required this.id,
    required this.name,
    required this.setting,
    required this.oneLineCard,
  });
}

abstract final class RizzScenarios {
  static const all = <Scenario>[
    Scenario(
      id: 'the_bar', name: 'THE BAR',
      setting:
          'A loud bar at 11pm on a Friday. She just sat down two stools '
          'away. Half a glass of wine left. Glanced over. Looked away. '
          'Glanced again. She is 28, dressed sharp, quietly amused, and '
          'has had this conversation a hundred times.',
      oneLineCard:
          'She just sat down two stools away. Open. Earn the next sentence.',
    ),
    Scenario(
      id: 'the_wedding', name: 'THE WEDDING',
      setting:
          'Your friend\'s wedding. You are seated next to the bride\'s '
          'younger sister at the reception dinner. She is 27, witty, '
          'slightly drunk, has been seated next to the single friend '
          'twice this year and is over it.',
      oneLineCard:
          'Bride\'s sister. Witty, slightly drunk, tired of being seated next to you.',
    ),
    Scenario(
      id: 'the_cashier', name: 'THE CASHIER',
      setting:
          'Specialty coffee shop, Tuesday afternoon. You are paying. The '
          'queue is gone. She is 24, bright, polite, gets hit on six '
          'times a shift and respects only originality.',
      oneLineCard:
          '24, sharp, gets hit on six times a shift. You have 30 seconds.',
    ),
    Scenario(
      id: 'the_ex', name: 'THE EX',
      setting:
          'You ran into your ex at a mutual friend\'s housewarming. You '
          'have not spoken in two years. She has moved on — married now — '
          'and is friendly but extremely clear about the frame.',
      oneLineCard:
          'Your ex. Two years. She is married now. You did not expect this.',
    ),
  ];

  static Scenario byId(String id) =>
      all.firstWhere((s) => s.id == id, orElse: () => all.first);
}

abstract final class EyesSyllabus {
  static const all = <EyeLesson>[
    // ── LESSON 1 ────────────────────────────────────────────────────────
    EyeLesson(
      id: 'the_lock', number: 1, name: 'THE LOCK',
      oneLine: 'First to blink dies. Tonight you don\'t die.',
      moves: [
        EyeMove(
          name:        'THE LOCK',
          why:         'First to blink dies. Tonight you don\'t die.',
          demoSays:    'Watch me. I\'m not anywhere else. Six seconds. '
                       'I don\'t move.',
          youGoSays:   'Your turn. Don\'t blink. Don\'t drift. Don\'t lose.',
          passSays:    'Good. You didn\'t flinch. That\'s the floor.',
          failSays:    'You broke. Most men do. Again — finish it this time.',
          onScreenHint: 'HOLD HER EYES · 6 SEC',
          metric:       EyeMetric.holdContact,
          holdSeconds:  6,
        ),
        EyeMove(
          name:        'PAST COMFORTABLE',
          why:         'Comfortable is where you stop. Attraction lives '
                       'past that.',
          demoSays:    'Eight seconds. The last two are the move. I do '
                       'not flinch.',
          youGoSays:   'Past the wall. Eight. Stay.',
          passSays:    'You stayed past the part where it gets weird. Rare.',
          failSays:    'Bailed at seven. The last second was the whole move. Again.',
          onScreenHint: 'HOLD · 8 SEC',
          metric:       EyeMetric.holdContact,
          holdSeconds:  8,
        ),
      ],
    ),

    // ── LESSON 2 ────────────────────────────────────────────────────────
    EyeLesson(
      id: 'the_triangle', number: 2, name: 'THE TRIANGLE',
      oneLine: 'Eyes. Mouth. Eyes. The oldest signal there is.',
      moves: [
        EyeMove(
          name:        'EYES TO MOUTH',
          why:         'Eyes, mouth, eyes. The oldest signal in any '
                       'language. She knows what it means.',
          demoSays:    'Watch. Eyes. Mouth. Hold. Eyes.',
          youGoSays:   'Now you. Eyes. Mouth. Hold there. Three seconds.',
          passSays:    'There. The drop was the message. She felt it.',
          failSays:    'Too quick. The mouth pause is the whole move. '
                       'Sit in it.',
          onScreenHint: 'DROP TO MOUTH · 3 SEC',
          metric:       EyeMetric.holdContact,
          holdSeconds:  3,
        ),
        EyeMove(
          name:        'THE FULL TRIANGLE',
          why:         'Each beat slower than the last. Slow is what '
                       'makes it predatory — not creepy.',
          demoSays:    'Eyes. Mouth. Eyes. Each one slower. That is the '
                       'rhythm.',
          youGoSays:   'Run it. Each beat slower than the one before.',
          passSays:    'You found the rhythm. That is the move.',
          failSays:    'Mechanical. Cut the speed in half on the second '
                       'look. Again.',
          onScreenHint: 'EYES · MOUTH · EYES',
          metric:       EyeMetric.lookAwayReturn,
          holdSeconds:  4,
        ),
      ],
    ),

    // ── LESSON 3 ────────────────────────────────────────────────────────
    EyeLesson(
      id: 'the_slow_look_away', number: 3, name: 'THE SLOW LOOK-AWAY',
      oneLine: 'A flicker is a flinch. A drift is an invitation.',
      moves: [
        EyeMove(
          name:        'BREAK SLOW',
          why:         'A flicker is a flinch. A drift is an invitation.',
          demoSays:    'Lock. Now — slowly — I drift. Like I noticed '
                       'something. Like I am coming back.',
          youGoSays:   'Lock. Drift away. Down and to the side. Slow.',
          passSays:    'The drift was the move. You held the line on the '
                       'way out.',
          failSays:    'You flicked. That is a flinch, not a break. Slower.',
          onScreenHint: 'DRIFT AWAY · SLOW',
          metric:       EyeMetric.lookAwayReturn,
          holdSeconds:  5,
        ),
        EyeMove(
          name:        'RETURN HEAVY',
          why:         'You return slower than you left. That tells her '
                       'you decided.',
          demoSays:    'Watch the return. Slower than the break. I hold. '
                       'I do not soften.',
          youGoSays:   'Come back. Slower than you broke. Hold.',
          passSays:    'The return was heavier than the break. That is '
                       'the whole pattern.',
          failSays:    'You snapped back. That kills it. Again.',
          onScreenHint: 'RETURN · HEAVIER',
          metric:       EyeMetric.holdContact,
          holdSeconds:  4,
        ),
      ],
    ),

    // ── LESSON 4 ────────────────────────────────────────────────────────
    EyeLesson(
      id: 'bedroom_eyes', number: 4, name: 'BEDROOM EYES',
      oneLine: 'Half-lidded is dominance. Wide is nervous.',
      moves: [
        EyeMove(
          name:        'DROP THE LIDS',
          why:         'Half-lidded is relaxed dominance. Wide is nervous.',
          demoSays:    'Watch my lids. Halfway. Like I just woke up next '
                       'to you.',
          youGoSays:   'Drop your lids. Halfway. Stay there.',
          passSays:    'Predator-relaxed. That is the look.',
          failSays:    'Eyes too wide. Drop the lids more. Again.',
          onScreenHint: 'DROP THE LIDS · HALFWAY',
          metric:       EyeMetric.softFocus,
          holdSeconds:  6,
        ),
        EyeMove(
          name:        'SMILE UNDER THE LIDS',
          why:         'A small smile under half-lids is the most '
                       'underrated weapon in the catalogue.',
          demoSays:    'Same eyes. Small smile. The smile stays in the '
                       'lips. Eyes do not change.',
          youGoSays:   'Hold the lids. Add the smallest smile. Don\'t '
                       'open the eyes.',
          passSays:    'Mm. The smile under those eyes. That is the move.',
          failSays:    'Smile opened your eyes. Keep the lids down. Again.',
          onScreenHint: 'HOLD SOFT FOCUS · 8 SEC',
          metric:       EyeMetric.softFocus,
          holdSeconds:  8,
        ),
      ],
    ),

    // ── LESSON 5 ────────────────────────────────────────────────────────
    EyeLesson(
      id: 'the_spark', number: 5, name: 'THE SPARK',
      oneLine: 'Less is accident. More is creep. Two is the dose.',
      moves: [
        EyeMove(
          name:        'TWO SECONDS',
          why:         'Less is accident. More is creep. Two is the dose.',
          demoSays:    'Across the room. I lock. Two beats. Smile. I break.',
          youGoSays:   'Lock me. Two seconds. Smile. Break.',
          passSays:    'Two seconds. Exactly the dose.',
          failSays:    'Too short or too long. The window is narrow. Again.',
          onScreenHint: 'LOCK · 2 SEC · SMILE',
          metric:       EyeMetric.holdContact,
          holdSeconds:  2,
        ),
        EyeMove(
          name:        'THREE SPARKS',
          why:         'Three sparks across five minutes is an invitation. '
                       'Anything less is plausible deniability.',
          demoSays:    'Each spark slightly longer. The third — hold it '
                       'until she comes to you.',
          youGoSays:   'Three sparks. Each one longer. The third — hold.',
          passSays:    'The third one stayed open. That was the invitation.',
          failSays:    'Mechanical. Each one needs to feel like the first '
                       'time. Again.',
          onScreenHint: 'THREE SPARKS · HOLD THE LAST',
          metric:       EyeMetric.lookAwayReturn,
          holdSeconds:  8,
        ),
      ],
    ),

    // ── LESSON 6 ────────────────────────────────────────────────────────
    EyeLesson(
      id: 'the_re_engage', number: 6, name: 'THE RE-ENGAGE',
      oneLine: 'The first look is investigation. The second is decision.',
      moves: [
        EyeMove(
          name:        'RETURN STRONGER',
          why:         'First look is investigation. Second is decision.',
          demoSays:    'Look away. Anywhere. I come back to your eyes '
                       'with more weight than I left.',
          youGoSays:   'Look away. Now come back. Heavier.',
          passSays:    'The weight on the return was the move. You loaded it.',
          failSays:    'Same energy twice. That kills it. The second look '
                       'must be heavier. Again.',
          onScreenHint: 'RETURN · HEAVIER',
          metric:       EyeMetric.lookAwayReturn,
          holdSeconds:  6,
        ),
        EyeMove(
          name:        'THE SECOND LOCK',
          why:         'The first look said I see you. The second says '
                       'I checked. Yes, you.',
          demoSays:    'Again. The second look says yes. Hold it.',
          youGoSays:   'Re-engage. You\'ve decided. Hold.',
          passSays:    'You decided on the second one. She felt it.',
          failSays:    'You looked the same way twice. Decide on the '
                       'second one. Again.',
          onScreenHint: 'SECOND LOCK · 5 SEC',
          metric:       EyeMetric.holdContact,
          holdSeconds:  5,
        ),
      ],
    ),

    // ── LESSON 7 ────────────────────────────────────────────────────────
    EyeLesson(
      id: 'the_smolder', number: 7, name: 'THE SMOLDER',
      oneLine: 'Lids low. Tilt. No blink. Stop the room breathing.',
      moves: [
        EyeMove(
          name:        'NO BLINK',
          why:         'Four seconds without a blink at close range is '
                       'when she stops breathing.',
          demoSays:    'Watch. Lids low. Tilt. Eyes locked. No blink. Four.',
          youGoSays:   'Lids low. Slight tilt. Lock. No blink. Four.',
          passSays:    'That tension. That is the smolder.',
          failSays:    'You blinked. The whole point was not blinking. Again.',
          onScreenHint: 'NO BLINK · 4 SEC',
          metric:       EyeMetric.noBlink,
          holdSeconds:  4,
        ),
        EyeMove(
          name:        'HOLD THE TILT',
          why:         'Tilt is what makes smolder land as seduction, not '
                       'aggression. Lose it and it gets ugly.',
          demoSays:    'Lids low. Tilt. Six. The tilt is the difference '
                       'between this and a glare.',
          youGoSays:   'Don\'t soften it. The tilt holds. Six.',
          passSays:    'You did not break the tilt. That is the difference.',
          failSays:    'Head straightened. The angle is the move. Again — '
                       'hold the tilt.',
          onScreenHint: 'HOLD TILT · 6 SEC',
          metric:       EyeMetric.slightTilt,
          holdSeconds:  6,
        ),
      ],
    ),

    // ── LESSON 8 ────────────────────────────────────────────────────────
    EyeLesson(
      id: 'the_power_look', number: 8, name: 'THE POWER LOOK',
      oneLine: 'The look that ends meetings. Not seduction — command.',
      moves: [
        EyeMove(
          name:        'AUTHORITY',
          why:         'This is the look that ends meetings. Not '
                       'seduction. Command.',
          demoSays:    'Eyes wider than rest. Direct. No tilt. No smile. '
                       'I am the room.',
          youGoSays:   'Wide. Direct. No softness. Six.',
          passSays:    'The look that empties a room. You found it.',
          failSays:    'Too friendly. Take the warmth out. Again.',
          onScreenHint: 'WIDE · DIRECT · NO BLINK',
          metric:       EyeMetric.noBlink,
          holdSeconds:  6,
        ),
        EyeMove(
          name:        'HOLD AUTHORITY',
          why:         'Authority that softens is bossy. Authority that '
                       'holds is law.',
          demoSays:    'Eight seconds of the same look. I do not soften.',
          youGoSays:   'Hold. Eight. Don\'t soften when it gets uncomfortable.',
          passSays:    'You held it through the discomfort. Rare.',
          failSays:    'Softened at five. The last three were the move. Again.',
          onScreenHint: 'HOLD AUTHORITY · 8 SEC',
          metric:       EyeMetric.holdContact,
          holdSeconds:  8,
        ),
      ],
    ),

    // ── LESSON 9 ────────────────────────────────────────────────────────
    EyeLesson(
      id: 'the_predator', number: 9, name: 'THE PREDATOR',
      oneLine: 'Animal. That is what attraction actually is.',
      moves: [
        EyeMove(
          name:        'IGNORE THE ROOM',
          why:         'Locking on one in a noisy room tells her you have '
                       'already chosen.',
          demoSays:    'Three other voices around me. I do not glance. '
                       'I am only here.',
          youGoSays:   'Three voices around you. Don\'t glance. Lock.',
          passSays:    'The noise didn\'t move you. That was the move.',
          failSays:    'You glanced. One glance broke the spell. Again.',
          onScreenHint: 'IGNORE THE NOISE · 8 SEC',
          metric:       EyeMetric.holdContact,
          holdSeconds:  8,
        ),
        EyeMove(
          name:        'COMMAND THE EYE CONTACT',
          why:         'An unbroken stare without blinking is animal. '
                       'Animal is what presence actually is.',
          demoSays:    'Longer. I want the room to feel watched before it '
                       'has noticed me.',
          youGoSays:   'Six. No blink. Command the eye contact.',
          passSays:    'Predatory without aggressive. Narrow window. You '
                       'hit it.',
          failSays:    'Too aggressive or too soft. Find the middle. Again.',
          onScreenHint: 'STAY LOCKED · 6 SEC',
          metric:       EyeMetric.noBlink,
          holdSeconds:  6,
        ),
      ],
    ),

    // ── LESSON 10 ───────────────────────────────────────────────────────
    EyeLesson(
      id: 'listening_eyes', number: 10, name: 'LISTENING EYES',
      oneLine: 'Most men cannot do soft. You will.',
      moves: [
        EyeMove(
          name:        'SOFT HOLD',
          why:         'People talk twice as long when you listen with '
                       'your eyes. Most men cannot do soft. You will.',
          demoSays:    'Soften everything. I am about to tell you something '
                       'I have never told anyone.',
          youGoSays:   'Soften your eyes. Hold mine. Like I\'m about to '
                       'confess.',
          passSays:    'That softness is rare in men. You did it.',
          failSays:    'Eyes too sharp. Soften them. Again.',
          onScreenHint: 'SOFT · HOLD · 8 SEC',
          metric:       EyeMetric.holdContact,
          holdSeconds:  8,
        ),
        EyeMove(
          name:        'MICRO-NOD',
          why:         'A tiny nod says I am here. Anything bigger says '
                       'hurry up.',
          demoSays:    'Same soft eyes. Tiny nod. Barely. Hold the eyes.',
          youGoSays:   'Small nod. Smaller than feels right. Hold.',
          passSays:    'Tiny enough to register without interrupting.',
          failSays:    'Nod too big. Half of that. Again.',
          onScreenHint: 'MICRO-NOD · HOLD',
          metric:       EyeMetric.holdContact,
          holdSeconds:  6,
        ),
      ],
    ),

    // ── LESSON 11 ───────────────────────────────────────────────────────
    EyeLesson(
      id: 'tell_me_more', number: 11, name: 'TELL ME MORE',
      oneLine: 'Whoever fills the silence loses the frame.',
      moves: [
        EyeMove(
          name:        'BROW LIFT',
          why:         'Brows up a fraction. Eyes hold. Say nothing. The '
                       'silence does the work.',
          demoSays:    'Watch. Brows up a fraction. Eyes hold. I say nothing.',
          youGoSays:   'Brows up. Hold the eyes. Say nothing.',
          passSays:    'The silence after the brow lift was the whole move.',
          failSays:    'You filled the silence. Lift, hold, wait. Again.',
          onScreenHint: 'BROW UP · HOLD · 6 SEC',
          metric:       EyeMetric.holdContact,
          holdSeconds:  6,
        ),
        EyeMove(
          name:        'HOLD THE SILENCE',
          why:         'Whoever speaks first to fill silence loses the '
                       'frame. So you don\'t speak first.',
          demoSays:    'No blink. Held eyes. The silence is the question.',
          youGoSays:   'Four. No blink. Let the silence work.',
          passSays:    'You didn\'t fill it. That is the muscle being built.',
          failSays:    'You blinked it out. The silence does the work. Again.',
          onScreenHint: 'NO BLINK · HOLD SILENCE',
          metric:       EyeMetric.noBlink,
          holdSeconds:  4,
        ),
      ],
    ),

    // ── LESSON 12 ───────────────────────────────────────────────────────
    EyeLesson(
      id: 'the_final_lock', number: 12, name: 'THE FINAL LOCK',
      oneLine: 'The whole curriculum was for this. Don\'t break first.',
      moves: [
        EyeMove(
          name:        'EYES TO LIPS',
          why:         'Before the kiss — the gaze drops. Two beats. Like '
                       'you are deciding.',
          demoSays:    'Watch the drop. Slow. I look at your mouth like '
                       'I am deciding.',
          youGoSays:   'Eyes on mine. Drop to my mouth. Two beats.',
          passSays:    'That was the pause before the decision.',
          failSays:    'Too fast. The pause is the whole move. Again.',
          onScreenHint: 'EYES → MOUTH · 4 SEC',
          metric:       EyeMetric.lookAwayReturn,
          holdSeconds:  4,
        ),
        EyeMove(
          name:        'DON\'T BREAK FIRST',
          why:         'Whoever looks away first kills the moment. The '
                       'whole curriculum was for this.',
          demoSays:    'Back to my eyes. Hold. I will not break. Will you?',
          youGoSays:   'Come back. Hold. Don\'t break first.',
          passSays:    'You did not break. The next move is hers — or '
                       'yours.',
          failSays:    'You broke first. The whole curriculum was for '
                       'not doing that. Again.',
          onScreenHint: 'HOLD · DON\'T BREAK FIRST',
          metric:       EyeMetric.holdContact,
          holdSeconds:  6,
        ),
      ],
    ),
  ];

  static EyeLesson byId(String id) =>
      all.firstWhere((l) => l.id == id, orElse: () => all.first);
}

abstract final class RizzSyllabus {
  static const all = <Lesson>[
    Lesson(
      id: 'the_held_look', number: 1, name: 'THE HELD LOOK',
      oneLine: 'A held gaze is the first move. Beat the urge to look away.',
      targetLines: [
        TargetLine(
          line: 'I noticed you the moment you walked in.',
          cue:  'said low and slow — and on "you", the voice softens, not lifts',
        ),
        TargetLine(
          line: 'I have been watching you for ten minutes. I was deciding whether you were worth the walk over.',
          cue:  'no apology in the voice; "worth" is the loaded word',
        ),
      ],
    ),
    Lesson(
      id: 'non_question_opener', number: 2, name: 'NON-QUESTION OPENER',
      oneLine: 'Open with an observation, not an interview.',
      targetLines: [
        TargetLine(
          line: 'You read the menu before you sat down. I respect that.',
          cue:  '"respect" lands flat — not flattering, just stated',
        ),
        TargetLine(
          line: 'That book in your hand. He gets better. The first two are him figuring out what to say. The third one is him saying it.',
          cue:  'no hedge, no "I think" — pronouncement, not opinion',
        ),
      ],
    ),
    Lesson(
      id: 'push_and_pull', number: 3, name: 'PUSH AND PULL',
      oneLine: 'Interest plus slight withdrawal. Never both feet in.',
      targetLines: [
        TargetLine(
          line: 'You are the most interesting person at this table. Which, looking around, is not saying much.',
          cue:  'amused on the first sentence; dry on the second — the contrast is the move',
        ),
        TargetLine(
          line: 'I like you more than I should. Anyway — where were we?',
          cue:  'the second sentence retracts the first; "anyway" carries the pivot',
        ),
      ],
    ),
    Lesson(
      id: 'qualification', number: 4, name: 'QUALIFICATION',
      oneLine: 'Make them qualify themselves to you.',
      targetLines: [
        TargetLine(
          line: 'Most people who say they know wine just mean they know what is expensive. Which are you?',
          cue:  'the question at the end carries the trap — slow on "which are you"',
        ),
        TargetLine(
          line: 'Tell me something about you that would surprise me. And nothing your mother would tell me.',
          cue:  'the second sentence is the wall — said flat, not warmly',
        ),
      ],
    ),
    Lesson(
      id: 'amused_mastery', number: 5, name: 'AMUSED MASTERY',
      oneLine: 'Laugh at the attack. Never defend.',
      targetLines: [
        TargetLine(
          line: 'Yes. Anyway — you were telling me about your year in Lisbon.',
          cue:  '"yes" is dry, half-amused; the pivot to her story is the move',
        ),
        TargetLine(
          line: 'You are right. I do think a lot of myself. And yet — here you are.',
          cue:  'the third sentence is the kill — slow on "here you are"',
        ),
      ],
    ),
    Lesson(
      id: 'the_takeaway', number: 6, name: 'THE TAKEAWAY',
      oneLine: 'Losing interest is the move. Let them close the distance.',
      targetLines: [
        TargetLine(
          line: 'You are somewhere else tonight. It is fine. Have a good one.',
          cue:  'no sting in the voice — pleasant, decided, leaving',
        ),
        TargetLine(
          line: 'This was good. I have somewhere to be. I am taking your number — text me when you get home.',
          cue:  'four sentences, four decisions; "text me" lands as instruction, not request',
        ),
      ],
    ),
    Lesson(
      id: 'the_calibrated_question', number: 7, name: 'THE CALIBRATED QUESTION',
      oneLine: 'Ask "how" or "what". Hand the problem back.',
      targetLines: [
        TargetLine(
          line: 'How am I supposed to leave you alone after that?',
          cue:  '"after that" is the loaded close — slow it down',
        ),
        TargetLine(
          line: 'What would have to be true for you to say yes?',
          cue:  'said evenly — not begging, framing',
        ),
      ],
    ),
    Lesson(
      id: 'the_label', number: 8, name: 'THE LABEL',
      oneLine: 'Name the emotion in the room before she has to.',
      targetLines: [
        TargetLine(
          line: 'It sounds like you have already decided this is going somewhere.',
          cue:  'said as observation, not accusation — drop the pitch on "somewhere"',
        ),
        TargetLine(
          line: 'You feel safer when you keep the conversation light. I respect it. I am also not going to play along.',
          cue:  'three sentences — the third one closes the door on the safety',
        ),
      ],
    ),
    Lesson(
      id: 'future_pacing', number: 9, name: 'FUTURE-PACING',
      oneLine: 'Describe the future as if it is already decided.',
      targetLines: [
        TargetLine(
          line: 'There is a bar near my place with a piano in the back. Tuesday is the night the regulars stay home.',
          cue:  'described, not invited — present tense; no question at the end',
        ),
        TargetLine(
          line: 'Wear something you cannot move in. The place I am taking you is not the kind of place you leave early.',
          cue:  '"cannot move in" lands soft; "not the kind of place" lands flat',
        ),
      ],
    ),
    Lesson(
      id: 'the_mirror', number: 10, name: 'THE MIRROR',
      oneLine: 'Repeat her last three words. She keeps talking.',
      targetLines: [
        TargetLine(
          line: '…the broken jukebox?',
          cue:  'small upward lift at the end — the only place you ever lift',
        ),
        TargetLine(
          line: '…worth the walk over?',
          cue:  'a held mirror — wait for her to expand',
        ),
      ],
    ),
    Lesson(
      id: 'cocky_caring', number: 11, name: 'COCKY / CARING',
      oneLine: 'Sharp. Then warm. Then sharp again.',
      targetLines: [
        TargetLine(
          line: 'You are unbelievably difficult tonight. I like that more than I should.',
          cue:  'two sentences — the second softens the first by half a degree, not a whole',
        ),
        TargetLine(
          line: 'Most women at this bar are doing an impression of someone interesting. You are not. Which is a problem for me.',
          cue:  'the third sentence is the closer — the "problem" is the compliment',
        ),
      ],
    ),
    Lesson(
      id: 'the_synthesis', number: 12, name: 'THE SYNTHESIS',
      oneLine: 'Combine all eleven. Walk into a room and own it in one minute.',
      targetLines: [
        TargetLine(
          line: 'I noticed you. I have been watching for ten minutes. I am deciding whether you are worth the walk.',
          cue:  'hold + open + qualify, all in three sentences — drop pitch on "worth"',
        ),
        TargetLine(
          line: 'I like you more than I should. Anyway — there is a place I am taking you Tuesday. Wear something you cannot move in.',
          cue:  'push-pull + future-pace + close — the whole curriculum compressed',
        ),
      ],
    ),
  ];

  static Lesson byId(String id) =>
      all.firstWhere((l) => l.id == id, orElse: () => all.first);
}
