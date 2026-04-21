import Replicate from 'replicate';
import crypto from 'node:crypto';

const replicate = new Replicate({ auth: process.env.REPLICATE_API_TOKEN });

// Pro beats Max on chained edits — BFL + community benchmarks both say
// Pro accumulates less identity drift over sequential passes. Max is
// better single-shot; we're not single-shot anymore.
const MODEL = 'black-forest-labs/flux-kontext-pro';

/**
 * Generate the Maximized Twin as a THREE-PASS CHAIN — one BFL-canonical
 * Kontext edit per fix, each pass taking the previous output as input.
 *
 *   docs.bfl.ai/guides/prompting_guide_kontext_i2i
 *
 * BFL's own guide, verbatim:
 *   "Complex transformations often require multiple steps. Break dramatic
 *    changes into sequential edits for better control. Make one change
 *    at a time."
 *
 * HUGE UX WIN of the chain:
 *   The 3 intermediate images are the FIX CARD images. The hero shows the
 *   cumulative "all 3 fixes applied" transformation; each fix card shows
 *   the state after the Nth fix was applied. User taps a card and the
 *   image loads INSTANTLY — no extra Flux call, no wait. 3 Flux calls
 *   total for the entire report: hero + all 3 fix previews.
 *
 * Returns:
 *   {
 *     url:               final cumulative hero (= intermediateUrls[2])
 *     intermediateUrls:  [after fix 1, after fixes 1+2, after all 3 fixes]
 *     seeds:             [s1, s2, s3]  (deterministic)
 *     prompts:           the three pass prompts (for debugging)
 *   }
 */
export async function maximize({ imageBase64, brief }) {
  // BFL allows up to ~2–3 edits per call safely, but for maximum consistency
  // we cap at 3 single-zone items and chain them. GPT's brief.improve is the
  // canonical source; callers should pass the array derived from the 3 fixes.
  const improve = Array.isArray(brief?.improve) && brief.improve.length > 0
    ? brief.improve.slice(0, 3)
    : defaultImprove();

  // Pad to exactly 3 items so the chain always does 3 passes. This keeps
  // the fix-card slot mapping stable on the Flutter side.
  while (improve.length < 3) {
    improve.push(defaultImprove()[improve.length]);
  }

  const prompts = improve.map(buildPassPrompt);
  const seeds   = improve.map((_, i) =>
    deterministicSeed(imageBase64, `pass${i + 1}`));

  const urls = [];
  let currentInputDataUri = `data:image/jpeg;base64,${imageBase64}`;

  for (let i = 0; i < 3; i++) {
    const outputUrl = await runKontext({
      imageDataUri: currentInputDataUri,
      prompt:       prompts[i],
      seed:         seeds[i],
    });
    urls.push(outputUrl);
    currentInputDataUri = outputUrl; // CHAIN — next pass uses this output
  }

  return {
    url:              urls[2],   // final = hero
    intermediateUrls: urls,      // [after fix1, after fix1+2, after all 3]
    seeds,
    prompts,
  };
}

/**
 * Default improve list used when GPT didn't return one. Three single-zone
 * items, ordered skin → eyes/rested → hair so that each pass builds on a
 * stable foundation. (Skin changes lighting cues that eye fixes key off;
 * hair is the most visually dominant so it lands last.)
 */
function defaultImprove() {
  return [
    'clear, healthy, even-toned skin with natural pores still visible',
    'bright, rested under-eyes with no puffiness',
    'cleanly groomed hair and eyebrows matched to the face shape',
  ];
}

/**
 * One BFL-canonical Kontext prompt per pass:
 *   1. Name the subject (no pronouns)
 *   2. State the single change
 *   3. Positive preservation clause (no "DO NOT" — BFL warns negatives can
 *      invert intent)
 *   4. Global pose/lighting/background lock
 */
function buildPassPrompt(visualChange) {
  const change = String(visualChange || '').trim();
  return `The person in this photo. Make this single change: ${change}.

Keep the exact same facial features, bone structure, face shape, jawline, nose shape, eye shape and colour, lips, ethnicity, age, and overall identity completely identical to the reference image. Natural skin texture with visible pores. Preserve the original pose, camera angle, framing, facial expression, lighting, and background. Everything not named in the change above stays pixel-identical.`;
}

async function runKontext({ imageDataUri, prompt, seed }) {
  const input = {
    prompt,
    input_image:      imageDataUri,
    aspect_ratio:     'match_input_image',
    output_format:    'png',   // BFL: png preserves skin detail vs jpg
    output_quality:   95,
    safety_tolerance: 2,
    prompt_upsampling: false,  // BFL: true silently rewrites prompt + breaks determinism
    seed,
  };
  const output = await replicate.run(MODEL, { input });
  return typeof output === 'string'
    ? output
    : (output?.url?.() ?? output?.[0] ?? String(output));
}

/**
 * Stable 32-bit unsigned seed from image bytes + a pass label. Same photo
 * always produces the same chain; different passes use different seeds
 * so Flux explores a different local basin for each edit type.
 */
function deterministicSeed(imageBase64, label) {
  const hash = crypto.createHash('md5')
    .update(imageBase64)
    .update('::')
    .update(label)
    .digest();
  return hash.readUInt32BE(0) % 2147483647;
}
