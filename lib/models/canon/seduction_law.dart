/// The Rizz tab reference book — sits at the bottom of the page as the
/// "THE LAWS" section. Robert Greene's archetypes + the 24 Laws of
/// Influence, compressed into plain English so users actually read them.
///
/// Three sections:
///   1. THE ARCHETYPES  — Greene's 9 charisma archetypes ("which one are you?")
///   2. THE 24 LAWS     — grouped into four phases (choosing → temptation
///                        → pain & pleasure → the final move)
///   3. THE FRAME LAWS  — modern, derived from social-influence and
///                        behavioural charisma research
class LawSection {
  final String id;
  final String title;
  final String subtitle;
  final String intro;
  final List<LawEntry> entries;

  const LawSection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.intro,
    required this.entries,
  });
}

class LawEntry {
  final String name;
  final String summary;        // plain-English one-liner
  final String example;        // worked example or quote
  final String? lessonId;      // optional jump-to-lesson

  const LawEntry({
    required this.name,
    required this.summary,
    required this.example,
    this.lessonId,
  });
}

abstract final class SeductionLaws {
  static const archetypes = LawSection(
    id: 'archetypes',
    title: 'THE ARCHETYPES',
    subtitle: 'Greene\'s nine — which one are you?',
    intro:
        'Robert Greene mapped nine archetypes of the magnetic personality '
        '— each is a different door into the same room. You will recognise '
        'yourself in two or three. Lean into the one that is already yours. '
        'Borrow tools from the others. Never imitate a type you are not.',
    entries: [
      LawEntry(
        name: 'THE SIREN',
        summary: 'Pure presence. Pure command. The room slows around them.',
        example: 'Marilyn. Cleopatra. Nothing said quickly. Everything '
                 'said with the body first.',
      ),
      LawEntry(
        name: 'THE RAKE',
        summary: 'Open intent. Refuses to apologise for wanting.',
        example: 'Casanova. The figure whose intent is so undisguised it '
                 'reads as honesty, not threat.',
      ),
      LawEntry(
        name: 'THE IDEAL LISTENER',
        summary: 'Sees in the other the thing no one else has noticed.',
        example: 'The friend who, in the first hour, names the part of '
                 'them they have been hiding from everyone else.',
      ),
      LawEntry(
        name: 'THE DANDY',
        summary: 'Plays with gender, taste, expectation. Always elsewhere.',
        example: 'Bowie. Oscar Wilde. The one who refuses every category '
                 'and is therefore unforgettable.',
      ),
      LawEntry(
        name: 'THE NATURAL',
        summary: 'Childlike, unselfconscious, plays without strategy.',
        example: 'The man who does not seem to be trying — and is '
                 'therefore the only one who lands.',
      ),
      LawEntry(
        name: 'THE COQUETTE',
        summary: 'Hot then cold. Withholds attention as currency.',
        example: 'The text that arrives three days late but lands like '
                 'a bullet because it is exactly the right line.',
      ),
      LawEntry(
        name: 'THE CHARMER',
        summary: 'Pure flattery, calibrated. Makes the room feel chosen.',
        example: 'The diplomat. The host. The man who, in twenty minutes, '
                 'has made every person in the room feel like the only one present.',
      ),
      LawEntry(
        name: 'THE CHARISMATIC',
        summary: 'Burning purpose. People follow him into rooms.',
        example: 'Steve Jobs. Malcolm X. The man whose conviction makes '
                 'the air thicker.',
      ),
      LawEntry(
        name: 'THE STAR',
        summary: 'Larger than life. Distant. Projects everyone\'s fantasy.',
        example: 'James Dean. The figure on the screen — close enough '
                 'to want, too far to hold.',
      ),
    ],
  );

