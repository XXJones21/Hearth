import { isTauri } from './clientProfile';

/* Hand a path to the OS file browser.
 *
 * Valar runs in WSL, so the paths it reports are POSIX (/mnt/d/Tools/...).
 * Windows Explorer cannot open those, so translate the /mnt/<drive> prefix
 * back to a drive letter. A path that is already Windows-shaped passes
 * through untouched. */
export function toHostPath(path: string): string {
  const wsl = /^\/mnt\/([a-z])(\/.*)?$/i.exec(path);
  if (wsl) {
    const rest = (wsl[2] || '').replace(/\//g, '\\');
    return `${wsl[1].toUpperCase()}:${rest || '\\'}`;
  }
  return path;
}

/** Opens the folder, or returns a short reason it could not.
 *
 * Two calls, because they fail differently: openPath asks the OS to open the
 * directory, revealItemInDir opens its parent with the folder selected. Both
 * are scoped in src-tauri/capabilities/default.json -- granting the bare
 * permission string leaves the path scope EMPTY, which denies every path and
 * is what broke the first build. The real error is surfaced rather than
 * swallowed so the next failure is diagnosable from the panel. */
export async function revealFolder(path: string): Promise<string | null> {
  if (!isTauri()) return 'Only the desktop app can open folders';
  const target = toHostPath(path);
  let firstError = '';
  try {
    const { openPath } = await import('@tauri-apps/plugin-opener');
    await openPath(target);
    return null;
  } catch (err) {
    firstError = err instanceof Error ? err.message : String(err);
  }
  try {
    const { revealItemInDir } = await import('@tauri-apps/plugin-opener');
    await revealItemInDir(target);
    return null;
  } catch (err) {
    const second = err instanceof Error ? err.message : String(err);
    return `Could not open ${target}: ${firstError || second}`;
  }
}
