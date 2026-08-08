import { useCallback, useEffect, useRef, useState } from 'react';
import { ttsPlayer } from '../../lib/audioPlayer';
import { getWsUrl } from '../../lib/config';
import { useAppStore } from '../../store/appStore';
import { ChoiceCard } from '../cards/ChoiceCard';
import { MessageCard } from '../feed/MessageCard';
import { TimelineEntry } from '../feed/TimelineEntry';
import { BRAIN_KICKOFF } from './opener';

/* Beat three: the second brain. Mockup screens 14 through 16.

   Hosted by the persona just made, in their own voice, and argued from
   self-interest rather than features: they will forget this conversation the
   moment it ends, and they would rather not. Three moves, one per turn --
   why it matters, what it actually is, and one real thing to put in it. The
   server's BRAIN_DIRECTION drives them; this screen only carries them.

   Unlike the interview, this dials its own socket rather than adopting the
   one before it. Nothing is lost by that: the handover cleared the session
   history deliberately, so the new persona's first words come from their own
   prompt rather than five turns of Sulivan speaking. A fresh connection gets
   the switched persona because the engine's current persona is house state,
   not connection state. */

type Bubble = { who: 'them' | 'you'; text: string; ts: number };
type Phase = 'waking' | 'thinking' | 'speaking' | 'waiting' | 'done';
type BrainInfo = { root: string; folders: { name: string; entries: number }[] };

/* Mockup screen 14's chips: the four folders and what each is for. The
   meanings are product copy, fixed here; only the counts and the path come
   from the server's brain_info. */
const FOLDER_MEANINGS: Record<string, string> = {
  Projects: 'Things with an end',
  Areas: 'Things that never end',
  Thoughts: 'What we talked about, by day',
  Resources: 'Things worth keeping',
};

