# Hearth Android Appliance, the overhaul plan

Written 2026-08-20 from the approved brainstorm. Companion to
`wiki/raw/android-client-plan.md` (the client rebuild, which comes first),
`tasks/android-client-mirror.md` (the task), and
`wiki/raw/research-foldable-prototype.md` (the device research). This plan
covers part 2 of the Android goal: strip stock Android on the Razr as far
as user space allows and rebuild the device as a dedicated Hearth
appliance.

## Decisions, locked in dialogue 2026-08-19/20

| Question | Decision |
| --- | --- |
| Target device | The locked AT&T XT2321-5 in hand, user-space only. No root, no bootloader unlock, no custom ROM. Wifi only, no SIM, no phone number. |
| End state | A Hearth appliance: the client is HOME, the persona is the primary surface, Lock Task pins it, almost nothing else launches. A pocket Echo Show. |
| Google | Keep GMS (Play Services + GSF) so the platform SpeechRecognizer STT keeps working; strip every other Google app. |
| Mechanism | Approach 1: reversible ADB debloat plus a thin Device Owner, everything undone by factory reset. Aggressive blocklist entries cherry-picked, never adopted wholesale. |
| UI baseline | The iOS app's UI structure is the baseline for the client on this device; the cover screen gets its own design pass (see Owed design work). |
| Sequencing | Client first to feature parity with iOS, then the appliance provisioning and strip. Nothing here blocks or reorders a client phase. |

Hardware context: adb-confirmed XT2321-5, ro.carrier att,
sys.oem_unlock_allowed 0, verified boot green, Snapdragon 8+ Gen 1,
security patch 2023-05-01. No brute-force unlock exists; the assessment
lives in `tasks/android-client-mirror.md`. Everything below fits inside
that ceiling on purpose.

## Section 1: Provisioning flow

`dpm set-device-owner` only succeeds on a device with zero accounts and
setup incomplete, so the flow is reset-first:

1. Remove any Google account in Settings BEFORE resetting (disarms
   Factory Reset Protection), then factory reset from Settings, never
   from recovery. The 2026-08-19 setup sign-in is the standing example of
   why this order matters.
2. Setup wizard: skip every account, connect wifi only, enable Developer
   options and USB debugging.
3. Take pending OTAs now, before anything is installed or removed; the
   2023-05-01 patch level wants them, and updates are safer before the
   strip than after.
4. Sideload the Hearth client APK, which carries the DPC (a
   `DeviceAdminReceiver`); one artifact, no separate admin app.
5. `adb shell dpm set-device-owner com.hearth/.DeviceOwnerReceiver`, the
   one-shot that grants the dedicated-device toolkit.
6. Install Tailscale and join the tailnet (Section 1a).
7. Run the strip script (Section 2).

Preflight (step 0 of the runbook): accounts must list zero, `pm list
users` must show only user 0, `settings get global device_provisioned`
informs whether reset is required.

### Section 1a: Tailscale, the same as every other platform

Every Hearth surface reaches a house away from home the same way: the
operator installs Tailscale's own app for that platform and signs it into
the tailnet. iOS, macOS and Windows each took that step by hand, and
Android is no different. Nothing is bundled and nothing is embedded: a VPN
app holds `BIND_VPN_SERVICE` and needs the user's system consent dialog,
so one app can never install or carry another's VPN. The client's only
part is dialing a tailnet hostname, which is just a hostname to it.

The step, in the runbook between provisioning and the strip:

1. Install Tailscale (`com.tailscale.ipn`), from the Play Store before it
   is stripped, or by sideloading its APK.
2. Sign in and approve the system VPN consent dialog. Confirm the device
   appears in the tailnet.
3. Verify from the device that the house resolves by its FULL tailnet
   name (`vytal.tail22b3ca.ts.net`). Short names fail, which iOS proved.
4. Set Tailscale to start on boot so the appliance rejoins the tailnet
   without a person present.

Consequences for the sections below, each already reflected there:

- Tailscale joins the Section 2 do-not-touch allowlist. Stripping it
  strands the appliance the moment it leaves the house.
- Tailscale joins `setLockTaskPackages` in Section 3, so the VPN keeps
  running under Lock Task.
- If Play Store is stripped in Tier 1, Tailscale updates arrive by
  sideload afterwards. Install it before the strip, not after.

## Section 2: The strip inventory

A documented, re-runnable ADB script walking `pm uninstall --user 0
<pkg>` over a curated list in four tiers, safest first, stoppable and
verifiable at each tier:

