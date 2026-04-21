/**
 * Category Gate — turns 16 MediaPipe measurements into a SHORTLIST of advice
 * categories GPT-4o is allowed to recommend, plus the specific protocol it
 * should narrate inside that category.
 *
 * Why: without this, GPT defaults to skin/hair/beard every time because those
 * are the safest generic hits. We're sitting on 16 measurements and 14 advice
 * levers from real looksmaxxing methodology, and we let GPT use 3 of them.
 *
 * How: each category has measurement-based eligibility rules + a protocol
 * sketch grounded in published evidence (PMC/PubMed/clinical guides where
 * available, community consensus where not). GPT receives the shortlist and
 * narrates the protocol in THE MIRROR voice — but it can't invent the
 * protocol or pick a category we've blocked.
 *
 * Sources for each protocol are inline as comments — these are the same
 * sources the looksmaxxing-methodology research agent surfaced.
 */
export function computeCategoryGate(geometry) {
  const g = geometry || {};
  const eligible = {};
  const blocked = {};

  // ── HAIR_CUT ──────────────────────────────────────────────────────────
  // Always eligible. Cut is the highest-leverage zero-cost lift in the grid;
  // protocol depends on faceLengthRatio + headShape + facialThirdTop.
  eligible.HAIR_CUT = hairCut(g);

  // ── HAIR_COLOR ────────────────────────────────────────────────────────
  // Always eligible — choice depends on skin undertone (image-only signal).
  eligible.HAIR_COLOR = {
    reason: 'always available — choice driven by skin undertone visible in image (not measured)',
    protocol: 'cool undertone → ash or platinum; warm undertone → caramel or auburn; neutral → keep natural',
  };

  // ── BEARD ─────────────────────────────────────────────────────────────
  {
    const ja = g.jawAngle;
    if (ja != null && ja < 118) {
      blocked.BEARD = {
        reason: `jaw angle ${ja.toFixed(0)}° is razor-sharp (top 15%) — covering with beard hides the user's #1 visual asset`,
      };
    } else {
      eligible.BEARD = beard(g);
    }
  }

  // ── SKIN ──────────────────────────────────────────────────────────────
  // Always eligible. Perceived skin health is the strongest single
  // attractiveness predictor (Rhodes 2007 PMC) — even when bones are great,
  // the read is gated by skin clarity.
  eligible.SKIN = {
    reason: 'universal lever — perceived skin health predicts attractiveness more strongly than symmetry (Rhodes 2007)',
    protocol: 'tretinoin 0.025% 3 nights/week wk1-2 → every other night wk3-6 → nightly; sandwich-method moisturizer; mineral SPF 30+ daily AM; visible smoothing wks 8-12',
  };

  // ── EYEBROW ───────────────────────────────────────────────────────────
  // Always eligible — image-dependent specifics.
  eligible.EYEBROW = eyebrow(g);

  // ── GLASSES ───────────────────────────────────────────────────────────
  // Always eligible — face-shape mapping is deterministic.
  eligible.GLASSES = glasses(g);

  // ── BODY_COMPOSITION ──────────────────────────────────────────────────
  // Eligible only if jaw is soft AND we suspect midface softness.
  // If jaw already sharp, blocked.
  {
    const ja = g.jawAngle;
    if (ja != null && ja < 118) {
      blocked.BODY_COMP = {
        reason: `jaw already sharp at ${ja.toFixed(0)}° — body comp lever already won (jawline emerges <14% BF, user is there)`,
      };
    } else if (ja != null && ja > 128) {
      eligible.BODY_COMP = {
        reason: `jaw angle ${ja.toFixed(0)}° reads soft — body fat is the most likely lever, not bone (Phelps 2024)`,
        protocol: 'cut to <14% BF: 0.5-1% BF/week max; jawline emerges <14%, cheekbone hollows <12%; 8-12wk visible; bloat lever (cut Na <2g, alcohol 5d, hydrate 3L) shows in 72h',
      };
    }
    // 118-128 is neutral — leave undecided so GPT can call image
  }

  // ── POSTURE ───────────────────────────────────────────────────────────
  // Always eligible — forward-head posture detection is GPT's call from image.
  eligible.POSTURE = {
    reason: 'forward head posture adds visual submental softness even in lean subjects (Etalon 2024)',
    protocol: 'chin tucks 3×10/day + wall angel 3×8/day + prone cobra hold; 8-12wk; "anteface" cue at photo time (chin out + slightly up) is a 2-second visual win',
  };

  // ── TEETH ─────────────────────────────────────────────────────────────
  // Eligible if teeth might be visible (we can't tell server-side; GPT decides).
  eligible.TEETH = {
    reason: 'high-renderability win — perceived health/confidence shifts with shade',
    protocol: 'Crest 3D White strips (10-14% HP) 30min/day × 14 days; 3-6 shade lift; brush + floss baseline; flag Invisalign only if visible misalignment',
  };

  // ── PHOTO_HABITS ──────────────────────────────────────────────────────
  // Always eligible — universal lever, often the biggest hidden win.
  eligible.PHOTO_HABITS = {
    reason: 'selfies <12in cause 30% nasal breadth distortion (Derakhshan 2024 Laryngoscope) — affects every visual judgment of the face',
    protocol: 'shoot ≥36 inches with rear cam or friend; ≥50mm equivalent (portrait mode telephoto); soft light 45° above; chin tilted down 5° eyes into camera',
  };

  // ── UNDER_EYE ─────────────────────────────────────────────────────────
  // Always eligible — under-eye is image-dependent severity, GPT picks.
  eligible.UNDER_EYE = {
    reason: 'caffeine + sleep + drainage produce measurable visible improvement in 2-4wks',
    protocol: 'caffeine eye serum 5% AM+PM (2-4wk visible); cut caffeine 8h before sleep; back-sleep + extra pillow for AM drainage; 7-9h sleep target',
  };

  // ── NECKLINE ──────────────────────────────────────────────────────────
  // Determined by faceLengthRatio.
  {
    const fl = g.faceLengthRatio;
    if (fl != null && fl > 1.35) {
      eligible.NECKLINE = {
        reason: `long face ratio ${fl.toFixed(2)} — horizontal neckline shortens perceived face length`,
        protocol: 'crew neck, henley, or banded collar; avoid v-neck which adds vertical and lengthens further',
      };
    } else if (fl != null && fl < 1.2) {
      eligible.NECKLINE = {
        reason: `broad/short face ratio ${fl.toFixed(2)} — vertical neckline elongates perceived face`,
        protocol: 'v-neck or open collar with chain; avoid crew neck which emphasizes broadness',
      };
    } else {
      eligible.NECKLINE = {
        reason: 'balanced face — most necklines work; pick by personal style',
        protocol: 'default fitted crew or henley; v-neck for casual',
      };
    }
  }

  // ── ORAL_POSTURE (mewing, rebranded conservatively) ───────────────────
  // Only eligible if long-face pattern. Adult mewing has NO RCT support for
  // skeletal change (JOMS 2019, Mew struck off 2024). Sell as posture/sleep.
  {
    const fl = g.faceLengthRatio;
    if (fl != null && fl > 1.40) {
      eligible.ORAL_POSTURE = {
        reason: `long-face pattern (ratio ${fl.toFixed(2)}) — adult mewing has no RCT support for bone change, but nasal-breathing/posture prevents worsening + improves sleep`,
        protocol: 'tongue flat on palate, lips sealed, nasal breathing only; mouth taping at night (3M micropore); 2wk habit primer; FRAME AS POSTURE/BREATHING HYGIENE — never sell as jaw reshaping',
      };
    } else {
      blocked.ORAL_POSTURE = {
        reason: `face length ratio ${fl?.toFixed(2) ?? 'unknown'} not in long-face range — oral posture irrelevant lever`,
      };
    }
  }

  // ── CHEWING / MASSETER ────────────────────────────────────────────────
  // Eligible only if face is NARROW + jaw soft. Block if face already broad —
  // chewing will widen further (counter-productive).
  {
    const fwhr = g.fwhr;
    const ja = g.jawAngle;
    if (fwhr != null && fwhr >= 1.95) {
      blocked.CHEWING = {
        reason: `face already broad (FWHR ${fwhr.toFixed(2)}) — chewing widens lower face further; counter-productive`,
      };
    } else if (ja != null && ja < 120) {
      blocked.CHEWING = {
        reason: `jaw already sharp at ${ja.toFixed(0)}° — chewing adds zero visible leverage`,
      };
    } else if (fwhr != null && fwhr < 1.85 && ja != null && ja > 125) {
      eligible.CHEWING = {
        reason: `narrow face (FWHR ${fwhr.toFixed(2)}) + soft jaw (${ja.toFixed(0)}°) — bilateral masseter mass without overbroadening`,
        protocol: 'mastic or Falim gum 30 min/day, BOTH SIDES equally; 12wk; flag TMJ risk; honest disclaimer that 2024 RCT (Jung) found no significant masseter change vs control',
      };
    }
  }

  return { eligible, blocked };
}

