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

Back up what must survive. A factory reset wipes the Download folder and
every sideloaded app, so both come off the device first:

```
mkdir -p backup
adb pull /sdcard/Download backup/Download
adb shell pm path com.theboisclub.pokemonred        # note every apk= line
adb pull <each-path> backup/pokemonred/
```

A split APK lists several paths; pull all of them. Keep `backup/` out of
the repository.

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
   adb install -r backup/pokemonred/*.apk    # install-multiple if split
   ```

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
3. Set Tailscale to start on boot.

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

1. A stripped package: `./restore.sh <package>` or `./restore.sh <tier>`.
2. Kiosk stuck: adb stays alive; the EXIT broadcast above, or set any
   restriction back over adb.
3. Ownership itself: `dpm remove-active-admin`, no reset needed.
4. Nuclear: factory reset restores stock completely. Standing rule: no
   Google sign-in on the appliance after provisioning, ever; an account
   re-arms FRP.
