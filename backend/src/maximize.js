import Replicate from 'replicate';
import crypto from 'node:crypto';

const replicate = new Replicate({ auth: process.env.REPLICATE_API_TOKEN });

// Max — BFL's designated multi-instruction model. We're doing one single-shot
// with multiple instructions, so Max > Pro on single-shot fidelity.
const MODEL = 'black-forest-labs/flux-kontext-max';

/**
 * Generate the Maximized Twin in ONE Flux call.
 *
 * PRODUCT RULE (user feedback — 2026-04-22):
 *   The HERO change must ALWAYS be a GROOMING edit — hair first, then beard.
 *   Skin is NEVER the hero. When skin appears in the change list, it is
 *   reduced to a soft daylight glow filter — invisible-as-an-edit — because
 *   the user must look IDENTICAL, just photographed on their best day.
 *
 *   Why: the earlier prompt treated all 3 fixes as equal siblings and Flux
 *   tended to blend them into a generic "smoothed/aged" look. Hair/beard
 *   edits are visually demonstrable wins (haircut, trimmed beard) — the
 *   "wow" moment. Skin edits at full strength read as AI-filter / plastic
 *   / older. The fix is HEIRARCHY:
 *     - 1 dominant grooming change (hair or beard)
 *     - 1 secondary grooming touch (beard if hair was primary, or stubble)
 *     - skin = "slight brightness lift, like soft daylight, no texture change"
 *
 * IDENTITY LOCK (hard):
 *   The user is the same person. Same exact face, same age, zero bone
 *   structure change. If Flux drifts these, the render fails. The clause
 *   is repeated three times in the prompt because Flux rewards redundancy.
 *
 * Returns:
 *   { url, prompt, seed, intermediateUrls: [] }
 */
export async function maximize({ imageBase64, brief }) {
  const improve = Array.isArray(brief?.improve) && brief.improve.length > 0
    ? brief.improve.slice(0, 3)
    : defaultImprove();

  while (improve.length < 3) {
    improve.push(defaultImprove()[improve.length]);
  }

  const prompt = buildCombinedPrompt(improve);
  const seed   = deterministicSeed(imageBase64);

  const url = await runKontextWithRetry({
    imageDataUri: `data:image/jpeg;base64,${imageBase64}`,
    prompt,
    seed,
  });

  return {
    url,
    prompt,
    seed,
    intermediateUrls: [], // client falls back to live /tryon per fix card
  };
}

function defaultImprove() {
  return [
    'cleanly styled modern haircut matched to the face shape',
    'a cleaner, more defined beard line (or neat stubble if clean-shaven)',
    'subtly brighter healthy skin — a light daylight glow, not a texture change',
  ];
}

/**
 * Classify each incoming improve item so we can rank them hero → supporting.
 *   priority 0 = HAIR     (hero if present)
 *   priority 1 = BEARD    (hero if hair absent; otherwise secondary)
 *   priority 2 = OTHER grooming (brows, teeth, glasses, etc.)
 *   priority 3 = SKIN     (demoted — rendered as a light filter, never as
 *                          an explicit edit)
 */
function classify(s) {
  const x = String(s || '').toLowerCase();
  if (/\b(hair(?!\s*line)|fade|crop|cut|hairline|fringe|buzz|taper|undercut|quiff|pomp|part)\b/.test(x)) return 0;
  if (/\b(beard|stubble|goatee|moustache|facial hair)\b/.test(x)) return 1;
  if (/\b(brow|eyebrow|teeth|whiten|glasses|frame|lash)\b/.test(x)) return 2;
  if (/\b(skin|complexion|pore|texture|tone|blemish|retinol|glow|tret|acne|redness|dull)\b/.test(x)) return 3;
  return 2;
}

