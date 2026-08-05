import type { BookEntry } from '../../lib/journal';

export type LibraryBook = {
  title: string;
  pages: number;
  summary?: string;
  note?: string;
  color?: string;
  glow?: boolean;
  entries: BookEntry[];
};

const PALETTE = ['#C97F45', '#B5713F', '#A9682E', '#8C5A32', '#E0A66B', '#C4874F'];

/* Project slugs whose pretty name a title-caser gets wrong. This started as a
   list of one person's projects; it is now only the general cases, and a user's
   own project folders title-case fine without help. */
const SPECIAL_NAMES: Record<string, string> = {
  ai: 'AI',
  api: 'API',
  ios: 'iOS',
  ui: 'UI',
};

export function displayName(slug: string): string {
  if (SPECIAL_NAMES[slug]) return SPECIAL_NAMES[slug];
  if (/^[A-Z]/.test(slug) || slug.includes(' ')) return slug;
  return slug
    .split('-')
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(' ');
}

const shade = (hex: string, pct: number): string => {
  const n = parseInt(hex.slice(1), 16);
  const f = (c: number) => Math.max(0, Math.min(255, c + Math.round(2.55 * pct)));
  return `rgb(${f(n >> 16)},${f((n >> 8) & 255)},${f(n & 255)})`;
};

const thickness = (p: number, s: number) => Math.max(20, Math.min(64, (14 + p * 3.4) * s));
const height = (p: number, s: number) => Math.max(92, Math.min(164, (100 + p * 3.2) * s));
const titleSize = (name: string, base: number) =>
  Math.max(7.5, base - Math.max(0, name.length - 9) * 0.42);

type Props = {
  book: LibraryBook;
  index: number;
  scale?: number;
  onOpen: (book: LibraryBook, el: HTMLDivElement) => void;
};

export function Book({ book, index, scale = 1, onOpen }: Props) {
  const color = book.color || PALETTE[index % PALETTE.length];
  const name = displayName(book.title);
  const h = height(book.pages, scale);
  return (
    <div
      className={`lib-book${book.glow ? ' glow' : ''}`}
      onClick={(e) => onOpen(book, e.currentTarget)}
      role="button"
      aria-label={`Open ${name}`}
    >
      <div
        className="lib-spine"
        style={{
          width: thickness(book.pages, scale),
          height: h,
          background: `linear-gradient(90deg, ${color}, ${shade(color, -18)})`,
        }}
      >
        <div className="lib-bands" />
        <div
          className="lib-spine-title"
          style={{ fontSize: titleSize(name, scale < 1 ? 10 : 11.5), maxHeight: h - 46 }}
        >
          {name}
        </div>
        <div className="lib-bands" />
      </div>
      <div
        className="lib-cover"
        style={{
          background: `linear-gradient(120deg, ${shade(color, 8)}, ${shade(color, -12)})`,
          height: h,
        }}
      >
        <div className="lib-cover-title">{name}</div>
        <div className="lib-cover-pages">
          {book.pages} page{book.pages === 1 ? '' : 's'}
          {book.note ? ` · ${book.note}` : ''}
        </div>
      </div>
      {book.glow && (
        <div
          className="lib-firefly"
          style={{ top: 12 + (index % 3) * 9, right: -10, animationDelay: `${(index % 5) * 0.7}s` }}
        />
      )}
    </div>
  );
}
