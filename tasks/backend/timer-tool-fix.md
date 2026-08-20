# Timer tool: nothing happens when a timer finishes

Opened 2026-08-20, found on the Android client but not an Android bug.

Setting a timer works. Firing one does not exist.

## What happens today

Verified on the Razr against the live house: "set a timer for two minutes"
records the timer, draws a `timer_card`, and the card counts down live to
0:00 on the client. Then nothing. No sound, no spoken line, no card change.
The timer simply stops being listed.

The client is behaving correctly. There is nothing for it to receive.

## Why

`backend/harness/valar/tools/handlers/timers.py` says so in its own header:

> NOTE on firing: a fired timer is a *proactive push* (Keystone 1), which is
> NOT built. The scheduler that says "your timer is done" reads
> `due_timers()` and is a separate deliverable.

The state half is deliberate and already correct:

- `set_timer` records `{label, fire_at, created}` in the in-process store.
- `list_timers` returns the pending ones, `fire_at` as epoch seconds so the
  client can tick its own countdown.
- `due_timers()` exists to be read by something that never arrived.

What is missing is the thing that notices a timer is due and the channel that
carries the news to a client.

## What needs to happen

### 1. A scheduler that reads due_timers()

Natural home is the gateway's own clock, not a second process. It already
runs the daily review on a half-hour tick (`memory/daily_review.py`, wired at
`server.py`), and the tray keeps the house alive, so the house's loop is the
right place. Timers need a much finer tick than the review: a second, or a
sleep computed to the next `fire_at`.

On finding a due timer it should mark it fired (so it cannot fire twice
across a restart or a reconnect) and hand it to the push below.

### 2. A way for the house to start a turn

This is the actual blocker and it is bigger than timers. Nothing in the
architecture lets the house speak first: every conversation begins with a
client opening a socket and sending something. The WebSocket is already
persistent and bidirectional, and every client already renders `ai_response`
plus the `tts_chunk_start` PCM stream, so the transport exists. What is new
is a turn the client did not ask for.

The same channel is what unblocks Selene reading her daily review aloud, the
morning brief, calendar nudges, a persona surfacing something unprompted on
the desktop, and notifications spoken on the foldable's cover screen. It is
Keystone 1 in `wiki/architecture/harness/proactive-tools-roadmap.md`; a fired
timer is simply its first concrete trigger.

### 3. A quiet-hours gate

Server-side policy, client-respected, so the house does not announce a timer
at three in the morning.

### 4. What each client then owes

Small, once the channel exists, and worth listing so it is not forgotten:

- Enter SPEAKING from IDLE with no preceding turn, and let the existing
  player and karaoke clock carry it.
- A notification with a sound when the app is not foregrounded, which is a
  platform concern rather than a socket one.
- On the appliance, a fired timer should light the cover screen.

## Definition of done

A timer set by voice announces itself out loud when it elapses, with no one
touching the device, on the phone and on the desktop client. It fires once
and only once. It stays quiet during configured quiet hours.
