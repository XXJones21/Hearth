/* The house: the backend process tree the Tauri side supervises. This file
 * is types and invoke calls, nothing more, same rule as probe.ts. */

import { invoke } from '@tauri-apps/api/core';

export type ProcStatus = {
  name: string;
  state: 'starting' | 'running' | 'restarting' | 'stopped' | 'failed' | '';
  pid: number | null;
  restarts: number;
  detail: string;
};

export type HouseStatus = {
  running: boolean;
  root: string;
  processes: ProcStatus[];
};

export const houseStart = (root: string) => invoke<void>('house_start', { root });

export const houseStop = () => invoke<void>('house_stop');

export const houseStatus = () => invoke<HouseStatus>('house_status');
