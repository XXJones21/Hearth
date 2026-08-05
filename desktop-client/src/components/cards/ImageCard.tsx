import { useEffect, useState } from 'react';
import { getHttpOrigin } from '../../lib/config';
import { resolvePersonaAssetUrl } from '../../lib/resolveAssetUrl';
import type { CardProps, ImageCardProps } from './types';

/* A picture from the local art studio, shown from the moment it is asked for.
 *
 * The card lands in the timeline while the canvas is still blank and polls
 * /imagery/state until the render settles, the same arrangement the terminal
 * card uses for a delegated run. The old flow put nothing on screen at all
 * unless the operator asked a second time and the model happened to pick
 * check_image, so a turn could end with "it should be ready" and leave the
 * transcript empty.
 *
 * The frame keeps the finished picture's aspect while it is empty, so the
 * timeline does not jump when the image arrives. */

export function ImageCard({ props }: CardProps) {
  const p = props as unknown as ImageCardProps;
  const [live, setLive] = useState<Partial<ImageCardProps> | null>(null);

  const status = live?.status ?? p.status ?? 'done';
  const src = live?.src || p.src || '';
  const note = live?.note ?? p.note ?? '';

  /* Poll only while THIS drawing can still change. A settled card is a
     transcript entry and must not mutate when a later drawing starts. */
  useEffect(() => {
    if (!p.job_id || status !== 'running') return;
    let cancelled = false;
    const tick = async () => {
      try {
        const res = await fetch(`${getHttpOrigin()}/imagery/state`, { cache: 'no-store' });
        if (!res.ok) return;
        const data = (await res.json()) as Partial<ImageCardProps> & { job_id?: string };
        if (!cancelled && data.job_id === p.job_id) setLive(data);
      } catch {
        /* server restarted or unreachable: the card keeps what it has */
      }
    };
    void tick();
    const id = window.setInterval(tick, 2500);
    return () => {
      cancelled = true;
      window.clearInterval(id);
    };
  }, [p.job_id, status]);

  return (
    <div className="max-w-[560px] rounded-2xl border border-linen bg-fluff px-4 py-3 shadow-soft">
      <div className="mb-2 flex items-center gap-2">
        <span className="text-[11.5px] font-bold uppercase tracking-wider text-ember">
          {p.title || 'From the easel'}
        </span>
        {status === 'running' && (
          <span className="flex items-center gap-1.5 text-[11px] text-fawn">
            <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-honey" />
            drawing
          </span>
        )}
      </div>

      {status === 'error' ? (
        <p className="text-[13px] leading-relaxed text-[#8A3D2A]">
          {note || 'The drawing did not finish.'}
        </p>
      ) : (
        <div className="relative aspect-[3/2] w-full overflow-hidden rounded-xl bg-parchment">
          {src ? (
            <img
              src={resolvePersonaAssetUrl(src, '')}
              alt={p.prompt || ''}
              className="h-full w-full object-cover"
            />
          ) : (
            /* The blank canvas: a slow warm sweep, not a spinner. Nothing is
               measurable here, so a progress bar would be a lie. */
            <div className="h-full w-full animate-pulse bg-gradient-to-br from-parchment via-glowtint to-parchment" />
          )}
        </div>
      )}

      {p.prompt && (
        <p className="mt-2.5 text-[13px] leading-relaxed text-fawn">{p.prompt}</p>
      )}
    </div>
  );
}
