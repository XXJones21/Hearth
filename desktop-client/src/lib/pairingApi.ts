import { getHttpOrigin } from './config';

/* Device pairing: who is allowed to talk to this house from off the machine.
 *
 * The gateway now binds 0.0.0.0 so a phone on the same network can reach it,
 * and its routes are not read-only -- /personas/apply rewrites a system prompt,
 * /apps/apply rewrites tools.yaml and restarts the server. So everything that
 * arrives from anywhere except this machine has to present a device token.
 *
 * THIS CLIENT NEEDS NO TOKEN. It dials 127.0.0.1, and the gateway exempts
 * loopback: a caller on this machine already has filesystem access to
 * everything the gateway could hand it, so a token would protect nothing. That
 * exemption is also why these four routes work at all -- they are refused from
 * off the machine even WITH a valid token, so a stolen phone cannot pair its
 * thief's phone or revoke the devices its owner still has.
 */

export type PairedDevice = {
  id: string;
  name: string;
  /** epoch seconds */
  created: number;
  /** epoch seconds; 0 when never seen since pairing */
  last_seen: number;
};

/* Three different failures need three different sentences, because they need
 * three different actions from the person reading them:
 *
 *   404  this house predates pairing        -> update the house
 *   401  this client is not ON the house    -> go to that machine
 *   -    unreachable                        -> the house is not running
 *
 * Collapsing them into one "could not pair" is how someone spends an evening
 * updating software that was never the problem. */
export type Failure = 'unsupported' | 'remote' | 'unreachable';

export type Result<T> = { ok: true; value: T } | { ok: false; why: Failure };

async function call<T>(path: string, init?: RequestInit): Promise<Result<T>> {
  try {
    const res = await fetch(`${getHttpOrigin()}${path}`, { cache: 'no-store', ...init });
    if (res.status === 404) return { ok: false, why: 'unsupported' };
    // The gateway exempts loopback and refuses the management routes from
    // anywhere else, token or not. A client pointed at another machine's house
    // is exactly that case, and the fix is to walk to the other machine.
    if (res.status === 401 || res.status === 403) return { ok: false, why: 'remote' };
    if (!res.ok) return { ok: false, why: 'unreachable' };
    return { ok: true, value: (await res.json()) as T };
  } catch {
    return { ok: false, why: 'unreachable' };
  }
}

function post<T>(path: string, body?: unknown): Promise<Result<T>> {
  return call<T>(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body ?? {}),
  });
}

/** What to tell the person, given why it failed. */
export function explain(why: Failure): string {
  switch (why) {
    case 'unsupported':
      return 'This house does not support pairing yet. Update Hearth on the machine running it.';
    case 'remote':
      return 'Pairing happens on the machine running the house. Open Hearth there.';
    case 'unreachable':
      return 'The house is not answering. Check that it is running.';
  }
}

/** Open a pairing window. Returns the code to show and how long it lasts. */
export async function openPairing(): Promise<Result<{ code: string; expires_in: number }>> {
  return post<{ code: string; expires_in: number }>('/pair/open');
}

/** Close the window early -- when the panel is dismissed, or a device pairs. */
export async function closePairing(): Promise<void> {
  await post('/pair/close');
}

export async function listDevices(): Promise<
  Result<{ devices: PairedDevice[]; pairing_open: boolean }>
> {
  return call<{ devices: PairedDevice[]; pairing_open: boolean }>('/pair/devices');
}

/** Revoke a device. Its token stops working on the house's next request. */
export async function revokeDevice(id: string): Promise<boolean> {
  const out = await post<{ ok: boolean }>('/pair/revoke', { id });
  return out.ok && out.value.ok;
}

/** "3 minutes ago", for a list whose only job is telling devices apart. */
export function relativeTime(epochSeconds: number): string {
  if (!epochSeconds) return 'never';
  const seconds = Math.max(0, Math.floor(Date.now() / 1000 - epochSeconds));
  if (seconds < 60) return 'just now';
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return days === 1 ? 'yesterday' : `${days}d ago`;
}
