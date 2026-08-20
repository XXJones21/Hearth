# Android client mirror

The foldable is real: the Motorola Razr 40 Ultra from the research note
arrived 2026-08-19. This task holds the phase 1 client work until it gets
mapped out properly. Source of truth for the decisions:
`wiki/raw/research-foldable-prototype.md` (recovered the same day).

## The goal

Mirror the Hearth client experience onto the phone's cover screen as the
first pocket surface: persona render, a stack of information cards, a
clock, notification content surfaced by Hearth in its own voice, and a tap
target that starts voice capture without unfolding. Closed-lid IS the
product; the inner screen is secondary.

## The decided route (phase 1, from the research)

- Stock firmware. No root, no custom ROM: current zeekr ROMs regress
  closed-lid operation, which is the entire product.
- The surface is a normal app: accessibility service plus overlay for the
  persistent cover-screen surface, `NotificationListenerService` for
  notification content, Device Owner over ADB for Lock Task and shade
  suppression. CoverScreen OS is the shipping existence proof of the shape.
- Sideload a private build, which also moots Play's accessibility-purpose
  restrictions.

## What transfers

- The Echo Show client is the architectural template: thin surface, one
  WebSocket to the house, streaming TTS back, kiosk posture. Same class of
  Android, newer everything.
- The Android bring-up gotcha list from the Echo applies: app-scoped config
  under scoped storage, cleartext ws:// network-security-config for LAN,
  lock-task launch quirks.
- Reachability away from home is met by the tailnet (M7); the phone should
  dial the full tailnet name (the iOS ATS lesson: short names fail).

## Day-1 moves that cost nothing

- Enable Developer options and check the OEM unlocking toggle state; the
  roughly 7-day greyed-out waiting period only burns down while the device
  is set up and online, and phase 2 wants the unlock even though phase 1
  never uses it. Checking the toggle does not unlock anything.
- Development can start off-device on any Android hardware:
  `adb shell settings put global overlay_display_devices 1080x1272/400`
  spawns a simulated cover screen.

## The sibling task

The research names push as the real server-side gap: nothing today lets the
house wake a surface and put a card on it. That is Keystone 1 in the
Valinor proactive-tools roadmap and needs its own mapping-out alongside
this one; the phone is a diminished product without it, but phase 1 (pull:
cards, clock, voice) does not block on it.

## Mapped out 2026-08-19

The rebuild plan exists: `wiki/raw/android-client-plan.md`, written from a
full survey of the iOS client (Core ~9,360 lines, app ~5,248). Two thirds
of Core is platform-agnostic logic that ports to Kotlin nearly 1:1,
including the clock-injected FaceDirector and its tests. The plan carries
the port map, the protocol notes, seven paid-for iOS behaviors to preserve
verbatim, the Tailscale connection posture, the two-step cover-screen
route, and six verification-gated phases. The items below remain open
inside that plan.

## Mapping out still owed

- Repo and app skeleton (new `android-client/`? Kotlin + Compose like the
  Echo), and what if anything is shared with the Echo Show codebase.
- Which persona renders ship first (compose2d sphere transfers; Filament
  path optional).
- Degraded operation when the house is unreachable: the phone must answer
  what the Echo never had to.
- What earns the closed screen: hand rules, persona judgment, or rules as
  a floor with the persona promoting and phrasing.
