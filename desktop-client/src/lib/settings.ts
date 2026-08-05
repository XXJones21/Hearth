/* Client-local settings.
 *
 * Everything here is owned by THIS device and persisted to localStorage. No
 * server round-trip: the Valar WS protocol has no setter, so a house-wide
 * value cannot be changed from a client yet (see tasks/settings-list.md).
 * House rows render read-only until that API exists.
 */

const KEY = 'hearth_settings';

export type Settings = {
  /** host:port of the Valar server, empty = use the build-time default */
  serverAddress: string;
  autoReconnect: boolean;
  theme: 'light' | 'ember';
  textScale: 'small' | 'medium' | 'large';
  reduceMotion: boolean;
  /** persona to request on connect, empty = whatever the house is on */
  startPersona: string;
  voiceEnabled: boolean;
  voiceVolume: number;
  /* Reveals internal personas, raw config, machine simulation, and the other
     surfaces that are useful to build with and confusing to meet. Off unless
     someone deliberately turns it on. */
  developerMode: boolean;
};

export const DEFAULTS: Settings = {
  serverAddress: '',
  autoReconnect: true,
  theme: 'light',
  textScale: 'medium',
  reduceMotion: false,
  startPersona: '',
  voiceEnabled: true,
  voiceVolume: 0.8,
  developerMode: false,
};

let cache: Settings | null = null;

export function loadSettings(): Settings {
  if (cache) return cache;
  let stored: Partial<Settings> = {};
  try {
    stored = JSON.parse(localStorage.getItem(KEY) || '{}') as Partial<Settings>;
  } catch {
    /* first run, private mode, or corrupt value: defaults are fine */
  }
  // The theme predates this file and shipped under its own key. Honor it so
  // an existing ember choice survives the upgrade.
  if (stored.theme === undefined) {
    try {
      if (localStorage.getItem('hearth_theme') === 'ember') stored.theme = 'ember';
    } catch {
      /* ignore */
    }
  }
  cache = { ...DEFAULTS, ...stored };
  return cache;
}

export const SETTINGS_EVENT = 'hearth-settings-changed';

export function saveSettings(patch: Partial<Settings>): Settings {
  const next = { ...loadSettings(), ...patch };
  cache = next;
  try {
    localStorage.setItem(KEY, JSON.stringify(next));
  } catch {
    /* quota or private mode: the setting still applies this session */
  }
  // The rail's ember shortcut and the Settings panel write the same value, so
  // whichever is open follows the other rather than showing a stale control.
  try {
    window.dispatchEvent(new CustomEvent(SETTINGS_EVENT));
  } catch {
    /* non-browser context */
  }
  return next;
}

/** Normalize whatever was typed into the address field into an origin.
 *  Accepts "host", "host:port", "http://host:port", "ws://host:port". */
export function parseAddress(raw: string): { ws: string; http: string } | null {
  const trimmed = raw.trim().replace(/\/+$/, '');
  if (!trimmed) return null;
  const stripped = trimmed.replace(/^(wss?|https?):\/\//i, '');
  const secure = /^(wss|https):\/\//i.test(trimmed);
  if (!stripped) return null;
  const hostPort = stripped.includes(':') ? stripped : `${stripped}:8700`;
  if (!/^[A-Za-z0-9._-]+(:\d{1,5})?$/.test(hostPort)) return null;
  return {
    ws: `${secure ? 'wss' : 'ws'}://${hostPort}`,
    http: `${secure ? 'https' : 'http'}://${hostPort}`,
  };
}

/** Per-persona transcript keys written by appStore. */
export function historyKeys(): { key: string; persona: string; count: number }[] {
  const out: { key: string; persona: string; count: number }[] = [];
  try {
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      if (!k || !k.startsWith('hearth_msgs_')) continue;
      let count = 0;
      try {
        const parsed = JSON.parse(localStorage.getItem(k) || '[]');
        count = Array.isArray(parsed) ? parsed.length : 0;
      } catch {
        count = 0;
      }
      const persona = k.slice('hearth_msgs_'.length);
      out.push({ key: k, persona: persona === '__default__' ? 'Unassigned' : persona, count });
    }
  } catch {
    /* storage unavailable */
  }
  return out.sort((a, b) => b.count - a.count);
}

export function clearHistory(key?: string): void {
  try {
    if (key) {
      localStorage.removeItem(key);
      return;
    }
    historyKeys().forEach((h) => localStorage.removeItem(h.key));
  } catch {
    /* ignore */
  }
}

/* Text size scales the whole shell rather than a root font-size token: the
   components ship px literals (text-[12.5px]), so rem scaling would move the
   type and leave every gap, icon, and card radius behind. Zoom is the honest
   knob until the literals get converted. */
const SCALE_ZOOM: Record<Settings['textScale'], string> = {
  small: '0.92',
  medium: '1',
  large: '1.09',
};

/** Apply the settings that paint the document. Called at boot and on change. */
export function applyDocumentSettings(s: Settings = loadSettings()): void {
  const root = document.getElementById('root');
  if (root) root.style.zoom = SCALE_ZOOM[s.textScale];
  document.documentElement.classList.toggle('reduce-motion', s.reduceMotion);
  document.querySelector('.hearth-field')?.classList.toggle('ember', s.theme === 'ember');
}
