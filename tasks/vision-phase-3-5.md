# Phase 3.5 -- finishing the volumetric window

The volume is nearly done and the immersive house is a different kind of work.
These are the things that should be true of the box before phase 4 starts,
collected 2026-08-17 after gate 3.

Phase 4 assumes a working volume: design section 1 has the main volume
DISMISSING when the immersive house opens and returning on exit, so anything
broken here is broken in both places and harder to see in one of them.

## 1. Persona, Apps and Settings render blank

Pressing those three on the button shelf opens a panel whose content area is
empty. Journal is fine (it is the library, and not a panel at all).

**Hypothesis, and it wants confirming before anything is rewritten.** All four
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

## 2. The right rail

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

## 3. Smaller things, if they are cheap

- The panel's inherited "Hearth" back button is inert in an attachment -- it
  calls `dismiss`, which has no presentation to pop. Either an environment flag
  the shared views consult, or it disappears with the navigation shell when
  item 1 is fixed. Probably the latter, for free.
- The status ornament reads only connection and persona name. The desktop shows
  more of the house's state and there is room for it.
