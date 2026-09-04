---
area: development
status: scoped
depends_on: []
blocks: []
updated: 2026-09-03
---

# The documentation pipeline, second pass

The four writer agents and the style skill were built as a live demo and then
used in anger on this corpus. They work. They took the wiki from 67 linter
findings to zero and caught a factual contradiction on the way.

They also cannot see the thing that is actually wrong with the wiki. This file
records what the second pass changes and why, so the work can be executed from
the record rather than from memory.

## The evidence

Two measurements set the scope.

### The corpus does not fit the four page types

All 26 published pages classified against `page-types.md`:

| Type | Pages | Notes |
| --- | --- | --- |
| Landing | 2 | `_index.md`, `whats-not-here.md` |
| How-to | 6 | `developing.md` is the model. `installing.md`, `install-macos.md`, and `releasing.md` are the three retired shapes. `first-run.md` is 322 lines of narrative beats. |
| Concept | 8 | `second-brain.md` carries 15 H2 sections. |
| Decision record | 2 | `native-runtime.md`, `packaging-options.md`. Both clean. |
| Reference | 2 | No template exists for these. |
| Platform overview | 5 | No template exists for these. |
| Hybrid, needs splitting | 1 | `build-pipeline.md` |

Two types are missing from the guide. Reference covers `tool-catalog.md` and
`persona-face.md`, whose catalog sections run 80 and 59 lines because no shape
tells them where to stop. Platform overview covers `clients/`, and it is not a
type invented for this document: `android.md`, `ios.md`, and `visionos.md`
already converged on the same spine independently.

```
## What it does today
## The persona, or The face
## How pairing works
## What it needs
## What it cannot do yet
```

The two client pages that do not follow it are `windows.md` and `macos.md`, and
those are the two that are broken. Conformance to the unnamed type predicts
which pages read well.

### The A/B against a known-good page

