import type { ReactNode } from 'react';

/* Warm glow + breathe wrapper around the persona canvas. The transform and
   drop-shadow animate on this wrapper; the canvas keeps its intrinsic size so
   three.js never renders through a scaled surface. Glow follows --persona.

   `halo` exists because the disc below is a still light for a persona that
   casts none. An orb is lit from outside, so the wrapper supplies the room.
   The fire is not: it draws its own halo in canvas, flickering, sized off its
   own body. Drawing both put a hard static disc behind a moving flame, and the
   disc read as the brighter of the two. */
export function OrbGlow({ children, halo = true }: { children: ReactNode; halo?: boolean }) {
  return (
    <div className="breathe relative h-full w-full">
      {halo && (
        <div
          aria-hidden="true"
          className="absolute left-1/2 top-1/2 aspect-square w-[85%] -translate-x-1/2 -translate-y-1/2 rounded-full blur-[2px]"
          style={{
            background:
              'radial-gradient(circle at 45% 40%, rgb(255 214 150 / 0.7), color-mix(in srgb, var(--persona-glow) 38%, transparent) 45%, color-mix(in srgb, var(--persona) 14%, transparent) 66%, transparent 74%)',
          }}
        />
      )}
      <div className="absolute inset-0">{children}</div>
    </div>
  );
}
