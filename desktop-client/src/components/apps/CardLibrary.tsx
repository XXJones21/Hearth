import { useEffect } from 'react';
import { cardComponentFor } from '../cards/registry';
import type { CardRow } from '../../lib/appsApi';

/* Everything the house can draw, rendered rather than described.
 *
 * Each tile mounts the REAL component from the registry with sample props, so
 * the preview cannot drift from what a card actually looks like. A card whose
 * component this client does not carry says so instead of vanishing, since
 * unknown-renders-nothing is right in the feed and wrong here. */

const SAMPLES: Record<string, Record<string, unknown>> = {
  clock: { time: '9:41', date: 'Monday, August 3' },
  weather_card: {
    location: 'Austin',
    temp: 97,
    condition: 'Hot and clear',
    high: 101,
    low: 78,
  },
  timer_card: {
    timers: [
      { label: 'Pasta', fire_at: String(Math.floor(Date.now() / 1000) + 252), seconds: 252 },
      { label: 'Laundry', fire_at: String(Math.floor(Date.now() / 1000) + 1360), seconds: 1360 },
    ],
  },
  brief_text: {
    title: 'Tomorrow',
    body: 'Two calls before noon, then the block you kept for the fine-tune.',
  },
  captions: { text: 'and that is why the ledger runs at half eleven, not midnight.' },
  slideshow: {
    images: [
      'data:image/svg+xml;utf8,' +
        encodeURIComponent(
          '<svg xmlns="http://www.w3.org/2000/svg" width="320" height="120">' +
            '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">' +
            '<stop offset="0" stop-color="#E9CDA6"/><stop offset="1" stop-color="#C9A57B"/>' +
            '</linearGradient></defs><rect width="320" height="120" fill="url(#g)"/></svg>',
        ),
    ],
    interval_ms: 4000,
  },
  terminal_card: {
    title: 'Claude Code',
    subtitle: 'scratch workspace',
    status: 'done',
    body: 'Wrote the countdown tool. I could not verify it: shell access was gated.\n\n```\npython countdown.py 2026-12-25 --once\n```',
    meta: ['6 turns', '$0.30', '32s'],
  },
  // No job_id, so the preview shows the settled shape and never polls the
  // live easel from inside the library.
  image_card: {
    title: 'From the easel',
    prompt: 'A corgi asleep on the deck of a cruise ship, in the afternoon sun.',
    status: 'done',
    src:
      'data:image/svg+xml;utf8,' +
      encodeURIComponent(
        '<svg xmlns="http://www.w3.org/2000/svg" width="480" height="320">' +
          '<defs><linearGradient id="s" x1="0" y1="0" x2="0" y2="1">' +
          '<stop offset="0" stop-color="#F6E3CB"/><stop offset="1" stop-color="#E0B583"/>' +
          '</linearGradient></defs><rect width="480" height="320" fill="url(#s)"/>' +
          '<circle cx="360" cy="80" r="38" fill="#F2C879"/></svg>',
      ),
  },
  generated_view: {
    template: 'brief',
    title: 'This week',
    sections: [
      {
        kind: 'stat_row',
        stats: [
          { label: 'Runs', value: '4' },
          { label: 'Beats', value: '31' },
          { label: 'Cards', value: '2' },
        ],
      },
      { kind: 'text', body: 'Mostly the settings panel and the Apps investigation.' },
    ],
  },
  // Field names taken from each card's catalog contract, not guessed: a
  // preview built on the wrong props renders empty and teaches nothing.
};

const STATE_LABEL: Record<CardRow['state'], { dot: string; label: string }> = {
  builtin: { dot: 'bg-emerald-600', label: 'built in' },
  forged: { dot: 'bg-fennec', label: 'made in this house' },
  scaffold: { dot: 'border border-bubble-line bg-linen', label: 'still being built' },
};

