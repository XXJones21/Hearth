---
area: docs
status: open
updated: 2026-09-03
---

# Wiki task list

**Corpus root:** wiki/
**Date:** 2026-09-03
**Updated:** 2026-09-03

The install cluster consolidation, the first-run split, and the documentation
defects the `graph` pass verified against the source tree. The decision record
behind every verdict here is `tasks/docs/artifacts/G1.research.json`, read in
full and reconciled against the linter and the doc graph before any task was
written.

## Task matrix

| ID | Task | Type | Shape | Scope | Confidence | Phase | Agent State | Score |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| T1 | Correct the 8 GB contradiction, the Windows install root, and the download figure in Installing Hearth | Fix | how-to | S | High | A | Backlog | |
| T2 | Correct the Windows install root and reconcile the coexistence sentence on Hearth on Windows | Fix | platform-overview | S | High | A | Backlog | |
| T3 | Correct the install root and the 8 GB example in the First run record | Fix | decision-record | S | High | A | Backlog | |
| T4 | Correct the download figure and retire the Windows-guide announcement on Hearth on macOS | Fix | platform-overview | S | High | A | Backlog | |
| T5 | Correct the settings-screen claim and state the persona-creation route on Personas | Fix | concept | S | High | A | Backlog | |
| T6 | Remove the install procedure from Hearth on macOS and salvage what only it holds | Restructure | platform-overview | S | High | B | Backlog | |
| T7 | Retype Getting started to concept and give it the download location | Restructure | concept | M | High | B | Backlog | |
| T8 | Write the reader-facing first-run walkthrough | Add | how-to | M | High | B | Backlog | |
| T9 | Give Installing Hearth a how-to spine and absorb the macOS salvage | Restructure | how-to | M | High | B | Backlog | |
| T10 | Write the Windows install procedure | Add | how-to | L | High | D | Backlog | |
| T11 | Update the wiki index for the retirement and the new how-to | Fix | landing | S | High | C | Backlog | |
| T12 | Restate the Windows gap as steps inside Installing Hearth | Fix | landing | S | High | C | Backlog | |
| T13 | Redirect the Installing on macOS link on Updating an install | Fix | concept | S | High | C | Backlog | |
| T14 | Drop install-macos.md from the Building a Hearth release frontmatter | Fix | how-to | XS | High | C | Backlog | |
| T15 | Extract the how-to and reference material from What the desktop app is | Restructure | platform-overview | L | High | D | Backlog | |
| T16 | Retire Installing on macOS once every salvage task is Complete | Consolidate | how-to | S | High | E | Backlog | |

## The consolidation verdict

The `graph` pass proposed a verdict per page for the five-page install cluster.
Four are ratified and one is revised. The cluster itself is confirmed twice
over: by G1 reading all seven pages, and by `python scripts/doc_graph.py
--json`, which returns exactly these five pages as one cluster with 20 shared
duplicate sections.

| Page | Proposed | Ratified | Task |
| :-- | :-- | :-- | :-- |
| wiki/installing.md | keep | keep | T1, T9, T10 |
| wiki/install-macos.md | fold | fold | T16, after salvage |
| wiki/clients/macos.md | keep | keep | T4, T6 |
| wiki/clients/windows.md | keep | keep | T2, T15 |
| wiki/getting-started.md | fold | **keep, retyped** | T7 |

### Why getting-started.md is revised from fold to keep

The research stage found every one of its four sections taught by a surviving
page and concluded it should retire. The sections are duplicated, and that part
holds. The conclusion does not, for three reasons.

The page's value is not a section. It is the only page written for a reader who
does not yet have an installer, and `wiki/installing.md:24` opens "You have the
Hearth installer", which rules that position out for itself. The proposal sends
the routing to `wiki/_index.md`, but `wiki/page-types.md:89-94` forbids a
landing page from carrying detail a reader can act on and asks them to leave
within one screen, so the index cannot absorb a side-by-side requirements
comparison. Two landing pages would in any case be the same defect in a new
place, since `wiki/page-types.md:93` says every published page appears exactly
once in exactly one section.

The corpus's largest single gap is that no page says where to download Hearth,
which is the first break in the traced journey. That content has exactly one
correct home, and it is the page a reader reaches before they have anything.
Retiring that page would remove the only place the gap can close.

So the page keeps and is retyped. Its declared `type: how-to` is wrong on its
own terms, since it has no numbered task steps, and all four objectives the
research stage recorded for it recommend a non-how-to shape. It becomes a
`concept` page: what Hearth is, whether this machine runs it, where to get it,
and what pre-alpha means. The duplicated `## Three steps to a running house`
and `## Where to go next` sections go, which is the part of the proposal that
was right.

### Why the other four are ratified

