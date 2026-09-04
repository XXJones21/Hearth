---
area: docs
status: open
updated: 2026-09-04
---

# Wiki task list

**Corpus root:** wiki/
**Date:** 2026-09-03
**Updated:** 2026-09-04 (Phase C run: T11 through T14, plus T64 and T65)

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
| T6 | Remove the install procedure from Hearth on macOS and salvage what only it holds | Restructure | platform-overview | S | High | B | Complete | 9 |
| T7 | Retype Getting started to concept and state honestly how a reader obtains Hearth | Restructure | concept | S | High | B | Complete | 8 |
| T8 | Write the reader-facing first-run walkthrough | Add | how-to | M | High | B | Complete | 8 |
| T9 | Give Installing Hearth a how-to spine and absorb the macOS salvage | Restructure | how-to | M | High | B | Complete | 9 |
| T10 | Write the Windows install procedure | Add | how-to | L | High | D | Backlog | |
| T11 | Update the wiki index for the retirement and the new how-to | Fix | landing | S | High | C | Complete | 9 |
| T12 | Restate the Windows gap as steps inside Installing Hearth | Fix | landing | S | High | C | Complete | 7 |
| T13 | Redirect the Installing on macOS link on Updating an install | Fix | concept | S | High | C | Complete | 5 |
| T14 | Drop install-macos.md from the Building a Hearth release frontmatter | Fix | how-to | XS | High | C | Complete | |
| T15 | Extract the how-to and reference material from What the desktop app is | Restructure | platform-overview | L | High | D | Backlog | |
| T16 | Demote Installing on macOS to wiki/raw/ and repoint its three sources citations | Consolidate | how-to | S | High | E | Backlog | |
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
| T41 | Correct the Windows video-memory requirement in README.md | Fix | (outside the corpus) | S | Medium | | Backlog | |
| T42 | Say on the iOS and visionOS pages that no build is obtainable yet | Add | platform-overview | S | Medium | | Backlog | |
| T43 | Correct the create_persona voice parameter in the First run record | Fix | decision-record | S | High | | Backlog | |
| T44 | The colour swatch the model is offered and the handler rejects | Fix | (product, not a page) | XS | High | | Backlog | |
| T45 | Link the persona walkthrough from the three pages no Phase B task owns | Fix | (three pages) | S | High | | Backlog | |
| T46 | Point the First run record at the walkthrough and reconcile its steps | Restructure | decision-record | M | High | | Backlog | |
| T47 | Capture the interview figure for Meeting your persona | Add | how-to | XS | High | | Backlog | |
| T48 | Capture the second-brain figure for Meeting your persona | Add | how-to | XS | High | | Backlog | |
| T49 | Capture the house row figure for Hearth on macOS | Add | platform-overview | XS | High | | Backlog | |
| T50 | Capture the macOS first-open dialog figure for Installing Hearth | Add | how-to | XS | High | | Backlog | |
| T51 | Move the macOS install tree and process list to a reference page | Restructure | reference | M | High | | Backlog | |
| T52 | Say what a Windows machine with no dedicated GPU gets | Fix | concept | M | High | | Backlog | |
| T53 | Name the step that removes the Hearth client on Windows | Fix | how-to | S | High | | Backlog | |
| T54 | Say what happens when setup is interrupted part way through | Add | how-to | S | High | | Backlog | |
| T55 | Record learning objectives for the pages the pipeline grades | Add | (process, not a page) | L | High | | Backlog | |
| T56 | Two nits on Hearth on macOS the reviewer deferred | Fix | platform-overview | XS | High | | Backlog | |
| T57 | Two nits on Getting started the reviewer deferred | Fix | concept | XS | High | | Backlog | |
| T58 | One nit on Meeting your persona the reviewer deferred | Fix | how-to | XS | High | | Backlog | |
| T59 | Move the disk-check sentence out of the macOS branch on Installing Hearth | Fix | how-to | XS | High | | Backlog | |
| T60 | Add the home row to the Windows install tree on Hearth on Windows | Fix | platform-overview | XS | High | | Backlog | |
| T61 | Capture the persona-in-use figure for Getting started | Add | concept | XS | High | | Backlog | |
| T62 | Capture the handover figure for Meeting your persona | Add | how-to | XS | High | | Backlog | |
| T63 | The persona name length limit is off by one at each end | Fix | (product, not a page) | XS | High | | Backlog | |
| T64 | Drop install-macos.md from the Getting started frontmatter | Fix | concept | XS | High | C | Complete | |
| T65 | Redirect the shipped-wording sentence in the First run record | Fix | decision-record | S | High | C | Complete | 4 |
| T66 | Correct the envs\voice row on the two Windows install-root trees | Fix | (two pages) | S | High | | Backlog | |
| T67 | Split or retype Updating an install, which is four registers on one page | Restructure | concept | L | High | | Backlog | |
| T68 | Two backticked-filename links on Updating an install | Fix | concept | XS | High | | Backlog | |
| T69 | No page states which voice engine runs on which platform | Add | (undecided) | M | High | | Backlog | |
| T70 | The linter has no index-membership check, so a page can publish with no sidebar entry | Add | (tooling, not a page) | S | High | | Backlog | |
| T71 | Decide whether a reader-facing page reproduces the shipped refusal wording | Fix | (undecided) | S | High | | Backlog | |
| T72 | Settle which index section a decision record belongs in | Fix | landing | S | Medium | | Backlog | |
| T73 | Page types and the publish script disagree about the once-only rule | Fix | reference | XS | High | | Backlog | |
| T74 | Compress What is not here to routing and retitle its two headings | Restructure | landing | S | High | | Backlog | |
| T75 | An unverifiable quotation on Updating an install | Fix | concept | S | High | | Backlog | |
| T76 | Four settled questions still presented as open on Build pipeline | Fix | how-to | S | High | | Backlog | |
| T77 | State whether an edit bumps last_reviewed | Add | (process, not a page) | XS | High | | Backlog | |
| T78 | The install-root tree in the First run record marks built directories as planned | Fix | decision-record | S | High | | Backlog | |
| T79 | No decision record says what would reopen its decisions | Add | decision-record | M | High | | Backlog | |

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

| Passage | Lines | Lands in | Task | Landed |
| :-- | :-- | :-- | :-- | :-- |
| The unsigned right-click-Open procedure, the only numbered steps in the cluster | 43-53 | wiki/installing.md | T9 | Yes, as `## Open Hearth for the first time on macOS` |
| The verbatim message shown to a machine below the floor | 32-34 | wiki/installing.md | T9 | Yes, as prose rather than a blockquote, by ruling |
| The Backend and Mind-and-voice rows of the plan table | 76-77 | wiki/installing.md | T9 | Yes, and the table now carries all five rows |
| The macOS uninstall, including copying `home/` out first | 128-133 | wiki/installing.md | T9 | Yes, with the copy-out step placed before the deletion |
| The log filenames and four named failure modes | 135-155 | wiki/installing.md | T9 | Yes, as `## Work out what went wrong` |
| Starting and stopping the backend on macOS | 118-126 | wiki/clients/macos.md | T6 | Yes, as `## Start and stop the house` |
| The measured RTF of 0.96 on the 8 GB Air (from clients/macos.md) | 102 | wiki/clients/macos.md | T6 | Yes, published as 0.961 with its provenance |
| The Windows install root tree (from clients/windows.md) | 153-161 | wiki/installing.md | T9 | Yes, with a `home` row the source tree omitted |
| The four-tier model dictionary description (from clients/windows.md) | 196-202 | wiki/installing.md | T9 | Yes, under `### What the plan says` |

All nine rows landed in the Phase B run of 2026-09-04, and the T9 reviewer
verified its seven independently against their sources rather than taking the
author's report for it. Two rows landed with a deliberate difference from the
source passage, both recorded above and both reasoned in the task detail: the
refusal message carries no figures because one of its three is contradicted by
current source, and the Windows tree gained a `home` row because the source tree
omits a directory the installer always creates.

Salvage is therefore no longer what blocks T16. The remaining precondition is
the inbound references, which is Phase C. Note that the Phase B tasks already
shrank that list: T6 and T9 each repointed their own page's prose links and
`related` entry, and each deliberately left its `sources` entry naming
`wiki/install-macos.md` as provenance. The T6 research stage also reported one
inbound reference the list at the top of this section omits, at
wiki/first-run.md:192.

The research stage listed a tenth item, `wiki/getting-started.md:36-46`, the
side-by-side requirements written for a reader who has not chosen a platform.
Revising that page to keep removes the item: the content stays where it is.

Every inbound reference to `install-macos.md` must be redirected before T16
runs. The set above was measured before Phase A. Re-measured on 2026-09-04 at
the start of the Phase C run, ten survive rather than seventeen: Phases A and B
cleared seven as a side effect of their own edits. The current set, its three
kinds, and which of them actually block the retirement are tabulated on T16.
Phase C clears the seven that block; the three `sources` entries are T16's own
work under the demote decision recorded there.

## Phases

A phase is a group of one-page tasks whose targets do not overlap. No page
appears twice in one phase.

| Phase | Tasks | What it does |
| :-- | :-- | :-- |
| A | T1, T2, T3, T4, T5 | Correct every verified defect on a page that survives. Nothing here depends on a verdict. |
| B | T6, T7, T8, T9 | Reshape the survivors and land the salvage. |
| C | T11, T12, T13, T14, T64, T65 | Redirect every inbound reference that blocks the retirement, and update the registers. Six disjoint pages. T64 and T65 were opened on the run itself, when measuring the references found two gate-blocking ones that no row owned. |
| D | T10, T15 | The blocked Windows procedure, and the Windows page split. |
| E | T16 | Demote `wiki/install-macos.md` to `wiki/raw/` and repoint its three `sources` citations. Its Phase C gate is now clear; see The retirement gate, measured. |
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

T66 through T79 carry no phase. Every one came out of the Phase C stages rather
than out of a plan, and a phase groups tasks by the page they touch, so none can
be assigned until its target is settled. Six of them state that plainly: T69,
T71, T72 and T79 have no settled target page, T66 and T79 each touch more than
one page and split after Research, and T70, T73 and T77 are tooling or process
work that no writer stage runs on. Two ordering constraints are already known and
recorded on the rows themselves: T76 and T17 both edit
`wiki/backend/build-pipeline.md` and must not share a phase, and T70 must not run
before T73 settles the exception any index check would have to encode.

Phases F and G were opened by the Phase A run of T2 through T5. Every task in
them came out of a research stage rather than out of the `graph` pass, which is
the pattern this pipeline should expect: a corrections task that reads the source
tree properly finds the same defect on pages nobody surveyed.

Phase B ran on 2026-09-04 and completed all four of its tasks. It ran in two
groups rather than one, which is a departure from the phase rule as written and
is worth recording as a precedent. The rule groups tasks so that no page appears
twice, and by that test all four were disjoint. But T8 created a page that T6,
T7 and T9 all needed to link to, and a dead body link is a hard linter error, so
running the four at once risked three broken pages if T8 failed. T8's author ran
first and alone, and the other three followed in parallel once the page existed.
The rule that actually governed was creation before reference, which the phase
rule does not express. A phase whose tasks are disjoint by page can still be
ordered by dependency.

That sequencing also solved a real problem the T8 research stage raised: the
three pages routing readers to the old record were exactly T6's, T7's and T9's
targets, T8 could not edit them, and left alone the corpus would have shipped a
walkthrough nothing linked to. Each of the three authors carried the repoint for
the page it already owned.

Phase B opened twenty-three new rows, T41 through T63. That is more than the
phase contained, and it is not a sign the phase went badly: the research stages
found defects on pages nobody had surveyed, the authors reported what they could
not place rather than dropping it, and the reviewers left every unfinished
checklist entry as work somebody has to schedule. Three of the new rows are
product defects rather than documentation, six are figure captures, and one,
T55, is a finding all four reviews made independently.

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

Updated after the Phase B run of T6 through T9. Again run twice, once after the
authors and once after the reviewers, and this time the two passes disagreed on
the gate, which is the case that justifies running both.

| When | Pages | Errors | Warnings | Figures pending |
| :-- | :-- | :-- | :-- | :-- |
| After the four authors | 29 | 2 | 193 | 8 |
| After the four reviewers | 29 | 0 | 196 | 10 |

The two errors after the author stage were both `british-spelling` on
`wiki/clients/macos.md`, and both traced to the orchestrator's own T6 dispatch,
which used a British spelling in the direction and in a figure capture spec that
the author then followed. They were the only errors in the corpus. The T6
reviewer was told about them explicitly and cleared both, which is why the gate
reads 0 after the review stage. The lesson is narrow and worth keeping: a
dispatch prompt is prose an author will copy, so it is subject to the same house
rules as the page.

Pages rose from 28 to 29 with `wiki/meeting-your-persona.md`. Warnings fell from
198 to 193 across the author stage and rose to 196 across the review stage, and
the whole of that rise is figure work orders: pending captures went 4 to 8 to
10. The final breakdown is 88 `long-paragraph`, 62 `bold-lead`, 24
`long-section`, 12 `reader-drift` and 10 `figure-pending`. The six new figures
are T47, T48, T49, T50, T61 and T62.

`python scripts/publish_wiki.py --out <temp>` was run once at the end of this
phase, because the phase added a page and moved content between pages, which is
where a broken cross-reference or a duplicate basename surfaces. It rendered 29
pages plus the sidebar and reported nothing.

Updated after the Phase C run of 2026-09-04: T11 through T14, T64 and T65. Run
twice again, once after the authors and once after the reviewers.

| When | Pages | Errors | Warnings | Figures pending |
| :-- | :-- | :-- | :-- | :-- |
| After the six authors | 29 | 0 | 196 | 10 |
| After the four reviewers | 29 | 0 | 196 | 10 |

Zero errors at both points, which is the gate. This is the first phase in which
the two passes returned identical numbers, including the per-rule breakdown: 88
`long-paragraph`, 62 `bold-lead`, 24 `long-section`, 12 `reader-drift` and 10
`figure-pending`. That is what a phase of frontmatter and single-sentence
redirects looks like against a linter that measures prose. No new figures were
requested, so no figure task was opened.

`python scripts/publish_wiki.py --out <temp>` was run once at the end. Exit code
0, 29 pages plus `_Sidebar` rendered, nothing else printed. The subagent that ran
it confirms `install-macos.md` is still among the rendered pages, which is
correct: Phase C clears the references and Phase E does the retirement.

None of the six authors and none of the four reviewers could execute commands.
Every one of them said so explicitly and none claimed a linter run it had not
made. Several read `scripts/lint_wiki.py` as a file to establish what it owns so
that they did not report findings the linter already covers, and two hand-counted
paragraphs against the 60-word limit and asked that the counts not be read as a
linter run. All three tooling passes on this phase, both linter runs and the
publish, were made by a separate subagent with a shell.

### The retirement gate, measured

The gate T16 waits on is that no inbound reference to `wiki/install-macos.md`
remains that a reader or the linter can follow. Measured three times on
2026-09-04 with
`grep -rn 'install-macos' wiki/ --include=*.md`, excluding `wiki/raw/` and the
page itself:

| When | References | Blocking |
| :-- | :-- | :-- |
| Before Phase C | 10 | 7 |
| After the six authors | 3 | 0 |
| After the four reviewers | 3 | 0 |

All seven blocking references are gone: the three `related` entries that would
have published as broken See also links, and the four body links that would have
been `dead-link` errors. The three that survive are the frontmatter `sources`
entries at wiki/clients/macos.md:11, wiki/clients/windows.md:13 and
wiki/installing.md:15. The verifying subagent opened each file and confirmed the
classification from the frontmatter block rather than inferring it from the line,
and confirmed that none of the three pages links a reader to the retiring page in
prose. `scripts/lint_wiki.py:284-286` never resolves a `sources` entry, so none
of the three fails the gate, and all three are repointed at
`wiki/raw/install-macos.md` by T16 itself under the demote decision recorded on
that row.

**T16 is unblocked by Phase C.** Its remaining precondition is the salvage, which
the Phase B run recorded as landed, plus T15, which does not block it, and the
two rows Phase C added to its gate list, T64 and T65, both now `Complete`.

Phase C opened sixteen new rows, T64 through T79. Two of those, T64 and T65, were
gate work the phase itself needed: measuring the inbound references found two
that block the retirement and that no row owned, which is the argument for
measuring a gate rather than reading a list of it. The other fourteen came out of
the research, author and review stages, and eleven of the fourteen are findings a
reviewer deferred or blocked rather than defects the phase introduced.

One pattern is worth recording. The four Phase C tasks were sized against a
tracker written before Phases A and B ran, and three of the four premises had
moved: seven inbound references had already been cleared, all three other
Windows-guide announcements had been removed, and `### Windows` on
`wiki/installing.md` had moved from lines 48-56 to 69-89. Nothing was broken by
this, because each task's research stage re-measured before its author acted and
one of them corrected the tracker's own stale citation. But the lesson is the one
integrity rule 2 already states from a different direction: a file read in an
earlier session is not a read, and that applies to a task row as much as to a
page.

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

- Agent State: Complete
- Type: Restructure
- Scope: S
- Confidence: High
- Sizing evidence: wiki/clients/macos.md, re-read in full on 2026-09-04 after the Phase A edits moved its lines. `## Installing` now runs lines 91-108 and contains a four-step numbered procedure. Line 108 carries the measured RTF of 0.96 on the 8 GB Air, inside step 4. Lines 87-89 carry one sentence on Settings > Connection at the end of `## What installing gives you`. Lines 110-120 are `## Updating`, whose lines 117-120 carry the unsigned-app reasoning for why there is no in-app updater. wiki/page-types.md:243-245 states that installation lives on the install page and that a platform overview which grows an install procedure has become a second install guide.
- Sources of truth:
  - source: desktop-client/src/components/settings/SettingsView.tsx:238, 271, 288, 291, 297, 661, covers the actual Settings pane the salvaged passage describes: a section labelled `Connection` holding a row labelled `The house` with Start, Stop and Restart controls, and a separately scoped `Connections` section in the same pane
  - source: desktop-client/src/components/settings/SettingsView.tsx:272, covers the shipped hint text the salvaged sentence paraphrases
  - source: wiki/raw/macos-status.md:21-23, covers the sole record of the measured real-time factor, which states 0.961 on a tool-grounded reply and never publishes
  - tooling: `python scripts/doc_graph.py --json`, run 2026-09-04, covers the current cluster shape and the duplicate scores between this page's sections and wiki/install-macos.md and wiki/installing.md
  - tooling: `python scripts/lint_wiki.py --warnings`, run 2026-09-04, covers the mechanical findings on this page
  - contextual: wiki/page-types.md:214-252, covers the platform-overview shape and its rules on installation, dated status logs and reference material
  - contextual: wiki/install-macos.md:118-126, covers the start-and-stop material this task copies
- Docs:
  - wiki/clients/macos.md, `## Installing`, `## What installing gives you` and `## Status and limitations`
- Artifacts:
  - Research: tasks/docs/artifacts/T6.research.json
  - Author: tasks/docs/artifacts/T6.author.json, wrote wiki/clients/macos.md
  - Review: tasks/docs/artifacts/T6.review.json, verdict PASS, minor nits open, score 6 to 9
