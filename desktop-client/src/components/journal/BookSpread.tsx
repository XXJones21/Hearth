import { useEffect, useRef, useState } from 'react';
import { displayName, type LibraryBook } from './Book';
import type { BookEntry } from '../../lib/journal';

/* Selene's voice for the living volumes; project/life pages come from her
   curation pass served by /journal/shelf. */
const SELENE_PAGES: Record<string, string> = {
  'The Journal':
    "The daily chronicle of our conversations -- every session Sulivan and I share with Joshua, distilled to its essence. Each page holds a day's decisions, questions, and promises. Read it backward to watch our path converge.",
  'About Joshua':
    'The living page. What I hold true about the one who tends this hearth -- gathered gently, revised honestly, never assumed.',
  "Selene's Ledger":
    "My own hand. Each night I read the day's pages and set down what mattered: the highlights, the patterns beneath them, the threads left loose. This ledger is how the library breathes.",
};

const PAGE_SIZE = 5;
const mdStrip = (t?: string) => (t || '').replace(/\*\*|\*|`|\[\[|\]\]/g, '');

type Props = {
  book: LibraryBook | null;
  onClose: () => void;
};

export function BookSpread({ book, onClose }: Props) {
  const [page, setPage] = useState(0);
  const [lifted, setLifted] = useState<BookEntry | null>(null);
  const [flipping, setFlipping] = useState(false);
  const entriesRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setPage(0);
    setLifted(null);
  }, [book]);

  const entries = book?.entries ?? [];
  const pageCount = Math.max(1, Math.ceil(entries.length / PAGE_SIZE));
  const slice = entries.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE);

  const turn = (dir: number) => {
    const next = Math.max(0, Math.min(page + dir, pageCount - 1));
    if (next === page) return;
    setFlipping(true);
    window.setTimeout(() => {
      setPage(next);
      setFlipping(false);
    }, 150);
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!book) return;
      if (e.key === 'Escape') onClose();
      if (e.key === 'ArrowRight') turn(1);
      if (e.key === 'ArrowLeft') turn(-1);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  const name = book ? displayName(book.title) : '';
  const summary = book
    ? mdStrip(SELENE_PAGES[book.title] || book.summary) ||
      "I have not yet written this volume's page. Ask me about it, and I will read it through and set down what it holds."
    : '';
  const latest = entries[0] ? entries[0].d || entries[0].t : '—';

  return (
    <div
      className={`lib-overlay${book ? ' open' : ''}`}
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="lib-spread">
        <button type="button" className="lib-closex" onClick={onClose} aria-label="Close book">
          ×
        </button>
        <div className="lib-pages">
          <div className="lib-page left">
            <h2>{name}</h2>
            <div className="lib-page-meta">
              {book?.pages ?? 0} page{(book?.pages ?? 0) === 1 ? '' : 's'}
              {book?.note ? ` · ${book.note}` : ''} · shelved by Selene
            </div>
            <div className="lib-keeper-note">
              {summary}
              <div className="lib-attrib">— Selene, keeper of the library</div>
            </div>
            <div className="lib-stats">
              {entries.length} entries
              <br />
              latest: {latest}
            </div>
          </div>
          <div className="lib-page right">
            <div ref={entriesRef} className={`lib-entries${flipping ? ' flipping' : ''}`}>
              {slice.map((e, i) => (
                <div
                  key={`${e.t}-${i}`}
                  className="lib-entry"
                  onClick={(ev) => {
                    ev.stopPropagation();
                    setLifted(e);
                  }}
                >
                  <div className="lib-entry-title">
                    <span className="lib-dot" style={{ background: e.dot || '#E39A5B' }} />
                    {e.t}
                  </div>
                  {e.d && <div className="lib-entry-date">{e.d}</div>}
                  {e.s && <div className="lib-entry-sum">{mdStrip(e.s)}</div>}
                </div>
              ))}
            </div>
            <div className="lib-pageturn">
              <button type="button" onClick={() => turn(-1)} disabled={page === 0}>
                ‹
              </button>
              <span>
                {page + 1} / {pageCount}
              </span>
              <button type="button" onClick={() => turn(1)} disabled={page >= pageCount - 1}>
                ›
              </button>
            </div>
          </div>
        </div>
        <div className={`lib-lifted${lifted ? ' show' : ''}`}>
          {lifted && (
            <>
              <div className="lib-lifted-title">{lifted.t}</div>
              <div className="lib-lifted-sum">{mdStrip(lifted.s) || '(no summary recorded)'}</div>
              <div className="lib-lifted-meta">{(lifted.d || '') + ' · lifted from the page'}</div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
