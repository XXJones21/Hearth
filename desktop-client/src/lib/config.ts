import { loadSettings, parseAddress } from './settings';

const defaultWs = 'ws://127.0.0.1:8700';
const defaultHttp = 'http://127.0.0.1:8700';

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

export function getWsUrl(): string {
  return (
    override()?.ws ||
    (import.meta.env.VITE_HEARTH_WS as string | undefined) ||
    defaultWs
  );
}

export function getHttpOrigin(): string {
  return (
    override()?.http ||
    (import.meta.env.VITE_HEARTH_HTTP_ORIGIN as string | undefined) ||
    defaultHttp
  );
}

/** What the address field shows when nothing has been typed yet. */
export function defaultAddressLabel(): string {
  const http = (import.meta.env.VITE_HEARTH_HTTP_ORIGIN as string | undefined) || defaultHttp;
  return http.replace(/^https?:\/\//, '');
}
