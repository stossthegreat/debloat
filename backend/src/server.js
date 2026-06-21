import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { analyse } from './analyse.js';
import { maximize } from './maximize.js';
import { tryOn } from './tryon.js';
import { chat } from './chat.js';
import { rate } from './rate.js';
import { rizzReply, rizzChat } from './rizz.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname  = path.dirname(__filename);
const publicDir  = path.resolve(__dirname, '..', 'public');

const app = express();
app.use(cors());
app.use(express.json({ limit: '25mb' }));
app.use(express.static(publicDir));

app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'mirror-backend' });
});

// ── Vision analysis: GPT-4o takes image(s) + CV measurements → returns brief + advice
app.post('/analyse', async (req, res) => {
  try {
    const { imageBase64, extraImagesBase64, geometry, isPro } = req.body;
    if (!imageBase64) return res.status(400).json({ error: 'imageBase64 required' });
    const report = await analyse({
      imageBase64,
      extraImages: Array.isArray(extraImagesBase64) ? extraImagesBase64 : [],
      geometry,
      isPro: isPro === true,   // v279 — Pro → gpt-4o, free → gpt-4o-mini
    });
    res.json(report);
  } catch (err) {
    console.error('[/analyse] error:', err);
    res.status(500).json({ error: err.message });
  }
});

// ── Maximize: Flux Kontext takes image + improvement brief → returns maximized image URL
app.post('/maximize', async (req, res) => {
  try {
    const { imageBase64, brief, geometry } = req.body;
    if (!imageBase64) return res.status(400).json({ error: 'imageBase64 required' });
    const result = await maximize({ imageBase64, brief, geometry });
    res.json(result);
  } catch (err) {
    console.error('[/maximize] error:', err);
    res.status(500).json({ error: err.message });
  }
});

// ── Full pipeline: analyse + maximize in one call.
//
// Resilience policy: analyse failure = 500 (nothing to show), but maximize
// failure after retries = 200 with an empty hero URL. The client renders
// the report and surfaces a "Generate hero image" retry button that hits
// /maximize directly. The user sees their analysis even when Replicate is
// having a bad day — which was the #1 cause of "Server hiccup" reports.
//
// Every stage is timed and logged so failures are diagnosable from server
// logs alone — no guessing at which of the three API calls died.
app.post('/scan', async (req, res) => {
  const t0 = Date.now();
  try {
    const { imageBase64, extraImagesBase64, geometry, isPro } = req.body;
    if (!imageBase64) return res.status(400).json({ error: 'imageBase64 required' });

    const extras = Array.isArray(extraImagesBase64) ? extraImagesBase64 : [];
    console.log(`[/scan] start — imageBytes=${Math.round(imageBase64.length * 0.75)} extras=${extras.length} pro=${isPro === true}`);

    // ── Stage 1: analyse (gpt-4o for Pro, gpt-4o-mini for free) ──────────
    const tAnalyse = Date.now();
    let report;
    try {
      report = await analyse({ imageBase64, extraImages: extras, geometry, isPro: isPro === true });
    } catch (err) {
      console.error(`[/scan] analyse FAILED after ${Date.now() - tAnalyse}ms:`, err);
      return res.status(500).json({
        error: err.message,
        stage: 'analyse',
      });
    }
    console.log(`[/scan] analyse ok: ${Date.now() - tAnalyse}ms fixes=${report?.fixes?.length ?? 0}`);

    // ── Stage 2: maximize (Nano Banana + face-swap) — OPTIONAL ──────────────
    // If this whole stage fails we still return the report with an empty
    // hero url and a structured error the client can surface as "Tap to
    // generate". No more "Server hiccup" on an otherwise-valid scan.
    const chainBrief = {
      improve: (report.fixes ?? [])
        .map((f, i) => (f?.visualRequest || report?.brief?.improve?.[i] || ''))
        .map(s => s.trim())
        .filter(Boolean),
    };

    const tMax = Date.now();
    let maxed;
    try {
      maxed = await maximize({ imageBase64, brief: chainBrief });
      console.log(`[/scan] maximize ok: ${Date.now() - tMax}ms url=${(maxed?.url || '').slice(0, 80)}`);
    } catch (err) {
      const elapsed = Date.now() - tMax;
      const msg = String(err?.message ?? err);
      console.error(`[/scan] maximize FAILED after ${elapsed}ms — returning report-only: ${msg}`);
      maxed = {
        url:              '',
        editUrl:          '',
        prompt:           '',
        seed:             0,
        heroChange:       '',
        model:            '',
        intermediateUrls: [],
        error:            msg,
      };
    }

    console.log(`[/scan] DONE ${Date.now() - t0}ms`);
    res.json({ report, maximized: maxed });
  } catch (err) {
    console.error(`[/scan] unexpected error after ${Date.now() - t0}ms:`, err);
    res.status(500).json({ error: err.message, stage: 'unexpected' });
  }
});

