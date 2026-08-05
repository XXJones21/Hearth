import { useEffect, useState } from 'react';
import { CardLibrary } from './CardLibrary';
import {
  applyApps,
  fetchApps,
  waitForServer,
  type AppRow,
  type AppsSurface,
} from '../../lib/appsApi';

/* Apps: what the house is connected to.
 *
 * An app is a bundle of capability (tools), connection (what it reaches),
 * surface (the cards it draws), and permission (who may use it). Every row is
 * derived server-side from tools.yaml, card_catalog.yaml, and persona grants,
 * so this view renders what arrives and invents nothing. Design:
 * tasks/apps-extensions-investigation.md. */

const GROUPS: { id: AppRow['state']; label: string; sub: string }[] = [
  { id: 'active', label: 'In the house', sub: 'connected and offered to at least one persona' },
  { id: 'setup', label: 'Needs setup', sub: 'the house knows about these, they need a credential' },
  { id: 'available', label: 'Available', sub: 'found on this machine, not let in yet' },
];

const KIND_LABEL: Record<AppRow['kind'], string> = {
  core: 'built in',
  cli: 'CLI',
  local: 'local bridge',
  mcp: 'MCP',
};

const PERSONA_COLOR: Record<string, string> = {
  Sulivan: '#E39A5B',
  Selene: '#FFB84D',
};

function glyph(name: string): string {
  const words = name.split(' ');
  return (words.length > 1 ? words.map((w) => w[0]).join('') : name.slice(0, 2))
    .slice(0, 2)
    .toUpperCase();
}

