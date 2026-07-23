import Replicate from 'replicate';
import crypto from 'node:crypto';

const replicate = new Replicate({ auth: process.env.REPLICATE_API_TOKEN });

// ─────────────────────────────────────────────────────────────────────────────
//  THE DEBLOAT TWIN — what this file does now
// ─────────────────────────────────────────────────────────────────────────────
// Debloat OS has ONE hero render: the user's OWN face, drained of bloat.
// Not a haircut. Not a grooming glow-up. The literal job is to show the user
// what they look like with the facial water-retention, puffiness, and soft
// submental/orbital fat removed — the face that is already there, under the
// bloat.
//
// WHY THE OLD PIPELINE NEVER DEBLOATED
// ------------------------------------
// The previous version ran a Stage-3 face-swap that pasted the ORIGINAL
// selfie's face geometry back onto the edit output. That was an identity
// lock for haircut edits — but for a debloat edit it is fatal: swapping the
// original (bloated) face back on top REVERTS the exact thing we just did.
// The de-puffing was being undone in the last step, every time. So the swap
// is gone. Identity is held by the edit model's native subject-lock plus a
// tightly-scoped prompt that changes ONLY soft tissue, never bone / hair /
// scene.
//
// MODEL
// -----
// Google's Nano Banana (Gemini 2.5 Flash Image). DeepMind's own line: it
// "locks onto your facial features, skin tone, and expression before making
// any change." That native identity clamp is exactly what a soft-tissue-only
// edit needs — we want the SAME person, minus the water. ~$0.039 / render.
const EDIT_MODEL = 'google/nano-banana';         // Gemini 2.5 Flash Image

/**
 * Generate the Debloat Twin — the user's face with facial bloat drained.
 *
 * Single-stage, identity-locked, soft-tissue-only. `brief` is accepted for
 * backward-compat with the /scan chain but is intentionally ignored: the
 * edit is ALWAYS "drain the bloat," never a haircut or grooming change.
 *
 * Returns { url, editUrl, prompt, seed, heroChange, model, intermediateUrls }.
 */
export async function maximize({ imageBase64, brief } = {}) {
  const prompt = buildPrompt();
  const seed   = deterministicSeed(imageBase64);
  const inputDataUri = `data:image/jpeg;base64,${imageBase64}`;

  console.log('[maximize] debloat render — single-stage, no face-swap');

  // Primary (and only) edit via Nano Banana. Retry on EVERY error
  // (not just transient): content-moderation false-positives, weird
  // Replicate 4xxs on valid payloads, and unclassified failures all
  // used to throw here and cascade up to a "Server hiccup" screen.
  // User's explicit ask: never fail. Retry 5 times; the Flutter
  // client will retry the whole request if we somehow still throw.
  const editStart = Date.now();
  const editUrl = await runWithRetry(
    () => runEdit({ imageDataUri: inputDataUri, prompt }),
    { label: 'debloat', maxAttempts: 5, retryAll: true },
  );
  console.log(`[maximize] debloat ok: ${Date.now() - editStart}ms`);

  return {
    url:              editUrl,
    editUrl,
    prompt,
    seed,
    heroChange:       'debloat',
    model:            EDIT_MODEL,
    intermediateUrls: [],
  };
}

