import Replicate from 'replicate';
import OpenAI from 'openai';
import crypto from 'node:crypto';

const replicate = new Replicate({ auth: process.env.REPLICATE_API_TOKEN });
const openai    = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

// ─────────────────────────────────────────────────────────────────────────────
//  THE MAXED + DEBLOATED TWIN — verified-render pipeline
// ─────────────────────────────────────────────────────────────────────────────
// The hero render shows the user their best self: the grooming glow-up they
// always had — fresh hair, clear skin, neat facial hair — AND their face
// drained of bloat (de-puffed, sharper jaw, hollowed cheeks). Both at once.
//
// WHY A MULTI-PASS, SELF-CHECKING PIPELINE (v45)
// ----------------------------------------------
// Replicate's google/nano-banana exposes ONLY prompt / image_input /
// aspect_ratio / output_format. No seed, no guidance, no edit-strength
// knob. The model is stochastic AND heavily identity-locked on faces, so
// a single-shot edit "works sik" one run and barely moves the next —
// exactly the inconsistency users hit in v40-v44. No prompt wording fixes
// a dice roll. What fixes it is checking the dice:
//
//   PASS A  groom the original (hair / skin / beard) — this edit family
//           has landed reliably since v1; it never carried the risk.
//   PASS B  fire TWO debloat edits on the groomed base CONCURRENTLY,
//           with two different framings (weight-loss narrative + the
//           "identical twin, 30 lbs lighter" framing that releases the
//           model's identity lock).
//   VERIFY  gpt-4o-mini vision scores each candidate 0-10 on how much
//           leaner the face actually got vs the base (~$0.001, ~2-4s).
//   RE-ROLL if nothing scores ≥ VERIFY_PASS_SCORE and there is time
//           budget left, roll once more, then ship the best scorer.
//
// Worst case ≈ 4 nano-banana runs ≈ $0.16 / render — fine for a paid
// feature whose entire pitch is this one image.
//
// WHY NO FACE-SWAP
// ----------------
// The original pipeline's Stage-3 face-swap pasted the ORIGINAL selfie's
// face back onto the edit — reverting the debloat AND the skin cleanup.
// Identity is held by nano-banana's native subject-lock plus prompts that
// keep eyes / nose / lips / age / ethnicity fixed.
const EDIT_MODEL = 'google/nano-banana';

// A debloat candidate must score at least this (0-10) to ship without a
// re-roll. 3 = "clearly visible slimming" per the verifier rubric.
const VERIFY_PASS_SCORE = 3;

// ...and must stay at least this recognisable (0-10, judged against the
// ORIGINAL selfie, ignoring hair/beard/clothing). Below this the render
// reads as a different person — v45 postmortem: a strong debloat came
// back with a new haircut, added clothing, and a face the user didn't
// recognise as himself. Over-transformation is failure too.
const IDENT_PASS_SCORE = 6;

/** A candidate ships without a re-roll only if it slims AND stays them. */
function isViable(c) {
  return !!c && c.slim >= VERIFY_PASS_SCORE && c.ident >= IDENT_PASS_SCORE;
}

/** Rank: viable first, then leanest, identity as tiebreak. */
function rankCandidate(c) {
  return (isViable(c) ? 1000 : 0) + c.slim * 10 + c.ident;
}

// Stop launching new Replicate work after this much wall time — the
// Flutter client aborts at 160s, so everything must land well before.
const TIME_BUDGET_MS = 90_000;

