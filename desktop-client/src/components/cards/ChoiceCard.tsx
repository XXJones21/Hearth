import { useState } from 'react';
import type { CardProps } from './types';

/* choice_card: a question with persona-authored options, the interview
 * mechanism from the first-run design. Tapping a chip dispatches
 * hearth-choice; the surface hosting the card decides what sending means
 * (the setup Interview sends it as the user's turn). The free composer
 * always outranks the chips, and the card says so.
 */

export const CHOICE_EVENT = 'hearth-choice';

type Option = { label: string; detail?: string };

export function ChoiceCard({ props }: CardProps) {
  const question = String(props.question ?? '');
  const options = (Array.isArray(props.options) ? props.options : []) as Option[];
  const allowFree = props.allow_free_text !== false;
  const [picked, setPicked] = useState<string | null>(null);

  if (!question || options.length === 0) return null;

  const choose = (label: string) => {
    setPicked(label);
    try {
      window.dispatchEvent(new CustomEvent(CHOICE_EVENT, { detail: { label, question } }));
    } catch {
      /* non-browser context */
    }
  };

  return (
    <div className="rounded-2xl border border-linen bg-fluff p-4 shadow-soft">
      <div className="text-[13px] font-semibold text-fawn">{question}</div>
      <div className="mt-3 grid gap-2 sm:grid-cols-2">
        {options.map((o) => (
          <button
            key={o.label}
            onClick={() => choose(o.label)}
            disabled={picked !== null}
            className={`rounded-xl border px-3.5 py-2.5 text-left transition-colors ${
              picked === o.label
                ? 'border-ember bg-ember text-cream'
                : picked !== null
                  ? 'border-linen bg-parchment opacity-50'
                  : 'border-linen bg-parchment hover:border-ember'
            }`}
          >
            <div className="text-[14px] font-bold">{o.label}</div>
            {o.detail && (
              <div
                className={`mt-0.5 text-[12.5px] leading-snug ${
                  picked === o.label ? 'text-cream' : 'text-fawn'
                }`}
              >
                {o.detail}
              </div>
            )}
          </button>
        ))}
      </div>
      {allowFree && picked === null && (
        <div className="mt-2.5 text-[12px] text-fawn">
          Or answer in your own words below; your words always win.
        </div>
      )}
    </div>
  );
}
