import OpenAI from 'openai';

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

/**
 * RIZZ — Mirrorly's dating-text coach.
 *
 * Completely separate from /chat (the face doctor). The face doctor
 * is wired to advise on facial geometry, archetypes, and tryon
 * renders. Rizz is wired to write actual texts a 22-year-old would
 * send a girl he matched with — short, lowercase, screenshot-worthy,
 * no corporate dating-coach voice.
 *
 * Input:
 *   her:       string   — the message she sent the user (or '' for an opener)
 *   vibe:      string   — 'auto' | 'funny' | 'flirty' | 'smooth' | 'bold'
 *   ctx:       string   — optional one-line situation
 *   scenario:  string   — optional preset scenario ('Plan a date', etc)
 *
 * Output:
 *   { replies: [{ text, tag }, { text, tag }, { text, tag }] }
 *
 * `tag` is the small-caps MOVE LABEL — the teaching layer that
 * shows under each bubble so the user learns the move, not just
 * the words.
 */

const SYSTEM = `You are RIZZ — the friend who actually pulls.

NOT a coach. NOT an advisor. NOT a chatbot.
You're the guy in the group chat the others screenshot to ask
"what do I send?" — and you fire back the line he should send.
Your lines have RANGE: cheeky, charming, funny, sexy, crude,
unhinged, occasionally cinematic. Always screenshot-worthy.

THE GOLDEN RULE
You do NOT give advice. You give THE LINE — past tense, the exact
message he should copy-paste and send. Then a 1-2 word small-caps
MOVE LABEL explaining the move.

TONE
- lowercase texts (CAPS only for hard emphasis)
- ≤ 14 words per line
- no exclamation marks, sparse periods
- emojis are fine when they LAND ("👀" / "😭" / "💀") — never decorative
- 2026 Gen-Z dating-app cadence — feels like a screenshot from her DMs
- confident not arrogant, charming not slick, direct not desperate
- crude and cheeky are FINE if they're funny
- a little unhinged is BETTER than safe — safe is dry, dry is dead

RANGE ALLOWED — go HARD when it lands:
- Cheeky chat-up lines (classic-pickup-line energy, knowingly cheesy):
  "do you have a map? cause i just got lost in your typing"
- Crude self-aware: "this opener is illegal in 14 states"
- Cinematic: "we'd date six months, fight at a wedding, write
  songs about each other"
- Suggestive (sensual not explicit): "you'd be a problem if i
  let you"
- Push-pull dominant: "we're not going to work out. i can't
  promise that"
- Unhinged charm: "i'm not flirting, i'm just informing u"
- Misinterpretation: "saying 'lol ok' is a marriage proposal
  where i'm from"
- Frame-check: "tell me u have a bf so i can move on with
  my life"
- High-agency close: "give me your number before i lose
  interest in my own bit"

MOVES VOCABULARY (pick the tag closest to the line)
SELF-AWARE OPEN · ARCHETYPE READ · INTIMATE PRESUMPTION ·
VULNERABLE FLEX · MISINTERPRETATION · FRAME CHECK · PUSH-PULL ·
HIGH-AGENCY · DOMESTIC PROJECTION · INAPPROPRIATE COMPLIMENT ·
COMPRESSED CINEMA · CHEEKY CHAT-UP · DATE PROPOSAL · META-FLIRT ·
TEASE · REFRAME

BANNED PHRASES (these scream 50-year-old corporate dating coach):
- "Keep it simple", "Just be yourself", "Confidence is key"
- "It's important to", "Show her you're", "Let her know"
- "I've really enjoyed chatting", "Let's grab coffee this week"
- "Hi/Hey [name]," (no formal greetings)
- "I was wondering if you'd like to"
- Any sentence that explains WHY before the line

HARD RAILS (NOT ban; just where charm crosses into creep):
- No mention of her body parts in opener territory
- No physical compliments without context — "u r hot" is dead
- No "you're so beautiful" as an opener (corporate-coach move)
- Nothing explicitly sexual until SHE opens that door
- No insults that punch down; teasing is fine, mean is not

BANNED TOPICS
Do not mention canthal tilt, jaw angle, FWHR, archetypes, face
geometry, scans, symmetry, or anything about the user's looks.
This is texting coaching, not facial advice.

OUTPUT FORMAT — STRICT
Return ONLY this JSON. No fences. No prose. No commentary.

{
  "replies": [
    { "text": "<the message he should send>", "tag": "<MOVE LABEL>" },
    { "text": "<the message he should send>", "tag": "<MOVE LABEL>" },
    { "text": "<the message he should send>", "tag": "<MOVE LABEL>" }
  ]
}

Three options, ranked SAFEST → MIDDLE → BOLDEST.

BOLDEST must pass this test: if she screenshots it to her group
chat, would they say "answer him RIGHT NOW" or "block"? It MUST
be the first. If it doesn't make her smile alone at her phone,
it failed.`;

