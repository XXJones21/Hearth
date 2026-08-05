import { useAppStore } from '../../store/appStore';

type Props = {
  onSwitch: (name: string) => void;
};

export function PersonaChips({ onSwitch }: Props) {
  const personas = useAppStore((s) => s.personas);
  const current = useAppStore((s) => s.currentPersonaName);

  if (personas.length === 0) return null;

  return (
    <div className="flex flex-wrap justify-center gap-2" role="group" aria-label="Choose a companion">
      {personas.map((p) => {
        const active = current?.toLowerCase() === p.name.toLowerCase();
        return (
          <button
            key={p.name}
            type="button"
            aria-pressed={active}
            title={p.description || undefined}
            onClick={() => onSwitch(p.name)}
            className={
              active
                ? 'rounded-full bg-fennec px-3.5 py-1.5 text-xs font-semibold text-white shadow-soft'
                : 'rounded-full border border-linen bg-fluff px-3.5 py-1.5 text-xs text-roast transition hover:border-fennec/60 hover:bg-parchment'
            }
          >
            {p.name}
          </button>
        );
      })}
    </div>
  );
}
