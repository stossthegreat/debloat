import axios from 'axios';

const VOICE_ID = process.env.ELEVENLABS_VOICE_ID || 'zrHiDhphv9ZnVXBqCLjz';
const MODEL_ID = process.env.ELEVENLABS_MODEL_ID || 'eleven_turbo_v2_5';
const API_KEY = process.env.ELEVENLABS_API_KEY!;

export async function synthesizeSelene(text: string): Promise<Buffer> {
  const res = await axios.post(
    `https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID}`,
    {
      text,
      model_id: MODEL_ID,
      voice_settings: {
        stability: 0.45,
        similarity_boost: 0.85,
        style: 0.35,
        use_speaker_boost: true,
      },
    },
    {
      headers: {
        'xi-api-key': API_KEY,
        'Content-Type': 'application/json',
        'Accept': 'audio/mpeg',
      },
      responseType: 'arraybuffer',
      timeout: 15000,
    }
  );
  return Buffer.from(res.data);
}