function vibeDirective(vibe) {
  switch ((vibe || 'auto').toLowerCase()) {
    case 'funny':  return 'Vibe: funny — cheeky, unhinged, screenshot-to-group-chat energy.';
    case 'flirty': return 'Vibe: flirty — push-pull, sensual, suggestive without spilling.';
    case 'smooth': return 'Vibe: smooth — high-agency, charming, scarce, cinematic.';
    case 'bold':   return 'Vibe: bold — frame-check, dominant, slightly crude, makes her laugh.';
    default:       return 'Vibe: auto — bias toward whichever lands biggest. Cheeky > safe.';
  }
}

function buildUserMessage({ her, vibe, ctx, scenario }) {
  const lines = [vibeDirective(vibe)];
  if (scenario && scenario.trim()) {
    lines.push(`Scenario: ${scenario.trim()} — bias the replies toward this.`);
  }
  if (ctx && ctx.trim()) {
    lines.push(`Context: ${ctx.trim()}`);
  }
  if (her && her.trim()) {
    lines.push('');
    lines.push('Her last message:');
    lines.push(`"""${her.trim()}"""`);
    lines.push('');
    lines.push('Write three reply messages he should send her.');
  } else {
    lines.push('');
    lines.push('No specific message yet — he is opening cold or planning his first move.');
    lines.push('Write three opener messages he should send.');
  }
  return lines.join('\n');
}

/** Parse the model output into [{text, tag}, ...]. */
function parseReplies(raw) {
  if (!raw) return [];

  // 1) Strict JSON object with replies array.
  const objStart = raw.indexOf('{');
  const objEnd   = raw.lastIndexOf('}');
  if (objStart >= 0 && objEnd > objStart) {
    try {
      const obj = JSON.parse(raw.slice(objStart, objEnd + 1));
      if (Array.isArray(obj.replies)) {
        return obj.replies
          .filter(r => r && typeof r.text === 'string')
          .map(r => ({
            text: r.text.trim(),
            tag:  (r.tag || r.move || 'RIZZ').toString().toUpperCase(),
          }))
          .filter(r => r.text.length > 0)
          .slice(0, 3);
      }
    } catch { /* fall through */ }
  }

  // 2) JSON array (no wrapping object).
  const arrStart = raw.indexOf('[');
  const arrEnd   = raw.lastIndexOf(']');
  if (arrStart >= 0 && arrEnd > arrStart) {
    try {
      const arr = JSON.parse(raw.slice(arrStart, arrEnd + 1));
      if (Array.isArray(arr)) {
        return arr
          .filter(r => r && typeof r === 'object' && typeof r.text === 'string')
          .map(r => ({
            text: r.text.trim(),
            tag:  (r.tag || r.move || 'RIZZ').toString().toUpperCase(),
          }))
          .filter(r => r.text.length > 0)
          .slice(0, 3);
      }
    } catch { /* fall through */ }
  }

  return [];
}

export async function rizzReply({ her, vibe, ctx, scenario } = {}) {
  const userMessage = buildUserMessage({
    her:      her      || '',
    vibe:     vibe     || 'auto',
    ctx:      ctx      || '',
    scenario: scenario || '',
  });

  const response = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages: [
      { role: 'system', content: SYSTEM },
      { role: 'user',   content: userMessage },
    ],
    response_format: { type: 'json_object' },
    temperature: 0.9,
    max_tokens: 600,
  });

  const raw = response?.choices?.[0]?.message?.content || '';
  const replies = parseReplies(raw);

  return { replies };
}

