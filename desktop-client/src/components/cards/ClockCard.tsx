import { FC } from 'react';
import type { CardProps, ClockProps } from './types';

/* (originally a build-run stub; see
   tasks/hearth-shell/plan.md). Renders the clock card. */
export const ClockCard: FC<CardProps> = ({ props }) => {
  const c = props as unknown as ClockProps;
  return (
    <div className="rounded-2xl border border-linen bg-fluff px-4 py-3 shadow-soft">
      <div className="text-[28px] font-bold text-roast">{c.time}</div>
      {c.date && (
        <div className="text-[11.5px] text-fawn">{c.date}</div>
      )}
    </div>
  );
};