`wiki/installing.md` survives as the single install how-to. It is the only page
already parameterized by platform, at `### macOS` line 35 and `### Windows`
line 48, `wiki/_index.md:30` routes to it, and `wiki/page-types.md:102` names
it as a how-to in the corpus. It carries three verified defects and no numbered
step anywhere between lines 22 and 147, so keeping it is conditional on T1 and
T9.

`wiki/install-macos.md` folds into it. The two pages print the same plan table
with different rows, which is the maintenance failure in miniature:
`wiki/install-macos.md:72-78` carries Backend and Mind-and-voice rows that
`wiki/installing.md:68-73` drops. The doc graph scores the pair at 0.72
duplicate. It is not a delete, because six passages live nowhere else, and
every one of them is listed in the salvage table below.

`wiki/clients/macos.md` and `wiki/clients/windows.md` both keep. Their overlap
is the highest in the cluster, but their objectives are different platforms and
their shared spine is the shape `wiki/page-types.md:227-252` prescribes for all
five client pages. What each needs is a removal, not a retirement:
`wiki/clients/macos.md:85-102` is a fourth copy of the install procedure that
`wiki/page-types.md:243-245` names as how the corpus ended up with two install
guides.

### The architecture this settles, and what it costs

Ratifying the fold picks one of two coherent futures, and the cost is worth
stating because three published pages currently promise the other one.

The chosen architecture is a single install how-to parameterized by platform.
The rejected one is a per-platform guide set, `install-macos.md` beside a new
`install-windows.md`, which is what `wiki/whats-not-here.md:23`,
`wiki/installing.md:135-138`, `wiki/clients/macos.md:122` and
`wiki/clients/windows.md:232-234` all describe.

Single-page wins because the shared material dominates. Read side by side, the
genuinely macOS-specific content is the unsigned right-click-Open step, the
Metal row, the home-directory default, the Trash uninstall, and the log names.
The scan, the plan, the download with its sha256 and resume behaviour, the
verification pass, the install root rules, and the update story are identical
prose already duplicated once. The per-platform architecture writes all of that
a third time for Windows, and the corpus has already demonstrated it cannot
keep two copies in agreement.

The cost is that `wiki/whats-not-here.md:23` is now wrong in its own right, not
merely a duplicate announcement. It describes the missing work as a page
mirroring `install-macos.md`, and under this verdict the missing work is a
Windows section inside `wiki/installing.md` and `install-macos.md` will not
exist. That is T12, and the research stage did not name it.

## The first-run decision

`wiki/first-run.md` stays a decision record, and a reader-facing how-to is
written beside it as `wiki/meeting-your-persona.md`. The alternative, rewriting
it in place as the how-to it used to claim to be, is rejected.

The retype already landed and is committed: `wiki/first-run.md:4` reads `type:
decision-record`. Reversing it would undo committed work to solve a routing
problem that has a cheaper fix.

The page is genuinely valuable as a record, and rewriting it as a how-to
destroys that value. It carries dated decisions at lines 52, 87, 105 and 159, a
rule derived from a bug at lines 62-85, the `nvidia-smi` rather than WMI rule
at lines 155-157, the standing "seed empty, never clone" constraint at lines
316-320, and four live open questions at lines 322-333. None of that belongs to
a reader carrying out a task, and none of it is recorded anywhere else.

`wiki/page-types.md:150-154` prescribes the remedy directly: a concept or
record page containing steps belongs on a how-to page it links to. The fix is
extraction, not retyping.

The extraction is small. Beats two and three hold roughly eight paragraphs of
reader-facing procedure, which is a short new page rather than a large one.

The new page takes the name `wiki/meeting-your-persona.md`, matching the
`## Meeting your persona` section that `wiki/_index.md:34` already has, and it
becomes the first entry in that section. Renaming `wiki/first-run.md` itself
was considered and deferred: it has eight inbound references, and the rename is
worth its own decision rather than being smuggled into this one. That is the
open question recorded on T8.

## Salvage before retirement

Integrity rule 9. `wiki/install-macos.md` is retired by T16 and by nothing
else, and T16 does not open until every row below reads `Complete`.

| Passage | Lines | Lands in | Task |
| :-- | :-- | :-- | :-- |
| The unsigned right-click-Open procedure, the only numbered steps in the cluster | 43-53 | wiki/installing.md | T9 |
| The verbatim message shown to a machine below the floor | 32-34 | wiki/installing.md | T9 |
| The Backend and Mind-and-voice rows of the plan table | 76-77 | wiki/installing.md | T9 |
| The macOS uninstall, including copying `home/` out first | 128-133 | wiki/installing.md | T9 |
| The log filenames and four named failure modes | 135-155 | wiki/installing.md | T9 |
| Starting and stopping the backend on macOS | 118-126 | wiki/clients/macos.md | T6 |
| The measured RTF of 0.96 on the 8 GB Air (from clients/macos.md) | 102 | wiki/clients/macos.md | T6 |
| The Windows install root tree (from clients/windows.md) | 153-161 | wiki/installing.md | T9 |
| The four-tier model dictionary description (from clients/windows.md) | 196-202 | wiki/installing.md | T9 |

