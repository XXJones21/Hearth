<!-- Raw source. Recovered 2026-08-19 from
C:\Users\josh2\Downloads\foldable-custom-rom-prototype-notes.md, where it had
been stranded outside both knowledge bases. Phase 1 decided; see section 6. -->

# Minimalist Foldable Phone — Research Notes

*Compiled Aug 2026. Revised 2026-08-10 after verification pass. Status: decided
for phase 1. Open items at the bottom.*

> **Revision note.** The original draft rested on a premise that verification
> did not support: that Motorola whitelists cover-screen apps and that a custom
> ROM is the only way around it. Both halves are wrong. Section 1 and section 6
> are rewritten accordingly, and the device recommendation changed as a result.
> Sections 2 and 5 stand largely as written.

---

## 1. Project Goal

Build a minimalist phone on a **clamshell foldable** as a prototype platform for
Hearth. Form factor matters: flip style specifically, not book-style. The device
is a pocket surface for the same architecture the Echo Show client already
proves, plus real notification gating and reduced screentime.

Target experience with the phone **closed**: persona render, a stack of
information cards, a clock, notification content surfaced by Hearth in its own
voice, and a tap target that starts voice capture without unfolding.

### What changed: the cover screen is not gated

The original claim was that Motorola whitelists which apps may run on the cover
screen, and that custom ROMs remove the restriction. Verification says
otherwise, in two independent ways:

1. **Motorola is the permissive OEM here.** On stock firmware, apps are toggled
   on for the cover panel in settings, and first launch prompts "Allow."
   Motorola is the outlier among flip makers precisely because it permits
   essentially any app on the outer display, while others ship a curated list.
2. **A third party already shipped this product shape.** CoverScreen OS is a
   Play Store app the developer describes as a mini OS for the cover screen:
   app launching in portrait and landscape, third-party home screen widgets,
   notification reading with voice/T9/QWERTY reply, media control, quick
   toggles, VoIP caller ID, custom animated clockfaces, edge lighting.
   Supported on Razr 40 Ultra, 50, 50 Ultra, 60, and 60 Ultra / Razr Ultra 2025.
   Stated requirements: **Notification Access and an Accessibility Service.**
   No root. No custom ROM. Both are normal user-granted permissions.

That is a shipping existence proof of the target experience, at the plain app
layer, on stock firmware.

**Hard requirement (unchanged):** unlockable bootloader and published kernel
sources, because phase 2 still wants them.

---

## 2. Landscape — Which Foldables Are Even Viable

| Device | Unlockable | Custom ROM scene | Verdict |
|---|---|---|---|
| Pixel Fold / 9 Pro Fold / 10 Pro Fold | Yes, fully | GrapheneOS + LineageOS official | Best support, **wrong form factor** (book-style only) |
| Motorola Razr line | Yes, via portal | Varies sharply by model, see §3 | **Target** |
| OnePlus Open | Yes | Unofficial LineageOS 21 | Book-style |
| Samsung Z Fold / Flip | **No** | Dead | Ruled out |
| Honor, Huawei, vivo | No | — | Ruled out |
| Xiaomi Mix Fold, Oppo Find N | China-only, quotas/approval | — | Ruled out |
| Tecno Phantom V Flip / V Flip2 | MediaTek, SP Flash stock firmware only | None | Ruled out |
| Nubia Flip / Flip 2 | Surfaces only in repair contexts | None | Ruled out |

**Confirmed 2026-08-10:** there is no viable clamshell foldable for custom
Android work outside the Motorola Razr line, and it is not close. The non-Moto
flips were swept and none has meaningful custom ROM activity.

**Samsung note:** One UI 8 removed the OEM unlocking toggle from Developer
options outright. US models had already been locked for years. No workaround.

**Google note:** Google has never shipped a clamshell Pixel.

---

## 3. The Real Selection Criterion

Bootloader unlock eligibility gets you in the door. It is **not** the binding
constraint.

> Motorola publishes kernel sources on GitHub, but **not** Android device trees
> or HAL configs. Those are reverse-engineered from stock vendor images by the
> community. The practical question for any candidate device is: **has someone
> already published a working device tree?**

### Razr models by that measure

**Razr 40 Ultra / Razr+ 2023 — codename `zeekr`, Snapdragon 8+ Gen 1 — BEST**
- Unofficial LineageOS 23.0 (Android 16), updated Nov 2025
- Kernel source: `LineageOS/android_kernel_motorola_sm8475`
- Device tree: `AmeChanRain/device_motorola_zeekr`
- Also: /e/OS build, Evolution X port, multiple custom recoveries
- Model number: **XT2321-x**, see §4 for the variant decoder

**Razr 50 Ultra / Razr+ 2024 — Snapdragon 8s Gen 3 (SM8635)**
- Unlockable, but XDA activity is root/KernelSU/SusFS only. No full ROM.
- Would require building the device tree from scratch
- Model number: **XT2451-x**

**Razr 50 base (2024)** — MediaTek Dimensity 7300X. Avoid; blob availability
makes AOSP work materially worse.