  // The 24 Laws, plain-English, grouped into the four phases Greene used.
  static const choosing = LawSection(
    id: 'choosing',
    title: 'CHOOSING WHO',
    subtitle: 'Laws 1–6 · who, and why',
    intro:
        'Before the first word, the magnetic has chosen. Not anyone. The '
        'right one. The one whose specific lack you can fill. The wrong '
        'reader wastes the playbook.',
    entries: [
      LawEntry(
        name: '1 · CHOOSE THE RIGHT MOMENT',
        summary: 'Pick someone who lacks what you carry. Not everyone.',
        example: 'A distracted stranger in the middle of their own night is '
                 'the wrong moment. A curious one who tells you they are '
                 'unimpressed is the right one.',
      ),
      LawEntry(
        name: '2 · CREATE A FALSE SENSE OF SECURITY',
        summary: 'Open friendly. Disarming. Threat-free. Then escalate.',
        example: 'Land the laugh in the first two minutes. The defences '
                 'come down. The frame goes up.',
        lessonId: 'approach_without_permission',
      ),
      LawEntry(
        name: '3 · SEND MIXED SIGNALS',
        summary: 'Be two things at once. Hot and cold. Hard and warm.',
        example: 'The cocky operator with one tender admission. They will '
                 'think about that admission for a week.',
        lessonId: 'cocky_caring',
      ),
      LawEntry(
        name: '4 · APPEAR TO BE AN OBJECT OF INTEREST',
        summary: 'Be visibly wanted by others. Scarcity by demonstration.',
        example: 'Arrive with friends who clearly like you. The pre-selection '
                 'does half the work before you speak.',
      ),
      LawEntry(
        name: '5 · CREATE A NEED',
        summary: 'Make them aware of a curiosity they have been ignoring.',
        example: 'Most people are afraid to actually say what they want. '
                 'You are not. That is the need.',
      ),
      LawEntry(
        name: '6 · MASTER THE ART OF INSINUATION',
        summary: 'Imply. Suggest. Never state directly.',
        example: '"There is one thing I noticed about you in the first '
                 'ten seconds." (do not finish the sentence)',
        lessonId: 'the_bait',
      ),
    ],
  );

  static const temptation = LawSection(
    id: 'temptation',
    title: 'CREATING THE TEMPTATION',
    subtitle: 'Laws 7–12 · the slow burn',
    intro:
        'The hook is set. Now the slow build. Make them feel that something '
        'inevitable is happening — but make them not quite sure when, or '
        'where, or how. Mystery is the engine.',
    entries: [
      LawEntry(
        name: '7 · ENTER THEIR SPIRIT',
        summary: 'Match their register first. Mirror their tempo, then steer.',
        example: 'Quiet room, you arrive quiet. Three minutes later you '
                 'raise the temperature by half a degree. They follow.',
        lessonId: 'read_the_energy',
      ),
      LawEntry(
        name: '8 · CREATE TEMPTATION',
        summary: 'Be the door they have been wondering whether to walk through.',
        example: 'Talk about the thing they have been curious about and '
                 'never had permission to say out loud.',
      ),
      LawEntry(
        name: '9 · KEEP THEM IN SUSPENSE',
        summary: 'Be unpredictable. Pattern-break before they get bored.',
        example: 'Three sharp lines. Then a soft one. Then a silence. '
                 'They cannot guess what is next. They do not leave.',
      ),
      LawEntry(
        name: '10 · USE THE DEMONIC POWER OF WORDS',
        summary: 'Language is the only weapon. Use it precisely.',
        example: 'Pick the loaded word. Name the thing they have not named '
                 'about themselves yet. The room changes.',
        lessonId: 'specificity',
      ),
      LawEntry(
        name: '11 · PAY ATTENTION TO DETAIL',
        summary: 'Notice the small thing nobody else has noticed.',
        example: '"You read the menu before you sat down. I respect that."',
        lessonId: 'non_question_opener',
      ),
      LawEntry(
        name: '12 · POETICISE YOUR PRESENCE',
        summary: 'Be slightly mythic. A small mystery about you, always.',
        example: 'Never explain where you go on Sundays. Never explain '
                 'why you stopped doing the thing they asked about.',
      ),
    ],
  );

  static const painPleasure = LawSection(
    id: 'pain_pleasure',
    title: 'PAIN AND PLEASURE',
    subtitle: 'Laws 13–18 · the alternation',
    intro:
        'Pleasure alone is dull. Pain alone is wounding. The magnetic alternates '
        '— giving, then withholding, then giving more than expected. They '
        'follow the rhythm without realising they are being read.',
    entries: [
      LawEntry(
        name: '13 · DISARM THROUGH STRATEGIC WEAKNESS',
        summary: 'A small, calibrated admission is more potent than ten lies.',
        example: '"I almost didn\'t come out tonight. I\'m glad I did." '
                 'Said once, only.',
      ),
      LawEntry(
        name: '14 · CONFUSE DESIRE AND REALITY',
        summary: 'Paint the future so well it feels like the present.',
        example: 'Describe the date as if it is already happening, in '
                 'present tense. She steps into the picture.',
        lessonId: 'future_pacing',
      ),
      LawEntry(
        name: '15 · CONTROL THE FRAME',
        summary: 'Pull them out of their usual social weather.',
        example: 'Take them to the bar they have never heard of. Outside '
                 'their frame, you are the only frame.',
      ),
      LawEntry(
        name: '16 · PROVE YOURSELF',
        summary: 'Do the small thing they did not ask for. Once.',
        example: 'Remember the drink they said they liked. Order it without '
                 'asking, two weeks later. Devastating.',
        lessonId: 'callback',
      ),
      LawEntry(
        name: '17 · EFFECT A REGRESSION',
        summary: 'Make them feel younger. Less self-conscious. Lighter.',
        example: 'Laugh at the small absurd thing. They remember the '
                 'last time someone made them laugh that hard.',
      ),
      LawEntry(
        name: '18 · STIR PLEASURE AND PAIN',
        summary: 'Compliment + tease + compliment. Hot, cold, hot.',
        example: '"You are the smartest person at this table. Which, '
                 'looking around, is not saying very much. But you, '
                 'separately — I am interested."',
        lessonId: 'push_and_pull',
      ),
    ],
  );

