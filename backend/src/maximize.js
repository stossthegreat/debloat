import Replicate from 'replicate';
import crypto from 'node:crypto';

const replicate = new Replicate({ auth: process.env.REPLICATE_API_TOKEN });

// ─────────────────────────────────────────────────────────────────────────────
//  THE MAXED + DEBLOATED TWIN
// ─────────────────────────────────────────────────────────────────────────────
// The hero render shows the user their best self: the grooming glow-up they
// always had — fresh hair, clear skin, neat facial hair — AND their face
// drained of bloat (de-puffed, sharper jaw, hollowed cheeks). Both at once.
//
// WHY NO FACE-SWAP
// ----------------
// The original pipeline ran a Stage-3 face-swap that pasted the ORIGINAL
// selfie's face back onto the edit output to lock identity for haircut edits.
// But that swap REVERTS everything done to the face itself — both the debloat
// AND the skin cleanup — because it pastes the original (bloated, original-
// skin) face region back on top. Only the hair survived. That's why the twin
// "did nothing" once we asked it to debloat. So the swap is gone. Identity is
// held by Nano Banana's native subject-lock + a prompt that explicitly
// preserves bone structure, age, and ethnicity while it grooms + drains.
//
// MODEL
// -----
// Google's Nano Banana (Gemini 2.5 Flash Image). DeepMind's own line: it
// "locks onto your facial features, skin tone, and expression before making
// any change." Best-in-class identity retention for exactly this kind of
// same-person edit. ~$0.039 / render.
const EDIT_MODEL = 'google/nano-banana';

/**
 * Generate the hero twin — grooming glow-up + facial debloat in one edit.
 *
 * `brief.improve` (from the GPT analysis) supplies the single grooming hero
 * change (hair > beard > other grooming). Skin is always cleaned up and the
 * face is always de-bloated on top, regardless of the brief. Single-stage,
 * identity-locked, no face-swap.
 *
 * Returns { url, editUrl, prompt, seed, heroChange, model, intermediateUrls }.
 */
export async function maximize({ imageBase64, brief } = {}) {
  const improve = Array.isArray(brief?.improve) ? brief.improve : [];

  // Rank grooming fixes: hair(0) > beard(1) > other-grooming(2). Skin(3) is
  // handled by the always-on baseline, not as a hero.
  const ranked = improve
    .map((s, i) => ({ s: String(s || '').trim(), pri: classify(s), idx: i }))
    .filter(r => r.s.length > 0 && r.pri <= 2)
    .sort((a, b) => a.pri - b.pri || a.idx - b.idx);

  const heroChange = ranked.length > 0
    ? ranked[0].s
    : 'a cleanly styled, modern haircut that suits the face shape';

  const prompt = buildPrompt(heroChange);
  const seed   = deterministicSeed(imageBase64);
  const inputDataUri = `data:image/jpeg;base64,${imageBase64}`;

  console.log(`[maximize] maxed+debloat render — hero="${heroChange}" (no face-swap)`);

  // Primary (and only) edit via Nano Banana. Retry on EVERY error
  // (not just transient): content-moderation false-positives, weird
  // Replicate 4xxs on valid payloads, and unclassified failures all
  // used to throw here and cascade up to a "Server hiccup" screen.
  // User's explicit ask: never fail. Retry 5 times; the Flutter
  // client will retry the whole request if we somehow still throw.
  const editStart = Date.now();
  const editUrl = await runWithRetry(
    () => runEdit({ imageDataUri: inputDataUri, prompt }),
    { label: 'maximize', maxAttempts: 5, retryAll: true },
  );
  console.log(`[maximize] ok: ${Date.now() - editStart}ms`);

  return {
    url:              editUrl,
    editUrl,
    prompt,
    seed,
    heroChange,
    model:            EDIT_MODEL,
    intermediateUrls: [],
  };
}

/**
 * Generic retry wrapper for Replicate calls. With retryAll (used here),
 * retries EVERY error. Backoff honours a Retry-After hint if present, else
 * exponential (3s, 6s, 12s) capped at 30s.
 */
async function runWithRetry(fn, { label, maxAttempts = 3, retryAll = false } = {}) {
  let lastErr;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      const msg = String(err?.message ?? err);
      const transient = isTransient(msg);
      const shouldRetry = retryAll || transient;
      if (!shouldRetry || attempt >= maxAttempts) {
        console.error(`[${label}] failed attempt ${attempt}/${maxAttempts} (terminal): ${msg}`);
        throw err;
      }
      const retryAfter = msg.match(/retry_after"?\s*:\s*(\d+)/);
      const waitSec    = retryAfter ? Number(retryAfter[1]) : Math.pow(2, attempt) * 3;
      const waitMs     = Math.min(Math.max(waitSec, 3), 30) * 1000;
      const kind = transient ? 'transient' : 'unclassified';
      console.warn(`[${label}] ${kind} failure attempt ${attempt}/${maxAttempts}: "${msg.slice(0, 200)}" — waiting ${waitMs}ms`);
      await new Promise(r => setTimeout(r, waitMs));
    }
  }
  throw lastErr;
}

