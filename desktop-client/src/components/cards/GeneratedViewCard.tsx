import type { CardProps, GeneratedViewProps, GeneratedViewSection, GridCell } from './types';
import { resolvePersonaAssetUrl } from '../../lib/resolveAssetUrl';

const MAX_SECTIONS = 12;
/* Six weeks of a month plus a weekday header is 49. Anything past this is a
   model that has lost the thread rather than a legitimate layout. */
const MAX_CELLS = 64;
const MAX_COLUMNS = 12;

/* The closed style set. A persona picks a name; the host owns the pixels. */
const CELL_STYLE: Record<string, string> = {
  default: 'bg-parchment text-roast',
  muted: 'bg-transparent text-fawn',
  marked: 'bg-fennec font-semibold text-fluff',
  accent: 'bg-bubble font-semibold text-roast',
  empty: 'bg-transparent text-transparent',
};

function Grid({ columns, heading, cells }: { columns: number; heading?: string; cells: GridCell[] }) {
  const cols = Math.min(Math.max(Math.floor(columns) || 1, 1), MAX_COLUMNS);
  return (
    <div>
      {heading && (
        <div className="mb-2 text-[13px] font-semibold text-roast">{heading}</div>
      )}
      <div
        className="grid gap-1"
        style={{ gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))` }}
      >
        {cells.slice(0, MAX_CELLS).map((c, i) => (
          <div
            key={i}
            className={`grid aspect-square place-items-center rounded-md text-[12px] ${
              CELL_STYLE[c.style ?? 'default'] ?? CELL_STYLE.default
            }`}
          >
            {c.text}
          </div>
        ))}
      </div>
    </div>
  );
}

/* A headed text section, styled like a journal page's section blocks:
   uppercase ember eyebrow over bullet-aware body lines in a soft panel. */
function HeadedTextBlock({ heading, body }: { heading: string; body: string }) {
  const lines = body
    .split('**').join('')
    .split('\n')
    .map((l: string) => l.trim())
    .filter(Boolean);
  return (
    <div className="rounded-xl border border-linen bg-parchment px-3.5 py-3">
      <div className="mb-2 text-[10px] font-bold uppercase tracking-wider text-ember">
        {heading}
      </div>
      <div className="flex flex-col gap-1">
        {lines.map((line, i) => {
          const isBullet = line.startsWith('-') || line.startsWith('*');
          return (
            <div key={i} className="flex items-start gap-1.5 text-[13px] text-roast">
              {isBullet && (
                <span className="mt-[7px] h-1 w-1 shrink-0 rounded-full bg-fawn" />
              )}
              <span>{isBullet ? line.slice(1).trim() : line}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function Section({ section, hero }: { section: GeneratedViewSection; hero: boolean }) {
  switch (section.kind) {
    case 'text':
      return section.heading ? (
        <HeadedTextBlock heading={section.heading} body={section.body} />
      ) : (
        <p className="text-[14px] text-roast">{section.body}</p>
      );
    case 'stat':
      return (
        <div>
          <div className={`font-bold text-roast ${hero ? 'text-[28px]' : 'text-[21px]'}`}>
            {section.value}
          </div>
          <div className="text-[11.5px] text-fawn">{section.label}</div>
        </div>
      );
    case 'stat_row':
      return (
        <div className="flex flex-wrap gap-5">
          {(section.stats || []).slice(0, 4).map((s, i) => (
            <div key={i}>
              <div className="text-[21px] font-bold text-roast">{s.value}</div>
              <div className="text-[11.5px] text-fawn">{s.label}</div>
            </div>
          ))}
        </div>
      );
    case 'image':
      return (
        <img
          src={resolvePersonaAssetUrl(section.src, '')}
          alt=""
          className="max-h-56 w-full rounded-xl object-cover"
        />
      );
    case 'grid':
      return (
        <Grid
          columns={section.columns}
          heading={section.heading}
          cells={Array.isArray(section.cells) ? section.cells : []}
        />
      );
    case 'divider':
      return <hr className="border-linen" />;
    default:
      return null;
  }
}

export function GeneratedViewCard({ props }: CardProps) {
  const gv = props as GeneratedViewProps;
  const sections = Array.isArray(gv.sections) ? gv.sections.slice(0, MAX_SECTIONS) : [];
  const template = gv.template || 'plain';
  const isComparison = template === 'comparison';

  return (
    <div className="max-w-[560px] rounded-2xl border border-linen bg-fluff px-4 py-3 shadow-soft">
      {gv.title && (
        <div className="mb-2 text-[11.5px] font-bold uppercase tracking-wider text-ember">
          {gv.title}
        </div>
      )}
      <div className={isComparison ? 'grid grid-cols-2 gap-x-5 gap-y-3' : 'flex flex-col gap-3'}>
        {sections.map((section, i) => (
          <Section key={i} section={section} hero={template === 'hero_stat' && i === 0} />
        ))}
      </div>
    </div>
  );
}
