---
area: release
status: open
depends_on: []
blocks: []
updated: 2026-08-26
---

# 0.1.1, the parallel release

**Scope: the drift.** 0.1.0 shipped from a tree that had already fallen behind
Valinor, and the audit on 2026-08-26 measured how far. This release does not
add features. It brings the two trees back into line and carries the fixes
that were made after the alpha was cut.

That is the whole test for whether something belongs in 0.1.1: **does it close
a gap between Valinor and Hearth, or fix something already shipped?** A new
capability is 0.2.

## The tools, 8 of them

Valinor's registry holds 65 tools, Hearth's 48. Sixteen of that gap is correct
and must stay: the `mentat_*` set, `wright`, `consult_liara`, the six `uefn_*`
tools and the two interview helpers are the developer build's own instruments
and have no business in a product.

Eight are candidates:

| Tool | Note |
| --- | --- |
| `house_status` | A person with a house should be able to ask how it is. The clearest yes on this list. |
| `project_status` | Reads the second brain, which the product has. |
| `play_media` | Daily-driver behaviour. |
| `list_models`, `switch_model` | Model choice may belong in Settings as UI rather than as a tool. Decide the surface before porting. |
| `view_ledger` | Only if the ledger is a product concept rather than an internal one. |
| `calendar_read`, `calendar_write` | **Not a port. See below.** |

## The calendar is a conflict, not a gap

The two repos have **different calendar designs**, and neither is a subset of
the other:

- Valinor: `calendar_read` and `calendar_write`, a general read/write pair.
- Hearth: `calendar_today` and `calendar_next`, two narrow intent-shaped tools.

There is a third copy: the INSTALLED runtime at
`D:/Hearth/runtime/backend/harness` carries `valar/memory/calendar.py` and
`valar/tools/handlers/calendar.py` that exist in neither source repository.

One feature, three versions, two repos and one install. Settle the design
before porting anything, because a persona prompt written against one
vocabulary does not work against the other.

## The fixes made after 0.1.0 was cut

Already committed on `fix/second-brain-env-and-task-tree` and belonging in
0.1.1:

- **hearth.env was written where no launcher reads it.** Repointing the second
  brain took effect for the running process and was forgotten on restart, while
  the caller reported success. Now derived from `HEARTH_BACKEND_DIR`, and
  `link_brain` returns the path it wrote so a wrong destination cannot be
  silent again.
- **Dev diaries rendered blank in the Journal.** The harvester wrote a format
  the Journal cannot parse, so every dev entry showed as an empty card with the
  commits on disk one directory away.
- **The fire was sized off the window** and had a static CSS disc behind it.

Still uncommitted in Valinor and worth carrying:

- **The `_CLAIM_RE` guard in `voice_loop.py`**, which stops a persona claiming
  it did something it did not. Highest-value of the loose changes.

## Known defects to weigh

Found by the same audit. Each needs a yes or no for this release rather than
drifting into 0.2 by default:

- **The desktop client claims the `files` capability unconditionally**, so
  pointing Settings at a remote house offers the persona tools that read and
  write another machine's disk. `clients/desktop-client/file-capability-scope.md`.
- **`/mentat/state` returns 500 on every client poll** in the installed
  runtime: `ModuleNotFoundError: No module named 'valar.tools.handlers.mentat'`.
- **The composer says "or just start talking"** and the client has no capture
  path at all. The sentence is a one-line fix and should not wait for the
  capability. `clients/desktop-client/speech-input.md`.
- **`"csp": null`** ships in both client trees.

## The other half of the drift

44 shared client files differ between the two trees, ranked in Valinor's
`tasks/GTM/client-drift.md`. Most of that is legitimate, since Hearth carries
onboarding Valinor does not, but nobody can currently say which without reading
all 44. Reconciling them is probably larger than this release; **deciding which
tree is canonical is not**, and that decision belongs here.

## Not in 0.1.1

Signing (`release-signing.md`), iOS and visionOS TestFlight, and everything in
0.2. Those are new work, and this release is about closing the distance between
what Valinor knows and what Hearth ships.
