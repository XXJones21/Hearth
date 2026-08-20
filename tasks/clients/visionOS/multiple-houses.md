---
area: clients/visionOS
status: open
depends_on: []
blocks: []
updated: 2026-08-20
---

# More than one house

`ServerConfig.shared` holds one address and one token. There is no directory of
houses, no switcher, and no cloud account tying a headset to a house.

## This is a deliberate position, not an oversight

Every client article says the same thing and says it as a feature: one headset,
one house, on your own network, no third party. The absence of a directory is
what makes the product's claim about ownership true rather than marketed.

So the file exists to hold the question, not to argue for the answer. **Nothing
should be built here until somebody wants two houses for a real reason**, and
the two real reasons that have surfaced are worth writing down before they get
confused with each other:

1. **A person with a house at home and a house at work.** Two machines, one
   person, genuinely separate. Wants a switcher.
2. **A person MOVING their house between machines.** One house, two addresses
   over time. Wants nothing -- it wants Settings to accept a new address, which
   it already does.

The second is much more common and is already solved. Building a directory to
serve it would be building the wrong thing.

## What it would touch if it happened

- **`ServerConfig.shared`** becomes a selection over a set. It is a static on a
  non-`Sendable` class today, and it is already the reason the shared package
  stayed on Swift 5 rather than adopting Swift 6 -- so this is the change that
  drags the concurrency audit with it.
- **Pairing** is per-house already: a token is issued by a house and hashed on
  that house. N houses is N tokens, which the token model handles without
  change.
- **Personas** belong to houses. A switcher means the persona on stage changes
  when the house does, and the anchored placements in the room were made for a
  persona that may not exist in the other house.
- **The room's memory.** `RoomAnchors` remembers where things were left. Whether
  those placements are per-house or per-room is a real question with no obvious
  answer -- the shelf is a fact about your room, but the library on it is a fact
  about your house.

## Open questions

- Is switching houses a mode, or is it just a re-pair? Re-pairing is one screen
  and no new concepts, and for the "home and work" case it may be enough.
- If a switcher exists, does the immersive space survive the switch, or does
  crossing houses close the room? Closing it is more honest.
