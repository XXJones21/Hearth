---
title: The Apple Client
status: draft
last_reviewed: 2026-08-08
related:
  - apple-implementation.md
  - apple-project-architecture.md
  - ../first-run.md
  - ../backend/component-catalog.md
  - ../_index.md
sources:
  - apple-client/Hearth/ (the project itself)
  - apple-client/manifest.yaml
  - a live end-to-end run on an iPhone 14 Pro Max, 2026-08-08
---

# The Apple Client

Hearth on a phone, and later on a headset. This article describes what the
client **is** — what it does, what it needs, and what it cannot do yet. The
four documents beside it describe how it was built from Valinor's Apple client;
this one is about the thing that resulted, and it is written from a real run
against a real house rather than from the plan.

The distinction that shapes everything below: **the Apple client is not a
Hearth install.** The desktop client supervises a backend. The phone supervises
nothing. It is a window onto a house running somewhere else, and every design
decision in it follows from that.

## What it is made of

One Xcode project, three targets, one local Swift package.

| Target | Platform | What it is |
| --- | --- | --- |
| `Hearth` | iOS 26 | the app |
| `Hearth Vision` | visionOS 27 | the headset app, a skeleton at pre-alpha |
| `Hearth WidgetExtension` | iOS 26 | home-screen widgets |
| `HearthCore` | package | everything all three share |

`HearthCore` holds the transport, the audio path, the state machine, the cards,
the persona rendering and the models. The app targets hold their own shells and
almost nothing else. The split is not tidiness: it is what lets the visionOS
app exist as a skeleton without duplicating a socket client, and what makes the
widget a package dependency rather than a list of files compiled twice.

Both apps install as **Hearth**. The identifiers are
`com.joshuajones.Hearth`, `com.joshuajones.HearthVision` and
`com.joshuajones.Hearth.Widgets`, sharing the app group
`group.com.joshuajones.Hearth`. No literal appears in the source; they resolve
from `HEARTH_*` variables in the xcconfigs.

## Finding the house

**There is deliberately no default host.** This is the single most consequential
decision in the client and it is worth stating plainly, because the obvious
alternatives are both wrong:

- `127.0.0.1` is honest on the desktop, where the backend really is on that
  machine. On a phone, `127.0.0.1` is the phone.
- A LAN literal is one machine on one home network compiled into a product
  other people install.

So "unset" is a distinct state rather than a missing value, and the app in that
state **does not dial**. It draws the bundled persona and asks where the house
is. First run is correct by construction rather than correct because a timeout
expired.

The port is **18700**, Hearth's own. Not 8700 — that is the internal Valinor
stack's port, and a Hearth build that defaults to it does not fail. It
connects, and comes up wearing someone else's memory, journal and personas.
That is a first run which looks flawless, which is the worst outcome available.

Exactly one type builds an origin. `ServerConfig.url(_:)` is the only way any
HTTP call in the client constructs a URL, and no port literal appears anywhere
else in the source — a rule that can be checked by grep rather than by reading.
When no house is configured it returns nil, so a surface that cannot build its
URL reports itself unavailable instead of dialling nowhere.

### Reaching a house on another machine

The gateway must be listening on something the phone can route to. A desktop
install writes `HEARTH_HOST=127.0.0.1`, which is loopback: correct for the
desktop client, and unreachable from every other device on the network. A house
that a phone is meant to reach needs `HEARTH_HOST=0.0.0.0` and its port allowed
through the machine's firewall.

Two symptoms, worth telling apart:

- **Connection refused / nothing listening** — the gateway is bound to
  loopback, or is not running.
- **No response at all after the TCP handshake** — something else is on that
  port. On a development machine this is usually the internal stack answering
  on 8700 while Hearth is on 18700.

`curl http://<host>:18700/health` is the fastest way to know which. A live
house answers with its backend, its readiness and its persona list.

## What a turn actually does

Measured on an iPhone 14 Pro Max against a Windows house, 2026-08-08:

```
[SpeechRecognitionManager] Recognition started (on-device)
[SpeechRecognitionManager] Silence timeout — finalizing:
    'What is the weather like today in Santa Clara?'
[TTSStreamPlayer] Stream started @ 48000.0Hz
[Client] Queued PCM segment 0 … 1 … 2 … 3
[UI] append type=weather_card v=1 (1 in feed)
[Client] Finished playing (PCM streaming)
```

Speech is recognised **on the phone**, not on the house.
`SpeechRecognitionManager` sets `requiresOnDeviceRecognition = true`, which
makes iOS fail the request rather than quietly reach for the network. That
replaced the server's Whisper round-trip, and it is why the Apps page can
honestly list Speech as an on-device row.

The reply comes back as streamed PCM in numbered segments, played in order by
`TTSStreamPlayer`, which also drives the orb's speaking waveform from real
playback amplitude rather than a canned animation. Cards arrive on the same
socket as `ui_component` payloads and land in the timeline as transcript
entries.

## The screens

**First run.** The bundled persona, and one question: where is your house.

**The stage.** Persona on top, this turn's card in the middle, caption below.
Stacked rather than overlaid — a tall card would otherwise bury the persona
entirely. The card scrolls inside a bounded share of the stage; the
visualization is the point of the screen and stays visible at all times.

