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

// THE signature axis — the sunken hollow beneath the cheekbones. General
// slimming without the cheek hollow is NOT a debloat render (v46
// postmortem: a render passed on slim+ident yet the cheek area stayed
// flat — user: "your cheek area hollows and it's not in this image").
const HOLLOW_PASS_SCORE = 4;

// ...and must stay at least this recognisable (0-10, judged against the
// ORIGINAL selfie, ignoring hair/beard/clothing). Below this the render
// reads as a different person — v45 postmortem: a strong debloat came
// back with a new haircut, added clothing, and a face the user didn't
// recognise as himself. Over-transformation is failure too.
const IDENT_PASS_SCORE = 6;

// The groomed base must keep the user's actual haircut (0-10 sameness,
// judged style + length vs the original selfie). Below this the groom
// pass restyled them — retry once, then skip grooming entirely.
const HAIR_PASS_SCORE = 6;

/** Ships without a re-roll only if it slims, HOLLOWS, and stays them. */
function isViable(c) {
  return !!c
    && c.slim   >= VERIFY_PASS_SCORE
    && c.hollow >= HOLLOW_PASS_SCORE
    && c.ident  >= IDENT_PASS_SCORE;
}

/** Rank: viable first, then deepest cheek hollow, then leanest, then identity. */
function rankCandidate(c) {
  return (isViable(c) ? 1000 : 0) + c.hollow * 20 + c.slim * 5 + c.ident;
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
  // v48 — heroChange NO LONGER drives a hair restyle. The old glow-up
  // system injected "give them <a modern haircut>" into the groom pass,
  // which flatly contradicted "do not switch haircuts" in the same
  // prompt — the model obeyed the explicit order and kept shipping
  // renders with brand-new haircuts (v45 fringe, v47 side-part on a
  // buzzed head). The groom pass now only POLISHES what's there. The
  // heroChange string survives purely as response metadata for the app.
  const improve = Array.isArray(brief?.improve) ? brief.improve : [];
  const heroChange = improve.map(s => String(s || '').trim()).find(s => s.length > 0)
    ?? 'a freshly groomed, debloated version of themselves';

  const seed         = deterministicSeed(imageBase64);
  const inputDataUri = `data:image/jpeg;base64,${imageBase64}`;
  const t0           = Date.now();

  console.log(`[maximize] verified pipeline — polish-only groom`);

  // ── PASS A · grooming ────────────────────────────────────────────────────
  // Polish only: skin cleanup + tidy THEIR OWN hair and beard. Guarded by
  // a hair-fidelity check — if the model swaps the haircut anyway, retry
  // once, and if it swaps again, skip grooming and debloat the raw selfie
  // (fidelity beats polish; the debloat prompts preserve their real hair).
  let groomedUrl = null;
  try {
    groomedUrl = await runWithRetry(
      () => runEdit({ imageDataUri: inputDataUri, prompt: groomPrompt() }),
      { label: 'groom', maxAttempts: 2, retryAll: true, capWaitSec: 3 },
    );
    const hair = await scoreHair(inputDataUri, groomedUrl);
    if (hair >= 0 && hair < HAIR_PASS_SCORE) {
      console.warn(`[maximize] groom swapped the haircut (hair ${hair}) — retrying once`);
      const retryUrl  = await runEdit({ imageDataUri: inputDataUri, prompt: groomPrompt() });
      const retryHair = await scoreHair(inputDataUri, retryUrl);
      if (retryHair < 0 || retryHair >= HAIR_PASS_SCORE) {
        groomedUrl = retryUrl;
      } else {
        console.warn(`[maximize] groom retry swapped hair again (hair ${retryHair}) — skipping groom, using raw selfie`);
        groomedUrl = null;
      }
    }
    if (groomedUrl) console.log(`[maximize] groom ok: ${Date.now() - t0}ms`);
  } catch (err) {
    groomedUrl = null;
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
    .map(s => ({ url: s.value, slim: -1, hollow: -1, ident: -1 }));
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
  console.log(`[maximize] candidate scores: [${candidates.map(c => `slim ${c.slim}/hollow ${c.hollow}/ident ${c.ident}`).join('; ')}] at ${Date.now() - t0}ms`);

  let best = candidates[0] ?? null;

  // ── RE-ROLLS · keep rolling until a candidate passes ALL gates ───────────
  // Up to three extra rolls inside the time budget. Prompt choice per
  // roll: if the best so far slims and stays them but lacks the hollow
  // (the common miss), deepen THAT render with the hollow-only prompt;
  // otherwise start clean from the groomed base with the twin framing.
  // Never deepen a failed render — compounding garbage was how a puffy
  // candidate could snowball.
  for (let roll = 1; roll <= 3 && !isViable(best) && Date.now() - t0 < TIME_BUDGET_MS; roll++) {
    try {
      const deepen =
        !!best && best.slim >= VERIFY_PASS_SCORE && best.ident >= IDENT_PASS_SCORE;
      const url = await withTimeout(
        runEdit({
          imageDataUri: deepen ? best.url : baseImage,
          prompt:       deepen ? HOLLOW_FOCUS : DEBLOAT_TWIN,
        }),
        40_000,
      );
      const scores = await scoreRender(inputDataUri, baseImage, url);
      console.log(`[maximize] re-roll ${roll} (${deepen ? 'deepen' : 'fresh'}): slim ${scores.slim}/hollow ${scores.hollow}/ident ${scores.ident} at ${Date.now() - t0}ms`);
      const cand = { url, ...scores };
      if (!best || rankCandidate(cand) > rankCandidate(best)) best = cand;
    } catch (err) {
      console.warn(`[maximize] re-roll ${roll} failed: ${String(err?.message ?? err).slice(0, 120)}`);
    }
  }

  // ── FLOOR · a render that scored as not-slimmer NEVER ships ──────────────
  // v50 postmortem: with no floor, "ship the least-bad candidate" sent a
  // user a face that scored as puffy/unchanged. If after every roll the
  // best still isn't clearly slimmer and recognisable, ship the groomed
  // base instead — no debloat beats anti-debloat, and the app's GENERATE
  // retry gives the dice another spin.
  // A -1 means the referee itself failed (OpenAI down), not a bad render
  // — in that case ship blind rather than silently downgrade every
  // render to grooming-only for the length of an outage.
  if (best && best.slim >= 0 && (best.slim < 2 || (best.ident >= 0 && best.ident < 5))) {
    console.warn(`[maximize] FLOOR: rejecting best (slim ${best.slim}/hollow ${best.hollow}/ident ${best.ident}) — shipping groomed base`);
    best = null;
  }

  // Ship the strongest verified render; grooming-only beats erroring, and
  // only a total wipeout of every pass throws.
  const finalUrl = best?.url ?? groomedUrl;
  if (!finalUrl) throw new Error('maximize: every pass failed');
  console.log(`[maximize] done in ${Date.now() - t0}ms — slim ${best?.slim ?? 'n/a'} / hollow ${best?.hollow ?? 'n/a'} / ident ${best?.ident ?? 'n/a'}`);

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

// PASS A — polish only. NO restyle instruction of any kind (v48: the old
// "give them <heroChange>" line ordered a new haircut and contradicted
// the keep-your-hair clause — the model obeyed the order every time).
function groomPrompt() {
  return (
    `Edit this photo. Keep the EXACT same haircut, hair length, and ` +
    `hairline — do not restyle the hair, only make it look clean, ` +
    `freshly washed, and neatly tidied. ` +
    `Give them clean, clear, healthy skin with even tone — no acne, no ` +
    `blemishes, no redness, no visible pores — but keep natural skin ` +
    `texture (not airbrushed, not plastic, not smoothed). ` +
    `If they have facial hair, keep the same beard exactly as it is, ` +
    `just neatly groomed with clean lines and a tight neckline. ` +
    `Groomed eyebrows, no stragglers. ` +
    `Do not add, remove, or change any clothing. ` +
    `Keep the face shape, expression, lighting, background, framing, ` +
    `and pose exactly the same. They must stay instantly recognisable ` +
    `— improve them, do not replace them. Photorealistic.`
  );
}

// PASS B candidate 1 — the weight-loss narrative. The sunken cheeks are
// named FIRST and hardest: they are THE signature of a debloated face
// ("sunken"/"curves inward" is structural wording — never "shadowed",
// see the v42 rule above).
const DEBLOAT_NARRATIVE =
  `Edit this photo. Show this exact same person after they lost 30 ` +
  `pounds of water weight and fat, with all of the loss showing in ` +
  `their face and neck. ` +
  `The most important change: their cheeks are now VISIBLY SUNKEN — ` +
  `the skin below each cheekbone curves clearly inward, hollow like a ` +
  `lean fashion model's cheeks, with high prominent cheekbones above. ` +
  `The lower cheeks and the area around the mouth are lean and drawn ` +
  `inward — absolutely no puffiness there. ` +
  `Even if they have a beard, the sunken hollow above the beard line ` +
  `must be clearly visible. ` +
  `On top of that: one sharp clean jawline from ear to chin, a firm ` +
  `tight neck with no fullness under the chin, and fresh flat ` +
  `under-eyes with no puffiness or bags. ` +
  `Their whole face looks narrower, sharper, more angular, drained of ` +
  `all bloat — sharper cheekbones, sharper jaw, a sharper face — ` +
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
  `same expression — but with a dramatically leaner face. Above all, ` +
  `the twin's cheeks are VISIBLY SUNKEN: the skin below each cheekbone ` +
  `curves clearly inward, hollow like a lean fashion model's cheeks, ` +
  `with high prominent cheekbones above, and the area around the ` +
  `mouth lean and drawn inward with zero puffiness. Plus a sharp ` +
  `clean jawline from ear to chin, a firm tight neck with no fullness ` +
  `under the chin, and completely flat under-eyes. ` +
  `Anyone who knows this person must instantly recognise the twin as ` +
  `them — identical face, just leaner. ` +
  `Nothing painted or drawn on the skin — clean, evenly lit, natural. ` +
  `Same room, same lighting, same framing, same pose. Do not add, ` +
  `remove, or change any clothing. ` +
  `Photorealistic — a real unedited photo.`;

// RE-ROLL — hollow-focused. Runs when the candidates slimmed the face
// but the cheek area stayed flat (the common miss). One job only: put
// in the missing sunken hollow, touch nothing else.
const HOLLOW_FOCUS =
  `Edit this photo. One change only: make the cheeks visibly SUNKEN. ` +
  `The skin below each cheekbone must curve clearly inward — a deep ` +
  `natural hollow, like a lean fashion model with no fat in their ` +
  `cheeks — with high prominent cheekbones above, and the area around ` +
  `the mouth lean and drawn inward. If they have a beard, the sunken ` +
  `hollow above the beard line must be clearly visible. ` +
  `This is a real structural change to the face — nothing ` +
  `painted or drawn on the skin, no darkened areas, just genuinely ` +
  `hollow cheeks with clean, evenly lit skin. ` +
  `Keep everything else exactly the same: same person, same eyes, ` +
  `nose, lips, age, hairstyle, facial hair, expression, clothing, ` +
  `lighting, background, framing, and pose. ` +
  `Photorealistic — a real unedited photo.`;

// ─── VERIFY · vision referee ─────────────────────────────────────────────────
// One gpt-4o-mini call scores a candidate on THREE axes:
//   slim   — how much leaner the face is vs the groomed base (IMAGE 2),
//            so hair/beard changes can't confuse the comparison.
//   hollow — THE signature: is there a clearly visible sunken hollow in
//            the cheeks beneath the cheekbones? Scored on the candidate
//            alone; general slimming can't stand in for it.
//   ident  — is this still recognisably the person in the ORIGINAL selfie
//            (IMAGE 1), ignoring hairstyle / facial hair / clothing.
// Returns -1s on any failure so a broken referee can never sink a good
// render.
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
              'IMAGE 3 is an AI edit that should show the same face slimmer with sunken cheeks. ' +
              'Score three things about IMAGE 3. ' +
              '(1) "slim": compared to IMAGE 2, how much slimmer and leaner is the face — ' +
              'cheek fullness, jawline sharpness, fullness under the chin, under-eye puffiness, ' +
              'and fullness around the mouth. ' +
              'If the face looks the same, or FULLER or puffier anywhere, slim = 0. ' +
              '0 = no visible change or puffier, 3 = clearly visible slimming, 6 = strong slimming, ' +
              '10 = dramatic transformation. ' +
              '(2) "hollow": looking at IMAGE 3 alone, is there a clearly visible sunken ' +
              'hollow in the cheeks just below the cheekbones — the skin curving inward ' +
              'like a lean model\'s cheeks? Judge the hollow specifically, not overall slimness. ' +
              '0 = cheeks flat or full, 4 = visible hollow, 7 = strong clear hollow, ' +
              '10 = deep dramatic model-like hollow. ' +
              '(3) "ident": ignoring hairstyle, facial hair, and clothing, is the face in ' +
              'IMAGE 3 still recognisably the SAME PERSON as IMAGE 1 — same eyes, nose, ' +
              'lips, bone character, age, ethnicity? ' +
              '10 = unmistakably the same person, 6 = same person with minor drift, ' +
              '3 = looks like a relative, 0 = a different person. ' +
              'Respond with JSON only: {"slim": <integer 0-10>, "hollow": <integer 0-10>, "ident": <integer 0-10>}',
          },
          // 'high' detail — at 'low' (512px) the referee couldn't reliably
          // see cheek hollows and let a puffy render score as slimmed.
          { type: 'image_url', image_url: { url: originalImage, detail: 'high' } },
          { type: 'image_url', image_url: { url: baseImage,     detail: 'high' } },
          { type: 'image_url', image_url: { url: candidateUrl,  detail: 'high' } },
        ],
      }],
      response_format: { type: 'json_object' },
      temperature: 0,
      max_tokens: 60,
    }), 15_000);
    const parsed = JSON.parse(r.choices[0]?.message?.content ?? '{}');
    return {
      slim:   Number.isFinite(parsed.slim)   ? parsed.slim   : -1,
      hollow: Number.isFinite(parsed.hollow) ? parsed.hollow : -1,
      ident:  Number.isFinite(parsed.ident)  ? parsed.ident  : -1,
    };
  } catch (err) {
    console.warn(`[maximize] verifier failed: ${String(err?.message ?? err).slice(0, 120)}`);
    return { slim: -1, hollow: -1, ident: -1 };
  }
}

