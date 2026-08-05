import type { ReactNode } from 'react';

/* The floating Direction B frame: rounded, shadowed, three-column grid.
   Below lg the stage and rail hide (they carry max-lg:hidden themselves). */
export function AppFrame({ children }: { children: ReactNode }) {
  return (
    <div className="relative z-[1] grid h-full max-h-[min(860px,calc(100vh_-_3rem))] w-full max-w-[1320px] grid-cols-[300px_minmax(0,1fr)_320px] overflow-hidden rounded-[26px] bg-fluff shadow-frame max-lg:grid-cols-1">
      {children}
    </div>
  );
}
