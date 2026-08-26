---
area: clients/visionOS
status: closed
depends_on: []
blocks: []
updated: 2026-08-18
---

# Phase 4 -- the immersive house

**CLOSED 2026-08-18. Gate 4 passed on device, with both persona kinds.**

The room exists and is usable: the persona crosses at the spot she was standing,
carries her work with her, wears her controls, and remembers where you put
things. Sections below are marked with what landed and what was deliberately
left -- see the design doc's phase 4 entry for the four lessons worth carrying
into 4.5.

Scoped 2026-08-18, after phase 3.5 closed. This supersedes the phase 4 sketch in
[the design doc](../../../wiki/raw/hearth-vision-design.md) section 8, which is now a
summary pointing here.

The sketch was written on 2026-08-17, before the volume had been built. Two of
its assumptions are now false, and both change the work rather than merely
adding to it.

## What changed under it

**The persona may have a body.** Phase 3.5 taught `PersonaRig` to dispatch on
`visualization.type`, so Selene renders as a `glb_animated` model where Sulivan
renders as a bead with a compute face. Everything the sketch assumed about the
orb -- that it is small, that it hovers at a comfortable height, that a halo
blooms around it -- is true of one of them and false of the other.

**The volume grew a full client interface, and all of it is ornaments.** House
status (and, since 3.5, persona switching), the composer and its mic, the
four-icon house shelf, and the right rail are every one of them ornaments on a
window. An `ImmersiveSpace` has no ornaments. Design section 1 says the volume
DISMISSES when the room opens -- which, as things stand, would leave a persona
in a room with no way to reach anything at all.

**Three things were built for this phase already, and should not be rebuilt.**
`modelPresentationScale` (1.0) and `modelVerticalOffset` (0) both default to the
room's own answer, so the immersive host is correct by saying nothing -- it must
simply not copy the volume's 0.4 and 0.16. And `personaAnchor` is how work
travels with the persona; `CardOrbitLayout.offsetFromOrb` has its caller.

## 1. The scene and the handover

Declare the `ImmersiveSpace(.mixed)` on `SceneID.immersiveHouse`, which is
already named in `HearthVisionApp`. The rig and the view model are already
hoisted to app level for exactly this, so the handover is a re-parent rather
than a rebuild.

Second, smaller: `MainVolume` holds `stageRoot`, `libraryEntity` and
`propLibrary` as `@State`. Those do NOT survive the volume dismissing, so
returning from the room rebuilds the library and re-fetches it. Acceptable, but
it means the return trip is not free and the journal's scroll position is lost.

### The tick, and why it is not a re-subscribe -- DONE 2026-08-18

The hazard is real. `rig.updateSubscription` holds a
`content.subscribe(to: SceneEvents.Update.self)` taken from the VOLUME's
content, and a subscription belongs to the scene that issued it. Apple's own
example stores that subscription in `@State` on the view -- its lifetime is
meant to match the host. Ours is stored on the rig, which outlives the host by
design, and nothing cancels it. When the volume dismisses, the rig stops
ticking: no face, no travel, no particles, no error. The persona freezes.

The obvious fix -- each host takes its own subscription and releases it on the
way out -- works and is wrong, because it makes every future host responsible
for a lifecycle it cannot see, and a brief overlap ticks the rig twice a frame.

**A registered `System` has no such problem.** From the docs: "register your
system with RealityKit by calling `registerSystem()`. RealityKit automatically
creates an instance of every registered system for every scene." So a system
keyed on a component the rig root carries runs in WHATEVER scene the rig is
currently in, and the handover costs nothing at all -- no host holds anything,
nothing needs releasing, and there is no window in which two hosts both tick.

**And Apple has already written the shape of it.** `ClosureComponent` in the
head-tracking sample is NOT a framework type -- it is about twenty lines of
sample source, and the painting-space sample shows both halves:

```swift
struct ClosureComponent: Component {
    let closure: (TimeInterval) -> Void
    init(closure: @escaping (TimeInterval) -> Void) {
        self.closure = closure
        ClosureSystem.registerSystem()
    }
}

struct ClosureSystem: System {
    static let query = EntityQuery(where: .has(ClosureComponent.self))
    init(scene: RealityKit.Scene) {}
    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            entity.components[ClosureComponent.self]?.closure(context.deltaTime)
        }
    }
}
```

