---
title: Page types
status: closed
type: reference
last_reviewed: 2026-09-03
related:
  - style-guide.md
  - developing.md
  - _index.md
sources:
  - https://developer.apple.com/documentation/visionos/introductory-visionos-samples
  - https://developer.apple.com/documentation/realitycomposerpro/realitycomposerpro-essentials-addingentitiestoscene
---

# Page types

Choose one of six shapes for every page in the wiki, and write to it.

Every page in `wiki/` is exactly one type, declared in its frontmatter as
`type:`. The type decides the shape, and the shape is what a reader recognizes
before they have read a sentence.

Pick the type first. Most weak pages are weak because they are two types at
once: a concept page that turns into a procedure halfway down, or a landing
page that starts explaining architecture. When a page resists being one type,
that is the page telling you it is two pages.

For voice, terminology, and the rules that apply to every type, see the
[Hearth style guide](style-guide.md). For the five mechanical conventions the
linter enforces, see [Developing on Hearth](developing.md).

## Choose a type

Start from what the reader can do afterward. The verb points at the type.

| The reader will | Type |
| --- | --- |
| Find their way to the right page | Landing |
| Look something up | Reference |
| Carry out a task | How-to |
| Understand how something works | Concept |
| Know why a choice was made | Decision record |
| Learn what one client does on one platform | Platform overview |

A page whose declared type disagrees with what its sections actually do is
mistyped, and that is worth fixing before any sentence in it is polished.

## Open every page the same way

All six types share an opening, following Apple Developer article structure.

- **Title.** A topic or gerund phrase naming the subject. Sentence case.
  Matches the frontmatter `title`.
- **Abstract.** One sentence, immediately under the title, before any heading.
  Action verb plus object plus context, keywords early. Not a summary of the
  page: a statement of what the reader gets. Apple's *Introductory visionOS
  samples* uses "Learn the fundamentals of building apps for visionOS with
  beginner-friendly sample code projects."
- **Section headings.** Action titles: imperative verb plus specific object.
  *Add a persona*, *Install the house*, *Verify the voice*. Never `Step 1`,
  never `Overview of X`, never `Miscellaneous`. Keep them parallel down the
  page.

Reference is the one type where noun headings are correct, because its
headings name the things being cataloged rather than actions to take.

## Landing

An entry point that routes. It carries almost no detail of its own, and a
reader who lands on it should leave within one screen.

**In the corpus:** [the wiki index](_index.md),
[What is not here](whats-not-here.md).

