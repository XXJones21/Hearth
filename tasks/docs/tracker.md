---
area: docs
status: open
updated: 2026-09-03
---

# Wiki task list

**Corpus root:** wiki/
**Date:** 2026-09-03
**Updated:** 2026-09-03 (Phase A run: T2 through T5, all four Complete)

The install cluster consolidation, the first-run split, and the documentation
defects the `graph` pass verified against the source tree. The decision record
behind every verdict here is `tasks/docs/artifacts/G1.research.json`, read in
full and reconciled against the linter and the doc graph before any task was
written.

## Task matrix

| ID | Task | Type | Shape | Scope | Confidence | Phase | Agent State | Score |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| T1 | Correct the 8 GB contradiction, the Windows install root, and the two download claims in Installing Hearth | Fix | how-to | S | High | A | Complete | 6 |
| T2 | Correct the Windows install root and reconcile the coexistence sentence on Hearth on Windows | Fix | platform-overview | S | High | A | Complete | 5 |
| T3 | Correct the install root and the 8 GB example in the First run record | Fix | decision-record | S | High | A | Complete | 5 |
| T4 | Correct the download figure and retire the Windows-guide announcement on Hearth on macOS | Fix | platform-overview | S | High | A | Complete | 1 |
| T5 | Correct the settings-screen claim and state the persona-creation route on Personas | Fix | concept | M | High | A | Complete | 7 |
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
| T17 | Correct the install root and the coexistence claim on Build pipeline | Fix | how-to | S | Medium | A | Backlog | |
| T18 | Correct the Windows install root on Native runtime | Fix | decision-record | S | Medium | A | Backlog | |
| T19 | Correct the Hearth home folder path on The second brain | Fix | concept | S | Medium | A | Backlog | |
| T20 | Capture the plan screen figure for Installing Hearth | Add | how-to | XS | High | | Backlog | |
| T21 | Capture the first-run voice check figure for Installing Hearth | Add | how-to | XS | High | | Backlog | |
| T22 | State the Windows floor in Before you start on Installing Hearth | Add | how-to | S | High | | Backlog | |
| T23 | Name which downloaded artifacts carry no published sha256 | Add | how-to | S | Medium | | Backlog | |
| T24 | Record the corpus unit convention as a decision | Add | decision-record | S | Medium | | Backlog | |
| T25 | The planner still warns a Windows reader that Hearth will install WSL | Fix | (product, not a page) | S | High | | Backlog | |
| T26 | Correct the create_persona domain and the unreachable-tools audit on The tool catalog | Fix | reference | M | High | F | Backlog | |
| T27 | Correct the permanent-reference and pending-voice claims on Voice | Fix | concept | S | High | F | Backlog | |
| T28 | Retire the solved cache-invalidation problem in the First run record | Fix | decision-record | S | High | G | Backlog | |
| T29 | Correct the sha256 claim on Hearth on Windows | Fix | platform-overview | S | High | F | Backlog | |
| T30 | Retire the fourth Windows-guide announcement on Installing Hearth | Fix | how-to | XS | High | F | Backlog | |
| T31 | Three product defects on the persona creation path | Fix | (product, not a page) | S | High | | Backlog | |
| T32 | No page documents the Personas page the clients point at | Add | (undecided) | M | Medium | | Backlog | |
| T33 | Give Hearth on Windows the platform-overview shape and move its catalogs out | Restructure | platform-overview | L | High | | Backlog | |
| T34 | State the Windows requirements floor on Hearth on Windows | Add | platform-overview | M | High | | Backlog | |
| T35 | Settle where the portability ledger's material is published | Fix | (undecided) | M | Medium | | Backlog | |
| T36 | Give Hearth on macOS the platform-overview shape and write its missing sections | Restructure | platform-overview | L | High | | Backlog | |
| T37 | Establish whether any client can change the default persona | Fix | concept | S | Medium | | Backlog | |
| T38 | Settle whether concept pages take action-title headings | Fix | reference | S | Medium | | Backlog | |
| T39 | Capture the On disk pane figure for Hearth on Windows | Add | platform-overview | XS | High | | Backlog | |
| T40 | Capture the Personas page figure for Personas | Add | concept | XS | High | | Backlog | |

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
| F | T26, T27, T29, T30 | The pages the Phase A research stage found that no row owned. Four disjoint targets: `wiki/backend/tool-catalog.md`, `wiki/features/voice.md`, `wiki/clients/windows.md` and `wiki/installing.md`. |
| G | T28 | `wiki/first-run.md` again, after T3. It is alone in its phase for one reason: T3 owns the same page in Phase A, and a phase never contains a page twice. |

Phase A is safe to run before any of the rest, because a wrong sentence on a
surviving page is wrong whether or not anything folds.

T17, T18 and T19 join Phase A. They are the same class of defect on three pages
the `graph` pass did not examine, found by the T1 research survey, and their
targets do not overlap with each other or with T1 through T5.

T20 through T24 carry no phase yet. T20 and T21 are figure capture, which is
work for a person with a screenshot tool rather than for a writer agent. T22,
T23 and T24 target pages whose ownership is an open question on each task, and
a phase cannot be assigned before the target is settled.

T25, T31 and T32 carry no phase either. T25 and T31 are product defects, so no
writer stage runs on them at all. T32 has no settled target path, and a phase
groups tasks by the page they touch.

Phases F and G were opened by the Phase A run of T2 through T5. Every task in
them came out of a research stage rather than out of the `graph` pass, which is
the pattern this pipeline should expect: a corrections task that reads the source
tree properly finds the same defect on pages nobody surveyed.

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

Updated after the T1 run: `python scripts/lint_wiki.py` now returns 28 pages
checked, 0 errors, 200 warnings, and `--figures` returns 2 pending, both placed
on `wiki/installing.md` by the T1 review and opened as T20 and T21. The error
count is unchanged at 0, which is the gate that matters. The warning count moved
by two, both of them the new `figure-pending` work orders; `wiki/installing.md`
carries eight warnings, the two figures and six `long-paragraph`.

Updated after the Phase A run of T2 through T5. The linter was run twice, once
after the four authors returned and again after the four reviewers returned,
because on the T1 run a single pass raced the reviewer's edits and only the
second was valid.

| When | Pages | Errors | Warnings | Figures pending |
| :-- | :-- | :-- | :-- | :-- |
| After the four authors | 28 | 0 | 197 | 2 |
| After the four reviewers | 28 | 0 | 198 | 4 |

Zero errors at both points, which is the gate. The warning count fell from 200
to 197 across the author stage and rose to 198 across the review stage, and the
whole of that rise is the two new `figure-pending` work orders less one
`long-paragraph` the reviewers cleared. The final breakdown is 95
`long-paragraph`, 65 `bold-lead`, 22 `long-section`, 12 `reader-drift` and 4
`figure-pending`. The two new figures are T39 and T40.

Neither the author, the reviewer, nor the orchestrator could execute commands in
this run. All four author agents and all four reviewer agents reported the
limitation explicitly rather than claiming a linter run they had not made, and
several established what the linter owns by reading `scripts/lint_wiki.py` as a
file so that they did not report findings the linter already covers. Both linter
passes above were run by a separate subagent with a shell.

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

### T1: Correct the 8 GB contradiction, the Windows install root, and the two download claims in Installing Hearth

The page contradicts itself about the same machine forty lines apart, states a
Windows install root the planner does not produce, prints a download figure
beside a sentence naming more items than the figure counts, and states that
every downloaded file is hash-verified. All four are corrections to existing
sentences on one page, and none of them waits on a consolidation verdict.

The page's four size figures were dispatched as suspected defects and are not
defects. The research stage established that 3.77 GB, 7.14 GB, 4.5 GB and 8.6 GB
are the planner's byte counts rendered by the product's own `human()`, which
divides by 2^30 and labels the result GB, so they match what the installer
prints on screen and stay as they are.

##### Details

- Agent State: Complete
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: wiki/installing.md, read in full this run. Lines 39-42 under `### macOS` state that an 8 GB M2 MacBook Air runs the mind and the voice at once and speaks; lines 75-78 under `## The scan and the plan` state that on an 8 GB machine the honest phrasing is that the persona will think and speak one at a time. Lines 42-44 under `### macOS` state free disk of "roughly 4.5 GB on an 8 GB Mac and 8.6 GB on a 16 GB Mac". Lines 74-75 state a 16 GB machine gets Gemma 4 12B at 65,536 tokens "for a 7.14 GB download", and the plan table at lines 68-72 gives an 8 GB Mac a 17,408-token context window and a 3.77 GB download. Lines 85-86 under `## Choosing where it lives` state the default is `D:\Hearth` on Windows. Lines 96-97 under `## The download` list four things downloading.
- Sources of truth:
  - source: crates/hearth-probe/src/plan.rs, covers the whole budget arithmetic: reserves and the coexistence decision at 104-159, the context window at 163 and 279-283, the two-entry `downloads[]` and their sum at 214-234, `disk_required` as total plus a fifth at 236-237, and the small-machine warning string at 144-148 with the branch that pushes it
  - source: crates/hearth-probe/dictionary.yaml, covers every constant the arithmetic uses: reserves at 79-89, the per-platform voice engine at 91-129, tier 0 at 132-177 and tier 2 at 198-211, and the runtime artifacts at 27-67 whose bytes the planner never counts
  - source: crates/hearth-probe/src/machine.rs, covers the default install root per platform at 224-272 and the fixtures the figures are quoted from at 275-360
  - source: crates/hearth-probe/src/lib.rs, covers `human()` at 24-35, where every size the product prints is bytes divided by GiB under a `GB` label. This is what settles whether the page's figures are stale
  - source: crates/hearth-probe/tests/plan_fixtures.rs, covers the pinned contract for the 8 GB Air at 36-52, including the assertion that no `one at a time` warning is produced, and the context-window floor at 54-75
  - source: desktop-client/src-tauri/src/provision.rs, covers what is fetched outside the planner: the module contract at 1-14 and the backend, inference engine and Python runtime chains at 248-369
  - source: desktop-client/src/lib/probe.ts, covers the five provisioning rows at 120-134 and the client's own `human()` at 158-164, byte-identical to the Rust one
  - source: desktop-client/src/components/setup/SetupFlow.tsx, covers what the plan screen shows a reader: the per-item download rows and the `Download` total at 474-484 and 548, the context window and `Mind and voice` rows at 501-506, the panel title keyed on coexist at 446, and the install-root field seeded at 132
  - source: desktop-client/src-tauri/src/probe.rs, covers `probe_install_root` at 86-88, the default the setup screen displays, and the voice row that is counted but not fetched at 178-196
  - source: crates/hearth-probe/src/download.rs, covers the hash behaviour at 154-206: verification happens only where the dictionary carries a sha256, and a mismatch deletes the file and fails
  - source: desktop-client/src-tauri/src/config_gen.rs, covers HEARTH_HOME rendered as `<root>/home` at line 64, with the relative path from crates/hearth-probe/src/defaults.rs:46
  - contextual: wiki/page-types.md, covers the how-to shape at 96-128, which names Installing Hearth as a how-to in the corpus
  - contextual: tasks/docs/tracker.md, covers the recorded task state, the questions carried onto T1, and the ownership of T2 through T5
- Docs:
  - wiki/installing.md, `### macOS` lines 39-46, `## The scan and the plan` lines 58-79 (the table at 68-72, the sentence at 74-75, the sentences at 75-79), `## Choosing where it lives` lines 85-86, and `## The download` lines 96-97 and line 100
- Artifacts:
  - Research: tasks/docs/artifacts/T1.research.json
  - Author: tasks/docs/artifacts/T1.author.json, wrote wiki/installing.md
  - Review: wiki/installing.review.json, verdict NEEDS_WORK, score 1 to 6