The research stage listed a tenth item, `wiki/getting-started.md:36-46`, the
side-by-side requirements written for a reader who has not chosen a platform.
Revising that page to keep removes the item: the content stays where it is.

Every inbound reference to `install-macos.md` must be redirected before T16
runs. The full set, from a corpus grep: `wiki/_index.md:31`,
`wiki/installing.md:7,14,27,132`, `wiki/whats-not-here.md:23`,
`wiki/clients/windows.md:10,14,233`, `wiki/releasing.md:9`,
`wiki/updates.md:8,105`, `wiki/clients/macos.md:7,11,29,89,127`.

## Phases

A phase is a group of one-page tasks whose targets do not overlap. No page
appears twice in one phase.

| Phase | Tasks | What it does |
| :-- | :-- | :-- |
| A | T1, T2, T3, T4, T5 | Correct every verified defect on a page that survives. Nothing here depends on a verdict. |
| B | T6, T7, T8, T9 | Reshape the survivors and land the salvage. |
| C | T11, T12, T13, T14 | Redirect every inbound reference and update the registers. |
| D | T10, T15 | The blocked Windows procedure, and the Windows page split. |
| E | T16 | Retire `wiki/install-macos.md`. Opens only when A through C read `Complete`. |

Phase A is safe to run before any of the rest, because a wrong sentence on a
surviving page is wrong whether or not anything folds.

## What the tooling added

`python scripts/lint_wiki.py` returns 28 pages checked, 0 errors, 198 warnings.
Every finding is a warning, so nothing blocks. The counts on the pages in scope
are: `wiki/clients/windows.md` 23, `wiki/first-run.md` 16,
`wiki/install-macos.md` 9, `wiki/installing.md` 6, `wiki/clients/macos.md` 3,
`wiki/getting-started.md` 1. These are style findings and the author stage
loads `hearth-style`, so they are handled on any page a task touches rather
than tracked as tasks of their own.

One linter finding is structural rather than stylistic and backs T15:
`wiki/clients/windows.md:28` reports a long section of 1135 words under
`## What the desktop app is` with no H3.

`python scripts/doc_graph.py --json` confirms the cluster and adds one signal
the research stage did not have: `wiki/clients/macos.md` is the only page of the
six with no entry in `unique` at all, meaning no section the tool considers its
own. That is the strongest fold signal in the cluster and it did not change the
verdict, because a verdict from a similarity score is a guess. It is recorded
as an open question on T6 with a named reassessment trigger.

`python scripts/lint_wiki.py --figures` returns 0 figures pending capture, so
no figure task is opened.

## Reconciling the research artifact

Three of the seven questions the `graph` pass left open are answered by source
this run read, and the answers change what the tasks must say. They are
recorded here rather than carried forward as open.

**The Windows single-drive fallback is fixed, not merely wrong.**
`crates/hearth-probe/src/machine.rs:238-248` now returns a visible `Hearth`
folder under the home directory on both macOS and Windows, with the comment
recording that the Windows branch is the single-drive fallback and so was the
ordinary laptop rather than an edge case. The hidden `.hearth` dotdir survives
only on Linux. The install-root tasks therefore describe the corrected
behaviour: `Hearth` on the roomiest non-removable, non-system fixed drive, and
a visible `Hearth` in the user profile on a single-drive machine.

**A persona made during first run can now create another persona.**
`backend/harness/valar/data/persona_template.json:33` grants the `personas`
domain, and the comment at line 32 states that leaving it out meant the only
route to a second persona was switching back to Sulivan, "which no page
documented and nothing intended". This answers both persona questions the
research pass raised, and it reverses what the documentation should say: T5
states that any persona can make another, not that only Sulivan can.

**Two defects reach one more page than the artifact recorded.** The
download-figure defect is on `wiki/clients/macos.md:51-54` as well as the two
pages named. A coexistence sentence also sits at
`wiki/clients/windows.md:199-201`, which the research pass did not examine; it
concerns Windows GPU tiers rather than an 8 GB Mac, so it may be correct, and
it is carried as an open question on T2 rather than as a defect.

The two questions the pass left open that this run cannot settle are carried
verbatim onto T1 and T9.

## Task list

### T1: Correct the 8 GB contradiction, the Windows install root, and the download figure in Installing Hearth

