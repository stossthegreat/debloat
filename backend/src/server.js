import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { analyse } from './analyse.js';
import { analyseFood } from './food.js';
import { maximize } from './maximize.js';

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

// ── Public legal / support pages — the URLs App Store Connect and
//    RevenueCat ask for. Clean extensionless addresses:
//      /privacy · /terms · /support
app.get('/privacy', (_req, res) => res.sendFile(path.join(publicDir, 'privacy.html')));
app.get('/terms',   (_req, res) => res.sendFile(path.join(publicDir, 'terms.html')));
app.get('/support', (_req, res) => res.sendFile(path.join(publicDir, 'support.html')));

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

// ── Food scan: GPT-4o Vision grades a meal photo for FACIAL BLOAT.
// Returns { name, verdict, overallScore, sodiumMg, sodiumPctDaily,
// puffinessRisk, stats[], betterSwap, tip }. See food.js for the shape.
app.post('/food', async (req, res) => {
  try {
    const { imageBase64 } = req.body;
    if (!imageBase64) return res.status(400).json({ error: 'imageBase64 required' });
    const result = await analyseFood({ imageBase64 });
    res.json(result);
  } catch (err) {
    console.error('[/food] error:', err);
    res.status(500).json({ error: err.message });
  }
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`[debloat-backend] listening on :${PORT}`);
});
