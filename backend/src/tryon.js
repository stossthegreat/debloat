import Replicate from 'replicate';
import crypto from 'node:crypto';

const replicate = new Replicate({ auth: process.env.REPLICATE_API_TOKEN });

// Same model choice as /maximize — see that file's header for the full
// research rationale. In one line: Kontext was drifting identity; Nano
// Banana + face-swap post-pass is the architecturally-correct fix for
// "same person, ONE grooming change, zero age drift."
const EDIT_MODEL = 'google/nano-banana';     // primary edit
const SWAP_MODEL = 'cdingram/face-swap';     // identity-lock post-pass

/**
 * Single-change edit on the user's face — the "SEE IT ON YOUR FACE" CTA
 * on each fix card + chat-advisor visual suggestions fire this.
 *
 * Same two-stage architecture as /maximize:
 *   Stage 1 — Nano Banana edit with a descriptor-first prompt that
 *             positively preserves age (fixes Flux's +2.18y age bias).
 *   Stage 2 — face-swap from the ORIGINAL selfie onto the edit output.
 *             This is the geometric identity guarantee — the face in the
 *             final render is literally from the user's own photo.
 *
 * styleRequest is passed VERBATIM — caller is schema-constrained to a
 * single-zone visual phrase (see chat.js system prompt + report screen
 * Fix.visualRequest). Protocol strings ("apply tretinoin nightly") are
 * never sent here; they'd be rendered literally.
 *
 * Seed: deterministic hash of image + style + category so the same
 * request produces the same render on retry.
 */
export async function tryOn({ imageBase64, styleRequest, category }) {
  if (!styleRequest || typeof styleRequest !== 'string') {
    throw new Error('styleRequest required');
  }

  const normalizedCategory = normalizeCategory(category);
  const prompt = buildPrompt({
    styleRequest: styleRequest.trim(),
    category:     normalizedCategory,
  });
  const seed = deterministicSeed(imageBase64, styleRequest, normalizedCategory);
  const inputDataUri = `data:image/jpeg;base64,${imageBase64}`;

  // Stage 1 — primary edit
  const editUrl = await runEditWithRetry({ imageDataUri: inputDataUri, prompt });

  // Stage 2 — face-swap the original face back onto the edited output
  let finalUrl = editUrl;
  try {
    finalUrl = await runFaceSwap({
      editedUrl:   editUrl,
      originalUri: inputDataUri,
    });
  } catch (e) {
    console.warn('[tryon] face-swap post-pass failed:', String(e?.message ?? e));
  }

  return {
    url:      finalUrl,
    editUrl,
    prompt,
    styleRequest,
    category: normalizedCategory,
    seed,
    model:    EDIT_MODEL,
  };
}

function normalizeCategory(c) {
  const allowed = new Set([
    'haircut', 'hair_color',
    'beard', 'facial_hair',
    'eyebrow',
    'skin',
    'glasses',
    'weight',
    'teeth',
  ]);
  return allowed.has(c) ? c : 'generic';
}

/**
 * Descriptor-first prompt with positive preserve clause, same structure
 * as /maximize. The sibling-lock sentence calls out the ONE adjacent
 * zone most likely to drift for this category — since Nano Banana also
 * has some tendency to "also groom" sibling zones when running a
 * haircut/beard edit.
 */
function buildPrompt({ styleRequest, category }) {
  // Strip imperative leading words so the request reads as an end-state
  // ("a 5mm squared beard") not a command ("apply a 5mm squared beard").
  const change = styleRequest.replace(/^(make\s+|apply\s+|give\s+(me|him|her|them)\s+)/i, '');
  const sibling = siblingLock(category);

  return (
    `The person in this photo. Give them ${change}. ` +
    `Match their head shape exactly. ` +
    `Keep the same face, skin tone, skin texture, jawline, nose shape, ` +
    `eye shape, eye colour, eyebrows, lips, expression, apparent age, ` +
    `and ethnicity — all exactly as in the original. ` +
    (sibling ? `${sibling} ` : '') +
    `Keep the same lighting, same background, same framing, same camera ` +
    `angle and same pose. Natural shadows. ` +
    `Photorealistic. Do not smooth the skin. Do not age the face. ` +
    `Do not alter any facial feature other than the single change specified.`
  );
}

function siblingLock(category) {
  switch (category) {
    case 'haircut':
    case 'hair_color':
      return 'The facial hair stays exactly as in the original.';
    case 'beard':
    case 'facial_hair':
      return 'The hair on the head stays exactly as in the original.';
    case 'skin':
      return 'The hair on the head and the facial hair stay exactly as in the original.';
    case 'eyebrow':
      return 'The hair on the head, facial hair, and skin stay exactly as in the original.';
    case 'glasses':
    case 'teeth':
    case 'weight':
      return 'Every other feature stays exactly as in the original.';
    default:
      return 'Every other feature stays exactly as in the original.';
  }
}

// ─── Stage 1 — primary edit ──────────────────────────────────────────────────
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
      console.warn(`[tryon] 429, waiting ${waitMs}ms (attempt ${attempt}/${maxAttempts})`);
      await new Promise(r => setTimeout(r, waitMs));
    }
  }
}

async function runEdit({ imageDataUri, prompt }) {
  const input = {
    prompt,
    image_input:   [imageDataUri],       // Nano Banana expects an array
    aspect_ratio:  'match_input_image',
    output_format: 'png',
  };
  const output = await replicate.run(EDIT_MODEL, { input });
  return extractUrl(output);
}

// ─── Stage 2 — face-swap post-pass ───────────────────────────────────────────
async function runFaceSwap({ editedUrl, originalUri }) {
  const input = {
    input_image: editedUrl,    // target (has the new feature)
    swap_image:  originalUri,  // source (has the correct face)
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

function deterministicSeed(imageBase64, styleRequest, category) {
  const hash = crypto.createHash('md5')
    .update(imageBase64)
    .update('::')
    .update(styleRequest)
    .update('::')
    .update(category ?? '')
    .digest();
  return hash.readUInt32BE(0) % 2147483647;
}