// ──────────────────────────────────────────────────────────────────────────
// Per-category protocol functions — segregated so each can grow without
// turning computeCategoryGate() into a wall.
// ──────────────────────────────────────────────────────────────────────────

function hairCut(g) {
  const fl = g.faceLengthRatio;
  const fwhr = g.fwhr;
  const tt = g.facialThirdTop;

  // Long face — needs compression cut
  if (fl != null && fl > 1.35) {
    if (tt != null && tt > 36) {
      return {
        reason: `long face (ratio ${fl.toFixed(2)}) + high forehead (top third ${tt.toFixed(0)}%) — fringe is mandatory to compress vertical`,
        protocol: 'mid-length textured fringe (curtain or side-swept); covers upper third; never slicked-back or pompadour',
      };
    }
    return {
      reason: `long face ratio ${fl.toFixed(2)} — vertical hair drags face longer`,
      protocol: 'mid-length textured cut with side-swept fringe or curtain bangs; absolutely no pompadour, slicked-back, or quiff',
    };
  }
  // Broad / short face — needs vertical mass
  if ((fl != null && fl < 1.2) || (fwhr != null && fwhr > 1.95)) {
    return {
      reason: `broad face (ratio ${fl?.toFixed(2) ?? '?'}, FWHR ${fwhr?.toFixed(2) ?? '?'}) — needs vertical mass`,
      protocol: 'pompadour or quiff with 4-5cm height on top, tight sides or mid-fade; no fringe',
    };
  }
  // Square face
  if (fwhr != null && fwhr > 1.8 && fwhr <= 2.0) {
    return {
      reason: `square face (FWHR ${fwhr.toFixed(2)}) — needs softening texture`,
      protocol: 'messy crop or loose textured cut; no full buzz which doubles down on angularity',
    };
  }
  // Oval / default
  return {
    reason: 'balanced proportions — most cuts work; default to classic taper with texture',
    protocol: 'classic taper with 3-4cm textured top, mid-fade or scissor sides',
  };
}

