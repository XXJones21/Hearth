---
name: hearth-style
description: >-
  Use when writing or grading any page under wiki/, README.md, or tasks/ in the
  Hearth repository. Loads the published style guide and page types as
  canonical, and carries the grading contract the writer agents share.
---

# Hearth style

The rules are not in this file. They are published in the repository, and this
file tells you where they are and what to do with them.

## Read these first, in this order

1. `wiki/style-guide.md` is canonical for voice, naming, density, and shape.
2. `wiki/page-types.md` is canonical for the six shapes. Every page is exactly
   one, declared as `type:` in its frontmatter.
3. `wiki/developing.md`, the "Writing documentation" section, carries the five
   mechanical conventions and is their only home.
4. `.claude/skills/technical-writing-style/SKILL.md` for generic craft that is
   not specific to this repository: Apple heading and SEO patterns, inclusive
   language, technical notation.

Where a Hearth page and the generic skill disagree, the Hearth page wins.

Do not restate these rules in an agent file, and do not carry a private copy.
They moved into `wiki/` precisely so that one source cannot disagree with
itself. If a rule seems missing, it belongs in `wiki/style-guide.md` and the
change goes there.

## Run the linter before you grade anything

```
python scripts/lint_wiki.py
python scripts/lint_wiki.py --warnings
```

**A finding the linter already reports is not a reviewer finding.** This is the
most important instruction in this file.

The one review artifact this pipeline produced before these rules existed found
nine items on a page: eight were style nits and the ninth was a `raw/` link the
linter catches. Zero structural findings, on a page with a 59-line catalog
section. That is what happens when the expensive judgment stage spends its run
on arithmetic.

The linter owns em dashes, emojis, sentence case, spelling, terminology, dead
links, frontmatter, reader drift, bold-lead blocks, long paragraphs, and long
sections. Read its output, then grade what it cannot see.

## What only a reviewer can see

These are the findings worth a run. Severity follows reader consequence.

| Finding | Detraction | What it means |
| --- | --- | --- |
| `wrong-type` | 2 | The declared `type:` disagrees with what the sections do. A page whose sections all teach the reader to carry out a task is a how-to, whatever its frontmatter says. |
| `type-mixture` | 2 | The page is two types at once. Most weak pages are weak for this reason. |
| `missing-spine` | 2 | A section the page's type requires is absent. |
| `term-list-as-prose` | 2 | A run of bolded-lead paragraphs that should be one list. The container collapsed, not the writing. |
| `unfollowable` | 2 | A procedure a reader cannot complete: a missing prerequisite, a missing entry point, a blocker presented as optional. |
| `no-abstract` | 1 | No one-sentence abstract under the title, before any heading. |
| `noun-heading` | 1 | Section headings are noun labels where the type calls for action titles. Reference is the exception. |
| `status-log` | 1 | A dated status section. `_index.md` was rebuilt to remove exactly this. |
| `missing-figure` | 1 | A section describes a surface a reader looks at and carries no figure. |
| `stale-claim` | 1 | A statement the source tree contradicts. Cite the file and line. |

A page starts at 10 and every open finding subtracts. A 10 means nothing
meaningful is left; if anything remains open, cap at 9.

## Figures

Where a section describes a surface a reader looks at, ask for a figure. Write
the placeholder; someone else captures it.

```markdown
![What the reader sees](images/pending/<page>-<slug>.png "CAPTURE: where to go, what to show, what state, size")
```

The alt text is for the reader and for screen readers. The title is the work
order. `python scripts/lint_wiki.py --figures` prints the queue.

Never imply an image exists, and never place a figure for a surface the page
does not describe.

## Learning objectives

A page's objectives say what a reader can do afterward. They use Bloom's
revised taxonomy, and the level implies the type, which is a consistency check
rather than a separate opinion.

| Level | Verbs | Type it implies |
| --- | --- | --- |
| Remember | list, name, identify | Reference |
| Understand | explain, describe, distinguish | Concept, Platform overview |
| Apply | install, configure, run | How-to |
| Analyze | diagnose, troubleshoot, compare | How-to, troubleshooting shape |
| Evaluate | choose, justify, decide | Decision record |
| Create | build, design, compose | How-to, terminal on a journey |

Write each as a verb and an object: *choose a model tier for your machine*, not
*understand model tiers*. One page carries between one and five.

## Duplication

```
python scripts/doc_graph.py
python scripts/doc_graph.py --json
```

It reports and does not decide. Similarity cannot separate duplication from
parallel structure: `clients/android.md` and `clients/ios.md` are the
highest-scoring pair in this corpus and both are correct, because they share
the platform overview spine while describing different platforms. Only the
objectives tell those apart.

Verdicts on a cluster are `keep`, `fold`, `demote` (to `raw/`), and `delete`.
`delete` is a real option and this pipeline does not flinch from it: a document
that adds no value costs more than the space it takes, because it is a second
answer a reader has to rule out.

The guard: `delete` requires either that the page teaches no objective, or that
every objective it teaches is also taught by a surviving page. Nothing is
retired before its unique sections land somewhere. Deletion is the only
irreversible step in this work.