- Verification: `python scripts/lint_wiki.py` reports 28 pages checked, 0 errors, 200 warnings, run after the reviewer's edits. `python scripts/lint_wiki.py --figures` reports 2 figures pending capture, both added by the reviewer on this page and both opened as T20 and T21. Neither the author nor the reviewer nor the orchestrator could execute commands in this run, so both linter passes were run by a separate subagent with a shell.
- Open questions:
  - Which machines actually take turns between the model and the voice, and at what memory? The author reported writing the general behaviour and naming no machine class, because the only band available is derived by hand rather than from an executed planner run and no fixture exercises it.
  - Do wiki/clients/macos.md:51-54 and wiki/install-macos.md:84-86 get the same treatment this task gave the four-things sentence? The author reported keeping all four items and adding a sentence naming what the plan figure counts, and reported that a different choice on those pages would leave the corpus inconsistent. Those pages are T4's and T16's.
  - How many bytes do the inference engine and the Python runtime add on top of the plan's download figure, and should a page say so? The author reported that the page now tells a reader the figure is incomplete without telling them by how much, and that the voice environment's pip installs have no recorded size at all.
  - Should a page name which downloaded artifacts carry no published sha256? The author reported that the page now claims verification only for files that carry a hash, and does not name the exceptions, so a reader cannot learn from this page what is unverified.
  - Was the linter run against this edit? The author reported that it could not execute commands in its session and checked the mechanical conventions by reading instead. See the orchestrator's verification note below.
  - Should wiki/installing.md keep the product's unit convention, GiB printed under a GB label, or restate its figures in decimal GB? The four figures at lines 42-44, 72 and 75 are correct under the first and wrong under the second, and the same bytes produce the dispatching lead's 4.05, 4.86, 7.66 and 9.19. Matching what the installer prints on screen argues for keeping the page as it is; nothing in wiki/style-guide.md or wiki/page-types.md states a rule, and this run found no source that settles which convention the corpus should use.
  - Does T1 correct the sentence at wiki/installing.md:96-97 by narrowing it to the two items the plan's number counts, or by keeping all four and separating the number from the sentence? Both are true statements; the choice is the author's and this stage does not make it. Whichever is chosen has to be made consistently across wiki/clients/macos.md:51-54 and wiki/install-macos.md:84-86, which say the same thing.
  - Does the corpus want to state the provisioning bytes the plan figure omits, roughly 35 MB on macOS and 657 MB on Windows with CUDA? It is a real gap for a reader on a metered connection, but naming it is new content rather than a correction, and T1 is a corrections-only task per tasks/docs/tracker.md:309-311.
  - Is wiki/installing.md:100, `Every file is verified against a published sha256 hash once it lands`, T1's to fix or a new tracker row? It is contradicted by source, it sits inside the `## The download` section T1 already opens, and it is outside the task statement. This stage records the defect and does not decide the ownership.
  - Do wiki/backend/build-pipeline.md:106 and :158, wiki/backend/native-runtime.md:79, and wiki/features/second-brain.md:64 get tracker rows? All four are contradicted by source, all four carry defects T1 through T5 are correcting elsewhere, and none is owned by any task in tasks/docs/tracker.md. build-pipeline.md:158 in particular is a fourth instance of the coexistence claim.
  - Is the coexistence sentence at wiki/clients/windows.md:199-201, carried as an open question on T2, correct? This run derived that an 8 GB dedicated GPU plans tier 1 with the voice resident and does not take turns, and that the !coexist branch is reached at roughly 4.5 to 5.4 GB of VRAM. That is arithmetic from crates/hearth-probe/src/plan.rs:110-159 and dictionary.yaml, not an executed planner run, and the page is T2's to settle, so it is passed on rather than answered.
- Orchestrator rulings on two of the questions above, recorded so the author is not left choosing:
  - The unit question is settled for this task by leaving the figures alone. The page matches what the installer prints, and a corrections task does not introduce a disagreement between a page and its own screen. Whether the corpus should state a unit policy stays open and is not T1's.
  - The sha256 sentence at line 100 is T1's. It is one contradicted sentence, on T1's page, inside a section T1 already opens, and the research stage established exactly which artifacts carry a hash and which do not. Leaving it would mean editing three lines above a sentence known to be false.

##### Draft

Lines 40-42 are the version that survives. Lines 75-78 are the sentences to
replace, and the replacement should still say something honest about a small
machine rather than deleting the thought, since saying so plainly in the
reader's language is the intent the passage was written for.

The install root sentence at lines 85-86 describes the corrected behaviour:
`Hearth` in the home directory on macOS, and on Windows `Hearth` on the
roomiest non-removable, non-system fixed drive, falling back to a visible
`Hearth` in the user profile on a single-drive machine.

The four size figures at lines 42-44, 72 and 75 do not change. They verify
correct against source under the product's own renderer.

The sentence at lines 96-97 and the number at line 72 are each true and
misleading beside each other. The sentence describes what provisioning does;
the number counts the model build and the voice weights only.

Line 100 overstates hash coverage. The model weights and the Python runtime are
hash-verified; the two OmniVoice GGUFs carry `sha256: null` and the llama.cpp
archives carry no sha256 field at all.

This task is corrections only. The page's structure belongs to T9, so the
author runs in `update` mode.

Notes from the author, on where the delivered change departed from the
direction above:

- On the download sentence, the author reported choosing to keep all four items
  and add one sentence naming what the plan figure counts, rather than narrowing
  the sentence to two. The reason given was that narrowing would drop true
  information a reader on a metered connection needs.
- On the 8 GB replacement, the author reported not restating that the plan
  explains its own reasoning including anything it traded away, because the page
  already says that two sentences earlier, and reported keeping only the half
  that was not already on the page.
- At `## Choosing where it lives`, the author reported splitting the existing
  paragraph in two at the corrected sentence, because the longer correct sentence
  pushed the paragraph past the style guide's length, and reported changing no
  wording outside the corrected sentence.

### T2: Correct the Windows install root and reconcile the coexistence sentence on Hearth on Windows

The page states a Windows install root the planner does not produce, and
carries a sentence about the model and the voice not staying loaded together
that resembles a claim corrected elsewhere but concerns a different machine
class.

##### Details

- Agent State: Complete
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: wiki/clients/windows.md, read in full this run. Line 151 under `## What the installer gives you` states the install root is `D:\Hearth` by default. Lines 199-201 under `## The hardware probe picks your model` state that on a smaller GPU Hearth says the model and the voice cannot both stay loaded at the same time. Lines 232-234 under `## Status` announce a Windows install guide mirroring Installing on macOS.
- Sources of truth:
  - source: crates/hearth-probe/src/machine.rs:224-272, covers the per-platform default install root: `default_install_root()` and `roomiest_non_system_drive()`
  - source: crates/hearth-probe/src/plan.rs:100-159, covers the coexist branch, the take-turns branch, the refusal, and the budget arithmetic they turn on
  - source: crates/hearth-probe/src/plan.rs:14, 25, 279-321, covers MIN_CTX, TARGET_CTX, `ctx_for()`, and the fit thresholds in `best_fit()`/`fit_at()` that set the smallest budget a plan can be built from
  - source: crates/hearth-probe/dictionary.yaml:69-129, covers the reserves (stt_bytes, headroom_bytes, os_unified_bytes, voice_resident_bytes) and the two voice engines with cpp_platforms
  - source: crates/hearth-probe/src/dict.rs:62-78, covers `uses_cpp()` and `resident_for()`, which decide that Windows holds the ~0.9 GiB cpp voice rather than the 2.2 GiB torch voice
  - source: crates/hearth-probe/dictionary.yaml:131-231, covers the four tiers, their byte sizes, their kv_bytes_per_token, their max_ctx, and tier 0's build ladder
  - source: crates/hearth-probe/src/machine.rs:274-362, covers the five shipped simulate fixtures and the FIXTURES list
  - source: crates/hearth-probe/src/plan.rs:323-381, covers the planner unit tests, which pin the 8 GB Air, the RTX 4080, the tiny refusal and the no-GPU fallback
  - source: crates/hearth-probe/src/lib.rs:26-34, covers `human()`, which divides by 2^30 and labels the result GB, so every figure the plan screen prints is a GiB wearing a GB label
  - source: desktop-client/src-tauri/src/provision.rs:240-243 and 480-483; desktop-client/src-tauri/src/config_gen.rs:25; desktop-client/src-tauri/src/probe.rs:113 and 153; desktop-client/src-tauri/src/house.rs:146; crates/hearth-probe/src/defaults.rs:69, covers the install-root layout: hearth-install.json, models, runtime, envs/voice, config, logs
  - source: scripts/lint_wiki.py:133-143, 284-297, 372, 455-456, covers that an unresolvable `related` entry and a dead body link are both errors, while a `sources` entry is only checked for an absolute path
  - contextual: wiki/installing.md:96-99, covers the corpus's already-corrected statement of the default install root, landed by T1
  - contextual: wiki/page-types.md:214-253, covers the platform-overview shape, including the rule against a dated status log
  - contextual: wiki/whats-not-here.md:21-25, covers the register for pages that are not written yet, which is where the Windows-guide gap belongs
  - contextual: tasks/docs/tracker.md:24, 393-436, 782-788, 1059-1078, covers the recorded state of T2, the draft it carries, and which rows own the neighbouring defects
- Docs:
  - wiki/clients/windows.md, frontmatter (`related` line 10, `sources` line 14), `## What the installer gives you`, `## The hardware probe picks your model`, and `## Status`
- Artifacts:
  - Research: tasks/docs/artifacts/T2.research.json
  - Author: tasks/docs/artifacts/T2.author.json, wrote wiki/clients/windows.md
  - Review: tasks/docs/artifacts/T2.review.json, verdict FAIL, score 1 to 5
- Review checklist, and where each entry went:
  - F5 opening does not orient, F3 false 8 GB tier claim, F4 coexistence sentence under-informs, F6 first-launch sequence as prose, F7 missing figure, F10 misaligned tree column: all `done` by the reviewer.
  - F8 sha256 claim: `deferred` to T29. The reviewer adds that the claim is repeated inside the fenced tree at line 156 as "model weights, sha256-verified", so a fix aimed at the prose alone will miss it. Recorded on T29.
  - F1 type-mixture, install and process catalogs on a describing page: `deferred`, `needs: restructure`, no owner existed. Opened as T33.
  - F9 dated status log occupying the honest-limits section: `deferred`, `needs: restructure`, no owner existed. Opened as T33 alongside F1, since both are the same section's shape.
  - F2 missing spine, the page states no requirements floor at all: `deferred`, `needs: restructure`, and the reviewer reports it also blocked on research. Opened as T34.
- Objective gaps recorded by the reviewer, which derived six objectives because neither the page nor the research artifact records any:
  - "Decide whether your Windows machine can run Hearth" is not taught. The reviewer reports the page states no floor of any kind. This is a task, opened as T34, and it is the largest reader gap on the page.
  - "Name what Hearth on Windows cannot do yet" is not taught. The reviewer reports the limits exist but are scattered across three sections. This is a task, opened as T33.
  - "Install Hearth on Windows" is not taught, and the reviewer records that as correct rather than as a gap, since the procedure is T10 and is blocked. Recorded so it is not read as an oversight.
  - The reviewer also reports two blocks of content serving no objective: the process tree with its five port numbers, and the file-tool paragraphs, which it reports would read identically on the macOS page. Both are recorded on T33 rather than charged twice.
- Open questions:
  - At what GPU size does the plan stop holding the model and the voice resident at the same time on Windows, and which machines does that describe? The author reported writing the mechanism with no machine class, on the orchestrator's ruling, and reported that the corpus still states the threshold nowhere and states nowhere that Windows holds the smaller omnivoice.cpp voice while Linux holds the torch one.
  - What does a frontmatter `sources` entry mean once its source page is retired? The author reported leaving `wiki/install-macos.md` at wiki/clients/windows.md:13 exactly as found, per the orchestrator's ruling, and reported that it will name a file that does not exist once T16 runs.
  - Was the linter run against this edit? The author reported that it could not execute commands in its session and checked the two length rules by hand instead, counting the split paragraphs at roughly 51 and 43 words against a 60-word limit. See the verification note below.
  - Is the phrase at `## The hardware probe picks your model` describing the smallest tier as one that "fits an 8 GB GPU" correct? The author reported noticing that the research artifact's own derivation puts an 8 GB card on tier 1 rather than tier 0, reported that no claim contradicts the phrasing, and reported that no task owns it.
  - Does any graphics card Hearth supports actually ship with VRAM inside the take-turns band of roughly 4.47 to 5.43 GB decimal? Nothing in the tree names one, and if none exists the corrected sentence at wiki/clients/windows.md:199-202 should drop the machine-class example rather than restate it with a band, because a page that describes a machine nobody owns is no more useful to a reader than one that describes the wrong machine.
  - If the corrected sentence does name a figure, which unit does it use? crates/hearth-probe/src/lib.rs:26-34 prints 4.16 GB where the decimal reading of the same threshold is 4.47 GB, so a reader comparing the page against the plan screen sees two different numbers for one boundary. tasks/docs/tracker.md carries this as T24, unresolved.
  - Should T2 also remove the `sources: wiki/install-macos.md` entry at wiki/clients/windows.md:14, or only the `related` entry at line 10 and the prose link at line 233? scripts/lint_wiki.py:284-286 never validates `sources`, and the entry records genuine provenance, so removing it discards a true record while keeping it names a file that will not exist after T16.
  - Who owns the uncorrected sha256 claim at wiki/clients/windows.md:204-207? It is the same defect T1 corrected on wiki/installing.md, it is contradicted by crates/hearth-probe/dictionary.yaml:25-26, 117 and 120, and T23 is scoped to a different page. It needs a row, whether that is T2 widened or a new one.
