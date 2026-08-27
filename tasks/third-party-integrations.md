---
area: release
status: open
depends_on: []
blocks: []
updated: 2026-08-26
---

# Third-party integrations, deferred

**Hearth connects to nothing outside the machine, and that is the position.**
Everything works locally today and should keep working locally. Integrations
with outside services are a later release, taken deliberately, rather than
scaffolding that accumulates until something half-works.

Removed 2026-08-26. This file is the record so the work is not lost, and so
nobody re-adds one of them by finding a stale reference.

## What was removed, and what state it was actually in

**Google Calendar.** Registered `calendar_today` and `calendar_next`, both
disabled, pointing at a handler module that had never existed in this
repository, and advertising `HEARTH_GOOGLE_CLIENT_SECRET` and
`HEARTH_GOOGLE_TOKEN` in both the Apps and Settings panels. Replaced by the
house's own calendar over `$ENGRAM/Areas/Calendar/YYYY-MM.md`, which needs no
account at all. Not deferred: superseded.

**Home Assistant.** A `hass_call` tool in the registry pointing at
`valar.tools.handlers.smarthome`, a module that does not exist, disabled, with
Apps and Settings entries asking for `HEARTH_HASS_URL` and `HEARTH_HASS_TOKEN`.
Nothing behind any of it. Genuinely deferred.

**Telegram.** A Settings connection requiring `HEARTH_NOTIFY_TG_TOKEN` and
`HEARTH_NOTIFY_TG_CHAT`, with `tools: []`. It advertised credentials for a
capability the product does not have. Valinor keeps its Telegram path, because
there it is real dev tooling with working bot scripts; that is a developer
build concern, not a product one.

## The pattern worth naming

All three were the same shape: **a panel telling the operator to go find
credentials for a feature that was not there.** A person who followed those
instructions would have obtained a Google OAuth token and a Home Assistant
token and got nothing for either.

That is worse than an absent feature. An absent feature is honest; an advertised
one that cannot work costs the person time and trust. The rule that follows:
**a connection appears in Apps or Settings when it works, not when it is
planned.**

## Still in the product, and worth a decision

`tools/handlers/claude_code.py` makes a live outbound call to
`api.telegram.org` to notify the operator when a delegated frontier-agent run
finishes. It degrades gracefully when the environment is unset, logging instead
of sending, so it is not advertising anything.

It is still a third-party network call shipping in a product that claims to
connect to nothing. It sits inside `consult_claude`, which is itself developer
delegation rather than a customer feature, so the real question is whether the
`dev` domain belongs in a shipped persona's grants at all. **Not decided here.**

## When these come back

Whichever release takes on outside services. Each needs the same three things
before it earns a panel entry:

1. A handler that exists and is tested against the real service.
2. An honest answer to what happens when the service is down or the credential
   expires, since a house that stops working because someone else's API changed
   is not local-first in any sense that matters.
3. A statement of what leaves the machine. That is the whole product claim, and
   every integration spends some of it.

## Related

- [release-0-1-1.md](release-0-1-1.md), where the calendar replacement lands.
- `wiki/backend/tool-catalog.md` for the current registry.
