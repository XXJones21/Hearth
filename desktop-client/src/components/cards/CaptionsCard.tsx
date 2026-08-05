import { FC } from 'react';
import type { CardProps, CaptionsProps } from './types';

/* Beat: fills the CaptionsCard stub. Renders a card shell with a
   single italic fawn text paragraph. */
export const CaptionsCard: FC<CardProps> = ({ props }) => {
  const c = props as unknown as CaptionsProps;
  return (
    <div className="rounded-2xl border border-linen bg-fluff px-4 py-3 shadow-soft">
      <div className="text-[13px] text-fawn italic">{c.text}</div>
    </div>
  );
};