**Model:** [Introductory visionOS samples](https://developer.apple.com/documentation/visionos/introductory-visionos-samples).

**Shape:**

1. Title and one-sentence abstract.
2. An overview paragraph of two or three sentences saying who the page is for
   and what the set covers.
3. Topic sections, each a gerund or action heading grouping related pages:
   *Getting started*, *Installing the house*, *Living with a persona*.
4. One or two sentences of prose under each heading before its links, saying
   what the group is for and when a reader wants it. Never a bare list under a
   bare heading.
5. Human titles as link text, never filenames.

**Rules:**

- No architecture, no decisions, no procedures. If a reader can act on it here,
  it belongs on a page this one links to.
- Every published page appears exactly once, in exactly one section.
- The section order is the reading order for someone meeting the product cold.

## How-to

A reader with a task. They arrive knowing what they want and leave having done
it.

**In the corpus:** [Developing on Hearth](developing.md) is the model.
[Installing Hearth](installing.md),
[Building a Hearth release](releasing.md).

**Model:** [Adding entities and assets to a scene](https://developer.apple.com/documentation/realitycomposerpro/realitycomposerpro-essentials-addingentitiestoscene),
written by this repository's author.

**Shape:**

1. Title and abstract. The abstract states the outcome.
2. A short overview naming what the reader needs before starting, only if they
   genuinely need something. A prerequisite that no later step uses does not
   belong.
3. Action-title sections, one per task.
4. Numbered steps inside each section. One action per step, imperative mood,
   the fenced block under the step that needs it.

**Rules:**

- **Bold** for UI controls and menu items: click **File**, then **Import
  File**.
- Code voice for identifiers, paths, and file extensions: `.usd`,
  `hearth-probe`, `~/personas`.
- Name alternate paths with "Alternatively" rather than a second numbered list.
- A result note follows the action; it never replaces it. "The Inspector shows
  the new properties" is fine after a step, never as the step.
- Placeholders in angle brackets: `<install root>`.

## Concept

A reader who wants to understand something before or instead of doing it.
Personas, the second brain, the house feed.

**In the corpus:** [Personas](features/personas.md),
[The second brain](features/second-brain.md),
[The house feed](features/house-feed.md).

**Shape:**

1. Title and abstract.
2. What the thing is, in one paragraph, in the reader's terms rather than the
   implementation's.
3. Why it works the way it does, including what it deliberately does not do.
4. What it looks like in use, with a concrete example.
5. Links to the how-to pages that act on it.

**Rules:**

- Lead with the reader's model, not the class diagram. A concept page that
  opens with a file path has started in the wrong place.
- Name the limits. A concept page that only lists capabilities reads as
  marketing.
- No procedures. If steps appear, they belong on a how-to page this one links
  to.

## Decision record

Why something is the way it is, written once, so the question stops being
reopened.

**In the corpus:** [Native runtime](backend/native-runtime.md),
[Packaging options](backend/packaging-options.md).

**Shape:**

1. Title and abstract.
2. The decision, stated first, with its date. Not the journey to it.
3. What was chosen and what it costs.
4. The alternatives, each with the reason it lost, steelmanned rather than
   strawmanned.
5. What would reopen the question.

**Rules:**

- The decision goes at the top. A reader who stops after two sentences must
  still leave with the right answer.
- A rejected alternative is described in the past tense and clearly marked as
  rejected, in the same screen as its description. A reader must never be able
  to read a rejected approach as current guidance.
- When a decision is retired, grep the corpus for it before closing the task.
  The record is not the only page that mentions it.

## Reference

A catalog. The reader knows what they are looking for and wants to find it
fast, then leave. Tools, animations, ports, file layouts, flags.

**In the corpus:** [The tool catalog](backend/tool-catalog.md),
[The persona face](features/persona-face.md), and this page.

**Shape:**

1. Title and abstract.
2. One short orienting paragraph: what is cataloged here and how it is
   organized. Two or three sentences, not a concept page in miniature.
3. A stable spine, repeated without variation. Usually a table, sometimes a
   term list. Every entry carries the same fields in the same order.
4. Nothing after the catalog except links out.

**Rules:**

- **The spine does not vary.** If one entry needs a field the others do not
  have, either every entry gets that field or the exception moves to prose
  below the table.
- Noun headings are correct here. A reference heading names the thing, not an
  action.
- No narrative. A reference page that explains why is a concept page wearing a
  table, and the explanation belongs on the concept page this one links to.
- Sort by something the reader can predict: alphabetical, or the order the
  system itself uses. Never by when it was written.
- One row per thing. A row that needs a paragraph is a sign the catalog is
  carrying concept material.

## Platform overview

What one client does on one platform, and what it does not do yet. The reader
has that device, or is deciding whether to use it.

**In the corpus:** all five of [Windows](clients/windows.md),
[macOS](clients/macos.md), [iOS](clients/ios.md),
[Android](clients/android.md), and
[Apple Vision Pro](clients/visionos.md).

This shape is not invented here. Three of the five client pages converged on it
independently, and the two that did not are the two that read worst.

**Shape:**

1. Title and abstract.
2. **What it does today.** Present tense, capability only. What a reader can do
   with this client right now.
3. **The persona surface.** How the persona appears on this platform: the face,
   the voice, the window or the room.
4. **The one procedure that belongs inline**, usually pairing or first launch.
   One procedure, in how-to shape. Anything longer is a how-to page this one
   links to.
5. **What it needs.** Hardware, operating system, and what must already be
   running.
6. **What it cannot do yet.** Honest limits, in the present tense.

**Rules:**

- Installation lives on the install page, not here. Link to it. A platform
  overview that grows an install procedure has become a second install guide,
  which is how the corpus ended up with two.
- **No dated status log.** "What it cannot do yet" is the honest-limits
  section, and it is written as capability rather than as a changelog. A
  section that reads "as of 2026-08-06" belongs in a decision record.
- Reference material (install trees, process trees, port tables) moves to a
  reference page. A platform overview describes; it does not catalog.
- Keep the five sections in this order across every client, so a reader who has
  read one can navigate the next.

## What each type teaches

Each type serves a different level of understanding, which is another way to
check that a page is the type it claims. A page whose sections all teach the
reader to *do* something is a how-to, whatever its frontmatter says.

| Type | The reader can afterward |
| --- | --- |
| Reference | Name and find a specific thing |
| Concept | Explain how something works, and what it will not do |
| Platform overview | Describe what one client does, and its limits |
| How-to | Carry out the task |
| Decision record | Justify the choice, and say what would reopen it |
