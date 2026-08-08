import { useEffect, useMemo, useState, type ReactNode } from 'react';
import {
  applyPersonas,
  fetchPersonas,
  fetchTestLine,
  type PersonaEdit,
  type PersonaRow,
  type PersonasSurface,
  type PersonaVoiceEdit,
} from '../../lib/personasApi';
import { waitForServer } from '../../lib/appsApi';
import { can } from '../../lib/clientProfile';
import { revealFolder } from '../../lib/openPath';
import { ttsPlayer } from '../../lib/audioPlayer';
import { loadSettings } from '../../lib/settings';
import { useAppStore } from '../../store/appStore';

/* Personas: who lives in the house.
 *
 * Six sections in the order a person cares about them. The system prompt gets
 * the page; everything else is a row around it, because the prompt IS the
 * persona and the rest is plumbing.
 *
 * Saving batches every edit and restarts the house, since persona.json is
 * read once at process start. Developer mode swaps the panel for the raw
 * file, and carries the two destructive actions (Discard, Remove) so neither
 * is reachable while someone is only looking. Design:
 * wiki/clients/persona-page.md. */

const FORM_LABEL: Record<string, { label: string; hint: string }> = {
  non_corporeal: { label: 'Non-corporeal', hint: 'light and particles, no body' },
  humanoid: { label: 'Humanoid', hint: 'an upright figure, four clips' },
  quadruped: { label: 'Quadruped', hint: 'four-legged, its own gaits' },
  custom: { label: 'Something else', hint: 'you supply the rig and the clips' },
};

const STATE_WHEN: Record<string, string> = {
  idle: 'waiting',
  listening: 'you are speaking',
  thinking: 'working it out',
  speaking: 'answering you',
};

/** What Hear it says for a persona who has no test line of their own yet. */
const FALLBACK_LINE = 'Good evening. Shall I read you the day?';

const WARM_DEFAULTS: Record<string, string> = {
  idle: '#E39A5B',
  listening: '#FFB84D',
  thinking: '#D68C50',
  speaking: '#C97F45',
};

function darken(hex: string, by = 60): string {
  const n = parseInt(hex.replace('#', ''), 16);
  if (Number.isNaN(n)) return hex;
  const f = (c: number) => Math.max(0, c - by);
  return `rgb(${f(n >> 16)},${f((n >> 8) & 255)},${f(n & 255)})`;
}
const glow = (hex: string) =>
  `radial-gradient(circle at 38% 34%, #FFF6E6, ${hex} 46%, ${darken(hex, 80)} 84%)`;

function Section({ label, sub, children }: { label: string; sub: string; children: ReactNode }) {
  return (
    <section className="mt-4">
      <h3 className="text-[11px] font-bold uppercase tracking-[0.18em] text-ember">{label}</h3>
      <p className="mb-2 text-[12px] italic text-fawn">{sub}</p>
      {children}
    </section>
  );
}

function Row({
  label,
  hint,
  children,
  stack,
}: {
  label: string;
  hint?: string;
  children?: ReactNode;
  stack?: boolean;
}) {
  return (
    <div
      className={`mt-2 rounded-[14px] border border-linen bg-fluff px-4 py-3 ${
        stack ? '' : 'flex items-center gap-3.5'
      }`}
    >
      <div className="min-w-0">
        <div className="text-[13.5px] text-roast">{label}</div>
        {hint && <div className="mt-0.5 text-[11.5px] leading-snug text-fawn">{hint}</div>}
      </div>
      {stack ? <div className="mt-2">{children}</div> : <div className="ml-auto shrink-0">{children}</div>}
    </div>
  );
}

const inputCls =
  'rounded-[10px] border border-linen bg-parchment px-3 py-2 text-[13px] text-roast focus:border-fennec focus:bg-fluff focus:outline-none';

