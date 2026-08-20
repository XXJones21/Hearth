---
title: Hearth on Apple Vision Pro
status: draft
last_reviewed: 2026-08-20
related:
  - ios.md
  - macos.md
  - ../first-run.md
sources:
  - wiki/raw/hearth-vision-design.md
  - wiki/raw/visionos-handoff.md
  - tasks/clients/visionOS/phase-3-5.md
  - tasks/clients/visionOS/phase-4.md
  - tasks/clients/visionOS/phase-4-5.md
  - apple-client/Hearth/Hearth Vision/
  - apple-client/Hearth/Core/Sources/HearthSpatial/
---

# Hearth on Apple Vision Pro

Hearth Vision is a separate app from the iPhone one, not the same app made
bigger. It shares the iPhone's networking, its personas and its face, and
almost nothing else: where the phone draws a persona on a screen you hold,
the headset puts one in the room you are standing in.

Like the phone, it runs nothing itself. There is no model, no inference and
no persona logic on the headset. It connects to a Hearth house running on a
computer on your network, and everything it shows or says comes from that
house. See [Hearth on iOS](ios.md) for what that relationship means; it is
the same one.

What follows is what the app is, as of 2026-08-20.

## Two places, one persona

Hearth Vision has two forms and you move between them with the same gesture.

**The volume** is the resting state: a box sitting in front of you, roughly
the size of something you would put on a desk. The persona is inside it,
with what it is currently saying floating above, cards arriving beside it,
and a shelf of destinations along the bottom edge.

**The room** is the expansion. The box goes away and the persona is simply
in your space, standing on your floor, lit against your walls, occluded by
your furniture.

To cross, pinch the persona and hold for two seconds. The same pinch-and-
hold brings you back. It works in both directions because it is one gesture
with one meaning -- change of place -- rather than an enter button and an
exit button.

A plain pinch, without the hold, starts a voice turn instead. Both live on
the same press: a single gesture decides between them by how long you keep
your fingers together, rather than two gestures racing each other for the
same pinch.

**The persona itself is not recreated when you cross.** The same persona
travels between the two scenes, keeping its state, its expression, and
whatever it was in the middle of saying. Closing the box does not end the
conversation.

## The persona

Two personas ship with the client and they are drawn in genuinely different
ways, because they are different kinds of thing.

**Sulivan is a fire.** Not a picture of one: a real piece of geometry
shaped like a flame, wearing a texture that is computed every frame, with a
light at its centre that spills onto your actual walls. A face sits on the
front of it. Embers rise off it, and what they do tells you where the
conversation is:

| When | What the embers do |
| --- | --- |
| Waiting | A slow, wide drift upward. The fire is burning and nobody is talking to it. |
| Listening | They draw into a narrow rising spiral, and the column swells with your voice. |
| Thinking | They turn -- a slow fire whirl around him, drawn as streaks rather than dots. |
| Speaking | They gather into a shell around him that pulses with the sound of his voice, like a level meter you can walk around. |

**Selene is a figure**, a humanoid model rather than a light. She gets none
of the fire's furniture -- no flame, no ember field, no glow -- because a
person wearing a fire's halo is two personas standing in one place. Which
effects a persona gets is decided by what kind of thing it is, never by its
name, so a new persona of either kind arrives already dressed correctly.

Both can be resized, and the ranges are different because the things are
different. Sulivan goes from about the size of a tennis ball to about
sixty centimetres, which is the span between a desk toy and a companion
standing beside you. Selene goes from a little over a foot to life size.

## The room's light

When the persona is in your space rather than in a box, it lights your
space.

The fire carries a point light at its exact centre, so the warmth falls off
around it the way a real flame's would, and it reaches physical surfaces
rather than only virtual ones. Set Sulivan on the floor at night and there
is a pool of firelight on the floorboards.

