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
| T1 | Correct the 8 GB contradiction, the Windows install root, and the two download claims in Installing Hearth | Fix | how-to | S | High | A | Complete | 6 |
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
| T17 | Correct the install root and the coexistence claim on Build pipeline | Fix | how-to | S | Medium | A | Backlog | |
| T18 | Correct the Windows install root on Native runtime | Fix | decision-record | S | Medium | A | Backlog | |
| T19 | Correct the Hearth home folder path on The second brain | Fix | concept | S | Medium | A | Backlog | |
| T20 | Capture the plan screen figure for Installing Hearth | Add | how-to | XS | High | | Backlog | |
| T21 | Capture the first-run voice check figure for Installing Hearth | Add | how-to | XS | High | | Backlog | |
| T22 | State the Windows floor in Before you start on Installing Hearth | Add | how-to | S | High | | Backlog | |
| T23 | Name which downloaded artifacts carry no published sha256 | Add | how-to | S | Medium | | Backlog | |
| T24 | Record the corpus unit convention as a decision | Add | decision-record | S | Medium | | Backlog | |

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

T17, T18 and T19 join Phase A. They are the same class of defect on three pages
the `graph` pass did not examine, found by the T1 research survey, and their
targets do not overlap with each other or with T1 through T5.

T20 through T24 carry no phase yet. T20 and T21 are figure capture, which is
work for a person with a screenshot tool rather than for a writer agent. T22,
T23 and T24 target pages whose ownership is an open question on each task, and
a phase cannot be assigned before the target is settled.

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

Note from the T1 run: `tasks/docs/artifacts/T1.research.json` reports deriving,
from crates/hearth-probe/src/plan.rs:110-159 and dictionary.yaml rather than
from an executed planner run, that an 8 GB dedicated GPU plans with the voice
resident and does not take turns, and that the take-turns branch is reached at
roughly 4.5 to 5.4 GB of VRAM. The research stage passed this on rather than
answering it, because the page is T2's. Treat it as a lead to confirm, not as
a settled figure to publish.

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

Note from the T1 run: `tasks/docs/artifacts/T1.research.json` reports that this
page's size figures at line 42 and lines 97-99 verify correct against source and
must not be changed. T1 was dispatched on a premise that those figures were
stale, and they are not: they are the planner's byte counts under the product's
own renderer. The only defect the T1 survey found here is the four-things
sentence at lines 51-54, plus the `~/Hearth` macOS default at the same lines,
which it reports as correct.

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