- Orchestrator rulings, so the author is not left choosing:
  - The take-turns question is settled by the research stage as far as source can settle it: the branch at crates/hearth-probe/src/plan.rs:137-150 is live and reachable, and is reachable only between 4,466,165,856 and 5,432,533,497 bytes of VRAM, which is narrower than any GPU the tree names. The author drops the machine-class example and keeps the mechanism, because the corpus cannot name the machine.
  - Both the `related` entry at line 10 and the prose link at line 233 are T2's, because scripts/lint_wiki.py:290-297 and 372 make each a hard error once T16 lands. The `sources` entry at line 14 stays: it is provenance, the linter never resolves it, and rewriting a page's history is not a corrections task.
  - The sha256 claim at lines 204-207 is not T2's. It is opened as T29 rather than widened into this task, because T2's statement names two defects and the research stage found this one outside them.

##### Draft

The install root at line 151 takes the corrected behaviour named in T1.

The announcement at lines 232-234 is retired: the register for unwritten pages
is `wiki/whats-not-here.md`, and under the ratified verdict the missing work is
a Windows section inside `wiki/installing.md` rather than a page mirroring
`install-macos.md`. Keep a link to the install page; drop the promise.

Lines 199-201 are not to be changed until the open question is settled. If the
sentence is right for a small Windows GPU, it stays.

Note from the T1 run: `tasks/docs/artifacts/T1.research.json` reports deriving,
from crates/hearth-probe/src/plan.rs:110-159 and dictionary.yaml rather than
from an executed planner run, that an 8 GB dedicated GPU plans with the voice
resident and does not take turns, and that the take-turns branch is reached at
roughly 4.5 to 5.4 GB of VRAM. The research stage passed this on rather than
answering it, because the page is T2's. The T2 research stage confirmed it at
source: the band is 4,466,165,856 to 5,432,533,497 bytes, which is T1's figure
read as decimal GB.

Notes from the author, on where the delivered change departed from the
direction above:

- The author reported being unable to execute commands, so it could not run
  `scripts/lint_wiki.py` and checked the length rules by hand instead. It asked
  that the hand counts not be read as a linter run.
- On the link left in `## Status`, the author reported pointing it at
  `wiki/installing.md` rather than a Windows-specific guide, because that is the
  page surviving T16, and reported taking the link text from that page's own
  `title`.
- The author reported moving the verified 16 GB coexistence fact into the second
  half of the split paragraph rather than losing it with the sentence it sat in.

### T3: Correct the install root and the 8 GB example in the First run record

The record states a Windows default in its install-root tree that the same page
then describes correctly fifty lines later, and it uses an 8 GB machine as the
worked example of a design principle that the machine no longer demonstrates.

##### Details

- Agent State: Complete
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: wiki/first-run.md, read in full this run. Frontmatter line 4 reads `type: decision-record`. Line 112, inside the fenced tree under `### One folder, and deleting it is the uninstall`, annotates the root as "the chosen folder, D:\Hearth by default". Lines 161-163 under `### The scan is not only about picking a model` state the roomiest-non-system-drive rule correctly. Lines 182-186 under `### Say what you found, and be honest about it` use an 8 GB machine as the example where the brain and the voice cannot both stay resident.
- Sources of truth:
  - source: crates/hearth-probe/src/machine.rs:232-251, covers `default_install_root()`: the per-platform default install root, including the Windows roomiest-non-system-drive branch, the visible Hearth fallback on macOS and Windows, and the .hearth dotdir on Linux
  - source: crates/hearth-probe/src/machine.rs:256-272, covers `roomiest_non_system_drive()`: filters removable drives and the SystemDrive, then takes max available_space; None on a single-drive machine, which is what routes the default to the home directory
  - source: crates/hearth-probe/src/plan.rs:104-159, covers the coexist arithmetic: base reserves, the coexist and sequential budgets, the !coexist branch and the take-turns warning string, and the TooSmall refusal
  - source: crates/hearth-probe/src/plan.rs:279-321, covers `ctx_for`, `best_fit` and `fit_at`: the TARGET_CTX-then-MIN_CTX search and the weights-plus-floor fit test that sets the minimum viable budget
  - source: crates/hearth-probe/dictionary.yaml:69-129, covers the measured reserves (voice_resident_bytes, stt_bytes, os_unified_bytes, headroom_bytes), the two voice engines, cpp_platforms [macos, windows], and the cpp resident cost of 966367641 bytes
  - source: crates/hearth-probe/tests/plan_fixtures.rs:35-52, covers the pinned contract that an 8 GB Air coexists, and that no warning containing "one at a time" is emitted for it. The comment records that this test used to assert the opposite
  - source: crates/hearth-probe/src/plan.rs:337-344, covers the in-crate unit test `air_8gb_keeps_its_quant_and_its_voice`, asserting coexist on m1-air-8gb with the comment "the cpp voice fits alongside on 8 GB"
  - source: crates/hearth-probe/src/machine.rs:275-362, covers the five shipped fixtures and the FIXTURES list: rtx4080, m1-air-8gb, m1-air-16gb, no-gpu, tiny
  - canonical: wiki/page-types.md:156-181, covers the decision-record shape and its three rules, including the rejected-alternative rule at 177-179 and the retired-decision grep rule at 180-181
  - canonical: wiki/style-guide.md:173-180, covers the supersession mechanism the corpus actually prescribes: a SUPERSEDED banner scoped to a section, or fixing the invalidated content in the same edit
  - contextual: wiki/installing.md:44-46, 96-100, covers the already-corrected wording for both defects, landed under T1: the computed Windows root, and an 8 GB Mac running the model and the voice at once
- Docs:
  - wiki/first-run.md, `### One folder, and deleting it is the uninstall` and `### Say what you found, and be honest about it`
- Artifacts:
  - Research: tasks/docs/artifacts/T3.research.json
  - Author: tasks/docs/artifacts/T3.author.json, wrote wiki/first-run.md
  - Review: tasks/docs/artifacts/T3.review.json, verdict FAIL, score 2 to 5
- Review checklist, and where each entry went:
  - F4 the refusal example, F5 "the brain" used for the model, F6 filename link text, F7 "itemised": all `done` by the reviewer. The reviewer reports that both T3 corrections landed and that neither appears in `remaining[]`.
  - F1 type-mixture and F8 noun headings: `deferred` to T8, which already owns the extraction of the reader-facing walkthrough. Confirmed that T8 exists and covers them.
  - F2 the create_persona cache-invalidation claim: `deferred` to T28. Confirmed that T28 exists and covers it.
  - F3 the portability ledger pointers: `blocked`, `needs: research`. Opened as T35.
- Objective gaps recorded by the reviewer, which derived six objectives because neither the page nor the research artifact records any:
  - "Describe what happens from download to a companion" is taught, and the reviewer reports that as the problem rather than the success: an `understand` objective maps to a concept or how-to page and never to a decision record, and four pages link here for the walkthrough. It is evidence for the T8 extraction rather than a new task.
  - "Build the persona-creation conversation" and "run the second-brain conversation" are served by content the reviewer reports as belonging on another page: an authored skill document in imperative mood, and two tool parameter catalogs. Both go to T8, and the tool blocks want a reference home that T8's draft does not currently name.
  - "Say what would reopen these decisions" is not taught. The reviewer reports item 5 of the decision-record shape as absent, and reports that the page's Open questions section lists things never decided rather than conditions that would undo what was. Two candidates already in evidence: the retirement of the take-turns branch, and whether a Linux client ships. Recorded here as a task for T8's run to absorb rather than as a separate row, because it is the same page and the same restructure.
- Open questions:
  - Was the linter run against this edit? The author reported that it could not execute commands in its session and checked the two rules statically against scripts/lint_wiki.py instead, counting the replacement at 57 and 46 words with neither "the user" nor "the operator" in it. See the verification note below.
  - Does Hearth ship a supported Linux desktop client? This is the one platform whose arithmetic reaches the take-turns branch, and nothing in wiki/ states whether it ships. Until it is answered, no Linux machine may be named as the replacement example.
  - Should the be-honest passage at wiki/first-run.md:182-186 state the principle with no worked example at all, or re-anchor it on the refusal case at crates/hearth-probe/src/plan.rs:87-92, which is the only small-machine case the source still supports? Both are source-defensible and the choice is the author's; research declines to draft it.
  - Is the take-turns branch at crates/hearth-probe/src/plan.rs:137-150 still intended to ship, given crates/hearth-probe/tests/plan_fixtures.rs:40-41 says the orchestration it promises "may never need building for this class"? If it is being retired in code, the decision record should record that rather than merely dropping the example, and that is an engineering question this pass cannot settle.
  - Do the stale WSL doc comments at crates/hearth-probe/src/machine.rs:218-223 and 228-231 want a tracker row? They contradict wiki/backend/native-runtime.md and wiki/first-run.md:122-124, and no existing row owns them. Out of scope for T3, which is documentation-only. Answered by the orchestrator: folded into T25, which already owns the WSL residue in this crate.
  - tasks/docs/tracker.md:459-460 cites wiki/page-types.md:179 as requiring that "a reader must never be able to read a superseded statement as current guidance". Line 179 in fact concerns a rejected approach, and the supersession rule lives at wiki/style-guide.md:173-177. Should the tracker row be corrected so the author is not sent to the wrong constraint? Answered by the orchestrator: yes, and the Draft below is corrected.

##### Draft

This is a decision record and the decisions stay. Lines 161-163 already state
the rule correctly, so line 112 is brought into agreement with the page's own
text rather than rewritten from scratch.

Lines 182-186 need care. The principle, that a small machine is told so plainly
and in the reader's language rather than in specs, is the decision and it
survives. What fails is the worked example: an 8 GB machine is no longer the
machine where the brain and the voice cannot both stay resident. Keep the
principle, keep the dated framing intact, and note that the research stage
established there is no supported machine class to substitute in.

Correction to this draft, made by the orchestrator after the research stage
reported. An earlier version of this block cited `wiki/page-types.md:179` as
requiring that a reader never read a superseded statement as current guidance.
That line governs a **rejected alternative**, not a superseded statement, and
neither T3 defect is a rejected alternative. The constraint that actually
applies is `wiki/style-guide.md:175-177`, which offers two remedies and names
the in-place fix first. The research stage settled which one this task takes:
an in-place correction, no banner and no strikethrough, with the 2026-08-06
framing preserved at both sites, because no decision is being retired. Where
this page has genuinely retired something it already shows the house pattern at
`wiki/first-run.md:122-124`, one prose sentence inside the dated decision.

Notes from the author, on where the delivered change departed from the
direction above:

- On the choice the research stage declined to make, the author reported
  re-anchoring the passage on the refusal case at
  crates/hearth-probe/src/plan.rs:87-92 rather than dropping the worked example
  entirely. The reason given was that a decision record whose example is deleted
  leaves the principle asserted and never demonstrated, and that the refusal is
  the one small-machine case a verified claim still supports. The author
  reported naming no machine class and writing no VRAM band.
- On the line 112 annotation, the author reported paraphrasing rather than
  repeating the rule at lines 161-165, because that rule is 44 words and will
  not fit a fenced tree annotation.
- The author reported being unable to execute commands, so it could not run
  `scripts/lint_wiki.py` and checked the two findings against the script's rules
  as written instead. It described that as arithmetic over the rules rather than
  an observed run.

