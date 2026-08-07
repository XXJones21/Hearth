import { Suspense, lazy, useCallback, useEffect, useRef, useState } from 'react';
import { open as openDialog } from '@tauri-apps/plugin-dialog';
import { OrbGlow } from '../stage/OrbGlow';
/* The persona ships with the client, as the same JSON the server would send.
   Sulivan has to be present during first run, before any backend exists, and
   the installer writes this same file into the backend when it provisions.
   One file, two uses, no transcription to drift. Model selection is absent on
   purpose: the hardware scan decides it at install time. */
import sulivan from '../../personas/sulivan.json';
import type { PersonaConfig } from '../../types/persona';

const SULIVAN = sulivan as unknown as PersonaConfig;

const PersonaCanvas = lazy(() => import('../PersonaCanvas'));
import {
  download,
  fixtures as loadFixtures,
  freeDisk,
  hasProbe,
  human,
  installRoot,
  makePlan,
  provision,
  PROVISION_ROWS,
  PROVISION_WEIGHTS,
  scan,
  type Machine,
  type Plan,
  type Progress,
} from '../../lib/probe';
import { houseStart } from '../../lib/house';
import { loadSettings, saveSettings } from '../../lib/settings';
import { Interview } from './Interview';
import { VoiceTest } from './VoiceTest';

type Step = 'welcome' | 'scanning' | 'found' | 'installing' | 'voice-test' | 'interview' | 'blocked';

/* The blocked panel serves three different misfortunes, and they deserve
   different sentences. A dev server is not a broken machine, and a machine
   that is too small is not an error: it is the product's honest refusal. */
type BlockedKind = 'no-probe' | 'scan-failed' | 'refused';

/* First run. The client is the installer, so this is the whole of the install
   experience: greet, look at the machine, say what it can run and why, fetch
   it, verify it.

   Every number and every sentence of justification comes from the plan. None
   of it is written here, because a screen that invents its own explanation is
   a screen that will eventually lie.

   `onExit(installed)`: only an install that actually completed may mark setup
   complete. Closing out of a blocked or unfinished setup leaves the flag
   false, so the next launch comes back here instead of dropping the person
   into an empty house that dials a backend which does not exist. */
