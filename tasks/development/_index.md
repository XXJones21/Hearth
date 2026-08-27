---
area: development
updated: 2026-08-26
---

# Development

Work proven on Hearth's own hardware before it is anything a customer receives.
Same distinction Valinor draws between the developer build and the product,
kept here for the pieces whose code lives in this repository.

A file belongs here when the answer to "who is this for" is "us, for now".

## What is here

| File | What it is | Status |
| --- | --- | --- |
| [android-appliance.md](android-appliance.md) | The Razr as a dedicated Hearth device: cover screen as the first pocket surface. | open |

## Why the appliance is not client work

It was filed at `tasks/android-client-mirror.md`, in among the customer-facing
client backlog, and it is a different kind of thing. The Android CLIENT is an
app a person installs on their own phone. The APPLIANCE is one specific
handset, provisioned as a dedicated Hearth device, with about 120 packages
stripped and a device policy controller holding it in place. Nobody receives
that; it is a prototype for finding out what a pocket surface wants to be.

Keeping them in one list made the board read as though Hearth owed customers
an appliance.

## Related

- [../clients/android/](../clients/android/) -- the actual Android client,
  which IS customer work.
- [../clients/_index.md](../clients/_index.md) if it exists, and the per-client
  folders otherwise.
