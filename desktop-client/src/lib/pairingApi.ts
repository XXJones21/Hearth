import { houseFetch } from './config';

/* Device pairing: who is allowed to talk to this house from off the machine.
 *
 * The gateway now binds 0.0.0.0 so a phone on the same network can reach it,
 * and its routes are not read-only -- /personas/apply rewrites a system prompt,
 * /apps/apply rewrites tools.yaml and restarts the server. So everything that
 * arrives from anywhere except this machine has to present a device token.
 *
 * A client that installed its own house needs no token: it dials 127.0.0.1,
 * and the gateway exempts loopback, because a caller on that machine already
 * has filesystem access to everything the gateway could hand it. A client that
 * JOINED a house on another machine is off-machine by definition and needs
 * one, which is what `claim` below is for.
 *
 * That loopback exemption is also why the four management routes here work at
 * all -- they are refused from off the machine even WITH a valid token, so a
 * stolen phone cannot pair its thief's phone or revoke the devices its owner
 * still has. It is the same reason a joined client shows no device list: it is
 * not standing on the house, and asking would only ever 401.
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
    const res = await houseFetch(`${path}`, { cache: 'no-store', ...init });
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

/* ---- the joining half: this device asking to be let into someone else's
   house. Everything above is the house's own screen; everything below runs on
   the machine that does NOT have the install. ---- */

export type ClaimFailure = 'rejected' | 'unsupported' | 'unreachable' | 'noaddress';

export type ClaimResult =
  | { ok: true; token: string }
  | { ok: false; why: ClaimFailure; detail: string };

/** Is a house answering at this origin, and what is it?
 *
 *  /health is deliberately open on the gateway: "is my address right" and "am
 *  I paired" have to be separately answerable, or a person retyping an address
 *  cannot tell which of the two they got wrong. */
export async function reachHouse(
  origin: string,
): Promise<{ ok: boolean; detail: string; personas?: string[] }> {
  try {
    const res = await fetch(`${origin}/health`, { cache: 'no-store' });
    if (!res.ok) return { ok: false, detail: `The house answered with HTTP ${res.status}.` };
    const body = (await res.json()) as { personas?: string[] };
    return { ok: true, detail: 'answering', personas: body.personas };
  } catch {
    return {
      ok: false,
      detail: 'Nothing answered there. Check the address, and that Hearth is running on that machine.',
    };
  }
}

/** Trade a six-digit code for this device's token.
 *
 *  Takes an explicit origin rather than reading the saved one: during first
 *  run nothing is saved yet, and saving an address that turns out to be wrong
 *  would leave the client dialling it forever. The address is only written
 *  once the house on the other end has agreed to let this device in.
 *
 *  This is the one request in the client that carries no token, because it is
 *  the request that asks for one. */
export async function claim(
  origin: string,
  code: string,
  deviceName: string,
): Promise<ClaimResult> {
  if (!origin) return { ok: false, why: 'noaddress', detail: 'No house address yet.' };
  let res: Response;
  try {
    res = await fetch(`${origin}/pair`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ code: code.trim(), device_name: deviceName.trim() || 'Mac' }),
    });
  } catch {
    /* Unreachable and refused are different problems with different fixes --
       check the address versus check the code -- so they never share a
       sentence. */
    return {
      ok: false,
      why: 'unreachable',
      detail: `Could not reach ${origin.replace(/^https?:\/\//, '')}. Check the address.`,
    };
  }
  if (res.status === 404) {
    return {
      ok: false,
      why: 'unsupported',
      detail: 'That house does not support pairing yet. Update Hearth on the machine running it.',
    };
  }
  if (!res.ok) {
    /* The house answers one way for wrong, expired and locked-out, because
       telling them apart is a free hint to anyone guessing. This client must
       not invent a more specific story than it was told. */
    return {
      ok: false,
      why: 'rejected',
      detail: 'That code was not accepted. Ask the other machine for a new one.',
    };
  }
  const body = (await res.json().catch(() => ({}))) as { token?: string };
  if (!body.token) {
    return {
      ok: false,
      why: 'unreachable',
      detail: 'The house accepted the code but sent no token.',
    };
  }
  return { ok: true, token: body.token };
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
