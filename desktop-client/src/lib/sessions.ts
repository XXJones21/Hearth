import { houseFetch } from './config';

/* Session records: what the house has actually said, written one turn at a
   time as it happens. The Journal (lib/journal.ts) is the curated version of
   the same conversations, and it only exists once something has been written
   up. These are the live truth, including the chat from four minutes ago. */

export type SessionRecord = {
  session_id: string;
  date: string;
  title: string;
  persona: string;
  platform: string;
  topic: string;
  turns: number;
  started_at: string;
  last_turn_at: string;
  has_transcript: boolean;
  synced: boolean;
  thought_slug?: string;
};

export async function fetchRecords(): Promise<SessionRecord[]> {
  try {
    const res = await houseFetch(`/sessions`, { cache: 'no-store' });
    if (!res.ok) return [];
    const data = (await res.json()) as { sessions?: SessionRecord[] };
    return data.sessions ?? [];
  } catch {
    // An older house without the endpoint: the rail falls back to the
    // Journal alone rather than showing an error.
    return [];
  }
}

export async function fetchRecord(
  sessionId: string,
): Promise<(SessionRecord & { chatlog: string }) | null> {
  try {
    const res = await houseFetch(`/sessions/${encodeURIComponent(sessionId)}`,
      { cache: 'no-store' },
    );
    if (!res.ok) return null;
    return (await res.json()) as SessionRecord & { chatlog: string };
  } catch {
    return null;
  }
}

/** The transcript as turns, for a preview that reads like a conversation
    rather than like a file. Mirrors the harness parser. */
export function chatlogTurns(text: string): { role: string; body: string }[] {
  const out: { role: string; body: string }[] = [];
  const parts = (text || '').split(/^###\s+(User|Assistant)\s*\([^)]*\)\s*$/m);
  for (let i = 1; i < parts.length - 1; i += 2) {
    const body = parts[i + 1].replace(/^\s*---\s*$/gm, '').trim();
    if (body) out.push({ role: parts[i].toLowerCase(), body });
  }
  return out;
}
