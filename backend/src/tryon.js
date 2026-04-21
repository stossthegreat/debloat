import Replicate from 'replicate';
import crypto from 'node:crypto';

const replicate = new Replicate({ auth: process.env.REPLICATE_API_TOKEN });
const MODEL = 'black-forest-labs/flux-kontext-max';

/**
 * Single-change edit on the user's face (haircut / beard / colour / glasses
 * / whatever they typed). Identity-locked per BFL's Kontext i2i guide.
 *
 *   docs.bfl.ai/guides/prompting_guide_kontext_i2i
 *
 * styleRequest is passed VERBATIM — the caller is responsible for ensuring
 * it describes a VISUAL outcome ("short squared beard, tight neckline")
 * and NOT protocol ("tretinoin 0.025% nightly, moisturize with CeraVe").
 * Flux is a text-to-image model and will render protocol text literally
 * (cream on the face, bottles in the shot). The report screen's fix card
 * sources this from the Fix.visualRequest field GPT writes specifically
 * for this purpose; the chat advisor writes it into style_request per its
 * own system-prompt rules.
 *
 * Seed: deterministic hash of image + style + category. Same input → same
 * render every run. Second tap on "See It" produces the same face,
 * eliminating the "sometimes perfect, sometimes worse" variance users hit.
 * Zero extra Replicate cost.
 */
export async function tryOn({ imageBase64, styleRequest, category }) {
  if (!styleRequest || typeof styleRequest !== 'string') {
    throw new Error('styleRequest required');
  }

  const prompt = buildPrompt({ styleRequest: styleRequest.trim(), category });
  const seed   = deterministicSeed(imageBase64, styleRequest, category);

  const input = {
    prompt,
    input_image: `data:image/jpeg;base64,${imageBase64}`,
    aspect_ratio: 'match_input_image',
    output_format: 'png',
    output_quality: 95,
    safety_tolerance: 2,
    prompt_upsampling: false,
    seed,
  };

  const output = await replicate.run(MODEL, { input });
  const url = typeof output === 'string'
    ? output
    : (output?.url?.() ?? output?.[0] ?? String(output));

  return { url, prompt, styleRequest, category, seed };
}

function buildPrompt({ styleRequest, category }) {
  // Zone hint keeps the edit localized — Kontext respects "only the X"
  // spatial constraints per BFL's i2i guide.
  const zone = zoneFor(category);
  const zoneLine = zone ? ` Only alter ${zone}.` : '';

  return `The person in this photo. Make this single change: ${styleRequest}.${zoneLine}

Keep the exact same facial features, bone structure, face shape, jawline, nose shape, eye shape and colour, eyebrows, lips, hairline, skin tone, ethnicity, age, and overall identity completely identical to the original. Natural skin texture with visible pores. Preserve the original pose, camera angle, framing, expression, and background. Everything not named in the change above stays pixel-identical.`;
}

function zoneFor(category) {
  switch (category) {
    case 'haircut':     return 'the hair on the head';
    case 'hair_color':  return 'the hair colour';
    case 'beard':
    case 'facial_hair': return 'the facial hair on the chin, jaw and upper lip';
    case 'glasses':     return 'the eyewear';
    case 'weight':      return 'the subtle distribution of facial fat (no more than 5–8% change, no bone changes)';
    default:            return '';
  }
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