Write that once and both jobs are done: the rig's tick becomes a
`ClosureComponent` on the rig root, and the follow below becomes another one on
each follower. Registering from the component's own initializer is what removes
the last thing a host had to remember.

One thing it does NOT carry across, and this is an improvement rather than a
cost: the volume's subscription closure also polls
`rig.apply(viewModel.personaPalette)`, `rig.apply(visualization:)` and
`rig.apply(faceGeometry:)` sixty times a second, because there was no observer
to hand. Those are view-model reads and belong in `onChange` handlers on the
host, where they will fire when the value actually changes.

## 2. Where the persona stands, and how big

In the volume this is settled and wrong for a room: the rig sits at
`CardOrbitLayout.orbY` (-0.22, low in the box so it can be set on a table),
scaled to 0.22, with a model at 0.4 of life size lifted 16cm to clear the
ornaments.

In a room, every one of those numbers is a different question:

- **The bead.** At the volume's 0.22 rig scale it is about 10cm across. In a
  room that is a marble on the floor. It has to grow, and how much is a
  judgement nobody has made yet.
- **The figure.** `modelPresentationScale` 1.0 makes Selene 1.34m, which is
  right -- and means she needs a FLOOR to stand on rather than a height above
  the box's centre.
- **Home.** `rig.homePosition` is currently a point in a box. In a room it wants
  to be floor-relative and in front of the person at a conversational distance,
  which is what world sensing (section 6) is for.

## 3. Controls without ornaments -- BUILT 2026-08-18 (spawn-and-anchor still to come)

Operator's call, and it is better than any of the three options first written
here: **the controls attach to the PERSONA, not to a window and not to the
room.** They become part of whoever is on stage, which is the same move already
made for cards and the caption, and `personaAnchor` is already where they hang.

The shape:

- **Two shelves, left and right of the persona, about 30cm each way.** The
  bottom shelf's four destinations go left; the rail's three tabs go right. They
  stop being edges of a box and become things beside a person, which is why this
  survives the box going away.
- **Mostly hidden until looked at.** They fade up on hover and fade back down,
  so the room holds a persona rather than a persona and a control panel.
- **Pinch an icon and drag it off the shelf to spawn it**, then leave it
  somewhere in the room, where it anchors and stays. A journal pulled off the
  shelf and set on a real table is the room's version of opening a panel.

### What the platform will and will not give us

**The hover reveal works, and SwiftUI is the cheaper path.** `CustomHoverEffect`
does exactly this, from Apple's own example:

```swift
content.hoverEffect { effect, isActive, proxy in
    effect.animation(.easeOut) { $0.opacity(isActive ? 1 : 0.5) }
}
```

and `hoverEffectGroup()` makes a whole shelf light as one -- "hovering anywhere
over the view will activate the hoverEffects added to" every descendant. So a
look anywhere near the shelf brings all of its icons up together, which is the
behaviour wanted and not merely an approximation of it.

Keeping the shelves as SwiftUI attachments parented to `personaAnchor` is
therefore the recommendation. The RealityKit route exists --
`HoverEffectComponent`, which needs `InputTargetComponent` and
`CollisionComponent` and applies down the whole entity hierarchy -- but its
`.shader` style, the one that could fade real geometry in as ITSELF, requires a
`ShaderGraphMaterial` authored in Reality Composer Pro. This project has no RCP
package and builds every material in code. The built-in `.highlight` style with
`opacityFunction: .full` can reveal a fully transparent entity, but as a
coloured glow rather than as its own artwork.

**The constraint to design around: the app can never know the shelf is
showing.** From the docs: hover effects "may be applied to a view
out-of-process. Therefore an effect's current phase may not be visible within
your app." Gaze is private and there is no API that reports it. Two
consequences:

- The fade is purely presentational. The buttons stay hit-testable at opacity
  zero, and that is fine on visionOS because a pinch lands where you are
  looking -- but no app logic can branch on "the shelf is open", so nothing else
  may depend on it.