function beard(g) {
  const fl = g.faceLengthRatio;
  const fwhr = g.fwhr;
  const ja = g.jawAngle;

  if (ja != null && ja > 130) {
    return {
      reason: `soft jaw at ${ja.toFixed(0)}° — squared beard rebuilds the jaw angle visually`,
      protocol: 'squared 5-8mm beard with high cheek line + tight neckline; defines jaw angle in one shave',
    };
  }
  if (fl != null && fl > 1.35) {
    return {
      reason: `long face ratio ${fl.toFixed(2)} — short stubble widens, full chin beard drags chin further down`,
      protocol: 'short stubble 3-5mm, fuller on sides lighter on chin; NEVER chin beard or goatee on this face shape',
    };
  }
  if (fwhr != null && fwhr > 1.95) {
    return {
      reason: `broad face (FWHR ${fwhr.toFixed(2)}) — anchor or pointed beard creates vertical to counter horizontal width`,
      protocol: 'anchor or ducktail beard with vertical chin emphasis',
    };
  }
  return {
    reason: 'balanced jaw + face proportions — light/medium stubble works universally',
    protocol: '3-5mm stubble or short squared beard per personal style',
  };
}

function eyebrow(g) {
  const fl = g.faceLengthRatio;
  const fwhr = g.fwhr;

  if (fl != null && fl > 1.35) {
    return {
      reason: `long face ratio ${fl.toFixed(2)} — flat horizontal brow shortens perceived face length`,
      protocol: 'flat or slight-arch brow; tweeze ONLY below the arch + the unibrow; never thread/wax full; thick > thin',
    };
  }
  if (fwhr != null && fwhr > 1.95) {
    return {
      reason: `broad face (FWHR ${fwhr.toFixed(2)}) — angled high-arch brow adds angle and breaks roundness`,
      protocol: 'angled high-arch brow; tweeze below the arch only; trim length with scissors against grain',
    };
  }
  return {
    reason: 'balanced face — slight natural arch reads masculine + youthful',
    protocol: 'natural arch with cleaned strays; thick > thin universally; never shave the top',
  };
}

