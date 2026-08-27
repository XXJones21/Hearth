---
area: release
status: open
depends_on: []
blocks: []
updated: 2026-08-26
---

# Signing the desktop artifacts

Android is signed. **Windows and macOS are not**, and there is no signing
configuration in `desktop-client/src-tauri/tauri.conf.json` for either: no
`certificateThumbprint`, no `signingIdentity`, no notarization step, no
hardened runtime.

That was a defensible alpha position. It stops being defensible the moment the
audience is anyone who did not already expect roughness.

## What unsigned actually costs, per platform

**macOS is the worst of the two.** Gatekeeper refuses a plain double-click on
first open. A tester gets past it with right-click, Open, Open anyway, once,
and it opens normally afterwards. That works and it is a terrible first
impression: a person who hits the refusal without warning concludes the
download is broken or unsafe, and some of them are right to.

**Windows** shows a SmartScreen warning on an unsigned installer. Less
absolute than Gatekeeper, and it costs the same thing: a stranger deciding
whether to trust a download from someone they do not know.

**Android is already correct.** Release builds pick up a keystore from a
`keystore.properties` beside it, both outside the repository. Worth confirming
rather than assuming, because a release build without that file is silently
unsigned rather than failing.

## What it takes

**macOS: Developer ID plus notarization.** An Apple Developer account, a
Developer ID Application certificate, hardened runtime enabled, and the
notarization round trip with Apple before stapling. Tauri supports all of it
through `tauri.conf.json` plus environment variables for the credentials.

**Windows: a code-signing certificate.** An OV certificate is cheap and still
accrues SmartScreen reputation slowly; an EV certificate carries reputation
immediately and costs more and usually wants a hardware token. Which one
depends on how many strangers are downloading and how soon.

**Both need somewhere to keep the credentials.** They cannot go in the
repository. That is the part to decide before buying anything: local-only on
the build seats, or a secret store if release building ever moves to CI.

## Sequencing

**macOS signing and the iOS TestFlight build need the same Apple developer
account.** Neither has it today. Getting it once unblocks both, so they should
be done together rather than the account being bought twice over.

Windows signing is independent and can happen whenever.

## Until then

Keep saying it in the release notes. The 0.1.0 notes carried the Gatekeeper
workaround and that is the right behaviour: an unsigned artifact that warns
people is honest, an unsigned artifact that surprises them is not.

## Related

- [../wiki/releasing.md](../wiki/releasing.md), which records the current
  signing state per platform and is where the procedure lands once this is
  done.
- The Apple developer account is also what iOS and visionOS need before either
  can ship at all.
