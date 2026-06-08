/// THE ARSENAL — 125 hand-picked rizz lines for 2026 Gen-Z men.
///
/// Source pool — what makes a line into the arsenal:
///   · Verified-pull screenshots from r/Hinge, r/Tinder, r/Bumble
///     match-success threads (2024-2026)
///   · TikTok rizz competition top-comment lines (>50k likes)
///   · The Hinge "what works" annual report — specific > generic,
///     observation > question, future-pacing > small-talk
///   · IG DM screenshot threads where the OP got the date
///
/// SELECTION RULES — the no-trash test:
///   1. ≤ 14 words. Phone fatigue.
///   2. THE SCREENSHOT TEST — would a 22-year-old save it to her
///      group chat? If she'd just react with "ok", it's cut.
///   3. NO 2014 PUA — no negs, no "you'd be cute if", no
///      "challenge me" energy. Reads as creepy now.
///   4. NO PHYSICAL COMPLIMENTS without context. "u r hot" is
///      not rizz, it's noise.
///   5. SPECIFICITY > GENERIC. "Your aura is unforgivable" beats
///      "you're pretty" every time.
///   6. MUST CARRY A MOVE — every line teaches a named technique
///      (frame check, push-pull, misinterpretation, archetype read,
///      compressed cinema, etc) so users learn the play, not just
///      the words.
///
/// MOVES VOCAB (the small-caps tag on each line):
///   · SELF-AWARE OPEN          — meta, breaks the 4th wall
///   · ARCHETYPE READ           — names a "type" she'll recognize
///   · COMPRESSED CINEMA        — paints a whole relationship in 1 line
///   · INTIMATE PRESUMPTION     — acts like you're already close
///   · INTIMATE PROBE           — asks an unguardedly-real question
///   · INAPPROPRIATE COMPLIMENT — too-specific to be generic
///   · VULNERABLE FLEX          — admits a "weakness" that's a flex
///   · DOMESTIC PROJECTION      — pictures a future together
///   · FRAME CHECK              — assumes the outcome; high agency
///   · PUSH-PULL                — playful disqualifier that hooks
///   · MISINTERPRETATION        — willfully misreads her flirty
///   · HIGH-AGENCY              — secure, scarce, decisive
///   · DISQUALIFIER             — light "i'm not for you" reverse
///   · BACKHANDED               — compliment-with-a-twist
///   · META-FLIRT               — flirts about flirting
///   · DATE PROPOSAL            — moves it offline
///   · PROXIMITY                — hints at meeting in real life
///   · REFRAME                  — flips her energy to your advantage
///   · TEASE                    — playful jab, light needle
class RizzLine {
  final String text;
  final String tag;
  const RizzLine(this.text, this.tag);
}

class RizzCategory {
  final String label;
  final String slug;
  final String headline;
  final String hint;
  final List<RizzLine> lines;
  const RizzCategory({
    required this.label,
    required this.slug,
    required this.headline,
    required this.hint,
    required this.lines,
  });
}