- Anything that must actually toggle -- and the pinch-drag-to-spawn does -- has
  to be driven by a gesture, not by the hover.

**Anchoring a spawned panel has two different costs**, and they are worth
separating before either is promised:

- **Stays put for this session**: `AnchorEntity(world:)` fixes a transform in
  the scene. No world sensing, no usage description, no ARKit session. This is
  enough for "pull the journal out and leave it beside you".
- **Stays put on that table, or across launches**: `AnchorEntity(.plane(...))`
  via `SpatialTrackingSession`, which is RealityKit's managed path -- it keeps
  the anchor aligned without the app running ARKit itself. This is what needs
  `NSWorldSensingUsageDescription`, and persistence across launches needs ARKit
  world anchors on top.

Recommend the first for phase 4 and the second only if the device run says the
panels want to belong to furniture. Shipping a usage-description key for a
capability that is not used is exactly what the gates script exists to catch.

**What landed 2026-08-18, and what did not.** Both shelves exist, hang off
`personaAnchor`, and open the same panels the box opens. Persona switching is on
the left. The hover-reveal is `CustomHoverEffect` plus `hoverEffectGroup()`,
resting at 0.14 rather than zero -- invisible until looked at means invisible
until GUESSED at, and a faint presence is a thing you can learn the position of
once and then find.

**Pull-out, and the bookcase it was designed for.** The journal is not a panel
and never was: its centre slot is a BOOKCASE, and that is the case the whole
pull-out gesture was imagined around. Pinch the journal icon, drag away from the
shelf, and once the grab has left the icon behind the library is spawned into
the room -- life size, standing on the floor, draggable to wherever you want it,
with an X off its left edge to put it away.

Three things that fall out of it being furniture rather than a panel:

- **It is parented to the ROOM, not to the persona.** Everything else the
  shelves open is work she is showing you and belongs beside her. A bookcase is
  a thing you put somewhere and walk to, and it is still there when she has
  moved across the room.
- **`presentationScale` finally does what it was built for.** The geometry has
  always been authored at 21cm books; the box showed it at 0.765 and a real
  floor shows it at 1.
- **Clipping and scrolling both come OFF, and one nil does both.**
  `clipBelowInParent` existed because a volume has a composer along its bottom
  edge, and the drag existed because a bookcase taller than the box could not
  otherwise be seen. On a real floor you walk to it and you look up. Setting it
  nil also takes `maxScroll` to zero, so the same `dragSurface` that scrolled
  the shelves in a box now moves the whole bookcase in a room -- one grabbable
  surface, two hosts, two meanings.

Still not built: ANCHORING what has been placed, so a bookcase left beside the
sofa is beside the sofa tomorrow. That is the world-anchor work in section 9,
and the same mechanism will serve every other thing pulled off a shelf.

### What still has no home

**Persona switching: SETTLED 2026-08-18.** It goes on the LEFT shelf, beside the
four destinations. It was on the status ornament in the box because the status
strip was already naming the persona and a menu on that name cost nothing; in a
room there is no strip, and switching is a thing you go and do rather than a
thing you notice. The left shelf is where going and doing lives.

Still homeless: the connection status, and the mic.

- **Status** may not need a home at all. A house that is not answering is
  already visible in the persona herself -- `setConnected` draws the dead look,
  and in a room that is a bead gone cold in front of you rather than a dot in a
  strip. Worth trying nothing before building something.
- ~~**The mic**~~ SETTLED 2026-08-18, and it turned out not to be about the mic.
  A headset has no keyboard and no controller, so speech is the way in and
  typing is the ACCESSIBILITY path rather than the convenience one. The existing
  `stageTypingBar` preference already says who needs it; the room just spends it
  differently. Off, a tap starts a turn. On, the SAME tap raises a composer with
  the keyboard already focused -- one gesture meaning one thing, "I want to say
  something", through whichever channel is available to the person making it.
  Instead of listening and never as well: someone typing because they cannot
  speak should not have a live microphone open while they do. The composer
  carries the mic, so the mic has a home whenever it has a reason to.

