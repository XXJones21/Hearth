/* The hardware scan, the plan, and the download.
 *
 * Every decision lives in the hearth-probe Rust crate, so the client, the CLI
 * and the installation skill all give the same answers. This file is types and
 * invoke calls, nothing more. */

import { Channel, invoke } from '@tauri-apps/api/core';

export type Gpu = {
  vendor: string;
  name: string;
  vram_bytes: number | null;
  compute_cap: string | null;
  driver: string | null;
  backend: string;
};

export type Machine = {
  os: string;
  arch: string;
  cpu_cores: number;
  ram_bytes: number;
  free_disk_bytes: number;
  gpu: Gpu | null;
  unified_memory: boolean;
  wsl_present: boolean | null;
  simulated?: string;
};

export type PlanDownload = {
  what: string;
  repo: string;
  file: string | null;
  bytes: number;
  url: string | null;
  sha256: string | null;
};

export type Plan = {
  tier: number;
  label: string;
  model: string;
  repo: string;
  file: string;
  quant: string;
  note: string;
  /** False when the brain and the voice have to take turns. */
  coexist: boolean;
  backend: string;
  n_ctx: number;
  n_gpu_layers: number;
  cuda_arch: string | null;
  downloads: PlanDownload[];
  total_download_bytes: number;
  disk_required_bytes: number;
  memory_pool_bytes: number;
  budget_bytes: number;
  /** Why each decision was made. Rendered, never paraphrased. */
  reasons: string[];
  warnings: string[];
};

export type Progress = {
  what: string;
  doneBytes: number;
  totalBytes: number;
  state: 'downloading' | 'verifying' | 'done' | 'skipped' | 'failed';
  message?: string;
};

/** Only meaningful inside the packaged app; the browser dev server has no Tauri. */
export const hasProbe = () =>
  typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

export const scan = (simulate?: string) =>
  invoke<Machine>('probe_scan', { simulate: simulate ?? null });

/** `dest` re-anchors the free-disk figure to the chosen destination volume.
 *  Ignored for fixtures, whose recorded disk numbers are the point. */
export const makePlan = (simulate?: string, dest?: string) =>
  invoke<Plan>('probe_plan', { simulate: simulate ?? null, dest: dest ?? null });

export const fixtures = () => invoke<string[]>('probe_fixtures');

export const modelDir = () => invoke<string>('probe_model_dir');

/** The default install root: the one folder everything lives under. */
export const installRoot = () => invoke<string>('probe_install_root');

/** This machine's name, offered as the name it pairs under. */
export const deviceName = () => invoke<string>('probe_device_name');

export type InstallState = {
  ok: boolean;
  recordExists: boolean;
  missing: string[];
};

/** Validate an install against its record on disk. The record is the truth;
 *  the settings flag is only a cache of it. */
export const installState = (root?: string) =>
  invoke<InstallState>('probe_install_state', { root: root ?? null });

/** Free bytes on the volume containing `path`. */
export const freeDisk = (path: string) => invoke<number>('probe_free_disk', { path });

export function download(
  onProgress: (p: Progress) => void,
  opts: { simulate?: string; dest?: string } = {},
) {
  const channel = new Channel<Progress>();
  channel.onmessage = onProgress;
  return invoke<string[]>('probe_download', {
    simulate: opts.simulate ?? null,
    dest: opts.dest ?? null,
    onProgress: channel,
  });
}

/** The rows for the placed runtime, run in parallel chains alongside the
 *  model download: backend and engine immediately, then once Python lands,
 *  the voice model fetch and the voice engine's environment side by side. */
export const PROVISION_ROWS = [
  'The backend',
  'Inference engine',
  'Python runtime',
  'Voice model',
  'Voice engine',
] as const;

/** Bar weights per provisioning row, in rough megabytes of work: downloads
 *  at face value, pip resolves at their observed cost. Model rows weigh
 *  their real bytes; these calibrate everything else against them so the
 *  one number over the rows reflects all of the work, not just the models.
 *  Pacing heuristics for the bar only; no correctness rides on them. */
export const PROVISION_WEIGHTS: Record<(typeof PROVISION_ROWS)[number], number> = {
  'The backend': 60,
  'Inference engine': 650,
  'Python runtime': 600,
  'Voice model': 3100,
  'Voice engine': 3900,
};

export function provision(
  onProgress: (p: Progress) => void,
  opts: { root: string; accel: string },
) {
  const channel = new Channel<Progress>();
  channel.onmessage = onProgress;
  return invoke<void>('provision', {
    root: opts.root,
    accel: opts.accel,
    onProgress: channel,
  });
}

/** GB as a person reads them, matching the Rust side. */
export function human(bytes: number): string {
  const GIB = 1073741824;
  const MIB = 1048576;
  return bytes >= GIB
    ? `${(bytes / GIB).toFixed(2)} GB`
    : `${Math.round(bytes / MIB)} MB`;
}
