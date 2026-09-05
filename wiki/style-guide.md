---
title: Hearth style guide
status: closed
type: reference
last_reviewed: 2026-09-03
related:
  - page-types.md
  - developing.md
  - _index.md
sources:
  - https://developer.apple.com/documentation/realitycomposerpro/realitycomposerpro-essentials-workspaceoverview
---

# Hearth style guide

Write wiki pages that read the same way, name things the same way, and hold the
reader steady from one page to the next.

This page covers the craft: voice, naming, density, and shape. It is the
companion to [Page types](page-types.md), which decides what a page is, and to
the five conventions in [Developing on Hearth](developing.md), which the linter
enforces. Where this guide and a convention disagree, the convention wins.

## Name each thing once

One name per concept. Every alternative below is somewhere in the corpus today,
which is the problem.

| Concept | Use | Not |
| --- | --- | --- |
| The local server | **the house** | the backend as a separate thing, the harness, the gateway |
| The agentic harness the house runs | **the harness**, or **Valar** | the house, the backend |
| The LLM | **the model** | the mind, the brain, the language model |
| The reader | **you** | the user, the operator, someone, a tester |
| Install location | **the install root** | the folder you chose, the destination |
| Text to speech | **the voice engine**, `omnivoice.cpp` on first mention | the cpp engine, the compiled engine, tts-server |

The house is the backend. They are one thing with one name, and the name is
**the house**.

The harness is not the house. The harness is Valar, the agentic harness the
house runs, and it is a component inside the house rather than another word for
it. Both **the harness** and **Valar** are correct in prose, because Valar is a
product noun here and not only a path.

## Write to the reader as "you"

Reader-facing pages address the reader as *you*. Not *the user*, not *the
operator*, not *someone*, not *a tester*.

Engineering-record pages under `backend/` may describe a third party (*the
client*, *the supervisor*) as an actor, because the reader there is not the
person performing the action. That is the one exception, and it is about who
acts, not about how to sound.

Keep the reader stable down the page. A page that opens *Before you begin* and
later says *Before users can* has changed who it is talking to mid-article.

## Use a term list when you are naming things

When a section introduces several named things, each with a short definition,
write it as a list: the term in bold, then one line that defines it. Do not
write a run of bolded-lead paragraphs.

This is the most common structural fault in the corpus, and it is the
difference between a page that scans and a page that does not.

Do this:

```markdown
- **Lock or unlock asset.** Locks the asset and prevents changes.
- **Show or hide asset.** Toggles the asset in the viewport.
- **Filter.** Type to narrow the list to matching items.
```

Not this:

```markdown
**Lock or unlock asset.** Locking an asset prevents changes to it, which
matters because the editor treats a locked asset as immutable and will refuse
edits that would otherwise silently apply, and this is separate from hiding...

**Show or hide asset.** Hiding an asset removes it from the viewport but not
from the scene, so it still exports, which is a distinction worth drawing...
```

Both forms carry the same information architecture: a bolded term introducing a
thing. Only the first one can be scanned. Eleven items in the first form read in
ten seconds; eleven in the second form is a wall.

If a term genuinely needs a paragraph, it is not a list item. Give it its own
section with an action-title heading.

## Keep paragraphs short

Aim for a paragraph that states one idea and stops. As a working target, most
paragraphs run under 40 words, and a paragraph over 60 words is a signal to
split it or turn it into a list.

Lead with the action or result, then the context. Vary sentence length. Cut
stacked adjectives and empty intensifiers.

## End a section before it sprawls

A section that runs past roughly 200 words either gains H3 headings or becomes
two sections. A section covering more than one subject is already two sections
regardless of length.

The test: name what the section is about in one phrase. If the phrase needs an
"and", split it.

## Ask for a figure where a reader needs to see

Where a section describes a surface a reader looks at, a window, a pane, a
control, a layout, it carries a figure. Text describing a visual arrangement is
a description of a picture that would have been faster.