## 4. The toggle -- DONE 2026-08-18 (reposition still to come)

Pinch-and-hold for two seconds on the persona, both directions. The rig carries
the machinery already, dormant since the port: `transitionProgress` ramps the
switch flourish and `configure(for:)` swaps presentation mode.

Watch:

- The hold must target `rig.tapTarget`, which is now a computed property that
  changes with the persona. It is only correct if the gesture is rebuilt when
  `modelActive` changes -- which is why that flag is `@Published`.
- A plain pinch still starts a voice turn. Two gestures on one target, told
  apart by duration, is the same arbitration the library's scroll-versus-open
  needed and got wrong twice.
- `realBloomActive` swaps the billboard halo for a real bloom. That is a fact
  about a BEAD; a model persona has no halo and `configure(for:)` must not
  assume one. Verify what the switch actually does under a model before
  trusting it.

## 5. Choreography at room scale

`BehaviorDirector.motion` has been `.none` since 2026-08-17 by the operator's
call, and this is the phase to turn it on: the travel was always a room-scale
idea being tried in a box.

- Re-register the director's targets in the room's own metres. `shelf`, `cards`
  and home are all currently points in a 0.8m box.
- `.subtle` multiplies every offset by 0.45 and exists for the volume; the room
  is what `.full` was written for.
- **A figure that travels is not a bead that travels.** The director moves and
  yaws `rootEntity`; a bead has no wrong way up, and a walking clip is not what
  it plays. Whether a model should travel at all in v1, or stand and turn, is
  worth deciding before tuning numbers.
### Following, INVESTIGATED 2026-08-18

Section 6 asks for cards that follow "with a soft spring lag" and that
"billboard toward the user". `personaAnchor` delivered the first half of the
first clause -- work travels -- and neither of the others. Two findings:

**The lag does not exist, and neither does the billboard.** The anchor is a
plain child entity, so work is welded to the persona with zero lag. And
`BillboardComponent` appears exactly once in the codebase, on the rig's own glow
billboard; no card or caption has one. Both were invisible in a box where the
orb never moved. With motion on, at room scale, neither will be.

**The anchor inherits the rig's YAW, and that is probably wrong.** `update`
sets `rootEntity.orientation` from `behavior.yaw` so the painted face looks
where the persona looks. Work parented under it swings around her when she turns
to the shelf -- which for a caption you are mid-way through reading is the
"prose that slides while you are reading it" problem in its worst form. Position
should follow with lag; ORIENTATION should billboard to the viewer rather than
inherit hers.

**The smoothing is settled, and it is not a spring.** From the operator's own
Apple sample, "Displaying an entity that follows a person's view":

```swift
let ratio = Float(pow(0.96, deltaTime / (16 * 1E-3)))
let newPosition = ratio * sphere.position(relativeTo: nil) + (1 - ratio) * targetPosition
sphere.setPosition(newPosition, relativeTo: nil)
```

Exponential smoothing, made frame-rate independent by raising the per-frame
retention to `dt / 16ms`. One tunable, no overshoot, no oscillation, and no
velocity state to keep -- which is what "a natural smoothing effect" wants and
what a real spring, with its stiffness and damping to balance, does not give
without ringing. 0.96 is the reference number at 60Hz; lower is snappier.

So this is one job with three parts, and it rides the same `ClosureComponent`
as the tick: a follow closure per follower doing the lerp above against the
persona's world transform, plus `BillboardComponent` on the followers so they
face the viewer instead of inheriting her yaw. A component rather than a
parent-child weld is also what lets the volume keep the rigid behaviour it
already has, by simply not adding it.

## 6. World sensing

`NSWorldSensingUsageDescription` into the Vision plist, and the plist rule
stands: every key justifies itself. Wanted for the floor the persona stands on
and the wall the bookcase leans against. Scope it to what is actually used --
a key carried for a feature that never landed is the kind of thing the gates
script exists to catch.

## 7. The library in a room

`JournalLibraryEntity` was built for this and mostly already does it: the
geometry is authored at life size and `presentationScale` shows it smaller. In
a room the scale is 1.0 and it is a real bookcase.

