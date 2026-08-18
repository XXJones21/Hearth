# Phase 3.5 -- finishing the volumetric window

The volume is nearly done and the immersive house is a different kind of work.
These are the things that should be true of the box before phase 4 starts,
collected 2026-08-17 after gate 3.

Phase 4 assumes a working volume: design section 1 has the main volume
DISMISSING when the immersive house opens and returning on exit, so anything
broken here is broken in both places and harder to see in one of them.

## 1. Persona, Apps and Settings render blank -- LANDED 2026-08-18

Pressing those three on the button shelf opens a panel whose content area is
empty. Journal is fine (it is the library, and not a panel at all).

**What it turned out to be.** The device disproved the "blank" reading: the
menus DO render, and a glossy glass panel stands in FRONT of them and swallows
every pinch aimed at the content. Same cause, worse symptom -- visionOS draws
the navigation container's own material as a slab, and in an attachment there is
nothing behind it to be the window it thinks it is decorating.

The hypothesis below was right about the cause and wrong about the effect, which
is worth keeping written down: "blank" was the report, and had the fix been
aimed at emptiness rather than at chrome it would have missed.

**Hypothesis as first written, and it wanted confirming before anything was
rewritten.** All four
shared surfaces -- Sessions too, which may be equally blank and simply was not
tried -- are built the same way: a `NavigationStack`, a `.toolbar` carrying a
"Hearth" back button, and `toolbarBackground(_:for: .navigationBar)`. That is a
phone's chrome. In a RealityView ATTACHMENT there is no navigation bar to give
a background to, no presentation for `dismiss` to pop, and a navigation
container may not lay out at all without a window to fill.

It is unlikely to be the data. Each of those views renders something while
loading -- "Asking the house who lives here...", a toolsOff banner, an
unavailable note -- so a failed fetch would show a message, not nothing.

**First diagnostics, cheapest first:**
- Put a plain `Text("hello")` in place of `content` in `HouseSurfacePanel`. If
  that renders, the panel and the attachment are fine and the shared views are
  the problem.
- Then render one surface's body WITHOUT its `NavigationStack` wrapper. If that
  renders, the navigation container is the cause and the fix is structural.
- Read the device console for layout complaints:
  `xcrun devicectl device console | grep -i -E "navigation|constraint"`.

**If the hypothesis holds, the fix is a split, not a fork.** Each surface grows
a body that renders without navigation chrome, and the phone keeps wrapping it
in the `NavigationStack` and toolbar it needs. Both clients keep one
implementation of what a settings screen SAYS; only the shell differs. That is
the same line phase 0 drew when the surfaces moved into HearthUI, and the same
one `hearthNavigationTitleInline()` already walks for one modifier.

What must NOT happen is a Vision-shaped copy of Settings. That is the second
settings screen to keep in step, and it will drift within a month.

**The fix, as built.** `HearthUI/Surfaces/SurfaceChrome.swift`. Chrome became a
choice the HOST makes rather than something each view assumes:

- `HearthSurfaceChrome` in the environment, `.navigation` by default so the
  phone is untouched, `.bare` for anything hosting a surface in an attachment.
- `HearthSurfaceShell` wraps each surface's body. In `.navigation` it draws the
  `NavigationStack`, the "Hearth" back button and the parchment toolbar exactly
  as before; in `.bare` it draws the body and nothing else.
- Trailing controls survive the switch. Apps' "Cards" button is the only one,
  and it is the sole way to reach the card library, so `.bare` gives it a strip
  above the content rather than dropping it with the toolbar.
- `hearthSurfaceClose` in the environment answers item 3's first bullet: the
  volume passes down the closure that took the panel off screen, so "New
  session" and "Resume" in `SessionsView` put the panel away instead of calling
  a `dismiss` with no presentation to pop.

It is a presentation choice, not a platform check -- nothing in the file reads
`os(visionOS)` -- so a phone that later shows a surface inside a sheet can ask
for `.bare` too.

## 2. The right rail -- LANDED 2026-08-18

The desktop's `AppFrame` is three slots -- persona left, view centre, rail
right -- and the volume currently implements two of them. `Rail.tsx` carries
Sessions, Memory and Routines as tabs.

Wanted: a control on the button shelf, set apart from the five destinations by
a deliberate gap, that toggles a rail docked to the RIGHT of the volume. Not a
sixth destination in the same row -- it is a different KIND of thing, a panel
that coexists with whatever is in the centre rather than replacing it, and the
gap is what says so.

Open questions worth settling before building:
- **Sessions is already a shelf destination.** The desktop rail's first tab is
  Sessions, so putting it in both places would be the same content twice. Either
  the rail takes it over and the shelf drops it, or the rail is Memory and
  Routines only.
- **Memory and Routines have no iOS surface yet.** The phone's shelf has five
  destinations and neither of these is among them, so this is new UI rather
  than reuse -- which makes it the one place in this phase where a
  Vision-shaped view is legitimate, because there is nothing to keep in step
  with.
- **Where the rail's width comes from.** The centre slot is a 560pt panel and
  the orb sits at `stageLeftX`; a rail on the right has to fit what is left of
  a box whose size the user controls. It should be authored against
  `designWidth` like everything else and let the stage root scale it.

