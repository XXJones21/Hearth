import { FC } from 'react';
import type { CardProps, BriefTextProps } from './types';

/* Beat: fills the BriefTextCard stub. Renders a card shell with an
   optional title and a body paragraph. */
export const BriefTextCard: FC<CardProps> = ({ props }) => {
  const b = props as unknown as BriefTextProps;
  return (
    <div className="rounded-2xl border border-linen bg-fluff px-4 py-3 shadow-soft">
      {b.title && (
        <div className="text-[11.5px] font-bold uppercase tracking-wider text-ember">{b.title}</div>
      )}
      <div className="text-[14px] text-roast whitespace-pre-wrap">{b.body}</div>
    </div>
  );
};