What comes OFF rather than on: `clipBelowInParent` exists because a volume has
a composer along its bottom edge, and the drag-to-scroll exists because a
bookcase taller than the box cannot be seen otherwise. A bookcase standing on a
real floor needs neither -- you walk to it.

## 8. What Valinor's immersive scene already answers

Re-read 2026-08-18 at `~/Valinor/Apple Client/Valinor/Valinor/VisionOS/`.
`CausticsImmersiveView.swift` is 423 lines and is a working immersive scene for
this same orb, device-validated. Several things the design doc listed as phase 4
UNKNOWNS are settled there, and porting the answers is cheaper than rediscovering
them.

**Bloom is not a preference; it is the only place bloom exists.** From the
source: "visionOS only blooms in an immersive space (no effect in the volume /
shared space), which is why the orb falls back to emissive shells in the volume
and gets real bloom here." That is why `realBloomActive` exists at all. Settings
that were tuned on device: `BloomComponent` with `scope = .unbounded`,
`BloomSettingsComponent(strength: 0.9, threshold: 0.5)`. Scope matters --
`.hierarchical` blooms a bounded region and leaves a hard disc edge, which Apple
warns about; unbounded blooms the whole screen and the threshold is what keeps
the passthrough room out of it.

Still open for a MODEL persona: bloom is a fact about a bright bead. Selene has
no emissive shell to clear a threshold, so she likely gets no bloom and that is
correct rather than missing. The operator's rule -- non-corporeal personas get
effects, humanoid ones do not, for now -- is the guide, and it wants writing
into the rig as a property of the visualization kind rather than as a check at
each effect.

**World reconstruction is already written.** `CausticsSceneMesh`: an
`ARKitSession` running a `SceneReconstructionProvider`, turning each anchor into
`MeshResource(from: anchor)` on a `ModelEntity` with `OcclusionMaterial()`. The
mesh is invisible on purpose -- it shows passthrough and occludes virtual
content behind it without painting a surface. This is exactly what phase 4 needs
for attaching panels to tables and walls, and it confirms the
`NSWorldSensingUsageDescription` decision.

**The handover has a typed trap in it, already found once.**
`content.transform(from: .immersiveSpace, to: .scene)` returns a Spatial
`AffineTransform3D`, which is DOUBLE precision, while the orb-transplant maths
is `simd_float4x4`. Valinor's handoff lists the wrong assumption here as risk
point 1 and carries a conversion extension for it. The captured transform rides
between scenes on the view model (`pendingOrbTransform`), with a fallback
placement -- 1m up, 1m forward -- when the capture did not happen.

**`causticsRoot` is `personaAnchor`, arrived at independently.** Its comment:
"The unscaled anchor the spotlight + cards attach to at the orb's world spot, so
the orb's 0.22 scale doesn't shrink their offsets." Two codebases reaching the
same structure from opposite directions is the strongest argument the structure
is right.

**The gesture arbitration is solved and tuned.** One `DragGesture(minimumDistance: 0)`
on the persona carries all three meanings: a 2-second hold switches spaces, a
movement past `dragMoveThreshold` (0.03m) becomes a reposition, and anything
else is a tap. `floorClearance` (0.25m) stops the orb being dragged below the
floor. Phase 4's toggle should start from this rather than from a fresh
`LongPressGesture`.

## 9. Anchoring, and what Arena already learned

Read 2026-08-18 at `~/Arena/Arena/RedReality/Stadium/Scene/`. Arena places a
Pokemon arena on a real floor through ARKit plane detection and puts it back in
the same physical spot on the next launch. It is the same problem phase 4 has
for panels dragged off a shelf, solved once already, and several of its comments
are scars.

### The spot the persona crosses at -- DONE 2026-08-18

RealityKit's two named coordinate spaces do this without ARKit at all. `.scene`
has its origin at the centre-back of the volumetric window; `.immersiveSpace`
has its origin at the point on the ground below you. `transformMatrix(relativeTo:)`
converts between them and returns a `simd_float4x4` -- which sidesteps
`content.transform(from:to:)` entirely, whose double-precision
`AffineTransform3D` return is risk point 1 in Valinor's handoff.

