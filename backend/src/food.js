import OpenAI from 'openai';

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

/**
 * FOOD SCAN — GPT-4o Vision reads a meal photo and grades it for FACIAL
 * BLOAT. Debloat OS is not a calorie counter; it answers one question:
 * "will this meal puff my face up tomorrow?" Sodium is the hero number
 * (water retention → facial puffiness), with a supporting grid of
 * bloat-relevant grades.
 *
 * Output (strict JSON, consumed by FoodAnalysis.fromJson on the client):
 * {
 *   name:           "Avocado Toast",
 *   verdict:        "Great choice" | "Moderate" | "High bloat risk",
 *   overallScore:   86,            // 0..100, higher = less bloating
 *   sodiumMg:       320,           // estimated sodium for the portion shown
 *   sodiumPctDaily: 13,            // % of a 2300mg daily limit
 *   puffinessRisk:  "Low" | "Moderate" | "High",
 *   stats: [
 *     { label:"Bloating Potential", score:20, rating:"good" },
 *     { label:"Inflammation",       score:30, rating:"good" },
 *     { label:"Digestion",          score:80, rating:"great" },
 *     { label:"Skin Health",        score:60, rating:"moderate" },
 *     { label:"Fluid Balance",      score:70, rating:"good" },
 *     { label:"Sodium Risk",        score:45, rating:"moderate" }
 *   ],
 *   betterSwap: { from:"White bread", to:"Whole grain bread" } | null,
 *   tip: "One sentence, actionable, debloat-focused."
 * }
 *
 * Score semantics: EACH stat's `score` is its natural 0..100 value and
 * `rating` ('bad'|'moderate'|'good'|'great') is what the client colours
 * off — because a LOW "Bloating Potential" (20) is GOOD while a HIGH
 * "Digestion" (80) is GOOD. The model decides the rating per metric so
 * the client never has to know which direction is good.
 */
