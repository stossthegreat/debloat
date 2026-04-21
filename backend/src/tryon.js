import Replicate from 'replicate';

const replicate = new Replicate({ auth: process.env.REPLICATE_API_TOKEN });
const MODEL = 'black-forest-labs/flux-kontext-max';

/**
 * Single-change edit on the user's face (haircut / beard / colour / glasses
 * / whatever they typed). Identity-locked per BFL's Kontext i2i guide.
 *
 *   docs.bfl.ai/guides/prompting_guide_kontext_i2i
 *
 * styleRequest is passed VERBATIM. If the user said "make my beard pink,"
 * the render shows pink beard. We don't sanitize. The identity-lock clause
 * at the bottom keeps them looking like themselves even through wild edits.
 */
export async function tryOn({ imageBase64, styleRequest, category }) {
  if (!styleRequest || typeof styleRequest !== 'string') {
    throw new Error('styleRequest required');
  }

  const prompt = buildPrompt({ styleRequest: styleRequest.trim(), category });

  const input = {
    prompt,
    input_image: `data:image/jpeg;base64,${imageBase64}`,
    aspect_ratio: 'match_input_image',
    output_format: 'png',
    output_quality: 95,
    safety_tolerance: 2,
    prompt_upsampling: false,
  };

  const output = await replicate.run(MODEL, { input });
  const url = typeof output === 'string'
    ? output
    : (output?.url?.() ?? output?.[0] ?? String(output));

  return { url, prompt, styleRequest, category };
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