  static const finalMove = LawSection(
    id: 'final_move',
    title: 'THE FINAL MOVE',
    subtitle: 'Laws 19–24 · the close',
    intro:
        'The build has worked. They are leaning in. Now the most dangerous '
        'part — because most people ruin it here. The final move is light, '
        'decisive, and short. Never long. Never asking. Never apologising.',
    entries: [
      LawEntry(
        name: '19 · USE SPIRITUAL LURES',
        summary: 'Talk about the larger thing — meaning, art, beauty.',
        example: 'After the small talk has done its work, the conversation '
                 'about what actually matters. She will remember it.',
      ),
      LawEntry(
        name: '20 · MIX PLEASURE WITH PAIN',
        summary: 'A small jealousy, well-timed, doubles interest.',
        example: 'Mention, casually, the other person whose attention you '
                 'have. Then never mention them again.',
      ),
      LawEntry(
        name: '21 · GIVE THEM SPACE TO FALL',
        summary: 'Step back. Let them come the last metre.',
        example: 'Do not chase the close. Let the silence between you '
                 'become unbearable. Then they close it.',
        lessonId: 'walk_away',
      ),
      LawEntry(
        name: '22 · USE PHYSICAL PRESENCE',
        summary: 'Once the frame is set — your presence. Slow. Light. Decisive.',
        example: 'The lean-in that opens the next beat in the conversation. '
                 'Said nothing. Meant everything.',
      ),
      LawEntry(
        name: '23 · MASTER THE ART OF THE BOLD MOVE',
        summary: 'When the moment arrives, do not hesitate. Move.',
        example: 'Read the moment. Step in. No question. No look. '
                 'The hesitation kills it.',
      ),
      LawEntry(
        name: '24 · BEWARE THE AFTEREFFECTS',
        summary: 'After the win, do not collapse the frame. Stay sharp.',
        example: 'The text that gives away everything in the morning '
                 'undoes the work of three weeks. Stay the version they met.',
        lessonId: 'the_takeaway',
      ),
    ],
  );

  // Modern derivations — frame laws from behavioural research, used in
  // the lessons even though they are not in Greene.
  static const frameLaws = LawSection(
    id: 'frame_laws',
    title: 'THE FRAME LAWS',
    subtitle: 'modern · derived from behavioural research',
    intro:
        'Greene wrote in the 90s. The frame laws are what the last twenty '
        'years of dating science and behavioural charisma research have '
        'added. They are not in the original 24 — but they belong here.',
    entries: [
      LawEntry(
        name: 'SCARCITY',
        summary: 'Be wanted by others, visibly. Be slightly hard to schedule.',
        example: 'Tuesday eight is the only night I have free this week — '
                 'that is the line. Not "whenever works for you".',
      ),
      LawEntry(
        name: 'QUALIFICATION',
        summary: 'Make them sell themselves to you. Reverse the audition.',
        example: '"Pick the next bottle for us. If it is good I will '
                 'tell my friends I met someone interesting tonight."',
        lessonId: 'qualification',
      ),
      LawEntry(
        name: 'AMUSED MASTERY',
        summary: 'Laugh at attacks. Never defend. Smile, agree, move on.',
        example: '"You think a lot of yourself." "Yes." (small smile, '
                 'change the subject)',
        lessonId: 'amused_mastery',
      ),
      LawEntry(
        name: 'THE TAKEAWAY',
        summary: 'Leave first. On purpose. Always.',
        example: '"This was good. I have somewhere to be. Text me when '
                 'you get home." (leave, do not look back)',
        lessonId: 'walk_away',
      ),
    ],
  );

  static const all = [
    archetypes,
    choosing,
    temptation,
    painPleasure,
    finalMove,
    frameLaws,
  ];
}
