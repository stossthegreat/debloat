import OpenAI from 'openai';
import { toFile } from 'openai/uploads';

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

export async function transcribeApprentice(audioBuffer: Buffer, mimeType = 'audio/mp4'): Promise<string> {
  const ext = mimeType.includes('webm') ? 'webm'
    : mimeType.includes('wav') ? 'wav'
    : mimeType.includes('mpeg') ? 'mp3'
    : 'm4a';
  const file = await toFile(audioBuffer, `apprentice.${ext}`, { type: mimeType });
  const res = await openai.audio.transcriptions.create({
    file,
    model: 'whisper-1',
    language: 'en',
    response_format: 'text',
    temperature: 0.0,
  });
  return (typeof res === 'string' ? res : (res as any).text || '').trim();
}