- Review checklist, and where each entry went:
  - L1, the two `british-spelling` hard errors: `done` by the reviewer. Both were the only errors in the corpus and both originated in the orchestrator's dispatch wording rather than in the author's judgment.
  - F1 close-versus-quit stated for macOS, F2 uninstall and containment claims corrected, F3 duplicated updater bullet trimmed, F4 `last_reviewed` bumped: all `done` by the reviewer. The reviewer graded F2 at 2 points because the page's own tree names `home/` as where memory and journal live and four lines later told the reader that deleting that folder is the uninstall, with no warning.
  - F5, the page calling the local server "the house" and then "the backend" twice: `deferred`, no research needed. Opened as T56.
  - S1, the missing persona surface section: `deferred`, `needs: restructure`, `owner: T36`. T36 exists at tasks/docs/tracker.md and its statement covers writing this page's missing sections, so it is confirmed rather than reopened. The reviewer adds that T36 inherits two facts already on this page that belong in that section: the cloned voice, and the real-time factor now hanging off a ports bullet.
  - S2, extracting the install tree and port list to a reference page: `deferred`, `needs: restructure`. Opened as T51 from the author's `extraction_needed`, and confirmed here to cover it.
  - R3, whether the start-and-stop section carries two further verified facts: `deferred`, an orchestrator decision rather than research. Opened as T56 alongside F5.
- Verification: `python scripts/lint_wiki.py` reports 29 pages checked, 0 errors, 196 warnings, run after the reviewers finished. `python scripts/publish_wiki.py` rendered 29 pages plus the sidebar with no broken cross-reference, unresolved link or duplicate basename. Neither the author nor the reviewer could execute commands in this run, and both said so rather than reporting a linter pass they had not made; every command above was run by a separate subagent with a shell.
- Objective gaps recorded by the reviewer, which derived six objectives because neither the page nor the research artifact records any:
  - "Describe how the persona appears on macOS" is not taught. The reviewer reports the page never says what Hearth looks like on a Mac, and that the platform-overview shape requires the section. This is T36's, not charged against this task.
  - "Start and stop the house from Settings" is taught as description rather than as an ordered procedure, and the shape's one inline-procedure slot is empty. The reviewer names it the natural candidate if that slot is ever filled. Recorded, not opened: the page deliberately holds no procedure this phase.
  - The reviewer reports two blocks serving no objective, the install-root tree with the port list and the real-time measurement. The first is T51's and the second moves with T36.
- Open questions:
  - Does wiki/installing.md carry the macOS install procedure and the troubleshooting section by the time this page publishes? The author reported that three links on this page now point there for material T9 had not landed when it wrote, that the dispatch directed the repoint on the ground that T9 lands both in this phase, and that nothing on this page can verify T9 completed.
  - Should the start-and-stop salvage widen to carry three further facts the author found verified in source and already published for Windows? The author reported all three and reported leaving each off the page because the dispatch settled only the Restart control: that closing the window on macOS hides it and leaves the backend running while Quit is the explicit stop; that the Start, Stop and Restart controls appear only when the device has no remote server address and does have an install root, so a Mac that joined a house elsewhere sees no house row at all; and that Stop and Quit file the conversation to the journal before anything is killed, which is the reason to prefer Stop over killing the process.
  - Does the corpus want a reader-facing performance number resting on one run from 2026-08-07 with no artifact in the source tree asserting it? The author reported publishing the figure with its provenance stated, as directed, and reported the question of whether it should be re-measured or retired as still open.
  - For T16: one deliberate reference to wiki/install-macos.md remains on this page, the `sources` frontmatter entry. The author reported leaving it exactly as found, per the ruling.
  - Who writes the persona surface section this page still lacks? The author reported leaving the shape gap open rather than filling it, because T36 owns it and filling it here would mean writing claims this stage did not verify.
  - Should wiki/clients/macos.md keep at all? The reassessment trigger stands but the premise recorded for it does not. `python scripts/doc_graph.py --json`, run 2026-09-04, gives this page a `unique` entry of `Status and limitations` and reports a five-page cluster, not a six-page one in which this page alone lacks a unique section. The trigger itself is unchanged: after this task removes `## Installing`, is what remains taught by wiki/installing.md and wiki/updates.md? The research stage reported two facts pointing opposite ways. Against the page: the same run scores `Updating` a 0.76 duplicate of wiki/installing.md's `Updating, briefly`, and `What your Mac needs` a 0.83 duplicate of wiki/install-macos.md's `What you need`, which T9 absorbs. For the page: the unsigned-app reasoning is absent from wiki/installing.md, though wiki/updates.md carries it in fuller form. The keep verdict at tasks/docs/tracker.md:76 is not revisited here.
  - Does the measured real-time factor of 0.96 survive scrutiny as published prose? The research stage reported that its only record is wiki/raw/macos-status.md:21-23, which never publishes, states 0.961 rather than 0.96, and describes it as measured on a tool-grounded reply where the page says "In a real conversation"; and that nothing in the source tree asserts the value, which is a single run dated 2026-08-07.
  - How should a page name the start-and-stop controls, given that no page currently names them fully? The research stage reported that wiki/install-macos.md:123 says "Settings > Connection", wiki/clients/windows.md:96 says "Settings > The house", and the source nests the second inside the first.
  - Is wiki/first-run.md:192 an inbound reference to wiki/install-macos.md that T16 must redirect? The research stage reported it is, and that the tracker's inbound-reference list at tasks/docs/tracker.md:213-215 omits it. Recorded here for T16 because T6 is the task that shrinks that list.
- Orchestrator rulings, so the author is not left choosing:
  - The replacement link points at `wiki/installing.md`, not at `wiki/install-macos.md`. T9 lands the macOS procedure on that page in this same phase, and adding a fifth inbound reference to a page T16 retires is work T16 would have to undo.
  - The real-time factor lands in `## What installing gives you`, beside the sentence on the voice engine being built against Apple's GPU, which is the surviving section that already discusses macOS voice performance. It does not go in `## Status and limitations`: that is the honest-limits section and a good measurement is not a limit. Writing a persona-surface section for this page is T36's work, not T6's.
  - T6 repairs the orphaned back-reference in `## Status and limitations`, which reads "first launch needs the right-click-Open step above" and refers to a step inside the section being removed. Removing the section without repairing it leaves the page wrong.
  - T6 owns the dated provenance sentence in `## Status and limitations`. It is a sentence about an install guide that this page will no longer contain, wiki/page-types.md:246-248 forbids a dated status log in the honest-limits section, and T4 declined it in Phase A naming this task's ground.
  - The copied passage names the full path the source has, `Settings > Connection`, and the row within it, `The house`. It also names the Restart control and states that stopping frees the memory the model and the voice hold without closing Hearth. All three are verified in the source and all three are already published for Windows, which makes a macOS reader the only one without them.
  - T6 owns the two prose links to wiki/install-macos.md on this page and the `related` frontmatter entry naming it, repointing each to wiki/installing.md. The `sources` entry stays: it is provenance, the linter never resolves it, and rewriting a page's history is not this task's work. That ruling matches the one recorded on T2.

##### Draft

Remove `## Installing` at lines 85-102 and leave a link to the install page in
its place.

Two things must survive the removal. The measured RTF of 0.96 at line 102 has
its only other home in `wiki/raw/macos-status.md`, which never publishes, so it
moves into a surviving section of this page. The start-and-stop material from
`wiki/install-macos.md:118-126` lands here and extends the single sentence at
lines 81-83, because this page is where a macOS reader looks for it once the
install page is one page for both platforms.

Note that the page carries the reasoning for why there is no in-app updater on
macOS, tied to the app being unsigned. That reasoning is macOS-specific, is not
in `wiki/installing.md`, and is part of why this page keeps. Do not lose it.

Notes from the author, on where the delivered change departed from the direction
above:

- The author reported that the page now runs abstract, what it does today, what
  installing gives you, start and stop the house, what it needs, updating, what
  it cannot do yet, and that it retitled two headings to match the other four
  client pages under the cross-client ordering rule.
- The author reported putting the start-and-stop salvage under its own heading
  rather than inside the section that already held the sentence it extends,
  because keeping it inline would have made one section of roughly 310 words
  covering two subjects.
- The author reported publishing the real-time factor as 0.961 on a real
  tool-grounded reply rather than as 0.96 in a real conversation, because that
  is what the only source supports.
- The author reported moving the dated provenance sentence rather than deleting
  it: removed from the honest-limits section where the page-type rules forbid a
  dated status log, and its substance restated as the provenance on the
  measurement itself.
- The author reported leaving the persona surface section absent and the page
  carrying no inline procedure, because the only procedure the page held was the
  install and that leaves.
- The author reported confirming, before removing the numbered steps, that the
  model tier figures and Sulivan's spoken first line already publish on
  wiki/installing.md, so nothing in the removed steps leaves the corpus.

### T7: Retype Getting started to concept and state honestly how a reader obtains Hearth

The page is declared a how-to and has no task steps, duplicates two sections
that survive elsewhere, and is the only page written for a reader who does not
yet have an installer. That last property is why it keeps, and it is where the
corpus has to say plainly how a reader gets Hearth today.

The task statement was corrected twice on 2026-09-04, and the second correction
reverses part of the first. It originally read "give it the download location".
An orchestrator grep across wiki/ for GitHub URLs, `.dmg`, `.msi`, `releases/`
and download phrasing found no reader-facing download location, and the
statement was rewritten on the reading that Hearth is simply not distributed.
The research stage then established that it is. A published release exists, and
this orchestrator confirmed the corpus's own record of it: wiki/releasing.md:199-200
states the artifacts and a `SHA256SUMS.txt` go to the GitHub release, and
wiki/releasing.md:208 records "0.1.0 alpha, published 2026-08-22, shipped
Windows, macOS and Android". A grep of wiki/ could not see this because the
corpus never links a thing that already exists. The corrected statement stands
as written, and the honest sentence it asks for is now a link rather than an
admission of a gap.

##### Details

- Agent State: Complete
- Type: Restructure
- Scope: S
- Confidence: High
- Sizing evidence: corrected from M to S by tasks/docs/artifacts/T7.research.json, whose route ran at M. The research stage opened the file and reported that exactly one page changes, that the two dropped sections are pure duplication with all seven of their links already present in wiki/_index.md, that `concept` passes the linter's accepted type list at scripts/lint_wiki.py:48-50, and that retyping breaks no inbound link, which is below the M definition of several pages or a net-new page. The orchestrator's own read stands behind the anchors: wiki/getting-started.md, re-read in full on 2026-09-04, is 83 lines rather than the 84 first recorded. Frontmatter line 4 reads `type: how-to`, line 3 reads `status: closed`. `## What you need` at lines 34-46 carries the side-by-side Windows and macOS requirements and the house-and-window framing. `## Three steps to a running house` at lines 48-60 restates the three beats. `## Where to go next` at lines 62-76 restates routing that wiki/_index.md:22-95 carries. `## Before you start` at lines 78-83 carries the pre-alpha caveat and the Developing link.
- Sources of truth:
  - canonical: https://github.com/XXJones21/Hearth/releases/tag/v0.1.0-alpha, covers the distribution point: the research stage reported fetching it and finding it published 2026-08-22, marked prerelease and not draft, carrying `Hearth_0.1.0_x64-setup.exe`, `Hearth_0.1.0_x64_en-US.msi`, `Hearth_0.1.0_aarch64.dmg`, `Hearth_0.1.0_android.apk` and `SHA256SUMS.txt`
  - source: crates/hearth-probe/src/plan.rs:151-157, covers `PlanError::TooSmall` and the refusal floor of 4,466,165,856 bytes of pool
  - source: crates/hearth-probe/tests/plan_fixtures.rs:36-52, covers the pinned assertion that an 8 GB Apple Silicon Mac plans tier 0, coexists, and emits no "one at a time" warning
  - tooling: `python scripts/lint_wiki.py`, run 2026-09-04, covers the accepted `type:` values at scripts/lint_wiki.py:48-50, which include `concept`, and the single existing warning on this page
  - contextual: wiki/releasing.md:39-41, 199-200 and 208, covers the corpus's own record that the artifacts go to a GitHub release and that 0.1.0 alpha was published 2026-08-22 shipping Windows, macOS and Android
  - contextual: wiki/page-types.md:129-154, covers the concept shape and its rule that a concept page carries no procedures
  - contextual: wiki/_index.md:22-95, covers the routing that this page's `## Where to go next` duplicates
- Docs:
  - wiki/getting-started.md, frontmatter line 4 (`type:`), `## What you need`, `## Three steps to a running house`, `## Where to go next` and `## Before you start`
- Artifacts:
  - Research: tasks/docs/artifacts/T7.research.json
  - Author: tasks/docs/artifacts/T7.author.json, wrote wiki/getting-started.md
  - Review: tasks/docs/artifacts/T7.review.json, verdict PASS, minor nits open, score 6 to 8
- Review checklist, and where each entry went:
  - F2, the page defining a persona where it should have defined the product: `done` by the reviewer, which reports this was the most expensive sentence on the page, since the corpus's only pre-installer entry point opened in the exact words the personas page uses for a persona.
  - F4, saying that the Android artifact needs a house: `done` by the reviewer.
  - F1, the concept shape's "what it looks like in use" section: `done` by the reviewer, which reports adding a 57-word section with no new outbound link, so the routing the reshape dropped is not rebuilt, plus the page's first figure request.
  - F3, what the page tells a Windows reader with integrated graphics: `blocked`, `needs: research`. Opened as T52.
  - F5, the page telling a reader twice that Sulivan interviews them, and F6, a persona called `it` one line above a section calling them `they`: both `deferred`, no research needed. Opened together as T57.
- Verification: the corpus-wide run recorded on T6 covers this page. `python scripts/lint_wiki.py` reports 0 errors after the reviewers, and the reviewer reported clearing this page's one pre-existing long-paragraph warning and adding one `figure-pending` warning by design.
- Objective gaps recorded by the reviewer, which derived five objectives because neither the page nor the research artifact records any:
  - "Decide whether your machine can run Hearth" is not taught for a Windows machine with integrated graphics. The reviewer reports that the abstract promises the reader will find this out, and that the three bands actively invite such a reader to measure video memory they do not have. That is T52 and it is the largest reader gap on the page.
  - "Name where to get Hearth today and which artifacts exist" is taught, and the reviewer records that this is the objective no page in the corpus taught before this task.
  - The reviewer reports no content on the page serving no objective, and that all five derived objectives sit at a level matching `type: concept`.
  - That no objectives are recorded anywhere is itself reported as a gap. Opened as T55, which is corpus-wide rather than this page's.
- Open questions:
  - Should the page state the video-memory bands in a unit a reader can check against their own screen? The reviewer reported recomputing both boundaries from source and getting 4.47 GB and 5.43 GB decimal, matching the page, and reported that the product prints GiB under a GB label so the same boundaries read 4.16 and 5.06 on screen, leaving the page about eight percent high against the product's own output. It reported that no reader is misled today, checking against real card sizes, and did not change it because that would override a directed editorial call. The unit half of this is T24.
  - Who maintains the version-and-date sentence? The reviewer reported that it goes stale silently at the next release and recommended either giving it an owner or dropping the version.
  - Is v0.1.0-alpha still the newest Hearth release when this page publishes? The author reported that the research stage graded this unverifiable, because a single fetch of the rendered listing showed one release and that is not proof no newer one exists or will exist. It reported that linking the floating index rather than the pinned tag means a later release does not make the link dead, but that the version and date sentence needs re-checking at the next release.
  - Should the page link the version-pinned release URL, which is what the research stage verified and which names exact artifacts, or the floating releases index, which survives the next release but which that stage did not verify will always list something? A pinned link goes stale silently; a floating link cannot be checked against an asset list. Settled by an orchestrator ruling below.
  - Which task owns README.md:74-79? The research stage reported that it repeats the contradicted Windows requirement sentence verbatim, that it sits outside the corpus root, and that no row in this tracker names it. Opened as T41.
  - What number should a page give for the Windows requirements floor? The research stage reported three source-derived candidates that say different things: Hearth refuses below roughly 4.5 GB of video memory, which is 4.16 GB in the units the product itself prints; it holds the model and the voice resident together at roughly 5.4 GB and above, which is 5.06 GB as printed; and between those it plans but warns the persona will think and speak one at a time. It also reported that an 8 GB card gets tier 1, labelled Small, which is one tier above the smallest. The unit half of this question is T24.
  - Does anything need to change for a reader who lands on wiki/clients/ios.md or wiki/clients/visionos.md expecting to install? The research stage reported that the release carries no iOS asset and that its notes say TestFlight follows, and that neither page states no build is obtainable. Opened as T42.
  - For T11: once this task lands, wiki/getting-started.md is where the corpus says how to obtain Hearth, and wiki/_index.md:24-27 introduces the Getting started group without mentioning that. Recorded so T11's dispatch carries it.
- Orchestrator rulings, so the author is not left choosing:
  - The premise correction recorded above is itself corrected, and this is the more important of the two. A distribution point exists. The research stage fetched it live, and this orchestrator confirmed it from the tree independently: wiki/releasing.md:199-200 states that artifacts and a `SHA256SUMS.txt` go to the GitHub release, and wiki/releasing.md:208 records "0.1.0 alpha, published 2026-08-22, shipped Windows, macOS and Android", which matches the fetched release's date and asset set. The gap is therefore a missing link on a page that keeps, not a missing product. Note the limit on this confirmation: the orchestrator holds no web access and did not open the URL, so the live release rests on the research stage's report plus the two corroborating in-tree records above.
  - The page links the floating releases index and names v0.1.0-alpha as what is published there today, with its date. Reason: wiki/releasing.md documents a continuing release process, so a version-pinned link on the corpus's entry page rots at the next release, while the floating index follows necessarily from a non-draft release existing. The pinned URL stays recorded here and in the research artifact as the evidence.
  - The contradicted "around 8 GB of video memory" figure comes out. In its place the page states the behaviour in three bands, which is what source supports and what T2 landed on wiki/clients/windows.md for the same mechanism: below roughly 4.5 GB of video memory Hearth declines and says why; between there and roughly 5.4 GB it installs but the persona thinks and speaks one at a time; above that both stay resident. State it as behaviour a reader will see rather than as a spec table. A concept page whose job includes deciding whether a machine qualifies fails that job if it names no floor at all, which is the defect the reviewer scored as the largest reader gap on wiki/clients/windows.md.
  - README.md is outside the corpus root and is not this author's to edit, even though it repeats the sentence being corrected here.

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

State how a reader gets Hearth today. The research stage established that a
published release exists, so the page links the floating releases index, names
v0.1.0-alpha as what is published there today with its date, says which
platforms have an artifact, and is honest that the macOS artifact is unsigned
and not notarized and that there is no iOS artifact.

Notes from the author, on where the delivered change departed from the direction
above:

- The author reported proceeding rather than stopping on the disagreement
  between the dispatch's `Page type` and the page's own declared `type:`,
  because the disagreement is the task rather than an ambiguity.
- The author reported re-heading `## What you need` to an action title and
  clearing the page's long-paragraph warning in the process.
- The author reported writing the concept shape's links-out step inline, one
  link per section, rather than as a closing links section, because a links
  section would rebuild the routing the reshape had just dropped.
- The author reported that the Windows three-band statement traces to the
  evidence of a contradicted claim and to an open question rather than to a
  verified claim, that the dispatch made the editorial call, and that it
  confirmed the three branches directly in source: the coexist arm, the
  take-turns arm with its one-at-a-time warning, and `PlanError::TooSmall` as
  the only refusal. It reported naming no graphics card.
