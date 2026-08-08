import { useCallback, useEffect, useRef, useState } from 'react';
import type { MutableRefObject } from 'react';
import { ttsPlayer } from '../../lib/audioPlayer';
import { getHttpOrigin, getWsUrl } from '../../lib/config';
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

  /* After each completed reply, look for a resident that was not there at
     the start. The server's create_persona wrote them; the house health
     endpoint lists them; a new name is the handoff. */
  const checkForNewPersona = useCallback(async () => {
    if (handedOffRef.current) return;
    try {
      const resp = await fetch(`${getHttpOrigin()}/health`);
      const body = (await resp.json()) as { personas?: string[] };
      const names = new Set((body.personas ?? []).map(String));
      if (baselineRef.current === null) {
        baselineRef.current = names;
        return;
      }
      for (const name of names) {
        if (!baselineRef.current.has(name)) {
          handedOffRef.current = true;
          newNameRef.current = name;
          setNewName(name);
          setPhase('handoff');
          const ws = wsRef.current;
          ws?.send(JSON.stringify({ action: 'switch_persona', name }));
          /* A beat for the switch to settle, then the first hello. */
          window.setTimeout(() => {
            sendUser(MEET_KICKOFF, { silent: true });
          }, 1200);
          return;
        }
      }
    } catch {
      /* health being briefly unreachable is not a handoff */
    }
  }, [sendUser]);

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
    <div className="mt-2 flex min-h-0 w-full max-w-[680px] flex-1 flex-col items-center">
      <h1 className="text-[24px] font-bold tracking-tight">
        {met ? `Meet ${newName}.` : "Let's make someone."}
      </h1>
      <p className="mt-1.5 max-w-[52ch] text-center text-[14px] leading-relaxed text-fawn">
        {met
          ? 'Made together, just now. The house is theirs too.'
          : 'Sulivan will ask a few things. There are no wrong answers, and your own words always beat his suggestions.'}
      </p>

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

      {met ? (
        <div className="mt-4 pb-4">
          <button
            onClick={onDone}
            className="rounded-full bg-roast px-7 py-3 text-sm font-bold text-cream"
          >
            Go to the house together
          </button>
        </div>
      ) : (
        <form
          className="mt-3 flex w-full gap-2.5 pb-4"
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
            placeholder="Answer in your own words"
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
      )}
    </div>
  );
}