### T4: Correct the download figure and retire the Windows-guide announcement on Hearth on macOS

The page describes four things downloading together, which is the same defect
carried by the install pages, and it announces an unwritten Windows guide that
belongs in the register rather than on a platform overview.

##### Details

- Agent State: Complete
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: wiki/clients/macos.md, read in full this run. Lines 51-54 under `## What installing gives you` state that opening Hearth for the first time downloads the model weights, a voice, the inference engine, and a private Python runtime together. Line 122 under `## Status and limitations` states that the Windows install guide does not exist yet.
- Sources of truth:
  - source: crates/hearth-probe/src/plan.rs, covers what the plan's download figure counts. The downloads vector at 214-233 has exactly two entries, the chosen model build (214-222) and the voice weights (223-232), and the total at 234 sums those two. `disk_required` at 237 is that total plus a fifth, which is the number the free-disk sentence quotes. `ctx_for` at 279-283 rounds the context window down to a 1024 multiple
  - source: desktop-client/src-tauri/src/provision.rs, covers what is fetched outside the planner. The module contract at 1-14 names three parallel chains. Chain A at 248-279 unpacks a bundled backend.tar.gz resolved from the Tauri resource directory at 213-215, so the backend is shipped inside the client rather than downloaded. Chain B at 281-322 fetches the inference engine. Chain C at 324-369 fetches and unpacks the Python runtime. The voice weights are fetched by the forked chain at 371-380
  - source: crates/hearth-probe/src/lib.rs, covers `human()` at 24-35: bytes divided by 1,073,741,824 and formatted with a `GB` label. This is what settles that the page's size figures are the planner's byte counts as the installer prints them
  - source: desktop-client/src/lib/probe.ts, covers the client's own `human()` at 157-164, byte-identical to the Rust one, so the screen a reader sees uses the same divisor as the figures on this page
  - source: crates/hearth-probe/dictionary.yaml, covers every constant the figures rest on: the voice download at 109-120 (945,284,608 bytes), tier 0's Q4_K_M build at 161-165 (3,106,738,272 bytes), tier 2's build at 202-205 (6,716,356,800 bytes) with max_ctx 65536 at 206, tier 0's max_ctx 32768 at 140, and the runtime artifacts at 27-54 whose bytes the planner never counts. The voice_env pip installs at 59-67 carry no recorded size at all
  - source: crates/hearth-probe/src/machine.rs, covers `default_install_root` at 232-251. On macOS the branch at 245-247 joins HOME to `Hearth`, which is the `~/Hearth` default the page states
  - source: crates/hearth-probe/tests/plan_fixtures.rs, covers the pinned contract for the 8 GB M2 Air at 35-52: tier 0, the E2B repo, coexist true, metal, no CUDA arch, and no "one at a time" warning. No fixture pins an exact context window; the shared test at 54-75 asserts only n_ctx >= 16384
  - source: desktop-client/src-tauri/src/probe.rs, covers the voice row at 182-195, counted in the plan's total but skipped by the model-download loop because it has no direct URL, and installed by the voice engine step instead
  - contextual: wiki/page-types.md, covers the platform-overview shape at 227-252. Section 6 at 239 defines "What it cannot do yet" as honest limits on capability in the present tense. The rule at 246-248 forbids a dated status log. The rule at 243-245 puts installation on the install page, which is T6's ground and not T4's
  - contextual: wiki/whats-not-here.md, covers the register of unwritten pages. Entry 1 at 23-25 already announces the missing Windows install page
  - contextual: wiki/installing.md, covers the treatment T1 gave the same sentence, at 106-112 under `## The download`, and a fourth surviving Windows-guide announcement at 156-159
  - contextual: wiki/install-macos.md, covers the third instance of the four-things sentence at 84-86, and the troubleshooting section at 135-155 that wiki/clients/macos.md:127-128 refers to
  - contextual: tasks/docs/tracker.md, covers recorded task state and ownership: T4, T6 (owns removing `## Installing` at lines 85-102), T12 (owns rewriting the whats-not-here.md Windows entry), T16 (retires install-macos.md and lists the inbound references), and T1's completed record
- Docs:
  - wiki/clients/macos.md, `## What installing gives you` and `## Status and limitations`
- Artifacts:
  - Research: tasks/docs/artifacts/T4.research.json
  - Author: tasks/docs/artifacts/T4.author.json, wrote wiki/clients/macos.md
  - Review: tasks/docs/artifacts/T4.review.json, verdict FAIL, score 1 to 1
- On the score of 1 to 1, which is the lowest in this run and needs reading rather than reacting to. The reviewer reports clearing 2.5 points of detraction while five structural findings carry 9 points on their own, so both the before and after grades sit on the clamp floor. Its own summary: "The corrections T4 was dispatched to make were the right corrections on a page that needs a restructure." T4 was a corrections task and did not have the restructure in scope. The delta of 0 is a property of the floor, not a report that nothing improved.
- The reviewer confirms that the size figures were not touched and that the fourth re-filing of that false finding did not happen.
- Review checklist, and where each entry went:
  - F5 the qualifier's placement, F7 a comma splice, F8 "five local programs" against four bullets: all `done` by the reviewer. On F5 the reviewer reports that the author's verbatim copy from wiki/installing.md was right as prose and wrong as placement, because on that page the plan and its figure share a section while here they are forty lines and two sections apart, so it reworked the introduction rather than the sentences.
  - F4 the inline install procedure: `deferred` to T6. Confirmed that T6 exists and covers it.
  - F9 a bare unclickable filename handed to a reader whose install just failed: `deferred` to T16. Confirmed that T16 exists and covers the inbound references.
  - F1 no capability section, F2 no persona surface section, F3 catalog material on a describing page, F6 a dated status section where the type wants present-tense limits: all `deferred`, `needs: restructure`, and no open row owned any of them. Opened as T36.
  - F2 additionally carries a research need inside the deferred entry, which T36 records: whether the macOS client draws the persona face of wiki/features/persona-face.md or an orb, and what else the macOS window holds.
- The reviewer independently confirms the research stage's correction of this row's citation: wiki/page-types.md:246-248 forbids a dated status log and did not reach the bullet that was removed, while wiki/page-types.md:239 read with :264 did. It reports that 246-248 does reach a passage still on the page, which is its F6 and now T36's.
- On the judgement this row asked the reviewer to test, it upholds the author's call: line 42 reports a disk requirement rather than a download, the figure is the exact threshold the installer enforces, and qualifying it would need a magnitude no source supplies because the voice environment's pip installs record no size. It filed no finding for it.
- Objective gaps recorded by the reviewer, which derived eight objectives because neither the page nor the research artifact records any. Taught: whether your Mac can run Hearth, what an install puts on disk, how updates work. Not taught or mis-served, all four carried into T36:
  - "Describe what Hearth on macOS does day to day" is not taught, and the reviewer reports this as the objective the page's own type exists to serve.
  - "Describe how the persona appears and sounds on your Mac" is not taught, and needs research first.
  - "List what Hearth on macOS cannot do yet" is taught only partially, mixing two real limits with a dated provenance, a status sentence, and a capability presented as a caveat.
  - "Install Hearth on macOS" is taught, and the reviewer reports that as the defect rather than the success, since an `apply` objective implies a how-to page. That is T6's.
  - "Look up the install tree and the local ports" is served by nineteen lines of reference material the reviewer reports this page should not carry.
- Open questions:
  - By how much does the real macOS install exceed the free-disk figure at wiki/clients/macos.md:42, and does that figure therefore want a qualifier of its own? The author reported choosing to qualify only the four-item list, and reported that the measurable omission is 36,326,051 bytes while the voice environment's pip installs carry no recorded size anywhere, so no total can be stated from source.
  - Was the linter run against this edit? The author reported that it could not execute commands in its session and applied the conventions by hand, and asked that the reviewer not treat that as a linter run. See the verification note below.
  - Does the qualifying sentence go beside the four-item list at wiki/clients/macos.md:51-54 only, or does the free-disk figure at line 42 need it too? On wiki/installing.md the sentence and the plan number share one section, so one qualifier covers both. On this page they are seventy lines and two sections apart: line 42's 'roughly 4.5 GB on an 8 GB Mac and 8.6 GB on a 16 GB Mac' is disk_required from crates/hearth-probe/src/plan.rs:237, which is the same two-item total plus a fifth, so a reader budgeting disk from line 42 is short by the engine and the runtime as well. This stage does not choose; both placements are defensible and the author owns the sentence.
  - Is the exact 17,408-token figure at wiki/clients/macos.md:97 pinned anywhere? It is consistent with crates/hearth-probe/src/plan.rs:279-283 and tier 0's max_ctx at crates/hearth-probe/dictionary.yaml:140, but crates/hearth-probe/tests/plan_fixtures.rs:35-75 asserts only tier, repo, coexist, backend and n_ctx >= 16384, and this stage executes nothing. Nothing contradicts the figure and no part of T4 should change it; the question is whether the corpus wants a fixture that pins it.
  - Does T4 also touch the dated provenance at wiki/clients/macos.md:118-120, 'The install guide reflects one real, end-to-end install on an 8 GB M2 Air, verified 2026-08-07'? Tracker row T4 cites wiki/page-types.md:246-248 as the ground for removing line 122, but 246-248 forbids a dated status log and line 122 carries no date, while lines 118-120 do. The rule that actually reaches line 122 is wiki/page-types.md:239 and 264, which make this section honest limits on the client's capability rather than on the wiki's coverage. T4's statement names the Windows-guide announcement and nothing else, and tracker row T6 already reworks this page's install material, so this stage reports the mismatch and does not assign it.
  - Who owns the fourth Windows-guide announcement at wiki/installing.md:156-159? Tracker row T12 says T2 and T4 remove 'the other three announcements', but the grep returns four: wiki/clients/macos.md:122, wiki/clients/windows.md:232-233, and wiki/installing.md:156-159. The third sits on T1's page, which reads Complete, and it names the Windows guide as a page rather than as the section T12 will define. No open row owns it.
  - When line 122 goes, does anything on wiki/clients/macos.md point a reader at wiki/whats-not-here.md? The gap stays registered at wiki/whats-not-here.md:23-25 and T12 rewrites that entry, so nothing is lost from the register, but this page currently has no link to it and a Windows reader who arrives here learns nothing about where the gap is tracked. Adding one is new content rather than a correction, and T4 is a corrections task.
- Orchestrator rulings, so the author is not left choosing:
  - The dated provenance at lines 118-120 is not T4's. T4's statement names the Windows-guide announcement, and the research stage reports the dated-log rule as reaching 118-120 rather than 122. Leave 118-120 alone; whether it wants a row is T6's ground, which already reworks this page.
  - The fourth announcement at wiki/installing.md:156-159 is not T4's either. It is opened as T30 rather than reached across from this page, because T4's target is exactly one page.
  - The link to wiki/whats-not-here.md is new content and stays out. T4 is a corrections task.

##### Draft

Line 122 goes. `wiki/whats-not-here.md` is the one register for unwritten work,
and the section it sits in is for the client's limits rather than the wiki's.

Correction to this draft, made by the orchestrator after the research stage
reported. An earlier version cited `wiki/page-types.md:246-248` as the ground
for removing line 122. That rule forbids a **dated** status log and names "as of
2026-08-06" as the failing pattern, and line 122 carries no date. The rule that
actually reaches it is the section definition at `wiki/page-types.md:239`,
"What it cannot do yet. Honest limits, in the present tense", read with the type
table at `wiki/page-types.md:264`: a platform overview states the limits of one
client, and "the Windows install guide does not exist yet" is a limit of the
wiki. The conclusion is unchanged; the citation behind it was off by a section,
and an author who followed it would not have found what this row claimed.

Lines 51-54 wait on the same open question as T1 and should be resolved
consistently with it, since three pages now state the same thing.

Note from the T1 run: `tasks/docs/artifacts/T1.research.json` reports that this
page's size figures at line 42 and lines 97-99 verify correct against source and
must not be changed. T1 was dispatched on a premise that those figures were
stale, and they are not: they are the planner's byte counts under the product's
own renderer. The only defect the T1 survey found here is the four-things
sentence at lines 51-54, plus the `~/Hearth` macOS default at the same lines,
which it reports as correct. The T4 research stage confirmed the figures a third
time and no digit was changed.

Notes from the author, on where the delivered change departed from the
direction above:

- On the choice the research stage declined to make, the author reported
  qualifying only the four-item list and leaving the free-disk figure at line 42
  alone. The reasons given were that line 42 reports a disk requirement rather
  than a download and is accurate as such, and that qualifying it would need a
  magnitude no source supplies, since the voice environment's pip installs carry
  no recorded size.
- The author reported copying the two qualifying sentences from
  wiki/installing.md unchanged rather than paraphrasing them, so that the two
  pages state this identically.
- The author reported splitting the paragraph at "together." and moving the
  folder clause to the end of the new paragraph, because one paragraph would
  have run past the style guide's length while the colon still had to meet the
  fenced tree. It reported adding and dropping no fact.
- The author reported being unable to execute commands, so it could not run
  `scripts/lint_wiki.py` and applied the conventions by hand. It asked
  explicitly that the reviewer not treat that as a linter run.

### T5: Correct the settings-screen claim and state the persona-creation route on Personas

The page closes by sending a reader away from a screen that ships, and it does
not tell them how to make a second persona, which is the question the page's
own subject raises.

##### Details

- Agent State: Complete
- Type: Fix
- Scope: M
- Confidence: High
- Sizing evidence: corrected from S to M by tasks/docs/artifacts/T5.research.json, which opened the page and the source tree and returned `recommended_size: M`. The reason it gives: the page alone is an S, but the staleness sweep found three further contradicted claims on it (lines 83-86, 95-96, 96-100) and three more pages the correction cannot leave standing, which is the M evidence bar of named candidate pages. Route ran at S, and S and M take the same route, so no stage rewound. The orchestrator's own read stands as the original sizing: wiki/features/personas.md, read in full this run, lines 111-113 under `## Switching and multiple personas` state that day-to-day details of managing several personas, such as a settings screen for editing or removing one, are not yet covered by what ships today, and `## Making your first one` at lines 46-71 describes only the first-run interview and opens "The first time you open Hearth".
- Split: this task kept wiki/features/personas.md as page 1. The other three pages in `affected_docs[]` became T26, T27 and T28.
- Sources of truth:
  - source: backend/harness/valar/data/persona_template.json, covers the tool domains a persona made by create_persona is born with; line 33 lists `personas` among them and the comment at line 32 records why
  - source: backend/harness/valar/tools/tools.yaml, covers create_persona's domain, its parameters and its required fields (lines 1083-1127), and the full domain vocabulary (13 domains across 48 tool entries, none named `projects`)
  - source: backend/harness/valar/tools/__init__.py, covers how a persona's tool_grants select the tools it is offered (lines 132-184) and the HEARTH_TOOLS_ENABLED master switch (lines 42-48)
  - source: backend/harness/valar/tools/handlers/creation.py, covers what create_persona writes, the name and colour rules, the voice design attempt, the memory seed, and the note that a new persona needs no cache invalidation
  - source: backend/harness/valar/gateway/first_run.py, covers when first run is active and when it expires permanently (lines 253-287), the interview and brain-beat grants (lines 37, 114-118), the scripted opening (lines 47-53) and the scripted farewell (lines 80-87)
  - source: backend/harness/valar/gateway/voice_loop.py, covers which grants apply on a turn (lines 1516-1533), the first-run handover that switches to the new persona (lines 2004-2077), and the fact that persona_created is read nowhere else
  - source: backend/harness/valar/gateway/personas_api.py, covers the persona page's server surface: GET /personas/surface, POST /personas/apply (edits, domain re-grants and removal), POST /personas/speak, and the restart that makes an edit real
  - source: backend/harness/valar/persona/engine.py, covers persona discovery and the picker's exclusions (lines 60-85), the load cache (lines 92-130), and switching (lines 150-162)
  - source: desktop-client/src/components/personas/PersonasView.tsx, covers the desktop Personas page: its six sections, the ungated domain editor, the ungated Save and restart, and the developer-mode gate on Remove and Discard
  - source: desktop-client/src/components/settings/SettingsView.tsx, covers the Developer mode switch at lines 651-656 and the Personas section at lines 408-420 that pins which persona a device asks for on connect
  - source: desktop-client/src/components/stage/PersonaStage.tsx, covers how the Personas page is reached (the ungated Personas icon at lines 69-71) and that the whole stage is hidden below the lg breakpoint (line 37)
  - source: desktop-client/src/hooks/useHearthWebSocket.ts, covers when the desktop client refreshes the persona list: on client_info_ack (line 119) and after persona_switched (line 179), and nowhere else
  - source: backend/personas/Sulivan/sulivan.json, covers the shipped persona's grants, including `personas` at line 72, and the absence of the `briefs` domain the tool catalog still reports
  - source: apple-client/Hearth/Core/Sources/HearthCore/Models/PersonaSurface.swift, covers which persona fields the iPhone can edit, and why the rest are locked (lines 5-18)
  - source: android-client/app/src/main/java/com/hearth/app/ui/surfaces/PersonaScreen.kt, covers the one field Android writes back, the system prompt (lines 305-306)
  - contextual: wiki/page-types.md, covers the concept page shape and its rule against procedures (lines 129-154)
  - contextual: tasks/docs/tracker.md, covers the recorded T5 state, its sizing evidence, its one carried open question, and the note that reverses the older Sulivan-only account
- Docs:
  - wiki/features/personas.md, `## Switching and multiple personas`, `## Making your first one`, `## Where a persona lives`, and `## Voices, briefly`
- Artifacts:
  - Research: tasks/docs/artifacts/T5.research.json
  - Author: tasks/docs/artifacts/T5.author.json, wrote wiki/features/personas.md
  - Review: tasks/docs/artifacts/T5.review.json, verdict NEEDS_WORK, score 3 to 7
- **The dead end this whole corpus pass was named after is closed.** The reviewer's objective validation records "describe how to make a persona after first run has ended" as taught, and names what closes it: the expiry of first run, the ask, the one-tool grant, the absence of a restart, the absence of a handover, and the pre-2026-09-03 caveat with its two working routes. It reports all five of the author's corrections as holding against source.
- Review checklist, and where each entry went:
  - F2 saying the house does not switch to the new persona, F6 reframing the truncated first-run quote, F3 glossing "the Personas page" at first mention, F5 adding the pending figure, F7 naming the iOS client consistently: all `done` by the reviewer.
  - F1 the missing Personas-page how-to: `deferred` to T32, `needs: restructure`. Confirmed that T32 exists and covers it. The reviewer adds that three places on this page want the link once T32 lands: the Note in `## Making another one`, the end of `## Voices, briefly`, and `## Changing a persona later`. Recorded on T32.
  - F4 whether any client can change the default persona: `blocked`, `needs: research`. Opened as T37.
- On the colour/color conflict this row asked the reviewer to adjudicate, it verified the author's reading against the script and reports the conclusion standing with one detail corrected. It reports scripts/lint_wiki.py:339-340 running the British pattern over every body line outside a fenced block at severity error, with no quote exemption at that call site for any page, so the exemption is not reserved for the style guide as the author described: `british-spelling` has no quote exemption anywhere. It reports two mechanical escapes it recommends refusing, inline code voice and a fenced block, on the ground that both misrepresent spoken product dialogue. Its recommendation is to change the product string at backend/harness/valar/gateway/first_run.py:47-53, and it reports the parameter name `colour` in tools.yaml and creation.py as identifiers that should not change. Recorded on T31.
  - The reviewer flags one of its own edits for the orchestrator: F2 added "The house does not switch to them", which it reports as the intended behaviour rather than the T31 defect, and notes the page still says nothing about the tool's return text. Reviewed and kept: it states what the product does, which is what the ruling asked for.
- Objective gaps recorded by the reviewer, which derived six objectives because neither the page nor the research artifact records any. Taught: what a persona is made of, how the first one is made, how to make one after first run, where a persona lives on disk, how a persona gets a voice.
  - "Explain how a persona gets a voice and what happens when design fails" is taught here, but the reviewer records that wiki/features/voice.md:32 and 38-43 still carry two claims this page has now corrected, so the two concept pages disagree until T27 runs. That is a real cost of splitting the work and it is why T27 should not sit in the backlog long.
  - "Describe what you can change about a persona later, and what you cannot" is not taught in full. Two holes, both already tasks: the removal route is written nowhere in the corpus (T32), and the default-persona precondition names an action no client appears to expose (T37).
  - "Change or remove a persona on the Personas page" is not taught, and the reviewer records that as correct for a concept page under wiki/page-types.md:153-154. It also records that until T32 lands, no page in the corpus teaches it at all.
  - The reverse check found no content serving no objective.
- The reviewer raises one corpus-level contradiction and declines to grade the page on it: wiki/page-types.md:59-62 requires action-title headings for every type but reference, while wiki/page-types.md:134 holds this page up as the model concept page, and all four concept pages use gerund headings. It reports charging no noun-heading detraction because grading this page against a rule its own guide exemplifies it as satisfying would be grading the guide. Opened as T38.
- Open questions:
  - Should the page tell a reader that a persona made outside first run does not reach the desktop switch chips until the client reconnects? The author reported leaving it out because the research stage left open whether the behaviour is intended, and reported that writing it would document a possible defect as behaviour.
  - Where should the removal control's gate be written down for a reader who cannot find it? The author reported that the orchestrator's ruling keeps the switch path off this page as a procedure, and reported that there is no how-to page for the Personas page to carry it, so the route is currently written nowhere. This depends on T32.
  - Was the linter run against this edit? The author reported that it could not execute commands in its session and wrote to the script's thresholds by hand after reading them from source. See the verification note below.
  - Does T5 own the corrections on wiki/backend/tool-catalog.md, wiki/features/voice.md and wiki/first-run.md, or do those need their own tracker rows? The tracker states that task targets do not overlap, and T3 already owns wiki/first-run.md for a different defect in a different section. Each of the three contradicts what T5 will state on Personas, so none can simply be left. Answered by the orchestrator: they are split out as T26, T27 and T28.
  - Should Personas state that a persona made before this change cannot make another, or is that a release-note concern rather than a concept-page concern? The fact is verified either way (persona_template.json is expanded once at creation and nothing migrates an existing manifest), and the reader it affects is anyone whose house predates 2026-09-03.
  - Should Personas name the two developer-mode switches that gate Remove, or say only that removal is behind developer mode? Naming both is accurate (Settings > Developer > Developer mode, then the switch that appears on the Personas page itself) and may be more procedure than a concept page should carry under wiki/page-types.md lines 153-154.
  - create_persona tells the persona 'Stop speaking as yourself after this turn: the house will hand over, and {name} speaks next' (creation.py lines 439-446), but outside first run nothing switches, because persona_created is read only by the first-run turn (voice_loop.py line 2014). A reader may hear their persona announce a handover that does not happen. Is the fix the tool's return text or the missing handover, and should Personas describe today's behaviour in the meantime?
  - A persona made outside first run does not reach the switch chips until the desktop client reconnects, because list_personas is sent only on client_info_ack and after persona_switched (useHearthWebSocket.ts lines 119 and 179). Is that intended, and does the page need to tell a reader to expect it?
  - tools.yaml line 1124 offers the swatch name Heather, which creation.py lines 52-60 no longer accept; a reader who chooses it silently gets Ember. Product defect or stale tool description? Carried to T31.
  - desktop-client/src/components/personas/PersonasView.tsx line 357 tells a reader that a persona with no clip borrows the house voice, while backend/harness/valar/voice/tts_service.py lines 145-157 clear the voice and let the engine refuse. Which is the intended behaviour, and which of the two should change? Carried to T31.
  - wiki/backend/tool-catalog.md is stale well beyond the create_persona row: the entry count at line 51, the domain column across lines 71-78, the audit at lines 91-102 and the briefs finding at lines 104-106 all disagree with tools.yaml and sulivan.json as they stand. Its last_reviewed is 2026-09-03. Does that page need a rebuild rather than a correction? Carried to T26.
  - The research stage reported that desktop-client/src/components/personas/PersonasView.tsx:28 names wiki/clients/persona-page.md as its design of record, and that no such file exists. Opened as T32.