// ─── VERIFY · hair-fidelity check on the groomed base ────────────────────────
// The debloat candidates inherit whatever hair the groomed base has, so a
// haircut swap here poisons every downstream render. Scores 0-10 how much
// the haircut (style + length, not neatness) matches the original selfie.
// Returns -1 on failure so a broken check never blocks the pipeline.
async function scoreHair(originalImage, groomedUrl) {
  try {
    const r = await withTimeout(openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [{
        role: 'user',
        content: [
          {
            type: 'text',
            text:
              'IMAGE 1 is an original selfie. IMAGE 2 is an AI-groomed version that was ' +
              'supposed to keep the exact same haircut. ' +
              'Score 0-10 how much the HAIRCUT in IMAGE 2 matches IMAGE 1 — same style, ' +
              'same length, same hairline. Ignore neatness, ignore the face, ignore ' +
              'facial hair. ' +
              '10 = same haircut, 6 = same haircut slightly neater or fuller, ' +
              '3 = noticeably different style or length, 0 = completely different haircut. ' +
              'Respond with JSON only: {"hair": <integer 0-10>}',
          },
          { type: 'image_url', image_url: { url: originalImage, detail: 'low' } },
          { type: 'image_url', image_url: { url: groomedUrl,    detail: 'low' } },
        ],
      }],
      response_format: { type: 'json_object' },
      temperature: 0,
      max_tokens: 30,
    }), 15_000);
    const hair = JSON.parse(r.choices[0]?.message?.content ?? '{}').hair;
    return Number.isFinite(hair) ? hair : -1;
  } catch (err) {
    console.warn(`[maximize] hair check failed: ${String(err?.message ?? err).slice(0, 120)}`);
    return -1;
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
