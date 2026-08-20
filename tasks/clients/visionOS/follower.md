---
area: clients/visionOS
status: scoped
depends_on: [motion-room-scale.md]
blocks: []
updated: 2026-08-20
---

# It comes with you

The persona keeps a comfortable distance and follows as you move around a space
or between rooms.

**The model is a puppy, not a HUD.** It does not need to be in view at all
times, it does not need to hold a position relative to your gaze, and it is
allowed to fall behind and catch up. Something that stays pinned in front of you
is an interface element; something that trails you is a companion.

This is also why cards stay rooted to the persona rather than following you
themselves. If something should come with you, the thing that should come with
you is the persona -- and everything it is holding comes too, without any of it
needing its own opinion about where you are.

## The house turns it on, not a setting

The trigger is a spoken request -- *"can you follow me?"* -- which makes this a
BEHAVIOUR rather than a client mode. That matters more than it sounds:

- `BehaviorDirector` already runs named behaviours from house cues, with a
  library a host may extend. Following is another entry in it, not a new system.
- A toggle in Settings would be the wrong shape. Whether the persona follows you
  is part of the conversation, and asking it to stop should work the same way
  asking it to start did.
- It means the client does not decide. The persona follows because it was asked,
  which is the same rule everything else here obeys: the house owns intent, the
  client owns rendering.

## Apple has published the technique

[Displaying an entity that follows a person's view](https://developer.apple.com/documentation/visionos/displaying-a-3D-object-that-moves-to-stay-in-a-person's-view)
is the sample, and it is close to a drop-in because it is built from parts this
project already has:

```swift
root.components.set(ClosureComponent { deltaTime in
    guard let currentTransform = headTracker.originFromDeviceTransform() else { return }
    let targetPosition = currentTransform.translation() - distance * currentTransform.forward()
    let ratio = Float(pow(0.96, deltaTime / (16 * 1E-3)))
    let newPosition = ratio * entity.position(relativeTo: nil) + (1 - ratio) * targetPosition
    entity.setPosition(newPosition, relativeTo: nil)
})
```

Three of those four lines already exist here in some form. `ClosureComponent` is
ours. `RoomAnchors.viewerTransform()` is `originFromDeviceTransform()` --
`queryDeviceAnchor` with an `isTracked` check, already used to make the persona
face you. And `pow(0.96, dt / 16ms)` is exactly the frame-rate-independent
retention the proximity spotlight's aim already uses; the rig has two of those
constants in it.

**The one caveat Apple states, and it decides the scope:** *"Device-tracking
data isn't available in visionOS apps that only display a SwiftUI window view or
a SwiftUI volumetric view."* Following is therefore immersive-only by platform
constraint, not by preference. In the volume the persona is in a box the size of
a desk toy and following is meaningless anyway -- but it is worth knowing that
it is impossible rather than merely unnecessary.

## Where it differs from the sample

The sample keeps a sphere in front of your face. A companion must not.

- **Translation, not rotation.** Following head rotation is what makes a
  follower nauseating: the thing orbits you every time you look around. The
  target must be derived from where you ARE, with your facing used at most to
  choose a side. This is the same axis lesson the billboard already taught --
  freeing the wrong axis is what made a tiny Selene on the floor look like an
  exorcism.
- **Beside and behind, not in front.** In front of you is where an obstacle
  stands.
- **A dead zone**, so it settles instead of creeping. The sample has none
  because a HUD element should never settle.
- **A speed cap**, so it never outruns a walk and never teleports. Fall behind
  and catch up is correct; snapping is not.
- **The floor and the walls.** The sample's target is a point in mid-air. Ours
  has to be clamped by the same scene mesh that already stops the persona being
  shoved through a wall, and has to respect `floorClearance`, which differs by
  persona kind. That clamp is [motion-room-scale.md](motion-room-scale.md)'s
  work, which is why this depends on it.

## The anchoring conflict

Everything else in the room is anchored: the library remembers its shelf, the
persona remembers where it was set down, and both return next launch. A follower
gives that up.

The two must be a CHOICE rather than a race, or a persona that is both anchored
and following will fight itself the first time you walk away. Planting it again
is already a gesture people have -- drag it somewhere -- so ending a follow may
need no new interaction at all.

## Open questions

- **Doorways.** The scene mesh is continuous, so "between rooms" is not a
  different problem to the app, but pathing through a door is a real one. The
  honest first version may be that it stops at the threshold and rejoins you
  when you come back into view.
- **What it does when it arrives.** A persona that follows you and then stands
  there is a persona waiting to be told something. It may want its own resting
  behaviour while following.
- **The proximity spotlight** was tuned for a persona that stays put. A follower
  is constantly near new surfaces, and the aim easing may need to be slower.
