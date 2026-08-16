import { useEffect, useState } from 'react';
import {
  fetchSession,
  fetchSessions,
  fetchShelf,
  type JournalSession,
  type ShelfBook,
} from '../../lib/journal';
import {
  chatlogTurns,
  fetchRecord,
  fetchRecords,
  type SessionRecord,
} from '../../lib/sessions';
import { useAppStore } from '../../store/appStore';

/* Two sources, one list. Records are what the house has said, written as it
   happens; journal entries are what it later wrote up. A conversation that has
   been through both appears once, as its record, because the record is the one
   that can still be resumed turn for turn. */
type Row = {
  key: string;
  kind: 'record' | 'journal';
  id: string;
  date: string;
  title: string;
  persona: string;
  resumable: boolean;
  turns?: number;
  synced?: boolean;
};

/* Earlier conversations from Engram Thoughts (diary or chatlog-only).
 * One-line rows grouped by date. Click expands a preview; Resume is a
 * second click. Sessions from journal start a fresh topic chat. */

type Props = {
  onNewSession?: () => void;
  onResumeSession?: (id: string, kind?: 'record' | 'journal') => void;
  onStartTopicSession?: (name: string) => void;
  busy?: boolean;
};

const ROW_CAP = 40;

function journalDate(s: JournalSession): string {
  if (/^\d{4}-\d{2}-\d{2}$/.test(s.date)) return s.date;
  const m = s.slug.match(/^(\d{4}-\d{2}-\d{2})/);
  return m ? m[1] : 'Unknown';
}

function mergeRows(records: SessionRecord[], journal: JournalSession[]): Row[] {
  const claimed = new Set(
    records.map((r) => (r.thought_slug || '').trim()).filter(Boolean),
  );
  const rows: Row[] = records.map((r) => ({
    key: `rec:${r.session_id}`,
    kind: 'record',
    id: r.session_id,
    date: r.date || (r.started_at || '').slice(0, 10) || 'Unknown',
    title: r.title || 'Untitled session',
    persona: r.persona || '',
    resumable: r.has_transcript !== false,
    turns: r.turns,
    synced: r.synced,
  }));
  for (const s of journal) {
    // The diary this record already produced would otherwise show twice.
    if (claimed.has(s.slug)) continue;
    rows.push({
      key: `jrn:${s.slug}`,
      kind: 'journal',
      id: s.slug,
      date: journalDate(s),
      title: rowTitle(s),
      persona: s.persona || '',
      resumable: Boolean(s.has_transcript),
    });
  }
  rows.sort((a, b) => b.date.localeCompare(a.date));
  return rows;
}