function AppCard({
  app,
  personas,
  on,
  grantedTo,
  onToggle,
  onGrant,
}: {
  app: AppRow;
  personas: string[];
  on: boolean;
  grantedTo: (persona: string) => boolean;
  onToggle: (next: boolean) => void;
  onGrant: (persona: string, next: boolean) => void;
}) {
  const [open, setOpen] = useState(false);

  return (
    <div
      className={`mt-2 overflow-hidden rounded-[16px] border ${
        app.key === 'core'
          ? 'border-bubble-line bg-gradient-to-b from-glowtint to-fluff'
          : 'border-linen bg-fluff'
      }`}
    >
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        className="flex w-full items-center gap-3 px-4 py-3 text-left"
      >
        <span
          className={`grid h-[34px] w-[34px] shrink-0 place-items-center rounded-[10px] border text-[13px] font-bold ${
            app.key === 'core'
              ? 'border-ember bg-gradient-to-b from-honey to-fennec text-roast'
              : 'border-linen bg-parchment text-ember'
          }`}
        >
          {glyph(app.name)}
        </span>
        <span className="min-w-0">
          <span className="flex items-center gap-2 text-[14px] font-semibold text-roast">
            {app.name}
            <span className="rounded-full border border-linen bg-parchment px-[7px] py-[2px] text-[10px] font-semibold uppercase tracking-wide text-fawn">
              {KIND_LABEL[app.kind]}
            </span>
            {app.risk !== 'read' && (
              <span className="rounded-full border border-[#E8CFC2] bg-[#F7EAE4] px-[7px] py-[2px] font-mono text-[10px] text-[#8A3D2A]">
                {app.risk}
              </span>
            )}
          </span>
          <span className="mt-0.5 block text-[11.5px] text-fawn">{app.tagline}</span>
        </span>
        <span className="ml-auto flex shrink-0 items-center gap-2.5">
          <span
            role="switch"
            aria-checked={on}
            aria-label={`${app.name} on`}
            aria-disabled={app.locked || undefined}
            tabIndex={app.locked ? -1 : 0}
            onClick={(e) => {
              e.stopPropagation();
              if (!app.locked) onToggle(!on);
            }}
            className={`relative h-[23px] w-10 shrink-0 rounded-full transition ${
              on ? 'bg-fennec' : 'bg-linen'
            } ${app.locked ? 'opacity-45' : 'cursor-pointer'}`}
          >
            <span
              className="absolute top-[3px] h-[17px] w-[17px] rounded-full bg-fluff shadow-soft transition-all"
              style={{ left: on ? '20px' : '3px' }}
            />
          </span>
          <span className={`text-[15px] leading-none text-fawn ${open ? 'rotate-90' : ''}`}>
            &#9656;
          </span>
        </span>
      </button>

      {open && (
        <div className="border-t border-linen py-1 pl-[63px] pr-4">
          <Facet label="Reaches">{app.transport}</Facet>
          <Facet label="Can do">
            {app.tools.map((t) => (
              <Pill key={t}>{t}</Pill>
            ))}
            {app.more > 0 && <Pill>+{app.more} more</Pill>}
          </Facet>
          <Facet label="Draws">
            {app.cards.length ? (
              app.cards.map((c) => (
                <Pill key={c} tone="card">
                  {c}
                </Pill>
              ))
            ) : (
              <em>draws nothing</em>
            )}
          </Facet>
          <Facet label="Who may">
            {personas.map((n) => {
              const granted = grantedTo(n);
              return (
                <button
                  type="button"
                  key={n}
                  aria-pressed={granted}
                  onClick={() => onGrant(n, !granted)}
                  className={`mr-1.5 mt-0.5 inline-flex items-center gap-1.5 rounded-full border border-linen bg-fluff py-[3px] pl-1 pr-2.5 text-[11.5px] transition hover:border-bubble-line ${
                    granted ? '' : 'opacity-40'
                  }`}
                >
                  <span
                    className="grid h-[17px] w-[17px] place-items-center rounded-full text-[9px] font-bold text-white"
                    style={{ background: granted ? PERSONA_COLOR[n] || '#8C7A66' : '#B8ADA0' }}
                  >
                    {n.slice(0, 2)}
                  </span>
                  {n}
                </button>
              );
            })}
            <div className="mt-1.5">
              {app.locked
                ? 'Always on. Permission is granted by domain, so a persona may also gain another app that shares one.'
                : 'Permission is granted by domain, so a persona may also gain another app that shares one.'}
            </div>
          </Facet>
          {app.needs.length > 0 && (
            <div className="mb-3 mt-1 rounded-[10px] border border-[#E8CFC2] bg-[#FBF1EC] px-3 py-2 text-[11.5px] text-[#8A3D2A]">
              Waiting on {app.needs.join(' and ')}.
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function Facet({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex gap-3 border-b border-dotted border-linen py-2.5 last:border-b-0">
      <div className="w-24 shrink-0 pt-[3px] text-[11px] font-bold uppercase tracking-[0.14em] text-ember">
        {label}
      </div>
      <div className="text-[12.5px] leading-relaxed text-fawn">{children}</div>
    </div>
  );
}

function Pill({ children, tone }: { children: React.ReactNode; tone?: 'card' }) {
  return (
    <span
      className={`mr-1 mt-0.5 inline-block rounded-full border px-2.5 py-[3px] text-[11px] ${
        tone === 'card'
          ? 'border-bubble-line bg-bubble text-roast'
          : 'border-linen bg-parchment font-mono text-roast'
      }`}
    >
      {children}
    </span>
  );
}

export function AppsView({ onAsk }: { onAsk: (text: string) => void }) {
  const [surface, setSurface] = useState<AppsSurface | null>(null);
  const [library, setLibrary] = useState(false);
  /* Pending edits, held here until Save. Both tools.yaml and the persona
     files are read once at process start, so applying them restarts the
     house. Batching keeps that to ONE restart no matter how many switches
     were flipped. */
  const [apps, setApps] = useState<Record<string, boolean>>({});
  const [grants, setGrants] = useState<Record<string, Record<string, boolean>>>({});
  const [saving, setSaving] = useState<'' | 'writing' | 'waiting'>('');
  const [note, setNote] = useState('');

  const load = () => void fetchApps().then(setSurface);
  useEffect(load, []);

  const isOn = (a: AppRow) => apps[a.key] ?? (a.state === 'active');
  const isGranted = (a: AppRow, persona: string) =>
    grants[persona]?.[a.key] ?? a.who.includes(persona);

  const dirtyCount =
    Object.keys(apps).length + Object.values(grants).reduce((n, g) => n + Object.keys(g).length, 0);

  const discard = () => {
    setApps({});
    setGrants({});
    setNote('');
  };

  const save = async () => {
    setSaving('writing');
    setNote('');
    const res = await applyApps({ apps, grants });
    if (!res.ok) {
      setSaving('');
      setNote(res.error || 'That did not go through.');
      return;
    }
    discard();
    if (res.restarting) {
      setSaving('waiting');
      const back = await waitForServer();
      setNote(back ? 'Saved. The house is back.' : 'Saved, but the house has not answered yet.');
    } else {
      setNote('Nothing needed changing.');
    }
    setSaving('');
    load();
  };

  return (
    <section className="flex min-h-0 flex-col overflow-hidden" aria-label="Apps">
      <div className="flex items-baseline gap-3 px-7 pt-6">
        <h2 className="text-[20px] font-bold text-roast">Apps</h2>
        <span className="text-[12px] italic text-fawn">what the house is connected to</span>
        <div className="ml-auto flex gap-2">
          <button
            type="button"
            onClick={() => setLibrary(true)}
            className="rounded-full border border-linen bg-fluff px-3.5 py-[7px] text-[12px] font-semibold text-roast shadow-soft transition hover:bg-glowtint"
          >
            Card library
          </button>
        </div>
      </div>

      <div className="mt-4 min-h-0 flex-1 overflow-y-auto px-7 pb-7">
        {!surface && (
          <p className="rounded-[14px] border border-linen bg-fluff px-4 py-3 text-[12.5px] text-fawn">
            The house has not answered yet.
          </p>
        )}

        {surface && !surface.tools_enabled && (
          <div className="mb-3 rounded-[14px] border border-[#E8CFC2] bg-[#FBF1EC] px-4 py-3 text-[12.5px] text-[#8A3D2A]">
            Tools are switched off on the server, so nothing here can act yet.
          </div>
        )}

        {note && !dirtyCount && (
          <div className="mb-3 rounded-[14px] border border-bubble-line bg-glowtint px-4 py-2.5 text-[12.5px] text-roast">
            {note}
          </div>
        )}

        {surface &&
          GROUPS.map((g) => {
            const rows = surface.apps.filter((a) => a.state === g.id);
            if (!rows.length) return null;
            return (
              <div key={g.id} className="mb-4">
                <h3 className="mt-4 text-[11px] font-bold uppercase tracking-[0.18em] text-ember">
                  {g.label}
                </h3>
                <p className="mb-2 text-[12px] italic text-fawn">{g.sub}</p>
                {rows.map((a) => (
                  <AppCard
                    key={a.key}
                    app={a}
                    personas={surface.personas}
                    on={isOn(a)}
                    grantedTo={(n) => isGranted(a, n)}
                    onToggle={(next) =>
                      setApps((prev) => {
                        const out = { ...prev };
                        if (next === (a.state === 'active')) delete out[a.key];
                        else out[a.key] = next;
                        return out;
                      })
                    }
                    onGrant={(persona, next) =>
                      setGrants((prev) => {
                        const forPersona = { ...(prev[persona] ?? {}) };
                        if (next === a.who.includes(persona)) delete forPersona[a.key];
                        else forPersona[a.key] = next;
                        const out = { ...prev, [persona]: forPersona };
                        if (!Object.keys(forPersona).length) delete out[persona];
                        return out;
                      })
                    }
                  />
                ))}
              </div>
            );
          })}

        {surface && (
          <div className="mt-2 rounded-[16px] border border-dashed border-bubble-line bg-parchment px-4 py-3.5 text-[12.5px] leading-relaxed text-fawn">
            <b className="text-roast">Teach the house something new.</b> Point it at an MCP
            server, or just ask: <i>&ldquo;Sulivan, connect us to Spotify.&rdquo;</i> He writes
            the integration, the workshop builds it, and it shows up here.
          </div>
        )}
      </div>

      {(dirtyCount > 0 || saving) && (
        <div className="flex items-center gap-3 border-t border-linen bg-glowtint px-7 py-3">
          <span className="text-[12.5px] text-roast">
            {saving === 'waiting'
              ? 'Restarting the house...'
              : saving === 'writing'
                ? 'Saving...'
                : `${dirtyCount} change${dirtyCount === 1 ? '' : 's'} pending.`}
          </span>
          <span className="text-[11.5px] text-fawn">
            {saving ? 'This takes a few seconds.' : 'Saving restarts the house to apply them.'}
          </span>
          {note && saving === '' && <span className="text-[11.5px] text-[#8A3D2A]">{note}</span>}
          <div className="ml-auto flex gap-2">
            <button
              type="button"
              onClick={discard}
              disabled={!!saving}
              className="rounded-full border border-linen bg-fluff px-3.5 py-[7px] text-[12px] font-semibold text-fawn shadow-soft disabled:opacity-50"
            >
              Discard
            </button>
            <button
              type="button"
              onClick={() => void save()}
              disabled={!!saving}
              className="rounded-full border border-ember bg-gradient-to-b from-honey to-fennec px-4 py-[7px] text-[12px] font-semibold text-roast shadow-soft disabled:opacity-50"
            >
              Save changes
            </button>
          </div>
        </div>
      )}

      {library && surface && (
        <CardLibrary
          cards={surface.cards}
          onClose={() => setLibrary(false)}
          onCommission={(text) => {
            setLibrary(false);
            onAsk(`I would like a new card: ${text}`);
          }}
        />
      )}
    </section>
  );
}
