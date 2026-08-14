import { create } from 'zustand';
import type { ListPersonaEntry, PersonaConfig } from '../types/persona';

export type ChatMessage = {
  id: string;
  role: 'user' | 'assistant';
  text: string;
  ts: number;
  personaName?: string;
};

export type VisualizerState = 'idle' | 'thinking' | 'speaking' | 'listening';

export type AgentActivityEvent = {
  id: string;
  stage: string;
  event: string;
  timestamp: string;
  payload: Record<string, unknown>;
};

export type VisualizationError = {
  assetUrl: string;
  message: string;
  timestamp: string;
};

type Conn = 'disconnected' | 'connecting' | 'ready' | 'error';

/** A live ui_component card (wire op: {op?, version, type, props, ttl_s?}). */
export type UiCard = {
  /** unique per instance -- the timeline is a transcript, so repeated
      upserts of one type are SEPARATE entries, not replacements */
  id: string;
  cardType: string;
  props: Record<string, unknown>;
  ts: number;
  /** epoch ms after which the card is dropped; null = no expiry */
  expiresAt: number | null;
};

export type UiComponentOp = {
  op?: 'upsert' | 'clear' | 'clear_all' | string;
  version?: number;
  type?: string;
  props?: Record<string, unknown>;
  ttl_s?: number;
};

type BackendStatus = {
  llamaReady?: boolean;
  activeModel?: string;
  activePersona?: string;
};

type AppState = {
  connection: Conn;
  lastError: string | null;
  isWaitingForResponse: boolean;
  runtimeStatus: string | null;
  serverState: { state: string; stage: string } | null;
  visualizationError: VisualizationError | null;
  connectionAttempt: number;
  setServerState: (v: { state: string; stage: string } | null) => void;
  setVisualizationError: (e: VisualizationError | null) => void;
  setConnectionAttempt: (n: number) => void;
  activeAssistantDraft: string;
  currentPersonaName: string | null;
  backendStatus: BackendStatus;
  personas: ListPersonaEntry[];
  personaConfig: PersonaConfig | null;
  messages: ChatMessage[];
  visualState: VisualizerState;
  inputFocused: boolean;
  agentEvents: AgentActivityEvent[];
  connectionEvent: boolean;
  /** which surface the center panel shows (icon-row navigation) */
  activeView: 'home' | 'journal' | 'personas' | 'settings' | 'apps';
  setActiveView: (v: 'home' | 'journal' | 'personas' | 'settings' | 'apps') => void;
  /** tools currently executing this turn (status bar), [] when none */
  activeTools: string[];
  setActiveTools: (t: string[]) => void;
  /** live ui_component cards, keyed by type (one card per type, Echo pattern) */
  uiCards: UiCard[];
  applyUiComponentOp: (op: UiComponentOp) => void;
  setConnection: (c: Conn, err?: string | null) => void;
  setConnectionEvent: (v: boolean) => void;
  setWaitingForResponse: (v: boolean) => void;
  setRuntimeStatus: (v: string | null) => void;
  setBackendStatus: (v: BackendStatus) => void;
  setAssistantDraft: (text: string) => void;
  appendAssistantDraft: (text: string) => void;
  clearAssistantDraft: () => void;
  setPersonas: (p: ListPersonaEntry[], current: string | null) => void;
  setPersonaConfig: (c: PersonaConfig | null) => void;
  setCurrentPersonaName: (n: string) => void;
  pushMessage: (m: Omit<ChatMessage, 'id' | 'ts'>) => void;
  /** drop the in-memory transcript (Settings > clear history) */
  resetMessages: () => void;
  /** replace the feed (resume_session rehydrate) */
  replaceMessages: (msgs: Omit<ChatMessage, 'id' | 'ts'>[]) => void;
  /** bump when a session ends so the Sessions rail reloads diaries */
  sessionsTick: number;
  bumpSessionsTick: () => void;
  /** Engram topic for the live chat (project or life-root name), or null */
  liveTopic: string | null;
  setLiveTopic: (n: string | null) => void;
  setVisualState: (v: VisualizerState) => void;
  setInputFocused: (f: boolean) => void;
  clearAgentEvents: () => void;
  pushAgentEvent: (e: {
    stage: string;
    event: string;
    timestamp: string;
    payload: Record<string, unknown>;
  }) => void;
  pushVisualizationError: (err: { assetUrl: string; message: string }) => void;
};

const MAX_AGENT = 400;

function rid() {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
}

/** Save messages + persona key to localStorage */
function persistMessages(messages: ChatMessage[], persona: string | null) {
  if (typeof localStorage === 'undefined') return;
  try {
    const key = `hearth_msgs_${persona || '__default__'}`;
    localStorage.setItem(key, JSON.stringify(messages));
  } catch {
    // quota exceeded or unavailable — silent no-op
  }
}

/** Restore messages for the given persona from localStorage */
function restoreMessages(persona: string | null): ChatMessage[] {
  if (typeof localStorage === 'undefined') return [];
  try {
    const key = `hearth_msgs_${persona || '__default__'}`;
    const raw = localStorage.getItem(key);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) return parsed as ChatMessage[];
    return [];
  } catch {
    return [];
  }
}


