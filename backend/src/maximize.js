import Replicate from 'replicate';
import crypto from 'node:crypto';

const replicate = new Replicate({ auth: process.env.REPLICATE_API_TOKEN });

// Pro on every pass. Less identity drift than Max for our use case per
// BFL + community benchmarks.
const MODEL = 'black-forest-labs/flux-kontext-pro';

/**
 * Generate the Maximized Twin.
 *
 * ARCHITECTURE — why SOLO from original, not chained:
 *
 * BFL's docs say "chain" for multi-step edits, but chain accumulates
 * identity drift: pass 1 sees the original and is clean; pass 2 sees
 * the already-edited pass 1 output and treats it as reference, so it
 * drifts on top of pass 1's drift; pass 3 compounds again. Users hit
 * exactly this — "first image perfect, second image face already
 * different, third image worst." Since the HERO is the last pass in
 * a chain, users literally saw the most-drifted image as the hero.
 *
 * Fix: three SOLO calls, each from the ORIGINAL photo. Every image
 * has the same reference, so none of them drift onto each other.
 * Hero = the first solo (GPT orders fixes by impact; fix 0 is the
 * most impactful). Fix cards 0/1/2 each display their own solo.
 *
 * TRADEOFF: the hero only shows ONE visible change, not all three
 * cumulatively. That's the honest limit of Kontext — it can't land
 * three clean zone edits in one image without drifting identity.
 * One strong clean change that's unmistakably THEM beats three
 * muddy ones where the face looks off.
 *
 * RATE LIMITING: calls are sequential with ~2s pacing + retry-with-
 * backoff on 429. Replicate's free/low-credit tier throttles to 6
 * req/min; this pacing keeps us under the ceiling and retries
 * gracefully if the ceiling shifts.
 *
 * Returns:
 *   {
 *     url:               first solo (= hero, most impactful fix)
 *     intermediateUrls:  [solo 0, solo 1, solo 2]
 *     seeds, prompts
 *   }
 */
export async function maximize({ imageBase64, brief }) {
  const improve = Array.isArray(brief?.improve) && brief.improve.length > 0
    ? brief.improve.slice(0, 3)
    : defaultImprove();

  while (improve.length < 3) {
    improve.push(defaultImprove()[improve.length]);
  }

  const prompts = improve.map(buildSoloPrompt);
  const seeds   = improve.map((_, i) =>
    deterministicSeed(imageBase64, `solo${i + 1}`));

  const inputDataUri = `data:image/jpeg;base64,${imageBase64}`;

  const urls = [];
  for (let i = 0; i < 3; i++) {
    const outputUrl = await runKontextWithRetry({
      imageDataUri: inputDataUri,  // ALWAYS the original — not the previous output
      prompt:       prompts[i],
      seed:         seeds[i],
    });
    urls.push(outputUrl);
    // Pace the loop so we don't trip Replicate's 6-req/min burst cap on
    // low-credit accounts. 2.2s between calls → ~27 req/min ceiling max,
    // well under any sensible throttle and invisible to users since
    // Flux itself takes ~5s per render anyway.
    if (i < 2) await sleep(2200);
  }

  return {
    url:              urls[0],   // hero = solo 0 (most impactful fix)
    intermediateUrls: urls,      // [solo 0, solo 1, solo 2] → fix cards 0/1/2
    seeds,
    prompts,
  };
}

/**
 * Default improve list when GPT didn't return one. Ordered by visual
 * impact so the hero (solo 0) lands the biggest change.
 */
function defaultImprove() {
  return [
    'clear, healthy, even-toned skin with natural pores still visible',
    'cleanly groomed hair and eyebrows matched to the face shape',
    'bright, rested under-eyes with no puffiness',
  ];
}

/**
 * BFL-canonical Kontext prompt, positive-only preservation clause, no
 * negative prompting (BFL: negatives can invert intent).
 */
function buildSoloPrompt(visualChange) {
  const change = String(visualChange || '').trim();
  return `The person in this photo. Make this single change: ${change}.

Keep the exact same facial features, bone structure, face shape, jawline, nose shape, eye shape and colour, lips, ethnicity, age, and overall identity completely identical to the reference image. Natural skin texture with visible pores. Preserve the original pose, camera angle, framing, facial expression, lighting, and background. Everything not named in the change above stays pixel-identical.`;
}

/**
 * Flux call with retry-with-backoff on 429. Honors Replicate's
 * `retry_after` when present, otherwise backs off exponentially.
 */
async function runKontextWithRetry({ imageDataUri, prompt, seed }) {
  const maxAttempts = 3;
  let attempt = 0;
  while (true) {
    attempt++;
    try {
      return await runKontext({ imageDataUri, prompt, seed });
    } catch (err) {
      const msg    = String(err?.message ?? err);
      const is429  = msg.includes('429') || msg.includes('Too Many Requests');
      if (!is429 || attempt >= maxAttempts) throw err;

      // Try to extract "retry_after":N from Replicate's error body.
      const m = msg.match(/retry_after"?\s*:\s*(\d+)/);
      const waitSec = m ? Number(m[1]) : Math.pow(2, attempt) * 3; // 6, 12, 24
      const waitMs  = Math.min(Math.max(waitSec, 3), 30) * 1000;
      console.warn(`[flux] 429 throttled, waiting ${waitMs}ms then retrying (attempt ${attempt}/${maxAttempts})`);
      await sleep(waitMs);
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

function sleep(ms) {
  return new Promise(r => setTimeout(r, ms));
}

function deterministicSeed(imageBase64, label) {
  const hash = crypto.createHash('md5')
    .update(imageBase64)
    .update('::')
    .update(label)
    .digest();
  return hash.readUInt32BE(0) % 2147483647;
}