/**
 * Generate the hero twin — grooming glow-up + verified facial debloat.
 *
 * `brief.improve` (from the GPT analysis) supplies the single grooming hero
 * change (hair > beard > other grooming). Skin is always cleaned up and the
 * face is always de-bloated on top, regardless of the brief.
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

  const seed         = deterministicSeed(imageBase64);
  const inputDataUri = `data:image/jpeg;base64,${imageBase64}`;
  const t0           = Date.now();

  console.log(`[maximize] verified pipeline — hero="${heroChange}"`);

  // ── PASS A · grooming ────────────────────────────────────────────────────
  // The reliable half. If it somehow fails after retries, debloat the raw
  // selfie instead of erroring — the debloat IS the product.
  let groomedUrl = null;
  try {
    groomedUrl = await runWithRetry(
      () => runEdit({ imageDataUri: inputDataUri, prompt: groomPrompt(heroChange) }),
      { label: 'groom', maxAttempts: 2, retryAll: true, capWaitSec: 3 },
    );
    console.log(`[maximize] groom ok: ${Date.now() - t0}ms`);
  } catch (err) {
    console.warn(`[maximize] groom failed — debloating the raw selfie: ${String(err?.message ?? err).slice(0, 120)}`);
  }
  const baseImage = groomedUrl ?? inputDataUri;

  // ── PASS B · two concurrent debloat candidates ───────────────────────────
  const settled = await Promise.allSettled(
    [DEBLOAT_NARRATIVE, DEBLOAT_TWIN].map(p =>
      withTimeout(runEdit({ imageDataUri: baseImage, prompt: p }), 45_000)),
  );
  let candidates = settled
    .filter(s => s.status === 'fulfilled')
    .map(s => ({ url: s.value, slim: -1, ident: -1 }));
  settled
    .filter(s => s.status === 'rejected')
    .forEach(s => console.warn(`[maximize] debloat candidate failed: ${String(s.reason?.message ?? s.reason).slice(0, 120)}`));

  // ── VERIFY · vision referee scores slimming AND identity ─────────────────
  // Slimness is judged against the groomed base (so hair/beard changes
  // can't confuse it); identity is judged against the ORIGINAL selfie,
  // ignoring hair/beard/clothing — a strong debloat that turns the user
  // into a different person is just as failed as a weak one.
  candidates = await Promise.all(
    candidates.map(async c => ({ ...c, ...(await scoreRender(inputDataUri, baseImage, c.url)) })),
  );
  candidates.sort((a, b) => rankCandidate(b) - rankCandidate(a));
  console.log(`[maximize] candidate scores: [${candidates.map(c => `slim ${c.slim}/ident ${c.ident}`).join('; ')}] at ${Date.now() - t0}ms`);

  let best = candidates[0] ?? null;

  // ── RE-ROLL · no candidate is both slim enough AND still them ────────────
  if (!isViable(best) && Date.now() - t0 < TIME_BUDGET_MS) {
    try {
      const url    = await withTimeout(runEdit({ imageDataUri: baseImage, prompt: DEBLOAT_TWIN }), 45_000);
      const scores = await scoreRender(inputDataUri, baseImage, url);
      console.log(`[maximize] re-roll score: slim ${scores.slim}/ident ${scores.ident} at ${Date.now() - t0}ms`);
      const cand = { url, ...scores };
      if (!best || rankCandidate(cand) > rankCandidate(best)) best = cand;
    } catch (err) {
      console.warn(`[maximize] re-roll failed: ${String(err?.message ?? err).slice(0, 120)}`);
    }
  }

  // Ship the strongest verified render; grooming-only beats erroring, and
  // only a total wipeout of every pass throws.
  const finalUrl = best?.url ?? groomedUrl;
  if (!finalUrl) throw new Error('maximize: every pass failed');
  console.log(`[maximize] done in ${Date.now() - t0}ms — slim ${best?.slim ?? 'n/a'} / ident ${best?.ident ?? 'n/a'}`);

  return {
    url:              finalUrl,
    editUrl:          finalUrl,
    prompt:           DEBLOAT_NARRATIVE,
    seed,
    heroChange,
    model:            EDIT_MODEL,
    intermediateUrls: [],
  };
}

/**
 * Generic retry wrapper for Replicate calls. With retryAll (used here),
 * retries EVERY error. Backoff honours a Retry-After hint if present, else
 * exponential, capped at capWaitSec.
 */
