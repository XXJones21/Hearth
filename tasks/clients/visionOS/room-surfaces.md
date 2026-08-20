---
area: clients/visionOS
status: open
depends_on: []
blocks: []
updated: 2026-08-20
---

# Persona and Apps have nowhere to live in the room

Both surfaces work in the volume, where the shelf along the bottom edge opens
them into the space beside the persona. In the immersive space they are
unreachable: the views exist, they are in the shared package, and nothing hosts
them.

## Why they were left

Phase 4 deliberately did not fork `MainVolume`. The immersive host is a
different stage for the same world, not a copy of the volume with the box taken
out -- so the surfaces did not come across automatically, and inventing a
placement for them was out of scope for a phase whose gate was the round trip.

Journal DID come across, and how it came across is the point: it is not a panel
in the room, it is a library of real books on real shelves that you scroll and
open. That is what a surface looks like when it is designed for a room rather
than ported into one.

## The question this is really asking

**Where does a panel go in a space with no edges?** The volume answers it by
having a bottom edge to hang a shelf off. A room has no such thing, and the
three obvious answers are all worse than they sound:

- **Floating in front of you** is a window, which is what the headset already
  does better than we will.
- **Anchored to the room** means walking to your settings.
- **Attached to the persona** is the most promising and the least explored --
  `personaAnchor` already exists for exactly this, and the persona-mounted
  shelves the design describes hang off it as entities carrying their own
  SwiftUI.

The design doc's own note is that `pushWindow` is the alternative shape: a real
window associated with the immersive space, closing with it. That is the honest
answer for Settings, which is a form and will never be anything else.

## A distinction worth making before building

The four surfaces are not one kind of thing:

- **Journal** is the persona's memory, and it became furniture.
- **Persona** is who they are -- prompt and colours. Arguably it belongs ON the
  persona, reachable by looking at them.
- **Apps** is what the house can do. Read-only from the client, and closest to a
  genuine list.
- **Settings** is where the house is. A form, and a window is fine.

Building one host for all four is what produced the volume's shelf, and in a
room it would produce four floating panels. The likelier right answer is that
each of the four gets the shape its content wants, the way Journal already did.

## Open questions

- Whether the rail (Sessions, Memory, Routines) follows the same rule or stays
  a rail.
- Whether Settings should even be reachable from the immersive space, or whether
  it belongs to the pairing window and the volume only.