- Orchestrator rulings, so the author is not left choosing:
  - The pre-change caveat stays in. A reader whose house predates 2026-09-03 is the reader most likely to arrive at this page asking exactly this question, and the research stage verified both routes that work for them. A concept page can state a limit without becoming a release note.
  - Say that removal is behind developer mode; do not name the two switches. `wiki/page-types.md:153-154` sends procedures to a how-to page, and naming a switch path is a procedure. The reader needs to know the control exists and is gated, not how to reach it.
  - Do not describe the handover text defect on the page. It is a product defect, recorded as T31, and a concept page that documents a bug as behaviour makes the bug permanent.

##### Draft

Two changes. The claim at lines 111-113 is replaced by what the product does,
which the research stage establishes rather than this tracker.

Second, the page should answer how a reader makes another persona after the
first. This is now a plain answer rather than a workaround:
`backend/harness/valar/data/persona_template.json:33` grants the `personas`
domain to a made persona, and the comment at line 32 records that its earlier
absence was unintended. Any persona can make another one by being asked. Do not
write the older account, in which the only route was switching back to Sulivan.

Notes from the author, on where the delivered change departed from the
direction above:

- On the passing fix to the quoted first-run opening line, the author reported
  truncating the quote before the disputed clause rather than spelling it
  "colour" as directed. The reason given was that scripts/lint_wiki.py raises
  `british-spelling` at severity **error** on that word in prose, with the only
  quote exemption reserved for the style guide itself, so making the quote match
  the shipped string would have taken the corpus off zero lint errors. This is
  a real conflict between the direction and the linter, and the author's reading
  of it should be checked rather than assumed.
- The author reported putting the Personas page material in its own H2,
  `## Changing a persona later`, rather than growing the switching section,
  citing the style guide's one-subject test and its 200-word section limit.
- The author reported writing both new headings as gerund phrases rather than
  imperative action titles, to stay parallel with the existing
  `## Making your first one` on a page it was not sent to restructure.
- The author reported being unable to execute commands, so it could not run
  `scripts/lint_wiki.py` and wrote to the script's thresholds by hand after
  reading them from source.

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

### T17: Correct the install root and the coexistence claim on Build pipeline

The page carries two of the defects Phase A is correcting elsewhere, on a page
no task owned. Found by the T1 research survey rather than by the `graph` pass.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: Medium
- Sizing evidence: wiki/backend/build-pipeline.md, frontmatter lines 1-12 opened this run, where line 4 reads `type: how-to`. The two defect locations are reported by tasks/docs/artifacts/T1.research.json and were not opened by the orchestrator, so the size is not evidence-backed and is sized up rather than down.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts: (none yet)
- Open questions:
  - Does line 106 state the `D:\Hearth` default, and does line 158 state that on 8 GB the voice and the brain cannot coexist? The T1 research artifact reports both, each contradicted by the same source that settles wiki/installing.md:76-78 and 85-86. Neither line was opened by the orchestrator.

##### Draft

Direction is the same as T1's on both claims. The research stage confirms the
locations before an author is dispatched.

### T18: Correct the Windows install root on Native runtime

A layout block naming a Windows install root the planner does not produce, on a
page no task owned.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: Medium
- Sizing evidence: wiki/backend/native-runtime.md, frontmatter lines 1-12 opened this run, where line 4 reads `type: decision-record`. The defect location is reported by tasks/docs/artifacts/T1.research.json and was not opened by the orchestrator.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts: (none yet)
- Open questions:
  - Does line 79 read `Windows: <root> = D:\Hearth (chosen at setup)`? The T1 research artifact reports it and reports the macOS half, `~/Hearth`, as correct. Neither line was opened by the orchestrator.
  - This page is a decision record. Does the line sit inside a dated decision, in which case wiki/page-types.md governs how a superseded statement is corrected rather than overwritten?

##### Draft

Direction on the install root is the same as T1's. The decision-record shape
constrains how the correction is made, which is what the research stage
establishes first.

### T19: Correct the Hearth home folder path on The second brain

The page names the Hearth home folder as a hidden dotdir that the installed
product does not create on macOS or Windows.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: Medium
- Sizing evidence: wiki/features/second-brain.md, frontmatter lines 1-12 opened this run, where line 4 reads `type: concept`. The defect location is reported by tasks/docs/artifacts/T1.research.json and was not opened by the orchestrator.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts: (none yet)
- Open questions:
  - Does line 64 name the Hearth home folder as `~/.hearth`? The T1 research artifact reports it, and reports that desktop-client/src-tauri/src/config_gen.rs:64 renders HEARTH_HOME as `<root>/home`, that crates/hearth-probe/src/machine.rs:245-248 keeps the `.hearth` dotdir for Linux only, and that backend/harness/valar/tools/handlers/second_brain.py:59-62 records `~/.hearth` as the systemd or WSL testbed layout. The line was not opened by the orchestrator.

### T20: Capture the plan screen figure for Installing Hearth

The page describes the one screen a reader has to recognise and approve before
anything downloads, and reproduces its contents as a table. The reviewer placed
a pending figure there during the T1 run.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: XS
- Confidence: High
- Sizing evidence: `python scripts/lint_wiki.py --figures`, run after the T1 review, reports this figure pending at wiki/installing.md:88. The linter is the standing queue for figure work and its output is quoted below verbatim; the orchestrator did not open the line itself.
- Sources of truth: (none, this is capture work rather than a writing task)
- Docs:
  - wiki/installing.md, line 88, inside `## The scan and the plan`
- Artifacts: (none, the route is neither Author nor Review)
- Open questions:
  - None.

##### Draft

This is work for a person with a screenshot tool, not for a writer agent. The
linter carries the order:

- path: `images/pending/installing-plan-screen.png`
- alt: The plan Hearth shows before it downloads anything
- spec: CAPTURE: setup on an 8 GB Apple Silicon Mac, the plan card at the point
  of approval, showing the model, context window, memory and download rows and
  the approve button, 1280x800

### T21: Capture the first-run voice check figure for Installing Hearth

The page describes the final screen of setup and its two buttons in prose. The
reviewer placed a pending figure there during the T1 run.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: XS
- Confidence: High
- Sizing evidence: `python scripts/lint_wiki.py --figures`, run after the T1 review, reports this figure pending at wiki/installing.md:137. The orchestrator did not open the line itself.
- Sources of truth: (none, this is capture work rather than a writing task)
- Docs:
  - wiki/installing.md, line 137, inside `## Proving it works`
- Artifacts: (none, the route is neither Author nor Review)
- Open questions:
  - None.

##### Draft

Work for a person with a screenshot tool. The linter carries the order:

- path: `images/pending/installing-voice-check.png`
- alt: The final screen of setup, after Sulivan has spoken
- spec: CAPTURE: the last setup screen just after the spoken line, both answer
  buttons visible and neither pressed, 1280x800

### T22: State the Windows floor in Before you start on Installing Hearth

The macOS subsection tells a reader whether their machine qualifies. The Windows
subsection does not, and the page it forwards them to has no requirements
section either, so half the audience cannot answer the only question that
section exists to answer.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: S
- Confidence: High
- Sizing evidence: wiki/installing.md, read in full by the orchestrator this run before the T1 edits. `### macOS` at lines 35-46 states a chip requirement, a memory floor with the refusal below it, free disk, and the verified OS version. `### Windows` at lines 48-56 states none of the four: it describes the scan and forwards to wiki/clients/windows.md for what the app looks like once running. Raised independently as F3 in wiki/installing.review.json, at a detraction of 2, and left unfixed there because supplying the numbers is research and authoring rather than review.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts: (none yet)
- Open questions:
  - What is the Windows floor, in the same four terms the macOS subsection uses? The reviewer named crates/hearth-probe/dictionary.yaml and the refusal branch at crates/hearth-probe/src/plan.rs:151-157 as where the numbers live, and warned against publishing the hand-derived 4.5 to 5.4 GB VRAM band from tasks/docs/artifacts/T1.research.json without an executed planner run behind it.
  - Is this separable from T10, which is blocked on someone performing a Windows install? The requirements can be established from source, whereas the procedure cannot, so this task is not blocked by the same thing. Confirm that reading before dispatching.

##### Draft

State the Windows floor in the same four terms `### macOS` uses. This is not the
Windows procedure, which is T10 and is blocked; it is the prerequisites, which
source can settle.

### T23: Name which downloaded artifacts carry no published sha256

T1 corrected the page to claim hash verification only for files that carry a
hash, which is true. It now tells a reader that some files are unverified
without telling them which.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: S
- Confidence: Medium
- Sizing evidence: wiki/installing.md line 100, read by the orchestrator this run before the T1 edits, stated "Every file is verified against a published sha256 hash once it lands". tasks/docs/artifacts/T1.research.json records that claim as contradicted and names the exceptions: both OmniVoice GGUFs at crates/hearth-probe/dictionary.yaml:117 and 120 with a FOLLOW-UP note at 126-128, and the llama.cpp archives at dictionary.yaml:44-54. Raised by the author as unresolved and by the reviewer as a further improvement needing its own row.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts: (none yet)
- Open questions:
  - Which page should carry this? It is new content rather than a correction, and wiki/installing.md is a how-to whose shape is already contested under T9. A reference or concept page may be the better home.
  - Is the missing hash on the OmniVoice GGUFs a permanent property or an open FOLLOW-UP in the dictionary? If it is being fixed, documenting the gap dates the page immediately.

##### Draft

Establish the home before writing. The facts are already in the T1 research
artifact.

### T24: Record the corpus unit convention as a decision

T1 was dispatched on the premise that four size figures were stale, and they
were not: they are the product's own rendering, bytes divided by 2^30 under a
GB label. Nothing in the corpus records that, so the next reader to check a
figure against a decimal calculator files the same defect again.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: S
- Confidence: Medium
- Sizing evidence: tasks/docs/artifacts/T1.research.json records the convention at crates/hearth-probe/src/lib.rs:24-35 with desktop-client/src/lib/probe.ts:158-164 byte-identical, records that nothing in wiki/style-guide.md or wiki/page-types.md states a rule, and lists the absence in `gaps[]`. Raised independently by the reviewer as a further improvement. The orchestrator opened neither source file.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts: (none yet)
- Open questions:
  - Where does a convention like this belong: wiki/style-guide.md, wiki/page-types.md, or a decision record of its own?
  - Which pages carry affected figures? The T1 research artifact names wiki/installing.md, wiki/clients/macos.md and wiki/install-macos.md, the last of which is scheduled for retirement under T16.

##### Draft

This run is the evidence that the gap costs real work: a correct page was
dispatched for correction on it. Record the convention where a future task will
look before refiling the same defect.

### T25: The planner still warns a Windows reader that Hearth will install WSL

This is a product defect rather than a documentation one, and no writer agent is
dispatched for it. The planner tells a Windows reader during setup that Hearth
will offer to install the Windows Subsystem for Linux and that this needs a
restart. The native-runtime decision of 2026-08-06 replaced WSL with native
Windows processes, and `wiki/clients/windows.md:230-232` states that decision is
final, so the setup screen contradicts the product on a page the corpus has
already been corrected to match.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: crates/hearth-probe/src/plan.rs, lines 245-251 opened by the
  orchestrator this run. The branch reads `if m.os == "windows" && m.wsl_present
  == Some(false)` and pushes the warning "The Windows Subsystem for Linux is not
  installed yet. Hearth will offer to install it, which needs a restart." into
  the plan's `warnings`. The size covers the removal and whatever else reads
  `wsl_present`, which the orchestrator did not trace.
- Sources of truth: (none, this is a code change rather than a writing task)
- Docs: (none, no page carries this sentence; it is emitted by the planner)
- Artifacts: (none, the route is neither Author nor Review)
- Open questions:
  - Is the fix removing the branch, or does `wsl_present` still serve some other
    purpose the orchestrator did not trace? Only lines 238-255 of plan.rs were
    opened this run.
  - Does any client surface render this warning string, and does any wiki page
    reproduce it? Neither was checked.

##### Draft

Not documentation work. It belongs to whoever owns `crates/hearth-probe`, and it
is recorded here only because a documentation run found it. Dispatch nothing.

Added after the T3 research stage reported: the same crate carries stale WSL
residue in its doc comments. The research stage reports
`crates/hearth-probe/src/machine.rs:218-223` and `:228-231` as still describing
the WSL distro and its unregister step as part of the install root, and reports
both as contradicted by `wiki/backend/native-runtime.md` and
`wiki/first-run.md:122-124`. The orchestrator did not open those lines. They are
folded in here rather than given their own row, because they are the same defect
class in the same crate and one person fixes all three at once.