- The author reported pruning `related` from ten entries to six and adding
  `install-macos.md`, because the page now sends a reader toward an unsigned
  macOS artifact, and reported that all six resolve.

### T8: Write the reader-facing first-run walkthrough

The install page hands a reader off to do first run, and the page it hands them
to is a design record ending in four unresolved open questions. This is the page
that receives the handoff.

##### Details

- Agent State: Complete
- Type: Add
- Scope: M
- Confidence: High
- Sizing evidence: wiki/first-run.md headings re-read on 2026-09-04 after the Phase A T3 edits moved its lines. `## Beat two: making someone` now starts at line 214 with subsections at 216, 233, 257 and 272, `## Beat three: the second brain` starts at line 300, and `## Open questions` starts at line 328. Frontmatter line 4 declares `type: decision-record`. wiki/installing.md:142-147 and wiki/getting-started.md:53-60 both route a reader to that page to perform first run. wiki/page-types.md:150-154 states that a concept or record page containing steps belongs on a how-to page it links to. wiki/_index.md:34 carries a `## Meeting your persona` section, whose entries at lines 41-44 are First run, Personas, The persona face and Voice. `wiki/meeting-your-persona.md` does not exist: a glob for it returns nothing.
- Sources of truth:
  - source: backend/harness/valar/tools/tools.yaml:1112-1121 and 1125-1126, covers the `create_persona` tool schema, including that the voice parameter is `voice_design` as an array, and the colour swatch list the model is offered
  - source: backend/harness/valar/tools/handlers/creation.py:52-60, 88-99 and 288-296, covers the accepted colour swatches, the fallback when one does not match, and the handler signature
  - source: backend/harness/valar/gateway/first_run.py:221, covers the first-run gateway's own declaration of `voice_design`
  - source: the desktop client's interview surface, covers the screen titles the reader actually sees, including "Let's make someone." becoming "Meet <name>." at the handover
  - tooling: `python scripts/lint_wiki.py --summary`, run 2026-09-04 under Python 3.13.5, covers the corpus baseline of 28 pages, 0 errors, 198 warnings that this new page must not break
  - tooling: `python scripts/lint_wiki.py --figures`, run 2026-09-04, covers the four pending figure captures, none of which is an interview or second-brain screen
  - contextual: wiki/first-run.md:214-326, covers the structure the extraction follows
  - contextual: wiki/page-types.md:96-127, covers the how-to shape this page is written to
- Docs:
  - wiki/meeting-your-persona.md, the new page, all sections
- Artifacts:
  - Research: tasks/docs/artifacts/T8.research.json
  - Author: tasks/docs/artifacts/T8.author.json, wrote wiki/meeting-your-persona.md
  - Review: tasks/docs/artifacts/T8.review.json, verdict PASS, minor nits open, score 6 to 8
- Review checklist, and where each entry went:
  - F1, a step telling the reader to say hello when the product speaks first: `done` by the reviewer. It reports the client sends a kickoff silently once the voice is ready and the persona greets the reader unprompted, that the button ending the beat does not render until that greeting completes, and that the original step also contradicted wiki/features/personas.md.
  - F3, that the interview runs once but the persona stays editable afterwards, and F4, the two screen titles moved to code voice so their trailing periods read as part of the title: both `done` by the reviewer.
  - F2, a figure for the handover surface: `done` by the reviewer, which added the placeholder and its capture order. Opened as T62 for the capture itself.
  - F5, a one-line fix left after the fix cycle closed: `deferred`, no research needed. Opened as T58.
  - F6, what the next launch shows when the app is closed part way through setup: `blocked`, `needs: research`. The reviewer reports that an unfinished setup leaves the completed flag false and the next launch returns to setup, but that step state initialises at the welcome screen, so the reader-facing outcome is not settled by source. Opened as T54.
  - OBJ1, that no objectives are recorded for this task: `blocked`, `needs: research`. Opened as T55, widened to the corpus because all four reviews this phase reported the same absence.
- Verification: the corpus-wide run recorded on T6 covers this page. The reviewer reported hand-checking the frontmatter against the linter and concluding the page adds no error, which the 0-error run after the reviewers confirms.
- Objective gaps recorded by the reviewer, which derived five objectives because neither the page nor the research artifact records any:
  - Four are taught outright: answering the opening question, choosing temperament, voice, colour and name, putting the first real thing into the second brain, and finishing setup.
  - "Recognise the handover" is taught only after the reviewer's own F1 fix. Recorded so the fix is not read as cosmetic.
  - "Finish setup" carries `needs: research` because of F6, which is T54.
  - `## Where to go next` serves no objective and the reviewer explicitly did not charge it, reporting that the corpus's model how-to carries the same tail.
- Open questions:
  - Which is right about the button that ends the interview, settled: the reviewer reports that SetupFlow is right and the comment is stale, because SetupFlow wires the interview's completion to the second-brain step and it is the second-brain screen's own completion that opens the house. It reports the comment describes an earlier cut, that the author's resolution was correct, and that the code comment is what should change.
  - Is the persona name length limit off by one at each end? The reviewer reports that the page says "under 24 characters", matching the product's own rejection message, but that the regex accepts 24 and rejects a one-character name, so both the product copy and the page are off by one. Opened as T63.
  - Nothing in the corpus links to this page yet. The reviewer reports this as the single thing standing between this work and a reader, and that it costs nothing in the score because the score grades the document. Three sibling tasks in this phase added their links; the index entry is T11's.
  - Does wiki/first-run.md need a row of its own for the reconciliation this task leaves behind? The author reported that the record still carries the beat-two and beat-three procedure this how-to now owns, that wiki/page-types.md:150-154 says a record containing steps points at the how-to instead, and that constraint 3 kept it from touching that page including its `related` pointer to the new page. Opened as T46.
  - Which is right about what the Second brain setup button does? The author reported that the comment at desktop-client/src/components/setup/Interview.tsx:414-416 says the button opens the house while SetupFlow.tsx:350 wires it to the second-brain step, that the two disagree, and that the page follows SetupFlow.
  - Should wiki/first-run.md be renamed once this page exists, so that a decision record and a reader-facing how-to are not both called first run? Still deferred. The research stage reported that it could not confirm the eight-inbound-reference figure the deferral rests on: a grep for `first-run.md` across wiki/ excluding the file itself returned 15 lines across 13 pages, counting both frontmatter `related` entries and body links.
  - Is `wiki/meeting-your-persona.md` the right filename, given the reader's task spans the persona interview and the second-brain setup? The research stage reported evidence for keeping it: the interview screen's own title is "Let's make someone." and becomes "Meet <name>." at the handover, and wiki/_index.md:34 already carries a section by that name. It also reported that the second-brain half is the smaller of the two beats and is largely served by links to wiki/features/second-brain.md.
  - Is the `voice_id: string` declaration on wiki/first-run.md correct? The research stage reported that three source locations declare the parameter as `voice_design`, an array of two to four attributes: backend/harness/valar/tools/tools.yaml:1112-1121, backend/harness/valar/tools/handlers/creation.py:288-296 and backend/harness/valar/gateway/first_run.py:221. Opened as T43, because this task is forbidden from touching that page's schemas and T28 is scoped to a different passage on it.
  - Does the colour swatch mismatch want a tracker row of its own, as T25 did for the planner's WSL warning? The research stage reported that backend/harness/valar/tools/tools.yaml:1125-1126 offers the model a swatch named `Heather` which backend/harness/valar/tools/handlers/creation.py:52-60 no longer accepts, that the comment at creation.py:56-57 records it was deliberately renamed to `Plum` after a live run named a persona after the swatch, and that a model passing `Heather` silently gets `Ember`. Opened as T44.
  - Should the new page carry a pending figure of either setup screen? The research stage reported that `python scripts/lint_wiki.py --figures` lists four pending captures and neither the interview nor the second-brain screen is among them, so nothing in the corpus shows a reader what these screens look like, and that a pending figure is a warning rather than an error.
  - For T11: does the new page go before or after First run under `## Meeting your persona` in wiki/_index.md? The research stage reported that its evidence favours before, because the section's own prose describes the reader's first hour as an arc, wiki/page-types.md:93-94 requires the section order to be the reading order, and a reader arriving from wiki/installing.md wants the procedure rather than the record.
- Orchestrator rulings, so the author is not left choosing:
  - The reachability problem the research stage raised is real and is solved by sequencing rather than by a later phase. It reported that the three pages currently routing a reader to wiki/first-run.md for this walkthrough are exactly T6's, T7's and T9's targets in this same phase, that T8 cannot edit them, and that left unresolved the corpus ships a walkthrough nothing links to. The ruling: T8's author runs first and alone, and the T6, T7 and T9 dispatches each carry the repoint for the page they already own. No page is edited by two tasks, and the new page exists before anything links to it.
  - `wiki/meeting-your-persona.md` keeps its name for this task. The filename question stays open, but a page has to be written before it can be renamed, and the rename is a decision with its own inbound-link cost.
  - Of the eight entries the research stage returned in `affected_docs[]`, exactly one is this author's: the new page, which the stage did not list because it does not exist yet. Seven are repoints on pages other tasks own. Three go to T6, T7 and T9 by the ruling above; wiki/clients/windows.md belongs to T15 and T29; and wiki/developing.md, wiki/features/personas.md and wiki/features/second-brain.md are unowned and open as T45.

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

Notes from the author, on where the delivered page departed from the direction
above:

- The skeleton's heading `## Answer Sulivan's first question` was written as
  `## Answer the question Sulivan opens with`. The author reported that the
  linter's sentence-case check exempts a heading word only when it matches a
  fixed proper-noun set, that the set holds `sulivan` but neither of the two
  normalisations the check applies turns `Sulivan's` into it, and that the
  skeleton's wording would therefore have been a hard error on a page required
  to add none.
- Where the skeleton said the second-brain screen opens by itself, the author
  reported writing it as a step the reader takes, because the source renders a
  Second brain setup button and wires it to that step, and reported the
  disagreement between the button's comment and its wiring as an open question.
- The author reported keeping every `sources` entry the skeleton named and
  adding two, because the step order and the choice-card behaviour come from
  those two files, and reported that the linter checks a `sources` entry only
  for an absolute machine path.

### T9: Give Installing Hearth a how-to spine and absorb the macOS salvage

The page is declared a how-to and contains no numbered step anywhere. Absorbing
the only numbered procedure in the cluster is both what fixes that and what
makes the macOS page's retirement safe.

##### Details

- Agent State: Complete
- Type: Restructure
- Scope: M
- Confidence: High
- Sizing evidence: wiki/installing.md and wiki/install-macos.md, both re-read in full on 2026-09-04 after the Phase A T1 edits. wiki/installing.md now runs 168 lines and contains no numbered list anywhere between line 22 and the end, and its second paragraph at lines 27-28 still calls the page "the narrative version of what happens next". wiki/page-types.md:114-116 requires action-title sections with numbered steps inside them. Its section headings are `## Before you start` (32, with `### macOS` at 38 and `### Windows` at 57), `## The scan and the plan` (67), `## Choosing where it lives` (90), `## The download` (106), `## Proving it works` (120), `## What comes next` (142), `## Platform notes` (149) and `## Updating, briefly` (161); only `## Before you start` and `## Proving it works` are action titles. The salvage passages currently sit at wiki/install-macos.md lines 43-53 (`## Opening it the first time`, the only numbered list in the cluster), 32-34 (the blockquoted decline message), 76-77 (the Backend and Mind-and-voice plan rows), 128-133 (`## Uninstalling`) and 135-155 (`## When something goes wrong`), and at wiki/clients/windows.md lines 155-173 (the install root prose and fenced tree) and 202-205 (the four-tier dictionary paragraph).
- Sources of truth:
  - source: desktop-client/src/components/setup/SetupFlow.tsx:444-547, covers what the plan screen renders on one screen: the model card at 463-480, the "What it will configure" card at 497-503, the install-root field and the single Download button
  - source: desktop-client/src/components/setup/SetupFlow.tsx:113-121 and 391-401, covers where the below-the-floor refusal appears, which is after the scan under the panel title "Hearth cannot run on this machine."
  - source: crates/hearth-probe/src/plan.rs:214-233 and 234, covers the two-element downloads vec and the sum that becomes the plan's download figure
  - source: crates/hearth-probe/src/dict.rs:245-247, covers `smallest()` taking the minimum over tiers by `tier.bytes`, which is what makes the refusal message's smallest-model figure resolvable
  - source: crates/hearth-probe/src/plan.rs:271-275, covers the context-window rounding to a multiple of 1024
  - source: crates/hearth-probe/src/machine.rs:288 and the Apple fixture, covers the backend value being the lowercase string `metal` and `cuda_arch` being absent on Apple Silicon
  - source: crates/hearth-probe/dictionary.yaml:28-36 and 37-54, with desktop-client/src-tauri/src/provision.rs:1-14, covers the inference engine and Python runtime, which are fetched alongside the model and are not in the plan's figure
  - tooling: `python scripts/lint_wiki.py` and `--warnings`, run 2026-09-04, covers the page's current 0 errors and 8 warnings, the long-section rule at scripts/lint_wiki.py:392 and the bold-lead word list at :116
  - contextual: wiki/page-types.md:96-127, covers the how-to shape the reshape targets
  - contextual: wiki/install-macos.md and wiki/clients/windows.md, cover the seven salvage passages this task copies
- Docs:
  - wiki/installing.md, frontmatter and all eight sections: `## Before you start` with `### macOS` and `### Windows`, `## The scan and the plan`, `## Choosing where it lives`, `## The download`, `## Proving it works`, `## What comes next`, `## Platform notes` and `## Updating, briefly`
- Artifacts:
  - Research: tasks/docs/artifacts/T9.research.json
  - Author: tasks/docs/artifacts/T9.author.json, wrote wiki/installing.md
  - Review: tasks/docs/artifacts/T9.review.json, verdict PASS, minor nits open, score 3 to 9
- Review checklist, and where each entry went:
  - F1 the entry point and where builds land, F2 the Windows prerequisites, F3 the missing `home` row in the Windows tree, F4 the negative branch after the spoken check, F5 a triple restatement trimmed, F6 the platform subheading order, F7 the plan-screen capture order, F8 the plan table column labels: all `done` by the reviewer.
  - F9, the step a Windows reader takes to remove the client application: `blocked`, `needs: research`. Opened as T53.
  - F10, a disk-check sentence left in the macOS branch by the reviewer's own F2 edit: `deferred`, no research needed, a one-sentence move. Opened as T59.
- The reviewer's baseline of 3 needs reading in context. It reports that its structural pass came back completely clean, that the declared type matches what every section does, that the page is not two types at once and no required section is missing, and that eight of the nine baseline deductions sat in the Windows half of the prerequisites, one routing gap, and five small defects. It also disclosed scoring one finding at baseline rather than as a regrade discovery, on the ground that a reader meets a gap whether or not an upstream artifact confesses it.
- Verification: the corpus-wide run recorded on T6 covers this page. The reviewer reported it could not run the linter and used the orchestrator's supplied run instead, which the 0-error run after the reviewers confirms.
- Objective gaps recorded by the reviewer, which derived six objectives because neither the page nor the research artifact records any:
  - "Install Hearth on a Windows PC" is not taught. The reviewer reports that the requirements and the shared procedure now land, but there is no Windows first-open step, which is T10, and the uninstall's last step is macOS-only, which is T53.
  - Five are taught: installing on an Apple Silicon Mac, deciding whether the machine can run it (only after F2), recovering a failed install, uninstalling without losing memory and journal (only after F3), and explaining why Hearth chose its plan.
  - The reviewer reports no content on the page serving no objective.
- Salvage landed. All seven passages, as the author reported them:
  1. The macOS first-open procedure: landed as `## Open Hearth for the first time on macOS`, three numbered steps, with the remembered-decision sentence written as a result note after the list rather than as a fourth step.
  2. The below-the-floor message: landed as prose in the `## Before you start` lead, above both platform headings, carrying no fixture figures, per the ruling.
  3. The `Backend` and `Mind and voice` plan rows: landed, and the table now carries all five rows in the ruled order.
  4. The uninstall: landed as `## Uninstall Hearth`, with the copy-out-of-`home/` instruction placed before the deletion step.
  5. The troubleshooting section: landed as `## Work out what went wrong`, last on the page, with all five log filenames and all four failure modes.
  6. The Windows install root prose and tree: landed under `## Check what Hearth installed` as `### Windows`.
  7. The four-tier dictionary paragraph: landed under `### What the plan says`.
- Salvage verified independently. The reviewer checked all seven passages against their sources and reports every one landed intact, with three notes. It reports the refusal prose is better than its source, because it adds the two facts the original message omitted, that the refusal comes after the scan and that the reason is memory rather than disk. It reports correcting the Windows tree by adding a `home` row, on the ground that `crates/hearth-probe/src/defaults.rs:46-48` and `desktop-client/src-tauri/src/config_gen.rs:64` write that directory unconditionally, so the salvaged tree simply omitted it: that is a deliberate correction to an authorised salvage passage. It reports that wiki/clients/windows.md still carries the same omission, which is opened as T60. It also confirms the spine holds, that the page branches in exactly the three places the platforms differ, and that it reads as one guide rather than two stapled together.
- Open questions:
  - Where do a Windows reader's memory and journal live? The author reported that the uninstall section tells a reader to copy anything they want to keep out of `home/`, that the `home/` path comes from the macOS install root tree, and that the absorbed Windows tree lists six entries with no `home` among them. It reported writing the warning as the source states it and leaving the discrepancy visible rather than papering over it.
  - How does a Windows reader remove the client application itself? The author reported that the absorbed material settles only the product side, that no source states the step for the app, and that it therefore named the Trash step for macOS only.
  - Does a Windows reader need the supervised process tree on this page? The author reported that the install root tree landed here as salvage and the process tree is its natural neighbour, that it is outside this task's scope, and that the section points at wiki/clients/windows.md rather than duplicating a fourth copy.
  - Does a real 8 GB Apple Silicon Mac plan 17,408 tokens, or does its reported memory move the figure? The research stage reported that the window is 17,408 only while the machine's reported RAM sits between 8,581,982,713 and 8,594,565,624 bytes, that below that it drops to 16,384 and at or above it rises to 18,432, and that exactly 8 GiB sits inside that band about 7.6 MiB above its floor. It also reported that crates/hearth-probe/src/machine.rs:75 takes the value from an external crate this repository does not vendor, so what a real Mac reports cannot be settled from this tree, and that the figure is right for the shipped fixture.
  - What should be done with the refusal message, given that one of its three figures does not match current source? The research stage reported that wiki/install-macos.md:34 says the smallest model is 2.36 GB while crates/hearth-probe/src/dict.rs:245-247 makes that string print 2.89 GB, because `smallest()` takes the minimum over tiers and never reaches the Q3_K_M build the 2.36 GB names. It further reported that the message's other two figures belong to a Windows machine with no GPU, and that no Apple Silicon Mac produces this message at all. Settled by an orchestrator ruling below.
  - Should the merged plan table add the "Layers on the GPU" row? The research stage reported that the setup screen shows it on every plan, so a five-row table is a selection rather than a transcription, and recommended leaving it out because it carries no reader decision.
  - Who owns removing wiki/installing.md's own references to wiki/install-macos.md? Settled by an orchestrator ruling below.
  - Should the macOS half of the install-root section point at wiki/clients/macos.md rather than repeating the tree? The research stage recommended pointing, because the Windows tree is salvage and has to land here while the macOS tree survives on a page that keeps, so writing it here would create a fourth copy.
  - Is wiki/install-macos.md's right-click-Open passage the only numbered procedure in the cluster, as the salvage table states? The research stage reported it is not: wiki/clients/macos.md carries a four-step numbered install procedure whose first two steps are the same material, on a page the verdict keeps. It also reported that this tracker holds both claims and they disagree, at line 197 and at line 129. T6 removes that copy in this same phase.
