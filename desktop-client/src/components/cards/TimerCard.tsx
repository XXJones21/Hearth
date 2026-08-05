import { FC, useEffect, useRef } from 'react';
import type { CardProps, TimerCardProps } from './types';

/* Beat: fills the TimerCard stub. Renders a card shell with one row per
   timer entry: label in text-roast, remaining time right-aligned as m:ss. */
export const TimerCard: FC<CardProps> = ({ props }) => {
  const timers = (props as unknown as TimerCardProps).timers;
  const tickRef = useRef<number | null>(null);

  const formatMSS = (epochSeconds: string) => {
    const now = Math.floor(Date.now() / 1000);
    const diff = parseInt(epochSeconds, 10) - now;
    const remaining = Math.max(diff, 0);
    const m = Math.floor(remaining / 60);
    const s = remaining % 60;
    return `${m}:${s.toString().padStart(2, '0')}`;
  };

  useEffect(() => {
    const id = window.setInterval(() => {
      timers.forEach((entry) => {
        entry.fire_at = formatMSS(entry.fire_at);
      });
    }, 1000);
    tickRef.current = id;

    return () => {
      window.clearInterval(id);
    };
  }, [timers.length]);

  return (
    <div className="rounded-2xl border border-linen bg-fluff px-4 py-3 shadow-soft">
      {timers.map((entry) => (
        <div
          key={entry.label}
          className="flex justify-between items-baseline gap-3"
        >
          <span className="text-roast whitespace-nowrap">{entry.label}</span>
          <span className="text-roast text-right tabular-nums">
            {formatMSS(entry.fire_at)}
          </span>
        </div>
      ))}
    </div>
  );
};