### T26: Correct the create_persona domain and the unreachable-tools audit on The tool catalog

Split from T5. The page states that `create_persona` sits in a `projects` domain
granted to nobody, and builds its most prominent finding on that: that the tools
behind it cannot be reached in ordinary conversation. T5 is about to state on
Personas that a reader can ask their persona to make another one, which this
page directly denies.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: M
- Confidence: High
- Split from: T5
- Sizing evidence: tasks/docs/artifacts/T5.research.json, which opened both the page and the source tree. It records five contradicted claims on this page rather than one: the domain at line 75, the audit at lines 91-102, Sulivan's grants at lines 92-93 and 104-106, and the catalog size at line 51. The orchestrator opened none of them.
- Sources of truth: shared with T5. See tasks/docs/artifacts/T5.research.json, in particular backend/harness/valar/tools/tools.yaml and backend/personas/Sulivan/sulivan.json, which this page names in its own `sources` field and contradicts in four places.
- Docs:
  - wiki/backend/tool-catalog.md, `## The inventory` and `## What the audit found`
- Artifacts:
  - Research: tasks/docs/artifacts/T5.research.json
- Open questions:
  - Does this page need a rebuild rather than a correction? The research stage reports the entry count at line 51, the domain column across lines 71-78, the audit at lines 91-102 and the briefs finding at lines 104-106 as all disagreeing with source, and reports its `last_reviewed` as 2026-09-03. A page whose every load-bearing figure is wrong may not be repairable by correction.
  - Is `reference` the right Shape? It is set from the page's own declared type, which the orchestrator did not open. Confirm before dispatching.

##### Draft

Do not dispatch an author before settling the rebuild question. The research
stage's report is that the staleness is structural rather than local, and a
corrections pass over a page that wants rebuilding is wasted twice.

### T27: Correct the permanent-reference and pending-voice claims on Voice

Split from T5. The page carries two claims that also appear on Personas and that
T5 is correcting there. Leaving them makes the two concept pages disagree with
each other about the same mechanism.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: High
- Split from: T5
- Sizing evidence: tasks/docs/artifacts/T5.research.json, which opened the page. It records line 32 stating that the designed clip becomes the persona's permanent reference, and lines 38-43 stating that a pending voice design is completed the next time the voice engine can run it. The orchestrator opened neither line.
- Sources of truth: shared with T5. See tasks/docs/artifacts/T5.research.json, in particular backend/harness/valar/gateway/personas_api.py:262-268 for the Replace control that overwrites the reference, and the report that a grep for `pending_design` returns one hit, the write at backend/harness/valar/tools/handlers/creation.py:398, with no reader anywhere.
- Docs:
  - wiki/features/voice.md, `## How a persona gets a voice`
- Artifacts:
  - Research: tasks/docs/artifacts/T5.research.json
- Open questions:
  - Is the pending-voice behaviour a documentation defect or a product gap? The research stage reports that nothing reads the flag the product writes, which means either the page describes an unbuilt feature or the feature was dropped. Which it is decides whether the page states today's behaviour or the corpus opens a product row.

##### Draft

Correct both claims to what the research stage established, and keep the
treatment consistent with whatever T5 lands on wiki/features/personas.md, since
the two pages state the same two mechanisms.

### T28: Retire the solved cache-invalidation problem in the First run record

Split from T5. The record lists as an open problem something the source tree
records as solved, and the solution is the fact T5 is about to publish: that
making a persona takes effect without restarting the house.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: High
- Split from: T5
- Sizing evidence: tasks/docs/artifacts/T5.research.json, which opened the page. It records lines 287-292, under `### create_persona`, stating that adding a persona needs cache invalidation rather than a process exit, and records backend/harness/valar/tools/handlers/creation.py:9-11 as recording the opposite. The orchestrator opened neither.
- Sources of truth: shared with T5. See tasks/docs/artifacts/T5.research.json, in particular backend/harness/valar/tools/handlers/creation.py:9-11 and backend/harness/valar/persona/engine.py:69-85 and 92-94.
- Docs:
  - wiki/first-run.md, `### create_persona`
- Artifacts:
  - Research: tasks/docs/artifacts/T5.research.json
- Open questions:
  - This is a decision record, and the passage is written as an unsolved problem inside it. Does retiring a solved problem take the in-place fix or the SUPERSEDED banner at wiki/style-guide.md:175-177? T3 settled the same question for two other passages on this page and chose the in-place fix; confirm that reading holds for a passage that is being retired rather than corrected.

##### Draft

**Phase G, and it cannot share a phase with T3.** Both target
`wiki/first-run.md`, and a phase is a group of tasks whose targets do not
overlap. T28 runs after T3 reads `Complete`, and the author re-reads the page
rather than working from the line numbers above, which T3's edit may move.

### T29: Correct the sha256 claim on Hearth on Windows

The page states that every download is verified against a published sha256. It
is the same sentence T1 corrected on `wiki/installing.md`, on a page whose own
task named two other defects and not this one.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: tasks/docs/artifacts/T2.research.json, which opened the page. It records lines 204-207 under `## The hardware probe picks your model` reading "Every download is verified against a published sha256 after it lands", and records the fenced tree at line 156 annotating the models folder as "model weights, sha256-verified". The orchestrator opened line 151 and lines 196-202 of this page but not 204-207.
- Sources of truth: shared with T2. See tasks/docs/artifacts/T2.research.json, in particular crates/hearth-probe/dictionary.yaml:117 and :120 (`sha256: null` for both OmniVoice GGUFs, with a FOLLOW-UP at 126-128), dictionary.yaml:25-26 (the llama.cpp zips carry no published sha256), and crates/hearth-probe/src/plan.rs:34-36 and 223-232.
- Docs:
  - wiki/clients/windows.md, `## The hardware probe picks your model`, lines 204-207, and the tree annotation at line 156
- Artifacts:
  - Research: tasks/docs/artifacts/T2.research.json
- Open questions:
  - Does the tree annotation at line 156, "model weights, sha256-verified", need the same treatment? It is narrower than the sentence at 204-207 and may be correct as written, since the model weights do carry hashes. The research stage recorded it beside the defect without ruling on it. The T2 reviewer independently raised the same point and put it more strongly: it reports the claim as repeated inside the fenced tree, and warns that a fix aimed at the prose alone will miss it. Whoever runs this task opens both locations.
  - Is this T29's or T23's? T23 is scoped to wiki/installing.md and asks which artifacts carry no published hash. The two tasks answer the same question on two pages, and running them in either order risks two different answers.

##### Draft

**Phase F, after T2 completes.** Both target `wiki/clients/windows.md`, so they
cannot share a phase. Match whatever wording T1 landed at
`wiki/installing.md:100`, so the corpus states hash coverage the same way twice.

### T30: Retire the fourth Windows-guide announcement on Installing Hearth