function groupByDate(rows: Row[]): { date: string; items: Row[] }[] {
  const map = new Map<string, Row[]>();
  for (const r of rows.slice(0, ROW_CAP)) {
    const arr = map.get(r.date) ?? [];
    arr.push(r);
    map.set(r.date, arr);
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
  const [records, setRecords] = useState<SessionRecord[]>([]);
  const [failed, setFailed] = useState(false);
  const [openRow, setOpenRow] = useState<Row | null>(null);
  const [detail, setDetail] = useState<JournalSession | null>(null);
  const [transcript, setTranscript] = useState<string>('');
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
    fetchRecords().then((list) => {
      if (live) setRecords(list);
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
    if (!openRow) {
      setDetail(null);
      setTranscript('');
      return;
    }
    let live = true;
    setDetailLoading(true);
    if (openRow.kind === 'record') {
      fetchRecord(openRow.id)
        .then((rec) => {
          if (!live) return;
          setDetail(null);
          setTranscript(rec?.chatlog || '');
        })
        .finally(() => {
          if (live) setDetailLoading(false);
        });
      return () => {
        live = false;
      };
    }
    fetchSession(openRow.id, true)
      .then((entry) => {
        if (!live) return;
        setTranscript('');
        setDetail(entry);
      })
      .finally(() => {
        if (live) setDetailLoading(false);
      });
    return () => {
      live = false;
    };
  }, [openRow]);

  const rows = mergeRows(records, sessions ?? []);
  const groups = sessions || records.length ? groupByDate(rows) : [];
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
        {earlierOpen && !failed && sessions !== null && rows.length === 0 && (
          <p className="text-[12.5px] leading-snug text-fawn">
            Nothing yet. Conversations land here as you have them.
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
                    const selected = openRow?.key === s.key;
                    return (
                      <li key={s.key}>
                        <button
                          type="button"
                          onClick={() => setOpenRow(selected ? null : s)}
                          className={
                            selected
                              ? 'flex w-full items-baseline gap-1.5 bg-tab px-2 py-1.5 text-left focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ember'
                              : 'flex w-full items-baseline gap-1.5 px-2 py-1.5 text-left transition hover:bg-parchment focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ember'
                          }
                        >
                          <span className="min-w-0 flex-1 truncate text-[13px] font-medium text-roast">
                            {s.title}
                          </span>
                          {s.persona ? (
                            <span className="shrink-0 text-[11px] text-fawn">
                              {s.persona}
                            </span>
                          ) : null}
                        </button>
                        {selected && (
                          <div className="mb-1 px-2 pb-2">
                            {detailLoading && (
                              <p className="text-[12.5px] text-fawn">Opening.</p>
                            )}
                            {!detailLoading && s.kind === 'record' && (
                              <RecordPreview
                                row={s}
                                chatlog={transcript}
                                busy={busy}
                                onResume={
                                  s.resumable && onResumeSession
                                    ? () => onResumeSession(s.id, 'record')
                                    : undefined
                                }
                              />
                            )}
                            {!detailLoading && s.kind === 'journal' && !detail && (
                              <p className="text-[12.5px] text-fawn">
                                Could not open that session.
                              </p>
                            )}
                            {!detailLoading && s.kind === 'journal' && detail && (
                              <SessionDetail
                                entry={detail}
                                busy={busy}
                                onResume={
                                  detail.has_transcript && onResumeSession
                                    ? () => onResumeSession(detail.slug, 'journal')
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

function rowTitle(s: JournalSession): string {
  const t = (s.title || '').trim();
  const generic = !t || ['voice session', 'untitled', 'untitled session'].includes(t.toLowerCase());
  if (!generic) return t;
  const src = (s.summary || '').replace(/^(operator|user):\s*/i, '').trim();
  const line = src.split(/\s+/).join(' ');
  if (!line) return t || 'Untitled session';
  if (line.length <= 56) return line;
  const cut = line.slice(0, 56).replace(/\s+\S*$/, '');
  return cut || line.slice(0, 56);
}

/* A record has no summary, because nothing has written one yet. What it has is
   the conversation, so the preview shows the last thing said rather than a
   blank space where a summary will eventually be. */
function RecordPreview({
  row,
  chatlog,
  onResume,
  busy = false,
}: {
  row: Row;
  chatlog: string;
  onResume?: () => void;
  busy?: boolean;
}) {
  const turns = chatlogTurns(chatlog);
  const tail = turns.slice(-2);
  return (
    <div className="flex flex-col gap-2">
      {tail.length === 0 ? (
        <p className="text-[12px] leading-snug text-fawn">Nothing recorded yet.</p>
      ) : (
        tail.map((t, i) => (
          <p key={i} className="text-[12.5px] leading-snug text-roast">
            <span className="text-fawn">{t.role === 'user' ? 'You: ' : ''}</span>
            {t.body.slice(0, 220)}
          </p>
        ))
      )}
      <p className="text-[11px] text-fawn">
        {row.turns ? `${row.turns} turn${row.turns === 1 ? '' : 's'}` : ''}
        {row.synced ? ' · written up in the Journal' : ' · not written up yet'}
      </p>
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
    </div>
  );
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
