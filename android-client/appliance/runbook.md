# Appliance runbook

Turning the Razr (XT2321-5) into the Hearth appliance, per
`wiki/raw/android-appliance-plan.md`. Everything here is user-space and
reversible; the recovery ladder is at the bottom. Run steps in order and
verify each before the next.

All adb commands assume one device attached; add `-s <serial>` if the Echo
Show or an emulator is also plugged in.

## 0. Preflight and backup

Check the ground before the reset:

```
adb shell dumpsys account | grep -c "Account {"     # must be 0 before reset
adb shell pm list users                              # only user 0
adb shell settings get global device_provisioned
```

Back up what must survive. A factory reset wipes the Download folder,
every sideloaded app, and app data, so all of it comes off first:

```
mkdir -p backup/pokemonred
adb pull /sdcard/Download backup/Download
adb shell pm path com.theboisclub.pokemonred        # note every apk= line
adb pull <each-path> backup/pokemonred/
adb shell bmgr enable true                          # off on a no-account device
adb backup -f backup/pokemonred/pokemonred.ab -apk com.theboisclub.pokemonred
```

`adb backup` is the only route to the save data: the game keeps its saves
in its scoped external dir (`Android/data/.../files/save/`), which neither
shell nor run-as can read on Android 13, and a plain `adb pull` writes
TRUNCATED files there without saying so. The backup works because the APK
is debuggable. It needs the lid OPEN, the phone unlocked, and a tap on
"Back up my data" (blank password); the confirmation dialog renders on the
inner display only. Verify before resetting: strip the 24-byte header,
zlib-inflate, and confirm `saves/` files are present at full size (done
2026-08-22; `saves/gold/slot1.lua` came through intact).

Keep `backup/` out of the repository (gitignored).

## 1. Reset and provision

1. Remove any Google account in Settings BEFORE resetting. This disarms
   Factory Reset Protection; skipping it prices recovery at a password
   ceremony. Then factory reset from Settings, never from recovery.
2. Setup wizard: skip every account, wifi only, enable Developer options
   and USB debugging.
3. Take pending OTAs now, before anything is installed or removed.
4. Sideload the client. The manifest carries `testOnly`, so the flag is
   required:

   ```
   adb install -r -t app-release.apk
   ```

5. The one-shot. Works only with zero accounts on the device:

   ```
   adb shell dpm set-device-owner com.hearth/.DeviceOwnerReceiver
   ```

6. Restore the keepers:

   ```
   adb push backup/Download /sdcard/Download
   adb install -r -t backup/pokemonred/base.apk
   adb shell bmgr enable true
   adb restore backup/pokemonred/pokemonred.ab   # lid open, tap Restore
   ```

   The restore puts the save data back into the game's scoped dir. Launch
   the game once and confirm the save loads before moving on.

7. Open Hearth once. On resume it applies the kiosk policy, takes HOME,
   and pins. Pair it with the house before stripping anything, so every
   later verify step has a live persona to talk to.

## 1a. Tailscale

Tailscale is already installed if the reset preserved nothing; reinstall
it now, from Play before Tier late strips it, or by sideloading its APK.

1. Sign in, approve the VPN consent dialog, confirm the device in the
   tailnet.
2. Verify the house resolves by its FULL tailnet name
   (`vytal.tail22b3ca.ts.net`); short names fail, which iOS proved.
3. Boot survival is enforced twice, because the first tier 1 reboot
   landed in a persona that could not reach the house: the DPC sets
   Tailscale as always-on VPN on every resume (Appliance.enterKiosk),
   and the secure setting backs it up:

   ```
   adb shell settings put secure always_on_vpn_app com.tailscale.ipn
   ```

   Verify after the next reboot: the tailnet ping must succeed with
   nobody opening the Tailscale app.

## 2. The strip, tier by tier

```
./strip.sh 0      # telephony and carrier
./strip.sh 1      # Google apps except the allowlist
./strip.sh 2      # Moto bloat and partner preloads
./strip.sh 3      # stock surfaces, ONLY after Hearth holds both HOMEs
./strip.sh late   # Play Store and the Search app, by hand, last
```

Verify between tiers, and stop on any failure:

- After every tier: reboot, confirm the device boots into Hearth pinned,
  wifi up, house reachable.
- After Tier 1 and again after `late`: a full voice turn. The live
  recognizer is `com.google.android.tts` (on the allowlist); confirm with
  `adb shell settings get secure voice_recognition_service`. If STT dies,
  `./restore.sh <pkg>` the last removals and file what broke.
- After Tier 3: power cycle with the lid closed; the cover screen must
  land in the persona, not a black seat. If the cover goes dark, restore
  `com.motorola.launcher.secondarydisplay` and investigate before
  retrying.

Every removal is logged with a reason in `strip-log.txt`.

## 3. Kiosk escapes (development)

- FROM THE DEVICE, no adb: hold the house button in the top corner, or
  open the shelf and take Settings > This phone > Hand the phone back.
  Either one unpins Hearth and opens Developer options, which is where
  USB debugging lives. It is not sticky: Hearth pins itself again on its
  next resume, so flip the toggle before going back.

- Unpin without dropping ownership:

  ```
  adb shell am broadcast -a com.hearth.appliance.EXIT --es confirm hearth
  ```

- Drop ownership entirely (works because the manifest keeps `testOnly`):

  ```
  adb shell dpm remove-active-admin com.hearth/.DeviceOwnerReceiver
  ```

## 4. Recovery ladder

Lightest first:

0. The device's own hand-back, above. Rungs 1 to 3 all need adb, and
   2026-08-26 proved adb is not guaranteed: the appliance came up from a
   reboot with `adb_enabled` at 0, USB enumerating MTP only, no ADB
   interface, and nothing on the device able to reach Settings. The
   client launches nothing but itself, the shade and keyguard are off,
   safe boot is disallowed, and the dialer and browser were stripped in
   tiers 0 and 1. The ladder had no rung between "adb" and "factory
   reset". This is that rung.
1. A stripped package: `./restore.sh <package>` or `./restore.sh <tier>`.
2. Kiosk stuck: the EXIT broadcast above, or set any restriction back
   over adb.
3. Ownership itself: `dpm remove-active-admin`, no reset needed.
4. Nuclear: factory reset restores stock completely. Standing rule: no
   Google sign-in on the appliance after provisioning, ever; an account
   re-arms FRP.

`Appliance.enterKiosk` also pins `adb_enabled` to 1 on every resume now,
so a reboot cannot take the dev line again. `DEVELOPMENT_SETTINGS_ENABLED`
is not on the device-owner allowlist, so if Developer options themselves
have been hidden the hand-back drops to the Settings root and the build
number ceremony is still yours to do.

## 5. Verify after every reboot

The tier verifies checked the tailnet and a voice turn but never checked
that the way out was still open, which is how the appliance got stranded.
Run this FIRST after any reboot, before anything else:

```
adb devices          # must list the serial, not nothing
```

If it lists nothing, check whether the ADB interface is even enumerating
before blaming a cable:

```
powershell "Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'VID_22B8' }"
```

WPD alone means `adb_enabled` is 0 at the device. A composite with an
"ADB Interface" child means the phone is offering adb and the problem is
this end.
