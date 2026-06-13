import 'presence_lesson.dart';

/// PRESENCE — Lucien's seductive-voice masterclass.
///
/// Ten named VOICE moves, taught deadly and tight: ONE punch of POWER
/// (why this does something to her), ONE line of HOW (exactly how to
/// execute it), then he hands the user a charged line to deliver. No
/// slow-motion, no rambling — every lesson is built to land like a
/// viral clip.
///
/// Flow: POWER → HOW → deliver the line (graded) → correction
/// ("you did X, fix it, Again.") → deliver again → score.
///
/// Grounded in real research: lower male pitch is rated more
/// attractive/dominant (Puts); rising "uptalk" reads as low-confidence
/// while downward inflection reads as certainty; a pause builds
/// anticipation; and — HONEST — "slow = attractive" is NOT supported,
/// so we coach "kill the nervous rush", never "talk slow", and the WPM
/// bands reflect that.
abstract final class PresenceSyllabus {
  static const all = <PresenceLesson>[
    // ── LESSON 1 — DROP THE PITCH ───────────────────────────────────
    PresenceLesson(
      id: 'drop_the_pitch',
      number: 1,
      name: 'DROP THE PITCH',
      oneLine: 'Speak from the chest, not the throat.',
      objective: 'Lower your voice into your chest. Let it sit there.',
      story: [
        'A low voice from the chest is read as more attractive and more '
            'in control. Every man does it on instinct around a woman he '
            'wants — you\'ll do it on purpose.',
      ],
      demo: [
        'How: drop your voice into your chest, not your throat. Lower, '
            'not louder. Let it settle there.',
      ],
      instruct: [
        'Low, from the chest, hold my eyes: "I wasn\'t going to come '
            'over. Then I changed my mind."',
      ],
      targetLine: 'I wasn\'t going to come over. Then I changed my mind.',
      deliveryCue: 'Low. From the chest. No rush.',
      drillSeconds: 11,
      weights: {
        PresenceDimension.voiceAuthority: 0.40,
        PresenceDimension.pace:           0.10,
        PresenceDimension.confidence:     0.20,
        PresenceDimension.eyeContact:     0.15,
        PresenceDimension.warmth:         0.00,
        PresenceDimension.tension:        0.15,
      },
      targetWpmLow: 95,
      targetWpmHigh: 150,
      warmthExpected: false,
      correction: [
        'That came from your throat — thin, reaching up at the end.',
        'Drop it into your chest. The weight is what she trusts. Again.',
      ],
    ),

    // ── LESSON 2 — END IT DOWN ──────────────────────────────────────
    PresenceLesson(
      id: 'end_it_down',
      number: 2,
      name: 'END IT DOWN',
      oneLine: 'Land every sentence going down, never up.',
      objective: 'End the line with the pitch falling. Kill the uptalk.',
      story: [
        'A sentence that lifts at the end sounds like you\'re asking '
            'permission to exist. Land it going DOWN and you sound '
            'certain — and certainty is the magnetic thing.',
      ],
      demo: [
        'How: drop your pitch on the last word. No lift. Land it like a '
            'door closing.',
      ],
      instruct: [
        'Land it down, hold my eyes: "You\'re trouble. I knew it the '
            'second you walked in."',
      ],
      targetLine: 'You\'re trouble. I knew it the second you walked in.',
      deliveryCue: 'Drop the pitch on the last word. No lift.',
      drillSeconds: 11,
      weights: {
        PresenceDimension.voiceAuthority: 0.25,
        PresenceDimension.pace:           0.10,
        PresenceDimension.confidence:     0.40,
        PresenceDimension.eyeContact:     0.15,
        PresenceDimension.warmth:         0.00,
        PresenceDimension.tension:        0.10,
      },
      targetWpmLow: 100,
      targetWpmHigh: 160,
      warmthExpected: false,
      correction: [
        'Your voice lifted at the end — you turned a statement into a '
            'question and handed her the power.',
        'Drop the ending. Own it. Again.',
      ],
    ),

    // ── LESSON 3 — THE PAUSE ────────────────────────────────────────
    PresenceLesson(
      id: 'the_pause',
      number: 3,
      name: 'THE PAUSE',
      oneLine: 'Say it. Then stop. Let the silence carry it.',
      objective: 'Deliver the line, then hold a full beat of silence.',
      story: [
        'The pause is where all the tension lives. Say the line, then '
            'stop — and the silence does more work than the words. Most '
            'men are too scared to let it sit.',
      ],
      demo: [
        'How: say the first half, hold a full second of silence on her '
            'eyes, then the rest. Don\'t fill the gap.',
      ],
      instruct: [
        'Drop it, then a full beat of silence: "I like you. ... That\'s '
            'inconvenient."',
      ],
      targetLine: 'I like you. That\'s inconvenient.',
      deliveryCue: 'Full beat of silence in the middle. Don\'t rush it.',
      drillSeconds: 11,
      weights: {
        PresenceDimension.voiceAuthority: 0.20,
        PresenceDimension.pace:           0.30,
        PresenceDimension.confidence:     0.25,
        PresenceDimension.eyeContact:     0.15,
        PresenceDimension.warmth:         0.00,
        PresenceDimension.tension:        0.10,
      },
      targetWpmLow: 70,
      targetWpmHigh: 130,
      warmthExpected: false,
      correction: [
        'You rushed straight through — the words tripped over each '
            'other to get it over with.',
        'Hold the pause longer than feels comfortable. Again.',
      ],
    ),

    // ── LESSON 4 — KILL THE RUSH ────────────────────────────────────
    PresenceLesson(
      id: 'kill_the_rush',
      number: 4,
      name: 'KILL THE RUSH',
      oneLine: 'Lose the nervous speed. You\'ve got nowhere to be.',
      objective: 'Even, controlled pace. No sprinting through the words.',
      story: [
        'The nervous man sprints through his words to get them over '
            'with — the speed itself is the confession. You\'re never in '
            'a hurry, because where exactly is she going?',
      ],
      demo: [
        'How: even it out. Not slow — just unrushed. Each word gets the '
            'room it needs.',
      ],
      instruct: [
        'Steady, unhurried, hold my eyes: "Slow down. We\'ve got time."',
      ],
      targetLine: 'Slow down. We\'ve got time.',
      deliveryCue: 'Steady and unhurried. Not slow — just no rush.',
      drillSeconds: 10,
      weights: {
        PresenceDimension.voiceAuthority: 0.25,
        PresenceDimension.pace:           0.40,
        PresenceDimension.confidence:     0.15,
        PresenceDimension.eyeContact:     0.10,
        PresenceDimension.warmth:         0.00,
        PresenceDimension.tension:        0.10,
      },
      targetWpmLow: 110,
      targetWpmHigh: 165,
      warmthExpected: false,
      correction: [
        'You sprinted — she heard the nerves before she heard the line.',
        'Kill the rush. You\'re running from nothing. Again.',
      ],
    ),

    // ── LESSON 5 — THE WHISPER ──────────────────────────────────────
    PresenceLesson(
      id: 'the_whisper',
      number: 5,
      name: 'THE WHISPER',
      oneLine: 'Drop the volume. Make the room lean in to hear it.',
      objective: 'Lower the volume on the key line. Pull her in.',
      story: [
        'When the whole room gets louder, you get quieter — and she has '
            'to lean in to catch it. The man who drops his voice makes '
            'the room come to him.',
      ],
      demo: [
        'How: pull the volume back on the line that matters. Intimate. '
            'Just for her.',
      ],
      instruct: [
        'Drop the volume, pull her in: "Come here. I want to tell you '
            'something."',
      ],
      targetLine: 'Come here. I want to tell you something.',
      deliveryCue: 'Quieter than feels natural. Make them come closer.',
      drillSeconds: 10,
      weights: {
        PresenceDimension.voiceAuthority: 0.35,
        PresenceDimension.pace:           0.15,
        PresenceDimension.confidence:     0.15,
        PresenceDimension.eyeContact:     0.15,
        PresenceDimension.warmth:         0.10,
        PresenceDimension.tension:        0.10,
      },
      targetWpmLow: 90,
      targetWpmHigh: 145,
      warmthExpected: true,
      correction: [
        'You said it at full volume, like an announcement — nothing to '
            'lean toward.',
        'Quieter. Make them close the distance for you. Again.',
      ],
    ),

    // ── LESSON 6 — ONE WORD ─────────────────────────────────────────
    PresenceLesson(
      id: 'one_word',
      number: 6,
      name: 'ONE WORD',
      oneLine: 'The power answer. Say less. Mean more.',
      objective: 'Answer with one calm word. Resist the urge to explain.',
      story: [
        'She asks if you\'re always this confident. The needy man writes '
            'a paragraph defending himself. You give her one word and '
            'let it stand — restraint is the loudest flex there is.',
      ],
      demo: [
        'How: one calm word. Then stop. No nervous laugh, no '
            'explanation trailing off the end.',
      ],
      instruct: [
        'She asked if you\'re always this sure of yourself. One word, '
            'then silence: "Yeah."',
      ],
      targetLine: 'Yeah.',
      deliveryCue: 'One word. Calm. Then silence. Don\'t add to it.',
      drillSeconds: 9,
      weights: {
        PresenceDimension.voiceAuthority: 0.30,
        PresenceDimension.pace:           0.15,
        PresenceDimension.confidence:     0.35,
        PresenceDimension.eyeContact:     0.15,
        PresenceDimension.warmth:         0.00,
        PresenceDimension.tension:        0.05,
      },
      targetWpmLow: 0,
      targetWpmHigh: 200,
      warmthExpected: false,
      correction: [
        'You answered, then kept talking — you buried the strong word '
            'under five nervous ones.',
        'Just the word. Add nothing. Again.',
      ],
    ),

    // ── LESSON 7 — THE SLOW BURN ────────────────────────────────────
    PresenceLesson(
      id: 'the_slow_burn',
      number: 7,
      name: 'THE SLOW BURN',
      oneLine: 'Slow down on the charged word. Let it land.',
      objective: 'Stretch the key word. Let the important one breathe.',
      story: [
        'Every line has one word that carries the charge. Slow down on '
            'it and it lands like a held breath — that\'s the difference '
            'between reading a line and meaning it.',
      ],
      demo: [
        'How: find the charged word and lean on it. Slow it down. Let '
            'it land before you move on.',
      ],
      instruct: [
        'Lean slow on the last word, hold my eyes: "I had a feeling '
            'about you. And I\'m usually right."',
      ],
      targetLine: 'I had a feeling about you. And I\'m usually right.',
      deliveryCue: 'Lean on "right". Slow it. Let it land.',
      drillSeconds: 11,
      weights: {
        PresenceDimension.voiceAuthority: 0.30,
        PresenceDimension.pace:           0.25,
        PresenceDimension.confidence:     0.20,
        PresenceDimension.eyeContact:     0.15,
        PresenceDimension.warmth:         0.00,
        PresenceDimension.tension:        0.10,
      },
      targetWpmLow: 90,
      targetWpmHigh: 150,
      warmthExpected: false,
      correction: [
        'You said it all at one flat speed — the word that mattered got '
            'lost in the traffic.',
        'Lean on it like you believe it. Again.',
      ],
    ),

    // ── LESSON 8 — THE DRAWL ────────────────────────────────────────
    PresenceLesson(
      id: 'the_drawl',
      number: 8,
      name: 'THE DRAWL',
      oneLine: 'The unbothered voice. Relaxed. Nowhere to be.',
      objective: 'Loose, relaxed delivery. Zero urgency in the voice.',
      story: [
        'Tension in the voice is the loudest tell there is. The '
            'unbothered man drawls — loose, relaxed, like the world can '
            'wait. "I don\'t need anything from you" is the most '
            'attractive thing a voice can say.',
      ],
      demo: [
        'How: loosen your jaw, drop the urgency, speak like you\'ve got '
            'nowhere to be.',
      ],
      instruct: [
        'Loose, slow jaw, hold my eyes: "I\'m not in a rush. I never '
            'am."',
      ],
      targetLine: 'I\'m not in a rush. I never am.',
      deliveryCue: 'Loose and relaxed. No tension. No urgency.',
      drillSeconds: 10,
      weights: {
        PresenceDimension.voiceAuthority: 0.35,
        PresenceDimension.pace:           0.20,
        PresenceDimension.confidence:     0.15,
        PresenceDimension.eyeContact:     0.10,
        PresenceDimension.warmth:         0.05,
        PresenceDimension.tension:        0.15,
      },
      targetWpmLow: 85,
      targetWpmHigh: 145,
      warmthExpected: false,
      correction: [
        'Your voice was tight and clipped — the tension leaked out of '
            'every word.',
        'Loosen it. The unbothered man always wins. Again.',
      ],
    ),

    // ── LESSON 9 — THE WARM EDGE ────────────────────────────────────
    PresenceLesson(
      id: 'the_warm_edge',
      number: 9,
      name: 'THE WARM EDGE',
      oneLine: 'Let the smile into your voice — but keep the edge.',
      objective: 'Warmth in the voice without losing the low ground.',
      story: [
        'Pure ice gets boring — a wall is easy to walk away from. Warm '
            'on top, low and certain underneath: that mix is the most '
            'magnetic register a man has. She feels welcome AND she '
            'feels the pull.',
      ],
      demo: [
        'How: let a real smile into your voice, but keep it low '
            'underneath. Both at once.',
      ],
      instruct: [
        'Smile in it, low underneath, hold my eyes: "You make me laugh. '
            'I didn\'t expect that."',
      ],
      targetLine: 'You make me laugh. I didn\'t expect that.',
      deliveryCue: 'Smile in the voice. Low underneath. Both at once.',
      drillSeconds: 11,
      weights: {
        PresenceDimension.voiceAuthority: 0.20,
        PresenceDimension.pace:           0.15,
        PresenceDimension.confidence:     0.15,
        PresenceDimension.eyeContact:     0.15,
        PresenceDimension.warmth:         0.30,
        PresenceDimension.tension:        0.05,
      },
      targetWpmLow: 95,
      targetWpmHigh: 155,
      warmthExpected: true,
      correction: [
        'Either it was flat and cold, or the smile pushed your voice up '
            'high and you lost the ground.',
        'Warm on top, low underneath. Both. Again.',
      ],
    ),

    // ── LESSON 10 — KILL THE FILLERS ────────────────────────────────
    PresenceLesson(
      id: 'kill_the_fillers',
      number: 10,
      name: 'KILL THE FILLERS',
      oneLine: 'Replace every "um" and "like" with silence.',
      objective: 'No fillers. Where one wants to come, put silence.',
      story: [
        'Every "um" and "like" is a tiny white flag — it says you\'re '
            'not sure you\'re allowed to be talking. A man comfortable '
            'with silence between his words sounds comfortable in his '
            'own skin.',
      ],
      demo: [
        'How: where an "um" wants out, put silence instead, and hold '
            'her eyes through the gap.',
      ],
      instruct: [
        'Zero fillers — silence in the gaps, hold my eyes: "I think you '
            'already know why I came over."',
      ],
      targetLine: 'I think you already know why I came over.',
      deliveryCue: 'Zero fillers. Silence in the gaps, not "um".',
      drillSeconds: 11,
      weights: {
        PresenceDimension.voiceAuthority: 0.20,
        PresenceDimension.pace:           0.15,
        PresenceDimension.confidence:     0.40,
        PresenceDimension.eyeContact:     0.15,
        PresenceDimension.warmth:         0.00,
        PresenceDimension.tension:        0.10,
      },
      targetWpmLow: 90,
      targetWpmHigh: 150,
      warmthExpected: false,
      correction: [
        'The fillers crept in — every "um" undid the authority the '
            'words were building.',
        'Silence beats filler. Let the gaps sit clean. Again.',
      ],
    ),
  ];

  static PresenceLesson byId(String id) =>
      all.firstWhere((l) => l.id == id, orElse: () => all.first);
}