// ── Chat: face-aware advisor. Text reply + optional inline tryon render.
app.post('/chat', async (req, res) => {
  try {
    const { messages, face } = req.body;
    if (!Array.isArray(messages) || messages.length === 0) {
      return res.status(400).json({ error: 'messages[] required' });
    }
    const result = await chat({ messages, face: face ?? {} });
    res.json(result);
  } catch (err) {
    console.error('[/chat] error:', err);
    res.status(500).json({ error: err.message });
  }
});

// ── Rizz: dating-text coach. Totally separate from /chat (the face
// doctor). The client posts what she said + vibe + scenario, this
// runs the RIZZ system prompt on gpt-4o, returns 3 ranked reply
// options as { replies: [{ text, tag }, ... ] }. No face geometry,
// no archetypes, no tryon — just text in, text out.
app.post('/rizz/reply', async (req, res) => {
  try {
    const { her, vibe, ctx, scenario, previous, imageBase64, mySide } = req.body || {};
    // `previous` is an optional array of {text, tag} objects sent by
    // the quick-action chips ("More heat", "Funnier", "Make a move").
    // When present, rizzReply switches into TRANSFORM MODE and
    // rewrites those three replies instead of generating cold.
    const prev = Array.isArray(previous)
      ? previous
          .filter(p => p && typeof p.text === 'string')
          .slice(0, 3)
          .map(p => ({ text: p.text, tag: typeof p.tag === 'string' ? p.tag : '' }))
      : [];
    // `imageBase64` is the bare-bytes-as-base64 of a chat screenshot.
    // When present, rizzReply uses the gpt-4o-vision path — the model
    // reads the iMessage UI directly, no OCR involved.
    const result = await rizzReply({
      her:         typeof her      === 'string' ? her      : '',
      vibe:        typeof vibe     === 'string' ? vibe     : 'auto',
      ctx:         typeof ctx      === 'string' ? ctx      : '',
      scenario:    typeof scenario === 'string' ? scenario : '',
      previous:    prev,
      imageBase64: typeof imageBase64 === 'string' ? imageBase64 : undefined,
      mySide:      typeof mySide    === 'string' ? mySide    : undefined,
    });
    res.json(result);
  } catch (err) {
    console.error('[/rizz/reply] error:', err);
    res.status(500).json({ error: err.message });
  }
});

// ── Rizz chat: free-form conversational mentor. Same RIZZ persona as
// /rizz/reply but for "ask me anything" questions on the Chat with
// Mirrorly surface. Returns { reply: string }.
app.post('/rizz/chat', async (req, res) => {
  try {
    const { messages, imageBase64 } = req.body || {};
    const result = await rizzChat({
      messages,
      imageBase64: typeof imageBase64 === 'string' ? imageBase64 : undefined,
    });
    res.json(result);
  } catch (err) {
    console.error('[/rizz/chat] error:', err);
    res.status(500).json({ error: err.message });
  }
});

// ── Rate: GPT-4o Vision honest looks rating. Companion to geometry —
// the vision-based half of the two-score moat. Returns null on refusal,
// client falls back to geometry-only in that case.
app.post('/rate', async (req, res) => {
  try {
    const { imageBase64 } = req.body;
    if (!imageBase64) return res.status(400).json({ error: 'imageBase64 required' });
    const result = await rate({ imageBase64 });
    if (result == null) {
      // Distinct 200 with {refused:true} so the client can degrade cleanly
      // without treating this as a hard error.
      return res.json({ refused: true });
    }
    res.json(result);
  } catch (err) {
    console.error('[/rate] error:', err);
    res.status(500).json({ error: err.message });
  }
});

// ── Try-on: "show me with a beard / fade / glasses / etc"
app.post('/tryon', async (req, res) => {
  try {
    const { imageBase64, styleRequest, category, geometry } = req.body;
    if (!imageBase64)   return res.status(400).json({ error: 'imageBase64 required' });
    if (!styleRequest)  return res.status(400).json({ error: 'styleRequest required' });
    const result = await tryOn({ imageBase64, styleRequest, category, geometry });
    res.json(result);
  } catch (err) {
    console.error('[/tryon] error:', err);
    res.status(500).json({ error: err.message });
  }
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`[mirror-backend] listening on :${PORT}`);
});
