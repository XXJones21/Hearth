import { useEffect, useState } from 'react';
import { Btn, IconFolder, Row, Section, Segmented, Toggle } from './controls';
import { ttsPlayer } from '../../lib/audioPlayer';
import { can } from '../../lib/clientProfile';
import { defaultAddressLabel } from '../../lib/config';
import { houseStart, houseStatus, houseStop, type HouseStatus } from '../../lib/house';
import { revealFolder, toHostPath } from '../../lib/openPath';
import {
  applyDocumentSettings,
  clearHistory,
  historyKeys,
  loadSettings,
  parseAddress,
  saveSettings,
  SETTINGS_EVENT,
  type Settings,
} from '../../lib/settings';
import { fetchSurface, probeHealth, type SettingsSurface } from '../../lib/settingsApi';
import { useAppStore } from '../../store/appStore';

type Props = {
  /** drop the socket and dial the current address again */
  onReconnect: () => void;
};

export function SettingsView({ onReconnect }: Props) {
  const [s, setS] = useState<Settings>(loadSettings);
  const [surface, setSurface] = useState<SettingsSurface | null>(null);
  const [health, setHealth] = useState<{ ok: boolean; ms: number; text: string } | null>(null);
  const [testing, setTesting] = useState(false);
  const [note, setNote] = useState('');
  const [history, setHistory] = useState(historyKeys);

  const personas = useAppStore((st) => st.personas);
  const connection = useAppStore((st) => st.connection);
  const lastError = useAppStore((st) => st.lastError);
  const resetMessages = useAppStore((st) => st.resetMessages);

  const set = (patch: Partial<Settings>) => {
    const next = saveSettings(patch);
    setS(next);
    applyDocumentSettings(next);
  };

  const flash = (msg: string) => {
    setNote(msg);
    window.setTimeout(() => setNote((n) => (n === msg ? '' : n)), 2600);
  };

  useEffect(() => {
    void fetchSurface().then(setSurface);
    void runTest();
    const sync = () => setS(loadSettings());
    window.addEventListener(SETTINGS_EVENT, sync);
    return () => window.removeEventListener(SETTINGS_EVENT, sync);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    ttsPlayer.setOutput(s.voiceEnabled, s.voiceVolume);
  }, [s.voiceEnabled, s.voiceVolume]);

  /* The house is the backend process tree this client supervises, and it is
     only ever started for you: on boot, and at the end of setup. When it dies
     or is stopped there is nothing in the interface that can bring it back,
     so the only way out has been to quit and relaunch. These two buttons are
     that missing door. Local installs only -- a client pointed at another
     machine's house has no business starting or stopping it. */
  const [house, setHouse] = useState<HouseStatus | null>(null);
  const [houseBusy, setHouseBusy] = useState(false);
  const localHouse = !s.serverAddress.trim() && !!s.installRoot;

  useEffect(() => {
    if (!localHouse) return;
    let alive = true;
    const poll = () => {
      houseStatus()
        .then((h) => alive && setHouse(h))
        .catch(() => alive && setHouse(null));
    };
    poll();
    const id = window.setInterval(poll, 2000);
    return () => {
      alive = false;
      window.clearInterval(id);
    };
  }, [localHouse]);

  async function toggleHouse(start: boolean) {
    setHouseBusy(true);
    try {
      if (start) {
        await houseStart(s.installRoot);
        flash('Starting the house');
      } else {
        await houseStop();
        flash('Stopped the house');
      }
    } catch (e) {
      flash(String(e));
    } finally {
      setHouseBusy(false);
      houseStatus().then(setHouse).catch(() => undefined);
    }
  }

  async function runTest() {
    setTesting(true);
    const r = await probeHealth();
    setTesting(false);
    setHealth({
      ok: r.ok,
      ms: r.ms,
      text: r.ok
        ? `${r.info?.brain_backend ?? 'brain'} ${r.info?.brain_ready ? 'ready' : 'starting'}`
        : r.error || 'unreachable',
    });
  }

  const addressValid = !s.serverAddress.trim() || parseAddress(s.serverAddress) !== null;
  const sessionsFolder =
    surface?.folders.find((f) => f.key === 'sessions') ??
    surface?.folders.find((f) => f.key === 'journal');

  return (
    <section className="flex min-h-0 flex-col overflow-hidden" aria-label="Settings">
      <div className="flex items-baseline gap-3 px-7 pt-6">
        <h2 className="text-[20px] font-bold text-roast">Settings</h2>
        <span className="text-[12px] italic text-fawn">how the house behaves</span>
        <span className="ml-auto flex items-center gap-2 text-[11.5px] text-fawn">
          <span className="rounded-full border border-bubble-line bg-tab px-2 py-[3px] text-[10px] font-semibold uppercase tracking-wide text-roast">
            The house
          </span>
          shared by every device
        </span>
      </div>

      <div className="mt-4 min-h-0 flex-1 overflow-y-auto px-7 pb-7">
        {note && (
          <div className="mb-3 rounded-[12px] border border-bubble-line bg-glowtint px-4 py-2.5 text-[12px] text-roast">
            {note}
          </div>
        )}

        {/* ---------------- Connection ---------------- */}
        <Section label="Connection" sub="where this device finds the hearth">
          <Row
            label="Server address"
            hint="Hostname or IP of the Valar server. A tailnet name works from anywhere."
          >
            <input
              value={s.serverAddress}
              onChange={(e) => set({ serverAddress: e.target.value })}
              placeholder={defaultAddressLabel()}
              spellCheck={false}
              aria-label="Server address"
              aria-invalid={!addressValid}
              className={`w-56 rounded-[10px] border bg-parchment px-3 py-2 text-[13px] text-roast placeholder:text-fawn focus:bg-fluff focus:outline-none ${
                addressValid ? 'border-linen focus:border-fennec' : 'border-[#E8CFC2]'
              }`}
            />
            <Btn onClick={runTest} disabled={testing || !addressValid}>
              {testing ? 'Testing' : 'Test'}
            </Btn>
            <Btn
              onClick={() => {
                onReconnect();
                flash('Reconnecting to ' + (s.serverAddress.trim() || defaultAddressLabel()));
                window.setTimeout(runTest, 900);
              }}
              disabled={!addressValid}
            >
              Apply
            </Btn>
          </Row>

          {localHouse && (
            <Row
              label="The house"
              hint="The backend on this machine: the mind, the voice, and the ears. Stopping it frees their memory; starting it brings them back without relaunching Hearth."
            >
              <span
                className={`text-[12px] ${
                  house?.running ? 'font-semibold text-[#0F7A52]' : 'text-fawn'
                }`}
              >
                {house === null
                  ? 'unknown'
                  : house.running
                    ? `running${
                        house.processes.length ? ` (${house.processes.length} processes)` : ''
                      }`
                    : 'stopped'}
              </span>
              <Btn onClick={() => toggleHouse(true)} disabled={houseBusy || !!house?.running}>
                Start
              </Btn>
              <Btn onClick={() => toggleHouse(false)} disabled={houseBusy || !house?.running}>
                Stop
              </Btn>
            </Row>
          )}

          {localHouse && house?.processes?.some((p) => p.state === 'failed') && (
            <div className="mt-2 rounded-[14px] border border-[#E8CFC2] bg-glowtint px-4 py-2.5 text-[12px] text-fawn">
              {house.processes
                .filter((p) => p.state === 'failed')
                .map((p) => (
                  <div key={p.name}>
                    <span className="font-semibold">{p.name}</span> failed
                    {p.detail ? `: ${p.detail}` : ''}
                  </div>
                ))}
            </div>
          )}

          <div className="mt-2 flex flex-wrap items-center gap-4 rounded-[14px] border border-bubble-line bg-glowtint px-4 py-2.5 text-[12px] text-fawn">
            <span className={connection === 'ready' ? 'font-semibold text-[#0F7A52]' : ''}>
              {connection === 'ready'
                ? 'Connected'
                : connection === 'connecting'
                  ? 'Connecting'
                  : 'Not connected'}
            </span>
            {surface && (
              <span>
                Valar <b className="font-semibold text-roast">{surface.server.version}</b>
              </span>
            )}
            {health && (
              <>
                <span>
                  health <b className="font-semibold text-roast">{health.text}</b>
                </span>
                {health.ok && (
                  <span>
                    latency <b className="font-semibold text-roast">{health.ms} ms</b>
                  </span>
                )}
              </>
            )}
            <span className="ml-auto">{lastError ? `last error: ${lastError}` : 'no errors'}</span>
          </div>

          <Row
            label="Reconnect automatically"
            hint="Backs off from 1s to 10s. Turn off only while debugging."
          >
            <Toggle
              checked={s.autoReconnect}
              onChange={(v) => set({ autoReconnect: v })}
              label="Reconnect automatically"
            />
          </Row>
        </Section>

        {/* ---------------- Appearance ---------------- */}
        <Section label="Appearance" sub="the light in the room" needs="inapp-theme">
          <Row label="Theme" hint="Ember is the warm-dark variant for evenings.">
            <Segmented
              label="Theme"
              value={s.theme}
              onChange={(v) => set({ theme: v })}
              options={[
                { id: 'light', label: 'Light' },
                { id: 'ember', label: 'Ember' },
              ]}
            />
          </Row>
          <Row label="Text size" hint="Scales the whole interface.">
            <Segmented
              label="Text size"
              value={s.textScale}
              onChange={(v) => set({ textScale: v })}
              options={[
                { id: 'small', label: 'Small' },
                { id: 'medium', label: 'Medium' },
                { id: 'large', label: 'Large' },
              ]}
            />
          </Row>
          <Row
            label="Reduce motion"
            hint="Stills the orb's breathing and card transitions. Follows your system setting by default."
          >
            <Toggle
              checked={s.reduceMotion}
              onChange={(v) => set({ reduceMotion: v })}
              label="Reduce motion"
            />
          </Row>
          {/* "Remember window size and position" is deliberately absent: it
              needs tauri-plugin-window-state, which restores before any JS
              runs, so a toggle could not gate it honestly. Deferred rather
              than shipped as a control that stores a preference nothing
              reads. See tasks/settings-list.md. */}
        </Section>

        {/* ---------------- Personas ---------------- */}
        <Section label="Personas" sub="who greets you, and what they remember">
          <Row label="Start with" hint="The persona this device asks for on connect.">
            <select
              value={s.startPersona}
              onChange={(e) => set({ startPersona: e.target.value })}
              aria-label="Start with"
              className="rounded-[10px] border border-linen bg-parchment px-3 py-2 text-[13px] text-roast focus:outline-none"
            >
              <option value="">Whoever the house is on</option>
              {personas.map((p) => (
                <option key={p.name} value={p.name}>
                  {p.name}
                </option>
              ))}
            </select>
          </Row>

          <Row
            label="Conversation history"
            hint={
              (history.length
                ? `Kept on this device, per persona. ${history
                    .map((h) => `${h.persona} ${h.count}`)
                    .join(' · ')}.`
                : 'Nothing kept on this device yet.') +
              (sessionsFolder ? ' The house keeps its own copy of every session.' : '')
            }
          >
            {/* Opens where the SESSIONS live, not the journal. The journal is
                the readable view; this is the raw .scx a conversation was
                written to, which is the only way to find an old one until a
                resume or an SCX reader exists. */}
            {sessionsFolder && can('files') && (
              <Btn
                onClick={async () => {
                  const err = await revealFolder(sessionsFolder.path);
                  flash(err ? err : `Opened ${toHostPath(sessionsFolder.path)}`);
                }}
              >
                <span className="flex items-center gap-1.5">
                  <IconFolder className="h-3.5 w-3.5 text-ember" /> Open folder
                </span>
              </Btn>
            )}
            <Btn
              tone="warn"
              disabled={!history.length}
              onClick={() => {
                clearHistory();
                resetMessages();
                setHistory(historyKeys());
                flash('Cleared every conversation on this device');
              }}
            >
              Clear all
            </Btn>
          </Row>

          {history.map((h) => (
            <Row key={h.key} label={h.persona} hint={`${h.count} messages on this device`}>
              <Btn
                onClick={() => {
                  clearHistory(h.key);
                  if (h.persona === useAppStore.getState().currentPersonaName) resetMessages();
                  setHistory(historyKeys());
                  flash(`Cleared ${h.persona}`);
                }}
              >
                Clear
              </Btn>
            </Row>
          ))}
        </Section>

        {/* ---------------- Voice ---------------- */}
        <Section label="Voice" sub="how the house sounds">
          <Row label="Speak replies aloud" hint="Muting stops the sound, not the reply.">
            <input
              type="range"
              min={0}
              max={100}
              value={Math.round(s.voiceVolume * 100)}
              aria-label="Voice volume"
              onChange={(e) => set({ voiceVolume: Number(e.target.value) / 100 })}
              className="h-1 w-32 cursor-pointer appearance-none rounded bg-linen accent-fennec"
            />
            <Toggle
              checked={s.voiceEnabled}
              onChange={(v) => set({ voiceEnabled: v })}
              label="Speak replies aloud"
            />
          </Row>
        </Section>

        {/* ---------------- Memory (house, read-only) ---------------- */}
        <Section label="Memory and journal" sub="what the house keeps">
          <Row
            house
            label="Remember our conversations"
            hint="Off means nothing is written to the journal. The house forgets when the session ends."
          >
            <span className="text-[12.5px] text-fawn">
              {resolvedValue(surface, 'memory') || 'unknown'}
            </span>
          </Row>
          <Row
            house
            label="End a session after"
            hint="Quiet time before the house closes the page and writes it up."
          >
            <span className="text-[12.5px] text-fawn">
              {resolvedValue(surface, 'session idle') || 'unknown'}
            </span>
          </Row>
          <div className="mt-2 flex gap-3 rounded-[14px] border border-dashed border-bubble-line bg-parchment px-4 py-3 text-[12.5px] leading-relaxed text-fawn">
            <span>
              <b className="text-roast">House settings need the server to accept changes.</b> Every
              value above is read once when Valar starts, so these rows are read-only until the
              settings API lands. They are shown so the shape is agreed before it is built.
            </span>
          </div>
        </Section>

        {/* ---------------- On disk ---------------- */}
        {surface && surface.folders.length > 0 && (
          <Section
            label="On disk"
            sub="where the house keeps its things, on the machine running Hearth"
            needs="files"
          >
            {surface.folders.map((f) => (
              <Row
                key={f.key}
                label={f.name}
                hint={`${toHostPath(f.path)} · ${f.detail}`}
              >
                <Btn
                  disabled={!f.exists}
                  onClick={async () => {
                    const err = await revealFolder(f.path);
                    flash(err ? err : `Opened ${toHostPath(f.path)}`);
                  }}
                >
                  <span className="flex items-center gap-1.5">
                    <IconFolder className="h-3.5 w-3.5 text-ember" /> Open folder
                  </span>
                </Btn>
              </Row>
            ))}
          </Section>
        )}

        {/* ---------------- Connections ---------------- */}
        {/* ---------------- Developer ---------------- */}
        {/* Lives outside the pane it opens, or there would be no way to reach
            it. Off by default: everything it reveals is useful to build with
            and confusing to meet. */}
        <Section label="Developer" sub="for building on the house, not living in it">
          <Row label="Developer mode" hint="Reveals internal personas, raw configuration, and machine simulation.">
            <Toggle
              checked={s.developerMode}
              onChange={(v) => set({ developerMode: v })}
              label="Developer mode"
            />
          </Row>
        </Section>

        <Section label="Connections" sub="what the house is plugged into">
          {surface?.connections.map((c) => (
            <Row
              key={c.key}
              label={
                <span className="flex items-center gap-2.5">
                  <span
                    className={`h-2 w-2 rounded-full ${
                      c.state === 'live' ? 'bg-emerald-600' : 'border border-bubble-line bg-linen'
                    }`}
                  />
                  {c.name}
                  <span
                    className={`text-[11.5px] ${
                      c.state === 'live' ? 'font-semibold text-[#0F7A52]' : 'text-fawn'
                    }`}
                  >
                    {c.state === 'live' ? 'Connected' : 'Not set up'}
                  </span>
                </span>
              }
              hint={c.detail ? `${c.role}. ${c.detail}` : c.role}
            />
          ))}
          {!surface && (
            <div className="rounded-[14px] border border-linen bg-fluff px-4 py-3 text-[12.5px] text-fawn">
              The server has not answered yet.
            </div>
          )}
          <div className="mt-2 flex gap-3 rounded-[14px] border border-bubble-line bg-glowtint px-4 py-3 text-[12.5px] leading-relaxed text-fawn">
            <span>
              This list grows on its own. Anything with an account or a key gets set up in{' '}
              <b className="text-roast">Apps</b>, and shows up here once it answers. Settings is how
              the house behaves. Apps is what it is connected to.
            </span>
          </div>
        </Section>

        {/* ---------------- Advanced ---------------- */}
        {s.developerMode && surface && (
          <Section label="Advanced" sub="for the person who builds the house">
            <details className="group">
              <summary className="flex cursor-pointer list-none items-center gap-2.5 rounded-[14px] border border-linen bg-fluff px-4 py-3 text-[13.5px] text-roast">
                <span className="rounded-full border border-[#DED5CA] bg-[#EDE7E0] px-2 py-[3px] text-[10px] font-semibold uppercase tracking-wide text-fawn">
                  Developer
                </span>
                Diagnostics and test tools
              </summary>
              <div className="mt-2 rounded-[14px] border border-linen bg-[#FCFAF6] px-4 py-3.5">
                <dl className="font-mono text-[11.5px] leading-[1.85] text-fawn">
                  {surface.resolved.map((r) => (
                    <div key={r.label} className="flex gap-3">
                      <dt className="w-28 shrink-0">{r.label}</dt>
                      <dd className="text-roast">
                        {r.value}
                        {r.drift && <span className="ml-2 text-[#8A3D2A]">({r.drift})</span>}
                      </dd>
                    </div>
                  ))}
                </dl>
                <div className="mt-3 flex flex-wrap gap-2">
                  <Btn
                    onClick={() => {
                      void navigator.clipboard
                        ?.writeText(JSON.stringify(surface, null, 2))
                        .then(() => flash('Copied the resolved surface'))
                        .catch(() => flash('Clipboard unavailable'));
                    }}
                  >
                    Copy config
                  </Btn>
                  <Btn
                    onClick={() => {
                      onReconnect();
                      flash('Reconnecting');
                    }}
                  >
                    Force reconnect
                  </Btn>
                </div>
              </div>
            </details>
          </Section>
        )}

        <p className="pt-1 text-center text-[11.5px] italic text-fawn">
          Hearth {surface?.server.version ?? ''} &middot; local-first &middot; nothing here leaves
          the house
        </p>
      </div>
    </section>
  );
}

function resolvedValue(surface: SettingsSurface | null, label: string): string {
  return surface?.resolved.find((r) => r.label === label)?.value ?? '';
}