The page contradicts itself about the same machine forty lines apart, states a
Windows install root the planner does not produce, and describes a download
figure as covering more than it counts. All three are corrections to existing
sentences on one page, and none of them waits on a consolidation verdict.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: wiki/installing.md, read in full this run. Lines 39-42 under `### macOS` state that an 8 GB M2 MacBook Air runs the mind and the voice at once and speaks; lines 75-78 under `## The scan and the plan` state that on an 8 GB machine the honest phrasing is that the persona will think and speak one at a time. Lines 85-86 under `## Choosing where it lives` state the default is `D:\Hearth` on Windows. Lines 96-97 under `## The download` list four things downloading.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T1.research.json
- Open questions:
  - Is the plan's download figure meant to cover four provisioned items or the two it sums? crates/hearth-probe/src/plan.rs:214-234 sums the model build and the voice only, while wiki/installing.md:95-97 and wiki/install-macos.md:84-86 both describe four things downloading. Either the prose is overstating what the number covers, or the inference engine and Python runtime are fetched by a path outside the planner that this pass did not find.
  - What context window does an 8 GB Mac actually plan? Both install pages say 17,408 tokens. The value has the right shape (crates/hearth-probe/src/plan.rs:280-283 rounds to a multiple of 1024) but no fixture asserts it, and confirming it needs the planner run rather than read.

##### Draft

Lines 40-42 are the version that survives. Lines 75-78 are the sentences to
replace, and the replacement should still say something honest about a small
machine rather than deleting the thought, since saying so plainly in the
reader's language is the intent the passage was written for.

The install root sentence at lines 85-86 describes the corrected behaviour:
`Hearth` in the home directory on macOS, and on Windows `Hearth` on the
roomiest non-removable, non-system fixed drive, falling back to a visible
`Hearth` in the user profile on a single-drive machine.

The download figure at lines 96-97 is under an open question. Do not assert
either number until the research stage settles what the planner counts.

### T2: Correct the Windows install root and reconcile the coexistence sentence on Hearth on Windows

The page states a Windows install root the planner does not produce, and
carries a sentence about the model and the voice not staying loaded together
that resembles a claim corrected elsewhere but concerns a different machine
class.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: wiki/clients/windows.md, read in full this run. Line 151 under `## What the installer gives you` states the install root is `D:\Hearth` by default. Lines 199-201 under `## The hardware probe picks your model` state that on a smaller GPU Hearth says the model and the voice cannot both stay loaded at the same time. Lines 232-234 under `## Status` announce a Windows install guide mirroring Installing on macOS.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T2.research.json
- Open questions:
  - Is the sentence at wiki/clients/windows.md:199-201 correct for Windows GPU tiers? The corrected claim elsewhere concerns an 8 GB Mac, and this run did not read crates/hearth-probe/src/plan.rs against the Windows tiers. It may be accurate as written.

##### Draft

The install root at line 151 takes the corrected behaviour named in T1.

The announcement at lines 232-234 is retired: the register for unwritten pages
is `wiki/whats-not-here.md`, and under the ratified verdict the missing work is
a Windows section inside `wiki/installing.md` rather than a page mirroring
`install-macos.md`. Keep a link to the install page; drop the promise.

Lines 199-201 are not to be changed until the open question is settled. If the
sentence is right for a small Windows GPU, it stays.

### T3: Correct the install root and the 8 GB example in the First run record

The record states a Windows default in its install-root tree that the same page
then describes correctly fifty lines later, and it uses an 8 GB machine as the
worked example of a design principle that the machine no longer demonstrates.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: wiki/first-run.md, read in full this run. Frontmatter line 4 reads `type: decision-record`. Line 112, inside the fenced tree under `### One folder, and deleting it is the uninstall`, annotates the root as "the chosen folder, D:\Hearth by default". Lines 161-163 under `### The scan is not only about picking a model` state the roomiest-non-system-drive rule correctly. Lines 182-186 under `### Say what you found, and be honest about it` use an 8 GB machine as the example where the brain and the voice cannot both stay resident.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T3.research.json
- Open questions:
  - None beyond those on T1.

##### Draft

This is a decision record and the decisions stay. Lines 161-163 already state
the rule correctly, so line 112 is brought into agreement with the page's own
text rather than rewritten from scratch.

Lines 182-186 need care. The principle, that a small machine is told so plainly
and in the reader's language rather than in specs, is the decision and it
survives. What fails is the worked example: an 8 GB machine is no longer the
machine where the brain and the voice cannot both stay resident. Replace the
example, keep the principle, and keep the dated framing intact.
`wiki/page-types.md:179` is the constraint that matters here: a reader must
never be able to read a superseded statement as current guidance.

### T4: Correct the download figure and retire the Windows-guide announcement on Hearth on macOS