export function SetupFlow({ onExit }: { onExit: (installed: boolean) => void }) {
  const [step, setStep] = useState<Step>('welcome');
  const [blockedKind, setBlockedKind] = useState<BlockedKind>('scan-failed');
  const [machine, setMachine] = useState<Machine | null>(null);
  const [plan, setPlan] = useState<Plan | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [progress, setProgress] = useState<Progress[]>([]);
  const [dest, setDest] = useState('');
  const [destFree, setDestFree] = useState<number | null>(null);
  const [sims, setSims] = useState<string[]>([]);
  const [sim, setSim] = useState<string | undefined>(undefined);
  const [connectNote, setConnectNote] = useState(false);

  const run = useCallback(async (simulate?: string) => {
    setStep('scanning');
    setError(null);
    setProgress([]);
    setDestFree(null);
    let m: Machine;
    try {
      m = await scan(simulate);
      setMachine(m);
    } catch (e) {
      setError(String(e));
      setBlockedKind('scan-failed');
      setStep('blocked');
      return;
    }
    try {
      const p = await makePlan(simulate);
      setPlan(p);
      setStep('found');
    } catch (e) {
      setError(String(e));
      setBlockedKind('refused');
      setStep('blocked');
    }
  }, []);

  useEffect(() => {
    if (!hasProbe()) {
      setError('The hardware scan only runs inside the packaged app, not the browser dev server.');
      setBlockedKind('no-probe');
      setStep('blocked');
      return;
    }
    loadFixtures().then(setSims).catch(() => {});
    installRoot().then(setDest).catch(() => {});
  }, []);

  /* The chosen destination decides which volume the free-disk figure and the
     disk warning describe, so the plan follows the box. Debounced: this fires
     per keystroke while someone types a path. Fixtures keep their recorded
     numbers; recomputing them against this machine's disks would overwrite
     the story the fixture exists to tell. */
  const destSeq = useRef(0);
  useEffect(() => {
    if (step !== 'found' || sim || !dest.trim()) return;
    const seq = ++destSeq.current;
    const t = window.setTimeout(() => {
      Promise.all([freeDisk(dest), makePlan(undefined, dest)])
        .then(([free, p]) => {
          if (seq !== destSeq.current) return;
          setDestFree(free);
          setPlan(p);
        })
        .catch(() => {
          /* an unfinished path mid-typing; the last good plan stands */
        });
    }, 400);
    return () => window.clearTimeout(t);
  }, [dest, sim, step]);

  const browse = async () => {
    try {
      const picked = await openDialog({
        directory: true,
        defaultPath: dest || undefined,
        title: 'Where Hearth installs',
      });
      if (typeof picked === 'string' && picked) setDest(picked);
    } catch {
      /* dialog unavailable; the text box still works */
    }
  };

  const startDownload = async () => {
    setStep('installing');
    setError(null);
    const onProgress = (p: Progress) =>
      setProgress((prev) => {
        const next = prev.filter((x) => x.what !== p.what);
        return [...next, p];
      });
    try {
      /* The model download and the runtime placement run together, as the
         mockup always showed. Both must land before the install is one. */
      await Promise.all([
        download(onProgress, { simulate: sim, dest: dest || undefined }),
        provision(onProgress, { root: dest, accel: plan?.backend ?? 'cpu' }),
      ]);
      /* The chosen root is what boot revalidates against, so it persists the
         moment the record exists, not when the user leaves the screen. */
      saveSettings({ installRoot: dest });
      /* No Go-to-the-house button: the install proves itself instead. The
         house starts, and the exit from setup is Sulivan speaking and a
         person saying they heard him. */
      await houseStart(dest);
      setStep('voice-test');
    } catch (e) {
      setError(String(e));
    }
  };

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col">
      <div className="flex h-1/4 min-h-[150px] shrink-0 items-center justify-center pt-6">
        <div className="h-full w-[220px]">
          <OrbGlow>
            <Suspense fallback={null}>
              <PersonaCanvas config={SULIVAN} />
            </Suspense>
          </OrbGlow>
        </div>
      </div>
      <div className="flex min-h-0 min-w-0 flex-1 flex-col items-center overflow-y-auto px-14 pb-10 pt-2 text-center max-lg:px-6">
      <DevBar
        sims={sims}
        active={sim}
        onPick={(s) => {
          setSim(s);
          run(s);
        }}
        /* Close from the voice test counts as installed: everything landed
           and the house is up; only the human confirmation was skipped. */
        onExit={() => onExit(step === 'voice-test' || step === 'interview')}
      />

      {step === 'welcome' && (
        <>
          <Panel title="Let's build your Hearth.">
            <p className="mx-auto max-w-[58ch] text-[15px] leading-relaxed text-fawn">
              A companion that lives on your own machine. Your conversations, your memory, and
              your persona's voice never leave it.
            </p>
            <p className="mx-auto mt-3 max-w-[58ch] text-[15px] leading-relaxed text-fawn">
              Setting up takes about fifteen minutes, and most of that is waiting for downloads.
            </p>
          </Panel>
          <div className="mt-8 flex items-center justify-center gap-3">
            <button
              onClick={() => run()}
              className="rounded-full bg-roast px-6 py-2.5 text-[14px] font-bold text-cream"
            >
              Get started
            </button>
            <button
              onClick={() => setConnectNote(true)}
              className="rounded-full border border-linen bg-parchment px-5 py-2.5 text-[14px] font-semibold text-fawn"
            >
              I already have a Hearth
            </button>
          </div>
          {connectNote && (
            <p className="mx-auto mt-4 max-w-[52ch] text-[13.5px] leading-snug text-fawn">
              Connecting to a Hearth that already runs on another machine is coming, but this
              build cannot do it yet. It can only install a new one here.
            </p>
          )}
        </>
      )}

      {step === 'blocked' && (
        <Blocked kind={blockedKind} error={error} onRescan={() => run(sim)} />
      )}

      {step === 'scanning' && (
        <Panel title="Looking at your machine.">
          <p className="mx-auto max-w-[58ch] text-[15px] leading-relaxed text-fawn">
            Hearth runs entirely on your hardware, so what it can do depends on what you have.
          </p>
        </Panel>
      )}

      {step === 'found' && machine && plan && (
        <Found
          machine={machine}
          plan={plan}
          dest={dest}
          destFree={destFree}
          onDest={setDest}
          onBrowse={browse}
          onGo={startDownload}
        />
      )}

      {step === 'installing' && plan && (
        <Installing
          plan={plan}
          progress={progress}
          done={false}
          error={error}
          onRetry={startDownload}
        />
      )}

      {step === 'voice-test' && (
        /* Hearing him is not the end anymore; it is the introduction to the
           interview, where they make someone together. */
        <VoiceTest onHeard={() => setStep('interview')} voiceResident={plan?.coexist ?? true} />
      )}

      {step === 'interview' && <Interview onDone={() => onExit(true)} />}
      </div>
    </div>
  );
}

