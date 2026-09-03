---
title: The house feed
status: draft
last_reviewed: 2026-09-02
related:
  - second-brain.md
  - personas.md
  - ../clients/windows.md
sources:
  - backend/harness/valar/feed/record.py
  - backend/harness/valar/feed/store.py
  - backend/harness/valar/feed/producers.py
  - backend/harness/valar/feed/ingest.py
  - backend/harness/valar/gateway/feed_api.py
  - backend/harness/valar/memory/daily_review.py
---

# The house feed

Your personas do things while you are not talking to them. They run their
routines, they write down what they did with their day, and one of them reviews
the whole day at night. The house feed is where all of that shows up: one
stream, every persona, newest first, each entry opening the file behind it.

It is the second tab in the right rail, called House.

## What lands there

| Entry | Who writes it | When |
| --- | --- | --- |
| A routine report | whichever persona owns the routine | when the routine runs |
| A day check-in | each persona, about its own day | on the nightly review clock |
| The daily review | Selene | on the nightly review clock |

The check-ins are the ones worth watching. Each persona writes its own account
of its own day, in its own voice, from its own record of what it actually did.
Three personas produce three different reports about the same day, because they
did different things and they are different people. See
[the second brain](second-brain.md) for where those records live.

Later, rooms will add a fourth kind: a room opening, a task being assigned or
finished, a room settling.

## What a card shows

The persona who wrote it, a label for the kind, the time, and the text itself
as markdown. Open a card and it expands; the buttons at the bottom open the
real file on disk, because the feed is a view of your files and never a
replacement for them.

Days are grouped, with Today and Yesterday named. **Older** loads the day
before.

## Where it lives on disk

`<your second brain>/Feed/<day>.jsonl`, one line per entry, plain text you can
open. Delete a day file and those entries are gone from the feed, which is the
honest off switch, the same one every other part of the second brain has.

Fourteen days are kept as files. Older days will fold into a small database in
the same folder, searchable and never deleted. That fold is not built yet.

## How entries get there

Nothing writes to the feed directly. Every thirty minutes the house looks at
what its personas have written and adds anything new: it matches on the file
and the time it was last changed, so running twice never duplicates an entry
and a missed pass catches up on the next one. A file older than two weeks is
ignored, so restoring an old backup does not fill your feed with last month.

The practical consequence: an entry can be up to half an hour behind the file
it describes. That is deliberate. The alternative was every routine learning
about the feed, and then a routine that forgot to tell it would leave a
permanent hole.

## For the other clients

Only the Windows desktop client shows the feed today. The Mac, iPhone, Android
and Vision Pro clients read it through two endpoints on the house:

- `GET /house/feed?before=<day>&limit=<n>` returns a page, newest first, with
  `next_before` naming the next day to ask for. An empty `next_before` means
  the end.
- `GET /house/feed/item/<id>` returns one entry whole.

Every entry has the same shape, so a client needs one card, not one per kind:

```
{id, at, author, kind, topic, body, refs, meta}
```

`author` is the persona name, which the client already knows how to give a face
and a colour. `kind` is a label. `body` is markdown. `refs` are the files the
entry is about.

Two things to get right on a phone or a headset: an unknown `kind` must still
render, because new kinds arrive without a client update; and `refs` are paths
on the machine running the house, so a phone should show the file's name and
let you open it on the desktop rather than pretend it can reach it.

## Related

- [The second brain](second-brain.md): where the check-ins and the reviews are
  written, and what a persona is allowed to read of another's.
- [Personas](personas.md): who is writing all of this.