The page describes four things downloading together, which is the same defect
carried by the install pages, and it announces an unwritten Windows guide that
belongs in the register rather than on a platform overview.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: wiki/clients/macos.md, read in full this run. Lines 51-54 under `## What installing gives you` state that opening Hearth for the first time downloads the model weights, a voice, the inference engine, and a private Python runtime together. Line 122 under `## Status and limitations` states that the Windows install guide does not exist yet.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T4.research.json
- Open questions:
  - Carries the download-figure question from T1. This page is a third instance the research artifact did not record.

##### Draft

Line 122 goes. `wiki/whats-not-here.md` is the one register for unwritten work,
and `wiki/page-types.md:246-248` forbids a dated status log on a platform
overview.

Lines 51-54 wait on the same open question as T1 and should be resolved
consistently with it, since three pages now state the same thing.

### T5: Correct the settings-screen claim and state the persona-creation route on Personas

The page closes by sending a reader away from a screen that ships, and it does
not tell them how to make a second persona, which is the question the page's
own subject raises.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: wiki/features/personas.md, read in full this run. Lines 111-113 under `## Switching and multiple personas` state that day-to-day details of managing several personas, such as a settings screen for editing or removing one, are not yet covered by what ships today. Section `## Making your first one` at lines 46-71 describes only the first-run interview and opens "The first time you open Hearth". backend/harness/valar/data/persona_template.json:33 grants the `personas` tool domain to a newly made persona.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T5.research.json
- Open questions:
  - Is the persona settings screen reachable by an ordinary reader, or only in developer mode? The research pass reported that editing is ungated and removing sits behind a developer-mode control. The page should not describe a control a reader cannot reach without saying so.

##### Draft

Two changes. The claim at lines 111-113 is replaced by what the product does,
which the research stage establishes rather than this tracker.

Second, the page should answer how a reader makes another persona after the
first. This is now a plain answer rather than a workaround:
`backend/harness/valar/data/persona_template.json:33` grants the `personas`
domain to a made persona, and the comment at line 32 records that its earlier
absence was unintended. Any persona can make another one by being asked. Do not
write the older account, in which the only route was switching back to Sulivan.

### T6: Remove the install procedure from Hearth on macOS and salvage what only it holds

A platform overview carrying a numbered install procedure is the exact defect
the page-type reference names as how the corpus came to have two install
guides. Removing it strands two passages that live nowhere else, so they move
in the same change.

##### Details

- Agent State: Backlog
- Type: Restructure
- Scope: S
- Confidence: High
- Sizing evidence: wiki/clients/macos.md, read in full this run. `## Installing` runs lines 85-102 and contains a four-step numbered procedure. Line 102 carries the measured RTF of 0.96 on the 8 GB Air. Lines 81-83 carry one sentence on Settings > Connection. wiki/page-types.md:243-245 states that installation lives on the install page and that a platform overview which grows an install procedure has become a second install guide.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T6.research.json
- Open questions:
  - Should wiki/clients/macos.md keep at all? `python scripts/doc_graph.py --json` reports it as the only page of the six in the install cluster with no entry in `unique`, meaning no section the tool considers its own. This run kept it on objectives rather than on the score, and the reassessment trigger is named: after this task removes `## Installing`, check whether what remains is taught by wiki/installing.md and wiki/updates.md. If it is, the page returns for a fold verdict.

##### Draft

Remove `## Installing` at lines 85-102 and leave a link to the install page in
its place.

Two things must survive the removal. The measured RTF of 0.96 at line 102 has
its only other home in `wiki/raw/macos-status.md`, which never publishes, so it
moves into a surviving section of this page. The start-and-stop material from
`wiki/install-macos.md:118-126` lands here and extends the single sentence at
lines 81-83, because this page is where a macOS reader looks for it once the
install page is one page for both platforms.

Note that lines 111-114 carry the reasoning for why there is no in-app updater
on macOS, tied to the app being unsigned. That reasoning is macOS-specific, is
not in `wiki/installing.md:140-146`, and is part of why this page keeps. Do not
lose it.

### T7: Retype Getting started to concept and give it the download location

The page is declared a how-to and has no task steps, duplicates two sections
that survive elsewhere, and is the only page written for a reader who does not
yet have an installer. That last property is why it keeps, and it is the only
correct home for the corpus's largest gap.

##### Details

- Agent State: Backlog
- Type: Restructure
- Scope: M
- Confidence: High
- Sizing evidence: wiki/getting-started.md, read in full this run. Frontmatter line 4 reads `type: how-to`. `## What you need` at lines 34-46 carries the side-by-side Windows and macOS requirements and the house-and-window framing. `## Three steps to a running house` at lines 48-60 restates the three beats that wiki/first-run.md:22-30 states. `## Where to go next` at lines 62-76 restates the routing that wiki/_index.md:29-67 carries. `## Before you start` at lines 78-83 carries the pre-alpha caveat.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T7.research.json
- Open questions:
  - Where does a reader download Hearth? No page in wiki/ names a source. The research pass reported that a case-insensitive grep across wiki/ excluding raw/ for release links, .dmg, and download phrasing returned no reader-facing download location, and that wiki/installing.md:24 treats holding the installer as already true. This task cannot close the gap until someone names the location, and the page should not invent one.