**The transcript.** Opt-in and remembered, expanding to 55% when opened. The
resting state is the stage alone: the log is history, and history does not need
to be on screen while someone is talking to you.

**The shelf**, a right-hand drawer with four destinations:

| Surface | What it is |
| --- | --- |
| Apps | the honest answer to "what can this thing do" |
| Persona | the two fields whose value lives entirely in the persona file |
| Journal | Selene's library — the memory, if memory ships |
| Settings | Connection first, because it is what matters most on a phone |

House apps are **read-only on the phone**, and that is a deliberate ownership
split rather than caution. Toggling an app and granting it to a persona writes
`tools.yaml` and the persona files and restarts the server; that stays at the
desk. On-device rows — Speech, Widgets — still act, because they are the
phone's own.

The Persona surface edits exactly two things: the system prompt and the colours
by state. Every other control on the desktop page points at something on the
home machine — a model under `models/`, a wav in the persona's folder, a tool
in `tools.yaml`. A model picker on a phone would list names that resolve on
exactly one machine.

### Connection, and why Apply is a button

The socket only reads the address when it **dials**, so saving alone changes
nothing — the old client has to be torn down and rebuilt against the new
origin. Apply means redial. Test probes what is typed and then rolls back, so a
bad address cannot take a live connection down before Apply commits it.

Clearing the field forgets the house and returns the app to first run. It does
not restore a built-in default, because there isn't one.

## What it cannot do yet

Stated rather than discovered, because a client that quietly does less than it
appears to is the failure this whole migration was organised against.

- **Widgets are not landed.** The target builds and the app group is declared,
  but the widget surface is area 5.
- **visionOS is a skeleton.** The volumetric window and the RealityKit scene
  are area 6. `PersonaModelView` — the `glb_animated` renderer — is in the
  shared package and reachable, but no persona model set is bundled.
- **No persona imagery ships.** `PersonaModelView` falls back to the orb, and
  that fallback is a stated design rather than a silent one. A house that
  serves assets will show them; a pre-alpha install has none.
- **The App Group is declared but not signed in.** `CODE_SIGN_ENTITLEMENTS` is
  deliberately unset until a device can prove the capability, so anything that
  crosses the app-group boundary — the widget snapshot — does not yet.
- **Performance tags are not sounded.** The house strips them before synthesis;
  see [`../backend/voice-engine.md`](../backend/voice-engine.md).

## What did not come across from Valinor

Each of these was a decision, and each is recorded with its reason in
`apple-client/manifest.yaml` under `excluded`.

| Left behind | Why |
| --- | --- |
| MWDAT / Meta Ray-Bans | the camera decodes frames and stops short of forwarding them; what works is registration and HFP audio, which is a Bluetooth headset story the OS already tells |
| On-device MLX inference | dormant and unlinked — the package was in no target's dependencies — and conceptually redundant: the product's thesis is that inference runs on the user's own machine, which for a phone means the house |
| The commissioned cards | one house's demo vocabulary, not Hearth's |
| `TTSAudioPlayer` | Hearth serves one TTS engine in one format, so there is no blob path to fall back to |
| Four tool labels | `consult_liara`, `mentat_`, `wright`, `uefn_` — a Hearth user should never be told the house is ringing a trading desk |

Nothing returns by bulk re-import. Each returns on a feature branch against the
clean project, with a stated verification gate.

## Building it

```
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -project apple-client/Hearth/Hearth.xcodeproj \
           -scheme Hearth -destination 'generic/platform=iOS Simulator' build
```

`DEVELOPMENT_TEAM` lives in `apple-client/Hearth/Local.xcconfig`, which is
**gitignored**. A second developer copies `Local.xcconfig.example` and puts
their own team there. A committed team ID builds on one Mac and fails
everywhere else with a provisioning error that does not explain itself.

Two checks say whether the tree is still good:

```
tools/apple-gates.sh
python3 tools/sync-report.py --manifest apple-client/manifest.yaml
```

The gates hunt couplings that should not have survived the move: a Valinor
name, an RFC1918 literal, an old port, an absolute path, a committed team ID.
They read tracked **and** untracked files, because a gate that cannot see new
code is blind exactly when an area lands.

### Running on a device

The device needs a provisioning profile for each bundle identifier, which Xcode
creates through the developer portal — so the Apple account in Xcode must be
signed in and current. A rejected login surfaces as *"No profiles for
'com.joshuajones.Hearth' were found"*, which reads like a project
misconfiguration and is not one.

## Traps

- **A synchronized root group copies every file in the folder**, including
  `Info.plist` and any dotfile. A target that also sets
  `GENERATE_INFOPLIST_FILE = YES` then produces it twice and the build fails
  with *"Multiple commands produce …"*. Setting `INFOPLIST_FILE` does not fix
  it; it needs a `membershipExceptions` entry.
- **Removing the development team in Xcode's UI writes
  `DEVELOPMENT_TEAM = ""` at project level**, which beats the xcconfig for any
  target that has no base configuration of its own. One target can resolve the
  team correctly while the others silently do not.
- **`xcode-select` and `DEVELOPER_DIR` can disagree.** A command-line build
  will use whichever is set and pick up a different SDK without saying so.
- **The Xcode MCP bridge advertises no tools when Xcode is closed**, which
  looks exactly like a broken configuration.
