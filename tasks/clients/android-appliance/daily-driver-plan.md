# The appliance as a daily driver, the design

Written 2026-08-22 from the approved brainstorm, the day the Razr became
the appliance. Companion to `wiki/raw/android-appliance-plan.md` (executed;
as-built addendum there) and `wiki/clients/android.md`. Everything here is
test-case work on `clients/android-appliance`, deliberately allowed to cut
against the grain of the shipped client; nothing merges toward main
without its own decision.

The question this document answers: what does it take for the appliance
to stop being a pocket Echo Show and become the phone Joshua carries,
with the persona as the operating layer and apps as instruments it plays.

## Decisions, locked in dialogue 2026-08-22

| Question | Decision |
| --- | --- |
| Ceiling | Staged: tethered companion first, on-device fallback second, standalone third. Design every wave 1 piece so it survives into wave 3. |
| Away from home | The iPhone-hotspot bridge counts as tethered: hotspot is wifi, the tailnet rides it. A real day out is a wave 1 story, not a wave 3 one. |
| App relationship | Apps as instruments. The persona drives programmatic seams (APIs, MediaSession, intents); generative UI is the face. App UIs are rarely seen. |
| First instruments | Music (Spotify), notifications to persona, messaging bridge, camera and photos. All four headline. |
| The open phone | Generative home: the inner display is a persona-composed canvas, the operator model applied to a phone. The stage is one element among the cards. |
| On-device inference | ONYX work waits for wave 2, with 2023-silicon expectations (Snapdragon 8+ Gen 1). Tethered capability comes first. |

## The three ceilings

**Wave 1, tethered companion.** The house is the brain; the phone is
hands, eyes, ears and a screen. Every instrument below that lists wave 1
works only while the house is reachable, and the persona is honest when
it is not.

**Wave 2, on-device fallback.** A small local model handles the offline
floor: timers, local music control, "the house is asleep, here is what I
can still do". The degraded-operation design owed by the appliance plan
folds into this wave.

**Wave 3, standalone.** Communications become real: messaging beyond
bridges, calls, navigation away from home. A SIM enters when it must;
everything that can be proven before the SIM is proven before it.

## The keystone: interactive cards

Nothing in the inventory works until cards can act. This is the one
contract change every instrument rides, and it lands at the harness seam
first (Valinor, then Hearth), per the architecture discipline.

- The `generated_view` DSL gains action-bearing elements: a button row, a
  tappable list row, a slider. Each carries a tool call and its
  arguments.
- The client renders them and, on interaction, posts a `card_action`
  event over the existing socket. No new connection, no HTTP.
- The house routes a `card_action` into the tool loop as if the persona
  had called the tool, then re-emits the card if the action changed what
  it shows. The turn machinery is not involved; a seek on a media card
  must not wake the whole pipeline.
- Unknown elements degrade to text on old clients, exactly as the headed
  text sections did.

A media player card is then `[art, title, slider(seek),
buttons(prev, pause, next)]` bound to `spotify.*` tools, and a playlist
browser is a list whose rows carry `spotify.play(uri)`.

Owed deep dive before build: the `card_action` contract (event shape,
idempotency, what re-emit means for the append-only card transcript).

## The instrument inventory

In build order within each wave. Status moves through: planned, spec'd,
built, live-verified.

| Wave | Instrument | Seam | Status | Notes |
| --- | --- | --- | --- | --- |
| 1 | Interactive cards | DSL + socket + tool loop | planned | The keystone; everything below rides it |
| 1 | Music (Spotify) | House tool over the Spotify Web API; the Razr's Spotify app as the Connect playback target | planned | The template instrument. Auth lives at the house. Spotify reinstalls on the appliance as a headless player |
| 1 | Notifications to persona | `NotificationListenerService` in the client, streamed to the house; house policy decides | planned | Speak, card, or swallow. Replaces the shade the DPC hides. Notification reply actions are themselves instrument seams |
| 1 | Camera and photos | CameraX capture tool + MediaStore browse; house vision describes and files | planned | The phone becomes the house's eye. Capture on request first; browse cards second |
| 1 | Local timer shadow | `AlarmManager` on-device | planned | A fired timer rings even if the house is asleep. The first daily-driver trust feature |
| 1 | Generative home v1 | Operator-model canvas on the inner display | planned | See the deep dive below; ships after two or more instruments exist to compose |
| 1.5 | Silent install and update | Device owner `PackageInstaller` | planned | The house ships APKs to the appliance, including Hearth itself. No Play, no tap |
| 1.5 | Usage awareness | `UsageStatsManager` | planned | The persona knows the phone's actual habits; feeds the generative home |
| 2 | On-device fallback | Small local model via ONYX on the SD8+G1 | planned | Offline intent floor: timers, local music, honest status |
| 2 | Degraded operation | Client | planned | The owed boot-window and house-unreachable surface; merges with fallback |
| 3 | Messaging bridge | Telegram and email tools first | planned | iPhone SMS relay is Apple-walled; do not fight it. Real SMS waits for the SIM |
| 3 | Calls | VoIP first, then SIM with our own dialer and `InCallService` as device owner | planned | The stock dialer is already stripped; we would own calling outright |
| 3 | Navigation | Maps deep links as instrument | planned | The away-from-home story |

Explicitly out: payments and NFC (Wallet is stripped, no Play, no
appetite), widgets (the persona composes surfaces instead), and any
return of the stock launcher experience.

## Device-owner superpowers

Claimed cheaply, cross-cutting, and honest about their edge:

- **Silent install.** `PackageInstaller` as device owner installs and
  updates APKs with no prompt. The house becomes the appliance's app
  store and update channel. This also retires the `adb install -r -t`
  loop for Hearth itself once trusted.
- **Usage stats.** `UsageStatsManager` access is a device-owner grant
  away. What the phone is actually used for becomes persona context.
- Already claimed by the appliance work and reused here: lock task,
  both home seats, always-on VPN, the strip and restore kit.

## Deep dives owed before their builds

Each of these gets its own brainstorm-to-spec pass in this directory
before code:

1. **Generative home.** The operator-model state machine on a phone:
   what the persona may compose, what is pinned (clock, stage,
   connection truth), how recomposition behaves in the hand versus on
   the cover, and what of the Unreal-style element library transfers.
   The cover-screen design pass owed by the appliance plan is the same
   conversation at a smaller size.
2. **`card_action` contract.** Shape, idempotency, re-emit versus the
   append-only transcript rule.
3. **Notification policy.** What speaks, what cards, what dies silently;
   per-app rules; how the operator teaches it.
4. **Spotify auth and account.** Where the OAuth dance happens (house),
   token custody, and what the appliance's Spotify login looks like on a
   device with no browser.

## Verification

Per instrument, live on the device, same discipline as the appliance
walk: build, install, a real use of the instrument by voice and by card,
then a closed-lid power cycle to prove it survives the appliance's
resting state. The daily-driver milestone is not a feature count; it is
the day the Razr leaves the house in a pocket and the iPhone stays in
the bag.
