import { useEffect, useState } from 'react';
import {
  fetchSession,
  fetchSessions,
  fetchShelf,
  type JournalSession,
  type ShelfBook,
} from '../../lib/journal';
import { useAppStore } from '../../store/appStore';

/* Earlier conversations from the memory tree (a filed diary, or a chatlog
 * from a chat too short to earn one). One-line rows grouped by date, because
 * a rail that shows three sessions at a time is a rail nobody scrolls. Click
 * expands the summary the house wrote; Resume is a second, deliberate click.
 * The journal shelves at the bottom start a NEW chat already pointed at a
 * project or a life root, which is not the same thing as resuming one. */

type Props = {
  onNewSession?: () => void;
  onResumeSession?: (slug: string) => void;
  onStartTopicSession?: (name: string) => void;
  busy?: boolean;
};

const ROW_CAP = 40;

function dateKey(s: JournalSession): string {
  if (/^\d{4}-\d{2}-\d{2}$/.test(s.date)) return s.date;
  const m = s.slug.match(/^(\d{4}-\d{2}-\d{2})/);
  return m ? m[1] : 'Unknown';
}

function groupByDate(
  sessions: JournalSession[],
): { date: string; items: JournalSession[] }[] {
  const map = new Map<string, JournalSession[]>();
  for (const s of sessions.slice(0, ROW_CAP)) {
    const k = dateKey(s);
    const arr = map.get(k) ?? [];
    arr.push(s);
    map.set(k, arr);
  }
  return [...map.entries()]
    .sort((a, b) => b[0].localeCompare(a[0]))
    .map(([date, items]) => ({ date, items }));
}

