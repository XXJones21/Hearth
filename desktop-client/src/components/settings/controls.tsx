/* Row primitives for the Settings panel. Direction B tokens only: fluff
   surfaces, linen borders, roast ink, fennec for the one live accent. */

import type { ReactNode } from 'react';
import { can, type Capability } from '../../lib/clientProfile';

export function Section({
  label,
  sub,
  needs,
  children,
}: {
  label: string;
  sub: string;
  /** capability this whole section requires; absent renders nothing */
  needs?: Capability;
  children: ReactNode;
}) {
  if (needs && !can(needs)) return null;
  return (
    <section className="mb-6">
      <h3 className="text-[11px] font-bold uppercase tracking-[0.18em] text-ember">{label}</h3>
      <p className="mb-2.5 text-[12px] italic text-fawn">{sub}</p>
      {children}
    </section>
  );
}

export function Row({
  label,
  hint,
  needs,
  house,
  children,
}: {
  label: ReactNode;
  hint?: string;
  needs?: Capability;
  /** house-scoped: shown read-only until the settings API exists */
  house?: boolean;
  children?: ReactNode;
}) {
  if (needs && !can(needs)) return null;
  return (
    <div
      className={`mt-2 flex items-center gap-3.5 rounded-[14px] border border-linen bg-fluff px-4 py-3 first:mt-0 ${
        house ? 'opacity-60' : ''
      }`}
    >
      <div className="min-w-0">
        <div className="text-[13.5px] text-roast">{label}</div>
        {hint && <div className="mt-0.5 text-[11.5px] leading-snug text-fawn">{hint}</div>}
      </div>
      <div className="ml-auto flex shrink-0 items-center gap-2.5">
        {house && <HouseBadge />}
        {children}
      </div>
    </div>
  );
}

export function HouseBadge() {
  return (
    <span className="rounded-full border border-bubble-line bg-tab px-2 py-[3px] text-[10px] font-semibold uppercase tracking-wide text-roast">
      The house
    </span>
  );
}

export function Toggle({
  checked,
  onChange,
  label,
  disabled,
}: {
  checked: boolean;
  onChange: (v: boolean) => void;
  label: string;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className={`relative h-[23px] w-10 shrink-0 rounded-full transition ${
        checked ? 'bg-fennec' : 'bg-linen'
      } ${disabled ? 'cursor-default' : ''}`}
    >
      <span
        className="absolute top-[3px] h-[17px] w-[17px] rounded-full bg-fluff shadow-soft transition-all"
        style={{ left: checked ? '20px' : '3px' }}
      />
    </button>
  );
}

export function Segmented<T extends string>({
  value,
  options,
  onChange,
  label,
}: {
  value: T;
  options: { id: T; label: string }[];
  onChange: (v: T) => void;
  label: string;
}) {
  return (
    <div
      role="radiogroup"
      aria-label={label}
      className="flex rounded-full border border-linen bg-parchment p-[3px]"
    >
      {options.map((o) => (
        <button
          key={o.id}
          type="button"
          role="radio"
          aria-checked={value === o.id}
          onClick={() => onChange(o.id)}
          className={
            value === o.id
              ? 'rounded-full bg-fluff px-3.5 py-[5px] text-[12px] font-semibold text-roast shadow-soft'
              : 'rounded-full px-3.5 py-[5px] text-[12px] text-fawn transition hover:text-roast'
          }
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

export function Btn({
  children,
  onClick,
  tone,
  disabled,
}: {
  children: ReactNode;
  onClick?: () => void;
  tone?: 'warn';
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className={`rounded-full border bg-fluff px-3.5 py-[7px] text-[12px] font-semibold shadow-soft transition disabled:opacity-40 ${
        tone === 'warn'
          ? 'border-[#E8CFC2] text-[#8A3D2A] hover:bg-glowtint'
          : 'border-linen text-roast hover:border-bubble-line hover:bg-glowtint'
      }`}
    >
      {children}
    </button>
  );
}

export function IconFolder({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.9"
      strokeLinejoin="round"
      className={className}
      aria-hidden="true"
    >
      <path d="M3 7.5A1.5 1.5 0 0 1 4.5 6h4l2 2.5h7A1.5 1.5 0 0 1 19 10v7.5A1.5 1.5 0 0 1 17.5 19h-13A1.5 1.5 0 0 1 3 17.5z" />
    </svg>
  );
}
