import { useEffect, useRef } from 'react';
import { MessageCard } from './MessageCard';
import { TimelineEntry } from './TimelineEntry';
import type { TimelineItem } from './timelineModel';
import { cardComponentFor } from '../cards/registry';
import { useAppStore } from '../../store/appStore';

function suggestedPrompts(classification?: string): string[] {
  if ((classification || '').toLowerCase() === 'abstract') {
    return [
      'What can you help me with today?',
      "What's on my plate this week?",
      'What did we talk about yesterday?',
    ];
  }
  return [
    'What should I work on first?',
    'Summarize the current state of the workspace.',
    'Help me debug the last change I made.',
  ];
}

type Props = {
  items: TimelineItem[];
  onPrompt?: (text: string) => void;
};

export function Timeline({ items, onPrompt }: Props) {
  const personaConfig = useAppStore((s) => s.personaConfig);
  const connection = useAppStore((s) => s.connection);
  const currentPersonaName = useAppStore((s) => s.currentPersonaName);
  const bottomRef = useRef<HTMLDivElement | null>(null);
  const streamingText = items.find(
    (i) => i.kind === 'message' && i.streaming
  );

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ block: 'end', behavior: 'smooth' });
  }, [items.length, streamingText && streamingText.kind === 'message' ? streamingText.text : '']);

  if (items.length === 0) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-4 text-center">
        <p className="max-w-[340px] text-[13px] leading-relaxed text-fawn">
          {personaConfig?.description || 'Your home companion is ready when you are.'}
        </p>
        <div className="flex flex-wrap justify-center gap-2">
          {suggestedPrompts(personaConfig?.classification).map((p) => (
            <button
              key={p}
              type="button"
              onClick={() => {
                if (connection === 'ready') onPrompt?.(p);
              }}
              disabled={connection !== 'ready'}
              className="rounded-full border border-linen bg-parchment px-3.5 py-1.5 text-xs text-roast transition hover:border-fennec/50 hover:bg-glowtint disabled:opacity-40"
            >
              {p}
            </button>
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="relative h-full min-h-0 overflow-y-auto pl-14 pr-1">
      {/* the rail line, drawn behind the nodes */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute bottom-2 left-[21px] top-2 w-[2px] rounded bg-linen"
      />
      {items.map((item) => {
        if (item.kind === 'message') {
          return (
            <TimelineEntry key={item.id} author={item.author}>
              <MessageCard
                role={item.role}
                author={item.author}
                text={item.text}
                ts={item.ts}
                streaming={item.streaming}
              />
            </TimelineEntry>
          );
        }
        const Card = cardComponentFor(item.cardType);
        if (!Card) return null; /* unknown type: no entry, no empty node */
        return (
          <TimelineEntry key={item.id} author={currentPersonaName || 'Hearth'}>
            <Card props={item.props} />
          </TimelineEntry>
        );
      })}
      <div ref={bottomRef} />
    </div>
  );
}
