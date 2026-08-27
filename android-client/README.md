# Hearth Android client

The Android client, mirroring the iOS app. Plan:
`wiki/raw/android-client-plan.md`. Appliance overhaul (phase 2 of the wider
Android goal): `wiki/raw/android-appliance-plan.md`. Task:
`tasks/android-client-mirror.md`.

## Layout

The iOS split, mirrored:

- `core/` -- the portable logic, the counterpart of the iOS `HearthCore`
  package. Transport, view model, models, face director, cards, config. No
  Compose in this module; if a file needs a Composable it belongs in `app`.
  Dependencies held to OkHttp and coroutines, matching Core's zero-dependency
  policy as far as Android allows.
- `app/` -- the Compose surface plus the device-owner receivers the appliance
  provisions (`com.hearth.DeviceOwnerReceiver`, `Appliance.kt`; no-ops on any
  device that is not provisioned as device owner).
- `appliance/` -- the strip script, restore script, and runbook that turn the
  Razr into the dedicated appliance. Nothing in it runs on a normal install.

`applicationId` is `com.hearth`, fixed by the DPC component the appliance plan
names (`com.hearth/.DeviceOwnerReceiver`). minSdk 33: the Razr 40 Ultra ships
Android 13 and nothing older matters.

## Building

Open `android-client/` in Android Studio, or from this directory:

```
./gradlew :core:test          # the phase 0 gate
./gradlew :app:assembleDebug  # the sideloadable APK
```

## Phase 0 status

Landed: the module graph, and the pure ports that carry their own tests.

- `core/persona/face/FaceExpressions.kt` -- the expression library, ported
  value for value from iOS. All three clients must perform the same face.
- `core/persona/face/FaceGeometry.kt` -- persona geometry with tolerant
  decode; a missing field falls back to its archetype default.
- `core/persona/face/FaceDirector.kt` -- the clock-injected director. Time and
  randomness both arrive as arguments, so the tests need no clock.
- `core/models/` -- `HearthState`, `ChatMessage`.

Next, in plan order: the rest of the direct-port list (cards, config, session
and journal models), then phase 1's OkHttp transport and pairing.

## House rules carried from iOS

Seven behaviors are ports, not reinventions, each a paid-for iOS bug fix. The
full list is in the client plan; the ones that bind on day one:

- Captions and face cues fire from PLAYBACK position, never packet arrival.
- The card transcript is append-only; a re-emit never replaces an instance.
- One origin construction; the port literal exists in exactly one place.
- No default host: unconfigured shows first run and does not dial.
