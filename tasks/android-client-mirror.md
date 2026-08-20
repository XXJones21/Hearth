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

## Hardware status (2026-08-19)

The delivered unit is NOT the ordered XT2321-3. Read over adb, serial
ZY22HCL8N3: `ro.boot.hardware.sku = XT2321-5`, `ro.carrier = att`,
`sys.oem_unlock_allowed = 0`, fingerprint `zeekr_gu/zeekr:13/T1TZ33.3-62-25`,
security patch 2023-05-01. The OEM unlocking toggle is absent because the
unlock path is closed on carrier units; Motorola refuses codes for AT&T.
Return recommended (ordered -3, received -5, not as described). Phase 1
runs fine on a -5 regardless; only the phase 2 AOSP path dies on it.
Development continues on emulator either way.

**No brute-force unlock exists for this unit, and age does not change
that.** Read over adb: `flash.locked 1`, `vbmeta.device_state locked`,
`verifiedbootstate green`, `secure_hardware 1`, platform `taro`
(Snapdragon 8+ Gen 1 / SM8475), bootloader MBM-3.0, baseband
M8475_DE305. The unlock is a Motorola-signed cryptographic code, not a
guessable secret; AT&T units are refused signing, and there is no code
space to brute force. The old escape hatches are closed by secure_hardware:
EDL (Qualcomm 9008) needs a signed firehose and does not defeat verified
boot anyway, and there is no known public bootloader exploit for the
SM8475 as of early 2026. The only real later-paths are paid gray-market
unlock services (mostly scams, low odds for a secured zeekr) or an
unscheduled community exploit. Clean path for the phase 2 OS overhaul:
return the -5, buy a verified retail XT2321-3, which unlocks through
Motorola's own portal.

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