/**
 * Generic retry wrapper for Replicate calls. Retries on:
 *   · HTTP 429 (rate limit)
 *   · HTTP 5xx (transient server errors — the #1 source of "Server hiccup"
 *     reports, Replicate's upstream is not always stable)
 *   · Network timeouts, ECONNRESET, ETIMEDOUT, socket hang up
 *
 * With retryAll (used here), retries EVERY error. Trade-off: a genuinely
 * broken payload wastes all attempts — but we'd rather waste retries than
 * throw a recoverable failure up to the user.
 *
 * Backoff: respects Retry-After hint if present, else exponential
 * (3s, 6s, 12s) capped at 30s.
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
  // HTTP status code matches
  if (/\b(429|500|502|503|504)\b/.test(m))           return true;
  if (m.includes('too many requests'))               return true;
  if (m.includes('internal server error'))           return true;
  if (m.includes('bad gateway'))                     return true;
  if (m.includes('service unavailable'))             return true;
  if (m.includes('gateway timeout'))                 return true;
  // Network / socket level
  if (m.includes('etimedout'))                       return true;
  if (m.includes('econnreset'))                      return true;
  if (m.includes('econnrefused'))                    return true;
  if (m.includes('socket hang up'))                  return true;
  if (m.includes('network socket disconnected'))     return true;
  if (m.includes('network error'))                   return true;
  if (m.includes('timeout'))                         return true;
  // Replicate-specific prediction failures that are often transient
  if (m.includes('prediction failed') && m.includes('overloaded')) return true;
  return false;
}

/**
 * THE DEBLOAT PROMPT — soft-tissue only, identity-locked.
 *
 * Six ordered beats, tuned for Nano Banana (Gemini 2.5 Flash Image):
 *
 *   1. Subject naming        — "The exact same person in this photo"
 *   2. The ONE job           — drain facial bloat / water retention
 *   3. Where the bloat lives  — cheeks, jawline, under-eyes, submental,
 *                               overall roundness/puffiness (named zones so
 *                               the model knows precisely what to reduce)
 *   4. Reveal, don't reshape  — the point is to UNCOVER the bone that is
 *                               already there under the water, NOT to carve
 *                               new bone. This keeps it believable and keeps
 *                               it the same person.
 *   5. Identity preserve      — bones, age, ethnicity, hair, expression,
 *                               skin tone exactly as-is
 *   6. Scene preserve         — lighting, background, framing, pose
 *
 * The framing is deliberately "the same face after perfect sleep, zero
 * sodium, and full hydration — every drop of water weight gone." That
 * mental model produces a de-puffed, sharper, drained version of the SAME
 * face rather than a different, thinner person. "Subtle but clearly
 * visible" keeps it from either doing nothing or going full ozempic-gaunt.
 */
function buildPrompt() {
  return (
    // 1 + 2 — subject + the single job
    `The exact same person in this photo, shown after their face has been ` +
    `completely de-bloated — drained of all water retention and facial ` +
    `puffiness, as if after perfect sleep, zero sodium, and full hydration. ` +

    // 3 — where the bloat lives (named zones)
    `Remove the facial bloat and soft water-weight puffiness from the ` +
    `cheeks, along the jawline and under the chin (submental area), and ` +
    `the puffy under-eye bags. Reduce the overall roundness and swelling ` +
    `of the face. Deflate the puffiness so the face looks tighter, leaner, ` +
    `drained, and more sculpted. ` +

    // 4 — reveal, don't reshape (this is what keeps identity + realism)
    `Reveal the cheekbones, the jawline, and the chin definition that are ` +
    `already there underneath the bloat — do NOT carve or add new bone, ` +
    `only uncover the existing bone structure by removing the water and ` +
    `soft fat sitting on top of it. Bring back a clean, defined jaw line ` +
    `and a flatter under-eye area. The change should be subtle but clearly ` +
    `visible — the same face, minus every drop of bloat. ` +

    // 5 — identity preserve
    `Keep it unmistakably the SAME person: same apparent age, same bone ` +
    `structure and face shape, same nose, same eye shape and eye colour, ` +
    `same lips, same expression, same hairstyle and hair, same facial ` +
    `hair, same ethnicity, and the same natural skin tone and skin ` +
    `texture. Do not beautify, do not airbrush, do not change the ` +
    `haircut, do not slim it into a different, thinner person. ` +

    // 6 — scene preserve
    `Keep the same lighting, background, framing, camera angle, and pose. ` +
    `Natural shadows. Photorealistic.`
  );
}

// ─── Primary edit ─────────────────────────────────────────────────────────────
async function runEdit({ imageDataUri, prompt }) {
  // Nano Banana accepts `image_input` as an ARRAY (supports up to 14 refs).
  // png output avoids jpg compression artifacts on skin.
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