export const useAppStore = create<AppState>((set) => ({
  connection: 'disconnected',
  lastError: null,
  isWaitingForResponse: false,
  runtimeStatus: null,
  activeAssistantDraft: '',
  backendStatus: {},
  personas: [],
  currentPersonaName: null,
  personaConfig: null,
  messages: restoreMessages(null),
  visualState: 'idle',
  inputFocused: false,
  activeView: 'home' as const,
  activeTools: [],
  serverState: null,
  visualizationError: null,
  connectionAttempt: 0,
  agentEvents: [],
  connectionEvent: false,
  uiCards: [],
  sessionsTick: 0,
  liveTopic: null,
  setLiveTopic: (n) => set({ liveTopic: n }),
  applyUiComponentOp: (op) =>
    set((s) => {
      const now = Date.now();
      const alive = s.uiCards.filter((c) => c.expiresAt === null || c.expiresAt > now);
      if (op.op === 'clear_all') return { uiCards: [] };
      if (op.op === 'clear') {
        return { uiCards: alive.filter((c) => c.cardType !== op.type) };
      }
      // upsert (the default when op is absent). Historical instances stay in
      // the transcript (live 2026-07-31: replacing by type made the earlier
      // card vanish and "move down" the feed); cap total to bound memory.
      if ((op.version ?? 1) !== 1 || !op.type) return { uiCards: alive };
      const card: UiCard = {
        id: `${op.type}-${now}-${Math.random().toString(36).slice(2, 7)}`,
        cardType: op.type,
        props: op.props ?? {},
        ts: now,
        expiresAt: op.ttl_s ? now + op.ttl_s * 1000 : null,
      };
      return { uiCards: [...alive, card].slice(-40) };
    }),
  setServerState: (v) => set({ serverState: v }),
  setConnection: (c, err = null) =>
    set({ connection: c, lastError: err ?? null }),
  setConnectionEvent: (v) => set({ connectionEvent: v }),
  setWaitingForResponse: (v) => set({ isWaitingForResponse: v }),
  setRuntimeStatus: (v) => set({ runtimeStatus: v }),
  setBackendStatus: (v) =>
    set((s) => ({ backendStatus: { ...s.backendStatus, ...v } })),
  setAssistantDraft: (text) => set({ activeAssistantDraft: text }),
  appendAssistantDraft: (text) =>
    set((s) => ({ activeAssistantDraft: `${s.activeAssistantDraft}${text}` })),
  clearAssistantDraft: () => set({ activeAssistantDraft: '' }),
  setPersonas: (p, current) =>
    set({ personas: p, currentPersonaName: current ?? null }),
  setPersonaConfig: (c) => set({ personaConfig: c }),
  setCurrentPersonaName: (n) =>
    set((s) => {
      // Same persona = nothing to swap. Without this guard the boot sequence
      // (personas_list then persona_config, both naming the current persona)
      // clears the transcript it just restored, so every reconnect silently
      // wiped the active persona's history. Found 2026-08-03 while wiring
      // Settings > clear history.
      if (s.currentPersonaName && s.currentPersonaName === n) return {};
      // Switching swaps the in-memory transcript. It does NOT delete the old
      // persona's stored one -- that is what makes per-persona history real,
      // and it is now Settings > Conversation history that removes it.
      const restored = restoreMessages(n);
      return { currentPersonaName: n, messages: restored };
    }),
  pushMessage: (m) =>
    set((s) => {
      const newMsg: ChatMessage = { ...m, id: rid(), ts: Date.now() };
      const next = [...s.messages, newMsg];
      persistMessages(next, s.currentPersonaName);
      return { messages: next };
    }),
  resetMessages: () =>
    set((s) => {
      persistMessages([], s.currentPersonaName);
      return { messages: [], activeAssistantDraft: '', uiCards: [], activeTools: [] };
    }),
  replaceMessages: (msgs) =>
    set((s) => {
      const base = Date.now();
      const next: ChatMessage[] = msgs.map((m, i) => ({
        ...m,
        id: rid(),
        ts: base + i,
      }));
      persistMessages(next, s.currentPersonaName);
      return {
        messages: next,
        activeAssistantDraft: '',
        uiCards: [],
        activeTools: [],
      };
    }),
  bumpSessionsTick: () => set((s) => ({ sessionsTick: s.sessionsTick + 1 })),
  setVisualState: (v) => set({ visualState: v }),
  setInputFocused: (f) => set({ inputFocused: f }),
  setActiveView: (v) => set({ activeView: v }),
  setActiveTools: (t) => set({ activeTools: t }),
  clearAgentEvents: () => set({ agentEvents: [] }),
  pushAgentEvent: (e) =>
    set((s) => {
      const next: AgentActivityEvent = {
        id: rid(),
        stage: e.stage,
        event: e.event,
        timestamp: e.timestamp,
        payload: e.payload,
      };
      const merged = [...s.agentEvents, next];
      if (merged.length > MAX_AGENT) {
        return { agentEvents: merged.slice(-MAX_AGENT) };
      }
      return { agentEvents: merged };
    }),
  setVisualizationError: (e) => set({ visualizationError: e }),
  setConnectionAttempt: (n) => set({ connectionAttempt: n }),
  pushVisualizationError: (err: { assetUrl: string; message: string }) => {
    const msg = err.message || 'Visualization failed';
    return set((s) => {
      const payload: Record<string, unknown> = {
        assetUrl: err.assetUrl,
        error: msg,
        timestamp: new Date().toISOString(),
      };
      const next: AgentActivityEvent = {
        id: rid(),
        stage: 'visualization',
        event: 'asset_failed',
        timestamp: payload.timestamp as string,
        payload,
      };
      const merged = [...s.agentEvents, next];
      if (merged.length > MAX_AGENT) return { agentEvents: merged.slice(-MAX_AGENT) };
      return { agentEvents: merged };
    });
  },
}));

export function mapVisualizerState(
  v: VisualizerState,
  inputFocused: boolean
): VisualizerState {
  if (inputFocused) return 'listening';
  return v;
}
