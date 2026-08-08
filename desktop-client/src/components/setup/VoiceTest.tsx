import { useCallback, useEffect, useRef, useState } from 'react';
import type { MutableRefObject } from 'react';
import { ttsPlayer } from '../../lib/audioPlayer';
import { getHttpOrigin, getWsUrl } from '../../lib/config';
import { useAppStore } from '../../store/appStore';
import { freshOpener, INTERVIEW_KICKOFF, type PrefetchedOpener } from './opener';

/* The voice test, the mockup's closing beat for the install: the one check no
   automated probe can perform. Sulivan speaks through the real pipeline, the
   mind that wrote the words and the voice that said them both freshly
   provisioned, and only the person in the room can say whether sound came
   out. The three buttons are equals, exactly as designed.

   This screen owns its own WebSocket rather than the house connection: setup
   is still in charge, and the socket dials the house that setup itself just
   started.

   It also works ahead. The greeting is deliberately just a greeting (the
   server's first-run direction keeps the interview out of it), so the moment
   it completes, this screen silently asks Sulivan to compose the interview
   opener and buffers the reply into `opener`. "I heard him" then hands the
   socket itself across, because the conversation the opener belongs to lives
   on this connection. Every reply routes by a queue of what was asked, so a
   "Say it again" that lands behind the prefetch still finds its own turn. */

type Phase = 'waking' | 'warming' | 'retrying' | 'asking' | 'speaking' | 'spoke' | 'gone';
type Expect = 'greeting' | 'opener';

/* How long the greeting keeps trying before it gives up and lets the person
   past. The same patience the resident path spends waiting on the voice,
   spent here on the mind. */
const PATIENCE_MS = 150_000;

const GREETING_QUERY =
  '(I have just finished installing you, and this is the voice test. ' +
  'Introduce yourself in two or three short sentences, and mention that if ' +
  'I can hear your voice, everything is working.)';

/* `voiceResident` is the plan's coexist flag. On a machine that cannot hold
   the mind and the voice together (the 8 GB Air), the voice is provisioned
   but does not boot resident, so this screen becomes a written first meeting:
   same greeting through the real mind, honestly no audio expected, one
   button. The take-turns voice is designed and not yet built. */
