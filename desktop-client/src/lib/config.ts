import { loadSettings, parseAddress } from './settings';

/* Hearth's own port block. 18700 by design, NOT 8700: the development machine
   runs the internal Valinor stack on 8700, and a Hearth build that defaults to
   it will discover that running house and adopt its data as the new user's.
   Distinct defaults are what let a test install and the daily driver share a
   machine without ever sharing a backend. The Hearth backend provisioner
   binds this same block. */
const defaultWs = 'ws://127.0.0.1:18700';
const defaultHttp = 'http://127.0.0.1:18700';

/* The build-time env is the DEFAULT, not the answer. Settings > Connection
   overrides it at runtime and persists the choice, which is what makes the
   packaged exe reachable at another Valar (and what a tailnet hostname drops
   into later). */

function override(): { ws: string; http: string } | null {
  try {
    return parseAddress(loadSettings().serverAddress);
  } catch {
    return null;
  }
}

/** The token this device was given when it paired, or '' on a local install.
 *
 *  The gateway exempts loopback, so a client supervising its own house on this
 *  machine needs nothing. Every other client is off-machine by definition and
 *  is refused without this. */
export function getDeviceToken(): string {
  try {
    return loadSettings().deviceToken.trim();
  } catch {
    return '';
  }
}

export function getWsUrl(): string {
  const base =
    override()?.ws ||
    (import.meta.env.VITE_HEARTH_WS as string | undefined) ||
    defaultWs;
  /* The token rides in the query string because a browser WebSocket takes a
     URL and nothing else -- no headers, no request object. The gateway reads
     it from either place for exactly this reason. */
  const token = getDeviceToken();
  return token ? `${base}?token=${encodeURIComponent(token)}` : base;
}

export function getHttpOrigin(): string {
  return (
    override()?.http ||
    (import.meta.env.VITE_HEARTH_HTTP_ORIGIN as string | undefined) ||
    defaultHttp
  );
}

/** A URL against the single origin. */
export function houseUrl(path: string): string {
  return `${getHttpOrigin()}${path}`;
}

/* A request against the house, carrying the device token.
 *
 * Every HTTP call in the client goes through this rather than calling fetch
 * with an origin of its own, so "does this carry credentials" is answered by
 * grep instead of by auditing twenty call sites. A site that forgets the
 * header does not fail loudly: it gets a 401 and reports the house
 * unreachable, which looks exactly like a network problem. That is the bug
 * this shape exists to make impossible. */
export function houseFetch(path: string, init?: RequestInit): Promise<Response> {
  const token = getDeviceToken();
  const headers = new Headers(init?.headers);
  if (token) headers.set('Authorization', `Bearer ${token}`);
  return fetch(houseUrl(path), { ...init, headers });
}

/* An asset URL with the token in the QUERY STRING, for the cases that cannot
 * send a header: <img src>, <audio src>, and anything else that takes a URL
 * rather than a request. Second choice everywhere else -- a query string lands
 * in server logs where a header does not -- but the alternative is every
 * picture in the client 401ing the moment the house is on another machine. */
export function assetUrl(url: string): string {
  const token = getDeviceToken();
  if (!token) return url;
  return `${url}${url.includes('?') ? '&' : '?'}token=${encodeURIComponent(token)}`;
}

/** What the address field shows when nothing has been typed yet. */
export function defaultAddressLabel(): string {
  const http = (import.meta.env.VITE_HEARTH_HTTP_ORIGIN as string | undefined) || defaultHttp;
  return http.replace(/^https?:\/\//, '');
}