When the image does not exist yet, write the placeholder and let someone
capture it later:

```markdown
![The On disk pane, with Journal and memory connected](images/pending/windows-ondisk.png "CAPTURE: Settings > On disk, Journal and memory row, Connect button visible, 1280x800")
```

The alt text is for the reader and for screen readers. The title, after the
path, is the capture instruction for whoever takes the screenshot. They are
different audiences, so they get different sentences. Keep placeholders under
`images/pending/` until the file lands.

## Use callouts for what must not hide

| Callout | Use for |
| --- | --- |
| **Tip** | Optional help, shortcuts, alternate patterns |
| **Note** | Useful context that is not blocking |
| **Important** | Blocking requirements, access needs, or data-loss consequences inside a procedure, where they would otherwise sit mid-paragraph |

Keep the body to one idea. Use the shape the page already uses, normally
`> **Tip:**` or `> **Important:**`. Do not invent callout types beyond these
three.

A requirement that already sits in a prerequisites list stays a bullet there.
Promoting it to **Important** in the same section says the same thing twice.

## Shape a procedure the same way every time

One shape, corpus-wide: an action-title heading, then an ordered list, then a
fenced block under the step that needs one.
[Developing on Hearth](developing.md) is the worked example.

- One primary action per step, in imperative mood.
- Sequential UI actions are an ordered list, never comma-stacked prose.
- A short result clause may follow the action in the same step. It never
  replaces it.
- Do not prefix a heading with `Step 1`. The step numbers live in the list.

Three other shapes are in the corpus and are being retired: step-number
headings, bolded-lead prose, and unlabeled prose sections.

## Write link text as human titles

`[Installing Hearth](installing.md)`, not `` [`installing.md`](installing.md) ``.

The wiki publishes flat, where a reader navigates a sidebar of titles and never
sees a directory. Descriptive link text also has to name its destination:
*see [how connectors work]*, never *click here* or a bare URL in running text.

## Spell it American

`normalized`, `behavior`, `color`, `organized`, `recognized`, `catalog`,
`summarized`. The corpus is mixed and the British forms are the ones to change.

## Mark superseded content so it cannot be read as current

A `SUPERSEDED` banner covers the section it opens, not the page. If a decision
invalidates content further down, either fix that content in the same edit or
give it its own banner.

A reader must never be able to read a rejected approach as current guidance.
When you retire a decision, grep the corpus for it before you close the task.

## Say which product a page describes

`wiki/` documents Hearth as a product a stranger installs. Valinor is the
personal testbed and superset, and it is a separate repository.

A page compiled from a Valinor audit is a Valinor document until someone
re-verifies it against Hearth. Say which one it describes, in the first
paragraph, and put the Valinor sources in `sources`.

## Punctuation

Convention 5 bans em dashes and emojis. When you reach for a dash, use one of
these instead:

- **Comma** for a brief aside.
- **Colon** when introducing a definition, list, or explainer.
- **Period** when the second clause stands alone.
- **Parentheses** for asides that interrupt the main thread.

Hyphens in compounds (`local-first`, `print-ready`) are fine.

Serial comma always. One space after a period. Avoid exclamation marks outside
direct quotes.

## Words to avoid

Replace on sight. These are weak verbs and common filler.

| Replace | With |
| --- | --- |
| utilize, leverage | use |
| ensure | make sure, or state how |
| robust | the specific behavior |
| seamless, seamlessly | delete, or describe what made it smooth |
| crucial, critically | delete, or quantify why |
| delve | look into, study |
| navigate the complexities of | handle |
| at scale | an explicit number |
| best-in-class, state-of-the-art, cutting-edge | delete, or name the comparison |

Strike these constructions on sight:

- *"It's not just X, it's Y."*
- *"Moreover,"* / *"Furthermore,"* / *"Additionally,"* opening a sentence.
- *"At its core, [thing] is [definition]."*
- *"Crucially,"* / *"Importantly,"* / *"Notably,"* opening a sentence.