##### Draft

Retype the frontmatter from `how-to` to `concept`, and write to the concept
shape at `wiki/page-types.md:138-154`: what Hearth is in the reader's terms,
why it works that way including what it deliberately does not do, and links out
to the how-to pages that act on it. The shape forbids procedures, so the
download location is stated rather than given as numbered steps.

Keep `## What you need` at lines 36-46, which is written for a reader who has
not chosen a platform and is the passage the consolidation pass listed as
salvage. Keep the house-and-window framing and the pre-alpha caveat.

Drop `## Three steps to a running house` and `## Where to go next`. Both are
duplicates of pages that survive, and the routing belongs to `wiki/_index.md`
under `wiki/page-types.md:93`.

Add where to get Hearth, subject to the open question above. If the location is
still unknown when this task runs, the honest page says the gap exists rather
than guessing, and the gap goes to `wiki/whats-not-here.md`.

### T8: Write the reader-facing first-run walkthrough

The install page hands a reader off to do first run, and the page it hands them
to is a design record ending in four unresolved open questions. This is the page
that receives the handoff.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: M
- Confidence: High
- Sizing evidence: wiki/first-run.md, read in full this run. `## Beat two: making someone` runs lines 208-292 and `## Beat three: the second brain` runs lines 294-320; both contain reader-facing material inside a page whose frontmatter line 4 declares `type: decision-record` and whose lines 322-333 are a four-item open-questions section. wiki/installing.md:121-126 and wiki/getting-started.md:53-60 both route a reader there to perform first run. wiki/page-types.md:150-154 states that a concept or record page containing steps belongs on a how-to page it links to. wiki/_index.md:34 already carries a `## Meeting your persona` section.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T8.research.json
- Open questions:
  - Should wiki/first-run.md be renamed once this page exists, so that a decision record and a reader-facing how-to are not both called first run? The rename touches eight inbound references and is deferred rather than decided here.
  - Is `wiki/meeting-your-persona.md` the right filename, given the reader's task spans the persona interview and the second-brain setup? The alternative considered was keeping the reader-facing page at `wiki/first-run.md` and renaming the record, which was rejected on the inbound-link cost.

##### Draft

A new page at `wiki/meeting-your-persona.md`, H1 "Meeting your persona",
written to the how-to shape at `wiki/page-types.md:108-127`: action-title
sections with numbered steps inside them, one action per step, imperative mood.

It covers what a reader does after the install proves itself: Sulivan interviews
them and they build a persona together, then the persona they made sets up the
second brain and takes one real thing into it.

Take the reader-facing material from `wiki/first-run.md` beats two and three.
Leave behind everything that makes that page a record: the dated decisions, the
tool parameter schemas at lines 258-286, the persona cache invalidation note at
lines 288-292, and the open questions. Nothing is deleted from `first-run.md`
by this task; the record keeps its content and gains a link to this page.

### T9: Give Installing Hearth a how-to spine and absorb the macOS salvage

The page is declared a how-to and contains no numbered step anywhere. Absorbing
the only numbered procedure in the cluster is both what fixes that and what
makes the macOS page's retirement safe.

##### Details

- Agent State: Backlog
- Type: Restructure
- Scope: M
- Confidence: High
- Sizing evidence: wiki/installing.md and wiki/install-macos.md, both read in full this run. wiki/installing.md contains no numbered list between line 22 and line 147, and its abstract at lines 26-27 calls itself "the narrative version of the install". wiki/page-types.md:114-116 requires action-title sections with numbered steps inside them. The passages to absorb are wiki/install-macos.md lines 43-53, 32-34, 76-77, 128-133 and 135-155, and wiki/clients/windows.md lines 153-161 and 196-202.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T9.research.json
- Open questions:
  - Is the plan's download figure meant to cover four provisioned items or the two it sums? crates/hearth-probe/src/plan.rs:214-234 sums the model build and the voice only, while wiki/installing.md:95-97 and wiki/install-macos.md:84-86 both describe four things downloading. Either the prose is overstating what the number covers, or the inference engine and Python runtime are fetched by a path outside the planner that this pass did not find.
  - What context window does an 8 GB Mac actually plan? Both install pages say 17,408 tokens. The value has the right shape (crates/hearth-probe/src/plan.rs:280-283 rounds to a multiple of 1024) but no fixture asserts it, and confirming it needs the planner run rather than read.
  - The two pages print the same plan table with different rows: wiki/install-macos.md:72-78 carries Backend and Mind-and-voice rows that wiki/installing.md:68-73 drops. Which row set is correct for each machine, and does the merged table keep all five rows?