**There is exactly one moment to call it.** `.immersiveSpace` only means
anything while a space is open, and it returns nil otherwise -- so the read
happens after `openImmersiveSpace` has returned and before the window is
dismissed, in the single instant both scenes are alive. The room's own view
therefore waits for the value rather than taking the rig on appear, or it would
have the entity a frame before it could be measured.

Only X and Z are carried. A captured Y is where she was inside a FLOATING BOX,
which is not where she belongs on a real floor -- a body has to stand on it, and
a bead has a height at which conversation happens. Height is the room's rule;
the spot is hers. A carried bead height is clamped, because a volume can be
dragged to the carpet or above head height.

### Persisting a placed thing -- BUILT 2026-08-18

Wanted for panels pulled off the shelf and left in the room. The shape, from
Apple's world-anchor docs and from Arena's working version:

- `WorldAnchor(originFromAnchorTransform:)` plus
  `worldTracking.addAnchor(_:)`. ARKit persists the anchor's UUID and pose, and
  redelivers it through `anchorUpdates` on later launches when the person is
  back in the same place.
- **ARKit persists the UUID and the pose and NOTHING ELSE.** What the anchor
  MEANS is ours to store -- which journal, which panel. A dictionary from anchor
  id to whatever it was carrying, saved beside the anchor.
- **The visionOS restore path is not the iOS one.** Arena's comment is explicit:
  it is `WorldTrackingProvider` redelivery matched by id, then
  `AnchorEntity(.world(transform:))` -- not `AnchorEntity(anchor:)` or
  `allAnchors`. Getting this wrong is a thing that silently never restores.
- Anchors are only redelivered for NEARBY places. Someone who opens Hearth in a
  different room gets nothing, and that is correct rather than broken.

**As built:** `RoomAnchors` runs the session and holds a `RoomSlot -> UUID` map
in UserDefaults, because ARKit keeps the id and the pose and nothing else.
Restoring is not a startup step -- an anchor arrives when ARKit recognises the
place, which may be seconds after the room opens or never -- so it is applied
whenever it turns up, and until then everything stands where it spawned. The
bookcase is STOOD UP by its own anchor rather than merely repositioned: a thing
left against a wall should be against that wall when you come back, without
being pulled off the shelf again first. Putting it away forgets the anchor, so
the room does not stand it back up tomorrow because it remembers a wall.

Degrades quietly on purpose. No world tracking in the simulator, and a person
may decline world sensing; in both cases the room still works and simply forgets
where things were. Refusing to open the immersive space over that would trade
the whole feature for one of its conveniences.

`NSWorldSensingUsageDescription` went in with this commit, which is what the
plist's own comment said the hold was waiting for -- and scoped to what is
actually used, since this is world tracking for anchors and not the scene
reconstruction that would let panels rest on real tables.

### Finding the floor, and the four traps in it

Arena's `noteFloor` is worth reading in full before writing our own:

- **Classification takes a beat, and the room is full of decoys.** ARKit reports
  big horizontal planes -- ceilings, tables, slivers -- before `.floor`
  classification resolves. Committing to the first horizontal plane drops
  content on the ceiling or at eye level. Arena commits ONLY to a
  `.floor`-classified plane, and falls back to the lowest horizontal plane seen
  after a three-second grace window.
- **visionOS plane geometry lies in the anchor's XY plane with a +Z normal.**
  Build debug quads with `generatePlane(width:height:)`, not `(width:depth:)`,
  which renders the floor standing up.
- **The immersive origin is at FLOOR level**, which Apple's docs also state and
  which Arena's code carries a corrected comment about: an earlier version
  assumed head height and buried the arena 1.35m underground. Our
  `ImmersiveHouse` already assumes floor level, and this is the confirmation.
- **Degrade deliberately.** `WorldTrackingProvider.isSupported` and
  `PlaneDetectionProvider.isSupported` are false in the simulator, and
  `session.requestAuthorization(for: [.worldSensing])` can be declined. Arena
  has a `.degraded` phase that drops the arena at a fixed spot ahead. Ours
  already has the equivalent: no capture means a sensible spot in front.