- Orchestrator rulings, so the author is not left choosing:
  - The plan table takes all five rows in wiki/install-macos.md's order: Model, Context window, Backend, Mind and voice, Download. The research stage settled this against the setup screen, which renders all five. `Layers on the GPU` and `CUDA architecture` stay out, on the stage's recommendation and because the second never appears on Apple Silicon at all. Note for the author: the screen prints the backend value raw and lowercase, while both pages print it capitalised.
  - The four-versus-two download question is settled and closed. The figure covers the two items it sums, and the page already says so correctly after T1. The reshape does not reopen that sentence.
  - The refusal message is absorbed as prose, not as a verbatim blockquote. A quotation presented as the product's own words that contains a figure the product does not print is a fabricated quote, and the passage's other two figures come from a Windows machine with no GPU rather than from any Mac. Write what the refusal tells a reader, which is that Hearth declines, that the reason is memory rather than disk, and that the message names what is left after the voice, speech recognition and headroom against the smallest model it could use. Do not print the fixture figures, and do not place it under a macOS heading. The salvage row lands as prose, and the deviation is recorded.
  - T9 owns wiki/installing.md's two prose references to wiki/install-macos.md and the `related` frontmatter entry naming it, repointing or removing each. The `sources` entry stays as provenance, matching the ruling on T2 and T6.
  - The eleven-section spine in the research artifact's `notes`, under "RECOMMENDED SPINE", is accepted as direction. It branches by platform in three places only and writes the shared bulk once, which is the architecture the consolidation verdict ratified.
  - Do not write or plan a Windows first-open procedure. The research stage confirmed that nothing in the tree or the corpus establishes what Windows shows on first open. T10 adds it when the fact exists.

##### Draft

Reshape the page to the how-to spine, keeping its platform parameterization:
`### macOS` and `### Windows` already exist under `## Before you start`.

Absorb from `wiki/install-macos.md`, preserving each passage rather than
paraphrasing it away: the right-click-Open procedure at lines 43-53, which is
the only numbered procedure in the cluster and whose existence this page
currently only mentions at lines 151-153; the verbatim decline message at lines
32-34; the Backend and Mind-and-voice plan rows at lines 76-77; the uninstall at
lines 128-133, of which this page has only the one-line version at line 104; and
the troubleshooting section at lines 135-155, with its log filenames and four
named failure modes.

Absorb from `wiki/clients/windows.md` the install root prose and fenced tree at
lines 155-168, because this page has no Windows equivalent, and the four-tier
dictionary description at lines 202-205, because lines 77-86 here describe only
two machine sizes.

Every line number above was verified on 2026-09-04, after the Phase A edits.
Locate each passage by its content rather than its line, because the author
stage moves text and the numbers shift underneath it.

Notes from the author, on where the delivered change departed from the direction
above:

- The author reported merging the spine's two platform headings for the folder
  defaults into one heading, because the two defaults are two sentences sharing
  one rule and two one-sentence headings would fragment the section.
- The author reported retitling the spine's `## When something goes wrong` to an
  action title, because the deliverable spec requires action titles and the
  page-type rules put noun labels outside reference pages.
- The author reported writing the `Backend` row value in lowercase code voice
  rather than capitalised, because the finding that the screen prints the raw
  lowercase string is graded verified.
- The author reported not carrying forward the sentence calling this the deepest
  install page Hearth has, measured on a real 8 GB M2 Air, because it describes
  a retiring page rather than the product, and reported that the real-machine
  provenance survives in the macOS requirements sentence.
- The author reported not carrying forward the announcement that a dedicated
  Windows install guide does not exist yet, because this page is now that guide,
  and reported preserving the useful half of the paragraph as a pointer to
  Hearth on Windows for the process tree and ports.
- The author reported not importing the one-at-a-time residency tradeoff from
  wiki/clients/windows.md, because it is not among the seven authorised passages
  and no verified claim carries that behaviour.
- The author reported writing the absorbed failure modes as a term list rather
  than as bolded-lead paragraphs, so that the two bold-lead warnings on the
  source page were not imported, and reported that the three sections expected
  to clear 200 words all carry subheadings.

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
- Sizing evidence: wiki/installing.md. The original read located `### Windows` at lines 48-56; after T9 that range is inside `### macOS`, and the T12 research stage re-measured on 2026-09-04: the page now carries two `### Windows` sections, requirements and video-memory bands at lines 69-89 and the install-root tree at lines 217-238, and no numbered Windows step anywhere in its 295 lines. The substantive finding holds at the new lines. wiki/install-macos.md:17-19 states that everything on the macOS page was measured on the machine it describes, and no equivalent Windows record exists in the corpus. Sized L because the page it lands on is the corpus's install spine and the content is net-new rather than moved.
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

- Agent State: Complete
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: wiki/_index.md, re-read in full on the Phase C run of 2026-09-04. Line 31 lists Installing on macOS under `## Getting started`, alongside line 29 Getting started, line 30 Installing Hearth and line 32 Updating an install. The section prose runs at lines 24-27. `## Meeting your persona` at line 34 has prose at 36-39 and lists First run at 41, Personas at 42, The persona face at 43 and Voice at 44; wiki/meeting-your-persona.md exists on disk and appears nowhere in this file. Line 7 names getting-started.md in the frontmatter `related` list.
- Sources of truth:
  - source: scripts/publish_wiki.py:172-195, covers that `sidebar()` builds the left rail only from `## ` headings and `- [text](target)` list items inside wiki/_index.md, so index membership decides whether a published page has a rail entry
  - source: scripts/publish_wiki.py:46, 63-76, 198-210, covers that `collect()` publishes every wiki/**/*.md outside wiki/raw/ regardless of index membership, so a page missing from the index still publishes
  - source: scripts/publish_wiki.py:189-194, covers that the rail opens with a hardcoded Home entry and closes with a hardcoded What is not here entry, both outside the section loop
  - source: scripts/publish_wiki.py:163-166, covers that `render()` suppresses the See also block for _index.md, so this page's own frontmatter `related` list never reaches a reader
  - source: scripts/lint_wiki.py:256-408, covers the complete set of checks, and establishes that there is no index-membership check and no once-and-only-once check
  - source: scripts/lint_wiki.py:31-32, 42-46, 443-446, covers that wiki/raw/ is excluded from linting and that 29 pages are the checked set
  - source: crates/hearth-probe/src/plan.rs:79-91, 155, 165-166, 274-306, covers that the install refusal is computed from a memory budget against the smallest tier, with no literal 8 GB floor constant, which is what the index's machine sentence has to hold against
  - canonical: wiki/page-types.md:67-94, covers the landing shape: routing only, prose under each heading before its links, human titles as link text, every published page exactly once in exactly one section, and section order as the reading order
  - canonical: wiki/page-types.md:36-46, 254-266, covers the type-to-reader-verb table, which is how a decision record is distinguished from a how-to
  - contextual: tasks/docs/tracker.md:208-210, covers the ratified placement of wiki/meeting-your-persona.md as the first entry in the section it takes its name from
  - contextual: wiki/meeting-your-persona.md:1-29, 102-122, 124-168, 181-193, covers what the new page is: `type: how-to`, the interview, the handover, the second-brain beat, and its closing pointer naming First run as the design record
  - contextual: wiki/first-run.md:1-34, covers `type: decision-record` at line 4 and an abstract written around a seventeen-screen mockup
  - contextual: wiki/installing.md:23-32, 47-89, 240-260, covers what the install how-to carries after T9, including a by-hand update procedure
  - contextual: wiki/getting-started.md:1-31, 95-102, covers `type: concept` after T7 and its own route to Meeting your persona
  - contextual: wiki/updates.md:1-17, covers `type: concept` and an abstract stating that nothing in it is built yet
  - contextual: wiki/whats-not-here.md:1-25, covers the corpus's second landing page, reached from wiki/_index.md:95 in prose rather than from a section list
- Docs:
  - wiki/_index.md, `## Getting started` (the prose at lines 24-27 and the link at line 31) and `## Meeting your persona` (the prose at lines 36-39 and the link list at lines 41-44)
- Artifacts:
  - Research: tasks/docs/artifacts/T11.research.json
  - Author: tasks/docs/artifacts/T11.author.json, wrote wiki/_index.md
  - Review: tasks/docs/artifacts/T11.review.json, verdict PASS, score 7 to 9
- Review checklist, and where each entry went:
  - F1 the page contradicted itself about where a product reader stops reading, F2 the update clause routed a reader to the page that says updating is not built while the working by-hand steps sit elsewhere, F3 a stale `last_reviewed`: all three `done` by the reviewer.
  - C1 `deferred`, `needs: restructure`, owner orchestrator: whether wiki/first-run.md, a decision record, belongs in the reader-facing `## Meeting your persona` section. No owner existed. Opened as T72. The reviewer adds that the research stage marked the underlying question `unverifiable`, because no page states which page types may sit in which index section, so it needs a rule before it needs an edit.
  - C2 `deferred`, owner orchestrator: wiki/page-types.md:93 and scripts/publish_wiki.py:189-194 disagree, because the rule says every published page appears exactly once in exactly one section while the publisher hardcodes the What is not here rail entry outside the section loop, so obeying the rule literally yields two rail entries. No owner existed. Opened as T73.
- Objective gaps recorded by the reviewer, which derived four because neither the page nor the research artifact records any:
  - "Find the page that answers your question about Hearth" is taught only in part. The reviewer reports 27 of the 28 other published pages reachable, and wiki/install-macos.md unreachable, since it still publishes with no index entry and therefore no rail entry. Owner T16. This is the ratified transient rather than a new task, and it closes when T16 lands.
  - The other three objectives are taught, all at remember or understand, which the reviewer records as the correct level for a landing page, so there is no wrong-type signal.
  - The reviewer reports no content on the page serving no objective.
- Open questions:
  - "Should the `## Meeting your persona` prose at wiki/_index.md:36-39 be rewritten as a four-part arc that names the second brain, or held at three parts with wiki/meeting-your-persona.md introduced separately? wiki/first-run.md:24-29 makes the second brain the third beat and wiki/meeting-your-persona.md devotes two of its seven sections to it (lines 124 and 146), but wiki/_index.md:53 already lists The second brain under `## Living with a house`, and wiki/page-types.md:93 forbids a page appearing twice."
  - "Does wiki/first-run.md still belong in the reader-facing `## Meeting your persona` section once the how-to sits above it? It declares `type: decision-record` at line 4 and its abstract at lines 15-17 is written around a seventeen-screen mockup, while wiki/_index.md:84-86 describes `## Looking under the hood` as the engineering record and says a reader who came to use Hearth can stop above that line. Moving it changes the reading order, which the task statement does not ask for, and tasks/docs/tracker.md:208-210 assumes it stays."
  - "If the `## Getting started` prose at wiki/_index.md:24-27 is restated for three pages, what does it say wiki/updates.md is for? updates.md:15-17 states nothing in it is built yet, while wiki/installing.md:247-260 now carries the by-hand update procedure that the index prose clause \"how an existing install becomes a newer one\" currently sends a reader to updates.md for."
  - "Is the transient orphan acceptable? Between T11 landing and T16 running, wiki/install-macos.md still publishes (scripts/publish_wiki.py:63-76) with no index entry, no rail entry, and, once T12, T13, T64, T14 and T65 also land, no inbound reference at all except the three `sources` entries the linter never resolves. tasks/docs/tracker.md:271 separates these into Phase C and Phase E deliberately, so the question is whether the two should land in one change rather than whether the ordering is wrong."
  - "Should wiki/meeting-your-persona.md be added to the index's frontmatter `related` list at wiki/_index.md:6-9? It would change nothing a reader sees, because scripts/publish_wiki.py:163-166 suppresses the See also block on _index.md, but the list is the only other place in the file where the index names a page, and it currently names getting-started.md, developing.md and whats-not-here.md."
  - Where should a reader who wants a newer build today be sent? The author reported that the index now states honestly that updating in place is not built, and does not route the reader to the by-hand steps, because the landing shape holds each section to one or two sentences and the paragraph had four words of headroom under the 60-word limit. The author reported that the reconciliation belongs on a page this task could not edit. Opened as T67.
  - Does anything enforce the rule that every published page appears exactly once in exactly one index section? The author reported that scripts/lint_wiki.py has no index-membership check and no once-and-only-once check, and that this is how wiki/meeting-your-persona.md came to publish with no rail entry and produce zero findings. The author reported fixing the one instance rather than the class. Opened as T70.
  - Was the linter run against this edit? The author reported that its tool set is Read, Grep, Write and Edit with no shell, that it hand-counted both edited paragraphs at 56 and 57 words against a 60-word limit, and that a hand check is not a linter run. See the Phase C verification note.
- Orchestrator rulings, so the author is not left choosing:
  - Placement is settled: wiki/meeting-your-persona.md is the first entry in `## Meeting your persona`, ahead of First run. That is what tasks/docs/tracker.md:208-210 ratified, and the corpus agrees independently, since wiki/installing.md and wiki/getting-started.md both route a reader to the how-to rather than to the record.
  - Hold the section prose to the arc it already describes and introduce the walkthrough inside it. Do not add a link to The second brain: it is listed under `## Living with a house` and wiki/page-types.md:93 forbids a page appearing twice. Naming the second brain as a beat in prose is not a link and is allowed.
  - wiki/first-run.md stays where it is. Moving a page between sections changes the reading order, which is a restructure and is not what this task is. The question stays open above.
  - The transient orphan is acceptable and is the design. Phase C and Phase E are separate because integrity rule 9 requires the salvage and the redirects to land before the irreversible step, and a page that publishes unreferenced for one phase is a smaller cost than a retirement that races its own redirects.
  - Do not touch the frontmatter `related` list. The See also block is suppressed on this page, so the entry would change nothing a reader sees, and this task is about the navigation surface.
  - Describe wiki/updates.md by what that page currently says it is. The overlap between it and wiki/installing.md's by-hand update procedure is real and is opened as T67 rather than settled inside a prose rewrite here.

##### Draft

Remove line 31. Line 29 stays, because `wiki/getting-started.md` keeps under the
revised verdict, and the prose under `## Getting started` at lines 24-27 should
say what each of the three remaining pages is for now that the set has changed.
The research stage reports that this prose already names three coverage clauses
against four links, and that `install-macos.md` is the link it never accounted
for, so the removal brings the prose and the list into agreement rather than
forcing a rewrite.

Add `wiki/meeting-your-persona.md` to `## Meeting your persona` as the first
entry. `wiki/page-types.md:82-86` requires prose under each heading before its
links, and `wiki/page-types.md:93-94` requires every published page to appear
exactly once and the section order to be the reading order.

This is the only navigation surface: `scripts/publish_wiki.py:172-195` builds
the sidebar rail from this file alone, which is why a page absent from it
publishes with no rail entry.

Runs after T7 and T8 so the pages it names exist in their final shape.

Notes from the author, on where the delivered change departed from the direction
above:

- The author reported rewriting the third `## Getting started` clause rather than
  leaving the prose alone. The reason given was that the clause was the first half
  of wiki/updates.md's own abstract with its second half dropped, so it promised a
  route that page cannot give, and that the direction asked for the page to be
  described by what it currently says it is.
- The author reported recasting the second `## Meeting your persona` sentence
  rather than appending a clause to it. The reason given was that the paragraph
  already ran 57 words against a 60-word limit, so a fifth role could not be
  appended without introducing a warning on a page that carries none.

### T12: Restate the Windows gap as steps inside Installing Hearth

The register of unwritten pages describes the missing Windows work as a page
mirroring Installing on macOS. Under the ratified architecture the missing work
is a section, and the page it would mirror will not exist.

##### Details

- Agent State: Complete
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: wiki/whats-not-here.md, re-read in full on the Phase C run of 2026-09-04. Lines 23-25 still read "**Installing on Windows.** [Installing on macOS](install-macos.md) is the shape it will take. What differs is the numbers and the CUDA voice build. Until it exists, [Hearth on Windows](clients/windows.md) covers what the app does." The page is `type: landing` at line 4, which is where this task's `Shape` comes from, and it is the target: wiki/installing.md is `type: how-to` and is not this task's page. A corpus grep on the Phase C run returns this as the only surviving Windows-guide announcement in the published wiki.
- Sources of truth:
  - source: crates/hearth-probe/dictionary.yaml:91-102, covers which platforms run which voice engine. Line 102 reads `cpp_platforms: [macos, windows]`, and the comment at 95-101 records that Windows measured omnivoice.cpp on CUDA on 2026-08-08 and moved to it, leaving only Linux on the torch engine
  - source: crates/hearth-probe/src/dict.rs:44-64, covers `Voice::uses_cpp(os)` matching the running OS against `cpp_platforms`
  - source: desktop-client/src-tauri/src/provision.rs:234-237 and 469-500, covers what an install actually does about the voice: lines 476-479 short-circuit the whole venv, torch and engine chain on a cpp platform, and lines 490-496 reach `torch_index_cuda` only on the non-cpp path
  - source: scripts/build_omnivoice.sh:10-12 and 51-55, covers that `-DGGML_CUDA=ON` on Windows is a build-machine cmake flag, that the build machine produces the binary and pack_backend.sh ships it, and that nothing is cloned or compiled on a user's machine
  - source: crates/hearth-probe/dictionary.yaml:37-54, covers the CUDA material a Windows install does fetch: `windows_cuda` at 47-51 lists the llama.cpp b10358 CUDA 12.4 build and the cudart redistributable, which belong to the inference engine rather than to the voice
  - source: scripts/lint_wiki.py:288-297 and 356-372, covers what the linter owns for this edit: `related` entries must resolve, body links must resolve, and any link matching a raw/ path is an error
  - source: scripts/lint_wiki.py:211-216 and 380-386, covers that `is_prose` excludes numbered list items, so entry 1 is exempt from the long-paragraph and bold-lead warnings however it is rewritten
  - canonical: wiki/page-types.md:67-94, covers the landing shape this page keeps, including the rule at 91-92 that a landing page carries no procedures and nothing a reader can act on
  - contextual: wiki/installing.md:69-89 and 217-238, covers what the corpus currently says about installing on Windows and what its two `### Windows` sections contain
  - contextual: wiki/clients/windows.md:27-29 and 241-246, covers whether entry 1's fallback pointer still holds: the page routes the install to ../installing.md twice
- Docs:
  - wiki/whats-not-here.md, entry 1 under `## Pages that are not written yet` at lines 23-25
- Artifacts:
  - Research: tasks/docs/artifacts/T12.research.json
  - Author: tasks/docs/artifacts/T12.author.json, wrote wiki/whats-not-here.md
  - Review: tasks/docs/artifacts/T12.review.json, verdict NEEDS_WORK, score 6 to 7
