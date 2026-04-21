import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { analyse } from './analyse.js';
import { maximize } from './maximize.js';
import { tryOn } from './tryon.js';
import { chat } from './chat.js';

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
    const { imageBase64, extraImagesBase64, geometry } = req.body;
    if (!imageBase64) return res.status(400).json({ error: 'imageBase64 required' });
    const report = await analyse({
      imageBase64,
      extraImages: Array.isArray(extraImagesBase64) ? extraImagesBase64 : [],
      geometry,
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

// ── Full pipeline: analyse → maximize (3-pass chain) in one call.
// The hero is a 3-pass Flux chain — one pass per fix — and the 3
// intermediate outputs double as the fix-card preview images so the
// Flutter side doesn't need a second Flux call when the user taps a
// fix to see it. 3 Flux calls for the entire report (hero + 3 fix
// previews), not 6.
app.post('/scan', async (req, res) => {
  try {
    const { imageBase64, extraImagesBase64, geometry } = req.body;
    if (!imageBase64) return res.status(400).json({ error: 'imageBase64 required' });

    const report = await analyse({
      imageBase64,
      extraImages: Array.isArray(extraImagesBase64) ? extraImagesBase64 : [],
      geometry,
    });

    // Pull the 3 visualRequest strings straight off the fixes so the chain
    // is 1:1 with the cards. Fallback to brief.improve if any visualRequest
    // is missing (older analyse response, cache, etc).
    const chainBrief = {
      improve: (report.fixes ?? [])
        .map((f, i) => (f?.visualRequest || report?.brief?.improve?.[i] || ''))
        .map(s => s.trim())
        .filter(Boolean),
    };

    const maxed = await maximize({
      imageBase64,
      brief: chainBrief,
    });

    res.json({ report, maximized: maxed });
  } catch (err) {
    console.error('[/scan] error:', err);
    res.status(500).json({ error: err.message });
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
