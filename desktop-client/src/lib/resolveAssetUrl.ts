import { getHttpOrigin } from './config';

/**
 * Resolve a manifest-relative asset path to a loadable URL.
 * In dev, same-origin `/Persona/...` is proxied by Vite to the Hearth server (port 8700) so the
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
  if (trimmed.startsWith('assets/')) {
    return `${getHttpOrigin()}/${trimmed}`;
  }
  if (import.meta.env.DEV) {
    return `/Persona/${trimmed}`;
  }
  const origin = getHttpOrigin();
  return `${origin}/Persona/${trimmed}`;
}
