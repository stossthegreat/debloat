import Anthropic from '@anthropic-ai/sdk';
import { SELENE_SYSTEM_PROMPT, buildSeleneUserTurn, buildSeleneOpener } from './selenePrompt';
import type { SeleneSession } from './seleneSession';

const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
const MODEL = process.env.SELENE_CLAUDE_MODEL || 'claude-sonnet-4-6';

export async function seleneOpener(drill: string): Promise<string> {
  const res = await anthropic.messages.create({
    model: MODEL,
    max_tokens: 200,
    system: [
      { type: 'text', text: SELENE_SYSTEM_PROMPT, cache_control: { type: 'ephemeral' } },
    ],
    messages: [{ role: 'user', content: buildSeleneOpener(drill) }],
  });
  return extractText(res);
}

export async function seleneReply(
  session: SeleneSession,
  apprenticeSaid: string
): Promise<{ text: string; scoreDelta: number }> {
  const history = session.turns.slice(-8).map(t => ({
    role: (t.role === 'apprentice' ? 'user' : 'assistant') as 'user' | 'assistant',
    content: t.text,
  }));

  const userTurn = buildSeleneUserTurn({
    drill: session.drill,
    turnNumber: session.turns.filter(t => t.role === 'apprentice').length + 1,
    currentScore: session.score,
    apprenticeSaid,
  });

  const res = await anthropic.messages.create({
    model: MODEL,
    max_tokens: 200,
    system: [
      { type: 'text', text: SELENE_SYSTEM_PROMPT, cache_control: { type: 'ephemeral' } },
    ],
    messages: [...history, { role: 'user', content: userTurn }],
  });

  const text = extractText(res);
  const scoreDelta = inferScoreDelta(text);
  return { text, scoreDelta };
}

function extractText(res: Anthropic.Messages.Message): string {
  const block = res.content.find(b => b.type === 'text') as Anthropic.Messages.TextBlock | undefined;
  return (block?.text || '').trim();
}

function inferScoreDelta(seleneSaid: string): number {
  const text = seleneSaid.toLowerCase();
  if (/good\.|that landed|clean|yes\./.test(text)) return 10;
  if (/again\.|stay there|hold it/.test(text)) return 5;
  if (/no\.|don't|stop/.test(text)) return -3;
  return 0;
}
