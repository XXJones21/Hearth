import { houseFetch } from './config';

/* The Apps surface: what the house is connected to. Every field is derived
   server-side from tools.yaml, card_catalog.yaml, and each persona's grants,
   so the client renders whatever arrives and invents nothing. */

export type AppRow = {
  key: string;
  name: string;
  kind: 'core' | 'cli' | 'local' | 'mcp';
  tagline: string;
  transport: string;
  tools: string[];
  more: number;
  cards: string[];
  who: string[];
  state: 'active' | 'setup' | 'available';
  risk: 'read' | 'write' | 'control';
  needs: string[];
  locked?: boolean;
};

export type CardRow = {
  type: string;
  purpose: string;
  data_fields: string;
  state: 'builtin' | 'forged' | 'scaffold';
};

export type AppsSurface = {
  apps: AppRow[];
  cards: CardRow[];
  personas: string[];
  tools_enabled: boolean;
};

export async function fetchApps(): Promise<AppsSurface | null> {
  try {
    const res = await houseFetch(`/apps/surface`, { cache: 'no-store' });
    if (!res.ok) return null;
    return (await res.json()) as AppsSurface;
  } catch {
    return null;
  }
}

export type AppsChanges = {
  /** app key -> should it be on */
  apps: Record<string, boolean>;
  /** persona -> app key -> may they use it */
  grants: Record<string, Record<string, boolean>>;
};

/* Applying writes tools.yaml and the persona files, both of which are read
   once at process start, so the server bounces itself afterwards. systemd
   brings it back in about five seconds (Restart=always). */
export async function applyApps(
  changes: AppsChanges,
): Promise<{ ok: boolean; changed?: string[]; restarting?: boolean; error?: string }> {
  try {
    const res = await houseFetch(`/apps/apply`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(changes),
    });
    return (await res.json()) as { ok: boolean; changed?: string[]; error?: string };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : 'unreachable' };
  }
}

/** Poll /health until the house answers again after a restart. */
export async function waitForServer(timeoutMs = 45000): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 1500));
    try {
      const res = await houseFetch(`/health`, { cache: 'no-store' });
      if (res.ok) return true;
    } catch {
      /* still down */
    }
  }
  return false;
}
