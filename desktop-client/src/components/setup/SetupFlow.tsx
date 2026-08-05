import { useCallback, useEffect, useState } from 'react';
import {
  download,
  fixtures as loadFixtures,
  hasProbe,
  human,
  makePlan,
  modelDir,
  scan,
  type Machine,
  type Plan,
  type Progress,
} from '../../lib/probe';
import { loadSettings } from '../../lib/settings';

type Step = 'scanning' | 'found' | 'installing' | 'done' | 'blocked';

/* First run. The client is the installer, so this is the whole of the install
   experience: look at the machine, say what it can run and why, fetch it.

   Every number and every sentence of justification comes from the plan. None
   of it is written here, because a screen that invents its own explanation is
   a screen that will eventually lie. */
export function SetupFlow({ onExit }: { onExit: () => void }) {
  const [step, setStep] = useState<Step>('scanning');
  const [machine, setMachine] = useState<Machine | null>(null);
  const [plan, setPlan] = useState<Plan | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [progress, setProgress] = useState<Progress[]>([]);
  const [dest, setDest] = useState('');
  const [sims, setSims] = useState<string[]>([]);
  const [sim, setSim] = useState<string | undefined>(undefined);

  const run = useCallback(async (simulate?: string) => {
    setStep('scanning');
    setError(null);
    setProgress([]);
    try {
      const m = await scan(simulate);
      setMachine(m);
      const p = await makePlan(simulate);
      setPlan(p);
      setStep('found');
    } catch (e) {
      setError(String(e));
      setStep('blocked');
    }
  }, []);

  useEffect(() => {
    if (!hasProbe()) {
      setError('The hardware scan only runs inside the packaged app, not the browser dev server.');
      setStep('blocked');
      return;
    }
    loadFixtures().then(setSims).catch(() => {});
    modelDir().then(setDest).catch(() => {});
    run();
  }, [run]);

  const startDownload = async () => {
    setStep('installing');
    try {
      await download(
        (p) =>
          setProgress((prev) => {
            const next = prev.filter((x) => x.what !== p.what);
            return [...next, p];
          }),
        { simulate: sim, dest: dest || undefined },
      );
      setStep('done');
    } catch (e) {
      setError(String(e));
    }
  };

  return (
    <div className="flex min-w-0 flex-col overflow-y-auto px-16 py-12 max-lg:px-7">
      <DevBar
        sims={sims}
        active={sim}
        onPick={(s) => {
          setSim(s);
          run(s);
        }}
        onExit={onExit}
      />

      {step === 'blocked' && (
        <Panel title="Cannot go on">
          <p className="max-w-[58ch] text-[15px] leading-relaxed text-fawn">{error}</p>
        </Panel>
      )}

      {step === 'scanning' && (
        <Panel title="Looking at your machine.">
          <p className="max-w-[58ch] text-[15px] leading-relaxed text-fawn">
            Hearth runs entirely on your hardware, so what it can do depends on what you have.
          </p>
        </Panel>
      )}

      {step === 'found' && machine && plan && (
        <Found machine={machine} plan={plan} dest={dest} onDest={setDest} onGo={startDownload} />
      )}

      {(step === 'installing' || step === 'done') && plan && (
        <Installing plan={plan} progress={progress} done={step === 'done'} error={error} />
      )}
    </div>
  );
}

function Panel({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mt-6">
      <h1 className="text-[26px] font-bold tracking-tight">{title}</h1>
      <div className="mt-3">{children}</div>
    </div>
  );
}