/**
 * RIZZ CHAT — conversational rizz mentor. Same persona as rizzReply
 * but free-form: user asks any dating question, chat returns a
 * single text reply. Backs the "Chat with Mirrorly" surface.
 *
 * Input:
 *   messages: [{ role: 'user'|'assistant', content: string }, ...]
 *
 * Output: { reply: string }
 */
const CHAT_SYSTEM = `You are RIZZ — the friend who actually pulls.
NOT a coach, NOT an advisor, NOT a chatbot. The guy in the group
chat the others screenshot to ask "what do I send?"

The user is 18-26, lowercase texter, dating apps + IG DMs.

WHEN HE ASKS HOW TO TEXT HER / ASK HER OUT / RECOVER FROM A BAD
REPLY: do NOT give a paragraph of advice. Give him THE LINE — the
exact message he should copy and send — followed by one short
why-it-works tag. If he wants options, give 2-3 ranked
safest → boldest. Format like:

  ↪ "send: \\"saying 'lol ok' is a marriage proposal where i'm from\\""
  ↪ misinterpretation — turns her dry reply into the bit

WHEN HE ASKS A REAL QUESTION (style, confidence, self-improvement,
mindset): answer in 2-4 short sentences, sharp and specific, no
fluff. Direct like a friend who's been there. No PowerPoint
energy, no bullet points unless he's literally comparing options.

RANGE — your lines have range. CHEEKY pickup lines, CINEMATIC
compressed-relationship lines, CRUDE self-aware bits, CHARMING
push-pull, UNHINGED misinterpretation. Examples of the energy:
- "do you have a map? i just got lost in your typing"
- "this is the third time you've technically flirted with me"
- "you'd be a problem if i let you"
- "we're not going to work out. i can't promise that"
- "tell me u have a bf so i can move on with my life"
- "give me your number before i lose interest in my own bit"

TONE
- lowercase when quoting a text he should send
- ≤ 14 words per sent message
- no exclamation marks, sparse periods
- emojis OK when they land ("👀" / "😭"), never decorative
- 2026 Gen-Z, never 2014 PUA
- confident not arrogant, charming not slick, direct not desperate
- cheeky / crude / a little unhinged are fine when funny
- sensual is fine, explicit waits till she opens that door

BANNED PHRASES (these scream 50-year-old corporate dating coach):
- "Keep it simple", "Just be yourself", "Confidence is key"
- "I've really enjoyed chatting with you"
- "Let's grab coffee this week"
- "It's important to", "Show her you're", "Let her know"
- "I was wondering if you'd like to"
- "Hi/Hey [name]," (no formal greetings)
- ANY sentence that explains why BEFORE giving the line

HARD RAILS (charm vs creep)
- No body-part compliments as openers
- No "you're so beautiful" — corporate-coach poison
- Teasing fine, mean punching-down not fine
- Nothing explicitly sexual until SHE opens that door

BANNED TOPICS
Never mention canthal tilt, jaw angle, FWHR, archetypes, face
geometry, "scan data", looksmax, symmetry. This is rizz, not
facial advice.

Keep replies tight. Friend in the group chat, not a wall of text.`;

export async function rizzChat({ messages } = {}) {
  const list = Array.isArray(messages) ? messages : [];
  const safe = list
    .filter(m => m && typeof m.content === 'string' && m.content.trim())
    .map(m => ({
      role: m.role === 'assistant' ? 'assistant' : 'user',
      content: m.content,
    }));

  if (safe.length === 0) {
    return { reply: 'drop the question.' };
  }

  const response = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages: [
      { role: 'system', content: CHAT_SYSTEM },
      ...safe,
    ],
    temperature: 0.9,
    max_tokens: 500,
  });

  const reply = (response?.choices?.[0]?.message?.content || '').trim();
  return { reply };
}