export async function analyseFood({ imageBase64 }) {
  const systemPrompt = `You are the FOOD LENS inside Debloat OS — a facial-debloat app. You look at a photo of food or a drink and grade it for ONE thing: how much facial bloat and puffiness it will cause. You are not a calorie tracker and never mention calories, weight loss, or dieting. Your entire lens is water retention, inflammation, digestion, and skin — the things that decide whether the user's face looks puffy or drained tomorrow morning.

## WHAT DRIVES FACIAL BLOAT (your grading model)
- SODIUM is the #1 driver. High-sodium food (processed, cured, fast food, soy sauce, cheese, bread, restaurant meals) pulls water into the face → puffy cheeks, undereye bags, soft jaw the next morning. Estimate sodium honestly for the PORTION shown.
- REFINED CARBS + SUGAR spike insulin → water retention + inflammation.
- ALCOHOL dehydrates then rebounds → morning face bloat.
- DAIRY + GLUTEN are common inflammation triggers for many people.
- ANTI-BLOAT foods: high-water vegetables, lean protein, potassium-rich foods (banana, avocado, leafy greens), water. These score WELL.

## SCORING
- overallScore: 0..100, HIGHER = LESS bloating / better for a lean face. A grilled-chicken-and-greens plate ≈ 85-95. A double cheeseburger + fries ≈ 15-30. Salted snacks / instant noodles ≈ 10-25.
- sodiumMg: realistic estimate for the visible portion, in milligrams.
- sodiumPctDaily: round(sodiumMg / 2300 * 100).
- puffinessRisk: "Low" if the meal is clean, "Moderate" mid, "High" for salty/processed/fried/alcohol.
- verdict: 2-3 words. "Great choice" / "Solid pick" / "Moderate" / "High bloat risk" / "Puffiness bomb".

## THE STAT GRID — return EXACTLY these six, in this order:
1. "Bloating Potential"  — LOW score is GOOD (low = won't bloat). rating good when score<=35, moderate 36-60, bad >60.
2. "Inflammation"        — LOW score is GOOD.
3. "Digestion"           — HIGH score is GOOD (easy to digest). rating great >=80, good 60-79, moderate 40-59, bad <40.
4. "Skin Health"         — HIGH score is GOOD (supports clear skin).
5. "Fluid Balance"       — HIGH score is GOOD (helps drain / potassium-rich, hydrating).
6. "Sodium Risk"         — LOW score is GOOD (low = little sodium).
For each, set rating to one of "bad" | "moderate" | "good" | "great" based on how GOOD that metric reads for a lean, drained face (NOT off the raw number — a low Sodium Risk is "good", a high Digestion is "great").

## BETTER SWAP
If there's an obvious lower-bloat substitution, return betterSwap {from,to} (short, 1-4 words each). Otherwise null.

## TIP
One short sentence, actionable, debloat-framed. e.g. "Drink 500ml water before bed to flush the sodium."

## IF THE PHOTO ISN'T FOOD
If the image clearly contains no food or drink, return name:"No food detected" and overallScore:0 and empty-ish stats (all score 0, rating "moderate"), betterSwap null, tip "Point the camera at a meal or drink."

## EXACT OUTPUT SHAPE — copy this structure precisely. Use the keys "label", "score" (a number 0-100), and "rating" for EVERY stat. Never leave a score null or 0 for real food.
{
  "name": "Fried potato wedges",
  "verdict": "High bloat risk",
  "overallScore": 30,
  "sodiumMg": 950,
  "sodiumPctDaily": 41,
  "puffinessRisk": "High",
  "stats": [
    { "label": "Bloating Potential", "score": 72, "rating": "bad" },
    { "label": "Inflammation", "score": 60, "rating": "moderate" },
    { "label": "Digestion", "score": 45, "rating": "moderate" },
    { "label": "Skin Health", "score": 38, "rating": "bad" },
    { "label": "Fluid Balance", "score": 40, "rating": "moderate" },
    { "label": "Sodium Risk", "score": 80, "rating": "bad" }
  ],
  "betterSwap": { "from": "Fried wedges", "to": "Baked potato" },
  "tip": "Drink 500ml water before bed to flush the sodium."
}

Output MUST be valid JSON with EXACTLY this shape. No markdown. No text outside the object.`;

  const userPrompt = 'Grade this meal/drink for facial bloat. Output the JSON per spec above. Estimate sodium for the portion actually shown in the photo.';

  const response = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages: [
      { role: 'system', content: systemPrompt },
      {
        role: 'user',
        content: [
          { type: 'text', text: userPrompt },
          {
            type: 'image_url',
            image_url: { url: `data:image/jpeg;base64,${imageBase64}`, detail: 'high' },
          },
        ],
      },
    ],
    response_format: { type: 'json_object' },
    temperature: 0.4,
    max_tokens: 1200,
  });

  const raw = response.choices[0]?.message?.content;
  if (!raw) throw new Error('analyseFood: empty completion content');
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    const tail = raw.length > 240 ? '…' + raw.slice(-240) : raw;
    console.error(`[food] JSON parse failed (${raw.length} chars). Tail: ${tail}`);
    throw new Error(`analyseFood: invalid JSON from model — ${err.message}`);
  }
  return normalize(parsed);
}

