import { useCallback, useEffect, useRef } from 'react';
import { ttsPlayer } from '../lib/audioPlayer';
import { getHttpOrigin, getWsUrl } from '../lib/config';
import { loadSettings } from '../lib/settings';
import { useAppStore } from '../store/appStore';
import type { PersonaConfig } from '../types/persona';

function parseConfig(raw: unknown): PersonaConfig | null {
  if (!raw || typeof raw !== 'object') return null;
  const o = raw as Record<string, unknown>;
  if (typeof o.name !== 'string' || !o.visualization) return null;
  return raw as PersonaConfig;
}

function personaConfigUrl(personaName: string): string {
  const entry = useAppStore
    .getState()
    .personas.find((p) => p.name.toLowerCase() === personaName.toLowerCase());
  if (import.meta.env.DEV) {
    return `/Persona/${entry?.name || personaName}/${personaName.toLowerCase()}.json`;
  }
  return (
    entry?.config_url ||
    `${getHttpOrigin()}/Persona/${personaName}/${personaName.toLowerCase()}.json`
  );
}

function runtimeStatusFor(event: string): string | null {
  switch (event) {
    case 'start':
      return 'Preparing request';
    case 'session_created':
      return 'Starting session';
    case 'session_reused':
      return 'Continuing session';
    case 'part_reasoning':
    case 'reasoning':
      return 'Reasoning';
    case 'part_tool':
    case 'tool':
      return 'Using tools';
    case 'step_finish':
    case 'part_step_finish':
      return 'Finalizing';
    default:
      if (event.includes('delta')) return 'Writing response';
      return null;
  }
}

async function fetchPersonaConfig(personaName: string) {
  try {
    const res = await fetch(personaConfigUrl(personaName), { cache: 'no-store' });
    if (!res.ok) return;
    const cfg = parseConfig(await res.json());
    if (!cfg) return;
    const s = useAppStore.getState();
    if (s.currentPersonaName?.toLowerCase() === personaName.toLowerCase()) {
      s.setPersonaConfig(cfg);
    }
  } catch {
    // The WebSocket get_persona_config path remains the authoritative fallback.
  }
}

/* The sentence the next audio frame belongs to. tts_chunk_start announces a
   segment and its text before any of it is audible, and ai_response does not
   arrive until the whole reply is generated -- so without this the screen sits
   empty while he speaks, and the words all land at once at the end. Held at
   module scope because the frames arrive outside routeMessage. */
let pendingSpokenText: string | null = null;

/** Show the sentence now being heard. Called from the binary frame handler. */
export function flushSpokenText() {
  if (!pendingSpokenText) return;
  const said = pendingSpokenText;
  pendingSpokenText = null;
  const s = useAppStore.getState();
  // appendAssistantDraft concatenates verbatim, and these are whole sentences
  // arriving one at a time, so the space between them belongs here.
  s.appendAssistantDraft(s.activeAssistantDraft ? ` ${said}` : said);
}