- Review checklist, and where each entry went:
  - F3 the first section lacked the orienting sentence its type requires, F4 the causal chain in the rewritten entry: both `done` by the reviewer.
  - F1 `deferred`, `needs: restructure`, no owner existed: the reviewer reports that `## Material that never publishes` spends four of its six sentences teaching a contributor how to cite a raw/ source and what the linter rejects, on a page whose type forbids anything a reader can act on, and that it links wiki/developing.md where that material already lives. Opened as T74.
  - F2 `deferred`, `needs: restructure`, no owner existed: both H2s are noun headings where the type asks for gerunds, and the abstract needs aligning. Opened as T74 alongside F1, since both are the same page's shape.
  - The reviewer confirms no entry is `blocked`, so nothing on this page needs a fact research has to establish.
- Objective gaps recorded by the reviewer, which derived four because neither the page nor the research artifact records any:
  - Three objectives are taught and sit at remember and understand, which the reviewer records as the levels a landing page takes, so nothing supports a wrong-type finding.
  - The reviewer reports content serving no objective at lines 40-45, which teaches a contributor at apply level on a page whose type caps it at understand, and which wiki/developing.md already owns. Recorded as F1 and carried to T74 rather than charged twice.
  - The reviewer separately reports that this page records no objectives at all and recommends giving it some, which is the same finding T55 already owns corpus-wide.
- Independent verification the reviewer performed, recorded because it is what the task turned on: the reviewer confirmed at source that the removed CUDA voice claim was genuinely false and is genuinely gone, citing crates/hearth-probe/dictionary.yaml:102 and desktop-client/src-tauri/src/provision.rs:476-479, and confirmed that wiki/installing.md:69-89 does already state the Windows requirements the rewritten entry credits it with.
- Open questions:
  - "Does the heading `## Pages that are not written yet` at wiki/whats-not-here.md:21, and the abstract at line 14 that also says 'pages', still fit a list whose first item is now a missing section inside an existing page and whose second item is still a missing page? Entry 2 at lines 26-28 genuinely describes a page, so the heading cannot simply be reworded to 'sections'. The author has to choose between a wider heading that covers both, and leaving the heading as it stands and letting entry 1 carry the distinction in its own words."
  - "Should the rewritten entry state why the Windows steps are missing, given that the reason is a recorded standard rather than an oversight? tasks/docs/tracker.md:1383 blocks T10 because nobody has performed and recorded a Windows install end to end, and wiki/install-macos.md:17-19 is the standard that makes an estimate unpublishable. Naming that reason tells a reader the gap is deliberate, which is what line 17 of this page promises the register is for; not naming it keeps the entry to one screen, which is what wiki/page-types.md:69-70 asks of a landing page."
  - "What replaces 'the CUDA voice build' in the entry's statement of what differs, if anything does? Source contradicts the current clause: crates/hearth-probe/dictionary.yaml:102 puts Windows on omnivoice.cpp alongside macOS, and desktop-client/src-tauri/src/provision.rs:476-479 skips the torch and CUDA chain entirely on both. The genuine install-time difference in the same area is the inference engine, where crates/hearth-probe/dictionary.yaml:47-51 fetches an accelerator-matched CUDA or Vulkan build against a single Metal tarball at 44-46. Whether a landing entry should name any technical difference at all, rather than simply pointing at the page where the steps will land, is a judgement wiki/page-types.md:91-92 bears on and does not settle."
  - "Who owns correcting the `envs\\voice\\` row on the Windows install-root trees? wiki/installing.md:226 and wiki/clients/windows.md:165 both describe it as the voice engine's own environment installed at first run, and desktop-client/src-tauri/src/provision.rs:476-479 never creates it on Windows because crates/hearth-probe/dictionary.yaml:102 puts windows in `cpp_platforms`. This is not T12's page and no row in tasks/docs/tracker.md appears to own it; it likely wants a new row against wiki/installing.md and wiki/clients/windows.md."
  - "Does the tracker's T10 sizing evidence want correcting before T10 runs? tasks/docs/tracker.md:1377 locates `### Windows` at wiki/installing.md lines 48-56, and after T9 that range is inside `### macOS`; the Windows section is now 69-89. The substantive finding, that it carries no numbered step, still holds at the new lines. This stage does not write the tracker."
  - Where should the corpus state what a Windows install actually differs by at install time? The author reported that dropping the false CUDA voice clause leaves the page naming no difference at all, that the genuine difference is the accelerator-matched inference engine download against the single macOS Metal tarball, and that it wants a home on a page this task could not edit. Opened as T69.
  - Does any page state which voice engine runs on which platform? The author reported that none does, and that removing the wrong clause corrected this page without stating the true fact anywhere. Opened as T69.
  - Was the linter run against this edit? The author reported that its tool set is Read, Grep, Write and Edit with no shell, that it could not run the linter and makes no linter claim, and that it checked the rules the edit touches by reading the script instead. See the Phase C verification note.
- Orchestrator rulings, so the author is not left choosing:
  - Leave the heading at line 21 and the abstract at line 14 as they stand, and let entry 1 carry the distinction in its own words. Rewriting a landing page's heading to cover two kinds of gap is a restructure, and this is a corrections task; entry 2 is still a page, so the heading is not wrong, only less precise than it was.
  - State the reason in one clause. Line 17 of this page promises the register exists so a reader knows a gap is known rather than overlooked, and a gap that is deliberate reads differently from one that is neglect. One clause keeps the entry inside the screen the landing shape asks for.
  - Drop the "CUDA voice build" clause rather than replacing it. It is contradicted by source, so it cannot stay, and the inference-engine difference that would replace it is detail a reader can act on, which wiki/page-types.md:91-92 keeps off a landing page. The entry routes to the page where the steps will land; it does not teach the difference.
  - The `envs\\voice\\` row is not T12's and is opened as T66 against both pages that carry it.
  - The T10 sizing evidence is corrected by the orchestrator on this run. The researcher was right to flag it and right not to write it.

##### Draft

Rewrite entry 1 so the gap is the Windows steps inside
[Installing Hearth](installing.md), not a separate page, and so it stops naming
`install-macos.md` as the shape. This is the entry that closes when T10 lands.

It is now the only place in the published corpus that announces this gap at all.
An earlier version of this draft said T2 and T4 would remove the other three
announcements; they did, in Phases A and B, and a corpus grep on 2026-09-04
confirms none survives. So the entry carries the whole weight of telling a
reader the gap is known.

Notes from the author: it reported no departure from the direction. The edit is
confined to entry 1, and the author reported that the heading at line 21, the
abstract at line 14, entry 2, the `## Material that never publishes` section and
the frontmatter are byte-identical to how they were found, as the rulings above
required.

### T13: Redirect the Installing on macOS link on Updating an install

The page links into `install-macos.md` in prose and names it in frontmatter.
Both break when that page is retired.

##### Details

- Agent State: Complete
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: wiki/updates.md, lines 1-20 and 95-119 read on the Phase C run of 2026-09-04. Frontmatter line 4 reads `type: concept`, line 8 lists `install-macos.md` under `related` beside backend/build-pipeline.md at 7 and _index.md at 9, and line 11 lists `wiki/raw/macos-status.md` under `sources`, which is a live instance of the raw-provenance convention. Line 105, under `## The decision underneath: signing`, reads "Hearth is not signed. That is why [`install-macos.md`](install-macos.md) tells people to right-click and choose Open on first launch". Lines 110-118 refer twice more to "the install guide" without linking it.
- Sources of truth:
  - source: scripts/lint_wiki.py:284-297, covers how the linter treats the two references differently. `sources` entries at 284-286 are tested only against an absolute path and are never resolved to a file; `related` entries at 290-297 are resolved relative to the page's own directory and reported as `dead-related` when the file does not exist
  - source: scripts/lint_wiki.py:357-372, covers body-link resolution: the target is split on the hash and only the path half is checked, so an anchor is never validated, and a missing file is a `dead-link` error
  - source: scripts/publish_wiki.py:79-92, 117-135, covers what `related` becomes for a reader: `see_also()` renders a See also block whose link label is the destination page's own frontmatter title, not the filename or anything the author writes
  - canonical: wiki/installing.md:91-103, covers the salvaged right-click-and-Open procedure and the heading it landed under, `## Open Hearth for the first time on macOS`
  - canonical: wiki/style-guide.md:160-165, covers the link-text rule: `## Write link text as human titles` names a backticked filename as the wrong form and a human title as the right one
  - canonical: wiki/page-types.md:138-155, covers the concept shape this page declares at line 4, whose item 5 is links to the how-to pages that act on it
  - contextual: wiki/install-macos.md:43-53, covers the source passage the salvage came from, for comparison against its destination
  - contextual: tasks/docs/tracker.md:35, 1457-1480, 1610-1626, covers the task's recorded state and the ownership of wiki/updates.md:8 and :105
- Docs:
  - wiki/updates.md, the frontmatter `related` entry at line 8 and the prose link at line 105 under `## The decision underneath: signing`
- Artifacts:
  - Research: tasks/docs/artifacts/T13.research.json
  - Author: tasks/docs/artifacts/T13.author.json, wrote wiki/updates.md
  - Review: tasks/docs/artifacts/T13.review.json, verdict FAIL, score 3 to 5
- Review checklist, and where each entry went:
  - F3 the page addressed the reader in the third person, F7 a first-person heading, F5 a British spelling: all three `done` by the reviewer. The reviewer reports F3 mattered most, because the page was the only top-level article in wiki/ that never said "you" and was doing it in the paragraph about the memory an update must not touch.
  - F1 `deferred`, `needs: restructure`, owner T67. Confirmed that T67 exists; its statement is widened on this run to cover the finding, because the reviewer reports the register mixture is three-way rather than two-way, with `## The order the work should land in` being backlog material in a third register again.
  - F4 `deferred`, `needs: restructure`, assigned by the reviewer to T67 but flagged as wanting its own row because the fix edits a different page. Opened as T76 against wiki/backend/build-pipeline.md.
  - F2 `blocked`, `needs: research`, no owner existed. Opened as T75, carrying the reviewer's result as the question research must answer.
  - F6 `blocked`, owner orchestrator: whether an edit bumps `last_reviewed`. No owner existed. Opened as T77.
  - The reviewer records dropping a candidate `noun-heading` finding after calibration, because the model concept pages named in wiki/page-types.md all use the same declarative style, so charging it would have invented a rule.
- Objective gaps recorded by the reviewer, which derived five because neither the page nor the research artifact records any:
  - "Justify whether Hearth should be signed" is not taught: the reviewer reports the section states cost and consequences and reaches no conclusion. It also reports that an evaluate-level objective implies a decision record rather than a concept page, which is evidence for T67 rather than a separate task.
  - "Sequence the update work in build order" is taught, and the reviewer records that as the defect rather than the success, because no page type carries a create-level objective and CLAUDE.md puts the backlog in tasks/. Carried to T67.
  - The reviewer reports `## What this closes elsewhere` as content serving no objective, three of whose four bullets answer questions about other pages. Recorded as F4 and carried to T76.
  - Three objectives are taught and match the concept type.
- Independent verification the reviewer performed: it confirmed at source that line 8 now reads `installing.md`, that line 105 links Installing Hearth with the destination's own frontmatter title as link text, that wiki/installing.md:91 carries the salvaged heading with the steps at 96-98, and that a grep finds no `install-macos` occurrence surviving on the page.
- Open questions:
  - "Does the GitHub wiki lower macOS to macos when it slugs `## Open Hearth for the first time on macOS`? No in-corpus anchor targets a mixed-case heading and this repository generates no slugs, so the exact fragment is the one detail the evidence here cannot settle. An unanchored link to installing.md is correct either way and is the safe fallback if the orchestrator will not accept an unverified fragment."
  - "Should the two unlinked mentions inside the signing section, at wiki/updates.md:111 and :118, and the two outside it, at :120 and :146, be left as generic prose? They all refer to wiki/installing.md, and the corpus links it by title elsewhere. Leaving them alone is defensible under one link per destination per section; the orchestrator owns whether that is the house rule, because no page in wiki/ states one."
  - "wiki/updates.md:113 and :153 repeat the same link-text violation as line 105, pointing at backend/build-pipeline.md. They are outside this task's statement, which bounds the work to the install-macos references. Does the orchestrator want a row for them, or should the author fix all three while the page is open?"
  - Does an edit of this size warrant bumping `last_reviewed`? The author reported that this page still carries 2026-09-03 while wiki/installing.md carries 2026-09-04, and declined to change it. The reviewer independently raised the same question as a blocked checklist entry and reported that the corpus already behaves as though a rule exists while nothing states one. Opened as T77.
  - Was the linter run against this edit? The author reported that its tool set is Read, Grep, Write and Edit with no shell, that it did not run the linter and does not claim its result, and that everything it asserts about link resolution comes from reading the two files and the linter source. See the Phase C verification note.
- Orchestrator rulings, so the author is not left choosing:
  - Link without a fragment. The researcher established that scripts/lint_wiki.py:370-371 never validates an anchor, so a wrong fragment passes the linter and fails only for a reader, and nothing in this repository settles how the destination heading is slugged. An unanchored link to wiki/installing.md is correct either way.
  - Leave the four unlinked mentions of "the install guide" at lines 111, 118, 120 and 146 as generic prose. This task redirects the two references that break; adding four links a reader did not ask for is not a correction.
  - Fix the link text at line 105 as part of the swap, because the researcher established that a backticked filename is the form wiki/style-guide.md:162 names as wrong, and the replacement has to take some shape. Leave lines 113 and 153 alone: they point at a different destination and are outside this task's statement. They are opened as T68.

##### Draft

Point line 105 and the frontmatter entry at `wiki/installing.md`, where the
right-click-Open step lands under T9. The research stage verified that landing at
source rather than taking it on report: `wiki/installing.md:91` carries
`## Open Hearth for the first time on macOS`, with the steps at 96-98 matching
the passage they came from. The sentence's claim about signing is not in
question; only its referent is.

The frontmatter entry publishes as a See also link labelled from the destination
page's own `title`, so it will read "Installing Hearth" whatever the entry says.

The prose link takes a human title rather than a backticked filename, per
`wiki/style-guide.md:160-165`.

### T14: Drop install-macos.md from the Building a Hearth release frontmatter

A single frontmatter entry naming a page that is being retired.

##### Details

- Agent State: Complete
- Type: Fix
- Scope: XS
- Confidence: High
- Sizing evidence: wiki/releasing.md lines 1-20, read on the Phase C run of 2026-09-04. Line 9 lists `install-macos.md` in the frontmatter `related` list, and line 10 already lists `installing.md`, so the change is a removal with no replacement to add. A corpus grep for `install-macos` on the same run returns no other match in this file, so the page's prose does not reference it. Line 4 reads `type: how-to`, which is where the Shape comes from.
- Sources of truth: (none, XS route runs no research)
- Docs: (none, XS route runs no research)
- Artifacts:
  - Author: tasks/docs/artifacts/T14.author.json, wrote wiki/releasing.md
- Open questions:
  - Does scripts/lint_wiki.py report no `dead-related` finding for wiki/releasing.md after this edit? The author reported that its tool set is Read, Grep, Write and Edit with no shell, that it could not run the linter, and that it verified the removal by reading the file and by grep only. See the Phase C verification note.
- Author's reported findings, recorded because they bear on T16: a case-sensitive grep of wiki/releasing.md returned line 9 as the only match for `install-macos`, and the author reported that the two `macos-package-handoff` paths in `sources` at lines 16 and 17 name a different file and were left alone. The author reported that the History paragraph's phrase about a staged source named in this page's frontmatter points at those `sources` entries rather than at the removed `related` entry, so the prose stays accurate.

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

### T16: Demote Installing on macOS to wiki/raw/ and repoint its three sources citations

The fold verdict, executed. The page moves to `wiki/raw/install-macos.md` and
the three pages that cite it as provenance are repointed in the same change.
This is the one irreversible step in the plan and it is held until the salvage
has landed.

##### Details

- Agent State: Backlog
- Type: Consolidate
- Scope: S
- Confidence: High
- Sizing evidence: wiki/install-macos.md, read in full on the run that wrote this row. Six passages live nowhere else and are listed in the salvage table above: lines 32-34, 43-53, 76-77, 118-126, 128-133 and 135-155. The inbound reference list in that sizing evidence is superseded by the Phase C measurement recorded under the Draft below, taken on 2026-09-04.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T16.research.json
- Open questions:
  - Does the demoted file need its frontmatter adjusted on the way into `wiki/raw/`? Nothing under `wiki/raw/` is linted, per scripts/lint_wiki.py:31-32 and 42-43, so the question is about what a later reader of the source needs rather than about a rule.
  - "wiki/install-macos.md:34 carries a contradicted figure, 2.36 GB where crates/hearth-probe/src/dict.rs:245-247 and crates/hearth-probe/dictionary.yaml:138 produce 2.89 GB, and under T16 that page moves to wiki/raw/ with the wrong figure intact." Raised by the T65 research stage. It bears on this task in two ways: the demoted file is the corpus's only verbatim copy of the shipped refusal wording, and if its figures are wrong it is not a trustworthy archive of that message. The T65 stage also reports that the blockquote's figures come from the `tiny` fixture, which crates/hearth-probe/src/machine.rs:322-331 defines as a Windows machine with no GPU and no unified memory, on a page titled Installing on macOS. Decide before the move whether to correct the figure, annotate it, or demote it as found and let the file record what the page said.

##### The demote-or-delete decision, and why

**Decision: demote to `wiki/raw/install-macos.md`, and repoint the three
`sources` citations at the new path in the same change.** Recorded by the
orchestrator on the Phase C run of 2026-09-04, which is the stage that owns this
call under integrity rule 9.

Three published pages cite this page in frontmatter `sources` as where their
content came from: wiki/clients/macos.md:11, wiki/clients/windows.md:13 and
wiki/installing.md:15. That claim is true, and the Phase B run made it truer:
wiki/installing.md absorbed seven salvaged passages from this page under T9 and
wiki/clients/macos.md two under T6. Deleting the page makes all three citations
name a file that does not exist, which discards a genuine record of where the
corpus's install material came from.

The corpus already has the mechanism for exactly this. `wiki/whats-not-here.md`
lines 32-33 name "staged sources and decommissioned documents" as what `raw/`
holds, and lines 34-37 state that an article compiled from one names it in
`sources` and never links to it. The linter enforces that split rather than
merely allowing it: `scripts/lint_wiki.py` lines 282-286 check a `sources` entry
only for an absolute machine path and never resolve it, and the comment at lines
83-88 states that naming a `raw/` document in `sources` "is the convention
working as designed", while lines 293-294 make a `raw/` value in `related` a
`raw-link` error and lines 346-362 make a `raw/` path in body prose one. So a
`sources` entry pointing into `raw/` is the one shape of reference that survives
the move, and it is the shape all three of these are already in.

Two live precedents in the corpus confirm the pattern rather than inventing it:
wiki/updates.md:11 cites `wiki/raw/macos-status.md` and wiki/releasing.md:16
cites `wiki/raw/legacy/macos-package-handoff.md`. Both are pages that left the
published corpus and kept their provenance. `component-catalog.md` and
`portability-ledger.md` were handled the same way.

Demotion also costs a reader nothing, because the publish step strips `raw/`, so
the page stops publishing either way. The difference between demote and delete
is invisible to every reader and visible only to whoever later asks where the
install guide's numbers came from. That asymmetry is the whole argument:
deletion buys nothing and forfeits the one thing this page still holds, which is
that its figures were measured end to end on a real machine rather than derived.

