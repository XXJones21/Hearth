import { useCallback, useEffect, useRef, useState } from 'react';
import { ttsPlayer } from '../../lib/audioPlayer';
import { getHttpOrigin, getWsUrl } from '../../lib/config';
import { useAppStore } from '../../store/appStore';
import { ChoiceCard } from '../cards/ChoiceCard';

/* The interview: Sulivan and the user make someone new, then the house hands
   over and the new persona speaks first. The mockup's screens 8 through 13 as
   one conversation rather than five forms; the server's first-run direction
   drives the questions, this screen only carries them.

   Owns its WebSocket like the voice test does: setup is still in charge, and
   the house it talks to is the one setup started. */

type Bubble = { who: 'sulivan' | 'you' | 'other'; text: string; name?: string };
type Phase = 'waking' | 'thinking' | 'speaking' | 'waiting' | 'handoff' | 'met';

const KICKOFF =
  '(This is my first run. Begin as your direction describes: greet me in one ' +
  'short sentence and ask your first question.)';

const MEET_KICKOFF =
  '(Say hello to me for the very first time, as yourself. Two or three short ' +
  'sentences, in your own voice.)';

export function Interview({ onDone }: { onDone: () => void }) {
  const [phase, setPhase] = useState<Phase>('waking');
  const [bubbles, setBubbles] = useState<Bubble[]>([]);
  const [card, setCard] = useState<Record<string, unknown> | null>(null);
  const [draft, setDraft] = useState('');
  const [newName, setNewName] = useState<string | null>(null);
  const wsRef = useRef<WebSocket | null>(null);
  const closedRef = useRef(false);
  const baselineRef = useRef<Set<string> | null>(null);
  const handedOffRef = useRef(false);

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
      if (!opts.silent) push({ who: 'you', text: line });
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
          if (!handedOffRef.current) sendUser(KICKOFF, { silent: true });
        }, 800);
      });

      ws.addEventListener('message', (ev) => {
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
            if (handedOffRef.current && newName) {
              push({ who: 'other', text: msg.text, name: newName });
            } else {
              push({ who: 'sulivan', text: msg.text });
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
      });

      ws.addEventListener('close', () => {
        wsRef.current = null;
        if (closedRef.current) return;
        setPhase('waking');
        retry = window.setTimeout(connect, 3000);
      });
    };

    connect();
    return () => {
      closedRef.current = true;
      if (retry) window.clearTimeout(retry);
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
    <div className="mt-2 flex min-h-0 w-full max-w-[640px] flex-1 flex-col items-center">
      <h1 className="text-[24px] font-bold tracking-tight">
        {met ? `Meet ${newName}.` : "Let's make someone."}
      </h1>
      <p className="mt-1.5 max-w-[52ch] text-center text-[14px] leading-relaxed text-fawn">
        {met
          ? 'Made together, just now. The house is theirs too.'
          : 'Sulivan will ask a few things. There are no wrong answers, and your own words always beat his suggestions.'}
      </p>

      <div className="mt-4 min-h-0 w-full flex-1 space-y-3 overflow-y-auto px-1 py-2">
        {bubbles.map((b, i) => (
          <div key={i} className={b.who === 'you' ? 'flex justify-end' : 'flex'}>
            <div
              className={`max-w-[46ch] rounded-2xl px-4 py-2.5 text-[14.5px] leading-relaxed ${
                b.who === 'you'
                  ? 'bg-peach'
                  : 'border border-linen bg-fluff shadow-soft'
              }`}
            >
              {b.who !== 'you' && (
                <div className="mb-1 text-[10.5px] font-semibold uppercase tracking-wide text-fawn">
                  {b.who === 'other' ? b.name : 'Sulivan'}
                </div>
              )}
              {b.text}
            </div>
          </div>
        ))}
        {card && (
          <ChoiceCard props={card} />
        )}
        {phase === 'waking' && (
          <div className="text-center text-[13px] text-fawn">Waking the house.</div>
        )}
      </div>

      {met ? (
        <div className="mt-4 pb-4">
          <button
            onClick={onDone}
            className="rounded-full bg-roast px-7 py-2.5 text-[14px] font-bold text-cream"
          >
            Go to the house together
          </button>
        </div>
      ) : (
        <form
          className="mt-3 flex w-full gap-2 pb-4"
          onSubmit={(e) => {
            e.preventDefault();
            sendUser(draft);
            setDraft('');
          }}
        >
          <input
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            placeholder="Answer in your own words"
            disabled={phase === 'waking' || phase === 'thinking'}
            className="w-full flex-1 rounded-full border border-linen bg-parchment px-4 py-2.5 text-[14px] outline-none disabled:opacity-60"
          />
          <button
            type="submit"
            disabled={phase === 'waking' || phase === 'thinking' || !draft.trim()}
            className="rounded-full bg-roast px-5 py-2.5 text-[14px] font-bold text-cream disabled:opacity-50"
          >
            Send
          </button>
        </form>
      )}
    </div>
  );
}