// Defensive normalization so the client always gets a well-formed shape
// even when the model drifts on field names/structure. This is the fix for
// the "grid shows all zeros" bug: GPT-4o sometimes returns the stats under
// different keys (`value` instead of `score`, `name` instead of `label`),
// as an object keyed by label instead of an array, or omits a couple. We
// tolerate all of that and, as a last resort, DERIVE any still-missing
// score from the overall/sodium read so the grid is never blank.
function normalize(p) {
  const clamp = (n, lo, hi) => Math.max(lo, Math.min(hi, Math.round(Number(n) || 0)));
  const RATINGS = new Set(['bad', 'moderate', 'good', 'great']);

  // Each metric: canonical label, key words to fuzzy-match on, and whether
  // a LOW score is the good outcome (drives derived rating + fallback).
  const METRICS = [
    { label: 'Bloating Potential', keys: ['bloat'],                    lowGood: true  },
    { label: 'Inflammation',       keys: ['inflam'],                   lowGood: true  },
    { label: 'Digestion',          keys: ['digest'],                   lowGood: false },
    { label: 'Skin Health',        keys: ['skin'],                     lowGood: false },
    { label: 'Fluid Balance',      keys: ['fluid', 'hydrat', 'water'], lowGood: false },
    { label: 'Sodium Risk',        keys: ['sodium', 'salt'],           lowGood: true  },
  ];

  // Flatten whatever the model gave us into a list of {label, raw}.
  const rawStats = [];
  const src = p.stats ?? p.breakdown ?? p.metrics ?? p.grid;
  if (Array.isArray(src)) {
    for (const s of src) {
      if (s && typeof s === 'object') {
        const lbl = String(s.label ?? s.name ?? s.title ?? s.metric ?? '');
        rawStats.push({ label: lbl, raw: s });
      }
    }
  } else if (src && typeof src === 'object') {
    // object keyed by label → { "Bloating Potential": 72 | {score,rating} }
    for (const [k, v] of Object.entries(src)) {
      rawStats.push({ label: k, raw: (v && typeof v === 'object') ? v : { score: v } });
    }
  }

  const readScore = (o) => {
    const cand = o.score ?? o.value ?? o.points ?? o.rating_score ?? o.number;
    const n = Number(cand);
    return Number.isFinite(n) ? clamp(n, 0, 100) : null;
  };
  const readRating = (o) => {
    const r = String(o.rating ?? o.level ?? o.severity ?? o.grade ?? '').toLowerCase();
    return RATINGS.has(r) ? r : null;
  };

  const overall = clamp(p.overallScore ?? p.score ?? p.overall, 0, 100);

  const stats = METRICS.map((m) => {
    // fuzzy match: first raw stat whose label contains any key word.
    const hit = rawStats.find((rs) => {
      const l = rs.label.toLowerCase();
      return m.keys.some((k) => l.includes(k));
    });
    let score = hit ? readScore(hit.raw) : null;
    let rating = hit ? readRating(hit.raw) : null;

    // Fallback: derive a plausible score from the overall read so the grid
    // never renders as blank zeros. lowGood metrics invert the overall.
    if (score == null) {
      score = m.lowGood ? clamp(100 - overall, 0, 100) : overall;
    }
    // Derive rating from the score + direction if the model didn't give one.
    if (rating == null) {
      const good = m.lowGood ? (100 - score) : score;
      rating = good >= 80 ? 'great' : good >= 60 ? 'good' : good >= 40 ? 'moderate' : 'bad';
    }
    return { label: m.label, score, rating };
  });

  const sodiumMg = clamp(p.sodiumMg ?? p.sodium ?? p.sodiumMilligrams, 0, 20000);
  const sodiumPctDaily = (p.sodiumPctDaily ?? p.sodiumPercent) != null
    ? clamp(p.sodiumPctDaily ?? p.sodiumPercent, 0, 999)
    : clamp((sodiumMg / 2300) * 100, 0, 999);

  let risk = String(p.puffinessRisk ?? p.risk ?? p.bloatRisk ?? '').trim();
  if (!/^(low|moderate|high)$/i.test(risk)) risk = 'Moderate';
  risk = risk.charAt(0).toUpperCase() + risk.slice(1).toLowerCase();

  let swap = null;
  const rawSwap = p.betterSwap ?? p.swap ?? p.substitution;
  if (rawSwap && typeof rawSwap === 'object') {
    const from = String(rawSwap.from ?? rawSwap.instead ?? '').trim();
    const to = String(rawSwap.to ?? rawSwap.better ?? '').trim();
    if (from && to) swap = { from, to };
  }

  const name = String(
    p.name ?? p.food ?? p.dish ?? p.meal ?? p.foodName ?? p.title ?? 'Your meal'
  ).trim().slice(0, 60);

  return {
    name: name || 'Your meal',
    verdict: String(p.verdict ?? p.summary ?? 'Moderate').trim().slice(0, 32) || 'Moderate',
    overallScore: overall,
    sodiumMg,
    sodiumPctDaily,
    puffinessRisk: risk,
    stats,
    betterSwap: swap,
    tip: String(p.tip ?? p.advice ?? '').trim().slice(0, 200),
  };
}
