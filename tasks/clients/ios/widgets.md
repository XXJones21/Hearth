---
area: clients/ios
status: open
updated: 2026-09-02
---

# Home-screen widgets

Filed 2026-09-02 after a widget was placed on a phone and showed Xcode's
template body: "Time: 5:45 PM, Favorite Emoji". The Hearth WidgetExtension
target exists and builds, but its four source files are the ones Xcode
generated on 2026-08-08. Nothing from the Valinor widgets crossed over, even
though the app side of the bridge did. This is the plan to finish it, written
for a MacBook session.

## What is already there

The app half was ported in the migration and is live:

- `Core/Sources/HearthCore/Widgets/SharedSnapshot.swift`: `HearthSnapshot`
  (persona name, connected, state string, session summary, flattened card
  summaries, updatedAt) and `SharedStore` reading and writing it through
  `UserDefaults(suiteName: "group.com.joshuajones.Hearth")` under the key
  `hearth.snapshot.v1`. Both types are `internal`, which the plan below
  changes.
- `ChatViewModel.publishWidgetSnapshot()` writes the snapshot and calls
  `WidgetCenter.shared.reloadAllTimelines()` on session resume and card
  changes, with `widgetCardSummaries()` flattening weather, timer and brief
  cards.
- `HearthApp.handleOpenURL` treats `hearth://talk` as a listening turn.
- `Hearth/Hearth.entitlements` grants the App Group as `$(HEARTH_APP_GROUP)`;
  `Dev.xcconfig` and `Release.xcconfig` define it.
- `HearthUI.PersonaOrb` is public, draws one static frame from a
  `HearthState` and a `PersonaPalette`, and its header says it exists for
  the widget.
- `apple-client/manifest.yaml` already fixes the names: bundle id
  `com.joshuajones.Hearth.Widgets`, types `HearthWidgetsBundle`,
  `HearthWidgetProvider`, `HearthEntry`, `PersonaWidget`, and the kind
  strings `hearth.persona` and `hearth.quicktalk`. Kind strings are one-way
  after release, so these are the ones to use from the first build.

What is missing is the extension itself: the widget target has no
entitlements file, so even a correct provider would read an empty container
and draw the placeholder, and it does not link the `HearthCore` or `HearthUI`
products.

## What Valinor's widgets were

Five files under `Apple Client/Valinor/ValinorWidgets/` in the Valinor
repository, 371 lines, all SwiftUI:

| File | What it does |
| --- | --- |
| `ValinorWidgetsBundle.swift` | Bundle of two widgets. |
| `ValinorWidgetProvider.swift` | One `TimelineProvider` for both. Reads the snapshot once, then emits 90 entries two seconds apart. `glowPhase` alternates 0 and 1 each entry so the orb breathes through the entry transition (widgets have no render loop). `cardIndex` advances every nine entries, about 18 s per card, so the larger sizes cycle their cards. Refresh policy after the last entry, about three minutes out. |
| `PulsingPersonaOrb.swift` | The static `PersonaOrb` with a radial glow behind it whose opacity and scale follow `glowPhase`, animated with `.animation(.easeInOut(duration: 1.9), value: glowPhase)`. The goal in its own words: simply not static. |
| `SulivanWidget.swift` | Small: orb, a name chip with a green or grey connection dot, a "Tap to talk" capsule. Medium: orb on the left at 120 pt, the current card on the right. Large: orb above, card beneath, mirroring the app's layout. `WidgetCardView` renders a card summary with title, subtitle or a live `Text(timerInterval:countsDown:)` countdown for timers, and detail. The whole widget carries `.widgetURL(valinor://talk)`. |
| `QuickTalkWidget.swift` | Small only: the orb with a violet "Tap to talk" capsule. |

The design holds. Two things do not carry as they are: the palette is the
old violet on near-black, and Hearth is the warm light-first brand; and
Sulivan on the phone is now a flame with a face, not an orb.

## The plan

Do the steps in order. Each ends in something you can see on a device.

### 1. Wire the target

1. Add `Hearth Widget/Hearth Widget.entitlements` with the
   `com.apple.security.application-groups` array containing
   `$(HEARTH_APP_GROUP)`, the same line the app uses, and set
   `CODE_SIGN_ENTITLEMENTS` on the WidgetExtension target to it. Without
   this the extension reads an empty container and the failure is silent:
   a placeholder orb is indistinguishable from a widget that is working
   and waiting.
2. Add the `HearthCore` and `HearthUI` package products to the
   WidgetExtension target's Frameworks phase. The pbxproj links them to
   the `Hearth` and `Hearth Vision` targets only; the widget links nothing.
3. Confirm the target's xcconfig gives it `HEARTH_APP_GROUP`,
   `HEARTH_BUNDLE_ID_WIDGETS` and `HEARTH_IOS_FLOOR`. `Shared.xcconfig`
   is where the app gets them.
4. Delete `Hearth_WidgetLiveActivity.swift` and `AppIntent.swift`. Nothing
   in the design is a Live Activity, and the widgets are static
   configurations, not intent-configured. Keep `Hearth_WidgetControl.swift`
   for step 5, renamed.

### 2. Open the bridge

1. Make `HearthSnapshot`, `HearthSnapshot.CardSummary`, `SharedStore.read`
   and `SharedStore.write` `public`. The widget imports `HearthCore` as a
   product, so anything it touches has to be public; this is the whole
   reason the package split exists (see the `Package.swift` header).
