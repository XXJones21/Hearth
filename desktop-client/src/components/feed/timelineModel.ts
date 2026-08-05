import type { ChatMessage, UiCard } from '../../store/appStore';

/* The timeline is the one event surface (Direction B): every entry is
   author-attributed. Cards (ui_component) join the same stream
   through the same union -- the layout never special-cases a source. */

export type TimelineItem =
  | {
      kind: 'message';
      id: string;
      role: 'user' | 'assistant';
      author: string;
      text: string;
      ts: number;
      streaming?: boolean;
    }
  | {
      kind: 'ui_card';
      id: string;
      cardType: string;
      props: Record<string, unknown>;
      ts: number;
    };

export function buildTimeline(
  messages: ChatMessage[],
  draft: string,
  currentPersona: string | null,
  filter: string,
  uiCards: UiCard[] = []
): TimelineItem[] {
  const q = filter.trim().toLowerCase();
  const now = Date.now();
  const items: TimelineItem[] = messages
    .filter((m) => !q || m.text.toLowerCase().includes(q))
    .map((m) => ({
      kind: 'message' as const,
      id: m.id,
      role: m.role,
      author: m.role === 'user' ? 'You' : m.personaName || currentPersona || 'Hearth',
      text: m.text,
      ts: m.ts,
    }));
  if (!q) {
    for (const c of uiCards) {
      if (c.expiresAt !== null && c.expiresAt <= now) continue;
      items.push({
        kind: 'ui_card',
        id: `card-${c.id}`,
        cardType: c.cardType,
        props: c.props,
        ts: c.ts,
      });
    }
    items.sort((a, b) => a.ts - b.ts);
  }
  if (draft && !q) {
    items.push({
      kind: 'message',
      id: '__draft__',
      role: 'assistant',
      author: currentPersona || 'Hearth',
      text: draft,
      ts: Date.now(),
      streaming: true,
    });
  }
  return items;
}

const NODE_COLORS: Record<string, string> = {
  selene: '#FFB84D',
  sulivan: '#E39A5B',
};

export function nodeColor(author: string): string {
  if (author === 'You') return '#EFE6D8';
  return NODE_COLORS[author.toLowerCase()] || 'var(--persona)';
}

export function nodeInitials(author: string): string {
  if (author === 'You') return 'You';
  return author.slice(0, 2);
}

export function formatTime(ts: number): string {
  return new Date(ts).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}
