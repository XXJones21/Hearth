/* The prefetched interview opener, carried from the voice test to the
   interview.

   The clean break the setup flow promises (a plain greeting first, the
   interview only after "I heard him") would otherwise cost the person a
   wait on the far side of the button. So the voice test asks Sulivan to
   compose the opener the moment the greeting finishes, buffers everything
   that comes back, and hands both the buffer AND the live socket to the
   interview screen. The socket matters as much as the buffer: the server
   keeps conversation history per connection, so the opener is only
   coherent with the answers that follow it if they travel the same wire.

   `detach` unhooks the voice test's listeners; the interview calls it and
   attaches its own in one synchronous block, so no frame can fall between
   the screens. */

export type PrefetchedOpener = {
  /** The voice test's socket, still open, offered for adoption. */
  ws: WebSocket | null;
  /** The kickoff went out; a reply is owed. */
  started: boolean;
  /** speaking_complete arrived; the buffer is the whole opener. */
  complete: boolean;
  /** The opener turn errored; the interview should ask again itself. */
  failed: boolean;
  text: string | null;
  card: Record<string, unknown> | null;
  audio: ArrayBuffer[];
  sampleRate: number;
  detach: (() => void) | null;
};

export function freshOpener(): PrefetchedOpener {
  return {
    ws: null,
    started: false,
    complete: false,
    failed: false,
    text: null,
    card: null,
    audio: [],
    sampleRate: 48000,
    detach: null,
  };
}

/* One kickoff, sent by whichever screen gets to send it: the voice test
   when it prefetches, the interview when it has to start cold. The
   server's first-run direction keys its two beats off these stage
   directions, so the wording is part of the contract. */
export const INTERVIEW_KICKOFF =
  '(This is my first run and I heard your voice. Open the interview now, ' +
  'in one message: one sentence picking up from your greeting, one ' +
  'sentence of what a persona is, then your first question with ' +
  'choice_card already called. Do not ask whether to begin.)';