Three tasks were opened to remove the announcement of an unwritten Windows
install guide, on the understanding that there were three instances plus the
register. There are four.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: XS
- Confidence: High
- Sizing evidence: tasks/docs/artifacts/T4.research.json, which reports a corpus grep outside wiki/raw/ returning four instances: wiki/clients/macos.md:122 (T4's), wiki/clients/windows.md:232-233 (T2's), wiki/whats-not-here.md:23 (the register, T12's), and wiki/installing.md:156-159, which it quotes as "A dedicated Windows install guide does not exist yet. [Hearth on Windows](clients/windows.md) covers what the Windows app does ... and is the best reference until that guide is written." tasks/docs/artifacts/T2.research.json independently reports the same four. The orchestrator opened none of them, so this size is not backed by its own read and is recorded here at the researchers' evidence rather than the orchestrator's.
- Sources of truth: (Research fills, if the route runs one)
- Docs: (Research fills, if the route runs one)
- Artifacts: (none yet)
- Open questions:
  - Is this XS, or does it wait on T12? T12 rewrites the register entry so the missing work is a section of wiki/installing.md rather than a separate page. An announcement on the very page that will contain the section is a different sentence from one on a platform overview, and it may want rewording rather than deleting.
  - Does it wait on T9 as well? T9 restructures this page, and tasks/docs/tracker.md records T1 as Complete, so this page currently has no open owner.

##### Draft

Do not delete blind. This instance sits on the page that will hold the Windows
procedure, so the honest sentence there may be one that tells a Windows reader
the steps are not written yet rather than one that points them at another page.
Settle that against T12's rewrite before dispatching.

### T31: Three product defects on the persona creation path

Product defects rather than documentation ones, found by the T5 research stage
and recorded so they do not disappear into an artifact. No writer agent is
dispatched for any of them.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: tasks/docs/artifacts/T5.research.json, which opened every location below. The orchestrator opened none of them, so each is recorded as what the research stage reports rather than as a fact this tracker establishes.
- Sources of truth: (none, this is a code change rather than a writing task)
- Docs: (none, no page carries these; they are product behaviour)
- Artifacts: (none, the route is neither Author nor Review)
- Open questions:
  - Does create_persona's return text promise a handover that does not happen? The research stage reports backend/harness/valar/tools/handlers/creation.py:439-446 returning text ending "Stop speaking as yourself after this turn: the house will hand over, and {name} speaks next" on every call, and reports that `persona_created` is read only at backend/harness/valar/gateway/voice_loop.py:2014, inside the first-run turn. If that holds, a reader outside first run hears their persona announce a handover that never comes. Is the fix the text or the missing handover?
  - Does the colour swatch list offer a name the handler rejects? The research stage reports backend/harness/valar/tools/tools.yaml:1124 offering "Ember, Tide, Fern, Heather, Clay" while backend/harness/valar/tools/handlers/creation.py:52-60 accepts ember, tide, fern, plum and clay, and reports a comment at creation.py:56-57 recording that heather was renamed to plum. If that holds, a reader who asks for Heather silently gets Ember.
  - Does the desktop client tell a reader something the server contradicts? The research stage reports desktop-client/src/components/personas/PersonasView.tsx:357 rendering "No clip yet, so they borrow the house voice", and reports backend/harness/valar/voice/tts_service.py:145-157 clearing the voice and letting the engine refuse instead. Which of the two is the intended behaviour?
  - Should the first-run opening line spell "colour" as "color"? Added after the T5 review. The reviewer reports backend/harness/valar/gateway/first_run.py:47-53 shipping "colour" in user-facing copy spoken on every install, and reports scripts/lint_wiki.py raising `british-spelling` at severity error on that word in any body line outside a fenced block, with no quote exemption at that call site for any page. The consequence it reports is that no wiki page can quote the shipped sentence whole without failing the build, so the corpus currently truncates the quote instead. Its recommendation is to change the one word in the product string rather than to teach the linter a quote exemption, because such an exemption would hole every prose rule and the product would still spell against its own documented standard. It reports the `colour` parameter name in tools.yaml and creation.py as identifiers that appear in code voice and should not change.

##### Draft

Not documentation work. Recorded here because a documentation run found it, and
because T5 had to decide what the page says while each of these stands. T5's
ruling was that a concept page does not document a bug as behaviour. Dispatch
nothing.

### T32: No page documents the Personas page the clients point at

The desktop client names a wiki page as its design of record and that page does
not exist. The Personas page is the surface T5 is about to tell readers exists,
and nothing in the corpus describes it.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: M
- Confidence: Medium
- Sizing evidence: tasks/docs/artifacts/T5.research.json records `desktop-client/src/components/personas/PersonasView.tsx:28` naming `wiki/clients/persona-page.md` as its design of record, reports that the file does not exist, and reports that `wiki/features/persona-face.md:117` refers to "Personas > Animations" as though the page were described somewhere. The orchestrator opened none of these. Sized M as a net-new page and left at Medium confidence, because the target path and the page's shape are both unsettled.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts: (none yet)
- Open questions:
  - Is the deliverable the page the client names, `wiki/clients/persona-page.md`, or sections on pages that already exist? The research stage reports the surface as cross-platform rather than desktop-only, with the iPhone editing two fields and Android one, which argues against a path under `wiki/clients/`.
  - Which of the six shapes does it take? A page describing what a screen is and what it can do reads as `platform-overview` or `concept`, while the editing and removal flows read as `how-to`. That is what decides whether this is one task or several.
  - Does it overlap T15, which extracts how-to and reference material from the Windows page? Both may be reaching for the same new home.

##### Draft

Route through Research before anything else. The shape and the path are both
open, and `wiki/page-types.md:93` requires every published page to appear exactly
once in exactly one section, so a wrong path here costs a second move later.

Added after the T5 review: three places on `wiki/features/personas.md` want a
link to this page once it exists. The reviewer names them as the Note in
`## Making another one`, the end of `## Voices, briefly`, and
`## Changing a persona later`. Until then, the reviewer reports that no page in
the corpus teaches a reader how to change or remove a persona.

### T33: Give Hearth on Windows the platform-overview shape and move its catalogs out

The page carries two reference catalogs a describing page should not hold, and
its `## Status` section is a dated changelog sitting where the honest-limits
section belongs. Both are shape defects rather than wrong sentences, which is why
T2 could not touch either.

##### Details

- Agent State: Backlog
- Type: Restructure
- Scope: L
- Confidence: High
- Sizing evidence: tasks/docs/artifacts/T2.review.json, findings F1 and F9, raised by the reviewer against the platform-overview shape at wiki/page-types.md:214-252 and deferred with `needs: restructure` and no owner. The orchestrator opened the page this run and confirms the two locations exist: the process tree with its five port numbers at lines 168-181, and `## Status` at lines 228-234 opening "Hearth is pre-alpha" and dating the native-runtime decision to 2026-08-06. The reviewer additionally reports the file-tool paragraphs as content serving no objective, which the orchestrator did not assess.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts: (none yet)
- Open questions:
  - Where do the install-root tree and the port map belong? T9 is already absorbing this page's install root tree at lines 153-161 into wiki/installing.md, so check what T9 left before moving anything twice. The T4 reviewer raises the identical question for wiki/clients/macos.md and recommends the decision be made once for both platforms rather than twice.
  - Are the file-tool paragraphs Windows-specific at all? The reviewer reports that `read_file`, `list_dir`, `write_file`, the permission card and the two YAML files would read identically on the macOS page, and suggests a page under wiki/features/ that all five client pages link to. If that holds, keeping them here is itself the defect.
  - Does removing the date from `## Status` fix it? The reviewer reports not: it says removing the date leaves the section standing where the honest-limits section belongs, so the fix is the section rather than the sentence.
  - Does this overlap T15, which extracts how-to and reference material from `## What the desktop app is` on this same page? Both are restructures of one page and they cannot run in the same phase. Establish whether they are one task or two before dispatching either.

##### Draft

Do not start by cutting. This task and T15 both target `wiki/clients/windows.md`
and T33 may simply be part of T15; settling that is the first thing a research
pass does. The T4 reviewer's recommendation stands here too: the catalog
question is a corpus decision about where install trees and port maps live, and
making it once for macOS and Windows together is cheaper than making it twice.

### T34: State the Windows requirements floor on Hearth on Windows

The macOS platform overview tells a reader whether their machine qualifies. The
Windows one states no floor of any kind, so half the audience cannot answer the
first question they came with.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: M
- Confidence: High
- Sizing evidence: tasks/docs/artifacts/T2.review.json, finding F2, which the reviewer records as the largest reader gap on the page and defers with `needs: restructure` and a research block. The orchestrator opened wiki/clients/windows.md in full this run and confirms it: `## The hardware probe picks your model` at lines 188-207 describes the tiers and the scan but names no minimum, and no section states a memory floor, a free-disk figure, a verified Windows version, or whether a GPU is required.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts: (none yet)
- Open questions:
  - What is the Windows memory and VRAM floor, in a settled unit? The reviewer reports this blocked on T24, the unit-convention question, because the same threshold reads 4.16 GB under the product's renderer and 4.47 GB in decimal.
  - What are the Windows free-disk figures, and what Windows version has the install been verified on?
  - Is a GPU required at all? The reviewer raises this pointedly: the `no-gpu` fixture is a Windows machine that still plans tier 2, so the page may be able to tell a reader that a GPU is optional rather than required.
  - How does this relate to T22, which states the Windows floor in `## Before you start` on wiki/installing.md? The two tasks answer the same question on two pages. Establish the source figures once and state them consistently, or decide that only one page carries them and the other links.

##### Draft

The requirements can be established from source even though the Windows install
procedure cannot, which is what separates this task from T10. Confirm that
reading before dispatching, and settle T22's relationship to it first, because
two pages independently deriving a hardware floor is how the corpus acquired the
contradictions this run has been correcting.

### T35: Settle where the portability ledger's material is published

Two canonical pages send a reader to a document the publish step strips, so the
reader has nothing to open.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: M
- Confidence: Medium
- Sizing evidence: tasks/docs/artifacts/T3.review.json, finding F3, recorded `blocked` with `needs: research`. The reviewer reports wiki/first-run.md:325 reading "See the portability ledger, section 8" and naming it again at line 148, reports the only such document as wiki/raw/portability-ledger.md, and reports the same pointer at wiki/backend/build-pipeline.md:181 and wiki/backend/packaging-options.md:193. The orchestrator opened none of these. Sized M because it reaches three pages and the answer may be a new published page.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts: (none yet)
- Open questions:
  - Is the ledger to be published, or should canonical pages stop naming it? The reviewer frames this as the question research must answer, and reports that it did not repoint one page alone because the answer governs all three.
  - If the ledger stays unpublished, which published page carries its section 8 and its hardware-constant inventory? The reviewer reports wiki/backend/build-pipeline.md:179-195 as already republishing part of the ledger as a table, and reports that nothing published covers section 8.
  - Does wiki/whats-not-here.md:36-40, which records that the publish step strips raw/, mean a raw/ link is always a defect? If so, a corpus-wide grep for links into raw/ is the real scope of this task.

##### Draft

Research first, across all three pages at once. A repointed link on one page
while the other two still send a reader nowhere is the same defect in a new
distribution.

### T36: Give Hearth on macOS the platform-overview shape and write its missing sections

The page is missing two of the six sections its declared type requires and
carries two blocks the type sends elsewhere. Its own abstract accurately
describes what it delivers, and that promise is narrower than its type makes.

##### Details

- Agent State: Backlog
- Type: Restructure
- Scope: L
- Confidence: High
- Sizing evidence: tasks/docs/artifacts/T4.review.json, findings F1, F2, F3 and F6, all deferred with `needs: restructure` and no owner. The reviewer reports the page declaring `type: platform-overview` while missing a section on what the client does day to day and a section on the persona surface, carrying nineteen lines of install tree and port map that the type sends to a reference page, and carrying a dated status section where the type wants present-tense limits. The orchestrator opened the page in full this run and confirms the abstract at lines 27-29 reads "This page covers what your Mac needs, what the install puts on your disk, and how updates work", and that `## Status and limitations` at lines 116-128 opens with a 2026-08-07 verification date.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts: (none yet)
- Open questions:
  - Does the macOS client draw the persona face of wiki/features/persona-face.md or an orb, and what else does the macOS window hold? The reviewer records this as a research need inside its deferred F2 and reports that the missing section cannot be written without it.
  - Where do the install tree and the port map live? The T2 reviewer raises the identical question for wiki/clients/windows.md under T33. Both reviewers recommend the decision be made once for both platforms.
  - Does this wait on T6, which removes `## Installing` from this page? T6 is a smaller restructure of the same page and the two cannot share a phase. Establish whether T6 folds into this task or runs first.
  - The reviewer names wiki/clients/ios.md as the model to write against. Confirm that page has the shape before using it as one.

##### Draft

The reviewer's recommendation is one restructure covering the capability
section, the persona surface and the honest-limits section together, with the
research on the macOS window running first because one of the three cannot be
written without it. Settle the relationship to T6 before dispatching, since both
target this page.

### T37: Establish whether any client can change the default persona

A page now tells a reader to set another persona as the default before removing
the current one, and the review stage could not find a control anywhere that
does it.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: Medium
- Sizing evidence: tasks/docs/artifacts/T5.review.json, finding F4, recorded `blocked` with `needs: research`. The reviewer reports what it verified: backend/harness/valar/config/settings.py:263 reads the value only from HEARTH_DEFAULT_PERSONA, desktop-client/src-tauri/src/config_gen.rs:191 writes that key once at install, backend/harness/valar/gateway/personas_api.py:356 reads it only to refuse a removal with "set another first", and a tree-wide grep finds no writer. The orchestrator opened none of these.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts: (none yet)
- Open questions:
  - Is there any surface on any client that changes `config.default_persona`? If there is not, is that a product defect or the design?
  - The reviewer reports deliberately not touching the sentence, on the ground that softening it would leave the same dead end while stating "fixed at install" would document a probable defect as behaviour. That reasoning holds, and it is why this is a research task rather than a wording task.
  - The reviewer reports a related reader trap: wiki/features/personas.md describes a per-device "Start with" pin two sections earlier, which a reader will mistake for the default. Does the page need to distinguish them explicitly?

##### Draft

Route through Research. This is a question about the product, and the page's
sentence is correct or incorrect depending on the answer.

### T38: Settle whether concept pages take action-title headings

The page-type reference contradicts itself: it requires action-title headings
for every type but reference, and then holds up as its model concept page one
that uses gerund headings throughout.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: Medium
- Sizing evidence: tasks/docs/artifacts/T5.review.json, which reports wiki/page-types.md:59-62 requiring action-title headings for every type but reference, reports wiki/page-types.md:134 naming wiki/features/personas.md as the model concept page, and reports all four concept pages using gerund headings. It records charging no noun-heading detraction on that ground, saying that grading the page against a rule its own guide exemplifies it as satisfying would be grading the guide. The orchestrator opened none of these lines.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts: (none yet)
- Open questions:
  - Which is right, the rule or the four pages? Either the rule gains an exception for concept pages or four pages get new headings. The second is much the larger change and touches inbound anchors.
  - Which page carries the answer, wiki/page-types.md or wiki/style-guide.md?
  - Does this affect how the reviewer stage grades? It charged nothing here, so a settled rule changes future scores on four pages.

##### Draft

This is a corpus convention rather than a page defect, and it costs a reviewer
a judgement call on every concept page until it is settled. The cheap answer is
an exception in the rule; establish first whether the four pages are the
convention or the drift.

### T39: Capture the On disk pane figure for Hearth on Windows

The T2 reviewer placed a pending figure on the page for the one Settings surface
that changes something rather than opening a folder.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: XS
- Confidence: High
- Sizing evidence: `python scripts/lint_wiki.py --figures`, run by the orchestrator through a shell-capable subagent after the T2 review, reports this figure pending at wiki/clients/windows.md:80. Its output is quoted below verbatim; the orchestrator did not open the line itself.
- Sources of truth: (none, this is capture work rather than a writing task)
- Docs:
  - wiki/clients/windows.md, line 80, inside `## What the desktop app is`
- Artifacts: (none, the route is neither Author nor Review)
- Open questions:
  - None.

##### Draft

Work for a person with a screenshot tool. The linter carries the order:

- path: `images/pending/windows-ondisk.png`
- alt: The On disk pane, with Journal and memory connected
- spec: CAPTURE: Settings > On disk, the Journal and memory row with a tree
  connected, Connect and Remove both visible, 1280x800

### T40: Capture the Personas page figure for Personas

The T5 reviewer placed a pending figure against the one surface the corpus
describes at length and never shows.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: XS
- Confidence: High
- Sizing evidence: `python scripts/lint_wiki.py --figures`, run by the orchestrator through a shell-capable subagent after the T5 review, reports this figure pending at wiki/features/personas.md:164. Its output is quoted below verbatim; the orchestrator did not open the line itself.
- Sources of truth: (none, this is capture work rather than a writing task)
- Docs:
  - wiki/features/personas.md, line 164, inside `## Changing a persona later`
- Artifacts: (none, the route is neither Author nor Review)
- Open questions:
  - Does this figure wait on T32? The capture spec asks for the Personas page, which is the surface T32 will document. Capturing it now is still useful, and the figure lands on a page that already describes it.

##### Draft

Work for a person with a screenshot tool. The linter carries the order:

- path: `../images/pending/personas-changing.png`
- alt: The Personas page, with a persona open for editing
- spec: CAPTURE: desktop client, Personas page with a persona you made selected,
  showing the Who they are, Voice and What they may do sections and the Save and
  restart button, developer mode off, 1280x800
