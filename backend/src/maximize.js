import Replicate from 'replicate';
import crypto from 'node:crypto';

const replicate = new Replicate({ auth: process.env.REPLICATE_API_TOKEN });

// Max, not Pro. Research:
//   - Pro is stabler across LONG CHAINS.
//   - Max has higher SINGLE-SHOT fidelity AND "better multi-instruction
//     handling" — BFL's own marketing copy for Max.
// We're doing one single shot with multiple instructions, so Max.
const MODEL = 'black-forest-labs/flux-kontext-max';

/**
 * Generate the Maximized Twin in ONE Flux call.
 *
 * ARCHITECTURE — why single call, not chain, not 3-solo:
 *
 *   Chained passes: each pass takes the previous output as reference, so
 *   drift compounds. By pass 3 the face is noticeably off.
 *
 *   3 solo from original: no drift accumulation per pass, but 3× Flux
 *   spend, 3× latency, and constant 429 throttling on Replicate's
 *   rate-limited tier. Hero only shows ONE fix anyway (we picked solo[0]
 *   as hero), so the other 2 renders were paid for but never seen in
 *   the primary moment.
 *
 *   Single call with all 3 combined: Max is BFL's designated multi-
 *   instruction model. One prompt, three visualRequests joined with
 *   commas + BFL canonical preservation clause. 1 call. No throttle.
 *   Fast. And when Max lands all three it IS the goat.
 *
 *   If Max drops one of three changes: the fix cards in the app are
 *   text-first; user taps "See it" on any individual fix to render
 *   it in isolation via /tryon. Cost-shifted to user intent — we
 *   don't pre-pay for renders the user might never look at.
 *
 * Preserve clause is CONFLICT-AWARE. BFL's canonical preserve list
 * includes "hairstyle" — but if the user's visualRequest is a haircut,
 * preserving hairstyle contradicts the change and Kontext flips a coin
 * on which wins. Solution: detect what's being changed and drop the
 * conflicting anchor from the preserve list.
 *
 * Returns:
 *   {
 *     url:              the single hero image (all 3 changes, if Max lands them)
 *     prompt:           the composed prompt (for debugging)
 *     seed:             deterministic
 *     intermediateUrls: [] (legacy field, kept for client compat)
 *   }
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
    'clearer, healthier skin with natural pores preserved',
    'cleanly groomed hair matched to the face shape',
    'a cleaner, more defined beard line',
  ];
}

/**
 * One BFL-canonical prompt combining all three changes. Conflict-aware
 * preserve list — if a change touches a canonical preserve anchor
 * (hairstyle / facial hair / skin tone), that anchor is dropped so the
 * model doesn't get contradicting instructions.
 */
function buildCombinedPrompt(changes) {
  const items = changes
    .map(s => String(s || '').trim())
    .filter(Boolean)
    .map(s => s.replace(/\.$/, ''));     // strip trailing periods
  if (items.length === 0) return '';

  // Join as a clean English list: "A, B, and C"
  const changeList = items.length === 1
    ? items[0]
    : items.length === 2
      ? `${items[0]} and ${items[1]}`
      : `${items.slice(0, -1).join(', ')}, and ${items[items.length - 1]}`;

  // Conflict detection — drop preserve anchors that contradict the changes.
  const lower = items.join(' | ').toLowerCase();
  const preserves = ['facial features', 'expression', 'age', 'ethnicity'];

  if (!/\b(hair(?!\s*line)|fade|crop|cut|hairline|fringe|buzz|taper|undercut)\b/.test(lower)) {
    preserves.push('hairstyle');
  }
  if (!/\b(beard|stubble|facial hair|moustache|goatee)\b/.test(lower)) {
    preserves.push('facial hair');
  }
  if (!/\b(skin|complexion|pore|texture|tone|blemish|retinol|glow)\b/.test(lower)) {
    preserves.push('skin tone');
  }

  const preserveClause = preserves.join(', ');

  return `The person in this photo, now with ${changeList}, while maintaining the same ${preserveClause}. Same pose, camera angle, framing, lighting, and background as the original. Photorealistic, natural pores preserved.`;
}

/**
 * Flux call with retry-with-backoff on 429. Honors Replicate's
 * `retry_after` when present. Single-call maximize rarely triggers 429
 * but the defence-in-depth is cheap.
 */
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
