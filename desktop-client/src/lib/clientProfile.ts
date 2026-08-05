/* Client capability tags.
 *
 * Some settings rows only make sense on some clients: a file-browser button
 * is dead weight on a phone, and iOS follows the OS for theme and text size.
 * Rather than branch on client name at each row, a row declares what it NEEDS
 * and a client declares what it HAS. No row ever asks "am I on iOS?", so
 * adding macOS later is one line here and zero row changes.
 *
 * The table is client-side for v1. The client already sends its identity in
 * client_info, so this can move server-side whenever the settings API lands.
 */

export type Capability = 'files' | 'window' | 'inapp-theme' | 'devpane';
export type ClientId = 'desktop' | 'ios' | 'echo' | 'quest';

export const CLIENTS: Record<ClientId, { label: string; has: Capability[] }> = {
  desktop: { label: 'Hearth desktop', has: ['files', 'window', 'inapp-theme', 'devpane'] },
  ios: { label: 'Hearth iOS', has: [] },
  echo: { label: 'Echo', has: [] },
  quest: { label: 'Quest', has: ['inapp-theme'] },
};

export const CLIENT_ID: ClientId = 'desktop';

/** Does this client carry the capability a row needs? */
export function can(capability: Capability): boolean {
  return CLIENTS[CLIENT_ID].has.includes(capability);
}

/** True when the app runs inside the Tauri shell rather than a browser tab.
 *  Browser dev has no file browser and no window state to remember, so
 *  `files`/`window` rows stay hidden there even though the client is desktop. */
export function isTauri(): boolean {
  return typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
}