**Razr 60 Ultra (2025)** — mid-2025 XDA thread polling for custom ROM interest
found essentially none.

### The zeekr outer-screen defect, corrected

The original draft framed this as a dead panel after years of maintainer work.
That overstates it in one direction and understates it in another. What the
LineageOS 22.2 thread replies actually report:

- **Call audio fails when folded.** On a normal call using the outer screen, the
  other party is inaudible until speakerphone is toggled on and back off.
- **The external screen loses touch** entirely, in at least one report.
- Boot logo persisting on the outer screen regardless of fold state.
- System blocks and reboots in the first period after install for some users.

Note the shape of that list. The panel is not dead. What is flaky is
**closed-lid operation specifically**, which is the entire product. On stock
firmware, closed-lid is Motorola's most polished path, because it is the feature
the phone is sold on. Installing a custom ROM today trades the best-supported
version of the core use case for the worst-supported one.

VoLTE status on zeekr custom ROMs remains **UNVERIFIED**. This is blocking for a
daily driver, since 2G and 3G are sunset on US carriers.

---

## 4. Purchasing — Model Number Decoder

The decoder is what protects the purchase. Buy by suffix, not by marketing name.

| Suffix | Variant | Verdict |
|---|---|---|
| **XT2321-3** | US retail unlocked | **Buy this.** Bootloader unlock confirmed; Magisk root guides exist for it |
| XT2321-1 | International unlocked | Acceptable. Unlock reported working. Verify US band support |
| XT2321-5 | Carrier | **Avoid.** Seen listed as "AT&T Only." Motorola refuses unlock codes for AT&T units |
| XT2321-2 | Unconfirmed | Unknown. Do not gamble |

Carrier-branded units also appear under other names (a Spectrum XT2321 was
listed). **Any listing naming a carrier is a pass, regardless of suffix.**

**Channel status as of 2026-08-10:**
- **eBay** has stock: multiple 256GB/8GB unlocked units in Good and Very Good
  condition, free returns. This is the channel to use.
- **Swappa** shows **zero** unlocked Razr 40 Ultra listings. Dry today; worth
  re-checking since it is the safer used channel when it has inventory.
- Live prices not captured. Click through and filter for XT2321-3.

Other cautions: expect the roughly 7-day greyed-out OEM unlock waiting period.
Unlocking voids warranty and affects Play Integrity, Wallet, and banking apps.
Inner-screen protector delamination is a known Razr wear issue on used units.

---

## 5. Device Tree — Scope Assessment

Two different things share the name:

1. **Linux devicetree (.dts/.dtb)** — hardware description for the kernel.
2. **Android device tree** (`device/motorola/<codename>`) — build configuration:
   makefiles, product definitions, SELinux policy, HAL manifests, fstab,
   resource overlays, proprietary-blob manifest.

### A distinction the original draft missed

"Build my own distro" and "use the zeekr device tree" are not in conflict. The
device tree is a hardware adapter, not a distro. Vanilla AOSP can be built
against `device_motorola_zeekr` plus `android_kernel_motorola_sm8475` with a
custom SystemUI and launcher on top, and none of LineageOS's userland comes
along. The one layer nobody should author twice is blob wiring.

### What's already automated

`dumpyara`, `aospdtgen` and similar take a stock firmware dump and emit a
skeleton tree in minutes. The skeleton may even boot. **This is not where the
time goes.**

### Where the time actually goes

Vendor blobs were compiled against Motorola's framework. They expect Moto's
HIDL/AIDL interfaces, Moto-specific system properties, Moto SELinux labels,
sometimes Moto framework jars absent from AOSP. Failure mode is a HAL
crash-looping with an unhelpful log. **Camera HAL and modem/VoLTE are the
classic multi-month sinks** and sometimes never fully land.

Foldable-specific work is the worst of it: display switching, posture detection,
and cover-screen resolution handling are all proprietary. The zeekr closed-lid
defects in §3 are that fact showing through.

### Realistic LLM leverage

- **Genuinely helps:** triaging logcat/dmesg, writing sepolicy rules, decoding
  Soong/Make errors, diffing a new tree against a sibling device's.
- **Doesn't help:** can't see the device, can't reverse-engineer stripped
  binaries, will produce confident and wrong config. Bringup is empirical.

### Time calibration

- Experienced dev, sibling device with public tree available: first boot in
  days-to-weeks, daily-driver in months.
- First time through: **the bringup becomes the project**, displacing the
  prototype it was meant to host.

Prior custom-Android experience at the framework and system-UI layer (Magic
Leap, Meta Spatial SDK) does not transfer to this. That work sat on top of
vendor bringup someone else had already done. The skill is real and it is the
right skill for the product; it is not the skill this section describes.

---

## 6. Decision — Resolved

The original open question was how much of the minimalist phone needs to live
below the Android framework. With §1 corrected, the answer is: **less than
assumed, and none of it blocks phase 1.**

### Routes to the cover screen, by privilege

