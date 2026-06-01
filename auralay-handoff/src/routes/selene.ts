import { Router } from 'express';
import { createSession, getSession, appendTurn, endSession } from '../services/selene/seleneSession';
import { seleneOpener, seleneReply } from '../services/selene/seleneBrain';
import { synthesizeSelene } from '../services/selene/seleneVoice';
import { transcribeApprentice } from '../services/selene/seleneEars';

const router = Router();

const VALID_DRILLS = new Set([
  'THE_LOCK',
  'THE_GREETING_HOLD',
  'THE_TRIANGLE',
  'THE_END_OF_STATEMENT_LOCK',
  'THE_DOWNWARD_BREAK',
  'THE_LISTENING_GAZE',
  'THE_LAST_WORD_DROP',
  'KILL_UPTALK',
  'KILL_INTERVIEW_MODE',
  'KILL_VALIDATION_SEEKING',
]);

router.get('/health', (_req, res) => res.json({ ok: true, service: 'selene' }));

router.post('/start', async (req, res) => {
  try {
    const drill = (req.body?.drill || 'THE_LOCK').toString();
    if (!VALID_DRILLS.has(drill)) {
      return res.status(400).json({ error: `invalid drill: ${drill}` });
    }
    const session = createSession(drill);
    const text = await seleneOpener(drill);
    appendTurn(session.id, { role: 'selene', text, timestamp: Date.now() });
    const audio = await synthesizeSelene(text);
    res.json({
      sessionId: session.id,
      drill,
      text,
      audioBase64: audio.toString('base64'),
      score: session.score,
      turnNumber: 0,
      done: false,
    });
  } catch (err: any) {
    console.error('[selene/start]', err);
    res.status(500).json({ error: err?.message || 'selene start failed' });
  }
});

router.post('/turn', async (req, res) => {
  try {
    const sessionId = (req.body?.sessionId || '').toString();
    const session = getSession(sessionId);
    if (!session) return res.status(404).json({ error: 'session not found or expired' });

    let audioBuffer: Buffer | null = null;
    let mimeType = 'audio/mp4';
    if (req.body?.audioBase64) {
      audioBuffer = Buffer.from(req.body.audioBase64, 'base64');
      mimeType = req.body.mimeType || mimeType;
    } else if ((req as any).file?.buffer) {
      audioBuffer = (req as any).file.buffer;
      mimeType = (req as any).file.mimetype || mimeType;
    }
    if (!audioBuffer) return res.status(400).json({ error: 'no audio provided' });

    const apprenticeSaid = await transcribeApprentice(audioBuffer, mimeType);
    appendTurn(session.id, { role: 'apprentice', text: apprenticeSaid, timestamp: Date.now() });

    const { text, scoreDelta } = await seleneReply(session, apprenticeSaid);
    appendTurn(session.id, { role: 'selene', text, scoreDelta, timestamp: Date.now() });

    const audio = await synthesizeSelene(text);
    const apprenticeTurnCount = session.turns.filter(t => t.role === 'apprentice').length;
    const done = apprenticeTurnCount >= 8;

    res.json({
      sessionId: session.id,
      drill: session.drill,
      apprenticeTranscript: apprenticeSaid,
      text,
      audioBase64: audio.toString('base64'),
      score: session.score,
      turnNumber: apprenticeTurnCount,
      done,
    });

    if (done) endSession(session.id);
  } catch (err: any) {
    console.error('[selene/turn]', err);
    res.status(500).json({ error: err?.message || 'selene turn failed' });
  }
});

export default router;
