import { getHttpOrigin, houseFetch } from './config';

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

/** Where memory lives. Its own row rather than one of the folders, because it
    has to be answerable when the answer is "nowhere yet". */
export type EngramRow = {
  path: string;
  connected: boolean;
  exists: boolean;
  entries: number;
};

export type SettingsSurface = {
  folders: FolderRow[];
  engram?: EngramRow;
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
    const res = await houseFetch(`/settings/surface`, { cache: 'no-store' });
    if (!res.ok) return null;
    return (await res.json()) as SettingsSurface;
  } catch {
    // Older server without the endpoint, or unreachable: the panel degrades
    // to its client-local rows rather than showing an error.
    return null;
  }
}

/** Point the house at a memory tree. An existing brain is adopted as it is; an
    empty folder is provisioned into one. Anything else is refused by the house,
    which is the same rule the conversational bridge follows. */
export async function setEngram(
  path: string,
): Promise<{ ok: boolean; error?: string; engram?: EngramRow; created?: boolean }> {
  return engramRequest({ path });
}

/** Unplug the memory tree. Nothing on disk is deleted. */
export async function clearEngram(): Promise<{
  ok: boolean;
  error?: string;
  engram?: EngramRow;
}> {
  return engramRequest({ clear: true });
}

async function engramRequest(
  body: Record<string, unknown>,
): Promise<{ ok: boolean; error?: string; engram?: EngramRow; created?: boolean }> {
  try {
    const res = await houseFetch(`/settings/engram`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const data = (await res.json()) as {
      ok?: boolean;
      error?: string;
      created?: boolean;
      engram?: EngramRow;
    };
    return {
      ok: Boolean(data.ok),
      error: data.error,
      created: data.created,
      engram: data.engram,
    };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : 'unreachable' };
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