| Route | Privilege | Enables | Cannot do |
|---|---|---|---|
| Moto native app toggle | None | Arbitrary apps on cover panel | Own the whole surface |
| Accessibility + overlay | User-granted permissions | Persistent custom surface, notification read and reply. Proven by CoverScreen OS | Suppress the underlying Moto UI at system level |
| `WindowAreaController` | None (Jetpack WM 1.2.0-beta03+) | Official rear-display transfer | Transient by design, not persistent ownership. Moto support UNVERIFIED |
| Device Owner (ADB provisioned) | No root | Lock Task, `setStatusBarDisabled`, package suspension | Cover-screen policy |
| Custom ROM | Full | Own SystemUI, kill the shade by construction, system-level screentime enforcement | Currently regresses closed-lid behavior |

### Phase 1 (now)

Buy an **XT2321-3**. Run **stock**. Build the Hearth cover-screen surface as a
normal app: accessibility service plus overlay for the surface,
`NotificationListenerService` for notification content, Device Owner over ADB
for Lock Task and shade suppression.

Rationale: the surface is reachable without root, and custom ROMs currently make
closed-lid operation worse rather than better. Days to a prototype instead of
months.

Development can start before hardware arrives:
`adb shell settings put global overlay_display_devices 1080x1272/400` spawns a
simulated secondary display on any Android device.

### Phase 2 (specced from friction, not in advance)

The parts of the concept that genuinely need system privilege are real:
suppressing the shade by construction rather than drawing over it, owning
SystemUI, enforcing screentime reduction at the system level. Build vanilla AOSP
against the zeekr tree when phase 1 has proven which of those limits actually
bite.

### Caveats on the phase 1 route

- Accessibility-plus-overlay surfaces are fragile across firmware updates.
- Google Play restricts accessibility use for non-accessibility purposes.
  Sideloading a private build makes this moot.

---

## 7. Server-Side Gap (Hearth, not Android)

The phone is the first Hearth client that leaves the house. Three assumptions
break:

1. **Reachability.** Covered by M7 (Tailscale, away-from-home), already open.
2. **Push.** Nothing in the current architecture initiates. Valar responds to a
   client that opened a socket. "The right information at the right time" is a
   push claim and there is no path today for the house to wake a surface and put
   a card on it. **Net-new server work, and the real feature gap.** Independently
   useful: it is what lets a persona surface something on the desktop client
   unprompted.
3. **Degraded operation.** The house will be unreachable sometimes. The Echo Show
   never had to answer what a persona does when the brain is gone. A phone does,
   on day one.

**Open design question:** what decides that something earns the closed screen.
Rules written by hand, a persona judging, or rules as a floor with the persona
promoting and phrasing on top. This determines whether the device is a thin
surface or needs a local model.

---

## 8. Still Unverified

- Whether any flip foldable boots a generic AOSP GSI with the cover screen
  intact. Nothing found either way.
- How much LineageOS-specific coupling sits in the zeekr device tree, and what
  reworking it for vanilla AOSP costs.
- VoLTE on zeekr custom ROMs on US carriers. Blocking for daily-driver use.
- Whether Motorola implements WindowManager Extensions for rear display mode.
  Moto's developer-facing documentation on this appears not to exist; only
  end-user support pages are indexed.
- Live used pricing for XT2321-3.

---

## 9. Reference Links

- CoverScreen OS: `https://ijp.app/apps/coverscreen-os/`
- CoverScreen OS on XDA:
  `https://xdaforums.com/t/coverscreen-os-now-ready-for-razr-50-series-a-mini-os-for-your-cover-screen.4737124/`
- Motorola cover-screen apps (Android Central):
  `https://www.androidcentral.com/apps-software/how-set-up-use-motorola-razr-cover-screen-apps`
- LineageOS 23.0 for zeekr (XDA):
  `https://xdaforums.com/t/2025-11-12-updated-rom-16-unofficial-lineageos-23-0-for-motorola-razr-40-ultra-zeekr.4767582/`
- LineageOS 22.2 for zeekr (XDA, bug reports on pages 2 and 4):
  `https://xdaforums.com/t/2025-06-18-updated-rom-15-unofficial-lineageos-22-2-for-motorola-razr-40-ultra-zeekr.4743376/`
- Device tree: `https://github.com/AmeChanRain/device_motorola_zeekr`
- Kernel: `https://github.com/LineageOS/android_kernel_motorola_sm8475`
- XT2321-3 bootloader unlock guide:
  `https://www.getdroidtips.com/unlock-bootloader-motorola-razr-40-ultra/`
- Motorola bootloader unlock portal:
  `https://en-us.support.motorola.com/app/standalone/bootloader/unlock-your-device-a`
- Android foldable display modes:
  `https://developer.android.com/develop/ui/compose/layouts/adaptive/foldables/support-foldable-display-modes`
- Jetpack WindowManager releases:
  `https://developer.android.com/jetpack/androidx/releases/window`
- Swappa (dry as of 2026-08-10):
  `https://swappa.com/buy/motorola-razr-40-ultra`

*Note: XDA returns HTTP 403 to automated fetches. Thread content above came
through search indexing, not direct reads. Verify load-bearing claims by opening
the threads in a browser.*