function isTransient(msg) {
  const m = msg.toLowerCase();
  if (/\b(429|500|502|503|504)\b/.test(m))           return true;
  if (m.includes('too many requests'))               return true;
  if (m.includes('internal server error'))           return true;
  if (m.includes('bad gateway'))                     return true;
  if (m.includes('service unavailable'))             return true;
  if (m.includes('gateway timeout'))                 return true;
  if (m.includes('etimedout'))                       return true;
  if (m.includes('econnreset'))                      return true;
  if (m.includes('econnrefused'))                    return true;
  if (m.includes('socket hang up'))                  return true;
  if (m.includes('network socket disconnected'))     return true;
  if (m.includes('network error'))                   return true;
  if (m.includes('timeout'))                         return true;
  if (m.includes('prediction failed') && m.includes('overloaded')) return true;
  return false;
}

/**
 * Classify an improve item so we can rank the grooming hero:
 *   0 = HAIR, 1 = BEARD, 2 = OTHER grooming, 3 = SKIN (baseline, not hero).
 */
function classify(s) {
  const x = String(s || '').toLowerCase();
  if (/\b(hair(?!\s*line)|fade|crop|cut|hairline|fringe|buzz|taper|undercut|quiff|pomp|part|bangs)\b/.test(x)) return 0;
  if (/\b(beard|stubble|goatee|moustache|facial hair)\b/.test(x)) return 1;
  if (/\b(brow|eyebrow|teeth|whiten|glasses|frame|lash)\b/.test(x)) return 2;
  return 3;
}

/**
 * THE PROMPT — grooming glow-up + facial debloat, identity-locked.
 *
 * Four beats:
 *   1. Subject + the grooming hero change (hair / beard / grooming)
 *   2. Grooming baseline — clean skin, styled hair, neat facial hair (always)
 *   3. THE DEBLOAT LAYER — drain facial water/puffiness, reveal the jaw and
 *      cheekbones already there (this is what makes it a Debloat render, not
 *      just a glow-up)
 *   4. Identity + scene preserve
 *
 * The debloat is framed as REVEALING existing bone by removing soft water-
 * weight, never carving new bone — that keeps it the same person, believable,
 * and un-revertable (no face-swap runs after this).
 */
function buildPrompt(heroChange) {
  return (
    // 1 — subject + grooming hero
    `The person in this photo. Give them ${heroChange}. ` +

    // 2 — grooming baseline (the glow-up they always had)
    `At the same time, make them look their absolute best: ` +
    `clean, clear, healthy skin with even tone — no acne, no blemishes, ` +
    `no redness, no visible pores — but keep natural skin texture ` +
    `(not airbrushed, not plastic, not smoothed). ` +
    `Give them freshly-cut, cleanly-styled hair. ` +
    `If they have facial hair, keep it neatly groomed with clean lines ` +
    `and a tight neckline. Groomed eyebrows, no stragglers. ` +

    // 3 — THE DEBLOAT LAYER (the whole point of the app — make it strong)
    `Now DRAMATICALLY de-bloat and de-puff the entire face — this is the ` +
    `most important change and it must be strong and obvious. Remove ALL ` +
    `facial water retention, bloat, and soft puffiness completely, as if ` +
    `this person lost every pound of water weight and facial fat and is at ` +
    `their leanest. HOLLOW OUT THE CHEEKS: reduce the buccal fat so the ` +
    `cheekbones stand out and a clear hollow appears just beneath them. ` +
    `Carve out a sharp, chiselled, clearly-defined jawline and a defined ` +
    `chin. Tighten the area under the chin and the neck — remove any ` +
    `submental fullness, soft double-chin, or jaw softness. Fully flatten ` +
    `and de-puff the under-eye bags. Slim the overall width and roundness ` +
    `of the face so it reads lean, sculpted, angular, and completely ` +
    `drained. Think "shredded, dehydrated, photo-shoot-ready face." Make ` +
    `the before→after transformation big and unmistakable. ` +

    // 4 — identity + scene preserve (leaner, but still clearly them)
    `Despite the strong slimming, it must still be recognisably the SAME ` +
    `person: keep their underlying bone structure, apparent age, nose ` +
    `shape, eye shape and eye colour, lip shape, expression, hairstyle, ` +
    `facial hair, ethnicity, and natural skin tone. Do not change who they ` +
    `are — only drain the bloat and fat to reveal a leaner, sharper version ` +
    `of this exact face. ` +
    `Keep the same lighting, background, framing, camera angle, and pose. ` +
    `Natural shadows. Photorealistic.`
  );
}

// ─── Primary edit ─────────────────────────────────────────────────────────────
async function runEdit({ imageDataUri, prompt }) {
  const input = {
    prompt,
    image_input:   [imageDataUri],
    aspect_ratio:  'match_input_image',
    output_format: 'png',
  };
  const output = await replicate.run(EDIT_MODEL, { input });
  return extractUrl(output);
}

// ─── helpers ─────────────────────────────────────────────────────────────────
function extractUrl(output) {
  if (typeof output === 'string') return output;
  if (Array.isArray(output))      return String(output[0]);
  if (output && typeof output.url === 'function') return output.url();
  if (output && typeof output.url === 'string')   return output.url;
  return String(output);
}

function deterministicSeed(imageBase64) {
  const hash = crypto.createHash('md5').update(imageBase64).digest();
  return hash.readUInt32BE(0) % 2147483647;
}
