import type { ReactNode } from 'react';
import { nodeColor, nodeInitials } from './timelineModel';

/* One rail entry: circular initial node hanging on the timeline + card slot.
   The node is absolutely positioned into the container's left padding
   (mockup pattern) -- the parent list supplies pl-14 and position:relative. */
export function TimelineEntry({ author, children }: { author: string; children: ReactNode }) {
  const isUser = author === 'You';
  return (
    <div className="relative mb-4">
      <span
        aria-hidden="true"
        className={`absolute -left-14 top-0.5 grid h-11 w-11 place-items-center rounded-full border-[3px] border-fluff text-xs font-bold shadow-soft ${
          isUser ? 'text-fawn' : 'text-white'
        }`}
        style={{
          background: isUser
            ? nodeColor(author)
            : `radial-gradient(circle at 35% 30%, color-mix(in srgb, ${nodeColor(author)} 55%, #ffffff), ${nodeColor(author)})`,
        }}
      >
        {nodeInitials(author)}
      </span>
      {children}
    </div>
  );
}