function Found({
  machine,
  plan,
  dest,
  onDest,
  onGo,
}: {
  machine: Machine;
  plan: Plan;
  dest: string;
  onDest: (v: string) => void;
  onGo: () => void;
}) {
  const gpu = machine.gpu;
  const memory = gpu?.vram_bytes ?? machine.ram_bytes;
  return (
    <>
      <Panel title={plan.coexist ? 'This machine can run the full thing.' : 'A small machine. Here is the honest picture.'}>
        <p className="max-w-[58ch] text-[15px] leading-relaxed text-fawn">
          Here is what Hearth will install, and why.
        </p>
      </Panel>

      <div className="mt-7 grid gap-5 lg:grid-cols-2">
        <Card head="Your machine">
          <Row k="System" v={`${machine.os} / ${machine.arch}`} />
          <Row k="Graphics" v={gpu?.name ?? 'none detected'} />
          <Row k={gpu?.vram_bytes ? 'Video memory' : 'Memory'} v={human(memory)} />
          <Row k="Free disk" v={human(machine.free_disk_bytes)} />
          {machine.wsl_present !== null && (
            <Row k="Linux subsystem" v={machine.wsl_present ? 'Ready' : 'Not installed'} />
          )}
          {machine.simulated && <Row k="Simulated" v={machine.simulated} />}
        </Card>

        <div className="flex flex-col rounded-2xl border border-bubble-line bg-glowtint p-5 shadow-soft">
          <span className="self-start rounded-full border border-bubble-line bg-bubble px-2.5 py-1 text-[11px] font-semibold uppercase tracking-wide">
            {plan.label}
          </span>
          <div className="mt-3 text-[19px] font-bold">{plan.model}</div>
          <div className="mt-1 break-all font-mono text-[12px] text-fawn">
            {plan.repo}/{plan.file}
          </div>
          <p className="mt-3 text-[13.5px] leading-snug text-fawn">{plan.note}</p>
          <div className="mt-auto border-t border-bubble-line pt-3">
            {plan.downloads.map((d) => (
              <div key={d.what} className="flex justify-between py-0.5 text-[13.5px]">
                <span className="text-fawn">{d.what}</span>
                <span className="font-semibold tabular-nums">{human(d.bytes)}</span>
              </div>
            ))}
            <div className="mt-1.5 flex justify-between border-t border-bubble-line pt-2 text-[14.5px] font-bold">
              <span>Download</span>
              <span className="tabular-nums">{human(plan.total_download_bytes)}</span>
            </div>
          </div>
        </div>
      </div>

      {plan.warnings.map((w) => (
        <div
          key={w}
          className="mt-5 flex max-w-[70ch] gap-3 rounded-xl border border-bubble-line bg-bubble px-4 py-3 text-[13.5px] leading-snug"
        >
          <span className="grid size-5 flex-none place-items-center rounded-full bg-honey text-[12px] font-bold">
            !
          </span>
          <span>{w}</span>
        </div>
      ))}

      <Card head="What it will configure" className="mt-6">
        <Row k="Context window" v={`${plan.n_ctx.toLocaleString()} tokens`} />
        <Row k="Backend" v={plan.backend} />
        <Row k="Layers on the GPU" v={plan.n_gpu_layers === -1 ? 'all' : String(plan.n_gpu_layers)} />
        {plan.cuda_arch && <Row k="CUDA architecture" v={plan.cuda_arch} />}
        <Row k="Mind and voice" v={plan.coexist ? 'both resident' : 'one at a time'} />
      </Card>

      <div className="mt-6">
        <div className="text-[11.5px] font-semibold uppercase tracking-wide text-fawn">Why</div>
        <ul className="mt-2 max-w-[74ch] space-y-1.5">
          {plan.reasons.map((r) => (
            <li key={r} className="text-[13.5px] leading-snug text-fawn">
              {r}
            </li>
          ))}
        </ul>
      </div>

      <label className="mt-6 block max-w-[560px]">
        <span className="text-[11.5px] font-semibold uppercase tracking-wide text-fawn">
          Where the weights go
        </span>
        <input
          value={dest}
          onChange={(e) => onDest(e.target.value)}
          className="mt-2 w-full rounded-full border border-linen bg-parchment px-4 py-2.5 text-[14px] outline-none"
        />
      </label>

      <div className="mt-7 flex gap-3 pb-4">
        <button
          onClick={onGo}
          className="rounded-full bg-roast px-6 py-2.5 text-[14px] font-bold text-cream"
        >
          Download {human(plan.total_download_bytes)}
        </button>
      </div>
    </>
  );
}

