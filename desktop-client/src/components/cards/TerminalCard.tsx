import { useEffect, useState, type ReactNode } from 'react';
import { getHttpOrigin } from '../../lib/config';
import type { CardProps, TerminalCardProps } from './types';

/* The generic report card for a delegated agent or a third-party CLI.
 *
 * Claude Code answers in markdown, and rendering that as a paragraph turned
 * a good answer into a wall of asterisks and backticks (live 2026-08-03).
 * This gives that class of output a console shape: a status bar, prose in the
 * body font, fenced blocks set as real command blocks, and anything the agent
 * could not run itself pulled out where the operator will see it.
 *
 * Deliberately one card type for every such tool. The next integration
 * reports through this too rather than earning its own type.
 *
 * While a run is in flight the card polls /claude/state and fills itself in,
 * so nobody has to ask "is it done yet". The header carries a collapsible
 * transcript of what the agent actually did, which the summary alone hides. */

const STATUS: Record<string, { label: string; dot: string; text: string }> = {
  running: { label: 'working', dot: 'bg-honey animate-pulse', text: 'text-fawn' },
  done: { label: 'done', dot: 'bg-emerald-600', text: 'text-[#0F7A52]' },
  error: { label: 'failed', dot: 'bg-[#B4553C]', text: 'text-[#8A3D2A]' },
  timeout: { label: 'timed out', dot: 'bg-[#B4553C]', text: 'text-[#8A3D2A]' },
  blocked: { label: 'needs you', dot: 'bg-honey', text: 'text-[#8A3D2A]' },
};