**How they were settled, and what was built** (`Hearth Vision/Scenes/HouseRail.swift`):

- **A vertical shelf, not a shelf button.** Operator's call: the rail's tabs
  become their own button shelf on the RIGHT face, mirroring the bottom one --
  same icon size, same padding, same press-the-lit-one-to-close gesture. It is
  an `.ornament(attachmentAnchor: .scene(.trailing))`, so like the bottom shelf
  it hangs outside the box and costs the stage no width until a tab is opened.
  The earlier sketch -- a sixth control on the bottom shelf behind a gap -- is
  dropped; a rail that lives on the right should be reached from the right.
- **Sessions moved.** It is off `HouseSurface` entirely and is the rail's first
  tab, which is where the desktop has always kept it. The bottom shelf is four:
  Journal, Persona, Apps, Settings.
- **Memory is real.** `MemoryFactsLoader` in HearthCore reads `/journal/facts`
  and `MemoryTabView` in HearthUI renders it -- placed in the shared library
  rather than the Vision target so the phone can adopt a rail without a move.
- **Routines is honest.** The desktop's `RoutinesTab` renders three rows from a
  `const routines` literal in the client: not read from the house, toggles write
  nothing, no route behind them. Porting them would show someone a schedule the
  house has never agreed to keep -- the same fault the desktop Memory tab was
  corrected for on 2026-08-05. So the tab exists and says there is nothing yet.
- **The width comes from the squeeze, not from a guess.** Opening the rail takes
  its width out of the centre slot the way the desktop's grid column does: the
  panel narrows 560 -> 440pt and slides left, the orb steps from `stageLeftX` to
  `stageLeftXWithRail`, and the library moves with the centre slot because it IS
  the centre slot for Journal. All of it is authored against `designWidth` and
  scaled by `stageRoot`, so it survives a resize.
- **One `slideStage()`, not two closures.** Two switches -- a destination and a
  rail tab -- make four combinations, and two independent `onChange` handlers
  would each be right about their own half and wrong about the other's.

Still to judge on the device: whether 440pt is enough for Persona's editors, and
whether the rail wants to be reachable while the immersive house is open (phase
4 dismisses this volume).

## 3. The app icon -- LANDED 2026-08-18

The Vision target shipped with Xcode's empty `AppIcon.solidimagestack`: three
layers, no images. Wanted the phone's icon, which is a flat hearth in the brand
palette.

A visionOS icon is not one image but three, masked to a circle and parallaxed
against each other, so the phone's single PNG had to be SPLIT rather than
resized. The art is flat vector with a five-colour palette, so the split is by
colour -- and the whole difficulty is at the edges, where a pixel is a blend of
two colours that may belong to different planes. Rounding a blend to whichever
colour it sits nearest was the first cut and it was visibly wrong: a blend of
brick and mortar lands nearest to the FLAME colour, which threaded fire along
every mortar line in the wall. Each blend is now divided between its two planes
by how much of each it holds.

The planes:

- **Back** is flat cream (`#FAF4EA`), the mortar's own colour, so the wall sits
  on the same paper its lines are cut from and the system has an opaque plate
  to mask.
- **Middle** is the brick wall and the dark firebox and hearthstone.
- **Front** is the flame, its pale inner tongue, and the log. The last two are
  the mortar and brick colours respectively, told apart from the wall by falling
  inside the flame's own bounding box -- there is nothing else brick-coloured in
  there, because the firebox surrounds it.

The drawing is scaled to 0.94 of the circle's radius about its content centre,
measured rather than guessed: a square illustration in a round hole loses its
corners otherwise.

The generator is `scratchpad/icon/layers.swift` -- CoreGraphics, no Pillow or
ImageMagick on this machine. It is a one-shot and is not in the repo; the three
1024x1024 PNGs it produced are. If the phone's icon changes, re-run it rather
than hand-editing the layers.

## 4. Persona switching from the status ornament -- LANDED 2026-08-18

The top ornament already named the live persona, so switching became that label
turning into a menu rather than a new control somewhere else. It is the phone's
arrangement in a shorter space: `HouseShelf` lists the personas above the
destinations with a tick on the live one and switches on tap; there is no drawer
in a volume, so the name already on screen carries the list.

- `viewModel.switchPersona(name)`, which is the same call the phone's drawer
  makes. Live session, writes nothing.
- The tick follows `selectedPersona`, as the phone's rows do.
- It is only a menu when there is something to choose -- connected, and more
  than one persona. A menu that opens onto one disabled row is a control that
  lied about being one.

Worth keeping straight: this is NOT Settings' "Start with", which pins a persona
for the next connect via `ClientPrefs.startPersona`. Two controls, two
timescales, and they should stay distinguishable.

## 5. Smaller things, if they are cheap

- ~~The panel's inherited "Hearth" back button is inert in an attachment.~~
  DONE with item 1, and both ways at once: the button goes with the navigation
  shell in `.bare`, and `hearthSurfaceClose` gives the in-content calls a way
  out that works.
- The status ornament reads only connection and persona name. The desktop shows
  more of the house's state and there is room for it.
