---
area: clients/visionOS
status: open
depends_on: []
blocks: []
updated: 2026-08-20
---

# More than one persona in the room

Sulivan and Selene in the immersive space at the same time, each with its own
configuration, its own visualization, its own place in the room.

The operator's framing: *"this last one opens the doors to a bunch of ideas."*
So this file is scoped as an ENABLER rather than as a feature, and the test of
the work is not "two personas appear" but "adding a third costs nothing."

## Why this is closer than it looks

`PersonaRig` is already an instance rather than a singleton. It owns its own
entities, its own palette, its own face texture and director, its own behaviour
director, its own particle choreography, its own flame. Nothing in it is static
except tuning constants. It was built that way for phase 4's round trip, where
the rig had to survive being re-parented between two scenes, and the same
property is what makes a second one possible.

What is a singleton is everything AROUND it:

- **`@StateObject private var rig`** on the app, one instance, handed to both
  scene hosts. That is correct today and is the thing that has to become a
  collection.
- **`FaceFeed.shared`**, which the face director reads for cues and speech
  level. One feed means every persona blinks on the same cue and mouths the
  same audio.
- **`ChatViewModel`**, which owns the turn, the audio and the transcript. One
  conversation, one speaker.
- **`RoomAnchors`**, keyed by a `RoomSlot` enum with exactly two cases,
  `persona` and `library`.
- **`ServerConfig.shared`**, which is fine -- one house is one house.

## Who is talking: answered

This looked like the hard part and is not, because the client already knows.

**You have to pinch a persona to talk to it.** That pinch names an entity, the
entity belongs to a rig, and the rig knows which persona it is wearing. The
addressee is therefore decided at the moment the turn starts, on the client,
with no guessing and no heuristic.

All that is missing is that the information is currently thrown away.
`ChatViewModel` sends a message with no persona on it, because until now the
answer was always "the one on screen". **The work is a persona field on the
outbound message**, which is a small addition to what the client sends and a
small addition to what the house reads.

That single field settles the rest of it by construction:

- **The reply comes back attributed**, so no persona lip-syncs another's words.
- **The house knows who was addressed**, which is what it needs anyway the
  moment personas differ in prompt, memory or tools.
- **Cards land on the persona that produced them**, which is the rule
  ([_index.md](_index.md)) finally having something to be a rule about.

What is still open is not the addressing but the ETIQUETTE: whether an
un-addressed persona listens, reacts, or idles. A persona that visibly attends
to a conversation it is not in is a much better idea than one that freezes, and
it is also much harder -- it wants a state the rig does not have yet.

## What it would touch

- **`RoomSlot`** becomes identified rather than enumerated -- a persona's slot
  keyed by its persona id, so N personas remember N places.
- **`FaceFeed`** becomes per-persona, or gains an addressee. It is shared with
  the phone, so this is a package change, not a Vision one.
- **The rig collection** replaces the single `@StateObject`, and the scene hosts
  iterate rather than reference.
- **Gesture targeting** already survives this: phase 4.5 learned the hard way
  that `targetedToEntity` NAMES a target without REQUIRING one, and the fix was
  explicit checks against the entity that was actually hit. That fix is what
  makes two grabbable personas safe.
- **The effect budget.** Two flames is two point lights, two Metal kernels, two
  particle systems and possibly two proximity spotlights. `EffectBudget` already
  has `particleDensity` and `lightScale`; it will need to know how many personas
  are sharing the frame. The thermal answer may be that only the ADDRESSED
  persona gets the full rig.

## What must not happen

**Personas must not become a client concept.** A persona is a file on the house,
and which effects it gets is decided by its visualization KIND, never by its
name -- that rule is what makes a new persona arrive already dressed correctly.
Two personas in a room is a rendering arrangement; it must not become a place
where the client starts knowing things about Sulivan and Selene specifically.

## Open questions

- Whether two personas share one conversation or whether each gets a session.
  The house has sessions already; that may be the seam.
- What the un-addressed persona DOES while another is speaking. Idle is the safe
  answer and a dull one; attending is the good one and needs a rig state that
  does not exist.
- Whether personas can address EACH OTHER, which is where
  [neighborhoods.md](neighborhoods.md) is heading and is out of scope here.
