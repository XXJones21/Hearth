import { assetUrl, getHttpOrigin } from './config';

/**
 * Resolve a manifest-relative asset path to a loadable URL.
 * In dev, same-origin `/Persona/...` is proxied by Vite to the Hearth server (port 18700) so the
 * GLTF loader does not hit cross-origin CORS. Production builds use the configured HTTP origin; the
 * Hearth asset server also sends CORS for direct use.
 */
export function resolvePersonaAssetUrl(
  path: string,
  _personaName: string
): string {
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return path;
  }
  const trimmed = path.replace(/^\/+/, '');
  // Server-generated assets (the imagery plumb) live under /assets, not
  // /Persona -- always absolute-origin (Valar sends CORS for webviews).
  /* The token goes in the query string here, and only here, because these
     URLs are handed to loaders and <img>/<audio> tags that take a URL and
     cannot carry a header. A house on another machine refuses them without
     it, and the failure looks like a broken image rather than a 401. */
  if (trimmed.startsWith('assets/')) {
    return assetUrl(`${getHttpOrigin()}/${trimmed}`);
  }
  if (import.meta.env.DEV) {
    return `/Persona/${trimmed}`;
  }
  const origin = getHttpOrigin();
  return assetUrl(`${origin}/Persona/${trimmed}`);
}
