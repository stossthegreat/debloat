import Replicate from 'replicate';
import crypto from 'node:crypto';

const replicate = new Replicate({ auth: process.env.REPLICATE_API_TOKEN });

// ─────────────────────────────────────────────────────────────────────────────
//  MODEL CHOICE — April 2026 research verdict
// ─────────────────────────────────────────────────────────────────────────────
// Kontext Max was producing "uglier / older / different person" outputs. The
// root cause is structural, not prompt-level:
//   1. Flux has a documented +2.18 year age bias on males (arxiv 2502.03420).
//   2. Kontext's identity is a SOFT prompt bias, not a face-embedding lock —
//      every edit re-synthesises the full face.
//   3. Flux's portrait prior over-smooths skin, which kills cheek-shadow and
//      reads as "older / less attractive."
// Fix = (a) use a model whose portrait prior isn't beauty-retouched, AND
//       (b) post-pass a face-swap from the ORIGINAL selfie back onto the edit
//           output — a GEOMETRIC identity lock that no prompt can outperform.
//
// Primary edit model: Google's Nano Banana (Gemini 2.5 Flash Image). Google's
// DeepMind marketing for this model: "locks onto your facial features, skin
// tone, and expression before making any change." Best-in-class for hair /
// beard edits where the face must stay recognisable.
//
// Post-pass: cdingram/face-swap on Replicate (buffalo_l + inswapper_128).
// Takes the edit output + the original selfie, pastes the original face's
// geometry onto the new haircut, blends. ~$0.01/img, ~4s.
//
// Net cost: Nano Banana Flash ($0.039) + face swap ($0.01) ≈ $0.05 / twin
// vs Kontext Max $0.08 — CHEAPER AND BETTER.
const EDIT_MODEL = 'google/nano-banana';         // primary — Gemini 2.5 Flash Image
const SWAP_MODEL = 'cdingram/face-swap';         // identity-lock post-pass

/**
 * Generate the Maximized Twin — ONE hero change, identity-locked.
 *
 * Architecture:
 *   Stage 1: pick the single hero change from brief.improve. Hair > Beard >
 *            other grooming. Skin is NEVER the hero and is never sent to the
 *            edit model. (Flux/Nano Banana both smooth skin as a side effect
 *            — which is how we got "uglier/older" outputs.)
 *   Stage 2: call Nano Banana with a descriptor-first prompt that positively
 *            preserves face/bones/age so the model clamps identity.
 *   Stage 3: face-swap post-pass using the ORIGINAL selfie as the face
 *            source. This is the geometric identity guarantee — no prompt
 *            can drift the face when we literally paste the original face
 *            geometry back at the end.
 *
 * Returns { url, editUrl, prompt, seed, heroChange, model, intermediateUrls }.
 */
export async function maximize({ imageBase64, brief }) {
  const improve = Array.isArray(brief?.improve) ? brief.improve : [];

  // Rank fixes: hair(0) > beard(1) > other-grooming(2). Skin(3) filtered out.
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

  // Stage 1+2 — primary edit via Nano Banana
  const editUrl = await runEditWithRetry({ imageDataUri: inputDataUri, prompt });

  // Stage 3 — face-swap original → edit (identity guarantee)
  let finalUrl = editUrl;
  try {
    finalUrl = await runFaceSwap({
      editedUrl:   editUrl,
      originalUri: inputDataUri,
    });
  } catch (e) {
    // If the face-swap post-pass fails, serve the edit as-is rather than
    // error the whole scan. Identity will drift slightly but user still
    // sees a maximized twin.
    console.warn('[maximize] face-swap post-pass failed:', String(e?.message ?? e));
  }

  return {
    url:              finalUrl,
    editUrl,
    prompt,
    seed,
    heroChange,
    model:            EDIT_MODEL,
    intermediateUrls: [],
  };
}

/**
 * Classify an improve item so we can rank it:
 *   0 = HAIR  (hero if present)
 *   1 = BEARD (hero if hair absent)
 *   2 = OTHER grooming (brows, teeth, glasses, lashes)
 *   3 = SKIN — never sent to the model
 */
function classify(s) {
  const x = String(s || '').toLowerCase();
  if (/\b(hair(?!\s*line)|fade|crop|cut|hairline|fringe|buzz|taper|undercut|quiff|pomp|part|bangs)\b/.test(x)) return 0;
  if (/\b(beard|stubble|goatee|moustache|facial hair)\b/.test(x)) return 1;
  if (/\b(brow|eyebrow|teeth|whiten|glasses|frame|lash)\b/.test(x)) return 2;
  return 3; // skin / tone / pore / blemish → drop
}

/**
 * Descriptor-first prompt. Four ordered beats per the community-validated
 * Nano Banana hair-swap template (Skywork + multiple Reddit threads):
 *
 *   1. Subject naming        — "The person in this photo"
 *   2. The ONE change        — "Give them [hero grooming change]"
 *   3. Positive preserve     — list what must stay the same (not negation)
 *   4. Lighting/background   — keep everything else identical
 *
 * KEY — "apparent age" listed in the preserve clause. This is the measured
 * fix for Flux/Gemini's +2y male age-drift bias (arxiv 2502.03420): by
 * positively preserving age, the model clamps to the source age instead
 * of defaulting older.
 */
function buildPrompt(heroChange) {
  return (
    `The person in this photo. Give them ${heroChange}. ` +
    `Match their head shape exactly. ` +
    `Keep the same face, skin tone, skin texture, jawline, nose shape, ` +
    `eye shape, eye colour, eyebrows, lips, expression, apparent age, ` +
    `and ethnicity — all exactly as in the original. ` +
    `Keep the same lighting, same background, same framing, same camera ` +
    `angle and same pose. Natural shadows. ` +
    `Photorealistic. Do not smooth the skin. Do not age the face. ` +
    `Do not alter any facial feature other than the single change specified.`
  );
}

// ─── Stage 1+2 — primary edit ────────────────────────────────────────────────
async function runEditWithRetry({ imageDataUri, prompt }) {
  const maxAttempts = 3;
  let attempt = 0;
  while (true) {
    attempt++;
    try {
      return await runEdit({ imageDataUri, prompt });
    } catch (err) {
      const msg   = String(err?.message ?? err);
      const is429 = msg.includes('429') || msg.includes('Too Many Requests');
      if (!is429 || attempt >= maxAttempts) throw err;
      const m       = msg.match(/retry_after"?\s*:\s*(\d+)/);
      const waitSec = m ? Number(m[1]) : Math.pow(2, attempt) * 3;
      const waitMs  = Math.min(Math.max(waitSec, 3), 30) * 1000;
      console.warn(`[edit] 429, waiting ${waitMs}ms (attempt ${attempt}/${maxAttempts})`);
      await new Promise(r => setTimeout(r, waitMs));
    }
  }
}

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

// ─── Stage 3 — face-swap post-pass (GEOMETRIC identity lock) ─────────────────
// The identity guarantee no prompt can deliver. Takes:
//   - editedUrl   : the Nano Banana output (has the new hair, drifted face)
//   - originalUri : the user's actual selfie (has the correct face)
// Pastes the original face geometry onto the edited output, blends.
async function runFaceSwap({ editedUrl, originalUri }) {
  const input = {
    input_image: editedUrl,     // target (has the new hair/beard)
    swap_image:  originalUri,   // source (has the correct face)
  };
  const output = await replicate.run(SWAP_MODEL, { input });
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
