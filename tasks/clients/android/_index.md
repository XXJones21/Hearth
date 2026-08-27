---
area: clients/android
updated: 2026-08-26
---

# The Android client, the backlog

The app a person installs on their own phone. It is a companion to a house
rather than a house: one desktop install carries the models and the memory, and
the phone connects to it, over the local network at home and over a tailnet
away from it.

Same convention as the other client folders: one file per area, and every file
states its status in its own frontmatter.

## Open

| Area | What it is | Status |
| --- | --- | --- |
| [implementation-plan.md](implementation-plan.md) | What the client has today, the defects with their evidence, and the work in sections. | open |
| [selene-model-renderer.md](selene-model-renderer.md) | A `glb_animated` persona has no renderer, so Selene lands in the fallback circle. | open |

## What is NOT here

The **appliance** moved to [../../development/android-appliance.md](../../development/android-appliance.md).
One provisioned Razr held as a dedicated Hearth device is a prototype, not
something a customer receives, and mixing it into this list made the board read
as though Hearth owed customers an appliance.

## Shipped

The APK shipped in 0.1.0 alpha and is the only signed artifact in that release;
the keystore lives outside the repository. Procedure in
[../../../wiki/releasing.md](../../../wiki/releasing.md).