function buildCombinedPrompt(changes) {
  const items = changes
    .map(s => String(s || '').trim())
    .filter(Boolean)
    .map(s => s.replace(/\.$/, ''));
  if (items.length === 0) return '';

  // Rank each item 0-3 (hair > beard > other grooming > skin).
  const ranked = items
    .map((s, i) => ({ s, pri: classify(s), idx: i }))
    .sort((a, b) => a.pri - b.pri || a.idx - b.idx);

  // Split into: primary grooming (hero), secondary grooming, skin-as-filter.
  const hero     = ranked[0];
  const secondary = ranked.find(r => r !== hero && r.pri <= 2);
  const hasSkin  = ranked.some(r => r.pri === 3);

  // Build the three sentence beats.
  const heroLine = hero
    ? `Apply a clearly visible primary grooming change: ${hero.s}. This is the hero change — it should be immediately obvious and flattering.`
    : '';

  const secondaryLine = secondary
    ? `In addition, refine: ${secondary.s}. This supports the hero change without competing with it.`
    : '';

  // Skin is NEVER described as an edit. It becomes a "light filter" beat.
  const skinLine = hasSkin
    ? `Apply only a very subtle daylight brightness lift to the skin — the kind of difference soft window light makes. NO texture change, NO blur, NO smoothing, NO retouching. Skin tone, pores, blemishes, freckles all remain exactly as in the original.`
    : '';

  // Conflict-aware preserve clause — drop anchors that contradict changes.
  const lower = items.join(' | ').toLowerCase();
  const preserves = ['facial features', 'bone structure', 'jawline', 'nose shape', 'eye shape', 'eye colour', 'lips', 'expression', 'apparent age', 'ethnicity'];

  if (!/\b(hair(?!\s*line)|fade|crop|cut|hairline|fringe|buzz|taper|undercut|quiff|pomp)\b/.test(lower)) {
    preserves.splice(1, 0, 'hairstyle');
  }
  if (!/\b(beard|stubble|goatee|moustache|facial hair)\b/.test(lower)) {
    preserves.push('facial hair');
  }

  const preserveClause = preserves.join(', ');

  return [
    `EDIT A PORTRAIT. Subject is the same exact person as in the input photo — same face, same bones, same age, same ethnicity, SAME IDENTITY. Do not make this person look older, younger, thinner, or different in any way other than the grooming changes specified below.`,
    ``,
    heroLine,
    secondaryLine,
    skinLine,
    ``,
    `HARD IDENTITY LOCK — preserve exactly: ${preserveClause}. If the face in the output doesn't visibly match the face in the input, the render has failed.`,
    ``,
    `Keep the same pose, camera angle, framing, lighting direction and background as the original photograph. Photorealistic. Natural pores and skin texture preserved. No beauty-filter smoothing. No painterly effect. No age shift.`,
  ].filter(Boolean).join(' ').replace(/\s+/g, ' ').trim();
}

async function runKontextWithRetry({ imageDataUri, prompt, seed }) {
  const maxAttempts = 3;
  let attempt = 0;
  while (true) {
    attempt++;
    try {
      return await runKontext({ imageDataUri, prompt, seed });
    } catch (err) {
      const msg   = String(err?.message ?? err);
      const is429 = msg.includes('429') || msg.includes('Too Many Requests');
      if (!is429 || attempt >= maxAttempts) throw err;
      const m       = msg.match(/retry_after"?\s*:\s*(\d+)/);
      const waitSec = m ? Number(m[1]) : Math.pow(2, attempt) * 3;
      const waitMs  = Math.min(Math.max(waitSec, 3), 30) * 1000;
      console.warn(`[flux] 429, waiting ${waitMs}ms (attempt ${attempt}/${maxAttempts})`);
      await new Promise(r => setTimeout(r, waitMs));
    }
  }
}

async function runKontext({ imageDataUri, prompt, seed }) {
  const input = {
    prompt,
    input_image:       imageDataUri,
    aspect_ratio:      'match_input_image',
    output_format:     'png',
    output_quality:    95,
    safety_tolerance:  2,
    prompt_upsampling: false,
    seed,
  };
  const output = await replicate.run(MODEL, { input });
  return typeof output === 'string'
    ? output
    : (output?.url?.() ?? output?.[0] ?? String(output));
}

function deterministicSeed(imageBase64) {
  const hash = crypto.createHash('md5').update(imageBase64).digest();
  return hash.readUInt32BE(0) % 2147483647;
}
