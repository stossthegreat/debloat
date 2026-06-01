import { v4 as uuid } from 'uuid';

export type SeleneTurn = {
  role: 'apprentice' | 'selene';
  text: string;
  scoreDelta?: number;
  timestamp: number;
};

export type SeleneSession = {
  id: string;
  drill: string;
  turns: SeleneTurn[];
  score: number;
  createdAt: number;
  lastActiveAt: number;
};

const SESSIONS = new Map<string, SeleneSession>();
const TTL_MS = (parseInt(process.env.SELENE_SESSION_TTL_MIN || '30', 10)) * 60 * 1000;

export function createSession(drill: string): SeleneSession {
  const session: SeleneSession = {
    id: uuid(),
    drill,
    turns: [],
    score: 0,
    createdAt: Date.now(),
    lastActiveAt: Date.now(),
  };
  SESSIONS.set(session.id, session);
  return session;
}

export function getSession(id: string): SeleneSession | undefined {
  const s = SESSIONS.get(id);
  if (!s) return undefined;
  if (Date.now() - s.lastActiveAt > TTL_MS) {
    SESSIONS.delete(id);
    return undefined;
  }
  s.lastActiveAt = Date.now();
  return s;
}

export function appendTurn(id: string, turn: SeleneTurn) {
  const s = SESSIONS.get(id);
  if (!s) return;
  s.turns.push(turn);
  if (turn.scoreDelta) s.score = Math.min(100, Math.max(0, s.score + turn.scoreDelta));
  s.lastActiveAt = Date.now();
}

export function endSession(id: string) {
  SESSIONS.delete(id);
}

setInterval(() => {
  const now = Date.now();
  for (const [id, s] of SESSIONS.entries()) {
    if (now - s.lastActiveAt > TTL_MS) SESSIONS.delete(id);
  }
}, 5 * 60 * 1000);