export function SessionsTab({
  onNewSession,
  onResumeSession,
  onStartTopicSession,
  busy = false,
}: Props) {
  const sessionsTick = useAppStore((s) => s.sessionsTick);
  const liveTopic = useAppStore((s) => s.liveTopic);
  const setActiveView = useAppStore((s) => s.setActiveView);
  const [sessions, setSessions] = useState<JournalSession[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [openSlug, setOpenSlug] = useState<string | null>(null);
  const [detail, setDetail] = useState<JournalSession | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [shelf, setShelf] = useState<{ projects: ShelfBook[]; life: ShelfBook[] } | null>(
    null,
  );
  const [earlierOpen, setEarlierOpen] = useState(true);
  const [journalOpen, setJournalOpen] = useState(false);

  useEffect(() => {
    let live = true;
    setFailed(false);
    fetchSessions()
      .then((list) => {
        if (!live) return;
        setSessions(list);
      })
      .catch(() => {
        if (live) {
          setFailed(true);
          setSessions([]);
        }
      });
    fetchShelf()
      .then((data) => {
        if (live) setShelf(data);
      })
      .catch(() => {
        if (live) setShelf({ projects: [], life: [] });
      });
    return () => {
      live = false;
    };
  }, [sessionsTick]);

  useEffect(() => {
    if (!openSlug) {
      setDetail(null);
      return;
    }
    let live = true;
    setDetailLoading(true);
    fetchSession(openSlug, true)
      .then((entry) => {
        if (!live) return;
        setDetail(entry);
      })
      .finally(() => {
        if (live) setDetailLoading(false);
      });
    return () => {
      live = false;
    };
  }, [openSlug]);

  const groups = sessions ? groupByDate(sessions) : [];
  const topicBooks = [
    ...(shelf?.projects ?? []).map((b) => ({ ...b, kind: 'project' as const })),
    ...(shelf?.life ?? []).map((b) => ({ ...b, kind: 'life' as const })),
  ];

  return (
    <div className="mt-4 flex flex-col gap-4">
      <div>
        <h3 className="mb-2 text-[11px] font-bold uppercase tracking-wider text-fawn">
          This conversation
        </h3>
        <p className="mb-3 text-[12.5px] leading-snug text-fawn">
          Start fresh without closing Hearth. The house keeps what it wrote down;
          the live chat clears.
          {liveTopic ? ` Live topic: ${liveTopic}.` : ''}
        </p>
        <button
          type="button"
          disabled={!onNewSession || busy}
          onClick={() => onNewSession?.()}
          className="rounded-full bg-tab px-3.5 py-2 text-[12.5px] font-semibold text-roast transition enabled:hover:brightness-95 disabled:opacity-50"
        >
          New session
        </button>
      </div>

      <div>
        <div className="mb-2 flex items-baseline justify-between gap-2">
          <button
            type="button"
            aria-expanded={earlierOpen}
            onClick={() => setEarlierOpen((v) => !v)}
            className="flex min-w-0 items-baseline gap-1.5 text-left focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ember"
          >
            <Caret open={earlierOpen} />
            <h3 className="text-[11px] font-bold uppercase tracking-wider text-fawn">
              Earlier conversations
            </h3>
          </button>
          <button
            type="button"
            onClick={() => setActiveView('journal')}
            className="shrink-0 text-[11px] font-semibold text-ember transition hover:brightness-95"
          >
            Open Journal
          </button>
        </div>

        {earlierOpen && failed && (
          <p className="text-[12.5px] leading-snug text-fawn">
            The journal is not reachable right now.
          </p>
        )}
        {earlierOpen && !failed && sessions === null && (
          <p className="text-[12.5px] leading-snug text-fawn">Reading.</p>
        )}
        {earlierOpen && !failed && sessions !== null && sessions.length === 0 && (
          <p className="text-[12.5px] leading-snug text-fawn">
            Nothing filed yet. Ended conversations land here.
          </p>
        )}
        {earlierOpen && !failed && groups.length > 0 && (
          <div className="flex flex-col gap-3">
            {groups.map((g) => (
              <div key={g.date}>
                <h4 className="mb-1 text-[11px] font-bold uppercase tracking-wider text-fawn">
                  {g.date}
                </h4>
                <ul className="flex flex-col">
                  {g.items.map((s) => {
                    const selected = openSlug === s.slug;
                    return (
                      <li key={s.slug}>
                        <button
                          type="button"
                          onClick={() => setOpenSlug(selected ? null : s.slug)}
                          className={
                            selected
                              ? 'flex w-full items-baseline gap-1.5 bg-tab px-2 py-1.5 text-left focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ember'
                              : 'flex w-full items-baseline gap-1.5 px-2 py-1.5 text-left transition hover:bg-parchment focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ember'
                          }
                        >
                          <span className="min-w-0 flex-1 truncate text-[13px] font-medium text-roast">
                            {rowTitle(s)}
                          </span>
                          {s.persona ? (
                            <span className="shrink-0 text-[11px] text-fawn">
                              {s.persona}
                            </span>
                          ) : null}
                        </button>
                        {selected && (
                          <div className="mb-1 rounded-xl border border-linen bg-fluff px-3 py-2.5">
                            {detailLoading && (
                              <p className="text-[12.5px] text-fawn">Opening.</p>
                            )}
                            {!detailLoading && !detail && (
                              <p className="text-[12.5px] text-fawn">
                                Could not open that session.
                              </p>
                            )}
                            {!detailLoading && detail && (
                              <SessionDetail
                                entry={detail}
                                busy={busy}
                                onResume={
                                  detail.has_transcript && onResumeSession
                                    ? () => onResumeSession(detail.slug)
                                    : undefined
                                }
                              />
                            )}
                          </div>
                        )}
                      </li>
                    );
                  })}
                </ul>
              </div>
            ))}
          </div>
        )}
      </div>

      <div>
        <button
          type="button"
          aria-expanded={journalOpen}
          onClick={() => setJournalOpen((v) => !v)}
          className="mb-2 flex items-baseline gap-1.5 text-left focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ember"
        >
          <Caret open={journalOpen} />
          <h3 className="text-[11px] font-bold uppercase tracking-wider text-fawn">
            Sessions from journal
          </h3>
        </button>
        {journalOpen && shelf === null && (
          <p className="text-[12.5px] leading-snug text-fawn">Reading shelves.</p>
        )}
        {journalOpen && shelf !== null && topicBooks.length === 0 && (
          <p className="text-[12.5px] leading-snug text-fawn">
            No journal shelves to start from.
          </p>
        )}
        {journalOpen && topicBooks.length > 0 && (
          <ul className="flex flex-col">
            {topicBooks.map((b) => (
              <li key={`${b.kind}-${b.title}`}>
                <button
                  type="button"
                  disabled={!onStartTopicSession || busy}
                  onClick={() => onStartTopicSession?.(b.title)}
                  className="w-full px-2 py-1.5 text-left text-[13px] font-medium text-roast transition hover:bg-parchment focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ember disabled:opacity-50"
                >
                  Start session for {b.title}
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

function Caret({ open }: { open: boolean }) {
  return (
    <span
      className={
        open
          ? 'inline-block text-[10px] text-fawn transition-transform rotate-90'
          : 'inline-block text-[10px] text-fawn transition-transform'
      }
      aria-hidden
    >
      &gt;
    </span>
  );
}

/* A row is one line, so the title has to earn it. "Voice session" is what the
   house calls a chat it never titled, and forty of those stacked are a list
   nobody can read: fall back to the first thing the operator actually said. */
function rowTitle(s: JournalSession): string {
  const t = (s.title || '').trim();
  const generic =
    !t || ['voice session', 'untitled', 'untitled session'].includes(t.toLowerCase());
  if (!generic) return t;
  const src = (s.summary || '').replace(/^(operator|user):\s*/i, '').trim();
  const line = src.split(/\s+/).join(' ');
  if (!line) return t || 'Untitled session';
  if (line.length <= 56) return line;
  const cut = line.slice(0, 56).replace(/\s+\S*$/, '');
  return cut || line.slice(0, 56);
}

function SessionDetail({
  entry,
  onResume,
  busy = false,
}: {
  entry: JournalSession;
  onResume?: () => void;
  busy?: boolean;
}) {
  return (
    <div className="flex flex-col gap-2">
      {onResume && (
        <button
          type="button"
          disabled={busy}
          onClick={onResume}
          className="self-start rounded-full bg-ember px-3.5 py-1.5 text-[12.5px] font-semibold text-fluff transition enabled:hover:brightness-95 disabled:opacity-50"
        >
          Resume
        </button>
      )}
      {entry.summary && (
        <p className="text-[12.5px] leading-snug text-roast whitespace-pre-wrap">
          {entry.summary}
        </p>
      )}
      {entry.decisions?.length > 0 && (
        <DetailList label="Decisions" items={entry.decisions} />
      )}
      {entry.questions?.length > 0 && (
        <DetailList label="Open questions" items={entry.questions} />
      )}
      {entry.actions?.length > 0 && (
        <DetailList label="Actions" items={entry.actions} />
      )}
      {entry.transcript ? (
        <div>
          <h4 className="mb-1 text-[11px] font-bold uppercase tracking-wider text-fawn">
            Transcript
          </h4>
          <pre className="max-h-56 overflow-y-auto whitespace-pre-wrap break-words rounded-lg bg-parchment px-2.5 py-2 font-sans text-[12px] leading-snug text-roast">
            {entry.transcript}
          </pre>
        </div>
      ) : (
        <p className="text-[12px] leading-snug text-fawn">
          No full transcript was kept for this one. The summary above is what the
          house filed.
        </p>
      )}
    </div>
  );
}

function DetailList({ label, items }: { label: string; items: string[] }) {
  return (
    <div>
      <h4 className="mb-1 text-[11px] font-bold uppercase tracking-wider text-fawn">
        {label}
      </h4>
      <ul className="list-disc space-y-0.5 pl-4 text-[12.5px] leading-snug text-roast">
        {items.map((item) => (
          <li key={item}>{item}</li>
        ))}
      </ul>
    </div>
  );
}