export function CardLibrary({
  cards,
  onClose,
  onCommission,
}: {
  cards: CardRow[];
  onClose: () => void;
  onCommission: (text: string) => void;
}) {
  useEffect(() => {
    const esc = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', esc);
    return () => window.removeEventListener('keydown', esc);
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-roast/35 backdrop-blur-[3px]"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
      role="dialog"
      aria-label="Card library"
    >
      <div className="flex max-h-[82vh] w-[min(880px,90vw)] flex-col overflow-hidden rounded-[22px] bg-cream shadow-frame">
        <div className="flex items-baseline gap-3 border-b border-linen px-6 py-4">
          <h3 className="text-[17px] font-bold text-roast">Card library</h3>
          <span className="text-[12px] italic text-fawn">everything the house can draw</span>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="ml-auto grid h-[30px] w-[30px] place-items-center rounded-full border border-linen bg-fluff text-[15px] text-fawn"
          >
            &times;
          </button>
        </div>

        <div className="overflow-y-auto px-6 py-4">
          <div className="mb-3.5 flex gap-4 text-[11.5px] text-fawn">
            {(Object.keys(STATE_LABEL) as CardRow['state'][]).map((s) => (
              <span key={s} className="flex items-center gap-1.5">
                <i className={`h-[7px] w-[7px] rounded-full ${STATE_LABEL[s].dot}`} />
                {STATE_LABEL[s].label}
              </span>
            ))}
          </div>

          <div className="grid grid-cols-[repeat(auto-fill,minmax(292px,1fr))] gap-3">
            {cards.map((c) => {
              const Component = cardComponentFor(c.type);
              const sample = SAMPLES[c.type];
              return (
                <div
                  key={c.type}
                  className="rounded-[14px] border border-linen bg-fluff px-3.5 py-3"
                >
                  <div className="flex items-center gap-2 text-[12.5px] font-semibold text-roast">
                    <i className={`h-[7px] w-[7px] rounded-full ${STATE_LABEL[c.state].dot}`} />
                    {c.type}
                  </div>
                  {c.purpose && (
                    <p className="mt-1 text-[11.5px] leading-relaxed text-fawn">{c.purpose}</p>
                  )}
                  <div className="relative mt-2.5 rounded-[11px] border border-linen bg-cream p-2.5">
                    <span className="absolute right-2 top-1 text-[8.5px] uppercase tracking-wider text-fawn/60">
                      live preview
                    </span>
                    <div className="mt-2 origin-top scale-[0.92]">
                      {Component && sample ? (
                        <Component props={sample} />
                      ) : (
                        <p className="py-3 text-center text-[11.5px] italic text-fawn">
                          {Component
                            ? 'No sample for this one yet.'
                            : 'Made for another surface.'}
                        </p>
                      )}
                    </div>
                  </div>
                  {c.data_fields && (
                    <div className="mt-2 border-t border-dotted border-linen pt-2 font-mono text-[10.5px] text-fawn">
                      {c.data_fields}
                    </div>
                  )}
                </div>
              );
            })}

            <form
              onSubmit={(e) => {
                e.preventDefault();
                const input = (e.currentTarget.elements.namedItem('ask') as HTMLInputElement);
                if (input.value.trim()) {
                  onCommission(input.value.trim());
                  input.value = '';
                }
              }}
              className="flex flex-col justify-center gap-2.5 rounded-[14px] border border-dashed border-bubble-line bg-parchment p-3.5"
            >
              <div className="flex items-center gap-2 text-[12.5px] font-semibold text-roast">
                <span className="grid h-6 w-6 place-items-center rounded-full border border-ember bg-gradient-to-b from-honey to-fennec text-[15px] leading-none text-roast">
                  +
                </span>
                Ask for a new card
              </div>
              <input
                name="ask"
                placeholder="a card that shows my week at a glance"
                className="w-full rounded-[9px] border border-linen bg-fluff px-2.5 py-[7px] text-[11.5px] text-roast placeholder:text-fawn focus:border-fennec focus:outline-none"
              />
              <p className="text-[11px] leading-relaxed text-fawn">
                Sulivan writes the spec, the workshop builds it, you approve at the gate. It
                appears here when it is done.
              </p>
            </form>
          </div>
        </div>
      </div>
    </div>
  );
}
