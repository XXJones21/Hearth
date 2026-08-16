import { useCallback, useEffect, useRef, useState } from 'react';
import type { MutableRefObject } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { ttsPlayer } from '../../lib/audioPlayer';
import { getWsUrl, houseFetch } from '../../lib/config';
import { saveSettings } from '../../lib/settings';
import { useAppStore } from '../../store/appStore';
import { ChoiceCard } from '../cards/ChoiceCard';
import { MessageCard } from '../feed/MessageCard';
import { TimelineEntry } from '../feed/TimelineEntry';
import { INTERVIEW_KICKOFF, type PrefetchedOpener } from './opener';

/* The interview: Sulivan and the user make someone new, then the house hands
   over and the new persona speaks first. The mockup's screens 8 through 13 as
   one conversation rather than five forms; the server's first-run direction
   drives the questions, this screen only carries them.

   Normally this screen adopts the voice test's socket rather than dialing its
   own: the session that holds the greeting and the prefetched opener lives on
   that connection, so the opener Sulivan composed behind the "I heard him"
   button appears here instantly and the answers that follow land in the same
   history. Dialing fresh is the fallback (no prefetch, a dead socket, a
   reconnect), and then the kickoff goes out cold like it always did. */

type Bubble = { who: 'sulivan' | 'you' | 'other'; text: string; name?: string; ts: number };
type Phase = 'waking' | 'thinking' | 'speaking' | 'waiting' | 'handoff' | 'met';

const MEET_KICKOFF =
  '(Say hello to me for the very first time, as yourself. Two or three short ' +
  'sentences, in your own voice.)';