export function VoiceTest({
  onHeard,
  voiceResident = true,
  opener,
}: {
  onHeard: () => void;
  voiceResident?: boolean;
  opener?: MutableRefObject<PrefetchedOpener>;
}) {
  const [phase, setPhase] = useState<Phase>('waking');
  const [reply, setReply] = useState('');
  const [hint, setHint] = useState('');
  const wsRef = useRef<WebSocket | null>(null);
  const framesRef = useRef(0);
  const closedRef = useRef(false);
  /* When the first greeting went out, so the retry loop knows how long it has
     been trying rather than how many times. */
  const askStartedRef = useRef(0);
  const retryRef = useRef<number | undefined>(undefined);
  /* The sentence the next audio frame belongs to. tts_chunk_start announces a
     segment and its text before any of it is audible, so the words are held
     here and shown when the first frame of that segment arrives. */
  const pendingTextRef = useRef<string | null>(null);
  /* Whose turn each incoming reply belongs to, in the order the questions
     went out. The server answers one query at a time per connection, so a
     shift on every turn-ending message keeps this aligned. */
  const expectRef = useRef<Expect[]>([]);
  /* Handoff mode: the screen is gone but its listeners stay on the wire,
     buffering opener frames into `opener` until the interview takes over.
     No setState and no audio output past this point. */
  const detachedRef = useRef(false);
  const handoffRef = useRef(false);
  const acRef = useRef<AbortController | null>(null);

  /* The orb above this screen is the same particle animation every client
     uses, driven by the shared visual state: he thinks while warming and
     speaks while speaking, exactly as he will in the house. No second
     waveform; he IS the waveform. */
  useEffect(() => {
    const setVisualState = useAppStore.getState().setVisualState;
    setVisualState(
      phase === 'speaking' ? 'speaking' : phase === 'spoke' ? 'idle' : 'thinking',
    );
    return () => setVisualState('idle');
  }, [phase]);

  const speak = useCallback(() => {
    const ws = wsRef.current;
    if (!ws || ws.readyState !== WebSocket.OPEN) return;
    framesRef.current = 0;
    pendingTextRef.current = null;
    if (!askStartedRef.current) askStartedRef.current = Date.now();
    expectRef.current.push('greeting');
    setReply('');
    setHint('');
    setPhase('asking');
    ws.send(JSON.stringify({ action: 'text_query', text: GREETING_QUERY }));
  }, []);

  /* The greeting is done; start Sulivan on the interview opener while the
     person decides whether they heard him. Silent on this screen: the reply
     buffers into `opener` and first plays on the interview side of the
     break. Once per connection; a reconnect gets a fresh chance. */
  const prefetch = useCallback(() => {
    const ws = wsRef.current;
    const o = opener?.current;
    if (!o || o.started || !ws || ws.readyState !== WebSocket.OPEN) return;
    o.started = true;
    expectRef.current.push('opener');
    ws.send(JSON.stringify({ action: 'text_query', text: INTERVIEW_KICKOFF }));
  }, [opener]);

  useEffect(() => {
    closedRef.current = false;
    let retry: number | undefined;

    const connect = () => {
      if (closedRef.current) return;
      const ws = new WebSocket(getWsUrl());
      ws.binaryType = 'arraybuffer';
      wsRef.current = ws;
      const ac = new AbortController();
      acRef.current = ac;

      ws.addEventListener(
        'open',
        () => {
          /* A new connection is a new server session: whatever a dead socket
             prefetched belongs to a history that no longer exists. */
          expectRef.current = [];
          if (opener) opener.current = freshOpener();
          ws.send(
            JSON.stringify({
              action: 'client_info',
              platform: 'desktop',
              capabilities: {
                audio: true,
                spatial: false,
                voice_input: false,
                text_input: true,
                /* True even though this screen renders no cards: the opener
                   prefetched on this session must be composed WITH the
                   choice_card tool, and the server primes tools against
                   what the client says it can show. */
                ui_render: true,
              },
              audio_format: { sample_rate: 48000, bit_depth: 16, channels: 1 },
            }),
          );
          /* Do not ask a cold engine to speak. Sulivan sits in the thinking
             state while the voice finishes its first warm (about a minute on
             first install), and only a ready voice gets the greeting. The cap
             is a backstop: past it we try anyway rather than sit forever,
             since the engine also lazy-loads on first request. On a machine
             whose plan keeps the voice non-resident there is nothing to wait
             for: the greeting arrives in writing. */
          if (!voiceResident) {
            window.setTimeout(() => speak(), 800);
            return;
          }
          setPhase('warming');
          const startedAt = Date.now();
          const waitForVoice = async () => {
            if (closedRef.current || wsRef.current !== ws) return;
            try {
              const resp = await fetch(`${getHttpOrigin()}/voice/ready`);
              const body = (await resp.json()) as { ready?: boolean };
              if (body.ready) {
                speak();
                return;
              }
            } catch {
              /* harness still settling; keep waiting */
            }
            if (Date.now() - startedAt > 150_000) {
              speak();
              return;
            }
            window.setTimeout(waitForVoice, 3000);
          };
          void waitForVoice();
        },
        { signal: ac.signal },
      );

      ws.addEventListener(
        'message',
        (ev) => {
          const head = expectRef.current[0];
          const o = opener?.current;
          if (typeof ev.data !== 'string') {
            if (!(ev.data instanceof ArrayBuffer)) return;
            if (head === 'opener') {
              o?.audio.push(ev.data);
              return;
            }
            if (detachedRef.current) return;
            framesRef.current += 1;
            ttsPlayer.push(ev.data);
            /* Show the sentence as it starts being heard, not when the whole
               reply is done. ai_response only arrives after the last word is
               generated, so waiting for it left him speaking two sentences
               into a screen that still read "Listening for him now." */
            if (pendingTextRef.current) {
              const said = pendingTextRef.current;
              pendingTextRef.current = null;
              setReply((prev) => (prev ? `${prev} ${said}` : said));
            }
            setPhase((p) => (p === 'asking' ? 'speaking' : p));
            return;
          }
          try {
            const msg = JSON.parse(ev.data);
            if (msg.action === 'tts_chunk_start') {
              if (head === 'opener') {
                if (o) o.sampleRate = Number(msg.sample_rate) || 48000;
                return;
              }
              if (detachedRef.current) return;
              ttsPlayer.begin(Number(msg.sample_rate) || 48000);
              if (typeof msg.text === 'string' && msg.text.trim()) {
                pendingTextRef.current = msg.text.trim();
              }
            } else if (msg.action === 'ui_component') {
              /* Only the opener asks for a card; this screen has nowhere to
                 render one anyway. */
              const comp = msg.component ?? msg;
              if (head === 'opener' && o && comp?.type === 'choice_card') {
                o.card = (comp.props as Record<string, unknown>) ?? null;
              }
            } else if (msg.action === 'ai_response' && typeof msg.text === 'string') {
              if (head === 'opener') {
                if (o) o.text = msg.text;
                return;
              }
              if (detachedRef.current) return;
              /* The authoritative text, and the only text when nothing spoke.
                 Replacing what the segments accumulated also repairs any
                 sentence whose audio never arrived. */
              pendingTextRef.current = null;
              setReply(msg.text);
            } else if (msg.action === 'error') {
              const failedTurn = expectRef.current.shift();
              if (failedTurn === 'opener') {
                /* The prefetch lost its race; the interview asks again
                   itself on the adopted socket. */
                if (o) o.failed = true;
                return;
              }
              if (detachedRef.current) return;
              /* The greeting can lose a race it was never told it was running:
                 llama-server takes tens of seconds to load its weights on a cold
                 install, and the non-resident path asks 800ms after the socket
                 opens. This screen used to sit on "Listening for him now"
                 forever, because an error carried no handler and the only button
                 is disabled while a question is outstanding. Keep asking while
                 the mind finishes waking, then let the person past regardless:
                 the install itself is sound, and trapping someone on the last
                 screen of setup is worse than a greeting they never got. */
              const waited = Date.now() - (askStartedRef.current || Date.now());
              if (waited < PATIENCE_MS) {
                setPhase('retrying');
                retryRef.current = window.setTimeout(speak, 3000);
              } else {
                setPhase('spoke');
                setHint(
                  `He could not answer: ${String(msg.message ?? 'unknown error')} ` +
                    'The house is installed and you can carry on; the logs folder of ' +
                    'your install has the detail.',
                );
              }
            } else if (msg.action === 'speaking_complete') {
              const doneTurn = expectRef.current.shift();
              if (doneTurn === 'opener') {
                if (o) o.complete = true;
                return;
              }
              /* The greeting just finished: the perfect moment to start
                 composing what comes after the button. */
              prefetch();
              if (detachedRef.current) return;
              setPhase('spoke');
              if (voiceResident && framesRef.current === 0) {
                setHint(
                  'No audio arrived. The voice may still be warming after its first ' +
                    'install; give it a moment and ask him to say it again.',
                );
              }
            }
          } catch {
            /* not JSON; ignore */
          }
        },
        { signal: ac.signal },
      );

      ws.addEventListener(
        'close',
        () => {
          wsRef.current = null;
          /* A socket that dies before adoption takes its session, and any
             half-buffered opener, with it. */
          if (opener?.current.ws === ws) opener.current.ws = null;
          if (closedRef.current) return;
          setPhase('waking');
          retry = window.setTimeout(connect, 3000);
        },
        { signal: ac.signal },
      );
    };

    connect();
    return () => {
      closedRef.current = true;
      if (retry) window.clearTimeout(retry);
      if (retryRef.current) window.clearTimeout(retryRef.current);
      const ws = wsRef.current;
      const o = opener?.current;
      if (handoffRef.current && o && ws && ws.readyState === WebSocket.OPEN) {
        /* "I heard him": the interview inherits this socket, because the
           session holding the greeting and the prefetched opener lives on
           it. The listeners stay attached in detached mode (refs only, no
           audio, no setState) so a reply still streaming keeps landing in
           the buffer; the interview's first synchronous act is detach()
           then its own listeners, so nothing falls between the screens. */
        detachedRef.current = true;
        o.ws = ws;
        const ac = acRef.current;
        o.detach = () => ac?.abort();
      } else {
        acRef.current?.abort();
        ws?.close();
      }
      ttsPlayer.reset();
    };
  }, [speak, prefetch, voiceResident, opener]);

  const leave = () => {
    handoffRef.current = true;
    onHeard();
  };

  return (
    <div className="mt-4 flex flex-col items-center">
      <h1 className="text-[26px] font-bold tracking-tight">Meet Sulivan.</h1>
      <p className="mt-2 max-w-[52ch] text-center text-[15px] leading-relaxed text-fawn">
        {voiceResident
          ? 'Your guide to Hearth. He lives here now, and this is the first thing he will ever say to you.'
          : 'Your guide to Hearth. He lives here now. On this machine his mind and his voice take turns, so today he writes; speaking comes in an update.'}
      </p>

      <div className="mt-6 w-full max-w-[520px] rounded-2xl border border-linen bg-fluff p-5 text-left shadow-soft">
        <div className="mb-2 text-[11.5px] font-semibold uppercase tracking-wide text-fawn">
          Sulivan
        </div>
        <p className="text-[15px] leading-relaxed">
          {reply ||
            (phase === 'waking'
              ? 'The house is starting: the mind, the voice, and the ears all loading for the first time.'
              : phase === 'warming'
                ? 'He is clearing his throat. The voice loads once, on its first day, and he speaks the moment it is ready.'
                : phase === 'retrying'
                  ? 'His mind is still loading. The weights are read from disk once, on this first start, and he answers the moment they are in.'
                  : 'Listening for him now.')}
        </p>
      </div>

      {hint && (
        <p className="mx-auto mt-4 max-w-[52ch] text-center text-[13.5px] leading-snug text-fawn">
          {hint}
        </p>
      )}

      <div className="mt-7 flex items-center justify-center gap-3 pb-4">
        {voiceResident ? (
          <>
            <button
              onClick={() =>
                setHint(
                  'Check the output device and volume, then ask him to say it again. ' +
                    'If it stays silent, the voice log lives in the logs folder of your install.',
                )
              }
              className="rounded-full border border-linen bg-parchment px-5 py-2.5 text-[14px] font-semibold text-fawn"
            >
              I didn't hear anything
            </button>
            <button
              onClick={speak}
              disabled={phase === 'waking' || phase === 'warming' || phase === 'asking'}
              className="rounded-full border border-linen bg-parchment px-5 py-2.5 text-[14px] font-semibold text-fawn disabled:opacity-50"
            >
              Say it again
            </button>
            <button
              onClick={leave}
              disabled={phase === 'waking' || phase === 'warming'}
              className="rounded-full bg-roast px-6 py-2.5 text-[14px] font-bold text-cream disabled:opacity-50"
            >
              I heard him
            </button>
          </>
        ) : (
          <button
            onClick={leave}
            disabled={phase === 'waking' || phase === 'asking'}
            className="rounded-full bg-roast px-6 py-2.5 text-[14px] font-bold text-cream disabled:opacity-50"
          >
            Meet the house
          </button>
        )}
      </div>
    </div>
  );
}