function glasses(g) {
  const fl = g.faceLengthRatio;
  const fwhr = g.fwhr;
  const tt = g.facialThirdTop;

  if (fwhr != null && fwhr > 1.95 && fl != null && fl < 1.25) {
    return {
      reason: `round/broad face (FWHR ${fwhr.toFixed(2)}, ratio ${fl.toFixed(2)}) — angular frames break roundness`,
      protocol: 'square / rectangle / browline frames; AVOID round or oval which double down on roundness',
    };
  }
  if (fl != null && fl > 1.35) {
    return {
      reason: `long face ratio ${fl.toFixed(2)} — tall oversized frames add horizontal mass at midface`,
      protocol: 'tall geometric or oversized frames; D-frame or aviator; AVOID narrow rectangular',
    };
  }
  if (fwhr != null && fwhr > 1.85 && fwhr <= 2.0) {
    return {
      reason: `square face (FWHR ${fwhr.toFixed(2)}) — round frames soften the angles`,
      protocol: 'round or oval frames; AVOID square/rectangle which sharpen further',
    };
  }
  if (tt != null && tt > 36) {
    return {
      reason: `wide forehead (top third ${tt.toFixed(0)}%) — bottom-heavy aviator/D-frame balances`,
      protocol: 'aviator or D-frame with bottom emphasis; AVOID browline which adds top weight',
    };
  }
  return {
    reason: 'balanced face — most frames work; default to wayfarer or aviator',
    protocol: 'wayfarer or aviator; tinted lenses for casual / clear for editorial',
  };
}

/**
 * Format the gate result for direct injection into a GPT system prompt.
 * Returns a string ready to drop into the prompt template.
 */
export function formatGateForPrompt(gate) {
  const lines = [];
  lines.push('## YOUR ELIGIBLE CATEGORIES (pick 3, all from this list)');
  lines.push('');
  lines.push('Each entry below is a category you MAY recommend, the measurement-based reason it qualifies, and the SPECIFIC protocol you must narrate (do NOT invent generic alternatives — the protocol is grounded in measurement + evidence; you re-write it in THE MIRROR voice).');
  lines.push('');
  for (const [cat, info] of Object.entries(gate.eligible)) {
    lines.push(`• ${cat}`);
    lines.push(`    why eligible: ${info.reason}`);
    lines.push(`    protocol:     ${info.protocol}`);
    lines.push('');
  }
  if (Object.keys(gate.blocked).length > 0) {
    lines.push('## BLOCKED CATEGORIES (DO NOT RECOMMEND — these would actively hurt this user)');
    lines.push('');
    for (const [cat, info] of Object.entries(gate.blocked)) {
      lines.push(`• ${cat} — ${info.reason}`);
    }
    lines.push('');
  }
  lines.push('## SELECTION RULES');
  lines.push('- Pick 3 distinct categories from ELIGIBLE only.');
  lines.push('- Never two fixes from the same category.');
  lines.push('- Each fix\'s `action` field MUST implement the protocol shown above for that category — adapted into THE MIRROR voice but preserving the specifics (dosages, timelines, brand names, exact protocols).');
  lines.push('- If you can\'t find 3 real gaps from ELIGIBLE, return 2 fixes + 1 preservation note rather than picking from BLOCKED.');
  return lines.join('\n');
}