There is a second light that only wakes near a surface. Bring the persona
close to a wall, a floor or a ceiling and a soft cone finds it, aims itself
along that surface's own angle, and widens as you get closer -- the way
something soft spreads when you press it against something flat. It also
changes what it throws depending on what it found: flames climbing a wall,
drifting smoke on a ceiling, a slow swirl on a floor. Near a corner it
blends between the two surfaces rather than snapping from one to the other.

The headset builds a mesh of your room as you move, and Hearth uses it for
two things. Your furniture **occludes** the persona, so it goes behind your
sofa rather than through it. And the same mesh is **solid**: you cannot
shove the persona through a wall, because the wall is really there as far
as the app is concerned.

## Moving things around

Everything the app puts in your room can be picked up and moved, and what
else you can do to a thing depends on what it is:

- **The persona** can be moved and resized, but not turned, because it
  already faces you.
- **The bookshelf** can be moved and turned, but not resized. It is a piece
  of furniture and furniture has a size.
- **A book** can be moved only.

Grabbable objects show a vertical handle down their left side, like the
spine of a book, with a close button above it.

Where you leave things is remembered. The persona and the library are
anchored to your room, so they are where you left them the next time you
open the app, at the size you left them.

## The face

The face is the same one the iPhone draws, from the same code and the same
persona file: two eyes and a mouth, built out of a dozen numbers the
persona owns, so two personas wearing the same expressions still look like
two different people. It blinks and looks around on its own, looks away
while the house is thinking, and follows the actual sound of the voice
while it talks.

On the headset it is drawn onto a curved card that sits just in front of
the flame and bends around it, so it reads as being ON the fire from the
angles you are likely to look from. If the headset cannot start the
drawing pipeline the app falls back to the flat face the phone uses, still
driven by the same director, so a persona is degraded but never faceless.

Full detail on how the face works lives in
`wiki/raw/persona-face-spec.md`, which every client implements from.

## The rest of the house

Along the bottom of the volume is a shelf of destinations: **Journal**,
**Persona**, **Apps** and **Settings**, and a right-hand rail carrying
**Sessions**, **Memory** and **Routines**. Opening one slides the persona
aside and puts the surface in the space next to it, rather than covering
the persona up.

Journal is the exception, and deliberately so. The persona's memory is not
a panel: it is a **library of real books on real shelves** that you scroll
by dragging and open by pinching a spine. Ask the house about something it
wrote down and it will walk to the shelves and fetch the book itself.

Cards stay beside the persona rather than following you around. A card is
something the persona handed you, so it belongs where the persona is; a card
that trails you from room to room is a notification, and the point of putting
a house in a room is that it is somewhere rather than everywhere.

## What it needs

- **A Hearth house running on a computer on your network.** The headset
  does not install or manage a backend.
- **visionOS 27 or later.** The persona's flame and face are built on APIs
  that do not exist before it.
- **The house's address and a pairing code**, entered once in a small
  window the app opens on first run. Pairing works the way it does on the
  phone -- a six-digit code shown on the house, exchanged once for a token
  the headset keeps. See [Hearth on iOS](ios.md#how-pairing-works).
- **The house reachable across the network**, which by default it is not.
  A house listens only on its own machine until you open its bind.

## What it cannot do yet

- **The persona does not walk the room.** It travels between places within
  a scene, and it goes to the shelves to consult a journal, but room-scale
  movement is not built.
- **Persona and Apps are unreachable in the room.** Both surfaces work in
  the volume; in the immersive space they have nowhere to be shown yet.
- **No away-from-home access.** Reaching a house from outside your own
  network is planned, not built.
- **One house.** There is no directory of houses and no cloud account. Several
  people and their personas working together is a real goal, and a long way
  off.

## A note on what this is for

The design decision underneath all of the above is that the persona is a
presence in a room rather than an interface in a window. That is why the
box is the resting state rather than the destination, why the fire lights
your actual walls, why your sofa hides it, why a wall stops it, and why the
journal is a shelf you reach for rather than a list you scroll.

None of that makes the headset a better place to read a transcript than the
phone. It makes it a better place for the house to be somewhere, rather
than something you open.