### Window life cycle, and the exit that is not ours

From "Handling the window life cycle with multiple scenes", and it found a bug
the day it was read: **a person can close any scene at any time.** Pressing the
Digital Crown out of the immersive space does not run our hold gesture, so the
app was left believing it was still in the room -- flag true, volume never
returning, and nothing on screen to bring it back with. The fix is
`onDisappear` on the immersive scene's root view, with the deliberate exit
clearing its flag BEFORE it awaits so the two paths can be told apart.

Other rules from the same doc, recorded because each is a trap:

- **Closing a window backgrounds it; it is only eliminated if another
  nonimmersive scene is open.** The last closed nonimmersive scene backgrounds
  WITHOUT receiving `onDisappear`. So when the volume dismisses for the room,
  it is probably backgrounded rather than destroyed -- which may mean its
  `@State` (and the journal's scroll position) survives the round trip after
  all. Worth checking on the device rather than assuming either way.
- **`dismissWindow(id:)` with no value dismisses every instance** of that scene.
  The volume is a `WindowGroup`, so this is what we want and would not be if we
  ever wanted two.
- **`restorationBehavior(.disabled)` and `defaultLaunchBehavior(.suppressed)`**
  for one-time scenes. Applied to the pairing window: restoring it would put a
  paired headset back in front of a form it has already filled in.
- **`@SceneStorage`** restores per-scene state across launches -- the open rail
  tab and the open destination are candidates, once the volume settles.

### No presentations in a room

Found on device 2026-08-18: **"Presentations are not currently supported in
Immersive contexts."** A `Menu` is a presentation, and so are sheets, popovers
and alerts -- in an immersive space they log that line and show nothing at all.

The persona switcher was a `Menu` and is now an unrolling section of the shelf
itself: pressing the dot grows the shelf downward into the persona list, which
is the same list in the same place without asking the system to present
anything.

**Still outstanding, and each is a control that will do nothing if pressed in
the room:** `PersonaView`'s prompt editor and colour picker, and `AppsView`'s
card library, all of which are `.sheet`. They work in the volume and are dead in
the room. The fix should follow the doctrine the settings rows already use -- a
capability the host declares rather than a platform check at each call site --
so a surface can ask whether presentations are available and offer a different
route, or withhold the control, rather than showing one that silently fails.

### Controls in a room, revisited

Two Apple samples bear on the shelves, and they change the options written in
section 3:

- **`ViewAttachmentComponent`** puts a SwiftUI view on an ENTITY as a component,
  rather than through a `RealityView`'s attachments closure. That is what the
  persona-mounted shelves want: they hang off `personaAnchor` as entities and
  carry their own SwiftUI, which means the existing shelf views port nearly
  unchanged and the hover-reveal keeps working.
- **`pushWindow`** associates a window with an immersive space so closing either
  closes both -- the alternative shape, if some surface turns out to want a real
  window rather than a panel on the persona.

## Gate 4

The immersive round trip: hold to enter, the room furnishes, hold to leave, the
volume returns.

Extended, because phase 3.5 changed what is being re-hosted: **the round trip
must pass with BOTH persona kinds.** A bead and a figure travel through the same
handover code and fail differently -- the bead is small and hovers, the figure
is large and stands, and only one of them has a model whose loader holds tasks
that a scene teardown does not cancel.

## What not to do

- **Do not fork `MainVolume`.** The immersive host is a different stage for the
  same world, not a copy of the volume with the box taken out. Everything in
  `MainVolume` that is not placement is either the rig's or the app's.
- **Do not let the immersive host own the rig.** It is `@StateObject` on the app
  for the exact reason that phase 4 exists; a host that owns it destroys it at
  the moment the design asks it to travel.
- **Do not copy the volume's presentation numbers.** `modelPresentationScale`
  0.4, `modelVerticalOffset` 0.16, `presentationScale` 0.765 and `clipFloorY`
  are all facts about a box with ornaments along its bottom edge. The rig's and
  the library's defaults are the room's answer.
