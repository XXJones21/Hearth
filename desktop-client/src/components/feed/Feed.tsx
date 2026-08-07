import { useEffect, useMemo, useState } from 'react';
import { Composer } from './Composer';
import { StatusBar } from './StatusBar';
import { Timeline } from './Timeline';
import { buildTimeline } from './timelineModel';
import { IconBell, IconFilter, IconSearch } from '../shell/icons';
import { useAppStore } from '../../store/appStore';

type Props = {
  onSend: (text: string) => void;
};

export function Feed({ onSend }: Props) {
  const [filter, setFilter] = useState('');

  /* A tapped choice_card chip is an answer: it goes out as the user's turn,
     exactly as if they had typed the label. */
  useEffect(() => {
    const onChoice = (e: Event) => {
      const label = (e as CustomEvent<{ label?: string }>).detail?.label;
      if (label) onSend(label);
    };
    window.addEventListener('hearth-choice', onChoice);
    return () => window.removeEventListener('hearth-choice', onChoice);
  }, [onSend]);
  const messages = useAppStore((s) => s.messages);
  const draft = useAppStore((s) => s.activeAssistantDraft);
  const currentPersona = useAppStore((s) => s.currentPersonaName);
  const uiCards = useAppStore((s) => s.uiCards);

  const items = useMemo(
    () => buildTimeline(messages, draft, currentPersona, filter, uiCards),
    [messages, draft, currentPersona, filter, uiCards]
  );

  return (
    <main className="flex h-full min-h-0 min-w-0 flex-col p-5" aria-label="Today">
      <div className="mb-4 flex items-center gap-2.5">
        <div className="flex flex-1 items-center gap-2.5 rounded-full border border-linen bg-parchment px-4 py-2.5">
          <IconSearch className="h-4 w-4 shrink-0 text-fawn" />
          <input
            type="search"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            placeholder="Search today"
            aria-label="Search the conversation"
            className="w-full bg-transparent text-sm text-roast outline-none placeholder:text-fawn"
          />
        </div>
        <button
          type="button"
          className="grid h-10 w-10 shrink-0 place-items-center rounded-full border border-linen bg-fluff text-fawn shadow-soft"
          aria-label="Filter"
        >
          <IconFilter className="h-[17px] w-[17px]" />
        </button>
        <button
          type="button"
          className="grid h-10 w-10 shrink-0 place-items-center rounded-full border border-linen bg-fluff text-fawn shadow-soft"
          aria-label="Notifications"
        >
          <IconBell className="h-[17px] w-[17px]" />
        </button>
      </div>


      <div className="min-h-0 flex-1">
        <Timeline items={items} onPrompt={onSend} />
      </div>

      <StatusBar />
      <Composer onSend={onSend} />
    </main>
  );
}
