import { useState } from 'react';
import { MemoryTab } from './MemoryTab';
import { RoutinesTab } from './RoutinesTab';
import { SessionsTab } from './SessionsTab';
import { IconMoon, IconPlus } from '../shell/icons';
import { toggleTheme } from '../../lib/theme';

type TabId = 'sessions' | 'memory' | 'routines';

const TABS: { id: TabId; label: string }[] = [
  { id: 'sessions', label: 'Sessions' },
  { id: 'memory', label: 'Memory' },
  { id: 'routines', label: 'Routines' },
];

export function Rail() {
  const [tab, setTab] = useState<TabId>('memory');

  return (
    <aside
      className="flex flex-col border-l border-linen bg-gradient-to-b from-fluff to-cream p-5 max-lg:hidden"
      aria-label="Mission Control"
    >
      <div className="flex justify-end gap-2.5">
        <button
          type="button"
          aria-label="Toggle ember mode"
          onClick={() => toggleTheme()}
          className="grid h-10 w-10 place-items-center rounded-full border border-linen bg-fluff text-fawn shadow-soft"
        >
          <IconMoon className="h-4 w-4" />
        </button>
      </div>

      <div className="mt-4 flex gap-2" role="tablist" aria-label="Panels">
        {TABS.map((t) => (
          <button
            key={t.id}
            type="button"
            role="tab"
            aria-selected={tab === t.id}
            onClick={() => setTab(t.id)}
            className={
              tab === t.id
                ? 'rounded-full bg-tab px-3.5 py-2 text-[12.5px] font-semibold text-roast'
                : 'rounded-full px-3.5 py-2 text-[12.5px] text-fawn transition hover:text-roast'
            }
          >
            {t.label}
          </button>
        ))}
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto">
        {tab === 'sessions' && <SessionsTab />}
        {tab === 'memory' && <MemoryTab />}
        {tab === 'routines' && <RoutinesTab />}
      </div>

      <div className="mt-4 flex items-center gap-2.5">
        <button
          type="button"
          aria-label="New routine"
          className="grid h-11 w-11 shrink-0 place-items-center rounded-full border border-linen bg-fluff text-ember shadow-soft"
        >
          <IconPlus className="h-[18px] w-[18px]" />
        </button>
      </div>
    </aside>
  );
}
