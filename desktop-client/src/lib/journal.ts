import { getHttpOrigin } from './config';

export type JournalSession = {
  slug: string;
  title: string;
  date: string;
  persona: string;
  project: string;
  tags: string[];
  session_id: string;
  summary: string;
  decisions: string[];
  questions: string[];
  actions: string[];
  has_transcript: boolean;
  transcript?: string;
};

export type JournalReview = { date: string; body: string };
export type JournalSearchHit = { slug: string; snippet: string };

async function getJson<T>(path: string): Promise<T | null> {
  try {
    const res = await fetch(`${getHttpOrigin()}${path}`);
    if (!res.ok) return null;
    return (await res.json()) as T;
  } catch {
    return null;
  }
}

export async function fetchSessions(persona = ''): Promise<JournalSession[]> {
  const qs = persona ? `?persona=${encodeURIComponent(persona)}` : '';
  const data = await getJson<{ sessions: JournalSession[] }>(`/journal/sessions${qs}`);
  return data?.sessions ?? [];
}

export async function fetchSession(slug: string, transcript = false): Promise<JournalSession | null> {
  return getJson<JournalSession>(`/journal/session/${slug}${transcript ? '?transcript=1' : ''}`);
}

export async function fetchReviews(limit = 3): Promise<JournalReview[]> {
  const data = await getJson<{ reviews: JournalReview[] }>(`/journal/reviews?limit=${limit}`);
  return data?.reviews ?? [];
}

export async function fetchFacts(): Promise<string> {
  const data = await getJson<{ body: string }>('/journal/facts');
  return data?.body ?? '';
}

export async function searchJournal(q: string): Promise<JournalSearchHit[]> {
  const data = await getJson<{ results: JournalSearchHit[] }>(
    `/journal/search?q=${encodeURIComponent(q)}`,
  );
  return data?.results ?? [];
}

export type BookEntry = { t: string; d?: string; s?: string; dot?: string };

export type ShelfBook = {
  title: string;
  pages: number;
  summary: string;
  entries: BookEntry[];
};

export async function fetchShelf(): Promise<{ projects: ShelfBook[]; life: ShelfBook[] }> {
  const data = await getJson<{ projects: ShelfBook[]; life: ShelfBook[] }>('/journal/shelf');
  return data ?? { projects: [], life: [] };
}

export const PERSONA_TINTS: Record<string, string> = {
  Sulivan: 'bg-fennec',
  Selene: 'bg-honey',
};