export function SecondBrain({ onDone }: { onDone: () => void }) {
  /* Whoever the house is currently speaking as. The interview's handover set
     this when persona_config arrived; reaching this screen by debug stage
     instead falls back to the shipped name. Subscribed rather than read once,
     so a switch that lands late still renames the rail. */
  const personaName = useAppStore((s) => s.currentPersonaName) || 'Sulivan';
  const [phase, setPhase] = useState<Phase>('waking');
  const [bubbles, setBubbles] = useState<Bubble[]>([]);
  const [card, setCard] = useState<Record<string, unknown> | null>(null);
  const [draft, setDraft] = useState('');
  const [project, setProject] = useState<string | null>(null);
  const [brain, setBrain] = useState<BrainInfo | null>(null);
  const wsRef = useRef<WebSocket | null>(null);
  const closedRef = useRef(false);
  /* The message handler is attached once and would otherwise close over the
     null this started as. */
  const doneRef = useRef(false);

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

  useEffect(() => {
    closedRef.current = false;
    let retry: number | undefined;

    const onMessage = (ev: MessageEvent) => {
      if (typeof ev.data !== 'string') {
        if (ev.data instanceof ArrayBuffer) {
          ttsPlayer.push(ev.data);
          setPhase((p) => (p === 'thinking' ? 'speaking' : p));
        }
        return;
      }
      try {
        const msg = JSON.parse(ev.data);
        if (msg.action === 'tts_chunk_start') {
          ttsPlayer.begin(Number(msg.sample_rate) || 48000);
        } else if (msg.action === 'ai_response' && typeof msg.text === 'string') {
          push({ who: 'them', text: msg.text, ts: Date.now() });
        } else if (msg.action === 'ui_component') {
          const comp = msg.component ?? msg;
          if (comp?.type === 'choice_card') setCard(comp.props ?? null);
        } else if (msg.action === 'brain_info' && typeof msg.root === 'string') {
          setBrain({
            root: msg.root,
            folders: Array.isArray(msg.folders)
              ? (msg.folders as { name: string; entries: number }[])
              : [],
          });
        } else if (msg.action === 'project_started') {
          /* The beat closed. The server says so rather than the screen
             inferring it, because "they stopped talking" is also what a
             failed turn looks like. */
          doneRef.current = true;
          if (typeof msg.title === 'string') setProject(msg.title);
          /* The footnote's count goes 0 to 1 without a round-trip. */
          setBrain((prev) =>
            prev
              ? {
                  ...prev,
                  folders: prev.folders.map((f) =>
                    f.name === 'Projects' ? { ...f, entries: f.entries + 1 } : f,
                  ),
                }
              : prev,
          );
        } else if (msg.action === 'speaking_complete') {
          setPhase(doneRef.current ? 'done' : 'waiting');
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
        /* A beat for client_info to land, then open the beat. */
        window.setTimeout(() => {
          if (!doneRef.current) sendUser(BRAIN_KICKOFF, { silent: true });
        }, 800);
      });

      ws.addEventListener('message', onMessage);
      ws.addEventListener('close', onClose);
    };

    connect();

    return () => {
      closedRef.current = true;
      if (retry) window.clearTimeout(retry);
      wsRef.current?.close();
      wsRef.current = null;
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

  const done = phase === 'done' || Boolean(project);

  return (
    <div className="mt-2 flex min-h-0 w-full max-w-[680px] flex-1 flex-col items-center">
      <h1 className="text-[24px] font-bold tracking-tight">A memory of their own.</h1>
      <p className="mt-1.5 max-w-[52ch] text-center text-[14px] leading-relaxed text-fawn">
        {done
          ? `${personaName} will remember this. It lives in folders on your disk, and you can read or delete any of it.`
          : `${personaName} has something to ask you about remembering.`}
      </p>

      {done && project && (
        <div className="mt-2.5 flex items-center gap-2 rounded-full border border-linen bg-glowtint px-3.5 py-1.5 text-[12.5px] font-semibold">
          <span
            className="size-2 rounded-full"
            style={{ background: 'var(--persona, #E39A5B)' }}
          />
          {project} is the first thing in it
        </div>
      )}

      {brain && (
        /* Mockup 14: the four folders as fixed furniture, with the real path
           underneath. The persona talks about them; the screen shows them. */
        <div className="mt-3 w-full">
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            {brain.folders.map((f) => (
              <div
                key={f.name}
                className="rounded-2xl border border-linen bg-parchment px-3 py-2.5 text-left"
              >
                <div className="text-[13px] font-bold text-roast">{f.name}</div>
                <div className="mt-0.5 text-[11.5px] leading-snug text-fawn">
                  {FOLDER_MEANINGS[f.name] ?? ''}
                </div>
              </div>
            ))}
          </div>
          <p className="mt-2 text-center text-[12px] text-fawn">
            Created at <span className="font-mono">{brain.root}</span>
            {' · '}
            {brain.folders.length} folders,{' '}
            {brain.folders.reduce((n, f) => n + f.entries, 0)} entries
          </p>
        </div>
      )}

      <div className="relative mt-4 min-h-0 w-full flex-1 overflow-y-auto pl-14 pr-1 pt-2 text-left">
        <span
          aria-hidden="true"
          className="pointer-events-none absolute bottom-2 left-[21px] top-2 w-[2px] rounded bg-linen"
        />
        {bubbles.map((b, i) => (
          <TimelineEntry key={i} author={b.who === 'you' ? 'You' : personaName}>
            <MessageCard
              role={b.who === 'you' ? 'user' : 'assistant'}
              author={b.who === 'you' ? 'You' : personaName}
              text={b.text}
              ts={b.ts}
            />
          </TimelineEntry>
        ))}
        {card && (
          <TimelineEntry author={personaName}>
            <ChoiceCard props={card} />
          </TimelineEntry>
        )}
        {phase === 'waking' && <div className="py-2 text-[13px] text-fawn">Waking the house.</div>}
        {phase === 'thinking' && (
          <div className="py-2 text-[13px] text-fawn">{personaName} is thinking.</div>
        )}
      </div>

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
          placeholder={done ? `Talk to ${personaName}` : 'Answer in your own words'}
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

      <div className="mb-4 mt-3">
        <button
          onClick={onDone}
          className="rounded-full bg-roast px-7 py-3 text-sm font-bold text-cream disabled:opacity-30"
          disabled={!done}
        >
          Go to the house
        </button>
      </div>
    </div>
  );
}