abstract final class RizzArsenal {
  static const categories = <RizzCategory>[
    // ── OPENERS ─────────────────────────────────────────────────────────
    RizzCategory(
      label:    'OPENERS',
      slug:     'openers',
      headline: 'The arsenal.',
      hint:     'First message. The one that decides if she replies.',
      lines: [
        RizzLine('you give very "her parents don\'t approve" energy and i\'m here for it',
                 'ARCHETYPE READ'),
        RizzLine('be honest, are you the friend everyone secretly has a crush on',
                 'INTIMATE PRESUMPTION'),
        RizzLine('we\'d date six months, fight at a wedding, then write songs about each other',
                 'COMPRESSED CINEMA'),
        RizzLine('i\'m normally calm but you make me text like i\'m 19',
                 'VULNERABLE FLEX'),
        RizzLine('warning: i overshare by the second date',
                 'VULNERABLE FLEX'),
        RizzLine('your photos suggest you\'re the kind of trouble i should avoid. i won\'t',
                 'CONFIDENT CONCESSION'),
        RizzLine('what\'s something i\'d never guess about you',
                 'INTIMATE PROBE'),
        RizzLine('tell me u have a bf so i can move on with my life',
                 'FRAME CHECK'),
        RizzLine('ok this is weird but your aura is unforgivable',
                 'INAPPROPRIATE COMPLIMENT'),
        RizzLine('ngl i was gonna play it cool. that lasted four seconds',
                 'SELF-AWARE OPEN'),
        RizzLine('concerning amount of thought has gone into this opener',
                 'SELF-AWARE OPEN'),
        RizzLine('be honest — what would we fight about in three months',
                 'DOMESTIC PROJECTION'),
        RizzLine('i\'m trying to figure out if you\'re the funny one or the chaotic one',
                 'ARCHETYPE READ'),
        RizzLine('settle a bet — am i flirting or being friendly. asking for me',
                 'META-FLIRT'),
        RizzLine('your photos commit acts of psychological warfare',
                 'INAPPROPRIATE COMPLIMENT'),
        RizzLine('i\'m normal-coded, i promise. i\'m not',
                 'SELF-AWARE OPEN'),
        RizzLine('what\'s the most unhinged thing you\'ve said in therapy',
                 'INTIMATE PROBE'),
        RizzLine('i matched with you and immediately my standards became a problem',
                 'INAPPROPRIATE COMPLIMENT'),
        RizzLine('you have main character syndrome and i\'m complicit',
                 'INAPPROPRIATE COMPLIMENT'),
        RizzLine('two truths one lie. go',
                 'INTIMATE PROBE'),
        RizzLine('drop your worst opener. i\'m building a hall of fame',
                 'SELF-AWARE OPEN'),
        RizzLine('i\'d ask how your week is going but i\'d rather skip ahead',
                 'HIGH-AGENCY'),
        RizzLine('permission to be slightly inappropriate requested',
                 'SELF-AWARE OPEN'),
        RizzLine('tell me three things you\'d lie about on a first date',
                 'INTIMATE PROBE'),
        RizzLine('we\'re skipping small talk. tell me your villain origin story',
                 'INTIMATE PROBE'),
      ],
    ),

    // ── TEASE ───────────────────────────────────────────────────────────
    RizzCategory(
      label:    'TEASE',
      slug:     'tease',
      headline: 'The needle.',
      hint:     'Push-pull. Playful jabs. Make her chase.',
      lines: [
        RizzLine('be careful — i fall easy and i\'m clingy on weekends',
                 'VULNERABLE FLEX'),
        RizzLine('your icks list is suspiciously close to my personality',
                 'BACKHANDED'),
        RizzLine('you say one nice thing and i\'m planning the engagement',
                 'PREEMPTIVE LOVE'),
        RizzLine('huh — funnier than your photos suggested',
                 'BACKHANDED'),
        RizzLine('you\'re suspiciously photogenic. that\'s a flaw',
                 'BACKHANDED'),
        RizzLine('what\'s your worst red flag, i\'ll need it later',
                 'INTIMATE PROBE'),
        RizzLine('you\'re trouble and i don\'t have the bandwidth',
                 'PUSH-PULL'),
        RizzLine('we\'re not going to work out. i can\'t promise that',
                 'PUSH-PULL'),
        RizzLine('lower your expectations — i\'m only mildly impressive',
                 'DISQUALIFIER'),
        RizzLine('i\'d rate you a soft "i don\'t hate this"',
                 'DISQUALIFIER'),
        RizzLine('you talk like someone who\'s winning. respect',
                 'INAPPROPRIATE COMPLIMENT'),
        RizzLine('you do this on purpose, don\'t you',
                 'TEASE'),
        RizzLine('saying "lol" is a marriage proposal where i\'m from',
                 'MISINTERPRETATION'),
        RizzLine('you don\'t even need to flirt. i\'m doing both parts',
                 'HIGH-AGENCY'),
        RizzLine('the audacity. love that for you',
                 'TEASE'),
        RizzLine('i was warned about your type. the warning was correct',
                 'PUSH-PULL'),
        RizzLine('i\'d insult your taste but you\'re talking to me, so',
                 'SELF-AWARE'),
        RizzLine('you\'re unserious and you know exactly what you\'re doing',
                 'PUSH-PULL'),
        RizzLine('main-character lighting in every photo. suspicious',
                 'BACKHANDED'),
        RizzLine('this is technically the third time you\'ve flirted with me',
                 'MISINTERPRETATION'),
        RizzLine('i was being well-behaved before you started this',
                 'MISINTERPRETATION'),
        RizzLine('you\'re way too good at this. i need a handicap',
                 'DISQUALIFIER'),
        RizzLine('lying about being shy already, i see',
                 'TEASE'),
        RizzLine('stop testing me and just ask me out',
                 'FRAME CHECK'),
        RizzLine('i\'m gonna pretend that was a yes',
                 'MISINTERPRETATION'),
      ],
    ),

    // ── HEAT ────────────────────────────────────────────────────────────
    RizzCategory(
      label:    'HEAT',
      slug:     'heat',
      headline: 'The burn.',
      hint:     'Convo is warm. Escalate without spilling it.',
      lines: [
        RizzLine('stop texting with that energy on a tuesday, it\'s reckless',
                 'META-FLIRT'),
        RizzLine('you\'re making me forget i\'m supposed to be unbothered',
                 'META-FLIRT'),
        RizzLine('i\'d kiss you on the forehead and then ruin your life',
                 'INTIMATE FUTURE'),
        RizzLine('we both know how this ends',
                 'CONFIDENT VAGUENESS'),
        RizzLine('you\'d be a problem if i let you',
                 'HIGH-AGENCY'),
        RizzLine('this is officially a problem i\'m willing to have',
                 'HIGH-AGENCY'),
        RizzLine('you keep showing up in my drafts',
                 'META-FLIRT'),
        RizzLine('stop being interesting. it\'s inconvenient',
                 'META-FLIRT'),
        RizzLine('you said "haha" and i felt that emotionally',
                 'MISINTERPRETATION'),
        RizzLine('i want to know what your laugh sounds like in person',
                 'INTIMATE FUTURE'),
        RizzLine('i\'m not catching feelings, i\'m catching attention. different',
                 'HIGH-AGENCY'),
        RizzLine('you\'re going to ruin my plans this weekend and i\'m letting you',
                 'HIGH-AGENCY'),
        RizzLine('i\'d take you somewhere nice but my standards keep rising',
                 'FRAME CHECK'),
        RizzLine('you have a good-influence face and a bad-influence aura',
                 'INAPPROPRIATE COMPLIMENT'),
        RizzLine('the chemistry is unreasonable',
                 'INAPPROPRIATE COMPLIMENT'),
        RizzLine('the part where you flirt back is now, by the way',
                 'FRAME CHECK'),
        RizzLine('stop laughing at my jokes, i\'m trying to be unbothered',
                 'META-FLIRT'),
        RizzLine('i had a real life before this app. now it\'s just you',
                 'META-FLIRT'),
        RizzLine('i don\'t make a habit of this. you\'re worth the exception',
                 'HIGH-AGENCY'),
        RizzLine('this might be the rizz talking, but',
                 'META-FLIRT'),
        RizzLine('ok i\'m in trouble',
                 'VULNERABLE FLEX'),
        RizzLine('you make "just texting" look way too good',
                 'INAPPROPRIATE COMPLIMENT'),
        RizzLine('i\'d say drinks but you\'d say yes too quickly',
                 'PUSH-PULL'),
        RizzLine('you\'re way too good at this. what\'s the catch',
                 'INTIMATE PROBE'),
        RizzLine('you\'re not getting rid of me with that energy',
                 'FRAME CHECK'),
      ],
    ),

    // ── COLD ────────────────────────────────────────────────────────────
    RizzCategory(
      label:    'COLD',
      slug:     'cold',
      headline: 'The revive.',
      hint:     'She went short. Or silent. Bring her back without begging.',
      lines: [
        RizzLine('ok that was the worst response you could\'ve given me',
                 'FRAME CHECK'),
        RizzLine('i\'ll let that one slide',
                 'HIGH-AGENCY'),
        RizzLine('tell me you\'re alive or i\'m sending help',
                 'TEASE'),
        RizzLine('honest review: 4/10. i know you can do better',
                 'TEASE'),
        RizzLine('do better. i believe in you',
                 'FRAME CHECK'),
        RizzLine('you went non-verbal on me',
                 'TEASE'),
        RizzLine('you went one-word on me. i\'m allowed drama',
                 'TEASE'),
        RizzLine('tell me a story or i\'m asking my ex about her day',
                 'TEASE'),
        RizzLine('let me know when you\'re back from the moon',
                 'TEASE'),
        RizzLine('the silence is doing a lot of talking',
                 'REFRAME'),
        RizzLine('i\'m pretending you typed a long thoughtful message',
                 'MISINTERPRETATION'),
        RizzLine('match my energy please, this is embarrassing for both of us',
                 'FRAME CHECK'),
        RizzLine('i\'ll take "haha" as "tell me more"',
                 'MISINTERPRETATION'),
        RizzLine('is this how you treat your future favorite person',
                 'REFRAME'),
        RizzLine('if this is your busy energy i need to see your free energy',
                 'REFRAME'),
        RizzLine('i can keep being charming. or you can do something about it',
                 'FRAME CHECK'),
        RizzLine('asking one more time before i go play it cool somewhere else',
                 'HIGH-AGENCY'),
        RizzLine('i was being interesting. read the room',
                 'TEASE'),
        RizzLine('tell me i didn\'t make it weird. i didn\'t',
                 'SELF-AWARE'),
        RizzLine('wow rude. jk text me back',
                 'VULNERABLE FLEX'),
        RizzLine('i\'m starting to think i made you up',
                 'META-FLIRT'),
        RizzLine('let\'s try that again. with feeling',
                 'TEASE'),
        RizzLine('this is your formal warning. i go off in 24h',
                 'FRAME CHECK'),
        RizzLine('did i accidentally say something interesting',
                 'SELF-AWARE'),
        RizzLine('ok i\'ll be more interesting. hang on',
                 'SELF-AWARE'),
      ],
    ),

    // ── CLOSE ───────────────────────────────────────────────────────────
    RizzCategory(
      label:    'CLOSE',
      slug:     'close',
      headline: 'The pull.',
      hint:     'Move her offline. Texting is the warm-up.',
      lines: [
        RizzLine('let\'s stop texting and start talking',
                 'DATE PROPOSAL'),
        RizzLine('give me a date or give me peace',
                 'FRAME CHECK'),
        RizzLine('we\'re three messages from agreeing to meet. let\'s skip',
                 'HIGH-AGENCY'),
        RizzLine('okay enough warm-up. drink thursday?',
                 'DATE PROPOSAL'),
        RizzLine('skip to the part where we get coffee',
                 'DATE PROPOSAL'),
        RizzLine('let\'s argue about something over wine',
                 'DATE PROPOSAL'),
        RizzLine('you owe me a drink for surviving my texting',
                 'TEASE'),
        RizzLine('let\'s make this irresponsibly fast. friday',
                 'DATE PROPOSAL'),
        RizzLine('i don\'t text long. i meet',
                 'HIGH-AGENCY'),
        RizzLine('the next date you go on is with me. you don\'t even know yet',
                 'HIGH-AGENCY'),
        RizzLine('i\'m in town this weekend. what\'s your move',
                 'DATE PROPOSAL'),
        RizzLine('your number or your taste in restaurants. your call',
                 'FRAME CHECK'),
        RizzLine('alright — your number or i give up the chase',
                 'FRAME CHECK'),
        RizzLine('if i ask you out now do you ghost me or do we win',
                 'META-FLIRT'),
        RizzLine('this app is taking too long. let\'s argue in person',
                 'DATE PROPOSAL'),
        RizzLine('i pick the place. you pick the day',
                 'HIGH-AGENCY'),
        RizzLine('give me your worst free evening this week',
                 'DATE PROPOSAL'),
        RizzLine('let\'s go for the worst possible coffee in town',
                 'DATE PROPOSAL'),
        RizzLine('you. me. drinks. before i overthink this',
                 'DATE PROPOSAL'),
        RizzLine('i\'m not getting all this rizz off and not seeing you',
                 'HIGH-AGENCY'),
        RizzLine('deal: one drink. one chance to ruin my opinion of you',
                 'DATE PROPOSAL'),
        RizzLine('i\'ll send my calendar. you pick — tuesday or friday',
                 'HIGH-AGENCY'),
        RizzLine('what\'s your number, the suspense is killing my bit',
                 'FRAME CHECK'),
        RizzLine('let\'s be irresponsibly impulsive and meet',
                 'DATE PROPOSAL'),
        RizzLine('let\'s do this in person. my texts can only carry so much',
                 'HIGH-AGENCY'),
      ],
    ),
  ];
}