##### Draft

Reshape the page to the how-to spine, keeping its platform parameterization:
`### macOS` and `### Windows` already exist under `## Before you start`.

Absorb from `wiki/install-macos.md`, preserving each passage rather than
paraphrasing it away: the right-click-Open procedure at lines 43-53, which is
the only numbered procedure in the cluster and which this page currently only
mentions exists at lines 130-131; the verbatim decline message at lines 32-34;
the Backend and Mind-and-voice plan rows at lines 76-77; the uninstall at lines
128-133, of which this page has only the one-line version at line 92; and the
troubleshooting section at lines 135-155, with its log filenames and four named
failure modes.

Absorb from `wiki/clients/windows.md` the install root tree at lines 153-161,
because this page has no Windows equivalent, and the four-tier dictionary
description at lines 196-202, because lines 74-78 here describe only two
machine sizes.

Do not write the Windows procedure. That is T10 and it is blocked.

This task runs after T1, which corrects the sentences this one moves around.

### T10: Write the Windows install procedure

Installing Hearth is parameterized by platform and, once the macOS procedure
lands, gives numbered steps for one of the two platforms it covers. A Windows
reader following the journey reaches step one and stops.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: L
- Confidence: High
- Sizing evidence: wiki/installing.md, read in full this run. `### Windows` at lines 48-56 states requirements and then hands off to a platform overview, with no numbered step. wiki/install-macos.md:17-19 states that everything on the macOS page was measured on the machine it describes, and no equivalent Windows record exists in the corpus. Sized L because the page it lands on is the corpus's install spine and the content is net-new rather than moved.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T10.research.json
- Open questions:
  - Has anyone performed and recorded a Windows install end to end? This is the blocker. wiki/install-macos.md:17-19 sets the standard for this corpus, which is that install numbers come off the machine rather than from an estimate, and no Windows equivalent exists. Writing numbered Windows steps from source-reading alone would invent a procedure and publish it as measured.
  - Does the Windows installer present the same screens as the macOS one, and does it need an unsigned-app equivalent of the right-click-Open step?

##### Draft

Blocked, and recorded as blocked rather than attempted. It does not open until
someone runs a Windows install and records what the screens actually do.

When it is unblocked, the deliverable is a `### Windows` procedure inside
`wiki/installing.md` in the same shape as the macOS one T9 lands, not a
separate page. That is the ratified architecture, and T12 is what makes the
register agree with it.

### T11: Update the wiki index for the retirement and the new how-to

The index lists a page that will not exist and does not list a page that will.
It is the nav every retirement in this cluster edits.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: wiki/_index.md, read in full this run. Line 31 lists Installing on macOS under `## Getting started`, alongside line 29 Getting started and line 30 Installing Hearth. `## Meeting your persona` at line 34 lists First run at line 41. Line 7 names getting-started.md in the frontmatter `related` list.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T11.research.json
- Open questions:
  - None.

##### Draft

Remove line 31. Line 29 stays, because `wiki/getting-started.md` keeps under the
revised verdict, and the prose under `## Getting started` at lines 24-27 should
say what each of the three remaining pages is for now that the set has changed.

Add `wiki/meeting-your-persona.md` to `## Meeting your persona`, before or after
First run depending on which a reader wants first. `wiki/page-types.md:82-86`
requires prose under each heading before its links, and
`wiki/page-types.md:93-94` requires every published page to appear exactly once
and the section order to be the reading order.

Runs after T7 and T8 so the pages it names exist in their final shape.

### T12: Restate the Windows gap as steps inside Installing Hearth

The register of unwritten pages describes the missing Windows work as a page
mirroring Installing on macOS. Under the ratified architecture the missing work
is a section, and the page it would mirror will not exist.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: wiki/whats-not-here.md, read in full this run. Lines 23-25 read "**Installing on Windows.** [Installing on macOS](install-macos.md) is the shape it will take. What differs is the numbers and the CUDA voice build. Until it exists, [Hearth on Windows](clients/windows.md) covers what the app does."
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T12.research.json
- Open questions:
  - None.

##### Draft

Rewrite entry 1 so the gap is the Windows steps inside
[Installing Hearth](installing.md), not a separate page, and so it stops naming
`install-macos.md` as the shape. This is the entry that closes when T10 lands,
and it is the only place in the corpus that should announce the gap at all:
T2 and T4 remove the other three announcements.

### T13: Redirect the Installing on macOS link on Updating an install

The page links into `install-macos.md` in prose and names it in frontmatter.
Both break when that page is retired.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: wiki/updates.md, read at the two matching locations this run. Frontmatter line 4 reads `type: concept` and line 8 lists `install-macos.md` under `related`. Line 105, under `## The decision underneath: signing`, reads "Hearth is not signed. That is why [`install-macos.md`](install-macos.md) tells people to right-click and choose Open on first launch".
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T13.research.json
- Open questions:
  - Only lines 1-11 and 102-108 of wiki/updates.md were read this run. Whether the page carries any other dependency on install-macos.md is for the research stage to establish.