/** Inline `code`, **bold**, *italic*. Same vocabulary as the journal's. */
function inline(text: string, key: number): ReactNode {
  const parts: ReactNode[] = [];
  let rest = text;
  let i = 0;
  const pattern = /\*\*([^*]+)\*\*|\*([^*]+)\*|`([^`]+)`/;
  while (rest.length > 0) {
    const m = pattern.exec(rest);
    if (!m) {
      parts.push(rest);
      break;
    }
    if (m.index > 0) parts.push(rest.slice(0, m.index));
    if (m[1] !== undefined) {
      parts.push(
        <strong key={`${key}-${i}`} className="font-semibold text-roast">
          {m[1]}
        </strong>,
      );
    } else if (m[2] !== undefined) {
      parts.push(<em key={`${key}-${i}`}>{m[2]}</em>);
    } else {
      parts.push(
        <code
          key={`${key}-${i}`}
          className="rounded border border-linen bg-parchment px-1 font-mono text-[0.9em] text-roast"
        >
          {m[3]}
        </code>,
      );
    }
    rest = rest.slice(m.index + m[0].length);
    i += 1;
  }
  return parts;
}

/** Split the body into prose and fenced blocks, then render each in kind. */
function Body({ text }: { text: string }) {
  const out: ReactNode[] = [];
  let k = 0;
  let bullets: ReactNode[] = [];

  const flush = () => {
    if (!bullets.length) return;
    out.push(
      <ul key={`u${k++}`} className="my-1.5 list-disc space-y-0.5 pl-5">
        {bullets}
      </ul>,
    );
    bullets = [];
  };

  // Fenced blocks first: everything between them is prose.
  const segments = text.split(/```[a-zA-Z]*\n?/);
  segments.forEach((segment, idx) => {
    const isFence = idx % 2 === 1;
    if (isFence) {
      flush();
      out.push(
        <pre
          key={`f${k++}`}
          className="my-2 overflow-x-auto rounded-[10px] border border-linen bg-[#FCFAF6] px-3 py-2.5 font-mono text-[11.5px] leading-[1.75] text-roast"
        >
          {segment.replace(/\n$/, '')}
        </pre>,
      );
      return;
    }
    segment.split('\n').forEach((line) => {
      const t = line.trim();
      if (!t) {
        flush();
        return;
      }
      if (/^#{1,4}\s/.test(t)) {
        flush();
        out.push(
          <div key={`h${k++}`} className="mt-2.5 text-[12.5px] font-semibold text-roast">
            {inline(t.replace(/^#{1,4}\s/, ''), k)}
          </div>,
        );
        return;
      }
      if (/^[-*]\s/.test(t)) {
        bullets.push(
          <li key={`b${k++}`} className="text-[12.5px] leading-relaxed">
            {inline(t.replace(/^[-*]\s/, ''), k)}
          </li>,
        );
        return;
      }
      flush();
      out.push(
        <p key={`p${k++}`} className="my-1.5 text-[12.5px] leading-relaxed">
          {inline(t, k)}
        </p>,
      );
    });
  });
  flush();
  return <div className="text-fawn">{out}</div>;
}

type LiveState = {
  status?: TerminalCardProps['status'];
  body?: string;
  steps?: string[];
  pending?: string[];
  cost_usd?: number | null;
  num_turns?: number | null;
  started?: number;
  finished?: number;
  run?: string | null;
};

export function TerminalCard({ props }: CardProps) {
  const p = props as unknown as TerminalCardProps;
  const [live, setLive] = useState<LiveState | null>(null);

  /* Poll only while THIS run can still change. A finished card is a
     transcript entry: it must not keep mutating as later runs happen. */
  const settled = (live?.status ?? p.status ?? 'done') !== 'running';
  useEffect(() => {
    if (!p.run_id || settled) return;
    let cancelled = false;
    const tick = async () => {
      try {
        const res = await fetch(`${getHttpOrigin()}/claude/state`, { cache: 'no-store' });
        if (!res.ok) return;
        const data = (await res.json()) as LiveState;
        if (!cancelled && data.run === p.run_id) setLive(data);
      } catch {
        /* server restarted or unreachable: the card keeps what it has */
      }
    };
    void tick();
    const id = window.setInterval(tick, 2000);
    return () => {
      cancelled = true;
      window.clearInterval(id);
    };
  }, [p.run_id, settled]);

  const [deciding, setDeciding] = useState<'approve' | 'deny' | null>(null);
  const [decideError, setDecideError] = useState('');

  /* Approve resumes the SAME Claude session with a grant scoped to the
     commands it asked for, so it verifies the work it already did instead of
     starting over. Deny closes the request and leaves the code as written. */
  const decide = async (approve: boolean) => {
    if (!p.run_id) return;
    setDeciding(approve ? 'approve' : 'deny');
    setDecideError('');
    try {
      const res = await fetch(`${getHttpOrigin()}/claude/decide`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ run_id: p.run_id, approve }),
      });
      const data = (await res.json()) as { ok?: boolean; error?: string };
      if (!data.ok) setDecideError(data.error || 'That did not go through.');
      else setLive((prev) => ({ ...(prev ?? {}), status: approve ? 'running' : prev?.status, pending: [] }));
    } catch {
      setDecideError('Could not reach the house.');
    } finally {
      setDeciding(null);
    }
  };

  const status = STATUS[(live?.status ?? p.status ?? 'done') as string] ?? STATUS.done;
  const body = live?.body ?? p.body;
  const steps = live?.steps ?? p.steps ?? [];
  const pending = live?.pending ?? p.pending ?? [];
  const meta =
    live && live.finished
      ? [
          live.num_turns ? `${live.num_turns} turns` : '',
          typeof live.cost_usd === 'number' ? `$${live.cost_usd.toFixed(2)}` : '',
          live.started ? `${Math.round(live.finished - live.started)}s` : '',
        ].filter(Boolean)
      : (p.meta ?? []);

  return (
    <div className="overflow-hidden rounded-[14px] border border-linen bg-fluff">
      <div className="flex items-center gap-2.5 border-b border-linen bg-parchment px-4 py-2.5">
        <span className={`h-2 w-2 shrink-0 rounded-full ${status.dot}`} />
        <span className="font-mono text-[12px] font-semibold text-roast">
          {p.title || 'Output'}
        </span>
        {p.subtitle && <span className="text-[11.5px] text-fawn">{p.subtitle}</span>}
        <span className={`ml-auto text-[11px] font-semibold uppercase tracking-wide ${status.text}`}>
          {status.label}
        </span>
      </div>

      {steps.length > 0 && (
        <details className="group border-b border-linen">
          <summary className="flex cursor-pointer list-none items-center gap-2 px-4 py-2 text-[11.5px] text-fawn hover:bg-glowtint">
            <span className="text-[10px] transition-transform group-open:rotate-90">&#9656;</span>
            {steps.length} step{steps.length === 1 ? '' : 's'}
            <span className="text-fawn/70">&middot; what it did</span>
          </summary>
          <ol className="border-t border-linen bg-[#FCFAF6] px-4 py-2.5">
            {steps.map((step, i) => (
              <li
                key={`${i}-${step}`}
                className="flex gap-2.5 py-[3px] font-mono text-[11px] leading-snug text-fawn"
              >
                <span className="w-4 shrink-0 text-right text-fawn/60">{i + 1}</span>
                <span className={step.includes('(refused)') ? 'text-[#8A3D2A]' : 'text-roast'}>
                  {step}
                </span>
              </li>
            ))}
          </ol>
        </details>
      )}

      <div className="px-4 py-3">
        {body ? (
          <Body text={body} />
        ) : (
          <p className="text-[12.5px] italic text-fawn">
            {status.label === 'working' ? 'Working...' : 'Nothing reported yet.'}
          </p>
        )}

        {pending.length > 0 && (
          <div className="mt-3 rounded-[10px] border border-[#E8CFC2] bg-[#FBF1EC] px-3 py-2.5">
            <div className="text-[11px] font-semibold uppercase tracking-wide text-[#8A3D2A]">
              Waiting on you
            </div>
            <p className="mt-1 text-[11.5px] leading-snug text-fawn">
              It wrote these but could not run them itself.
            </p>
            <div className="mt-2 overflow-x-auto font-mono text-[11.5px] leading-[1.8] text-roast">
              {pending.map((c) => (
                <div key={c} className="whitespace-pre">
                  {c}
                </div>
              ))}
            </div>
            {p.run_id && (
              <div className="mt-2.5 flex items-center gap-2">
                <button
                  type="button"
                  disabled={deciding !== null}
                  onClick={() => void decide(true)}
                  className="rounded-full border border-ember bg-gradient-to-b from-honey to-fennec px-3.5 py-[6px] text-[12px] font-semibold text-roast shadow-soft disabled:opacity-50"
                >
                  {deciding === 'approve' ? 'Approving' : 'Approve'}
                </button>
                <button
                  type="button"
                  disabled={deciding !== null}
                  onClick={() => void decide(false)}
                  className="rounded-full border border-linen bg-fluff px-3.5 py-[6px] text-[12px] font-semibold text-fawn shadow-soft disabled:opacity-50"
                >
                  Deny
                </button>
                <span className="text-[11px] text-fawn">
                  Approving lets it run only these, in this workspace.
                </span>
              </div>
            )}
            {decideError && (
              <p className="mt-2 text-[11.5px] text-[#8A3D2A]">{decideError}</p>
            )}
          </div>
        )}
      </div>

      {meta.length > 0 && (
        <div className="flex gap-3 border-t border-linen px-4 py-2 font-mono text-[11px] text-fawn">
          {meta.map((m) => (
            <span key={m}>{m}</span>
          ))}
        </div>
      )}
    </div>
  );
}