`wiki/clients/windows.md` measured against
[Navigating the Reality Composer Pro workspace](https://developer.apple.com/documentation/realitycomposerpro/realitycomposerpro-essentials-workspaceoverview),
an Apple Developer article of comparable purpose written by this repository's
author.

| | Apple | `windows.md` |
| --- | --- | --- |
| Abstract | 14 words, one sentence | none |
| H2 sections | 15 | 6 |
| Median paragraph | 12 words | 55 words |
| Longest paragraph | 51 words | 128 words |
| Paragraphs over 40 words | 2 of 75 | 22 of 31 |
| Words per section | about 80 | about 310 |
| Lists | 12 | 4 |
| Images | 8 | 0 |
| Callouts | 5 | 0 |
| See also | 6 links, rendered | `related:` present, never rendered |
| Action-title headings | 14 of 15 | 0 of 6 |

The finding underneath the numbers: **Hearth writes term lists as paragraphs.**
Apple gives a bolded term a six-word definition inside a list, so eleven
toolbar icons scan in ten seconds. `windows.md` gives a bolded term ninety
words of prose, nine times on one page. The information architecture is already
right. The container collapsed.

This matters for scoping the work. `windows.md` is well written at the sentence
level and its technical claims hold up: `POST /sessions/flush` is real at
`backend/harness/valar/gateway/server.py:229`, and `file_roots.yaml` is real at
`backend/harness/valar/tools/file_roots.yaml`. The page fails on form alone.

### The layer the work sits in

Three enforcement layers exist and the work is in the wrong one.

| Layer | Cost | Catches today |
| --- | --- | --- |
| `scripts/lint_wiki.py` | free, runs in CI | the five conventions, link resolution |
| The style packs | read by two agents | everything else, as prose |
| The reviewer agent | one subagent run per page | whatever it can enumerate |

Most of what the packs describe is mechanically detectable, and all of it
currently sits in the layer that costs a subagent run per page. That is why 26
pages have been graded once. The one review artifact in the repo,
`wiki/features/persona-face.review.json`, found nine items: eight are style
nits and the ninth is a `raw/` link the linter already catches. Zero structural
findings, on a page with a 59-line catalog section.

That is not a bad agent. It is an agent grading against the only material
enumerated concretely enough to grade against. `SKILL.md` gives it tables, bans,
and a severity scale. `page-types.md` gives it 882 words of prose and no
findings vocabulary.

## What ships

### 1. `wiki/style-guide.md`

The canonical Hearth writing rules, published rather than living only in a
gitignored directory. It carries the terminology table, the reader-is-you rule
and its `backend/` exception, American English, procedure shape, link text,
superseded content, and the Hearth versus Valinor scope rule.

It does not restate the five conventions. `developing.md` is their canonical
home and the only place that states them, and the style guide links there.

### 2. `wiki/page-types.md`

The six types, each with its purpose, shape, rules, and the corpus pages that
are examples of it. Reference and platform overview are new. Platform overview
is written from the spine the three conforming client pages already use.

Both pages need an `_index.md` entry under "Building and changing Hearth",
beside `developing.md`, because every published page appears there exactly once
and `_Sidebar` is built from it.

### 3. Frontmatter: `type:` added, `status:` given a vocabulary

`type:` becomes the sixth key, stamped on every page from the classification
above. This changes a published convention, so convention 3 in `developing.md`
gains `type` in the same change, and the linter's frontmatter check follows.
That is the documentation parity `CLAUDE.md` requires.

`status:` gets the six work-tracking values that `wiki/task-files.md` already
defines: `open`, `scoped`, `design`, `blocked`, `decided`, `closed`. This
settles the "Needs sign-off" note the Hearth pack has carried since it was
written. One vocabulary now spans `wiki/` and `tasks/`, so moving between them
needs no second set of habits and the board can see documentation work in the
same terms as everything else.

All 26 pages currently say `draft`, which is not one of the six, so every page
takes a real value during this pass. What the values mean for a page rather than
a task:

| Value | The page |
| --- | --- |
| `open` | Exists and needs work nobody has scoped. |
| `scoped` | The work on it is defined. |
| `design` | Its shape is being decided or restructured. |
| `blocked` | Waiting on something outside the page. |
| `decided` | The content decision is made, the writing is not done. |
| `closed` | Accurate, correctly typed, needs nothing. |

The starting assignment: pages this spec names for conversion are `scoped`,
`native-runtime.md` and `packaging-options.md` are `closed` because the
classification found them clean, and everything else is `open`.

Frontmatter never reaches a reader. `publish_wiki.py` strips it, which is why
internal work states are safe to keep here.

One thing to watch rather than fix now: `closed` reads as finished, and a living
document is never finished. If the field starts lying, that is the signal to
revisit the vocabulary.

### 4. `scripts/lint_wiki.py`

The linter gains a severity level. Today every finding fails CI, which is why
no subjective check can be added: the reader-drift rule alone would fail on 25
instances across 9 pages on the day it landed.

**Errors**, deterministic with no false positives:

- `type` present and one of the six values.
- `status` present and one of the six values. `draft` is no longer legal.
- No absolute machine paths in `sources`. PR #23 fixed eight of these by hand
  and nothing stops them returning.
- The targeted British spellings: `summarised`, `normalisation`, `catalogue`,
  and the rest of a named list rather than a broad regex.
- `the gateway` used to mean the house.

**Warnings**, reported without failing:

- Reader drift outside `backend/`: 25 instances across 9 pages today.
- Bold-lead prose blocks: 90 across 15 pages today.
- A section over a word threshold with no H3.
- A paragraph over a word threshold.

Warnings let the thresholds be calibrated against real pages before any of them
is promoted to an error.

The linter also gains `--figures`, which prints every pending figure
placeholder with its page, line, path, and capture spec. See the figure
protocol below.

### 5. `scripts/publish_wiki.py`

Three changes, none of them agent work:

- Render `related:` as a See also section. The data is already in the
  frontmatter of every page and is currently thrown away at publish time. This
  is the cheapest quality win available.
- Strip unfulfilled figure placeholders, so a pending capture never renders as
  broken art on the live wiki.
- Teach the image regex the capture-spec title, and drop that title at publish.
  It is an authoring annotation and does not belong to the reader.

Correction to an earlier draft of this file: images are **already** handled.
`render()` rewrites every image link to a `raw.githubusercontent.com` URL
against main, so no asset copy into the wiki repository is needed or wanted.
The earlier claim that images could not reach the wiki came from grepping for
a copy operation rather than reading the renderer.

### 6. `scripts/doc_graph.py`

The duplication detector. Section-level cosine similarity over content words,
best-match swept across the corpus, thresholded at 0.45 for duplicate and 0.30
for overlap. It is deterministic, needs no model call, and belongs in a script
for the same reason the mechanical style rules belong in the linter: the
researcher should spend its run on judgment, not on arithmetic it cannot do as
well.

It emits three things:

- `clusters[]`: pages whose pairwise similarity exceeds the threshold, with a
  per-section best-match mapping.
- `unique[]`: sections in a cluster member matching nothing else. These are the
  salvage list, and no page is retired before they land somewhere.
- `planned[]`: prose announcing intent to create a page, matched against the
  existing clusters. Phrases such as "does not exist yet", "mirroring", and
  "until that guide is written". This is the check that would have caught the
  install cluster before it grew.

Two findings from running the prototype across all 26 pages, both of which the
implementation has to respect:

**Cluster on sections, not on whole documents.** Connected components over
whole-document similarity at 0.50 produced a nine-page cluster chaining
`install-macos.md` through `installing.md`, `windows.md`, `first-run.md`,
`build-pipeline.md`, and `developing.md` to `releasing.md`. That is transitive
drift, not a nine-way duplication. Section-level matches are the real signal.

**Similarity cannot license a deletion on its own.** The highest-scoring pair
in the corpus is `clients/android.md` against `clients/ios.md` at 0.75, above
the install pair at 0.72. Their sections match hard: `How pairing works`
against its twin at 0.71, `What it needs` at 0.68. Both pages are correct.
They score high because they share the platform overview spine while describing
different platforms.

The score cannot separate that from real duplication. Only the objectives can:
"pair the Android client" and "pair the iOS client" are two objectives a reader
needs both of, while "install Hearth on a Mac" is one objective with two pages.
A `delete` verdict driven by similarity alone would eventually delete `ios.md`.
This is why the learning graph is a prerequisite for the consolidation verdict
rather than an enhancement on top of it.

### 7. `scripts/graph_lint.py` and the objective records

The learning graph and its linter. Objectives live with the page rather than in
a side file, as a frontmatter block naming what the page teaches and at what
Bloom level. Journeys live in one corpus-level file, because a journey crosses
pages by definition.

The linter runs the checks in the learning graph section below. Like
`doc_graph.py` it is deterministic: the graph is data, and traversing it is
arithmetic. Writing the objectives is the judgment, and that belongs to the
researcher.

### 8. `.claude/skills/hearth-style/`

A thin loader that reads `wiki/style-guide.md` and `wiki/page-types.md` as
canonical, plus `technical-writing-style` for generic craft. It carries only the
agent-only material: the findings vocabulary and the severity scale.

Reading the wiki pages at runtime rather than generating copies removes the
sync problem entirely. `technical-writing-style` stays untouched and portable to
other repositories.

This also settles the handoff's first open question in the useful direction. The
rules become tracked and public even if `.claude/` stays gitignored.

## New style rules the A/B produced

These do not exist in any current pack. They are the difference between the two
pages measured above.

**Term lists.** When a section introduces several named things, each with a
short definition, it is a list with a bolded term and a one-line definition, not
a run of bolded-lead paragraphs. This is the single highest-leverage rule in the
second pass.

**Paragraph density.** A target and a ceiling, calibrated from the A/B rather
than asserted. Apple's median is 12 words and 3 percent of its paragraphs exceed
40 words.

**Section mass.** A section has a size at which it must gain H3 headings or
split. Nothing anywhere currently says a section should end.

**Figures.** Where a section describes a UI surface, it carries a figure.

## Agent contract changes

| Agent | Change |
| --- | --- |
| Reviewer | A structural findings vocabulary with ids and detractions, graded against the page's declared `type`. Wrong type, missing spine section, section over mass, term list as paragraphs, and a dated status log all become findings that cost real points. Without this the reviewer keeps grading nits, because nits are what it can enumerate. |
| Author | A `restructure` mode. Reshape a page to its type's spine: moving, splitting, and re-heading allowed, inventing facts still forbidden. Content belonging on a different page returns as `extraction_needed[]` rather than a second file, so the one-page discipline holds. Also emits figure placeholders and reports them as `figures_requested[]`. |
| Researcher | Three additions. First, a code authority: the repository is the canonical source for behavioral claims, and the current vocabulary of `canonical`, `primary`, and `contextual` describes only documents. For a product that reaches no external service, the source tree settles questions that WebSearch cannot. Second, a corpus graph mode, because `gap-map` fires only on `Type: Add` for a page that does not exist yet, so nothing analyzes the pages that already exist. Third, a consolidation verdict: given the graph, decide which page survives a cluster and what must be salvaged before the others are retired. Fourth, and the one that makes the rest safe, the learning graph: write the objectives a page teaches, at a Bloom level, and trace the reader journeys through them. Findings JSON also gains `recommended_type`. See the learning graph and the consolidation protocol below. |
| Orchestrator | The restructure route in the route table, and a page-type column in the tracker, named so it does not collide with the existing `Type` meaning Fix or Add. |

## The figure protocol

The author is the only stage that knows why a figure belongs somewhere, so it
writes the work order. A placeholder is a real markdown image tag using the
native title attribute:

```markdown
![The On disk pane, with Journal and memory connected](images/pending/windows-ondisk.png "CAPTURE: Settings > On disk, Journal and memory row, Connect button visible, light theme, 1280x800")
```

The alt text is reader-facing and ships to screen readers. The title is the
capture instruction. They are different audiences wanting different sentences,
and one string cannot serve both without becoming bad alt text or a vague spec.

A useful accident makes this cheap: `lint_wiki.py:186` already calls
`target.split()[0]` to strip a title before resolving a link, so the existing
code handles this syntax without being taught anything.

Two blockers the protocol has to clear, both confirmed:

1. The linter's `MD_LINK` regex is `\[[^\]]*\]\(([^)]+)\)`, which matches
   `![alt](path)` as well as a normal link. A placeholder with no file behind it
   is reported as `dead-link` today, so it fails CI and blocks the publish. The
   `images/pending/` prefix becomes a known state reported as a warning.
   Everything outside that prefix still fails as a dead link.
2. Publish copies no assets, so images cannot reach the wiki at all.

Fulfillment is a separate pass, by hand or by an agent driving Puppeteer, reading
the queue from `lint_wiki.py --figures`. The queue command is what makes this a
pipeline rather than a convention: without it, placeholders scatter across 26
files and nothing knows what is outstanding.

Video is deferred. Markdown has no video element, GitHub wiki renders raw
`<video>` inconsistently, and a committed mp4 is heavy in a wiki repository. A
link with a poster frame is the later answer.

## Order of work

**Phase 1, foundation.** No agent changes, so the corpus improves even if the
rest slips.

1. `wiki/page-types.md` with six types.
2. `wiki/style-guide.md`.
3. `_index.md` entries for both, and convention 3 in `developing.md` gains
   `type`.
4. `type:` stamped on all 26 pages.
5. `lint_wiki.py`: severities, the four error checks, the four warning checks.
6. `publish_wiki.py`: See also from `related:`, asset copy, placeholder strip.
7. `scripts/doc_graph.py`, and run it across the corpus to establish the
   baseline cluster map.

**Phase 2, pipeline.** The agent contracts and the skill.

8. Objectives written for all 25 surviving pages, and the five journeys.
9. `scripts/graph_lint.py`.
10. `.claude/skills/hearth-style/`.
11. Reviewer structural findings vocabulary.
12. Author restructure mode and figure placeholders.
13. Researcher code authority, corpus graph mode, consolidation verdict, and
    learning graph.
14. Orchestrator route and tracker column.

**Phase 3, proof.** Run the pipeline on real pages and measure.

15. `clients/windows.md`: restructure to platform overview, reference material
    flagged for extraction. This is the hardest path and the page that prompted
    the work.
16. The install cluster: salvage, fold, retire. See the consolidation protocol.
    This is the proof that the graph mode works, because the researcher should
    reach the same verdict recorded below without being told it.
17. The persona-creation gap: a how-to for making a persona outside first run.
    This is the proof that the learning graph works, because the gap was found
    by tracing a journey and by nothing else.
18. Re-measure `windows.md` against the A/B table. The target is the median
    paragraph and the paragraphs-over-40-words row, because those are the
    numbers that describe how the page reads.

## Carried notes

**Three pages still end in a dated status log**: `windows.md`, `macos.md`, and
`voice.md`. This is the failure `_index.md` was rebuilt to remove. Folded into
the platform overview and concept conversions rather than tracked separately.

## The learning graph

The duplication detector answers "which pages say the same thing." It cannot
answer "what should cover what," and it cannot see a subject the corpus never
covers at all. The learning graph is what answers both.

### Objectives

A learning objective is what a reader can do after reading a page, written as a
verb and an object, at a level from Bloom's revised taxonomy. The taxonomy and
the six page types turn out to be the same axis, which gives a consistency
check for free:

| Bloom level | Objective verbs | Page type that serves it |
| --- | --- | --- |
| Remember | list, name, identify | Reference |
| Understand | explain, describe, distinguish | Concept, Platform overview |
| Apply | install, configure, run | How-to |
| Analyze | diagnose, troubleshoot, compare | How-to, the troubleshooting shape |
| Evaluate | choose, justify, decide | Decision record |
| Create | build, design, compose | How-to, terminal on a journey |

A page declaring `type: concept` whose objectives are all Apply-level is
mistyped, and that is a finding rather than a judgment call.

### The graph

Nodes are objectives, each carrying its Bloom level and the page that teaches
it. Edges are prerequisites. A journey is a named reader goal: a path from an
entry state to a terminal objective.

Journeys to define first, from the audiences the corpus already implies:

- Understand what Hearth is before installing anything.
- Install Hearth and talk to it.
- Make my own persona.
- Run Hearth on a second device.
- Build and release Hearth.

### The graph linter

| Check | What it finds |
| --- | --- |
| Orphan page | Teaches no objective on any journey. The `delete` candidate. |
| Unreachable objective | An objective a journey needs that no page teaches. |
| Broken prerequisite | A page assumes an objective nothing earlier on the journey teaches. The reader hits a wall. |
| Duplicate objective | Two pages teaching one objective. A consolidation cluster with a reason rather than a score. |
| Parallel structure | Two pages, one shape, different subjects. Explicitly not a defect. |
| Type mismatch | The declared `type:` disagrees with the Bloom level of the page's objectives. |
| Journey dead end | A terminal objective unreachable from its entry point. |

### The worked journey, and the gap it found

"I am a new user and I want to make my own persona." Terminal objective, at
Create: build a persona with its own purpose, voice, and face.

Traced backward through the corpus, the path holds through installing, first
run, and what a persona is made of, and then it dead-ends. Both
`features/personas.md > Making your first one` and `first-run.md > Beat two`
describe only the guided onboarding flow, where Sulivan interviews you once.
Neither states how to make a second persona, or how to make one outside first
run.

The corpus documents persona creation as something that happens once, to you,
during setup. A reader who wants another one has nowhere to go.

No similarity metric finds this. It is not a duplicate and not a bad sentence:
it is an objective with no page. This is the class of finding only the graph
produces, and it is the reason to build one.

### The verdict vocabulary

Consolidation and the graph share four verdicts:

| Verdict | Meaning |
| --- | --- |
| `keep` | The survivor of a cluster. |
| `fold` | Content moves into the survivor, the page is retired. |
| `demote` | Moved to `raw/`. The repository already uses this for `component-catalog.md` and `portability-ledger.md`. |
| `delete` | No reader on any journey needs this. Nothing is salvaged. |

`delete` is a real option and the pipeline should not flinch from it. A document
that adds no value costs more than the space it takes, because it is a second
answer a reader has to rule out. The graph is what makes the call defensible:
"no journey traverses any objective this page teaches" is a reason, and "it felt
redundant" is not.

The guard: `delete` requires either that the page teaches no objective, or that
every objective it teaches is also taught by a surviving page. Deletion is the
only irreversible step in this plan, and `demote` to `raw/` is the landing when
the call is close.

## The consolidation protocol, worked on the install cluster

This is both a decision and the reference case for the graph mode. The
researcher should reach this verdict from `doc_graph.py` output without being
handed the answer.

`install-macos.md` is not a two-page collision. It is a three-way duplication:

| Compared to | Whole-document similarity |
| --- | --- |
| `clients/macos.md` | 0.80 |
| `installing.md` | 0.78 |
| `clients/windows.md` | 0.53 |

Four of its eight sections have a near-duplicate elsewhere. `## What you need`
scores 0.86 against `macos.md > What your Mac needs`.

`installing.md` is already the platform-parameterized page. It carries
`### macOS` and `### Windows` under `## Before you start`, each naming its own
hardware floor and download size. The structure was already built, and
`install-macos.md` is a second answer standing beside it.

The corpus also records an intention to repeat the mistake, in three places,
all of them found by `doc_graph.py --json` rather than by reading:

- `clients/windows.md`, `## Status`: "A dedicated Windows install guide,
  mirroring [Installing on macOS], does not exist yet."
- `installing.md`, `## Platform notes`: "A dedicated Windows install guide does
  not exist yet."
- `clients/macos.md`, `## Status and limitations`: "The Windows install guide
  does not exist yet; only macOS is documented."

So the plan on record is to build `install-windows.md` as a mirror of a page
already 78 to 80 percent duplicate of two others. That plan is cancelled, and
all three announcements come out with it.

**The verdict.**

1. Salvage the four sections `doc_graph.py` reports as not duplicated
   elsewhere: `## Starting and stopping the backend`, `## Uninstalling`,
   `## When something goes wrong`, and `## What this does not cover yet`. Also
   the unsigned-app right-click-Open step, which `installing.md` cites as
   living only on the macOS page.

   The salvage bar is "not duplicated" rather than "shares no vocabulary". A
   section whose closest match anywhere is 0.33, against a section about
   something else, is not covered by that match, and retiring its page would
   lose it. Conservative is correct in front of the only irreversible step in
   this plan.
2. Fold them into `installing.md` under its platform sections, retitled
   `### Install Hearth for macOS` and `### Install Hearth for Windows`.
3. Retire `install-macos.md`. Remove `installing.md`'s `## Platform notes`
   section, which exists only to explain the split.
4. Point `clients/macos.md` and `clients/windows.md` at their own platform
   section, and drop `macos.md`'s `## Installing` section in the same change.
5. Update `_index.md`, which currently links `install-macos.md` under Getting
   started, and every `related:` block naming it.

Nothing is deleted before step 1 lands. The salvage list is the gate.

The corpus becomes 25 published pages, and all five client pages become one
type.

### The wider boundary question

The install cluster is the sharpest case, not the only one. Four pages cover the
beginning: `getting-started.md`, `installing.md`, `first-run.md`, and
`install-macos.md`. `first-run.md`'s `## Beat one: install` alone runs 172
lines.

| Section pair | Similarity |
| --- | --- |
| `installing.md > What comes next` and `getting-started.md > Three steps to a running house` | 0.62 |
| `first-run.md > Three beats` and `getting-started.md > Three steps to a running house` | 0.51 |
| `installing.md > Updating, briefly` and `clients/macos.md > Updating` | 0.76 |
| `features/personas.md > Voices, briefly` and `features/voice.md > How a persona gets a voice` | 0.70 |

The last two name a pattern worth its own rule: a section labeled "briefly"
that drifted into being a second full copy of another page. Deciding what covers
what across these four pages is graph work, not similarity work, and it waits
for the objectives.

## Verification

Phase 1 and 2 hold the existing loop:

```
python scripts/lint_wiki.py
python scripts/publish_wiki.py --out <dir>
```

The linter must report zero errors. Warnings are expected and are the calibration
signal. Publish must render 26 pages plus `_Sidebar`, and after the `related:`
change every page with a populated `related:` block gains a See also section.

Phase 3 is measured, not asserted. The A/B table above is the baseline for
`windows.md` and the same script re-runs against the rewritten page.
