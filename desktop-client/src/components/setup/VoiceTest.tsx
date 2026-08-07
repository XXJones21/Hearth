import { useCallback, useEffect, useRef, useState } from 'react';
import { ttsPlayer } from '../../lib/audioPlayer';
import { getHttpOrigin, getWsUrl } from '../../lib/config';
import { useAppStore } from '../../store/appStore';

/* The voice test, the mockup's closing beat for the install: the one check no
   automated probe can perform. Sulivan speaks through the real pipeline, the
   mind that wrote the words and the voice that said them both freshly
   provisioned, and only the person in the room can say whether sound came
   out. The three buttons are equals, exactly as designed.

   This screen owns its own WebSocket rather than the house connection: setup
   is still in charge, and the socket dials the house that setup itself just
   started. */

type Phase = 'waking' | 'warming' | 'asking' | 'speaking' | 'spoke' | 'gone';

const GREETING_QUERY =
  'I have just finished installing you, and this is the voice test. ' +
  'Introduce yourself in two or three short sentences, and mention that if ' +
  'I can hear your voice, everything is working.';

/* `voiceResident` is the plan's coexist flag. On a machine that cannot hold
   the mind and the voice together (the 8 GB Air), the voice is provisioned
   but does not boot resident, so this screen becomes a written first meeting:
   same greeting through the real mind, honestly no audio expected, one
   button. The take-turns voice is designed and not yet built. */
export function VoiceTest({
  onHeard,
  voiceResident = true,
}: {
  onHeard: () => void;
  voiceResident?: boolean;
}) {
  const [phase, setPhase] = useState<Phase>('waking');
  const [reply, setReply] = useState('');
  const [hint, setHint] = useState('');
  const wsRef = useRef<WebSocket | null>(null);
  const framesRef = useRef(0);
  const closedRef = useRef(false);

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
    setReply('');
    setHint('');
    setPhase('asking');
    ws.send(JSON.stringify({ action: 'text_query', text: GREETING_QUERY }));
  }, []);

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
              ui_render: false,
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
      });

      ws.addEventListener('message', (ev) => {
        if (typeof ev.data !== 'string') {
          if (ev.data instanceof ArrayBuffer) {
            framesRef.current += 1;
            ttsPlayer.push(ev.data);
            setPhase((p) => (p === 'asking' ? 'speaking' : p));
          }
          return;
        }
        try {
          const msg = JSON.parse(ev.data);
          if (msg.action === 'tts_chunk_start') {
            ttsPlayer.begin(Number(msg.sample_rate) || 48000);
          } else if (msg.action === 'ai_response' && typeof msg.text === 'string') {
            setReply(msg.text);
          } else if (msg.action === 'speaking_complete') {
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
  }, [speak, voiceResident]);

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
              onClick={onHeard}
              disabled={phase === 'waking' || phase === 'warming'}
              className="rounded-full bg-roast px-6 py-2.5 text-[14px] font-bold text-cream disabled:opacity-50"
            >
              I heard him
            </button>
          </>
        ) : (
          <button
            onClick={onHeard}
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

