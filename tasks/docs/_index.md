---
area: docs
updated: 2026-09-04
---

# Documentation

Work on the wiki, the style guide, and the pipeline that writes them. A file
belongs here when the deliverable is a page a reader opens, or the machinery
that produces one.

Product work that a page merely describes does not live here. When a
documentation pass finds a defect in the product, which happens often because
verifying prose against the source tree is what the research stage does, the
fix goes to the area that owns the code and this folder keeps the finding.

## What is here

| File | What it is | Status |
| --- | --- | --- |
| [tracker.md](tracker.md) | The live task matrix. The orchestrator is its only writer. | open |
| [artifacts/](artifacts/) | Agent handoff JSON, one file per stage per task. The evidence the tracker cites. | open |

The plan these tasks execute is
[documentation-pipeline.md](../development/documentation-pipeline.md), which
records the evidence, the eight deliverables, and the three phases.

## How the tracker works

One living file, not one per day. History is git, so
`git log tasks/docs/tracker.md` is the record a dated filename would otherwise
carry. Every task that is not `Complete` stays in the file and keeps its ID.

The orchestrator writes it and nothing else does. The researcher, author, and
reviewer return JSON artifacts, and those reach the tracker only through the
orchestrator, so a claim in the matrix is one a single stage is accountable
for.

`Agent State` records where a task actually is: `Backlog`, `Research`,
`Author`, `Review`, `Complete`. It flips before each dispatch rather than after
a result returns, so an interrupted run can tell a task in flight from one
nobody started.

## The one gate worth knowing

A `fold` or `delete` verdict is a decision to schedule, never an action to
take. The salvage tasks open first, every one of them reaches `Complete`, and
only then does the task that removes the page open.

Deletion is the only irreversible step in this work. `demote` to `wiki/raw/` is
the landing when the call is close.
