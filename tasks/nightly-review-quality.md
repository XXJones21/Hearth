# Nightly review quality

The mechanism is proven; the writing is not. Raise the quality of Selene's
daily review so the review paragraph says what happened and the project
updates differ per project and carry real content.

Opened 2026-08-18, from the first nightly that produced project updates.

## Where things stand

The daily-review routine runs in the gateway
(`backend/harness/valar/memory/daily_review.py`, wired at `server.py:670`,
ticks every half hour, honors `Areas/routines.md`). Verified working
2026-08-18 00:12: `Reviews/daily/2026-08-17.md` written and two project
updates appended under `Key Decisions` in `Projects/hearth/claude.md` and
`Projects/valinor/claude.md`. That run was the first ever to produce a
nonzero project-update count, because recall and the review both read the
brain deeply only since the engram-mcp seam fix (Hearth `ea33cb7`).

## Landed 2026-08-19 (commit on feat/ios-qol-tier0)

The plumbing around the review was fixed while investigating "Sulivan says
nothing happened yesterday": chatlog-only days now count as pending and
feed the review raw; recall answers day-shaped queries from the review and
session list directly; the reviews shelf became a search scope
(engram-mcp `11da537`); Sulivan got a Memory Honesty section; the WSL
selene-review.timer was retired so only this routine writes the shelf.
What remains in THIS task is the writing quality below.

## The defects

1. **Vague review prose.** The 2026-08-17 review says "a reflective
   examination" and "a moment of structural contemplation" where the day
   actually held: the second-brain retrieval root cause found and fixed, the
   engram-mcp bundling shipped, the house restarted, the Hearth Vision spec
   written. The paragraph should name the work, not the mood.
2. **Duplicate generic project updates.** Both projects received the same
   line, "Reviewed progress on the Consumer Layer and Second Brain memory
   systems." An update should say what was done in THAT project that day,
   and a project that only got a passing mention should get no update at
   all.

## Where to look

- `_selene_task()` builds the prompt. It asks for "one short paragraph" and
  "one line of what was done" with no quality bar: nothing forbids mood
  prose, nothing demands concrete nouns (files, decisions, fixes), nothing
  says updates must differ per project or be omitted when the diary only
  mentions a project without work happening in it.
- The diaries are truncated (`_MAX_DIARY_CHARS` 4000, `_MAX_DIARIES` 8), so
  on a heavy day the model may see summaries of summaries; check what the
  2026-08-17 diaries actually contained before blaming the prompt alone.
- `_UPDATE_LINE_RE` accepts any `- <slug>: <text>` line; consider whether
  the parser should reject an update line that is identical to another
  project's, or that contains no concrete content.
- Style: the review is user-visible in the Journal. The house style guide
  applies (no em dashes, concrete over ornamental).

## Definition of done

- A re-run over the 2026-08-17 diaries produces a review that names the
  engram seam fix and the Vision spec, and per-project updates that differ
  and are true.
- A day where a project is only name-dropped produces no update for it.
- Prompt-only if possible; parser changes only if the prompt cannot hold
  the line.
