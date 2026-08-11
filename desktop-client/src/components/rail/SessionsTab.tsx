import { useEffect, useState } from 'react';
import {
  fetchSession,
  fetchSessions,
  type JournalSession,
} from '../../lib/journal';
import { useAppStore } from '../../store/appStore';

/* Earlier conversations from the Journal diaries the house already writes.
 * Click one to read its summary (and transcript when present). Resume seeds
 * that chatlog into a fresh live session (Slice 3). */

type Props = {
  onNewSession?: () => void;
  onResumeSession?: (slug: string) => void;
  busy?: boolean;
};

export function SessionsTab({
  onNewSession,
  onResumeSession,
  busy = false,
}: Props) {
  const sessionsTick = useAppStore((s) => s.sessionsTick);
  const setActiveView = useAppStore((s) => s.setActiveView);
  const [sessions, setSessions] = useState<JournalSession[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [openSlug, setOpenSlug] = useState<string | null>(null);
  const [detail, setDetail] = useState<JournalSession | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);

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

  return (
    <div className="mt-4 flex flex-col gap-4">
      <div>
        <h3 className="mb-2 text-[11px] font-bold uppercase tracking-wider text-fawn">
          This conversation
        </h3>
        <p className="mb-3 text-[12.5px] leading-snug text-fawn">
          Start fresh without closing Hearth. The house keeps what it wrote down;
          the live chat clears.
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
          <h3 className="text-[11px] font-bold uppercase tracking-wider text-fawn">
            Earlier conversations
          </h3>
          <button
            type="button"
            onClick={() => setActiveView('journal')}
            className="text-[11px] font-semibold text-ember transition hover:brightness-95"
          >
            Open Journal
          </button>
        </div>

        {failed && (
          <p className="text-[12.5px] leading-snug text-fawn">
            The journal is not reachable right now.
          </p>
        )}
        {!failed && sessions === null && (
          <p className="text-[12.5px] leading-snug text-fawn">Reading.</p>
        )}
        {!failed && sessions !== null && sessions.length === 0 && (
          <p className="text-[12.5px] leading-snug text-fawn">
            Nothing filed yet. Ended conversations with enough turns land here.
          </p>
        )}
        {!failed && sessions !== null && sessions.length > 0 && (
          <ul className="flex flex-col gap-1.5">
            {sessions.slice(0, 20).map((s) => {
              const selected = openSlug === s.slug;
              return (
                <li key={s.slug}>
                  <button
                    type="button"
                    onClick={() => setOpenSlug(selected ? null : s.slug)}
                    className={
                      selected
                        ? 'w-full rounded-xl bg-tab px-3 py-2.5 text-left'
                        : 'w-full rounded-xl bg-parchment px-3 py-2.5 text-left transition hover:brightness-[0.98]'
                    }
                  >
                    <span className="block text-[13px] font-medium text-roast">
                      {s.title || 'Untitled session'}
                    </span>
                    <span className="mt-0.5 block text-[11px] text-fawn">
                      {[s.date, s.persona].filter(Boolean).join(' · ')}
                      {s.has_transcript ? ' · transcript' : ''}
                    </span>
                    {s.summary && (
                      <span className="mt-1 block text-[12px] leading-snug text-fawn line-clamp-2">
                        {s.summary}
                      </span>
                    )}
                  </button>

                  {selected && (
                    <div className="mt-1 rounded-xl border border-linen bg-fluff px-3 py-2.5">
                      {detailLoading && (
                        <p className="text-[12.5px] text-fawn">Opening.</p>
                      )}
                      {!detailLoading && !detail && (
                        <p className="text-[12.5px] text-fawn">Could not open that session.</p>
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
        )}
      </div>
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
          No full transcript was kept for this one — the summary above is what
          the house filed.
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
