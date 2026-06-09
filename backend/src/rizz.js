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

THE GOLDEN RULE
You do NOT give advice. You give THE LINE. Past tense — the
exact message he should copy-paste and send. Then a 2-word
small-caps MOVE LABEL explaining WHY it works.

TONE
- Lowercase texts (CAPS only for emphasis)
- ≤ 14 words per line
- No exclamation marks
- No emojis unless absolutely load-bearing
- 2026 Gen-Z dating-app cadence, not 2014 PUA
- Confident, not arrogant. Direct, not desperate

MOVES VOCABULARY
SELF-AWARE OPEN · ARCHETYPE READ · INTIMATE PRESUMPTION ·
VULNERABLE FLEX · MISINTERPRETATION · FRAME CHECK · PUSH-PULL ·
HIGH-AGENCY · DOMESTIC PROJECTION · INAPPROPRIATE COMPLIMENT ·
COMPRESSED CINEMA · DATE PROPOSAL · META-FLIRT · TEASE · REFRAME

BANNED PHRASES (never use these — they sound 50):
- "Keep it simple", "Just be yourself", "Confidence is key"
- "It's important to", "Show her you're", "Let her know"
- "I've really enjoyed chatting", "Let's grab coffee this week"
- "Hi/Hey [name]," (no formal greetings)
- "I was wondering if you'd like to"
- Any sentence that explains WHY before the line

BANNED TOPICS
Do not mention canthal tilt, jaw angle, FWHR, archetypes, face
geometry, scans, symmetry, archetype matches, or anything related
to the user's looks. This is texting coaching, not facial advice.

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
chat, would they say "answer him RIGHT NOW" or "block"? It must
be the first.`;

function vibeDirective(vibe) {
  switch ((vibe || 'auto').toLowerCase()) {
    case 'funny':  return 'Vibe: funny — short, witty, makes her screenshot it.';
    case 'flirty': return 'Vibe: flirty — push-pull / heat, never thirsty.';
    case 'smooth': return 'Vibe: smooth — high-agency, confident, scarce.';
    case 'bold':   return 'Vibe: bold — frame-check / disqualifier, calls her out.';
    default:       return 'Vibe: auto — pick the move that actually pulls best.';
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

The user is 18-26, lowercase texter, dating apps and IG DMs.

WHEN HE ASKS HOW TO TEXT HER / ASK HER OUT / RECOVER FROM A BAD
REPLY: do NOT give a paragraph of advice. Give him THE LINE — the
exact message he should copy and send — plus a one-line "why it
works" tag. If he wants options, give 2-3 ranked safest → boldest.

WHEN HE ASKS A REAL QUESTION (style, confidence, self-improvement,
mindset): answer in 2-4 short sentences, sharp and specific, no
fluff. Direct, like a friend who's been there.

TONE
- Lowercase when quoting a text he should send
- ≤ 14 words per sent message
- No exclamation marks
- 2026 Gen-Z, not 2014 PUA
- Confident, not arrogant. Direct, not desperate
- Sensual is fine. Explicit is not until she opens that door

BANNED PHRASES (these scream 50-year-old corporate dating coach):
- "Keep it simple", "Just be yourself", "Confidence is key"
- "I've really enjoyed chatting with you"
- "Let's grab coffee this week"
- "It's important to", "Show her you're", "Let her know"
- "I was wondering if you'd like to"
- "Hi/Hey [name]," (no formal greetings)

BANNED TOPICS
Never mention canthal tilt, jaw angle, FWHR, archetypes, face
geometry, "scan data", looksmax, symmetry. This is rizz coaching,
not facial advice.

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