function Panel({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mt-6 flex flex-col items-center">
      <h1 className="text-[26px] font-bold tracking-tight">{title}</h1>
      <div className="mt-3">{children}</div>
    </div>
  );
}

/* Three causes, three answers.

   The refusal is the one a real person can meet, and it must not strand them:
   the plan's own sentence says why, and the way forward is the client-only
   path once it exists. Close here deliberately does NOT mark setup complete;
   nothing was installed, so there is no house to drop into. */
function Blocked({
  kind,
  error,
  onRescan,
}: {
  kind: BlockedKind;
  error: string | null;
  onRescan: () => void;
}) {
  if (kind === 'refused') {
    return (
      <Panel title="Hearth cannot run on this machine.">
        <p className="mx-auto max-w-[58ch] text-[15px] leading-relaxed text-fawn">{error}</p>
        <p className="mx-auto mt-4 max-w-[58ch] text-[15px] leading-relaxed text-fawn">
          This is about memory, not disk space, so freeing things up will not change it. A
          machine like this will still be able to join a Hearth that runs on another computer
          in your home. That is coming; this build cannot do it yet.
        </p>
      </Panel>
    );
  }
  if (kind === 'scan-failed') {
    return (
      <Panel title="The scan could not read this machine.">
        <p className="mx-auto max-w-[58ch] text-[15px] leading-relaxed text-fawn">{error}</p>
        <div className="mt-5">
          <button
            onClick={onRescan}
            className="rounded-full bg-roast px-6 py-2.5 text-[14px] font-bold text-cream"
          >
            Try again
          </button>
        </div>
      </Panel>
    );
  }
  return (
    <Panel title="Cannot go on">
      <p className="mx-auto max-w-[58ch] text-[15px] leading-relaxed text-fawn">{error}</p>
    </Panel>
  );
}