export function PersonasView() {
  const [surface, setSurface] = useState<PersonasSurface | null>(null);
  const [sel, setSel] = useState(0);
  const [dev, setDev] = useState(false);
  const [edits, setEdits] = useState<Record<string, PersonaEdit>>({});
  const [saving, setSaving] = useState<'' | 'writing' | 'waiting'>('');
  const [hearing, setHearing] = useState<'' | 'rendering' | 'playing'>('');
  const [voiceNote, setVoiceNote] = useState('');
  const [note, setNote] = useState('');

  const load = () => void fetchPersonas().then(setSurface);
  useEffect(load, []);

  const shown = useMemo(
    () => (surface?.personas ?? []).filter((p) => dev || !p.internal),
    [surface, dev],
  );
  const person: PersonaRow | undefined = shown[Math.min(sel, Math.max(0, shown.length - 1))];

  const dirty = Object.values(edits).reduce((n, e) => n + Object.keys(e).length, 0);

  /** Current value: the pending edit if there is one, else the file. */
  function val<K extends keyof PersonaRow>(p: PersonaRow, key: K): PersonaRow[K] {
    const e = edits[p.key] as Record<string, unknown> | undefined;
    return (e && key in e ? (e[key] as PersonaRow[K]) : p[key]);
  }

  function edit(p: PersonaRow, patch: PersonaEdit) {
    setEdits((prev) => ({ ...prev, [p.key]: { ...(prev[p.key] ?? {}), ...patch } }));
  }

  /** Voice fields accumulate into one pending edit rather than replacing it. */
  function editVoice(p: PersonaRow, patch: PersonaVoiceEdit) {
    setEdits((prev) => ({
      ...prev,
      [p.key]: { ...(prev[p.key] ?? {}), voice: { ...(prev[p.key]?.voice ?? {}), ...patch } },
    }));
  }

  const discard = () => {
    setEdits({});
    setNote('');
  };

  /* Hear it.
   *
   * The visualizer state is the interlock. One voice comes out of the house
   * at a time, so the button refuses while anyone is thinking or speaking --
   * including a real turn in the feed. Two overlapping generations on the
   * shared 4080 is how OmniVoice runs out of VRAM, so this is a resource
   * guard as much as a sensible one.
   *
   * Rendering is `thinking` and playback is `speaking`, which is what those
   * states already mean everywhere else. The persona on the left moves for
   * the preview the same way it moves for a reply. */
  async function hearIt(p: PersonaRow, v: PersonaRow['voice']) {
    if (hearing) return;
    const store = useAppStore.getState();
    if (store.isWaitingForResponse || store.visualState !== 'idle') {
      setVoiceNote('Someone is mid-sentence. Give them a moment.');
      return;
    }
    if (!loadSettings().voiceEnabled) {
      setVoiceNote('Voice output is off in Settings, so there is nothing to hear.');
      return;
    }

    setVoiceNote('');
    setHearing('rendering');
    store.setVisualState('thinking');
    const clip = await fetchTestLine({
      persona: p.key,
      text: v.test_line.trim() || FALLBACK_LINE,
      reference_audio: v.reference_audio,
      reference_text: v.reference_text,
    });
    if (typeof clip === 'string') {
      useAppStore.getState().setVisualState('idle');
      setHearing('');
      setVoiceNote(clip);
      return;
    }
    setHearing('playing');
    useAppStore.getState().setVisualState('speaking');
    try {
      await ttsPlayer.playClip(clip);
    } catch (err) {
      setVoiceNote(err instanceof Error ? err.message : 'That would not play.');
    }
    useAppStore.getState().setVisualState('idle');
    setHearing('');
  }

  async function save(remove?: string) {
    setSaving('writing');
    setNote('');
    const res = await applyPersonas({ edits, remove: remove ? [remove] : [] });
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
    setSel(0);
    load();
  }

  if (!surface || !person) {
    return (
      <section className="flex min-h-0 flex-col overflow-hidden" aria-label="Personas">
        <div className="px-7 pt-6">
          <h2 className="text-[20px] font-bold text-roast">Personas</h2>
        </div>
        <p className="mx-7 mt-4 rounded-[14px] border border-linen bg-fluff px-4 py-3 text-[12.5px] text-fawn">
          {surface ? 'Nobody lives here yet.' : 'The house has not answered yet.'}
        </p>
      </section>
    );
  }

  const states = (val(person, 'state_colors') as Record<string, string> | null) ?? null;
  /* Voice is the one group edited field by field, so a pending edit holds
     only the fields touched so far. Merge it over the file or the untouched
     inputs go blank the moment a sibling is edited. */
  const voice = { ...person.voice, ...(edits[person.key]?.voice ?? {}) };

  return (
    <section className="flex min-h-0 flex-col overflow-hidden" aria-label="Personas">
      <div className="flex items-baseline gap-3 px-7 pt-6">
        <h2 className="text-[20px] font-bold text-roast">Personas</h2>
        <span className="text-[12px] italic text-fawn">who lives in the house</span>
        {loadSettings().developerMode && (
        <label className="ml-auto flex items-center gap-2 text-[11.5px] text-fawn">
          Developer mode
          <button
            type="button"
            role="switch"
            aria-checked={dev}
            aria-label="Developer mode"
            onClick={() => {
              setDev((v) => !v);
              setSel(0);
            }}
            className={`relative h-[23px] w-10 shrink-0 rounded-full transition ${
              dev ? 'bg-fennec' : 'bg-linen'
            }`}
          >
            <span
              className="absolute top-[3px] h-[17px] w-[17px] rounded-full bg-fluff shadow-soft transition-all"
              style={{ left: dev ? '20px' : '3px' }}
            />
          </button>
        </label>
        )}
      </div>

      <div className="mt-3 min-h-0 flex-1 overflow-y-auto px-7 pb-6">
        {/* the household strip is the navigation */}
        <div className="flex gap-2.5 overflow-x-auto pb-3 pt-1">
          {shown.map((p, i) => (
            <button
              type="button"
              key={p.key}
              onClick={() => setSel(i)}
              className={`w-[104px] shrink-0 rounded-[16px] border px-2 py-3 text-center transition ${
                i === sel
                  ? 'border-ember bg-gradient-to-b from-glowtint to-fluff shadow-soft'
                  : 'border-linen bg-fluff hover:border-bubble-line'
              }`}
            >
              <span
                className="mx-auto mb-1.5 block h-[46px] w-[46px] rounded-full"
                style={{ background: glow(p.accent) }}
              />
              <span className="block truncate text-[12.5px] font-semibold text-roast">{p.name}</span>
              <span className="block truncate text-[10.5px] text-fawn">
                {p.internal ? 'machinery' : p.classification || 'resident'}
              </span>
            </button>
          ))}
        </div>

        {note && !dirty && (
          <div className="mb-2 rounded-[12px] border border-bubble-line bg-glowtint px-4 py-2.5 text-[12.5px] text-roast">
            {note}
          </div>
        )}

        {dev ? (
          <Section label={`${person.key.toLowerCase()}.json`} sub="the whole file, as it is on disk">
            <pre className="overflow-x-auto rounded-[14px] border border-linen bg-[#FCFAF6] px-4 py-3.5 font-mono text-[11.5px] leading-[1.75] text-fawn">
              {JSON.stringify({ ...person, ...(edits[person.key] ?? {}) }, null, 2)}
            </pre>
            <div className="mt-2 flex gap-3 rounded-[14px] border border-dashed border-bubble-line bg-parchment px-4 py-3 text-[12.5px] leading-relaxed text-fawn">
              <span>
                This is the surface as the server reads it, not the raw file byte for byte.
                Editing here is the next step; for now the form below writes the same fields.
              </span>
            </div>
          </Section>
        ) : null}

        <Section label="Who they are" sub="the part a guest would notice">
          <Row label="Name">
            <input
              className={`${inputCls} w-52`}
              value={val(person, 'name') as string}
              onChange={(e) => edit(person, { name: e.target.value })}
            />
          </Row>
          <Row label="In a line" hint="Shown under their name on every client.">
            <input
              className={`${inputCls} w-[340px]`}
              value={val(person, 'description') as string}
              onChange={(e) => edit(person, { description: e.target.value })}
            />
          </Row>
        </Section>

        <Section label="How they are" sub="the character itself, in their own words">
          <textarea
            rows={7}
            className={`${inputCls} w-full resize-y leading-relaxed`}
            value={val(person, 'system_prompt') as string}
            onChange={(e) => edit(person, { system_prompt: e.target.value })}
          />
          <div className="mt-2 flex gap-3 rounded-[14px] border border-dashed border-bubble-line bg-parchment px-4 py-3 text-[12.5px] leading-relaxed text-fawn">
            <span>
              <b className="text-roast">This is the persona.</b> Everything else on this page is
              plumbing around it. It saves like the rest: batched, behind one Save.
            </span>
          </div>
        </Section>

        <Section label="Voice" sub="how they sound">
          <Row label="Manner" hint="Guides the clone. A plain description, not a setting.">
            <input
              className={`${inputCls} w-[320px]`}
              value={voice.voice_description}
              onChange={(e) => editVoice(person, { voice_description: e.target.value })}
            />
          </Row>
          <Row
            label="Voice clone"
            hint={
              person.voice.clips.length > 1
                ? `${person.voice.clips.length} clips in their folder. The chosen one is what the cloner hears.`
                : voice.reference_audio || 'No clip yet, so they borrow the house voice.'
            }
          >
            <div className="flex items-center gap-2">
              {person.voice.clips.length > 1 && (
                <select
                  className={inputCls}
                  aria-label="Voice clone"
                  value={voice.reference_audio}
                  onChange={(e) => editVoice(person, { reference_audio: e.target.value })}
                >
                  {[...new Set([voice.reference_audio, ...person.voice.clips])]
                    .filter(Boolean)
                    .map((c) => (
                      <option key={c} value={c}>
                        {c}
                      </option>
                    ))}
                </select>
              )}
              {can('files') && (
                <button
                  type="button"
                  onClick={async () => {
                    const err = await revealFolder(person.voice.folder);
                    setVoiceNote(
                      err ||
                        'Put the new wav in that folder, then pick it here and write what it says.',
                    );
                  }}
                  className="rounded-full border border-linen bg-fluff px-3 py-[6px] text-[12px] font-semibold text-roast shadow-soft"
                >
                  Replace
                </button>
              )}
            </div>
          </Row>
          <Row
            label="What the clip says"
            hint={`The exact words in ${
              voice.reference_audio || 'the recording'
            }. The cloner aligns against this, so a wrong transcript makes the voice worse, not just inaccurate.`}
            stack
          >
            <textarea
              rows={2}
              className={`${inputCls} w-full resize-y`}
              value={voice.reference_text}
              onChange={(e) => editVoice(person, { reference_text: e.target.value })}
            />
          </Row>
          <Row
            label="Test line"
            hint="What they say when you press Hear it. Something in their register."
            stack
          >
            <div className="w-full">
              <div className="flex w-full items-center gap-2">
                <input
                  className={`${inputCls} flex-1`}
                  placeholder={FALLBACK_LINE}
                  value={voice.test_line}
                  onChange={(e) => editVoice(person, { test_line: e.target.value })}
                />
                <button
                  type="button"
                  disabled={hearing !== ''}
                  title={
                    voice.test_line.trim()
                      ? `${person.name} speaks the line`
                      : 'Speaks the placeholder until you write one'
                  }
                  onClick={() => void hearIt(person, voice)}
                  className="w-[104px] shrink-0 rounded-full border border-ember bg-tab px-3.5 py-[7px] text-[12px] font-semibold text-roast shadow-soft disabled:opacity-50"
                >
                  {hearing === 'rendering'
                    ? 'Rendering...'
                    : hearing === 'playing'
                      ? 'Speaking'
                      : 'Hear it'}
                </button>
              </div>
              {voiceNote && (
                <p className="mt-2 rounded-[10px] border border-[#E8CFC2] bg-[#FBF1EC] px-3 py-2 text-[11.5px] leading-snug text-[#8A3D2A]">
                  {voiceNote}
                </p>
              )}
            </div>
          </Row>
          <div className="mt-2 flex gap-3 rounded-[14px] border border-dashed border-bubble-line bg-parchment px-4 py-3 text-[12.5px] leading-relaxed text-fawn">
            <span>
              <b className="text-roast">Voice quality is house-wide, not per persona.</b> OmniVoice
              trades latency for polish with its diffusion steps, and it applies to everyone at
              once, so it lives in Settings.
            </span>
          </div>
        </Section>

        <Section label="Presence" sub="what you see when they speak">
          <Row
            label="Takes the form of"
            hint={`${FORM_LABEL[val(person, 'form') as string]?.hint ?? ''}${
              person.preset ? ` · ${person.preset}` : ''
            }`}
          >
            <select
              className={inputCls}
              value={val(person, 'form') as string}
              onChange={(e) => edit(person, { form: e.target.value })}
            >
              {surface.forms.map((f) => (
                <option key={f} value={f}>
                  {FORM_LABEL[f]?.label ?? f}
                </option>
              ))}
            </select>
          </Row>

          <div className="mt-2 rounded-[14px] border border-linen bg-fluff px-4 py-3">
            <div className="text-[13.5px] text-roast">Colours by state</div>
            <p className="mt-0.5 text-[11.5px] leading-snug text-fawn">
              Hover one to see it move the way it will in the room. Every client reads these, so
              they should agree with each other.
            </p>
            {states ? (
              <div className="mt-2.5 grid grid-cols-4 gap-2.5">
                {['idle', 'listening', 'thinking', 'speaking'].map((k) => {
                  const c = states[k] ?? WARM_DEFAULTS[k];
                  return (
                    <label
                      key={k}
                      className="group cursor-pointer rounded-[14px] border border-linen bg-fluff px-2 pb-2.5 pt-3.5 text-center transition hover:-translate-y-0.5 hover:border-ember hover:shadow-soft"
                    >
                      <span
                        className="mx-auto mb-2 block h-14 w-14 rounded-full transition group-hover:scale-105"
                        style={{ background: glow(c), boxShadow: `0 0 20px 4px ${c}55` }}
                      />
                      <span className="block text-[12px] font-semibold text-roast">{k}</span>
                      <span className="block font-mono text-[9.5px] text-fawn">
                        {c.toUpperCase()}
                      </span>
                      <span className="mt-0.5 block text-[10px] text-fawn opacity-0 transition group-hover:opacity-100">
                        {STATE_WHEN[k]}
                      </span>
                      <input
                        type="color"
                        className="sr-only"
                        value={c}
                        onChange={(e) =>
                          edit(person, {
                            state_colors: { ...states, [k]: e.target.value.toUpperCase() },
                          })
                        }
                      />
                    </label>
                  );
                })}
              </div>
            ) : (
              <div className="mt-2 flex gap-3 rounded-[12px] border border-dashed border-bubble-line bg-parchment px-4 py-3 text-[12.5px] leading-relaxed text-fawn">
                <span>
                  <b className="text-roast">No colours of their own yet.</b> They fall back to the
                  house defaults. Give them their own and every client picks them up.
                  <button
                    type="button"
                    onClick={() => edit(person, { state_colors: { ...WARM_DEFAULTS } })}
                    className="ml-3 rounded-full border border-linen bg-fluff px-3 py-[5px] text-[11.5px] font-semibold text-roast shadow-soft"
                  >
                    Give them their own
                  </button>
                </span>
              </div>
            )}
          </div>
        </Section>

        <Section label="What they may do" sub="the same grants the Apps page shows, edited here">
          <div className="mt-2 rounded-[14px] border border-linen bg-fluff px-4 py-3">
            <div className="text-[13.5px] text-roast">Allowed</div>
            <div className="mt-1.5">
              {surface.domains.map((d) => {
                const on = (val(person, 'domains') as string[]).includes(d);
                return (
                  <button
                    type="button"
                    key={d}
                    onClick={() => {
                      const cur = val(person, 'domains') as string[];
                      edit(person, {
                        domains: on ? cur.filter((x) => x !== d) : [...cur, d],
                      });
                    }}
                    className={`mr-1.5 mt-1.5 rounded-full px-2.5 py-1 text-[11px] transition ${
                      on
                        ? 'border border-ember bg-tab font-semibold text-roast'
                        : 'border border-dashed border-linen bg-fluff text-fawn hover:border-bubble-line'
                    }`}
                  >
                    {d}
                  </button>
                );
              })}
            </div>
            {person.deny.length > 0 && (
              <>
                <div className="mt-3 text-[13.5px] text-roast">
                  Never, even if the domain allows it
                </div>
                <div className="mt-1.5">
                  {person.deny.map((d) => (
                    <span
                      key={d}
                      className="mr-1.5 rounded-full border border-[#E8CFC2] bg-[#FBF1EC] px-2.5 py-1 text-[11px] text-[#8A3D2A] line-through"
                    >
                      {d}
                    </span>
                  ))}
                </div>
              </>
            )}
          </div>
        </Section>

        <Section label="How they think" sub="the model behind them, and how far they reason">
          <Row
            label="Their model"
            hint="The one they actually think with, from what is in your models folder."
          >
            <select
              className={inputCls}
              value={val(person, 'model') as string}
              onChange={(e) => edit(person, { model: e.target.value })}
            >
              {[...new Set([person.model, ...surface.models])].filter(Boolean).map((m) => (
                <option key={m} value={m}>
                  {m}
                </option>
              ))}
            </select>
          </Row>
          <Row
            label="Manner of thought"
            hint="Lower stays close to the facts. Higher wanders further for an idea."
          >
            <div>
              <input
                type="range"
                min={0}
                max={100}
                value={Math.round((val(person, 'temperature') as number) * 100)}
                onChange={(e) => edit(person, { temperature: Number(e.target.value) / 100 })}
                className="h-1 w-[170px] cursor-pointer appearance-none rounded bg-linen accent-fennec"
              />
              <div className="flex w-[170px] justify-between text-[10.5px] text-fawn">
                <span>precise</span>
                <span>inventive</span>
              </div>
            </div>
          </Row>
          <Row
            label="Reasoning"
            hint="Reasons about which tools to use before reaching for one. Slower turns, better choices."
          >
            <button
              type="button"
              role="switch"
              aria-checked={val(person, 'reasoning') as boolean}
              aria-label="Reasoning"
              onClick={() => edit(person, { reasoning: !(val(person, 'reasoning') as boolean) })}
              className={`relative h-[23px] w-10 shrink-0 rounded-full transition ${
                val(person, 'reasoning') ? 'bg-fennec' : 'bg-linen'
              }`}
            >
              <span
                className="absolute top-[3px] h-[17px] w-[17px] rounded-full bg-fluff shadow-soft transition-all"
                style={{ left: val(person, 'reasoning') ? '20px' : '3px' }}
              />
            </button>
          </Row>
          <Row label="Tool rounds" hint="How many times they may reach for a tool in one turn.">
            <select
              className={inputCls}
              value={val(person, 'rounds') as number}
              onChange={(e) => edit(person, { rounds: Number(e.target.value) })}
            >
              {[1, 2, 3, 4, 6, 8].map((n) => (
                <option key={n} value={n}>
                  {n}
                </option>
              ))}
            </select>
          </Row>
          <details className="group mt-2">
            <summary className="flex cursor-pointer list-none items-center gap-2.5 rounded-[14px] border border-linen bg-fluff px-4 py-3 text-[13.5px] text-roast">
              <span className="rounded-full border border-[#DED5CA] bg-[#EDE7E0] px-2 py-[3px] text-[10px] font-semibold uppercase tracking-wide text-fawn">
                Advanced
              </span>
              What this persona runs on
            </summary>
            <dl className="mt-2 rounded-[14px] border border-linen bg-[#FCFAF6] px-4 py-3 font-mono text-[11.5px] leading-[1.9] text-fawn">
              <div className="flex gap-3">
                <dt className="w-24">model</dt>
                <dd className="text-roast">{person.model || '(the plan’s)'}</dd>
              </div>
              <div className="flex gap-3">
                <dt className="w-24">context</dt>
                <dd className="text-roast">{person.n_ctx || '(default)'} tokens</dd>
              </div>
            </dl>
          </details>
        </Section>
      </div>

      {(dirty > 0 || dev || saving) && (
        <div className="flex items-center gap-3 border-t border-linen bg-glowtint px-7 py-3">
          {dev && (
            <button
              type="button"
              disabled={!!saving}
              onClick={() => void save(person.key)}
              className="rounded-full border border-[#E8CFC2] bg-[#FBF1EC] px-3.5 py-[7px] text-[12px] font-semibold text-[#8A3D2A] shadow-soft disabled:opacity-45"
            >
              Remove {person.name}
            </button>
          )}
          <span className="text-[12.5px] text-roast">
            {saving === 'waiting'
              ? 'Restarting the house...'
              : saving === 'writing'
                ? 'Saving...'
                : dirty
                  ? `${dirty} change${dirty === 1 ? '' : 's'} pending.`
                  : ''}
          </span>
          <span className="text-[11.5px] text-fawn">
            {saving
              ? 'This takes a few seconds.'
              : dirty
                ? 'Saving restarts the house to apply it.'
                : dev
                  ? 'Nothing pending.'
                  : ''}
          </span>
          {note && !saving && <span className="text-[11.5px] text-[#8A3D2A]">{note}</span>}
          <div className="ml-auto flex gap-2">
            {dev && (
              <button
                type="button"
                onClick={discard}
                disabled={!dirty || !!saving}
                className="rounded-full border border-linen bg-fluff px-3.5 py-[7px] text-[12px] font-semibold text-fawn shadow-soft disabled:opacity-45"
              >
                Discard
              </button>
            )}
            <button
              type="button"
              onClick={() => void save()}
              disabled={!dirty || !!saving}
              className="rounded-full border border-ember bg-gradient-to-b from-honey to-fennec px-4 py-[7px] text-[12px] font-semibold text-roast shadow-soft disabled:opacity-45"
            >
              Save and restart
            </button>
          </div>
        </div>
      )}
    </section>
  );
}
