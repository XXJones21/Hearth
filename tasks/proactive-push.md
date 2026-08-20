# Proactive push: the house speaking first

Opened 2026-08-20, when a timer on the Android client counted down to
zero and nothing happened.

The house cannot start a turn. Every conversation Hearth has ever had began
with a client opening a socket and saying something; there is no path for the
house to wake a surface and put a sentence or a card on it. That was
theoretical until a timer needed it.

## The evidence

`backend/harness/valar/tools/handlers/timers.py` names this in its own header:

> NOTE on firing: a fired timer is a *proactive push* (Keystone 1), which is
> NOT built. The scheduler that says "your timer is done" reads
> `due_timers()` and is a separate deliverable.

So the state half exists and is deliberate: `set_timer` records a `fire_at`
instant, `list_timers` reports what is pending, `due_timers()` is there to be
read. What is missing is the thing that reads it and the channel that carries
the result.

Verified on the Razr 2026-08-20: "set a timer for two minutes" drew a
timer_card, the countdown ticked live client-side to 0:00, and then the
house was silent. The client is behaving correctly; there is nothing to
receive.

## Why this is bigger than timers

The same missing channel blocks every one of these:

- A timer, an alarm, a calendar nudge.
- Selene reading her daily review aloud.
- The morning brief.
- A notification surfaced in the persona's voice on the foldable's cover
  screen, which is the whole premise of `wiki/raw/research-foldable-prototype.md`:
  "the right information at the right time" is a push claim.
- A persona surfacing something unprompted on the desktop client.

It is tracked as Keystone 1 in the Valinor proactive-tools roadmap
(`wiki/architecture/harness/proactive-tools-roadmap.md`), which already
records the phone's stake in it.

## What it needs

Three pieces, per the roadmap:

1. **A scheduler in the house.** Time-based and event-based triggers, reading
   `due_timers()` among others. The natural home is the gateway's own clock,
   which already runs the daily review every half hour, rather than a second
   process.
2. **A push over the existing socket.** The WebSocket is already persistent
   and bidirectional and every client already renders `ai_response` plus the
   `tts_chunk_start` stream, so the transport is there. What is new is a turn
   the client did not ask for, and each client handling it: go to SPEAKING
   with no preceding LISTENING.
3. **A quiet-hours gate.** Server-side policy, client-respected, so the house
   does not talk at three in the morning.

## Client-side, on Android

Small once the channel exists, and worth naming so it is not forgotten:

- Accept an unsolicited turn: enter SPEAKING from IDLE without a preceding
  send, and let the existing player and karaoke clock carry it.
- A sound for a fired timer even when the app is not foregrounded, which is
  a notification rather than a socket concern.
- On the appliance, a fired timer should light the cover screen.

## Definition of done

A timer set by voice announces itself out loud when it elapses, on the phone
and on the desktop client, without anyone touching the device, and stays
quiet during configured quiet hours.