This decision also answers the open question carried on T2, "What does a
frontmatter `sources` entry mean once its source page is retired?" It means the
same thing it meant before, and it is repointed rather than removed. T2's
orchestrator ruling to leave wiki/clients/windows.md:13 exactly as found was
correct and is now completed by this task rather than left dangling.

##### Draft

**Do not open this task until T6, T9, T11, T12, T13, T14, T64 and T65 all read
`Complete`.** That is integrity rule 9 and it is the whole reason this task
exists separately from T9. T64 and T65 were added on the Phase C run of
2026-09-04, when measuring the inbound references found two gate-blocking ones
that no row owned.

The Phase C measurement of 2026-09-04, before that phase ran, found ten inbound
references rather than the seventeen this row's sizing evidence enumerated.
Phases A and B cleared seven as a side effect. The surviving ten, by kind:

| Kind | Locations | Blocks T16 | Owner |
| :-- | :-- | :-- | :-- |
| `related` entry | wiki/getting-started.md:8, wiki/releasing.md:9, wiki/updates.md:8 | Yes, `dead-related` and a broken See also link | T64, T14, T13 |
| Body link | wiki/first-run.md:192, wiki/updates.md:105, wiki/whats-not-here.md:23, wiki/_index.md:31 | Yes, `dead-link` | T65, T13, T12, T11 |
| `sources` entry | wiki/clients/macos.md:11, wiki/clients/windows.md:13, wiki/installing.md:15 | No, never resolved by the linter | T16 itself, per the decision above |

The three `sources` entries are this task's own work and are repointed at
`wiki/raw/install-macos.md` as part of the move, not before it: the target path
does not exist until the file is moved, so splitting the repoint into Phase C
would have written a citation to a file that was not there yet.

Before running it, verify two things rather than assuming them: that every
passage in the salvage table appears in its destination, and that the corpus
grep for `install-macos`, excluding `wiki/raw/` and the page itself, returns
nothing. A fold that misses an inbound reference leaves a dead link on a page
that was correct before.

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

### T41: Correct the Windows video-memory requirement in README.md

The T7 research stage reported that README.md repeats, verbatim, the Windows
requirement sentence that T7 corrects on wiki/getting-started.md, and that
source contradicts it. README.md sits outside the corpus root, so no writer
stage in Phase B may edit it, and CLAUDE.md's documentation-parity rule means it
cannot simply be left disagreeing with the page it was copied from.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: Medium
- Sizing evidence: unread by the orchestrator, sized up. Opened from tasks/docs/artifacts/T7.research.json, which reports the sentence at README.md:74-79.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Open questions:
  - Does a file outside `wiki/` belong in this tracker at all, and if it does, which corpus root does its research stage run against? Every other row in this file targets a page under wiki/.
  - Which of the three source-derived figures does README.md take? The same question is open on T7, and the two must not be answered differently.

##### Draft

Whatever T7 lands on wiki/getting-started.md, stated in README.md's register.
The two must agree, so this task runs after T7 and copies its resolution rather
than deriving its own.

### T42: Say on the iOS and visionOS pages that no build is obtainable yet

The T7 research stage reported that the published release carries assets for
Windows, macOS and Android but none for iOS, and that its notes say TestFlight
follows. Neither client page states that a reader cannot obtain a build. Once
T7 makes the corpus explicit about distribution, those two pages are the places
where it is still silent.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: S
- Confidence: Medium
- Sizing evidence: unread by the orchestrator, sized up. Opened from tasks/docs/artifacts/T7.research.json. Two pages are named, wiki/clients/ios.md and wiki/clients/visionos.md, and neither was opened in this run.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Open questions:
  - Does the honest-limits section of a platform overview take this, or does it belong in wiki/whats-not-here.md? wiki/page-types.md:239 names "What it cannot do yet" as the honest-limits section, which argues for the client pages.
  - Is the TestFlight intention firm enough to state? The research stage reported it from the release notes rather than from the tree.

##### Draft

Two pages, so this splits into one task per page after research.

### T43: Correct the create_persona voice parameter in the First run record

The T8 research stage reported that wiki/first-run.md declares the
`create_persona` voice parameter as `voice_id: string`, and that three source
locations declare it as `voice_design`, an array of two to four attributes. T8
was forbidden from touching that page's schemas and T28 is scoped to a different
passage on it, so no row owned this.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: unread by the orchestrator at the cited anchor, sized to match T28's scope on the same page. Opened from tasks/docs/artifacts/T8.research.json, which reports the declaration at wiki/first-run.md:283 and the three contradicting locations at backend/harness/valar/tools/tools.yaml:1112-1121, backend/harness/valar/tools/handlers/creation.py:288-296 and backend/harness/valar/gateway/first_run.py:221.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Open questions:
  - Should this be folded into T28, which already owns a correction on the same page in Phase G, rather than run as its own row? A phase never contains a page twice, so the two cannot run in parallel.
  - Does the corpus document the voice attribute vocabulary anywhere a reader can find it? The T8 research stage reported that the vocabulary is in the tree and in none of the 28 published pages.

##### Draft

A schema correction inside a decision record. The record's value is that it
states what the tool actually takes, so a wrong parameter name is the one defect
that makes the passage worthless rather than merely dated.

### T44: The colour swatch the model is offered and the handler rejects

The T8 research stage reported a product defect: the tool schema offers the
model a colour swatch the handler no longer accepts, and a model that picks it
silently gets a different colour. This is a defect in the product rather than in
a page, so no writer stage runs on it. It is recorded here for the same reason
T25 and T31 are.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: XS
- Confidence: High
- Sizing evidence: unread by the orchestrator, recorded from tasks/docs/artifacts/T8.research.json, which reports the swatch offered at backend/harness/valar/tools/tools.yaml:1125-1126, the accepted list at backend/harness/valar/tools/handlers/creation.py:52-60, the rename comment at creation.py:56-57, and the silent fallback at creation.py:88-99.
- Sources of truth: (none, this is a product defect and no page states the swatch list)
- Docs: (none, no page is edited)
- Open questions:
  - Is the fix to rename the swatch in the schema, or to accept the old name in the handler? The research stage reported that the rename was deliberate, after a live run named a persona after the swatch.

##### Draft

No writer stage. This row exists so the defect is not lost, and it is the
engineer's to take.

### T45: Link the persona walkthrough from the three pages no Phase B task owns

The T8 research stage returned seven pages that route a reader toward the
material the new walkthrough now holds. Three went to T6, T7 and T9, which
already own those pages this phase. Two belong to T15 and T29. Three are
unowned: a concept page that should link to the how-to that acts on it, a second
concept page in the same position, and a developer page whose pointer may
already be correctly aimed at the record.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: unread by the orchestrator at the cited anchors, sized from the three page count. Opened from tasks/docs/artifacts/T8.research.json, which names wiki/features/personas.md `## Making your first one`, wiki/features/second-brain.md `## Meeting it for the first time`, and wiki/developing.md `## Where to start reading`, and cites wiki/page-types.md:145 for the rule that a concept page links to the how-to pages that act on it.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Open questions:
  - Does wiki/developing.md need any change at all? The research stage reported that its pointer is correctly aimed at the record rather than at the walkthrough, and recorded it so the next stage decides rather than assumes.

##### Draft

Three pages, so this splits into one task per page after research. It cannot
run in the same phase as any task that owns one of them.

### T46: Point the First run record at the walkthrough and reconcile its steps

T8 wrote `wiki/meeting-your-persona.md` by extracting beats two and three of
`wiki/first-run.md`, and was forbidden from touching the record. So the record
still carries the procedure the how-to now owns, and it does not link to it. The
author reported both facts, and wiki/page-types.md:150-154 states that a record
page containing steps points at the how-to instead of holding them.

##### Details

- Agent State: Backlog
- Type: Restructure
- Scope: M
- Confidence: High
- Sizing evidence: wiki/first-run.md headings read by the orchestrator on 2026-09-04. `## Beat two: making someone` starts at line 214 with four subsections and `## Beat three: the second brain` starts at line 300, which is the material now duplicated by wiki/meeting-your-persona.md, whose sections the orchestrator read at lines 26 to 171 of that file. The record's frontmatter declares `type: decision-record` at line 4.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Open questions:
  - How much of beats two and three stays? The record's value is the dated decisions, the rule derived from a bug, and the reasoning; the reader-facing steps are what moved. Where a passage is both, this task decides which page keeps it, and nothing is deleted before the how-to demonstrably carries it.
  - Does this task or T43 correct the `voice_id` declaration? Both target the same page and a phase never contains a page twice.
  - Does the rename question close here? T8 left open whether a record and a how-to should both be called first run. This is the task that would carry the rename.

##### Draft

The record keeps its record. It gains a link to wiki/meeting-your-persona.md at
the point where a reader who wants to do the thing rather than understand the
decision should leave. Nothing is deleted until the how-to is confirmed to carry
it.

### T47: Capture the interview figure for Meeting your persona

Work for a person with a screenshot tool, requested by the T8 author. No writer
stage runs on it.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: XS
- Confidence: High
- Sizing evidence: requested in tasks/docs/artifacts/T8.author.json and placed as a pending figure in wiki/meeting-your-persona.md under `## Answer the question Sulivan opens with`. `python scripts/lint_wiki.py --figures` is the standing queue.
- Sources of truth: (none, XS route runs no research)
- Docs: (none, XS route runs no research)
- Open questions:
  - None recorded.

##### Draft

- path: `wiki/images/pending/meeting-your-persona-interview.png`
- The alt text and the capture spec are in the page's own placeholder, which is
  where the linter reads them from.

### T48: Capture the second-brain figure for Meeting your persona

Work for a person with a screenshot tool, requested by the T8 author. No writer
stage runs on it.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: XS
- Confidence: High
- Sizing evidence: requested in tasks/docs/artifacts/T8.author.json and placed as a pending figure in wiki/meeting-your-persona.md under `## Set up your second brain`. `python scripts/lint_wiki.py --figures` is the standing queue.
- Sources of truth: (none, XS route runs no research)
- Docs: (none, XS route runs no research)
- Open questions:
  - None recorded.

##### Draft

- path: `wiki/images/pending/meeting-your-persona-second-brain.png`
- The alt text and the capture spec are in the page's own placeholder, which is
  where the linter reads them from.

### T49: Capture the house row figure for Hearth on macOS

Work for a person with a screenshot tool, requested by the T6 author when it
landed the start-and-stop salvage. No writer stage runs on it.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: XS
- Confidence: High
- Sizing evidence: `python scripts/lint_wiki.py --figures`, run 2026-09-04, lists it pending at wiki/clients/macos.md:98 with its path, alt text and capture spec.
- Sources of truth: (none, XS route runs no research)
- Docs: (none, XS route runs no research)
- Open questions:
  - None recorded.

##### Draft

- path: `images/pending/macos-house-row.png`
- The alt text and the capture spec are in the page's own placeholder.

### T50: Capture the macOS first-open dialog figure for Installing Hearth

Work for a person with a screenshot tool, requested by the T9 author when it
landed the right-click-Open procedure. No writer stage runs on it.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: XS
- Confidence: High
- Sizing evidence: `python scripts/lint_wiki.py --figures`, run 2026-09-04, lists it pending at wiki/installing.md:88 with its path, alt text and capture spec.
- Sources of truth: (none, XS route runs no research)
- Docs: (none, XS route runs no research)
- Open questions:
  - None recorded.

##### Draft

- path: `images/pending/installing-macos-first-open.png`
- The alt text and the capture spec are in the page's own placeholder.

### T51: Move the macOS install tree and process list to a reference page

The T6 author reported that `wiki/clients/macos.md` still holds the install root
directory tree and the five supervised programs with their ports, that
wiki/page-types.md:249-250 moves reference material of that kind off a platform
overview, and that it left both on the page because no reference page carries
them for macOS yet and `wiki/clients/windows.md` holds the parallel material in
the same shape. Nothing is deleted before its new home exists.

##### Details

- Agent State: Backlog
- Type: Restructure
- Scope: M
- Confidence: High
- Sizing evidence: recorded from tasks/docs/artifacts/T6.author.json as an `extraction_needed` item. The orchestrator read wiki/clients/macos.md on 2026-09-04 before the edit and confirmed it then carried both the fenced install tree and the five-program list with ports 18700, 18765, 18766, 18080 and 18702.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Open questions:
  - Does one reference page serve both platforms, or does each client page get its own? The author reported the parallel Windows material is in the same shape, which makes this a two-page job either way.
  - Does this overlap T33, which already moves the install and process catalogs off wiki/clients/windows.md? If it does, the two should be one task rather than two, because both would create the same destination page.

##### Draft

The destination page does not exist. Creating it is the first half of this task,
and nothing comes off either client page until it does.

### T52: Say what a Windows machine with no dedicated GPU gets

The T7 reviewer reported this as the largest reader gap on `wiki/getting-started.md`
and blocked on it. The page's abstract promises a reader will find out whether
their machine runs Hearth, and the three video-memory bands T7 landed invite a
reader with integrated graphics to measure video memory they do not have.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: M
- Confidence: High
- Sizing evidence: recorded from tasks/docs/artifacts/T7.review.json, which blocked F3 on research. The orchestrator read wiki/getting-started.md on 2026-09-04 before the reshape and confirmed it then stated a Windows floor in video-memory terms only.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Open questions:
  - Is a Windows machine with no dedicated GPU a supported configuration, and what should a page tell a reader with integrated graphics? The reviewer reported that source settles the mechanism and not the position: crates/hearth-probe/src/machine.rs:49-51 falls back to total system RAM when no GPU reports video memory and :55-57 resolves the backend to `cpu`, so a 16 GB integrated-graphics laptop clears the refusal floor and is planned a tier 1 or larger model on the processor rather than declined. It reported that wiki/clients/windows.md assumes CUDA or Vulkan, that wiki/installing.md says only that a smaller GPU gets a smaller plan, and that it wrote no sentence because both honest options are a product call plus a measurement nobody has made.
  - How many pages state the Windows floor, and must they all change together? wiki/getting-started.md, wiki/clients/windows.md and wiki/installing.md all now speak to it.

##### Draft

The blocking fact is a product decision, not a documentation one: whether a
CPU-only Windows install is supported. Research establishes what the planner
does; someone has to say whether that is intended before a page states it.

### T53: Name the step that removes the Hearth client on Windows

The T9 reviewer blocked on this. `wiki/installing.md` now carries an uninstall
section whose last step is macOS-only, so a Windows reader is told how to remove
the product's folder and not how to remove the application.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: recorded from tasks/docs/artifacts/T9.review.json, which blocked F9 on research. The orchestrator read wiki/clients/windows.md:170-173 on 2026-09-04 and confirmed it settles only the product side, saying uninstalling is deleting the folder and that nothing is left in the registry beyond the installer's own entry.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Open questions:
  - Does the Windows installer register an entry in Apps and features that uninstalls the client, and is that the step to tell a reader to take, or is the client removed some other way? This is the question the reviewer stopped on.

##### Draft

One step in an existing section, once the fact exists.

### T54: Say what happens when setup is interrupted part way through

The T8 reviewer blocked on this. `wiki/meeting-your-persona.md` walks a reader
through a flow with no stated recovery path, and a reader whose app closes mid
interview has no way to learn what they lost.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: S
- Confidence: High
- Sizing evidence: recorded from tasks/docs/artifacts/T8.review.json, which blocked F6 on research.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Open questions:
  - With the app closed part way through the interview or the second-brain beat, what does the next launch of the desktop client show, and is the in-progress persona lost? The reviewer reported that an unfinished setup leaves the completed flag false and the next launch returns to setup, but that step state initialises at the welcome screen, so the reader-facing outcome is not settled by source.

##### Draft

A short section or a result note on the existing steps, once the behaviour is
established by running it rather than by reading it.

### T55: Record learning objectives for the pages the pipeline grades

All four reviews in Phase B reported the same absence: no page and no research
artifact records what the page is meant to teach, so every reviewer derived
objectives itself and graded against derived intent. That makes a review
unrepeatable, because the next reviewer derives a different set.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: L
- Confidence: High
- Sizing evidence: recorded from four review artifacts of 2026-09-04, T6.review.json, T7.review.json, T8.review.json and T9.review.json, each of which states that objectives are recorded nowhere and lists the set it derived. The orchestrator confirmed the mechanism by reading tasks/docs/tracker.md, where earlier phases record the same finding on T2.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Open questions:
  - Where does an objective live: in page frontmatter, in the research artifact, or in the tracker task? Each choice puts the record in a different agent's hands.
  - Is this a documentation task at all, or a change to the pipeline's contracts? It may belong beside the agent definitions rather than in the wiki backlog.
  - Do the four derived sets from this phase become the starting record, or is deriving them again the point?

##### Draft

Decompose before dispatch. This is a corpus-wide addition touching the reviewer
and researcher contracts, and the four sets already derived this phase are the
evidence that it is worth doing rather than the deliverable.

### T56: Two nits on Hearth on macOS the reviewer deferred

Both surfaced after the T6 reviewer's fix cycle closed, and neither needs
research.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: XS
- Confidence: High
- Sizing evidence: recorded from tasks/docs/artifacts/T6.review.json, entries F5 and R3, on a page the orchestrator read in full on 2026-09-04.
- Sources of truth: (none, XS route runs no research)
- Docs: (none, XS route runs no research)
- Open questions:
  - Should the start-and-stop section carry the two further facts the author left unresolved and the reviewer confirmed verified: that Quit, Stop and Restart file the conversation to the journal first, which is why Stop beats killing the process, and that the house row appears only on a Mac running its own house? Both are already published for Windows.

##### Draft

The page teaches that the local server is called "the house" and then calls it
the backend twice. The reviewer named the two strings.

### T57: Two nits on Getting started the reviewer deferred

Both surfaced during the T7 reviewer's single regrade, and neither needs
research. The reviewer reports both predate its own edits.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: XS
- Confidence: High
- Sizing evidence: recorded from tasks/docs/artifacts/T7.review.json, entries F5 and F6, on a page the orchestrator read in full on 2026-09-04.
- Sources of truth: (none, XS route runs no research)
- Docs: (none, XS route runs no research)
- Open questions:
  - None recorded.

##### Draft

The page tells a reader twice that Sulivan interviews them, and it calls a
persona `it` one line above a section that calls them `they`. The reviewer
reports the second argues against the product's own claim that you make someone
rather than configure something.

### T58: One nit on Meeting your persona the reviewer deferred

A one-line fix the T8 reviewer found after its fix cycle closed.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: XS
- Confidence: High
- Sizing evidence: recorded from tasks/docs/artifacts/T8.review.json, entry F5, on a page written and read in this run.
- Sources of truth: (none, XS route runs no research)
- Docs: (none, XS route runs no research)
- Open questions:
  - None recorded.

##### Draft

The reviewer describes it as a one-line fix for whoever next opens the page, and
reports deferring it only because its contract forbids a second fix cycle.

### T59: Move the disk-check sentence out of the macOS branch on Installing Hearth

The T9 reviewer's own F2 edit left a disk-check sentence in the macOS branch
when it applies to both platforms. It reports this needs no research and is a
one-sentence move.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: XS
- Confidence: High
- Sizing evidence: recorded from tasks/docs/artifacts/T9.review.json, entry F10, which states the reviewer caused it and could not fix it inside its single fix pass.
- Sources of truth: (none, XS route runs no research)
- Docs: (none, XS route runs no research)
- Open questions:
  - None recorded.

