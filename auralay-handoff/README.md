# Auralay handoff — Selene v1 backend

Real files. One copy button per file (GitHub raw → 📋). Each file goes at the **same path** in Auralay (mirror the `src/...` structure below into Auralay's `src/`).

## What to do

1. In Railway → Auralay service → Variables, add these:

```
ANTHROPIC_API_KEY=sk-ant-...        (probably already set)
OPENAI_API_KEY=sk-...                (probably already set, used for Whisper)
ELEVENLABS_API_KEY=...               NEW
ELEVENLABS_VOICE_ID=zrHiDhphv9ZnVXBqCLjz   Charlotte — soft sensual female
ELEVENLABS_MODEL_ID=eleven_turbo_v2_5
SELENE_CLAUDE_MODEL=claude-sonnet-4-6
SELENE_SESSION_TTL_MIN=30
```

2. In Auralay repo, run:

```bash
npm install @anthropic-ai/sdk openai axios uuid
npm install -D @types/uuid
```

3. Copy each file from this folder into Auralay at the **same path** (e.g. `auralay-handoff/src/routes/selene.ts` → `src/routes/selene.ts` in Auralay):

| Auralay file path | Source |
|---|---|
| `src/services/selene/selenePrompt.ts` | [selenePrompt.ts](src/services/selene/selenePrompt.ts) |
| `src/services/selene/seleneSession.ts` | [seleneSession.ts](src/services/selene/seleneSession.ts) |
| `src/services/selene/seleneBrain.ts` | [seleneBrain.ts](src/services/selene/seleneBrain.ts) |
| `src/services/selene/seleneVoice.ts` | [seleneVoice.ts](src/services/selene/seleneVoice.ts) |
| `src/services/selene/seleneEars.ts` | [seleneEars.ts](src/services/selene/seleneEars.ts) |
| `src/routes/selene.ts` | [selene.ts](src/routes/selene.ts) |

4. In Auralay's main app file (usually `src/index.ts` or `src/app.ts`), add this line near the other `app.use(...)` calls:

```typescript
import seleneRouter from './routes/selene';
app.use('/selene', seleneRouter);
```

5. Push to Auralay → Railway redeploys the same service → URL stays the same.

## Test it's alive

```bash
curl https://<auralay-railway-url>/selene/health
# → {"ok":true,"service":"selene"}

curl -X POST https://<auralay-railway-url>/selene/start \
  -H "Content-Type: application/json" \
  -d '{"drill":"THE_LOCK"}'
# → {"sessionId":"...","text":"...","audioBase64":"...","done":false,...}
```

If `/start` returns a non-empty `audioBase64`, Selene is breathing. Ping me with the Railway URL and I wire the Mirrorly frontend next session.

## What's in v1

- ONE drill per session (10 named drills available)
- Turn-based voice loop (record → transcribe → reason → speak)
- In-memory session store, 8 reps per session, scored
- ElevenLabs Charlotte voice (swap via env var)
- Whisper for transcription, Claude Sonnet 4.6 for reasoning

v2 adds MediaPipe face metrics. v3 adds sub-300ms backchannels + avatar.
