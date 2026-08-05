import { getHttpOrigin } from './config';

/* The read-only settings surface Valar serves at /settings/surface: the
   folders a client may open, the connections the house has registered, and
   the resolved config for the developer pane. Registries, not fixed lists --
   a new folder or a packaged extension appears without a client change. */

export type FolderRow = {
  key: string;
  name: string;
  path: string;
  detail: string;
  exists: boolean;
};

export type ConnectionRow = {
  key: string;
  name: string;
  role: string;
  state: 'live' | 'off';
  detail: string;
};

export type ResolvedRow = { label: string; value: string; drift: string };

export type SettingsSurface = {
  folders: FolderRow[];
  connections: ConnectionRow[];
  resolved: ResolvedRow[];
  server: { version: string; port: number; brain_backend: string };
};

export type HealthInfo = {
  status: string;
  brain_backend: string;
  brain_ready: boolean;
  current_persona: string | null;
};

export async function fetchSurface(): Promise<SettingsSurface | null> {
  try {
    const res = await fetch(`${getHttpOrigin()}/settings/surface`, { cache: 'no-store' });
    if (!res.ok) return null;
    return (await res.json()) as SettingsSurface;
  } catch {
    // Older server without the endpoint, or unreachable: the panel degrades
    // to its client-local rows rather than showing an error.
    return null;
  }
}

/** Probe an origin for /health. Returns latency in ms alongside the payload. */
export async function probeHealth(
  origin?: string,
): Promise<{ ok: boolean; ms: number; info?: HealthInfo; error?: string }> {
  const target = origin || getHttpOrigin();
  const started = performance.now();
  try {
    const res = await fetch(`${target}/health`, { cache: 'no-store' });
    const ms = Math.round(performance.now() - started);
    if (!res.ok) return { ok: false, ms, error: `HTTP ${res.status}` };
    return { ok: true, ms, info: (await res.json()) as HealthInfo };
  } catch (err) {
    return {
      ok: false,
      ms: Math.round(performance.now() - started),
      error: err instanceof Error ? err.message : 'unreachable',
    };
  }
}
