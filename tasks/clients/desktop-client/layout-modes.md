---
area: clients/desktop-client
status: open
depends_on: []
blocks: []
updated: 2026-08-26
---

# Standard and conversational

Two layouts for the desktop client, chosen by the person rather than by the
window size. **Standard** is what ships today. **Conversational** is the shape
the phone and the headset already use: the persona in the middle, everything
else got out of its way.

## Standard, which is the current one

A three-column shell. The persona rail on the left holds the fire, the name,
the persona chips and the five section icons. The middle is the working
surface: search, the feed, the composer along the bottom. The right rail holds
Sessions, Routines, Memory and Runs.

It is a workstation layout and it earns its place: the desktop is where a
person has room for the journal, the session list and the reply at the same
time, and where they are as likely to be reading as talking.

## Conversational, which is the new one

The persona moves to the CENTRE of the window and becomes the thing the layout
is about, the way it is on iOS and Android. Underneath it, one chat input.
Nothing else competes.

- **The persona is centred**, at a size that reads as presence rather than as a
  widget in a corner.
- **The right rail collapses.** It does not vanish, because the session list is
  how a person finds what was said last week; it gets out of the way and comes
  back on demand.
- **The bottom is one input box.** The same composer, without the search bar,
  the filters and the prompt chips above it.
- **The left rail's contents have to go somewhere.** Persona switching and the
  five sections still need a home when the rail is not there. Probably the same
  place the phone puts them, which is worth checking before inventing one.

## Why it is worth having both

The phone and the headset were built conversational because they have no room
to be anything else. That constraint produced the better *feeling* layout, and
the desktop currently cannot get to it. Someone who mostly talks to their house
should be able to have the talking layout on the big screen too, and someone
mid-project should be able to switch back.

It is also the cheaper half of a question the product will face anyway: what
the desktop client looks like when it is not being used as a workstation.

## Open questions

- **Where the toggle lives.** Settings under Appearance is the obvious answer
  and may be the wrong one if the mode is something a person flips several
  times a day rather than once.
- **Whether the mode is per person or per persona.** Selene is a librarian and
  Sulivan is a daily driver; they may not want the same room.
- **Whether conversational is the default on a narrow window.** The shell
  already hides the left rail under `lg`, so something layout-ish already
  happens at small widths and the two behaviours need to agree rather than
  fight.
- **What the persona does with the space.** On the phone the fire sits in a
  large empty field and that emptiness is most of the effect. A maximised
  desktop window is a great deal more emptiness.

## Related

The fire's size is fixed in CSS pixels rather than derived from the window
(`hearth-client/src/components/PersonaFlame.tsx`), so it does not grow when the
window does. Conversational will want a different fixed size from standard,
which is an argument for the size being per-mode rather than a constant.

**Voice is not part of this.** The desktop client can speak and cannot listen:
it has an `AudioContext` for TTS playback and no capture path at all, in either
the web layer or the Tauri side. A conversational layout with a text-only input
is honest today; the composer's "or just start talking" placeholder already is
not. See [speech-input.md](speech-input.md).
