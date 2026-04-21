import Replicate from 'replicate';
import crypto from 'node:crypto';

const replicate = new Replicate({ auth: process.env.REPLICATE_API_TOKEN });
const MODEL = 'black-forest-labs/flux-kontext-max';

/**
 * Generate the Maximized Twin — the SAME person at their best.
 *
 * Prompt authored to Black Forest Labs' official Kontext i2i guide:
 *   docs.bfl.ai/guides/prompting_guide_kontext_i2i
 *
 * Rules the prior prompt broke (every call):
 *   - Used pronouns instead of naming the subject by visible features
 *     (BFL #1 failure cause)
 *   - Used "transform / BETTER / aspirational" verbs — BFL flags these as
 *     licence for Flux to morph identity
 *   - Wall of "DO NOT" negative prompts — Kontext does NOT support
 *     negative prompting; it can ATTEND to the forbidden concept and
 *     invert the intent ("do not enlarge eyes" can enlarge them)
 *   - Blew past the 512-token attention cap by ~3× — preservation clauses
 *     were silently dropped
 *   - Stacked 13+ edits. BFL hard cap: 2–3 per call (cumulative drift)
 *
 * Also: deterministic seed from the input image. Same photo → same render
 * every run, so we stop coin-flipping between a user's best-case and worst-
 * case Flux attractors. Zero extra Replicate cost.
 */
export async function maximize({ imageBase64, brief }) {
  const improve = Array.isArray(brief?.improve) ? brief.improve.slice(0, 3) : [];
  const prompt  = buildPrompt({ improve });
  const seed    = deterministicSeed(imageBase64);

  const input = {
    prompt,
    input_image: `data:image/jpeg;base64,${imageBase64}`,
    aspect_ratio: 'match_input_image',
    output_format: 'png',        // BFL: png avoids jpg compression artifacts on skin
    output_quality: 95,
    safety_tolerance: 2,
    prompt_upsampling: false,    // BFL: leaving true silently rewrites prompt + injects drift
    seed,
  };

  const output = await replicate.run(MODEL, { input });
  const url = typeof output === 'string'
    ? output
    : (output?.url?.() ?? output?.[0] ?? String(output));

  return { url, prompt, seed };
}

function buildPrompt({ improve }) {
  const fixes = improve.length
    ? improve.map(s => lowerFirst(String(s).trim())).filter(Boolean).join('; ')
    : 'clear healthy skin with even tone and visible natural pores; bright rested eyes with no puffiness; tidy shaped eyebrows and clean neat hair';

  // BFL canonical structure, 3 parts:
  //   1. name the subject by visible features (no pronouns)
  //   2. the specific change(s) — 2–3 max
  //   3. canonical preservation clause naming every facial landmark to lock
  return `The person in this photo. Refine only these specific improvements: ${fixes}.

Keep the exact same facial features, bone structure, face shape, jawline, nose shape, eye shape and colour, eyebrows, lips, hairline, skin tone, ethnicity, age, and overall identity completely identical to the original. Natural skin texture with visible pores. Soft natural daylight. Preserve the original pose, camera angle, framing, expression, and background. Only change the items listed above.`;
}

function lowerFirst(s) {
  if (!s) return s;
  return s.charAt(0).toLowerCase() + s.slice(1);
}

/**
 * Stable 32-bit unsigned seed derived from the input image bytes. Replicate
 * accepts any integer seed; hashing the base64 means the SAME scan always
 * produces the SAME render, without us tracking state anywhere. First 4
 * bytes of md5 → unsigned int32, mod 2^31-1 keeps it in positive-int range.
 */
function deterministicSeed(imageBase64) {
  const hash = crypto.createHash('md5').update(imageBase64).digest();
  return hash.readUInt32BE(0) % 2147483647;
}