##### Draft

One sentence, out of `### macOS` and into the shared lead of the section.

### T60: Add the home row to the Windows install tree on Hearth on Windows

The T9 reviewer established that `home` exists on a Windows install and added
the row to the copy of the tree on `wiki/installing.md`. The original on
`wiki/clients/windows.md` still omits it, and that omission is what put a wrong
tree into the salvage in the first place.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: XS
- Confidence: High
- Sizing evidence: the orchestrator read wiki/clients/windows.md:160-168 on 2026-09-04 and confirmed the fenced tree lists six entries with no `home` among them. tasks/docs/artifacts/T9.review.json cites crates/hearth-probe/src/defaults.rs:46-48 defining the relative path and desktop-client/src-tauri/src/config_gen.rs:64 joining it to the root unconditionally.
- Sources of truth: (none, XS route runs no research)
- Docs: (none, XS route runs no research)
- Open questions:
  - Does this belong to T33, which already restructures this page's catalogs? If T33 rewrites the tree, this row folds into it.

##### Draft

One row in a fenced block, matching the wording the T9 reviewer used on
wiki/installing.md so the two copies agree until T51 or T33 merges them.

### T61: Capture the persona-in-use figure for Getting started

Work for a person with a screenshot tool, placed by the T7 reviewer. No writer
stage runs on it.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: XS
- Confidence: High
- Sizing evidence: `python scripts/lint_wiki.py --figures`, run 2026-09-04 after the reviewers, lists it pending at wiki/getting-started.md:115 with its path, alt text and capture spec.
- Sources of truth: (none, XS route runs no research)
- Docs: (none, XS route runs no research)
- Open questions:
  - None recorded.

##### Draft

- path: `images/pending/getting-started-persona-in-use.png`
- The alt text and the capture spec are in the page's own placeholder.

### T62: Capture the handover figure for Meeting your persona

Work for a person with a screenshot tool, placed by the T8 reviewer. No writer
stage runs on it.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: XS
- Confidence: High
- Sizing evidence: `python scripts/lint_wiki.py --figures`, run 2026-09-04 after the reviewers, lists it pending at wiki/meeting-your-persona.md:122 with its path, alt text and capture spec.
- Sources of truth: (none, XS route runs no research)
- Docs: (none, XS route runs no research)
- Open questions:
  - None recorded.

##### Draft

- path: `images/pending/meeting-your-persona-handover.png`
- The alt text and the capture spec are in the page's own placeholder.

### T63: The persona name length limit is off by one at each end

A product defect the T8 reviewer found while fact-checking. No writer stage runs
on it, and the page is not wrong relative to the product: the page and the
product's own rejection message agree with each other and both disagree with the
code that enforces the rule.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: XS
- Confidence: High
- Sizing evidence: recorded from tasks/docs/artifacts/T8.review.json, which cites the rejection message at backend/harness/valar/tools/handlers/creation.py:302 and the regex at creation.py:44.
- Sources of truth: (none, this is a product defect)
- Docs: (none, no page is edited until the product settles)
- Open questions:
  - Which end is wrong, the message or the regex? The reviewer reports the message says "under 24 characters" while the regex accepts 24 and rejects a one-character name. Fixing the regex and fixing the copy give a reader two different products.

##### Draft

No writer stage. Once the product settles, wiki/meeting-your-persona.md carries
the sentence that has to match.

### T64: Drop install-macos.md from the Getting started frontmatter

A single frontmatter `related` entry naming a page that is being retired. The
same defect as T14, on a page the Phase C plan did not own, found by measuring
the inbound references rather than by reading the earlier list.

##### Details

- Agent State: Complete
- Type: Fix
- Scope: XS
- Confidence: High
- Sizing evidence: wiki/getting-started.md lines 1-25, read on the Phase C run of 2026-09-04. Line 8 lists `install-macos.md` in the frontmatter `related` list, and line 7 already lists `installing.md`, so the change is a removal with no replacement to add. A corpus grep for `install-macos` on the same run returns no other match in this file, so the page's prose does not reference it. Line 4 reads `type: concept`, which is where the Shape comes from, and is the retype T7 landed.
- Sources of truth: (none, XS route runs no research)
- Docs: (none, XS route runs no research)
- Artifacts:
  - Author: tasks/docs/artifacts/T64.author.json, wrote wiki/getting-started.md
- Open questions:
  - Does the `sources` list want an entry for the page whose material this one absorbed? It names eleven sources and not install-macos.md, so this is a question about provenance rather than a dead reference, and it is not what this task fixed.
  - Does scripts/lint_wiki.py report no `dead-related` finding for wiki/getting-started.md after this edit? The author reported that its tool set is Read, Grep, Write and Edit with no shell, that it could not run the linter, and that it makes no claim of having run it. See the Phase C verification note.
- Author's reported findings: a grep of the target page returned line 8 as the only match for `install-macos`, and the author reported that the body's unsigned and unnotarized paragraph already links Installing Hearth, so no reader-facing pointer was lost by the removal.

##### Draft

Remove `install-macos.md` from the `related` list at line 8. Do not add a
replacement: line 7 already carries `installing.md`, which is the page that
survives the fold. Change nothing else on the page, including the `sources`
list, the prose, and `last_reviewed`.

This is why the entry has to go rather than merely being repointed:
`scripts/lint_wiki.py:288-297` resolves every `related` entry the way it
resolves a body link and reports an unresolvable one as `dead-related`, and the
publish step renders `related` as a See also section, so after the retirement
the entry would be a broken link a reader can click.

### T65: Redirect the shipped-wording sentence in the First run record

The record points a reader at Installing on macOS for the verbatim refusal
message. The link breaks when that page is retired, and the sentence makes a
claim about the destination that has to hold before the link can simply be
repointed.

##### Details

- Agent State: Complete
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: wiki/first-run.md lines 180-199, read on the Phase C run of 2026-09-04. Line 192, closing the passage under `### Say what you found, and be honest about it`, reads "[Installing on macOS](install-macos.md) quotes the shipped wording." Lines 188-191 describe how the refusal is written: it leads with what the refusal means, then the arithmetic behind it. A corpus grep for `install-macos` on the same run returns this as the only match in this file, so the frontmatter does not name it. Sized S rather than XS because wiki/installing.md:39-45, the page the salvage landed on, paraphrases the refusal rather than quoting it, so the sentence's own claim may stop being true when the link moves.
- Sources of truth:
  - source: crates/hearth-probe/src/plan.rs:84-96, covers the shipped refusal wording itself, which is a format template rather than a fixed sentence: "this machine cannot run Hearth. It has {} to work with, which leaves {} after the voice, speech recognition and headroom, and the smallest model is {}."
  - source: crates/hearth-probe/src/plan.rs:151-157, covers when the refusal is reached: `PlanError::TooSmall` only after `best_fit` fails against the coexist budget and then against the sequential budget
  - source: crates/hearth-probe/src/plan.rs:105-121, covers the arithmetic the wording names: base reserves, the coexist budget and the sequential budget
  - source: crates/hearth-probe/src/lib.rs:26-34, covers `human()`, which renders every figure in the message as GiB under a GB label
  - source: crates/hearth-probe/src/dict.rs:245-247, covers that `smallest()` is a minimum over tiers and can never return a build inside a tier's ladder
  - source: crates/hearth-probe/dictionary.yaml:131-224, covers the shipped tier table, whose minimum is tier 0 at 3,106,738,272 bytes
  - source: crates/hearth-probe/src/machine.rs:322-331, covers the `tiny` fixture, the only one that produces the refusal, which is a Windows machine with no GPU and no unified memory
  - source: crates/hearth-probe/tests/plan_fixtures.rs:118-124, covers the only test of the refusal, which asserts two substrings and guards no figure in the message
  - source: scripts/lint_wiki.py:88, 132-143, 293-297, 346-372, covers what the linter owns for this edit: `dead-link`, `raw-link`, and a bare raw/ path named in prose, all three at severity error
  - source: scripts/lint_wiki.py:211-216, 219-234, 380-386, covers paragraph measurement, and establishes that `is_prose` returns False for any line beginning with `[`, so line 192 as written is excluded from paragraph accounting and the paragraph at 188-191 is measured alone
  - contextual: wiki/installing.md:34-45, covers the candidate destination, which describes the refusal in the writer's own words and quotes nothing
  - contextual: wiki/install-macos.md:27-34, covers the retiring page and the corpus's only verbatim reproduction of the wording, as a blockquote at lines 32-34
  - contextual: wiki/page-types.md:156-181, covers the decision-record shape, which neither requires nor forbids a pointer sentence after a decision
  - contextual: tasks/docs/tracker.md:223, 236-238, covers the ratified salvage ruling that the message landed as prose rather than as a blockquote and carries no figures
  - contextual: wiki/updates.md:34-38, covers corpus precedent for a page quoting the source tree verbatim in prose and naming the file
  - contextual: wiki/getting-started.md:24-25, covers corpus precedent for naming a source-tree file in frontmatter `sources`
- Docs:
  - wiki/first-run.md, the pointer sentence at line 192 closing `### Say what you found, and be honest about it`
- Artifacts:
  - Research: tasks/docs/artifacts/T65.research.json
  - Author: tasks/docs/artifacts/T65.author.json, wrote wiki/first-run.md
  - Review: tasks/docs/artifacts/T65.review.json, verdict FAIL, score 2 to 4
- Review checklist, and where each entry went:
  - F2 a same-host detection claim the reviewer could not find in this tree, and F3 an abstract that promised the walkthrough on a decision record: both `done` by the reviewer. On F2 the reviewer reports that the cited file is not in this repository, that tasks/clients/desktop-client/file-capability-scope.md:68-72 records it as an archived Valinor document whose item 4 was never built, and that desktop-client/src/lib/clientProfile.ts:16-21 shows the client still declaring its capabilities unconditionally with no locality test. The page now states the mechanism is intended and unbuilt.
  - F1 type-mixture: `deferred`, owner T46. Confirmed that T46 exists and covers reconciling beats two and three and linking the walkthrough.
  - F4 the `voice_id` parameter name: `deferred`, owner T43. Confirmed that T43 exists and was opened for this exact line.
  - F5 the cache-invalidation claim: `deferred`, owner T28. Confirmed that T28 exists, and that T3's reviewer already deferred the same finding there.
  - F7 the two citations into wiki/raw/: `deferred`, `needs: research`, owner T35. Confirmed that T35 exists and holds that question corpus-wide.
  - F6 the install-root tree, which marks four existing directories as planned and omits `home\` in the same section that says uninstalling is one delete: `deferred`, no owner existed. Opened as T78. The reviewer names this as the one action item from its run with no owner.
  - The reviewer confirms no entry is `blocked`.
- Objective gaps recorded by the reviewer, which derived six because neither the page nor the research artifact records any:
  - "Say what would reopen any of these decisions" is not taught. The reviewer recorded it and deliberately did not charge it, reporting that wiki/backend/native-runtime.md and wiki/backend/packaging-options.md share the gap, so it is a corpus ruling rather than this page's defect. Opened as T79 rather than folded into T38, which concerns heading style and does not cover it. The same gap was recorded independently by the T3 reviewer, so this is the second time it has surfaced.
  - Content serving no objective: beats two and three teach apply-level objectives, which map to a how-to and never to a record, and the `choice_card` and `create_persona` parameter blocks plus `### The direction` are reference and source material. Both carried to T46.
  - Four of the six objectives are taught.
- Independent verification the reviewer performed on this task's own change: it confirmed that wiki/installing.md:39-42 describes and quotes nothing, that crates/hearth-probe/src/plan.rs:87-92 holds the wording as a three-slot template, that both halves of the replacement sentence are therefore true, that the sentence still opens with a link so paragraph accounting is unchanged, and that the added `sources` entry is precedented by wiki/getting-started.md:24.
- Open questions:
  - "Which of the three repairs does the author take? (A) Repoint to wiki/installing.md with the verb corrected to what that page does. (B) Replace the page pointer with a sentence that names crates/hearth-probe/src/plan.rs as where the wording lives. (C) Remove the pointer sentence and leave the decision at lines 182-191 standing alone. The evidence for and against each is set out in `notes`; this stage does not choose." Answered by the orchestrator ruling below.
  - "If the author takes option B, may the sentence also reproduce the wording, that is, the crates/hearth-probe/src/plan.rs:89-90 template with its three figure slots left unfilled? Quoting the template rather than an instance would satisfy the section's own argument, which is about phrasing, without importing the contradicted 2.36 GB or any other computed figure onto a decision record. It would also enlarge the edit beyond one sentence, which the dispatch bounds to the pointer sentence at line 192. The orchestrator owns that boundary, not this stage."
  - "If the author takes option B, does the citation also go into wiki/first-run.md's frontmatter `sources` at lines 9-11, which currently names only two unpublished research files? wiki/getting-started.md:24 sets the precedent and scripts/lint_wiki.py:282-286 never validates the entry, but the dispatch bounds this task to line 192 and a frontmatter edit is outside it."
  - "wiki/install-macos.md:34 carries a contradicted figure, 2.36 GB where crates/hearth-probe/src/dict.rs:245-247 and crates/hearth-probe/dictionary.yaml:138 produce 2.89 GB, and under T16 that page moves to wiki/raw/ with the wrong figure intact. That is T16's to answer, not T65's, but it bears on T65: it is the reason no surviving page quotes the wording, and it means the demoted file is not a trustworthy archive of the message either." Carried onto T16.
  - Where can a reader who is not looking at the source tree see the shipped refusal wording itself? The author reported that the corpus's only verbatim copy leaves the published wiki under T16, that wiki/installing.md describes the refusal without quoting it, and that the replacement sentence therefore serves a reader changing the house but not a reader who only has the wiki. Opened as T71.
  - May a wiki page publish the crates/hearth-probe/src/plan.rs template with its three figure slots left unfilled? The author reported that this is the only identified repair that would close the gap above, and that the dispatch forbade it inside this task's bounds. Opened as T71.
  - Was the linter run against this edit? The author reported that its tool set is Read, Grep, Write and Edit with no shell, that scripts/lint_wiki.py could not be executed, and that it verified the relevant rules by reading the source instead. See the Phase C verification note.
- Orchestrator rulings, so the author is not left choosing:
  - Take option B, and keep a reader-facing pointer inside it. The replacement is one sentence that names crates/hearth-probe/src/plan.rs as where the shipped wording lives and points a reader at wiki/installing.md for what the refusal tells them. Option A alone is rejected because it keeps a pointer whose verb has to be weakened to stay true, and the sentence's whole job is to say where the wording itself is. Option C is rejected because it deletes the routing and leaves the principle at lines 182-191 asserted with nowhere to check it. This page is `type: decision-record` and wiki/_index.md:84-86 places records with the engineering material, so a source citation serves its reader better than a paraphrase does, and wiki/updates.md:34-38 is the corpus precedent for exactly that shape.
  - Do not reproduce the template. Quoting it would enlarge the edit past the one sentence this task owns and would put a format string on a reader-facing page for no gain the citation does not already give.
  - Add `crates/hearth-probe/src/plan.rs` to the frontmatter `sources` list. A page that names a source in its prose and not in its frontmatter is inconsistent with the convention the corpus states at wiki/whats-not-here.md:34-37, the entry is never resolved by the linter, and wiki/getting-started.md:24 is the precedent. This is one line and it is a direct consequence of the edit rather than a widening of it.
  - The contradicted 2.36 GB figure on the retiring page is recorded on T16 and is not T65's to fix.

##### Draft

Do not repoint the link before establishing what the destination says. The
sentence carries two things: a pointer, and a claim that the pointed-at page
quotes the shipped wording. Only the pointer is broken by the retirement; the
claim is what decides whether repointing is honest.

The page is a decision record and the decision stays. The passage at lines
182-191 is the decision, and this task touches only the pointer sentence that
follows it. If wiki/installing.md paraphrases rather than quotes, the honest
repair is to reword the sentence to say what that page actually does, not to
move the link and leave the verb.

The research stage settled that it does paraphrase, and the orchestrator ruling
above picks the repair. Note one mechanical constraint the research stage found:
`scripts/lint_wiki.py:216` excludes any line beginning with `[` from paragraph
accounting, so line 192 as written is measured alone. A replacement that no
longer opens with a link joins the paragraph at 188-191 for length purposes, and
that paragraph is already four lines.

### T66: Correct the envs\voice row on the two Windows install-root trees

Both Windows install-root trees describe a voice environment installed at first
run. Source says a Windows install never creates one, because Windows moved to
the shipped omnivoice.cpp engine and skips the whole virtual-environment chain.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: reported by the T12 research stage on 2026-09-04 and recorded from tasks/docs/artifacts/T12.research.json. It cites wiki/installing.md:226 and wiki/clients/windows.md:165 as the two trees, and desktop-client/src-tauri/src/provision.rs:476-479 with crates/hearth-probe/dictionary.yaml:102 as the source that contradicts them. The orchestrator did not open either page at those lines on this run, so the Confidence rests on the research stage's citations rather than on an orchestrator read, and the research stage is the one that opened them.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T66.research.json
- Open questions:
  - Is the row wrong on both pages, or does the Windows install create the directory without populating it? The research stage reports that the provisioning chain short-circuits before the environment is built; whether anything else on the install path creates the path is not established.
  - Does the same row appear on the macOS tree, and is it correct there? crates/hearth-probe/dictionary.yaml:102 puts macOS in `cpp_platforms` too, so the same reasoning may reach a third location.

##### Draft

Two pages carry the same wrong row, so this task splits after Research into one
Author task per page. Do not touch either tree before the research stage
establishes what the install actually creates on Windows: the correction is
either a changed description, a removed row, or nothing at all, and the three
are not distinguishable from the pages themselves.

### T67: Split or retype Updating an install, which is four registers on one page

The page declares `type: concept` and its first six sections are a good concept
article. Then the register changes three times: a decision with no decision
reached, a build order, and bookkeeping for another page. Separately, the index
sends a reader here to learn how an install becomes a newer one, while the
working by-hand procedure sits on the install how-to.

##### Details

- Agent State: Backlog
- Type: Restructure
- Scope: L
- Confidence: High
- Sizing evidence: two stages, both on 2026-09-04. The T13 reviewer charged this as its largest finding, worth 2 of the page's 4.5 open penalty, and reports the mixture is three-way rather than two-way because `## The order the work should land in` is backlog material in a third register again; recorded from tasks/docs/artifacts/T13.review.json. The T11 research stage independently cites wiki/updates.md:15-17 stating that nothing in it is built yet, wiki/installing.md:247-260 carrying the by-hand update procedure landed by T9, and the index prose clause at wiki/_index.md:26-27; recorded from tasks/docs/artifacts/T11.research.json. The orchestrator read wiki/updates.md:1-20 and 95-119 on this run and confirmed the abstract and the signing section. Raised from M to L, and from Fix to Restructure, because the reviewer's finding is a page shape rather than a routing overlap, and because the reviewer reports two objective gaps that follow from it: an evaluate-level objective that implies a decision record, and a create-level objective that no page type carries at all.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T67.research.json
- Open questions:
  - Which page owns the update procedure, and which owns the design and the decision behind it? wiki/updates.md declares `type: concept` and wiki/installing.md declares `type: how-to`, which is an argument that the procedure belongs where T9 put it and updates.md keeps the reasoning. That is a verdict, not a reading, and it is what the research stage has to establish.
  - Does the index prose clause at wiki/_index.md:26-27 point at the right page today? T11 was ruled not to settle this inside a prose rewrite, so whichever way this task lands, the index sentence may need a follow-up.
  - Is this a consolidation question rather than a correction? If the two pages substantially duplicate, the `Corpus` route decides it rather than a Fix does.