- Tier 0, telephony and carrier (zero risk, no SIM): dialer, messages,
  IMS and carrier services, `com.att.*`, visual voicemail,
  emergency-alert UIs.
- Tier 1, Google apps except GMS: Chrome, Gmail, Photos, YouTube,
  Assistant, Search, Drive, Maps, TV. Kept: `com.google.android.gms` and
  `com.google.android.gsf` (the STT rides them). Play Store goes only
  after sideloads are done.
- Tier 2, Motorola bloat: Moto app suite, widgets, analytics, demos,
  tips, wallpapers; the Moto launcher only once Hearth holds HOME.
- Tier 3, stock surfaces the appliance replaces: stock launcher,
  keyboard (if we ship one), themes, screensaver; stripped only after
  Hearth is HOME and the DPC owns the shade.

Guard rails: a do-not-touch allowlist at the top of the script (Tailscale
`com.tailscale.ipn`, whose removal strands the appliance away from home;
SystemUI,
the DPC itself, GMS/GSF, Settings, the package resolver, the wifi and
network stack); every removal logged with a one-line reason; a mirror
restore script (`cmd package install-existing <pkg>`) that reverses any
tier without a reset.

## Section 3: The kiosk shell

Standard dedicated-device APIs, all reversible:

- Hearth carries a `CATEGORY_HOME` intent filter; the DPC sets it as the
  persistent preferred HOME. Power-on lands in the persona.
- `setLockTaskPackages` allowlists Hearth, the GMS speech component, and
  Tailscale (`com.tailscale.ipn`, so the VPN keeps running under Lock
  Task); Hearth calls `startLockTask` when it is device owner.
- `setStatusBarDisabled(true)` and Lock Task features without the
  notification and system-info flags: the shade and stock notifications
  never render. Notification content routes through
  `NotificationListenerService` into the persona's voice instead.
- `setKeyguardDisabled(true)`: no lockscreen on a held wifi appliance.
- `BOOT_COMPLETED` receiver re-enters Lock Task and relaunches Hearth;
  stay-awake and screen timeout pinned by the DPC.
- Set `DISALLOW_SAFE_BOOT` (safe boot is a kiosk escape). Deliberately
  NOT set: `DISALLOW_FACTORY_RESET` and ADB restrictions; reset is the
  approved recovery and adb is the dev line, and this device cannot be
  reflashed if we lock ourselves out.
- The primary surface is the closed cover screen; the kiosk and the
  cover surface are the same target from two directions.

## Section 4: Reversibility and recovery

Lightest to nuclear, each with a named undo:

1. Stripped package: `cmd package install-existing <pkg>`, per tier.
2. Kiosk stuck: adb stays alive; `am task lock stop` or the DPC's debug
   exit intent; every restriction settable back over adb.
3. Ownership itself: the DPC manifest keeps `testOnly=true` so
   `dpm remove-active-admin` works without a reset during development.
4. Nuclear: factory reset restores stock completely. Standing rule: no
   Google sign-in on the appliance after provisioning, ever; an account
   re-arms FRP and prices the nuclear option at a password ceremony.

The runbook (preflight, provisioning one-shot, per-tier strip and
restore, recovery paths) lives in the repo next to the scripts.

## Section 5: Where this meets the client

The client knows almost nothing about the appliance. Three additive
touchpoints, all no-ops off the appliance: the HOME intent filter, the
`DeviceAdminReceiver` plus boot receiver, and a `startLockTask` call
gated on "am I device owner" so the same APK runs unpinned on an
emulator. `NotificationListenerService` is already in the client plan.
The iOS app's UI structure is the baseline the client mirrors
(`android-client-plan.md` carries the screen-by-screen map); this plan
adds no UI of its own.

## Owed design work

- The cover-screen face: what the closed lid actually shows and how it
  reads at a glance (persona frame, cards, clock, talk target). The
  client plan carries the mechanics (Glance widget, then the owned
  overlay surface); the visual design pass is not yet done and should
  start from the iOS stage and widget-snapshot contract as its
  vocabulary.
- Degraded operation: what the closed lid shows and says when the house
  is unreachable. Owed before the appliance ships as a daily object.

## Deliverables and order

1. Client to feature parity (the existing six-phase client plan; not
   this document's scope).
2. `android-client/appliance/` in this repo: the strip script, restore
   script, and runbook.
3. DPC receivers folded into the client APK.
4. The reset, provision, strip, verify pass on the Razr, tier by tier.
5. The cover-screen design pass, then the closed-lid surface.

Each step verified on the device before the next; the appliance is done
when a power cycle lands in the persona on the closed lid with nothing
else reachable.