2. Replace the hand-typed `appGroupID` literal with a read of an Info.plist
   key. Add `HEARTH_APP_GROUP` to both targets' generated Info.plist
   settings (`INFOPLIST_KEY_HEARTH_APP_GROUP = $(HEARTH_APP_GROUP)`) and
   read it with `Bundle.main.object(forInfoDictionaryKey:)`, falling back
   to the literal. The manifest's note on `widget-bridge` asks for exactly
   this: one hand-maintained copy of the string instead of three.
3. Add a public `HearthState.init(snapshotString:)` in HearthCore, the
   inverse of `ChatViewModel.stateString`, so the widget does not carry its
   own string switch.

### 3. Port the widgets

New files in `Hearth Widget/`, names from the manifest:

1. `HearthWidgetsBundle.swift`: `@main`, body is `PersonaWidget()`,
   `QuickTalkWidget()`, and the control from step 5.
2. `HearthWidgetProvider.swift`: `HearthEntry` and `HearthProvider`, the
   Valinor provider with the types renamed. Keep the two-second pulse, the
   nine-step card cadence and the 90-entry window; they were tuned against
   the widget animation budget on a device.
3. `PulsingPersonaOrb.swift`: as Valinor's, but the glow colour comes from
   the palette's idle colour rather than a violet literal, and the base
   `PersonaOrb` gets `palette: .fallback`, which is already the warm set.
4. `PersonaWidget.swift`: `SulivanWidget` renamed, kind `hearth.persona`,
   `.widgetURL(hearth://talk)`, display name "Persona" and a description
   that does not name Sulivan, since the snapshot carries whoever the
   resident is. Restyle to the brand: `containerBackground` cream in
   light and ember in dark, name chip and card text in roast, connection
   dot fennec when connected and fawn when not, the card tile linen at
   low opacity. The token values are in the desktop design system
   (`hearth-client/docs/design-system.md` in Valinor) and in
   `HearthPalette.swift` here.
5. `QuickTalkWidget.swift`: kind `hearth.quicktalk`, the talk capsule in
   fennec with cream text.
6. Build, run the app once so it publishes a snapshot, place all three
   sizes. Check: the name chip shows the current persona, the dot turns
   fennec when the house is connected, the orb breathes, a timer card
   counts down, and a tap opens the app listening.

### 4. Put the flame on the widget

Sulivan on the phone is `PersonaFlameCanvas` over `PersonaFaceView`, both
in HearthUI and both drawn by a `TimelineView`. A widget cannot host a
`TimelineView`, but it can draw one frame.

1. Expose a single-frame entry point from HearthUI: a public
   `PersonaFlameFrame(state:palette:date:)` view that calls the flame's
   draw function and the face's `draw(_:into:size:)` for one `date`,
   with `drawsHead: false` and no director (a resting pose from
   `FaceExpressions`). If the flame draw is a private method on the
   canvas, lift it to a `static func draw(...)` first; that is a move,
   not a rewrite.
2. In `PulsingPersonaOrb`, branch on the snapshot: when the persona's
   visualization is `flame` draw `PersonaFlameFrame`, else `PersonaOrb`.
   Add `visualizationType: String` to `HearthSnapshot` and set it in
   `publishWidgetSnapshot()` from `personaVisualization.kind.rawValue`.
   The provider's alternating `glowPhase` gives the flame a two-phase
   flicker by passing two fixed `date` values, which is the same trick
   the orb uses for breathing.
3. Blink on the entry transition is free: use the two phases as eyes open
   and eyes at a half-blink. Do not try to animate more than that; the
   widget budget is the constraint the Valinor header warned about.

### 5. The Control Center button

Xcode's `Hearth_WidgetControl.swift` is a `ControlWidget` template, and a
control is a real addition Valinor never had: a button in Control Center
and on the lock screen that opens the app listening.

1. Rename to `TalkControl.swift`, kind `hearth.talk`, a `ControlWidgetButton`
   whose intent is an `OpenURLIntent` for `hearth://talk` (or an
   `OpenIntent` that the app resolves the same way), symbol
   `mic.fill`, title "Talk".
2. Add the kind to the manifest's `widget_kinds` before the first build
   with it.

### 6. Close out

1. `apple-client/manifest.yaml`: entries for every new file under
   `Hearth Widget/`, and remove the template files' entries if they have
   any. Run `python3 tools/sync-report.py --manifest apple-client/manifest.yaml`
   and `tools/apple-gates.sh`.
2. `wiki/clients/ios.md`: replace "No widgets yet" under "What it cannot do
   yet" with a short section on the three widgets and the control, what
   each shows, and that they read the last published snapshot rather than
   a live connection.
3. Update the status line at the top of this file and the row in
   `_index.md`.

## Traps, from the Valinor history

- **Widgets never animate on their own.** Every motion here is an entry
  transition. If something looks frozen, the fix is in the provider's
  entries, not in the view.
- **The App Group must match in three places** and a mismatch compiles,
  signs and runs. Step 2.2 collapses it to one; until then, check the
  entitlements of both targets against the xcconfig before debugging
  anything else.
- **Kind strings are permanent.** `hearth.persona`, `hearth.quicktalk`,
  `hearth.talk`. Changing one after a TestFlight build orphans every placed
  widget.
- **The bundle identifier must be prefixed by the host's.** The manifest
  has it right; a typo here fails at install with a message that does not
  mention widgets.
- **Test the widget against a real snapshot.** The placeholder is designed
  to look fine, which means a broken bridge also looks fine. The name chip
  and connection dot exist so a working widget is visibly different from
  the placeholder.