##### Draft

Point line 105 and the frontmatter entry at `wiki/installing.md`, where the
right-click-Open step lands under T9. The sentence's claim about signing is not
in question; only its referent is.

### T14: Drop install-macos.md from the Building a Hearth release frontmatter

A single frontmatter entry naming a page that is being retired.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: XS
- Confidence: High
- Sizing evidence: wiki/releasing.md:9, which lists `install-macos.md` in the frontmatter `related` list. A corpus grep for `install-macos` returns no other match in this file, so the page's prose does not reference it. The Shape is taken from wiki/page-types.md:103, which names Building a Hearth release as a how-to in the corpus.
- Sources of truth: (none, XS route runs no research)
- Docs: (none, XS route runs no research)
- Artifacts:
  - Author: tasks/docs/artifacts/T14.author.json
- Open questions:
  - None.

##### Draft

Remove `install-macos.md` from the `related` list at line 9. Replace it with
`installing.md` if the list does not already carry it. Change nothing else on
the page.

### T15: Extract the how-to and reference material from What the desktop app is

A single section of a platform overview runs 1135 words with no subheading and
is largely procedure and catalog, which the page-type reference sends to a
how-to page and a reference page respectively.

##### Details

- Agent State: Backlog
- Type: Restructure
- Scope: L
- Confidence: High
- Sizing evidence: wiki/clients/windows.md, read in full this run. `## What the desktop app is` runs lines 28-143. `python scripts/lint_wiki.py --warnings` reports `wiki/clients/windows.md:28: [long-section] 1135 words under "What the desktop app is" with no H3`, and three `reader-drift` findings at lines 105, 125 and 137 naming "the operator". The section covers session management at lines 96-123, the memory tree at lines 67-89, and file permissions at lines 125-143, all of which teach a reader to do something. wiki/page-types.md:249-250 states that reference material moves to a reference page and that a platform overview describes rather than catalogs.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T15.research.json
- Open questions:
  - Where does the extracted material land? The how-to content covers sessions, the memory tree, and file permissions, and none of those is desktop-only in principle. Whether it becomes one new how-to page, several, or sections on existing feature pages is for the research stage to decide, and it may exceed one page, in which case this task splits.
  - Is this material Windows-specific at all? If the same surfaces exist on macOS, keeping it on the Windows page is itself the defect, and the extraction target is a shared page rather than a Windows one.

##### Draft

Do not start by cutting. Establish first where each block belongs, because the
research stage's `affected_docs[]` is what decides whether this is one task or
several.

The page keeps its platform-overview job: what the Windows app is, what it
supervises, what it needs, and what it cannot do yet. The process tree at lines
168-181 and the install root tree at lines 153-161 are catalog material, and
the latter is already moving to `wiki/installing.md` under T9, so check what T9
left before moving it twice.

This task does not change the keep verdict for the page and does not block T16.

### T16: Retire Installing on macOS once every salvage task is Complete

The fold verdict, executed. This is the one irreversible step in the plan and
it is held until the salvage has landed.

##### Details

- Agent State: Backlog
- Type: Consolidate
- Scope: S
- Confidence: High
- Sizing evidence: wiki/install-macos.md, read in full this run. Six passages live nowhere else and are listed in the salvage table above: lines 32-34, 43-53, 76-77, 118-126, 128-133 and 135-155. A corpus grep for `install-macos` returns inbound references at wiki/_index.md:31, wiki/installing.md:7,14,27,132, wiki/whats-not-here.md:23, wiki/clients/windows.md:10,14,233, wiki/releasing.md:9, wiki/updates.md:8,105 and wiki/clients/macos.md:7,11,29,89,127.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T16.research.json
- Open questions:
  - Should the page be deleted or demoted to `wiki/raw/`? Demotion is the landing when the call is close, and this page was measured end to end on a real machine on 2026-08-07, which is a provenance worth keeping even after its prose has moved. Demotion also keeps it out of the published wiki, since the publish step strips `raw/` per wiki/whats-not-here.md:36-40.

##### Draft

**Do not open this task until T6, T9, T11, T12, T13 and T14 all read
`Complete`.** That is integrity rule 9 and it is the whole reason this task
exists separately from T9.

Before running it, verify two things rather than assuming them: that every
passage in the salvage table appears in its destination, and that the corpus
grep for `install-macos` returns nothing outside this page. A fold that misses
an inbound reference leaves a dead link on a page that was correct before.

The recommendation is demotion to `wiki/raw/` rather than deletion, subject to
the open question above.