function routeMessage(raw: string, send: (o: Record<string, unknown>) => void) {
  let data: Record<string, unknown>;
  try {
    data = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return;
  }
  const action = data.action as string | undefined;
  if (!action) return;

  const s = useAppStore.getState();

  switch (action) {
    case 'client_info_ack': {
      s.setConnectionEvent(true);
      send({ action: 'list_personas' });
      break;
    }
    case 'personas_list': {
      // Protocol tolerance: the Rust-era server sent persona OBJECTS; Valar
      // (the live gateway) sends plain NAME strings. Normalize both shapes so
      // every consumer sees {name, description?, ...}. (Live 2026-07-20: raw
      // strings crashed PersonaSwitcher's p.name.toLowerCase() and blanked
      // the whole app -- no root error boundary.)
      const raw = (data.personas as Array<unknown>) || [];
      const list = raw
        .map((p) =>
          typeof p === 'string'
            ? { name: p, config_url: '' }
            : (p as {
                name: string;
                description?: string;
                version?: string;
                visualization_type?: string;
                config_url: string;
              }),
        )
        .filter((p) => p && typeof p.name === 'string');
      const current = (data.current_persona as string) || null;
      s.setPersonas(list, current);
      s.setConnection('ready', null);
      if (current) {
        s.setCurrentPersonaName(current);
        send({ action: 'get_persona_config', persona_name: current });
      }
      // Settings > Personas > "start with": ask the house for our preferred
      // persona once per connect. Only when it differs and actually exists,
      // so a stale pin cannot strand the client on a persona the house
      // no longer serves.
      const pin = loadSettings().startPersona;
      if (
        pin &&
        pin.toLowerCase() !== (current || '').toLowerCase() &&
        list.some((p) => p.name.toLowerCase() === pin.toLowerCase())
      ) {
        send({ action: 'switch_persona', persona_name: pin });
      }
      break;
    }
    case 'persona_config': {
      const cfg = parseConfig(data.config);
      if (cfg) {
        s.setPersonaConfig(cfg);
        s.setCurrentPersonaName(
          (data.persona_name as string) || cfg.name
        );
      }
      break;
    }
    case 'persona_switched': {
      const name = data.persona_name as string;
      if (name) {
        s.setCurrentPersonaName(name);
        s.clearAgentEvents();
        send({ action: 'get_persona_config', persona_name: name });
        send({ action: 'list_personas' });
      }
      break;
    }
    case 'ai_response': {
      const text = String((data as { text?: string }).text || '');
      const personaName = String((data as { persona_name?: string }).persona_name || '');
      // The authoritative text replaces whatever the segments accumulated,
      // which also repairs a sentence whose audio never arrived.
      pendingSpokenText = null;
      s.clearAssistantDraft();
      s.pushMessage({ role: 'assistant', text, personaName });
      s.setWaitingForResponse(false);
      s.setRuntimeStatus(null);
      s.setActiveTools([]);
      s.setVisualState('idle');
      break;
    }
    case 'pipeline_stage': {
      const stage = String(data.stage || '');
      const event = String(data.event || '');
      if (stage === 'tools') {
        s.setActiveTools(
          Array.isArray((data as { tools?: unknown }).tools)
            ? ((data as { tools: unknown[] }).tools as string[]).map(String)
            : [],
        );
        break;
      }
      const ts = String(data.timestamp || new Date().toISOString());
      const { action: _a, stage: _s, event: _e, timestamp: _t, ...rest } = data;
      const friendlyStatus = runtimeStatusFor(event);
      if (friendlyStatus) {
        s.setRuntimeStatus(friendlyStatus);
      }
      s.pushAgentEvent({ stage, event, timestamp: ts, payload: rest });
      if (event === 'complete' || event === 'error') {
        s.setVisualState('idle');
      } else {
        s.setVisualState('thinking');
      }
      break;
    }
    case 'state_update': {
      s.setServerState({ state: String(data.state), stage: String(data.stage) });
      break;
    }
    case 'ui_component': {
      const { action: _ignored, ...op } = data;
      s.applyUiComponentOp(op as import('../store/appStore').UiComponentOp);
      break;
    }
    case 'tts_chunk_start': {
      ttsPlayer.begin(Number((data as { sample_rate?: number }).sample_rate));
      const seg = String((data as { text?: string }).text || '').trim();
      if (seg) pendingSpokenText = seg;
      s.setVisualState('speaking');
      break;
    }
    case 'tts_chunk_end':
      break;
    case 'tts_error': {
      s.pushAgentEvent({
        stage: 'tts',
        event: 'tts_error',
        timestamp: new Date().toISOString(),
        payload: { message: (data as { message?: string }).message },
      });
      break;
    }
    case 'speaking_complete': {
      s.setVisualState('idle');
      break;
    }
    case 'session_ended': {
      // Idle watchdog or an explicit new_session: wipe the transcript and
      // cards so the next turn has a clean frame. Server already cleared its
      // history; without this the feed kept prior turns after New session.
      // resume_session also emits this first, then session_resumed repaints.
      pendingSpokenText = null;
      ttsPlayer.reset();
      s.resetMessages();
      s.clearAgentEvents();
      s.clearAssistantDraft();
      s.setWaitingForResponse(false);
      s.setRuntimeStatus('New session');
      s.setActiveTools([]);
      s.setVisualState('idle');
      s.setServerState({ state: 'idle', stage: String(data.reason || 'ended') });
      s.setLiveTopic(null);
      s.bumpSessionsTick();
      break;
    }
    case 'session_resumed': {
      // After session_ended wipe: rehydrate feed from the Journal chatlog the
      // house just seeded into session.history.
      const turns = Array.isArray(
        (data as { turns?: Array<{ user?: string; assistant?: string }> }).turns
      )
        ? (data as { turns: Array<{ user?: string; assistant?: string }> }).turns
        : [];
      const msgs: Array<{ role: 'user' | 'assistant'; text: string }> = [];
      for (const t of turns) {
        const user = String(t.user || '').trim();
        const assistant = String(t.assistant || '').trim();
        if (user) msgs.push({ role: 'user', text: user });
        if (assistant) msgs.push({ role: 'assistant', text: assistant });
      }
      s.replaceMessages(msgs);
      s.setRuntimeStatus('Resumed session');
      s.setServerState({ state: 'idle', stage: 'resumed' });
      s.setVisualState('idle');
      break;
    }
    case 'topic_session': {
      // A fresh chat that already knows what it is about: the house opened it
      // with an Engram topic hint, so recall reads that project or life root
      // first. Not a resume; there is no transcript to rehydrate.
      const name = String((data as { name?: string }).name || '').trim();
      s.setLiveTopic(name || null);
      s.setRuntimeStatus(name ? `Session for ${name}` : 'New session');
      s.setServerState({ state: 'idle', stage: 'topic' });
      s.setVisualState('idle');
      break;
    }
    case 'execute_artifacts': {
      s.pushMessage({
        role: 'assistant',
        text: `execute_artifacts: ${JSON.stringify(
          (data as { code_artifacts?: unknown }).code_artifacts
        )}`,
      });
      break;
    }
    case 'error': {
      s.setConnection(
        'error',
        String((data as { message?: string }).message || 'error')
      );
      s.setWaitingForResponse(false);
      s.setRuntimeStatus(null);
      s.clearAssistantDraft();
      break;
    }
    case 'pong': {
      s.setBackendStatus({
        llamaReady: Boolean(data.llama_ready),
        activeModel: typeof data.active_model === 'string' ? data.active_model : undefined,
        activePersona: typeof data.current_persona === 'string' ? data.current_persona : undefined,
      });
      break;
    }
    default:
      break;
  }
}