async function runWithRetry(fn, { label, maxAttempts = 3, retryAll = false, capWaitSec = 30 } = {}) {
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
      const waitSec    = retryAfter ? Number(retryAfter[1]) : Math.pow(2, attempt);
      const waitMs     = Math.min(Math.max(waitSec, 2), capWaitSec) * 1000;
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

// ─────────────────────────────────────────────────────────────────────────────
//  PROMPTS
// ─────────────────────────────────────────────────────────────────────────────
// HARD-LEARNED RULES:
//   · v42: NEVER use shadow/contour/darkness words ("shadowed hollow",
//     "carve", "dark") — the model takes them literally and PAINTS
//     grey-black contour smudges onto the cheeks. A real user got black
//     patches drawn on his face.
//   · v43: anatomical command-lists ("reduce buccal fat", "reshape the
//     geometry") barely move the needle — surgical face-proportion orders
//     read as an identity threat and get resisted. Community guides use
//     "no jawline reduction" as a KEEPER phrase, i.e. slimming is easy
//     for the model when asked the natural way.
//   · What works: a plain weight-loss story with numbers (documented
//     nano-banana case: "make this guy slimmer — 210 to 177 lbs" → full
//     transformation), and the "identical twin" framing, the community's
//     standard unlock when the identity lock resists a structural edit.
//   · One job per pass: mixing grooming + debloat in one prompt let the
//     model "spend" the edit on hair and skip the face.

// PASS A — grooming only. The ask that has landed reliably since v1.
function groomPrompt(heroChange) {
  return (
    `Edit this photo. Give them ${heroChange}. ` +
    `Make them look their absolute best: ` +
    `clean, clear, healthy skin with even tone — no acne, no blemishes, ` +
    `no redness, no visible pores — but keep natural skin texture ` +
    `(not airbrushed, not plastic, not smoothed). ` +
    `Give them a freshly-cut, cleanly-styled version of THEIR OWN ` +
    `hairstyle — sharpen and tidy what they already have, do not switch ` +
    `them to a different haircut. ` +
    `If they have facial hair, keep it neatly groomed with clean lines ` +
    `and a tight neckline. Groomed eyebrows, no stragglers. ` +
    `Do not add, remove, or change any clothing. ` +
    `Keep the face shape, expression, lighting, background, framing, ` +
    `and pose exactly the same. They must stay instantly recognisable ` +
    `— improve them, do not replace them. Photorealistic.`
  );
}

// PASS B candidate 1 — the weight-loss narrative.
const DEBLOAT_NARRATIVE =
  `Edit this photo. Show this exact same person after they lost 30 ` +
  `pounds of water weight and fat, with all of the loss showing in ` +
  `their face and neck. ` +
  `Their face is now much slimmer and leaner: tight slim cheeks that ` +
  `sit close against the bone with a natural lean hollow beneath the ` +
  `cheekbones, high visible cheekbones, one sharp clean jawline from ` +
  `ear to chin, a firm tight neck with no fullness under the chin, ` +
  `and fresh flat under-eyes with no puffiness or bags. ` +
  `Their whole face looks narrower, lighter, drained of all bloat — ` +
  `like the "after" photo of a dramatic weight-loss transformation. ` +
  `The change must be big and clearly visible, but completely ` +
  `natural: real lean facial structure, clean evenly-lit skin with ` +
  `nothing painted or drawn on it. ` +
  `Keep the hairstyle, facial hair, clothing, expression, lighting, ` +
  `background, framing, and pose exactly the same. Photorealistic.`;

// PASS B candidate 2 — the identical-twin framing. Asking for a *twin*
// releases the model's identity lock (it no longer has to preserve "the
// same person's" proportions) while every named feature keeps the twin
// visually identical. Community-standard unlock for structural edits.
const DEBLOAT_TWIN =
  `Replace this person with their identical twin who weighs 30 pounds ` +
  `less. The twin looks exactly like them — same eyes, same nose, same ` +
  `lips, same skin tone, same age, same hairstyle, same facial hair, ` +
  `same expression — but with a dramatically leaner face: tight slim ` +
  `cheeks with a natural lean hollow beneath high visible cheekbones, ` +
  `a sharp clean jawline from ear to chin, a firm tight neck with no ` +
  `fullness under the chin, and completely flat under-eyes. ` +
  `Anyone who knows this person must instantly recognise the twin as ` +
  `them — identical face, just leaner. ` +
  `Nothing painted or drawn on the skin — clean, evenly lit, natural. ` +
  `Same room, same lighting, same framing, same pose. Do not add, ` +
  `remove, or change any clothing. ` +
  `Photorealistic — a real unedited photo.`;

// ─── VERIFY · vision referee ─────────────────────────────────────────────────
// One gpt-4o-mini call scores a candidate on BOTH axes:
//   slim  — how much leaner the face is vs the groomed base (IMAGE 2),
//           so hair/beard changes can't confuse the comparison.
//   ident — is this still recognisably the person in the ORIGINAL selfie
//           (IMAGE 1), ignoring hairstyle / facial hair / clothing.
// Returns {slim: -1, ident: -1} on any failure so a broken referee can
// never sink a good render.
async function scoreRender(originalImage, baseImage, candidateUrl) {
  try {
    const r = await withTimeout(openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [{
        role: 'user',
        content: [
          {
            type: 'text',
            text:
              'IMAGE 1 is the original selfie. IMAGE 2 is a groomed version of it. ' +
              'IMAGE 3 is an AI edit that should show the same face slimmer. ' +
              'Score two things about IMAGE 3. ' +
              '(1) "slim": compared to IMAGE 2, how much slimmer and leaner is the face — ' +
              'cheek fullness, hollowness under the cheekbones, jawline sharpness, ' +
              'fullness under the chin, under-eye puffiness. ' +
              '0 = no visible change, 3 = clearly visible slimming, 6 = strong slimming, ' +
              '10 = dramatic transformation. ' +
              '(2) "ident": ignoring hairstyle, facial hair, and clothing, is the face in ' +
              'IMAGE 3 still recognisably the SAME PERSON as IMAGE 1 — same eyes, nose, ' +
              'lips, bone character, age, ethnicity? ' +
              '10 = unmistakably the same person, 6 = same person with minor drift, ' +
              '3 = looks like a relative, 0 = a different person. ' +
              'Respond with JSON only: {"slim": <integer 0-10>, "ident": <integer 0-10>}',
          },
          { type: 'image_url', image_url: { url: originalImage, detail: 'low' } },
          { type: 'image_url', image_url: { url: baseImage,     detail: 'low' } },
          { type: 'image_url', image_url: { url: candidateUrl,  detail: 'low' } },
        ],
      }],
      response_format: { type: 'json_object' },
      temperature: 0,
      max_tokens: 40,
    }), 15_000);
    const parsed = JSON.parse(r.choices[0]?.message?.content ?? '{}');
    return {
      slim:  Number.isFinite(parsed.slim)  ? parsed.slim  : -1,
      ident: Number.isFinite(parsed.ident) ? parsed.ident : -1,
    };
  } catch (err) {
    console.warn(`[maximize] verifier failed: ${String(err?.message ?? err).slice(0, 120)}`);
    return { slim: -1, ident: -1 };
  }
}

/** Hard timeout for best-effort calls. */
function withTimeout(promise, ms) {
  return Promise.race([
    promise,
    new Promise((_, rej) =>
      setTimeout(() => rej(new Error(`timed out after ${ms}ms`)), ms)),
  ]);
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
  const url = extractUrl(output);
  // A non-http "url" ([object Object], empty, etc.) means the model
  // returned something unusable — throw so the caller can retry or
  // discard instead of shipping garbage the app can't load.
  if (typeof url !== 'string' || !url.startsWith('http')) {
    throw new Error(`runEdit: unusable output url: ${String(url).slice(0, 80)}`);
  }
  return url;
}

// ─── helpers ─────────────────────────────────────────────────────────────────
function extractUrl(output) {
  if (typeof output === 'string') return output;
  if (Array.isArray(output))      return String(output[0]);
  if (output && typeof output.url === 'function') {
    const u = output.url();
    return typeof u === 'string' ? u : (u && u.href) ? u.href : String(u);
  }
  if (output && typeof output.url === 'string')   return output.url;
  return String(output);
}

function deterministicSeed(imageBase64) {
  const hash = crypto.createHash('md5').update(imageBase64).digest();
  return hash.readUInt32BE(0) % 2147483647;
}
