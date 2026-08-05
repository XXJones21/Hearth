import { useEffect, useMemo, useRef, useState } from 'react';
import './library.css';
import { Book, displayName, type LibraryBook } from './Book';
import { BookSpread } from './BookSpread';
import {
  fetchFacts,
  fetchReviews,
  fetchSessions,
  fetchShelf,
  type ShelfBook,
} from '../../lib/journal';

/* Selene's Library -- the Journal surface. Four rooms per her floor plan:
   the Heart (living volumes), the Curator's Alcove (life), the Active
   Forge (projects), and the Glass Conservatory (seedlings). */

const PERSONA_DOT: Record<string, string> = {
  Sulivan: '#E39A5B',
  Selene: '#FFB84D',
};

export function LibraryView() {
  const [heart, setHeart] = useState<LibraryBook[]>([]);
  const [shelf, setShelf] = useState<{ projects: ShelfBook[]; life: ShelfBook[] }>({
    projects: [],
    life: [],
  });
  const [open, setOpen] = useState<LibraryBook | null>(null);
  const [query, setQuery] = useState('');
  const pulledRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    fetchShelf().then(setShelf);
    Promise.all([fetchSessions(), fetchFacts(), fetchReviews(60)]).then(
      ([sessions, facts, reviews]) => {
        setHeart([
          {
            title: 'The Journal',
            pages: sessions.length,
            glow: true,
            color: '#C97F45',
            note: 'the daily chronicle',
            entries: sessions.map((s) => ({
              t: s.title,
              d: `${s.date} · ${s.persona}`,
              s: s.summary,
              dot: PERSONA_DOT[s.persona] || '#8C7A66',
            })),
          },
          {
            title: 'About Joshua',
            pages: 1,
            color: '#8C5A32',
            note: 'living page',
            entries: facts
              .split('\n')
              .filter((l) => l.trim().startsWith('-'))
              .map((l) => {
                const f = l.replace(/^\s*-\s*/, '').trim();
                return { t: f, s: f };
              }),
          },
          {
            title: "Selene's Ledger",
            pages: reviews.length,
            glow: true,
            color: '#B5713F',
            note: 'her own hand',
            entries: reviews.map((r) => ({
              t: `Daily review · ${r.date}`,
              d: r.date,
              s: r.body.replace(/^#.*\n/, '').trim().slice(0, 220),
            })),
          },
        ]);
      },
    );
  }, []);

  const { forge, seedlings, life } = useMemo(() => {
    const match = (b: ShelfBook) =>
      !query.trim() || displayName(b.title).toLowerCase().includes(query.trim().toLowerCase());
    const projects = shelf.projects.filter(match);
    return {
      forge: projects.filter((p) => p.pages > 1).sort((a, b) => b.pages - a.pages),
      seedlings: projects.filter((p) => p.pages <= 1),
      life: shelf.life.filter(match),
    };
  }, [shelf, query]);

  const openBook = (book: LibraryBook, el: HTMLDivElement) => {
    pulledRef.current = el;
    el.classList.add('pulling');
    window.setTimeout(() => setOpen(book), 320);
  };
  const closeBook = () => {
    setOpen(null);
    const el = pulledRef.current;
    pulledRef.current = null;
    if (el) window.setTimeout(() => el.classList.remove('pulling'), 380);
  };

  return (
    <section className="lib-root flex min-h-0 flex-col overflow-hidden" aria-label="Journal">
      <div className="flex items-baseline gap-3 px-7 pt-6">
        <h2 className="text-[20px] font-bold text-roast">Journal</h2>
        <span className="text-[12px] italic text-fawn">kept by Selene</span>
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search the library"
          className="ml-auto w-52 rounded-full border border-linen bg-parchment px-4 py-2 text-[13px] text-roast placeholder:text-fawn focus:outline-none"
        />
      </div>

      <div className="mt-4 min-h-0 flex-1 space-y-6 overflow-y-auto px-7 pb-7">
        <div>
          <div className="lib-room-label">The Heart of the Library</div>
          <div className="lib-room-sub">the pulse of the room — the volumes that live and grow</div>
          <div className="lib-pedestal">
            {heart.map((b, i) => (
              <Book key={b.title} book={b} index={i} scale={1.05} onOpen={openBook} />
            ))}
          </div>
        </div>

        <div>
          <div className="lib-room-label">The Curator's Alcove</div>
          <div className="lib-room-sub">the person before the works</div>
          <div>
            <div className="lib-shelf">
              {life.map((b, i) => (
                <Book key={b.title} book={b} index={i} onOpen={openBook} />
              ))}
            </div>
            <div className="lib-shelf-board" />
          </div>
        </div>

        <div>
          <div className="lib-room-label">The Active Forge</div>
          <div className="lib-room-sub">works in motion</div>
          <div>
            <div className="lib-shelf">
              {forge.map((b, i) => (
                <Book key={b.title} book={b} index={i} onOpen={openBook} />
              ))}
            </div>
            <div className="lib-shelf-board" />
          </div>
        </div>

        <div>
          <div className="lib-room-label">The Glass Conservatory</div>
          <div className="lib-room-sub">seedlings — a breath of cool air</div>
          <div className="lib-conservatory">
            <div className="lib-shelf">
              {seedlings.map((b, i) => (
                <Book key={b.title} book={b} index={i} scale={0.72} onOpen={openBook} />
              ))}
            </div>
            <div className="lib-shelf-board" style={{ opacity: 0.55 }} />
          </div>
        </div>

        <div className="lib-sanctum">
          <div className="lib-sanctum-door">The Sanctum of Reflection</div>
          <span className="lib-sanctum-glow" />
          where threads between books are woven — opening soon
        </div>
      </div>

      <BookSpread book={open} onClose={closeBook} />
    </section>
  );
}