function Found({
  machine,
  plan,
  dest,
  destFree,
  onDest,
  onBrowse,
  onGo,
}: {
  machine: Machine;
  plan: Plan;
  dest: string;
  destFree: number | null;
  onDest: (v: string) => void;
  onBrowse: () => void;
  onGo: () => void;
}) {
  const gpu = machine.gpu;
  const memory = gpu?.vram_bytes ?? machine.ram_bytes;
  return (
    <>
      <Panel title={plan.coexist ? 'This machine can run the full thing.' : 'A small machine. Here is the honest picture.'}>
        <p className="mx-auto max-w-[58ch] text-[15px] leading-relaxed text-fawn">
          Here is what Hearth will install, and why.
        </p>
      </Panel>

      <div className="mt-7 grid w-full max-w-[740px] gap-5 text-left lg:grid-cols-2">
        <Card head="Your machine">
          <Row k="System" v={`${machine.os} / ${machine.arch}`} />
          <Row k="Graphics" v={gpu?.name ?? 'none detected'} />
          <Row k={gpu?.vram_bytes ? 'Video memory' : 'Memory'} v={human(memory)} />
          <Row k="Free disk" v={human(destFree ?? machine.free_disk_bytes)} />
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
          className="mt-5 flex w-full max-w-[740px] gap-3 rounded-xl border border-bubble-line bg-bubble px-4 py-3 text-left text-[13.5px] leading-snug"
        >
          <span className="grid size-5 flex-none place-items-center rounded-full bg-honey text-[12px] font-bold">
            !
          </span>
          <span>{w}</span>
        </div>
      ))}

      <Card head="What it will configure" className="mt-6 w-full max-w-[740px] text-left">
        <Row k="Context window" v={`${plan.n_ctx.toLocaleString()} tokens`} />
        <Row k="Backend" v={plan.backend} />
        <Row k="Layers on the GPU" v={plan.n_gpu_layers === -1 ? 'all' : String(plan.n_gpu_layers)} />
        {plan.cuda_arch && <Row k="CUDA architecture" v={plan.cuda_arch} />}
        <Row k="Mind and voice" v={plan.coexist ? 'both resident' : 'one at a time'} />
      </Card>

      <div className="mt-6 w-full max-w-[740px] text-left">
        <div className="text-[11.5px] font-semibold uppercase tracking-wide text-fawn">Why</div>
        <ul className="mt-2 max-w-[74ch] space-y-1.5">
          {plan.reasons.map((r) => (
            <li key={r} className="text-[13.5px] leading-snug text-fawn">
              {r}
            </li>
          ))}
        </ul>
      </div>

      <label className="mt-6 block w-full max-w-[740px] text-left">
        <span className="text-[11.5px] font-semibold uppercase tracking-wide text-fawn">
          Where Hearth installs
        </span>
        <div className="mt-2 flex gap-2">
          <input
            value={dest}
            onChange={(e) => onDest(e.target.value)}
            className="w-full flex-1 rounded-full border border-linen bg-parchment px-4 py-2.5 text-[14px] outline-none"
          />
          <button
            onClick={onBrowse}
            className="rounded-full border border-linen bg-parchment px-4 py-2.5 text-[13.5px] font-semibold text-fawn"
          >
            Browse
          </button>
        </div>
        <span className="mt-1.5 block text-[12.5px] text-fawn">
          Everything lives in this one folder: the models, the runtime, the
          configuration. Removing Hearth means deleting it.
          {destFree !== null && <> {human(destFree)} free where this points.</>}
        </span>
      </label>

      <div className="mt-7 flex justify-center gap-3 pb-4">
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
  onRetry,
}: {
  plan: Plan;
  progress: Progress[];
  done: boolean;
  error: string | null;
  onRetry: () => void;
}) {
  /* One bar over ALL the work. Every row carries a weight in rough megabytes
     (model rows their real bytes, provisioning rows the calibrated constants)
     and contributes its fraction of that weight; skipped rows leave both
     sides of the ratio. A bar that hit 100 while torch was still installing
     had stopped meaning anything, which is the one failure a progress bar
     is not allowed to have. */
  const frac = (p: Progress | undefined): number => {
    if (!p) return 0;
    if (p.state === 'done') return 1;
    if (p.state === 'skipped') return 0;
    return p.totalBytes > 0 ? Math.min(1, p.doneBytes / p.totalBytes) : 0;
  };
  const MIB = 1048576;
  let weightTotal = 0;
  let weightDone = 0;
  for (const d of plan.downloads) {
    const p = progress.find((x) => x.what === d.what);
    if (p?.state === 'skipped') continue;
    const w = d.bytes / MIB;
    weightTotal += w;
    weightDone += w * frac(p);
  }
  for (const row of PROVISION_ROWS) {
    const w = PROVISION_WEIGHTS[row];
    weightTotal += w;
    weightDone += w * frac(progress.find((x) => x.what === row));
  }
  const pct = weightTotal ? Math.min(100, (weightDone / weightTotal) * 100) : done ? 100 : 0;
  /* The byte label keeps talking about the downloads people can size. */
  const modelRows = new Set(plan.downloads.map((d) => d.what));
  const modelProgress = progress.filter((p) => modelRows.has(p.what));
  const got = modelProgress.reduce(
    (n, p) =>
      n +
      (p.state === 'done' || p.state === 'verifying'
        ? p.totalBytes
        : p.state === 'skipped'
          ? 0
          : p.doneBytes),
    0,
  );
  const total =
    plan.total_download_bytes -
    modelProgress.reduce((n, p) => n + (p.state === 'skipped' ? p.totalBytes : 0), 0);
  return (
    <>
      <Panel title={done ? 'Downloaded.' : 'Setting up.'}>
        <p className="mx-auto max-w-[58ch] text-[15px] leading-relaxed text-fawn">
          {done
            ? 'Everything the plan asked for is on disk, checked against its published fingerprint.'
            : 'You can leave this running. Nothing here needs you.'}
        </p>
      </Panel>

      <div className="mt-6 w-full max-w-[600px] text-left">
        <div className="h-[7px] overflow-hidden rounded-full bg-linen">
          <div
            className="h-full rounded-full bg-gradient-to-r from-fennec to-honey transition-[width]"
            style={{ width: `${pct}%` }}
          />
        </div>
        <div className="mt-2 flex justify-between text-[13px] text-fawn">
          <span>
            {human(got)} of {human(total)} downloaded
          </span>
          <span className="tabular-nums">{pct.toFixed(1)}% installed</span>
        </div>

        <div className="mt-5">
          {[
            /* Only direct downloads earn a row of their own. The voice has
               no URL here; the Voice engine row fetches it, and one piece
               of work gets one row. */
            ...plan.downloads
              .filter((d) => d.url !== null)
              .map((d) => ({ what: d.what, bytes: d.bytes })),
            /* The runtime rows, placed while the models download. Their
               sizes vary (bundled unpack, per-accelerator assets, a pip
               resolve), so the right-hand cell reads from progress alone. */
            ...PROVISION_ROWS.map((r) => ({ what: r as string, bytes: 0 })),
          ].map((d) => {
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
                    ? /* A phase message outranks numbers: "installing torch"
                         says more than a synthetic percent pair would. */
                      (p.message ??
                        (p.totalBytes > 0
                          ? `${human(p.doneBytes)} / ${human(p.totalBytes)}`
                          : ''))
                    : p && state === 'verifying'
                      ? p.totalBytes > 0
                        ? `checking ${human(p.doneBytes)} / ${human(p.totalBytes)}`
                        : 'checking'
                      : state === 'skipped'
                        ? p?.message
                        : state === 'done'
                          ? d.bytes > 0
                            ? human(d.bytes)
                            : 'ready'
                          : ''}
                </span>
              </div>
            );
          })}
        </div>

        {error && (
          <div className="mt-5 rounded-xl border border-bubble-line bg-bubble px-4 py-3 text-left text-[13.5px]">
            <p>{error}</p>
            {/* The fetch resumes from where it stopped, so retrying a dropped
                connection is cheap and the button says so. */}
            <button
              onClick={onRetry}
              className="mt-3 rounded-full bg-roast px-5 py-2 text-[13.5px] font-bold text-cream"
            >
              Retry download
            </button>
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
    <div className="flex w-full flex-wrap items-center gap-2 border-b border-linen pb-3 text-left text-[12px]">
      {/* Machine simulation is a building tool. Close stays outside the gate,
          or turning developer mode off would trap you in the setup view. It
          leaves setup without claiming an install happened; only a finished
          download marks setup complete. */}
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