##### Draft

Establish first, correct second. The failure mode here is a corrections task that
picks one page and edits the other into agreement without asking which one should
hold the material.

Nothing about this blocks T16 and nothing about it is urgent. It is recorded
because it is a real overlap introduced by the Phase B salvage, and the T11 run
was ruled not to absorb it.

### T68: Two backticked-filename links on Updating an install

Two links use a backticked filename as their link text, which the style guide
names as the wrong form. The same defect on the same page at line 105 is fixed by
T13; these two point at a different destination and were left outside that task's
statement.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: XS
- Confidence: High
- Sizing evidence: reported by the T13 research stage on 2026-09-04 and recorded from tasks/docs/artifacts/T13.research.json, which cites wiki/updates.md:113 and :153 as repeating the link-text violation at line 105, both pointing at backend/build-pipeline.md, and wiki/style-guide.md:160-165 as the rule. The orchestrator read wiki/updates.md:95-119 on this run and confirmed the backticked link at line 113; it did not read line 153.
- Sources of truth: (none, XS route runs no research)
- Docs: (none, XS route runs no research)
- Open questions:
  - Is the link at line 153 the same shape as the one at line 113? The orchestrator read the first and not the second, and the second is recorded from the research stage's report.

##### Draft

Replace the backticked filename with the destination page's human title in both
places, taking the title from wiki/backend/build-pipeline.md's own frontmatter.
Change nothing else. Run after T13, which owns the same page.

The linter enforces no part of this rule: the T13 research stage read all 492
lines of scripts/lint_wiki.py and reports that `MD_LINK` captures only the link
target. So this defect is invisible to the gate and is fixed because the style
guide states it, not because anything fails.

### T69: No page states which voice engine runs on which platform

The corpus says nothing about which of the two voice engines a given platform
runs, and nothing about what a Windows install downloads that a Mac does not.
T12 removed a sentence that got this wrong; nothing states what is right.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: M
- Confidence: High
- Sizing evidence: reported by the T12 author on 2026-09-04 and recorded from tasks/docs/artifacts/T12.author.json, and independently by the T12 research stage. The research stage cites crates/hearth-probe/dictionary.yaml:102 reading `cpp_platforms: [macos, windows]`, desktop-client/src-tauri/src/provision.rs:476-479 short-circuiting the virtual environment and torch chain on those platforms, and crates/hearth-probe/dictionary.yaml:44-54 as the genuine install-time difference, where a Windows install fetches an accelerator-matched CUDA build plus a cudart redistributable against a single Metal tarball. This tracker already records the same absence from the other direction on T2. The orchestrator opened none of these files on this run, so the Confidence rests on two agent stages that did.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T69.research.json
- Open questions:
  - Which page owns this? `wiki/backend/voice-engine.md` is the obvious home for which engine runs where, and `wiki/installing.md` is the obvious home for what a reader downloads. That may make this two tasks rather than one, which is what the research stage settles.
  - Is the difference worth stating to a reader at all, or only to a contributor? A reader on a metered connection cares about the download size; the engine's identity is an implementation fact. The two answers land on different pages.

##### Draft

Do not start on a page. The research stage decides where each half of this
belongs, and the split follows from its `affected_docs[]`.

Note the shape constraint that produced this row: T12 could not state the fact
because wiki/whats-not-here.md is a landing page and wiki/page-types.md:91-92
keeps anything a reader can act on off one. The fact is real and correcting the
page that carried it wrongly did not place it anywhere.

### T70: The linter has no index-membership check, so a page can publish with no sidebar entry

wiki/page-types.md requires every published page to appear exactly once in
exactly one section of the index, and nothing enforces it. A page can be
published, be absent from the index, have no sidebar rail entry, and produce zero
linter findings. That is exactly what happened to wiki/meeting-your-persona.md
between the phase that created it and the phase that indexed it.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: S
- Confidence: High
- Sizing evidence: reported by the T11 author and independently by the T11 research stage on 2026-09-04, recorded from tasks/docs/artifacts/T11.author.json and tasks/docs/artifacts/T11.research.json. The research stage read scripts/lint_wiki.py:256-408 as the complete set of checks and reports no index-membership check and no once-and-only-once check, and cites scripts/publish_wiki.py:63-76, which publishes every page outside wiki/raw/ regardless of index membership, against scripts/publish_wiki.py:172-195, which builds the rail only from the index. The lived instance is this repository's own: wiki/meeting-your-persona.md published with no rail entry and the linter said nothing.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T70.research.json
- Open questions:
  - Is this a linter change, a documentation change, or both? The rule exists and is stated; what is missing is enforcement. A new check in scripts/lint_wiki.py would catch it, and that is code rather than prose.
  - What severity? An unindexed page is invisible to a reader navigating the wiki, which argues for an error. But a page can legitimately be mid-flight between the phase that writes it and the phase that indexes it, which argues for a warning. See T73, which is the exception that any such check has to encode.

##### Draft

This is tooling work with a documentation consequence, so it needs research
before anyone decides which. Do not add a check without first settling T73: the
publish script hardcodes one rail entry outside the section loop, so a naive
once-and-only-once check would flag wiki/whats-not-here.md, which is correct as
it stands.

### T71: Decide whether a reader-facing page reproduces the shipped refusal wording

The product's refusal message is the corpus's worked example of writing plainly
to someone whose machine is too small. Once wiki/install-macos.md is demoted, no
page a reader can open reproduces it. The decision record now cites the source
file, which serves a contributor and not a reader.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: reported by the T65 author and established by the T65 research stage on 2026-09-04, recorded from tasks/docs/artifacts/T65.author.json and tasks/docs/artifacts/T65.research.json. The research stage established that crates/hearth-probe/src/plan.rs:87-92 holds the wording as a three-slot format template, that wiki/install-macos.md:32-34 is the corpus's only verbatim copy, and that wiki/installing.md:34-45 describes the refusal and quotes nothing. The T65 reviewer independently confirmed both halves.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T71.research.json
- Open questions:
  - May a wiki page publish the template with its three figure slots left unfilled? The T65 author reports this is the only identified repair that closes the gap, because publishing an instance would import figures that source contradicts. The research stage reports that the only verbatim copy in the corpus carries a figure of 2.36 GB where source produces 2.89 GB, which is why an instance cannot simply be copied.
  - Which page carries it if any does? wiki/installing.md is where the refusal is described, so it is the candidate, but a format string on a reader-facing install page is a judgement rather than an obvious yes.
  - Is the gap worth closing at all? A reader whose machine is refused sees the message on their own screen. The page's job may be to describe the refusal rather than to reprint it, in which case the answer is no and this row closes with a recorded decision.

##### Draft

The honest outcome here may be "no page carries it", and that is a result rather
than a failure. What is not acceptable is leaving it undecided, because the
corpus currently has a decision record arguing for a style of message with no
reader-facing example of that style anywhere.

### T72: Settle which index section a decision record belongs in

wiki/first-run.md is a decision record listed in a reader-facing index section,
now beneath a how-to that was extracted from it. The index describes another
section as the engineering record and tells a reader using Hearth they can stop
above it. Nothing states a rule, so the question keeps being reopened.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: Medium
- Sizing evidence: raised as an open question by the T11 research stage and deferred as checklist entry C1 by the T11 reviewer on 2026-09-04, recorded from tasks/docs/artifacts/T11.research.json and tasks/docs/artifacts/T11.review.json. Both cite wiki/first-run.md:4 declaring `type: decision-record` and wiki/_index.md:84-86 describing `## Looking under the hood` as the engineering record with a line a product reader can stop above. The research stage marked the underlying claim `unverifiable`, because wiki/page-types.md governs each page's own shape and states no rule about which types may sit in which index section. Confidence is Medium because the evidence is strong and the answer is a policy the corpus does not yet have.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T72.research.json
- Open questions:
  - Is the rule about page type, or about audience? A decision record can be exactly what a reader of a reader-facing section wants, and the index's own division is by audience rather than by type.
  - If first-run.md moves, does anything else move with it? wiki/backend/ already holds records, so the question may be about a page in the wrong place rather than about a missing rule.

##### Draft

The deliverable is a rule written into wiki/page-types.md, and then whatever
index edit follows from it. Do not move the page first: the T11 run declined to
move it precisely because moving a page between index sections changes the
reading order, and a reading order should change because of a rule rather than
because of one page.

### T73: Page types and the publish script disagree about the once-only rule

wiki/page-types.md requires every published page to appear exactly once in
exactly one index section. scripts/publish_wiki.py hardcodes one rail entry
outside the section loop, so obeying the rule literally for that page produces
two rail entries. Neither file records the exception.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: XS
- Confidence: High
- Sizing evidence: deferred as checklist entry C2 by the T11 reviewer and independently reported by the T11 research stage on 2026-09-04, recorded from tasks/docs/artifacts/T11.review.json and tasks/docs/artifacts/T11.research.json. Both cite wiki/page-types.md:93 for the rule and scripts/publish_wiki.py:189-194 for the hardcoded `[What is not here](whats-not-here)` entry that closes the rail outside the section loop. The lived consequence is that wiki/whats-not-here.md is reached from closing prose at wiki/_index.md:95 rather than from a section list, which is correct and looks like a rule violation.
- Sources of truth: (none, XS route runs no research)
- Docs: (none, XS route runs no research)
- Open questions:
  - Is the fix to record the exception in wiki/page-types.md, or to drop the hardcoded entry from the publish script so the rule holds without one? The second is a code change and changes the rail.

##### Draft

The reviewer calls this a trap for the next author rather than a defect in any
page, which is the right reading: nothing is wrong today and the next person to
apply the rule literally will break the rail. One sentence in
wiki/page-types.md beside the rule is the cheap fix. Blocks nothing, and T70
should not add an index-membership check before this is settled, because such a
check has to encode this exception.

### T74: Compress What is not here to routing and retitle its two headings

The register of gaps spends most of one section teaching a contributor how to
cite a raw/ source and what the linter rejects, on a page whose type forbids
anything a reader can act on, and links the page where that material already
lives. Both its headings are nouns where the type asks for gerunds.

##### Details

- Agent State: Backlog
- Type: Restructure
- Scope: S
- Confidence: High
- Sizing evidence: deferred as checklist entries F1 and F2 by the T12 reviewer on 2026-09-04, recorded from tasks/docs/artifacts/T12.review.json. The reviewer charges F1 at 2 and F2 at 1 of the page's 3 open penalty, cites wiki/page-types.md:91-92 for the rule the section violates twice, and reports that `## Material that never publishes` spends four of its six sentences on contributor material that wiki/developing.md, linked from that same section, already owns. The orchestrator read wiki/whats-not-here.md in full on this run and confirms the section runs lines 30-40 and that lines 34-40 are the contributor material described.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T74.research.json
- Open questions:
  - Does the raw/ convention move to wiki/developing.md, or is it already there? The reviewer reports that page already owns it, which would make this a deletion rather than a move. Verify before cutting: nothing is deleted before its new home exists.
  - What does the `## Pages that are not written yet` heading become, given that entry 1 is now a missing section and entry 2 is a missing page? The reviewer reports the heading cannot simply become "Sections".
- Reviewer's own estimate, recorded as the reviewer's report rather than as a tracker claim: it reports that clearing F1 would take the page from 7 to 9, and that clearing both would reach the cap.

##### Draft

The verdict that the page keeps `type: landing` is carried forward from the T12
review and is not reopened here. This is a compression, not a retype.

### T75: An unverifiable quotation on Updating an install

The page quotes a comment about what the install record is read by, and the
comment is not in this repository. One verified quotation sitting beside one that
cannot be found is worse than neither, because a reader who checks the second has
no way to know the first is sound.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: raised as checklist entry F2 by the T13 reviewer on 2026-09-04 at `state: blocked`, `needs: research`, and recorded from tasks/docs/artifacts/T13.review.json. The reviewer reports the quotation at wiki/updates.md:56, reports that a grep of the whole worktree for its distinctive phrase returns only that line and one line of wiki prose at wiki/first-run.md:98, reports that the record is written at desktop-client/src-tauri/src/probe.rs:255-275, and reports that the nearest real comment at probe.rs:148-155 says something else. The reviewer states its live hypothesis is that the comment lives in Valinor, which this repository does not carry.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T75.research.json
- Open questions:
  - The question research must answer, in the reviewer's own framing: does the quoted comment exist in any authoritative tree, and which one?
  - If it exists only in Valinor, may a Hearth page quote it? CLAUDE.md makes Valinor the developer build and Hearth the product, and features land in Valinor first, so a comment may be real and still not be Hearth's to cite.

##### Draft

Routed through Research, because the reviewer stopped precisely where it could
not settle the fact itself, and reports that it did not soften, delete or
repoint the sentence because all three would settle a provenance question by
guess. That restraint is correct and this task exists to end it properly.

The claim the sentence makes is independently supported by wiki/first-run.md:98,
so one available repair is to keep the claim and drop the quotation marks. That
is a decision for after the research, not before it.

### T76: Four settled questions still presented as open on Build pipeline

wiki/updates.md carries a section recording that four questions raised on the
build pipeline page are now answered. The build pipeline page still presents them
as open, so only a reader who lands on the update page learns otherwise.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: raised as checklist entry F4 by the T13 reviewer on 2026-09-04 at `state: deferred`, `needs: restructure`, and recorded from tasks/docs/artifacts/T13.review.json. The reviewer charges it at 1, reports that three of the four bullets under `## What this closes elsewhere` answer questions about bundling, WSL and the macOS voice engine, cites wiki/style-guide.md:173-180 as the supersession mechanism this defeats, and recommends keeping "Who signs the macOS build?" open in both places. The reviewer assigned it to T67 and then flagged that it wants its own row because the fix edits a different page, which is why it is here.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T76.research.json
- Open questions:
  - Are all four genuinely settled, and settled by what? The reviewer reports the update page's account of them; the source that settles each is what research establishes.
  - Does the material move to wiki/backend/build-pipeline.md, or is it stated in both places? The reviewer recommends moving the answers and leaving one sentence behind.
- Note: this task edits wiki/backend/build-pipeline.md, which T17 also owns. The two must not run in the same phase.

##### Draft

Two pages are fixed by one change, which is why the reviewer wanted it separated
from the page it was found on. Do not run it inside T67.

### T77: State whether an edit bumps last_reviewed

Every page carries a `last_reviewed` date, the linter checks that the key is
present and never that it is current, and no page states whether editing a page
should move it. The corpus already behaves as though a rule exists.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: XS
- Confidence: High
- Sizing evidence: raised by the T13 author and then as checklist entry F6 by the T13 reviewer on 2026-09-04 at `state: blocked`, recorded from tasks/docs/artifacts/T13.author.json and tasks/docs/artifacts/T13.review.json. The reviewer reports that wiki/installing.md:5 moved to 2026-09-04 after being edited that day while wiki/style-guide.md:5, wiki/page-types.md:5 and wiki/developing.md:5, untouched, still read 2026-09-03, so the corpus behaves as though the rule exists. It reports that wiki/developing.md:227-229 requires the key and is silent on maintaining it, and that the linter checks presence rather than freshness. The orchestrator read wiki/updates.md:5 on this run and confirms it still reads 2026-09-03 after being edited on 2026-09-04.
- Sources of truth: (none, XS route runs no research)
- Docs: (none, XS route runs no research)
- Open questions:
  - Does every edit bump it, or only an edit that re-verifies the page's claims? The key is named `last_reviewed`, not `last_edited`, which argues for the second, and the T13 reviewer notes its own edit was a review in that sense.
- Reviewer's stated view, recorded as the reviewer's report rather than as a decision: it recommends bumping the date and writing the rule down, and reports that it did not act because applying an unstated rule on one page sets a corpus-wide precedent from one page.

##### Draft

One sentence in wiki/developing.md beside convention 3. The deliverable is the
rule, not a sweep of the corpus's dates; whether a backfill follows is a separate
call once the rule exists.

### T78: The install-root tree in the First run record marks built directories as planned

The record's install-root tree annotates four directories that exist as
"(planned)", and omits `home\` from the same section that says uninstalling is
one delete of the install root. A reader is told to expect the wrong shape of a
folder the page tells them they can delete.

##### Details

- Agent State: Backlog
- Type: Fix
- Scope: S
- Confidence: High
- Sizing evidence: raised as checklist entry F6 by the T65 reviewer on 2026-09-04 at `state: deferred` with no owner, and recorded from tasks/docs/artifacts/T65.review.json. The reviewer names it as the one action item from its run with no owner, and reports the two halves together: four existing directories marked planned, and `home\` omitted in the section headed on the premise that deleting the folder is the uninstall. The orchestrator did not open the tree on this run, so the Confidence rests on the reviewer's read.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T78.research.json
- Open questions:
  - Which four directories, and what creates each? The reviewer reports the count and the defect; which rows are wrong is what research establishes against the provisioning source.
  - Is this the same defect as T60, which adds a `home` row to the Windows install tree on Hearth on Windows? Two pages carrying the same missing row would make one source fix and two page edits. Check before running either.

##### Draft

wiki/first-run.md is a decision record and its decisions stay. This is a tree
that describes the product, so correcting it is a correction rather than a
retype, and the dated framing around it is not touched.

Note that T3 and T65 have both already run on this page and T46 owns its
extraction. Check what each left before editing.

### T79: No decision record says what would reopen its decisions

The decision-record shape asks a record to say what would reopen what it decided.
Three records do not. Two separate reviewers found the same gap independently, on
different pages, which makes it a corpus ruling rather than one page's defect.

##### Details

- Agent State: Backlog
- Type: Add
- Scope: M
- Confidence: High
- Sizing evidence: recorded independently by the T3 reviewer and the T65 reviewer, on 2026-09-04 and in the Phase A run, from tasks/docs/artifacts/T3.review.json and tasks/docs/artifacts/T65.review.json. The T65 reviewer reports the gap on wiki/first-run.md and deliberately did not charge it, because wiki/backend/native-runtime.md and wiki/backend/packaging-options.md share it, so it is a corpus ruling. The T3 reviewer reports the same absence on wiki/first-run.md and names two candidate reopening conditions already in evidence: the retirement of the take-turns branch, and whether a Linux client ships. This is not T38, which concerns whether concept pages take action-title headings.
- Sources of truth: (Research fills)
- Docs: (Research fills)
- Artifacts:
  - Research: tasks/docs/artifacts/T79.research.json
- Open questions:
  - Is the remedy a section on each record, or a rule stated once in wiki/page-types.md and then applied? The shape already asks for it, so the rule exists and what is missing is the content, which argues for three page edits.
  - Does every decision need a reopening condition, or only the ones whose premises are known to be moving? A record that lists a condition for every decision it ever made becomes a list nobody reads.

##### Draft

Three pages, so this splits after Research into one Author task per page.

The two candidate conditions the T3 reviewer named are a starting point and not
the answer: a reopening condition has to come from the decision it belongs to.
