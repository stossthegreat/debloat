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
  /// Raw single-line text. Null for sequence entries — those compute
  /// [text] lazily from [parts] joined with " — ".
  final String? _rawText;
  final String tag;

  /// Multi-line sequences — the question-then-killshot format. Each
  /// element renders as its own line inside the card. First entry is
  /// the setup ("Be honest with me…"), second is the payoff. Clipboard
  /// copy uses the [text] getter (joined) so the user pastes the
  /// whole thing in one go.
  final List<String>? parts;

  const RizzLine(String text, this.tag, {this.parts}) : _rawText = text;

  /// Multi-part sequence — must be a const NAMED constructor (not a
  /// factory) so the const RizzCategory tree can hold it. Initializer
  /// list assigns directly because we can't call .join() in a const
  /// expression — [text] computes the joined form lazily on read.
  const RizzLine.seq(List<String> sequence, this.tag)
      : _rawText = null,
        parts = sequence;

  /// The line's flat text — explicit for single lines, joined for
  /// sequences. Used by clipboard copy + analytics.
  String get text => _rawText ?? (parts ?? const []).join(' — ');

  bool get isSequence => parts != null && parts!.length > 1;
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

    // ── CHEESY ──────────────────────────────────────────────────────────
    // The classic chat-up lines that work BECAUSE they're cheesy. Land
    // with a smile and zero apology — she'll groan, then she'll laugh,
    // then she'll be the one keeping the convo going.
    //
    // CULL: bro flagged this category as carrying trash from earlier
    // builds. Out: "parking ticket / fine", "bank loan / interest",
    // "google / searching", "campfire / s'more", "keyboard / type",
    // "boxer / knockout", "raisins / date", "dictionary / meaning",
    // "god bless / already did", "are you a magician" — all read like
    // 2014 Reddit, none would survive the screenshot test.
    //
    // The survivors are the ones that still slap because they're
    // either short, self-aware, or cinematic. The sunset / storm /
    // gravity quartet stays because the seductive-pun framing actually
    // lands on Hinge in 2026 — those four are the modern keepers.
    RizzCategory(
      label:    'CHEESY',
      slug:     'cheesy',
      headline: 'The chat-ups.',
      hint:     'The classics that still slap. Land them with a smile.',
      lines: [
        RizzLine('do you have a map? i keep getting lost in your eyes',
                 'TIMELESS LEGEND'),
        RizzLine('do you believe in love at first sight or should i walk past again',
                 'TIMELESS LEGEND'),
        RizzLine('do you have a name or can i call you mine',
                 'CLASSIC PUN'),
        RizzLine('i\'m not a photographer but i can picture us together',
                 'CLASSIC PUN'),
        RizzLine('are you french? eiffel for you',
                 'CLASSIC PUN'),
        RizzLine('i was going to play it cool. then you smiled. cool is cancelled',
                 'SELF-AWARE'),
        RizzLine('excuse me. i think you dropped something. my jaw',
                 'CLASSIC PUN'),
        RizzLine('i had a whole speech. you completely ruined it by being this attractive',
                 'SELF-AWARE'),
        RizzLine('are you a sunset? i\'d stop everything just to watch you',
                 'SEDUCTIVE PUN'),
        RizzLine('are you a storm? you walked in and changed the whole atmosphere',
                 'SEDUCTIVE PUN'),
        RizzLine('are you gravity? everything in me just moves towards you',
                 'SEDUCTIVE PUN'),
        RizzLine('are you a compass? every version of me points towards you',
                 'SEDUCTIVE PUN'),
        RizzLine('are you a library? i\'d come back to you every day for the rest of my life',
                 'SEDUCTIVE PUN'),
        RizzLine('are you a melody? i\'ve had you stuck in my head all morning',
                 'SEDUCTIVE PUN'),
        RizzLine('are you a memory? i don\'t want to forget a single detail',
                 'SEDUCTIVE PUN'),
        RizzLine('hi. you looked interesting. i had to',
                 'UNDEFEATED'),
        RizzLine('this is the bit where i\'m supposed to be smooth. i\'m not. but you\'re still here',
                 'SELF-AWARE'),
        RizzLine('i don\'t have a clever line. i have a really strong opinion that you\'re worth talking to',
                 'GENUINE'),
        RizzLine('i was minding my own business until you walked in. now i\'m minding yours',
                 'SELF-AWARE'),
        RizzLine('every time i look at you i forget the rule about playing it cool',
                 'SELF-AWARE'),
        RizzLine('i think you\'re my favourite kind of mistake',
                 'PUSH-PULL'),
        RizzLine('i\'m going to need you to stop being this perfect, it\'s unfair to the others',
                 'INAPPROPRIATE COMPLIMENT'),
        RizzLine('hi. i\'m the future regret you\'d have for ignoring this',
                 'HIGH-AGENCY'),
        RizzLine('i don\'t flirt. i just say the truth and people get nervous',
                 'HIGH-AGENCY'),
        RizzLine('you\'re going to be my favourite story to tell',
                 'COMPRESSED CINEMA'),
      ],
    ),

    // ── CHARM ───────────────────────────────────────────────────────────
    // Heart-melters. Genuine soulful warmth in a sea of performers.
    // The ones that aren't trying to be clever — they\'re just trying
    // to make her feel seen. These hit different at 2am.
    RizzCategory(
      label:    'CHARM',
      slug:     'charm',
      headline: 'The heart-melters.',
      hint:     'Drop the act. Genuine. The ones that make her feel seen.',
      lines: [
        RizzLine('you laugh like you mean it. that\'s rarer than you think',
                 'NOTICED'),
        RizzLine('you\'ve got kind eyes. not soft. kind. there\'s a difference',
                 'NOTICED'),
        RizzLine('something about you makes me want to be a better conversationalist',
                 'VULNERABLE FLEX'),
        RizzLine('you make being nervous feel worth it',
                 'VULNERABLE FLEX'),
        RizzLine('i don\'t do this often. you should feel special. because you are',
                 'HIGH-AGENCY'),
        RizzLine('i just want to know everything about you. not quickly. properly',
                 'GENUINE'),
        RizzLine('you\'re the kind of person i\'d want in my corner. just generally. in life',
                 'NOTICED'),
        RizzLine('you make being genuine feel like the only option worth taking',
                 'GENUINE'),
        RizzLine('i don\'t want a moment with you. i want the whole story',
                 'KILLSHOT'),
        RizzLine('you deserve someone who notices everything. every single thing',
                 'GENUINE'),
        RizzLine('i just want to make you laugh. properly. repeatedly. forever',
                 'KILLSHOT'),
        RizzLine('i feel like you\'re someone worth being patient for',
                 'GENUINE'),
        RizzLine('you make being honest feel easier than being impressive',
                 'GENUINE'),
        RizzLine('you\'re the kind of thought that keeps me up. and i haven\'t even spoken to you',
                 'MIDNIGHT'),
        RizzLine('there\'s something about you that makes me want to be the most interesting version of myself',
                 'MIDNIGHT'),
        RizzLine('i don\'t have a type anymore. i have you as a reference point now',
                 'KILLSHOT'),
        RizzLine('i\'d let you distract me from everything i\'ve carefully prioritised',
                 'MIDNIGHT'),
        RizzLine('you\'re not my first thought in the morning yet. but you\'re about to be',
                 'KILLSHOT'),
        RizzLine('i\'d cancel plans for this conversation. good plans too',
                 'NOTICED'),
        RizzLine('you walked in and my whole plan for the evening restructured itself around you',
                 'HOOK'),
      ],
    ),

    // ── SEQUENCES ───────────────────────────────────────────────────────
    // Multi-line setups. The question-then-killshot format — the most
    // powerful structure in the game. The question pulls her in; the
    // answer hits before she can defend. Tap to copy the whole thing.
    RizzCategory(
      label:    'SEQUENCES',
      slug:     'sequences',
      headline: 'The setups.',
      hint:     'Setup → killshot. Multi-line. The most powerful structure in the game.',
      lines: [
        RizzLine.seq(const [
          'be honest with me for a second…',
          'do you actually try or does it just come naturally? that\'s unfair either way',
        ], 'QUESTION → KILLSHOT'),
        RizzLine.seq(const [
          'can i tell you something honest?',
          'you make it really hard to be a person who plays it cool. like genuinely',
        ], 'INTIMATE PRESUMPTION'),
        RizzLine.seq(const [
          'you know what i think?',
          'you\'d be completely disarmed by someone who actually listened to every word',
        ], 'GENUINE'),
        RizzLine.seq(const [
          'can i make a confession?',
          'i had a whole approach planned. forgot it the second you looked at me',
        ], 'VULNERABLE FLEX'),
        RizzLine.seq(const [
          'what are you like at 2am?',
          'because right now you\'re already the most interesting person here',
        ], 'INTIMATE PROBE'),
        RizzLine.seq(const [
          'can i tell you something you probably never hear?',
          'the unguarded version of you — that\'s the one i\'m already more interested in',
        ], 'GENUINE'),
        RizzLine.seq(const [
          'be honest…',
          'when\'s the last time someone made you feel completely understood?',
        ], 'INTIMATE PROBE'),
        RizzLine.seq(const [
          'can i make you a promise?',
          'i will never make you feel like you\'re too much. you\'re not too much',
        ], 'KILLSHOT'),
        RizzLine.seq(const [
          'you know what\'s crazy?',
          'if we\'d met at the wrong time we\'d have still found each other eventually',
        ], 'COMPRESSED CINEMA'),
        RizzLine.seq(const [
          'i\'m not saying i\'m the best option…',
          'but i\'m absolutely the most interesting one and you already know that',
        ], 'HIGH-AGENCY'),
        RizzLine.seq(const [
          'i\'m a terrible idea.',
          'you look like someone who\'s made terrible ideas work before',
        ], 'PUSH-PULL'),
        RizzLine.seq(const [
          'do you know what your problem is?',
          'you\'re exactly my type and i had carefully decided to stop having a type',
        ], 'MISINTERPRETATION'),
        RizzLine.seq(const [
          'i\'m a simple man.',
          'i saw you. i panicked internally. i approached anyway. love story',
        ], 'VULNERABLE FLEX'),
        RizzLine.seq(const [
          'quick question…',
          'are you always this captivating or did you decide to destroy me today?',
        ], 'INAPPROPRIATE COMPLIMENT'),
        RizzLine.seq(const [
          'excuse me. i think you dropped something.',
          'your standards. don\'t worry — i\'ll keep them high for you',
        ], 'FRAME CHECK'),
        RizzLine.seq(const [
          'you\'re a nightmare.',
          'my favourite kind',
        ], 'PUSH-PULL'),
        RizzLine.seq(const [
          'i don\'t even like you that much.',
          'yet',
        ], 'PUSH-PULL'),
        RizzLine.seq(const [
          'you\'re difficult, funny, and completely magnetic.',
          'worst combination possible. i\'m obsessed',
        ], 'KILLSHOT'),
        RizzLine.seq(const [
          'do you believe in first impressions?',
          'because mine of you was that you\'re the kind of person i\'d regret not talking to',
        ], 'GENUINE'),
        RizzLine.seq(const [
          'i don\'t have a line.',
          'i just know that walking away without saying something would\'ve bothered me forever',
        ], 'KILLSHOT'),
      ],
    ),

    // ── COMEBACKS ───────────────────────────────────────────────────────
    // For when she claps back. Calm, warm, slightly amused. The whole
    // game is showing her you\'re not rattled.
    RizzCategory(
      label:    'COMEBACKS',
      slug:     'comebacks',
      headline: 'The volleys.',
      hint:     'When she claps back. Don\'t fold. Smile and stay.',
      lines: [
        RizzLine.seq(const [
          'her: "you\'re weird"',
          'you: "yeah. still here though"',
        ], 'UNBOTHERED'),
        RizzLine.seq(const [
          'her: "i have a boyfriend"',
          'you: "cool. i have a dog. we\'re both taken. wanna talk anyway?"',
        ], 'REFRAME'),
        RizzLine.seq(const [
          'her: "why are you like this"',
          'you: "genuinely working on it. you\'re not helping"',
        ], 'SELF-AWARE'),
        RizzLine.seq(const [
          'her: laughs and says nothing',
          'you: "see. you get it"',
        ], 'INTIMATE PRESUMPTION'),
        RizzLine('you\'re lucky you\'re cute — that was the worst comeback i\'ve heard',
                 'PLAYFUL DISS'),
        RizzLine('you\'re a handful aren\'t you. i can tell already',
                 'PLAYFUL DISS'),
        RizzLine('did you just roll your eyes at me? adorable. try again',
                 'PLAYFUL DISS'),
        RizzLine('you\'re testing me right now and i want you to know i\'m winning',
                 'FRAME CHECK'),
        RizzLine('you\'re giving me attitude like that\'s going to stop me. it won\'t',
                 'FRAME CHECK'),
        RizzLine('you\'re trouble. i decided i don\'t care',
                 'HIGH-AGENCY'),
        RizzLine('i\'ve met walls with better comebacks honestly',
                 'PLAYFUL DISS'),
        RizzLine('you\'re so competitive. i love it. you\'re still losing though',
                 'PUSH-PULL'),
        RizzLine('you\'re really not going to make this easy are you. good',
                 'FRAME CHECK'),
        RizzLine('you\'ve got a comeback for everything. attractive and slightly exhausting',
                 'NOTICED'),
        RizzLine('you clearly have excellent taste — you\'re still talking to me',
                 'HIGH-AGENCY'),
        RizzLine('i\'m not for everyone. i\'m just for people with good instincts',
                 'HIGH-AGENCY'),
        RizzLine('you\'re pretending not to be interested. it\'s cute. take your time',
                 'PUSH-PULL'),
        RizzLine('you argued back immediately. most attractive thing you\'ve done',
                 'TEASE'),
        RizzLine('i can\'t tell if you like me or you\'re just competitive. entertained either way',
                 'TEASE'),
        RizzLine('you\'re difficult.',
                 'PUSH-PULL'),
      ],
    ),
  ];
}