export function Interview({
  onDone,
  opener,
}: {
  onDone: () => void;
  opener?: MutableRefObject<PrefetchedOpener>;
}) {
  const [phase, setPhase] = useState<Phase>('waking');
  const [bubbles, setBubbles] = useState<Bubble[]>([]);
  const [card, setCard] = useState<Record<string, unknown> | null>(null);
  const [draft, setDraft] = useState('');
  const [newName, setNewName] = useState<string | null>(null);
  const wsRef = useRef<WebSocket | null>(null);
  const closedRef = useRef(false);
  const baselineRef = useRef<Set<string> | null>(null);
  const handedOffRef = useRef(false);
  /* The message handler reads this, not the state: the handler is attached
     once and would otherwise close over the null the state started as. */
  const newNameRef = useRef<string | null>(null);

  /* The orb above is the shared particle animation; it thinks and speaks as
     the conversation does, same as everywhere else. */
  useEffect(() => {
    const set = useAppStore.getState().setVisualState;
    set(phase === 'thinking' ? 'thinking' : phase === 'speaking' ? 'speaking' : 'idle');
    return () => set('idle');
  }, [phase]);

  const push = useCallback((b: Bubble) => {
    setBubbles((prev) => [...prev.slice(-30), b]);
  }, []);

  const sendUser = useCallback(
    (text: string, opts: { silent?: boolean } = {}) => {
      const ws = wsRef.current;
      const line = text.trim();
      if (!ws || ws.readyState !== WebSocket.OPEN || !line) return;
      if (!opts.silent) push({ who: 'you', text: line, ts: Date.now() });
      setCard(null);
      setPhase('thinking');
      ws.send(JSON.stringify({ action: 'text_query', text: line }));
    },
    [push],
  );

  /* The handover, from either signal: the server's persona_switched after the
     commit turn (primary), or the health poll below (fallback). Idempotent;
     the guard makes the second arrival a no-op.

     The voice engine loads its named voices at startup, so the persona made
     ten seconds ago has a designed clip the running engine has never heard
     of. The handover therefore bounces the engine (house_reload_voice; the
     monitor respawns it with a fresh persona scan) and gates the first hello
     on /voice/ready coming back, so their first words arrive in THEIR voice.
     Sulivan's farewell already told the person the voice is waking. */
  const beginHandoff = useCallback(
    (name: string) => {
      if (handedOffRef.current || !name) return;
      handedOffRef.current = true;
      newNameRef.current = name;
      setNewName(name);
      setPhase('handoff');
      /* Harmless when the server already switched; the fallback path needs it. */
      wsRef.current?.send(JSON.stringify({ action: 'switch_persona', persona_name: name }));
      void (async () => {
        try {
          await invoke<boolean>('house_reload_voice');
        } catch {
          /* No Tauri (dev browser) or no house: proceed on the old voice
             rather than never speaking. */
        }
        /* A beat for the kill to land, then wait for the engine to answer
           again. Capped: a voice that never wakes must not hold the meeting
           hostage, and the say path degrades to silence, not an error. */
        const deadline = Date.now() + 90_000;
        await new Promise((r) => window.setTimeout(r, 2000));
        while (Date.now() < deadline) {
          try {
            const res = await houseFetch(`/voice/ready`, { cache: 'no-store' });
            const body = (await res.json()) as { ready?: boolean };
            if (body.ready) break;
          } catch {
            /* gateway briefly busy; keep waiting */
          }
          await new Promise((r) => window.setTimeout(r, 1500));
        }
        sendUser(MEET_KICKOFF, { silent: true });
      })();
    },
    [sendUser],
  );

  /* Fallback detection: after each completed reply, look for a resident that
     was not there at the start. The server's create_persona wrote them; the
     house health endpoint lists them; a new name is the handoff. */
  const checkForNewPersona = useCallback(async () => {
    if (handedOffRef.current) return;
    try {
      const resp = await houseFetch(`/health`);
      const body = (await resp.json()) as { personas?: string[] };
      const names = new Set((body.personas ?? []).map(String));
      if (baselineRef.current === null) {
        baselineRef.current = names;
        return;
      }
      for (const name of names) {
        if (!baselineRef.current.has(name)) {
          beginHandoff(name);
          return;
        }
      }
    } catch {
      /* health being briefly unreachable is not a handoff */
    }
  }, [beginHandoff]);

  useEffect(() => {
    closedRef.current = false;
    let retry: number | undefined;
    let playout: number | undefined;

    const onMessage = (ev: MessageEvent) => {
      if (typeof ev.data !== 'string') {
        if (ev.data instanceof ArrayBuffer) {
          ttsPlayer.push(ev.data);
          setPhase((p) => (p === 'thinking' || p === 'handoff' ? 'speaking' : p));
        }
        return;
      }
      try {
        const msg = JSON.parse(ev.data);
        if (msg.action === 'tts_chunk_start') {
          ttsPlayer.begin(Number(msg.sample_rate) || 48000);
        } else if (msg.action === 'ai_response' && typeof msg.text === 'string') {
          if (handedOffRef.current && newNameRef.current) {
            push({ who: 'other', text: msg.text, name: newNameRef.current, ts: Date.now() });
          } else {
            push({ who: 'sulivan', text: msg.text, ts: Date.now() });
          }
        } else if (msg.action === 'ui_component') {
          const comp = msg.component ?? msg;
          if (comp?.type === 'choice_card') setCard(comp.props ?? null);
        } else if (msg.action === 'persona_switched' && typeof msg.persona_name === 'string') {
          /* The server hands the session over at commit; this is the primary
             handoff signal. Sulivan is a switch too (the fallback path echoes
             one) so only a NEW name counts. */
          if (msg.persona_name.toLowerCase() !== 'sulivan') beginHandoff(msg.persona_name);
        } else if (msg.action === 'persona_config' && msg.config) {
          /* The new persona's colour, into the shared accent channel: the
             store's config drives applyPersonaTheme on the root, which the
             avatar nodes and the pill read through var(--persona). */
          const cfg = msg.config as { name?: unknown; visualization?: unknown };
          if (typeof cfg.name === 'string' && cfg.visualization) {
            const s = useAppStore.getState();
            s.setPersonaConfig(msg.config);
            s.setCurrentPersonaName(cfg.name);
            /* The promise in Sulivan's farewell, kept across restarts: the
               made persona is the main one now. The connect flow already
               switches to this pin on every dial, so recording it here is
               the entire persistence mechanism. */
            saveSettings({ startPersona: cfg.name });
          }
        } else if (msg.action === 'speaking_complete') {
          if (handedOffRef.current) {
            setPhase('met');
          } else {
            setPhase('waiting');
            void checkForNewPersona();
          }
        }
      } catch {
        /* not JSON */
      }
    };

    const onClose = () => {
      wsRef.current = null;
      if (closedRef.current) return;
      setPhase('waking');
      retry = window.setTimeout(connect, 3000);
    };

    const connect = () => {
      if (closedRef.current) return;
      const ws = new WebSocket(getWsUrl());
      ws.binaryType = 'arraybuffer';
      wsRef.current = ws;

      ws.addEventListener('open', () => {
        ws.send(
          JSON.stringify({
            action: 'client_info',
            platform: 'desktop',
            capabilities: {
              audio: true,
              spatial: false,
              voice_input: false,
              text_input: true,
              ui_render: true,
            },
            audio_format: { sample_rate: 48000, bit_depth: 16, channels: 1 },
          }),
        );
        void checkForNewPersona(); // seeds the baseline
        window.setTimeout(() => {
          if (!handedOffRef.current) sendUser(INTERVIEW_KICKOFF, { silent: true });
        }, 800);
      });

      ws.addEventListener('message', onMessage);
      ws.addEventListener('close', onClose);
    };

    const o = opener?.current;
    if (o?.ws && o.ws.readyState === WebSocket.OPEN) {
      /* Adoption. Everything here is one synchronous block: the voice test's
         listeners come off and ours go on with no await between them, so a
         reply still streaming cannot drop a frame in the seam. */
      const ws = o.ws;
      o.ws = null;
      o.detach?.();
      o.detach = null;
      wsRef.current = ws;
      ws.addEventListener('message', onMessage);
      ws.addEventListener('close', onClose);

      /* Replay what Sulivan already composed behind the button. */
      if (o.text) push({ who: 'sulivan', text: o.text, ts: Date.now() });
      if (o.card) setCard(o.card);
      const hadAudio = o.audio.length > 0;
      let samples = 0;
      if (hadAudio) {
        ttsPlayer.begin(o.sampleRate);
        for (const b of o.audio) {
          samples += Math.floor(b.byteLength / 4);
          ttsPlayer.push(b);
        }
        o.audio = [];
      }
      void checkForNewPersona(); // seeds the baseline
      if (!o.started || o.failed) {
        /* Prefetch never ran (they pressed the button mid-greeting) or its
           turn errored; ask on the inherited session, where the greeting is
           already history. */
        sendUser(INTERVIEW_KICKOFF, { silent: true });
      } else if (o.complete) {
        /* The opener's speaking_complete was consumed during buffering, so
           when there is audio the switch back to waiting runs on the clock:
           the replayed frames were scheduled gaplessly starting now. */
        if (hadAudio) {
          setPhase('speaking');
          playout = window.setTimeout(
            () => setPhase((p) => (p === 'speaking' ? 'waiting' : p)),
            Math.ceil((samples / o.sampleRate) * 1000),
          );
        } else {
          setPhase('waiting');
        }
      } else {
        /* Still streaming; the live frames arriving through onMessage will
           carry the phase from here. */
        setPhase('thinking');
      }
    } else {
      connect();
    }

    return () => {
      closedRef.current = true;
      if (retry) window.clearTimeout(retry);
      if (playout) window.clearTimeout(playout);
      wsRef.current?.close();
      ttsPlayer.reset();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  /* Chip taps are answers, same as the house Feed. */
  useEffect(() => {
    const onChoice = (e: Event) => {
      const label = (e as CustomEvent<{ label?: string }>).detail?.label;
      if (label) sendUser(label);
    };
    window.addEventListener('hearth-choice', onChoice);
    return () => window.removeEventListener('hearth-choice', onChoice);
  }, [sendUser]);

  const met = phase === 'met' && newName;

  return (
    <div className="mt-2 flex min-h-0 w-full max-w-[740px] flex-1 flex-col items-center">
      <h1 className="text-[24px] font-bold tracking-tight">
        {met ? `Meet ${newName}.` : "Let's make someone."}
      </h1>
      <p className="mt-1.5 max-w-[52ch] text-center text-[14px] leading-relaxed text-fawn">
        {met
          ? 'Made together, just now. The house is theirs too.'
          : 'Sulivan will ask a few things. There are no wrong answers, and your own words always beat his suggestions.'}
      </p>
      {met && (
        /* The sign that the handover is real: they are the one on the wire
           now, voice and all, and the chat below already belongs to them. */
        <div className="mt-2.5 flex items-center gap-2 rounded-full border border-linen bg-glowtint px-3.5 py-1.5 text-[12.5px] font-semibold">
          <span
            className="size-2 animate-pulse rounded-full"
            style={{ background: 'var(--persona, #E39A5B)' }}
          />
          {newName} is here, listening
        </div>
      )}

      {/* The same chat the house renders: the rail, the initial nodes, the
          message cards. Meeting your persona should look like living with
          them, one screen early. */}
      <div className="relative mt-4 min-h-0 w-full flex-1 overflow-y-auto pl-14 pr-1 pt-2 text-left">
        <span
          aria-hidden="true"
          className="pointer-events-none absolute bottom-2 left-[21px] top-2 w-[2px] rounded bg-linen"
        />
        {bubbles.map((b, i) => (
          <TimelineEntry
            key={i}
            author={b.who === 'you' ? 'You' : b.who === 'other' ? (b.name ?? 'Them') : 'Sulivan'}
          >
            <MessageCard
              role={b.who === 'you' ? 'user' : 'assistant'}
              author={b.who === 'you' ? 'You' : b.who === 'other' ? (b.name ?? 'Them') : 'Sulivan'}
              text={b.text}
              ts={b.ts}
            />
          </TimelineEntry>
        ))}
        {card && (
          <TimelineEntry author="Sulivan">
            <ChoiceCard props={card} />
          </TimelineEntry>
        )}
        {phase === 'waking' && (
          <div className="py-2 text-[13px] text-fawn">Waking the house.</div>
        )}
        {phase === 'thinking' && (
          <div className="py-2 text-[13px] text-fawn">
            {handedOffRef.current && newName ? `${newName} is thinking.` : 'Sulivan is thinking.'}
          </div>
        )}
      </div>

      {/* The composer stays through the handover: meeting someone means you
          can talk to them, so the chat keeps working while they are the one
          answering. */}
      <form
        className="mt-3 flex w-full gap-2.5"
        onSubmit={(e) => {
          e.preventDefault();
          sendUser(draft);
          setDraft('');
        }}
      >
        <textarea
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault();
              sendUser(draft);
              setDraft('');
            }
          }}
          rows={1}
          placeholder={met ? `Talk to ${newName}` : 'Answer in your own words'}
          disabled={phase === 'waking' || phase === 'thinking'}
          className="max-h-[140px] min-h-[46px] flex-1 resize-none rounded-3xl border border-linen bg-parchment px-4 py-3 text-sm text-roast outline-none placeholder:text-fawn focus:border-fennec/50 disabled:opacity-60"
        />
        <button
          type="submit"
          disabled={phase === 'waking' || phase === 'thinking' || !draft.trim()}
          className="shrink-0 self-end rounded-full bg-roast px-5 py-3 text-sm font-bold text-cream disabled:opacity-30"
        >
          Send
        </button>
      </form>
      {met ? (
        /* The next beat of setup (mockup screens 14 through 16): the second
           brain, where the new persona gets a memory of their own. The flow
           behind this button is the next cut; today it opens the house. */
        <div className="mb-4 mt-3">
          <button
            onClick={onDone}
            className="rounded-full bg-roast px-7 py-3 text-sm font-bold text-cream"
          >
            Second brain setup
          </button>
        </div>
      ) : (
        <div className="pb-4" />
      )}
    </div>
  );
}
