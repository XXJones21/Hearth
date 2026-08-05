import { Suspense, lazy } from 'react';
import { OrbGlow } from './OrbGlow';
import { PersonaChips } from './PersonaChips';
import { IconBook, IconGear, IconGrid, IconHome, IconPerson } from '../shell/icons';
import { useAppStore } from '../../store/appStore';
import type { PersonaConfig } from '../../types/persona';

const PersonaCanvas = lazy(() => import('../PersonaCanvas'));

type Props = {
  config: PersonaConfig | null;
  onSwitch: (name: string) => void;
};

export function PersonaStage({ config, onSwitch }: Props) {
  const connection = useAppStore((s) => s.connection);
  const current = useAppStore((s) => s.currentPersonaName);
  const attempt = useAppStore((s) => s.connectionAttempt);
  const activeView = useAppStore((s) => s.activeView);
  const setActiveView = useAppStore((s) => s.setActiveView);

  const dotClass =
    connection === 'ready'
      ? 'bg-emerald-600'
      : connection === 'connecting'
        ? 'bg-honey animate-pulse'
        : 'bg-red-400';
  const statusLabel =
    connection === 'ready'
      ? 'Joshua · home'
      : connection === 'connecting'
        ? `Reconnecting (attempt ${attempt})...`
        : 'Disconnected';

  return (
    <aside
      className="flex flex-col items-center border-r border-linen bg-gradient-to-b from-fluff to-cream p-6 pb-5 max-lg:hidden"
      aria-label="Persona"
    >
      <div className="flex w-full items-center gap-2 self-start text-xs text-fawn" aria-live="polite">
        <span className={`h-2 w-2 shrink-0 rounded-full ${dotClass}`} />
        {statusLabel}
      </div>

      <div className="mt-4 min-h-0 w-full flex-[3]">
        <OrbGlow>
          <Suspense fallback={null}>
            <PersonaCanvas config={config} />
          </Suspense>
        </OrbGlow>
      </div>

      <h1 className="mt-3 text-[22px] font-bold text-roast">{current ?? 'Hearth'}</h1>
      <div className="mt-0.5 line-clamp-2 text-center text-[13px] text-fawn">
        {config?.description || 'your daily companion'}
      </div>

      <div className="mt-auto pt-4">
        <PersonaChips onSwitch={onSwitch} />
      </div>

      <nav className="mt-5 flex gap-[22px] text-fawn" aria-label="Sections">
        <button type="button" aria-label="Home" onClick={() => setActiveView('home')}>
          <IconHome className={`h-5 w-5 ${activeView === 'home' ? 'text-ember' : ''}`} />
        </button>
        <button type="button" aria-label="Journal" onClick={() => setActiveView('journal')}>
          <IconBook className={`h-5 w-5 ${activeView === 'journal' ? 'text-ember' : ''}`} />
        </button>
        <button type="button" aria-label="Personas" onClick={() => setActiveView('personas')}>
          <IconPerson className={`h-5 w-5 ${activeView === 'personas' ? 'text-ember' : ''}`} />
        </button>
        <button type="button" aria-label="Apps" onClick={() => setActiveView('apps')}>
          <IconGrid className={`h-5 w-5 ${activeView === 'apps' ? 'text-ember' : ''}`} />
        </button>
        <button type="button" aria-label="Settings" onClick={() => setActiveView('settings')}>
          <IconGear className={`h-5 w-5 ${activeView === 'settings' ? 'text-ember' : ''}`} />
        </button>
      </nav>
    </aside>
  );
}
