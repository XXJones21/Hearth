/* Light-first with an "ember" warm-dark variant.
 *
 * Settings > Appearance owns the value now; this stays as the rail's
 * one-tap shortcut so both controls read and write the same place. */

import { applyDocumentSettings, loadSettings, saveSettings } from './settings';

export function isEmber(): boolean {
  return loadSettings().theme === 'ember';
}

export function initTheme(): void {
  applyDocumentSettings();
}

export function toggleTheme(): boolean {
  const next = !isEmber();
  applyDocumentSettings(saveSettings({ theme: next ? 'ember' : 'light' }));
  return next;
}
