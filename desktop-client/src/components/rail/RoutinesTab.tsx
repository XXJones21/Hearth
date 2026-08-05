import { useState } from 'react';

type Routine = {
  name: string;
  schedule: string;
  checked: boolean;
};

const routines: Routine[] = [
  { name: 'Morning brief', schedule: 'daily · 7:30', checked: true },
  { name: 'Wind down', schedule: 'daily · 21:30', checked: true },
  { name: 'Nightly memory review', schedule: 'daily · 23:30', checked: false },
];

export function RoutinesTab() {
  const [checked, setChecked] = useState<boolean[]>(routines.map(r => r.checked));

  return (
    <ul className="space-y-1">
      {routines.map((r, idx) => (
        <li
          key={idx}
          className="flex items-center gap-3 rounded-xl bg-parchment border border-linen px-3 py-2.5"
        >
          <span className="flex-1">
            <span className="block text-[13px] text-roast">{r.name}</span>
            <span className="block text-[11.5px] text-fawn">{r.schedule}</span>
          </span>
          <button
            role="switch"
            aria-checked={checked[idx]}
            onClick={() => setChecked(prev => prev.map((v, i) => i === idx ? !v : v))}
            className={`h-5 w-[34px] rounded-full transition ${
              checked[idx] ? 'bg-fennec' : 'bg-linen'
            }`}
          />
        </li>
      ))}
    </ul>
  );
}