function Installing({
  plan,
  progress,
  done,
  error,
}: {
  plan: Plan;
  progress: Progress[];
  done: boolean;
  error: string | null;
}) {
  const total = plan.total_download_bytes;
  const got = progress.reduce(
    (n, p) => n + (p.state === 'done' ? p.totalBytes : p.doneBytes),
    0,
  );
  const pct = total ? Math.min(100, (got / total) * 100) : 0;
  return (
    <>
      <Panel title={done ? 'Downloaded.' : 'Setting up.'}>
        <p className="max-w-[58ch] text-[15px] leading-relaxed text-fawn">
          {done
            ? 'Everything the plan asked for is on disk.'
            : 'You can leave this running. Nothing here needs you.'}
        </p>
      </Panel>

      <div className="mt-6 max-w-[600px]">
        <div className="h-[7px] overflow-hidden rounded-full bg-linen">
          <div
            className="h-full rounded-full bg-gradient-to-r from-fennec to-honey transition-[width]"
            style={{ width: `${pct}%` }}
          />
        </div>
        <div className="mt-2 flex justify-between text-[13px] text-fawn">
          <span>
            {human(got)} of {human(total)}
          </span>
          <span className="tabular-nums">{pct.toFixed(1)}%</span>
        </div>

        <div className="mt-5">
          {plan.downloads.map((d) => {
            const p = progress.find((x) => x.what === d.what);
            const state = p?.state ?? 'waiting';
            return (
              <div
                key={d.what}
                className="flex items-center gap-3 border-b border-linen py-3 text-[14.5px] last:border-b-0"
              >
                <span className="grid size-5 flex-none place-items-center rounded-full bg-peach text-[11px] font-bold text-ember">
                  {state === 'done' ? '✓' : state === 'failed' ? '!' : '·'}
                </span>
                <span className={state === 'waiting' ? 'text-fawn opacity-60' : ''}>{d.what}</span>
                <span className="ml-auto text-[13px] tabular-nums text-fawn">
                  {p && state === 'downloading'
                    ? `${human(p.doneBytes)} / ${human(p.totalBytes)}`
                    : state === 'skipped'
                      ? p?.message
                      : state === 'done'
                        ? human(d.bytes)
                        : ''}
                </span>
              </div>
            );
          })}
        </div>

        {error && (
          <div className="mt-5 rounded-xl border border-bubble-line bg-bubble px-4 py-3 text-[13.5px]">
            {error}
          </div>
        )}
      </div>
    </>
  );
}

function Card({
  head,
  children,
  className = '',
}: {
  head: string;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={`rounded-2xl border border-linen bg-fluff p-5 shadow-soft ${className}`}>
      <div className="mb-3 text-[11.5px] font-semibold uppercase tracking-wide text-fawn">
        {head}
      </div>
      {children}
    </div>
  );
}

function Row({ k, v }: { k: string; v: string }) {
  return (
    <div className="flex justify-between border-b border-linen py-1.5 text-[14px] last:border-b-0">
      <span className="text-fawn">{k}</span>
      <span className="font-semibold tabular-nums">{v}</span>
    </div>
  );
}

/* Developer strip. This is how a small-machine install gets exercised from a
   machine that is not small. Hidden unless Settings > Developer is on. */
function DevBar({
  sims,
  active,
  onPick,
  onExit,
}: {
  sims: string[];
  active?: string;
  onPick: (s?: string) => void;
  onExit: () => void;
}) {
  return (
    <div className="flex flex-wrap items-center gap-2 border-b border-linen pb-3 text-[12px]">
      {/* Machine simulation is a building tool. Close stays outside the gate,
          or turning developer mode off would trap you in the setup view. */}
      {loadSettings().developerMode && (
        <>
      <span className="text-fawn">Pretend to be:</span>
      <button
        onClick={() => onPick(undefined)}
        className={`rounded-lg border px-2.5 py-1 ${
          !active ? 'border-ember bg-ember text-cream' : 'border-linen bg-parchment text-fawn'
        }`}
      >
        this machine
      </button>
      {sims.map((s) => (
        <button
          key={s}
          onClick={() => onPick(s)}
          className={`rounded-lg border px-2.5 py-1 ${
            active === s ? 'border-ember bg-ember text-cream' : 'border-linen bg-parchment text-fawn'
          }`}
        >
          {s}
        </button>
      ))}
        </>
      )}
      <button onClick={onExit} className="ml-auto rounded-lg border border-linen bg-parchment px-2.5 py-1 text-fawn">
        Close
      </button>
    </div>
  );
}