/** `enabled` is false during first-run setup: there is no backend yet, and a
    client that dials the usual port before setup would silently adopt whatever
    is already running on the machine. */
export function useHearthWebSocket(enabled = true) {
  const wsRef = useRef<WebSocket | null>(null);
  const intentionalClose = useRef(false);
  const reconnectRef = useRef(0);
  const pingIntervalRef = useRef<number | null>(null);
  const connectionEvent = useAppStore((s) => s.connectionEvent);
  const setConnection = useAppStore((s) => s.setConnection);
  const setConnectionAttempt = useAppStore((s) => s.setConnectionAttempt);
  const isWaitingForResponse = useAppStore((s) => s.isWaitingForResponse);
  const clearAgentEvents = useAppStore((s) => s.clearAgentEvents);
  const setVisualState = useAppStore((s) => s.setVisualState);
  const setWaitingForResponse = useAppStore((s) => s.setWaitingForResponse);
  const setRuntimeStatus = useAppStore((s) => s.setRuntimeStatus);
  const clearAssistantDraft = useAppStore((s) => s.clearAssistantDraft);
  const pushMessage = useAppStore((s) => s.pushMessage);

  const connect = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) return;
    intentionalClose.current = false;
    setConnection('connecting', null);
    const socket = new WebSocket(getWsUrl());
    socket.binaryType = 'arraybuffer';
    wsRef.current = socket;

    const send = (obj: Record<string, unknown>) => {
      if (socket.readyState === WebSocket.OPEN) {
        socket.send(JSON.stringify(obj));
      }
    };

    const stopPing = () => {
      if (pingIntervalRef.current !== null) {
        window.clearInterval(pingIntervalRef.current);
        pingIntervalRef.current = null;
      }
    };

    socket.addEventListener('open', () => {
      reconnectRef.current = 0;
      stopPing();
      send({
        action: 'client_info',
        platform: 'desktop',
        capabilities: {
          audio: true,
          spatial: false,
          voice_input: false,
          text_input: true,
          ui_render: true,
        },
        audio_format: {
          sample_rate: 48000,
          bit_depth: 16,
          channels: 1,
        },
      });
      send({ action: 'ping' });
      pingIntervalRef.current = window.setInterval(() => {
        send({ action: 'ping' });
      }, 5000);
    });

    socket.addEventListener('message', (ev) => {
      if (typeof ev.data === 'string') {
        routeMessage(ev.data, send);
      } else if (ev.data instanceof ArrayBuffer) {
        ttsPlayer.push(ev.data);
        flushSpokenText();
      }
    });

    socket.addEventListener('close', () => {
      stopPing();
      wsRef.current = null;
      ttsPlayer.reset();
      if (intentionalClose.current) return;
      setConnectionAttempt(reconnectRef.current);
      setConnection('disconnected', 'connection closed');
      setWaitingForResponse(false);
      setRuntimeStatus(null);
      clearAssistantDraft();
      // Settings > Connection: someone debugging a server can stop the client
      // from dialing back every second.
      if (!loadSettings().autoReconnect) return;
      const baseDelay = 1000;
      const maxDelay = 10000;
      const jitter = 0.5 + Math.random() * 0.5;
      const t = Math.min(maxDelay, baseDelay * Math.pow(2, reconnectRef.current) * jitter);
      reconnectRef.current += 1;
      window.setTimeout(() => {
        if (!intentionalClose.current) {
          connect();
        }
      }, t);
    });

    socket.addEventListener('error', () => {
      setConnection('error', 'WebSocket error');
      setWaitingForResponse(false);
      setRuntimeStatus(null);
      clearAssistantDraft();
    });
  }, [clearAssistantDraft, setConnection, setRuntimeStatus, setWaitingForResponse]);

  const disconnect = useCallback(() => {
    intentionalClose.current = true;
    if (pingIntervalRef.current !== null) {
      window.clearInterval(pingIntervalRef.current);
      pingIntervalRef.current = null;
    }
    wsRef.current?.close();
    wsRef.current = null;
    setWaitingForResponse(false);
    setRuntimeStatus(null);
    clearAssistantDraft();
    setConnection('disconnected', null);
  }, [clearAssistantDraft, setConnection, setRuntimeStatus, setWaitingForResponse]);

  const sendTextQuery = useCallback(
    (text: string) => {
      const trimmed = text.trim();
      if (!trimmed) return;
      if (useAppStore.getState().isWaitingForResponse) return;
      setVisualState('thinking');
      setWaitingForResponse(true);
      setRuntimeStatus('Sending');
      clearAssistantDraft();
      clearAgentEvents();
      pushMessage({ role: 'user', text: trimmed });
      if (wsRef.current?.readyState === WebSocket.OPEN) {
        wsRef.current.send(
          JSON.stringify({ action: 'text_query', text: trimmed })
        );
      }
    },
    [clearAgentEvents, clearAssistantDraft, pushMessage, setRuntimeStatus, setVisualState, setWaitingForResponse]
  );

  const switchPersona = useCallback((personaName: string) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      useAppStore.getState().setCurrentPersonaName(personaName);
      useAppStore.getState().clearAgentEvents();
      void fetchPersonaConfig(personaName);
      wsRef.current.send(
        JSON.stringify({ action: 'switch_persona', persona_name: personaName })
      );
      wsRef.current.send(
        JSON.stringify({
          action: 'get_persona_config',
          persona_name: personaName,
        })
      );
    }
  }, []);

  const startNewSession = useCallback(() => {
    if (wsRef.current?.readyState !== WebSocket.OPEN) return;
    if (useAppStore.getState().isWaitingForResponse) return;
    setRuntimeStatus('Starting new session');
    wsRef.current.send(JSON.stringify({ action: 'new_session' }));
  }, [setRuntimeStatus]);

  const resumeSession = useCallback(
    (id: string, kind: 'record' | 'journal' = 'journal') => {
      const trimmed = id.trim();
      if (!trimmed) return;
      if (wsRef.current?.readyState !== WebSocket.OPEN) return;
      if (useAppStore.getState().isWaitingForResponse) return;
      setRuntimeStatus('Resuming session');
      // A record is resumed by its own id; a journal entry by its diary slug.
      // Same action, because to the operator it is the same button.
      wsRef.current.send(
        JSON.stringify(
          kind === 'record'
            ? { action: 'resume_session', session_id: trimmed }
            : { action: 'resume_session', slug: trimmed }
        )
      );
    },
    [setRuntimeStatus]
  );

  const startTopicSession = useCallback(
    (name: string) => {
      const trimmed = name.trim();
      if (!trimmed) return;
      if (wsRef.current?.readyState !== WebSocket.OPEN) return;
      if (useAppStore.getState().isWaitingForResponse) return;
      setRuntimeStatus(`Starting session for ${trimmed}`);
      wsRef.current.send(
        JSON.stringify({ action: 'start_topic_session', name: trimmed })
      );
    },
    [setRuntimeStatus]
  );

  useEffect(() => {
    if (!enabled) return;
    connect();
    return () => {
      intentionalClose.current = true;
      if (pingIntervalRef.current !== null) {
        window.clearInterval(pingIntervalRef.current);
        pingIntervalRef.current = null;
      }
      wsRef.current?.close();
      wsRef.current = null;
    };
  }, [connect, enabled]);

  return {
    sendTextQuery,
    switchPersona,
    startNewSession,
    resumeSession,
    startTopicSession,
    reconnect: connect,
    disconnect,
    connectionEvent,
    isWaitingForResponse,
  };
}
