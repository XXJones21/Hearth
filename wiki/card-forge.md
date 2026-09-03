---
title: The card forge
status: draft
last_reviewed: 2026-09-03
related:
  - first-run.md
  - backend/build-pipeline.md
  - _index.md
sources: []
---

# The card forge
When a persona has something to show you that no existing card can carry, it
makes a new one. The card library grows by use rather than by release.

This article records a change of mechanism decided 2026-08-05. The idea is
unchanged; the way it works is completely different, and the old way could
never have shipped.

## What it was

The forge commissioned code. Calling `forge_card` wrote a null-returning React
stub into the client's source tree, added an import and a registry line through
marker comments, appended a spec to a plan file, and dispatched a coding run
that filled the stub in. The card appeared after the run finished and the client
was rebuilt.

It worked. Two cards were commissioned in conversation this way, and the loop
from operator dissatisfaction to a working card was genuinely the thing it
promised.

It also cannot exist in a product. On a machine that installed Hearth there is:

- no source tree, because the app is a compiled binary with bundled assets
- no Node, no npm, no Rust toolchain, and no reason for a user to have them
- no coding harness, because that is a personal tool and does not ship
- no way to rebuild without invalidating the application's code signature

Every one of those is fatal on its own. The dependency on a specific coding
executor was the least of the problems, and removing that dependency would not
have helped.

## What it is now

**The forge produces a layout, not a component.** A commissioned card is data:
a title, a template, and an ordered list of sections. It is saved where the
user's own data lives, loaded at startup, and rendered by a renderer that
already ships.

The consequences are worth stating plainly, because they are all the direction
you want:

- **It works in a packaged app**, since nothing is compiled.
- **It works on a small model.** Writing a JSON layout is a far easier task
  than writing a correct React component, which matters enormously when tier 0
  is a 2.3B model on a laptop.
- **It works immediately.** No run, no build, no waiting. The persona describes
  the card and the card is there.
- **It survives updates.** User cards are data in the user's directory, not
  patches to source that a new release would overwrite.
- **It needs no executor at all**, so any persona can do it, which is the
  actual requirement.

The cost is real and worth accepting: a commissioned card can only be made from
the vocabulary the renderer knows. A genuinely novel visual is not reachable
this way. Extending the vocabulary is a client release rather than a
conversation.

That trade is correct here. The value was never arbitrary code; it was that the
persona notices the shape of what it is trying to say and builds something that
fits it.

## The vocabulary

Already shipping, as `generated_view`. The forge adopts it rather than
inventing a second one.

**Templates** arrange the sections: `plain` stacks them, `brief` is a short
read, `hero_stat` makes the first section large, `comparison` lays them out in
two columns.

**Sections** are the primitives:

| Kind | Carries |
| --- | --- |
| `text` | a paragraph |
| `stat` | one number with a label |
| `stat_row` | up to four numbers side by side |
| `image` | a picture, by asset path |
| `grid` | a wrapping grid of cells, each with text and a style |
| `divider` | a rule |

`grid` was added 2026-08-05 after investigating whether a calendar was
reachable. It is the one shape that turns a fixed vocabulary into a general
one, because a calendar, a habit tracker, a seat map, a keypad and a swatch
board are all a grid of cells.

```json
{ "kind": "grid", "columns": 7, "heading": "August 2026",
  "cells": [ { "text": "S", "style": "muted" },
             { "text": "1", "style": "default" },
             { "text": "5", "style": "marked" },
             { "text": "",  "style": "empty" } ] }
```

**Cells are emitted unrolled, one object each, with a literal style.** There is
no loop and no condition, deliberately, and this is the decision the whole
design rests on.

Repetition and conditional styling are compression features for a human author.
A person writes a loop because typing forty-two cells is tedious. A model
already knows which days are marked and can emit forty-two objects directly.
Unrolling costs a few hundred tokens; in exchange it removes the entire
expression-language surface, and with it every place a small model could write
a predicate that is subtly wrong.

Two pieces of outside evidence support drawing the line here. Vercel Labs
published `json-render` in 2026 as the generic solution to this exact problem;
it has conditionals, templates and host-registered functions, and **no loops**.
And Adaptive Cards, which does have full templating, has it in order to
separate a human template author from a service supplying data. Hearth has one
model producing both, so the expression layer buys nothing and costs
correctness: a model writing a conditional must also emit the field it tests
and keep the two in agreement, which is strictly harder than putting the right
style on the right cell.

`style` is a closed set the host resolves to real CSS, so a persona never
authors a color or a class.

## The shape of the tool

Two halves. The first shipped on 2026-08-05; the second has not.

### `compose_view`, shipped

Putting a card on screen. Until this existed the renderer had no driver: the
only cards reaching a screen were built by the consult handlers, so a persona
could describe a layout in words and had no way to show one.

```yaml
compose_view:
  parameters:
    title:    string
    template: string   # plain | brief | hero_stat | comparison
    sections: array    # the layout, in the vocabulary above
```

The handler **cleans rather than validates**, which matters at small model
sizes. An unrecognized cell style falls back instead of passing through, a
column count is clamped, a bare string becomes a cell, and a section it cannot
parse is dropped while the rest of the card still renders. A model that gets one
section wrong should still get a card. Only an entirely empty layout is refused,
with an explanation the persona can act on.

### `forge_card`, still to do

Saving a composed card so it can be used again, which is what makes the library
grow rather than each card being a one-off.

`forge_card` keeps its name and its place in the conversation, and changes what
it does.

```yaml
forge_card:
  description: >
    Make a new card when nothing in the library fits what you are showing.
    Describe the layout; do not write code. The card is saved and available
    from now on.
  parameters:
    name:        string   # what this card is called, in the library
    purpose:     string   # one line: when should this card be used again
    template:    string   # plain | brief | hero_stat | comparison
    sections:    array    # the layout, in the vocabulary above
```

`list_cards` gains the saved cards alongside the builtins, so a persona can find
what it made last week.

## Where cards live

With the user's data, not with the application. Alongside the second brain
rather than inside the install, so that reinstalling does not lose them and
uninstalling does not orphan them.

A saved card is the layout plus its metadata: who made it, when, what it was
for. That last field is what makes `list_cards` useful to a persona months
later, and it is the field a person would forget to record.

## What is deliberately not here

**No approval gate.** The old forge had one, because commissioning wrote code
into a source tree and that warrants review. A layout made of five safe
primitives does not. If a card is wrong the persona makes a better one, which
takes seconds.

**No runtime code, and not because it is impossible.** This was investigated
properly on 2026-08-05 rather than assumed. See below.

**No data binding, yet.** A forged card is rendered with the values the persona
passes when it shows it. Cards that pull their own data on a schedule are a
larger idea and need the same decision the image card needed: who fetches, who
waits, and what the card does while it waits.

## Emitting a card reliably

Two findings that apply whichever shape a card takes, and both come from
measurement rather than preference.

**Constrain the grammar.** llama.cpp supports GBNF grammars that restrict the
sampler so only conforming tokens can be emitted, and it converts JSON Schema
into one automatically. Hearth already runs on llama.cpp, so this is available
today and should be mandatory for card emission. It matters at the sizes that
matter: measured JSON parse rates put a 3B model between 48 and 57 percent and
a 1.7B model at 26 percent. Tier 0 is a 2.3B model.

**Then reason first and constrain late.** Grammar constraint fixes syntax
completely and costs semantics. A study measuring exactly this on a
calendar-shaped task found schema validity rising to 100 percent while
executable accuracy fell from 91.5 to 48 percent, with the failures being
schema-valid and wrong. So the persona should work out what to show in ordinary
prose first, and a second short constrained pass should only serialise it. That
matches the pipeline shape Hearth already has.

The consequence for anyone testing this: **the metric is not whether the card
parsed.** At 2.3B the common failure will be a calendar that renders perfectly
with the wrong days marked. Instrument how often a card is valid and wrong.

## The escape hatch, and why it stays shut

Investigated on 2026-08-05, because "we cannot load code into a shipped app"
turned out to be wrong and the real reason is different.

A packaged, signed Tauri v2 application **can** load a plain ES module from
disk at runtime. The asset protocol serves `.js` as `text/javascript` with the
window origin in its CORS header, which is what a module fetch requires, and
that path needs no `unsafe-eval`. Executing JavaScript from a user-writable
directory does not touch or invalidate the code signature on Windows or macOS.
The only place it becomes a policy problem is the Mac App Store, which is not
the channel.

So the door is open. What closes it is reliability, not packaging: a model that
manages 26 to 56 percent on plain JSON will not produce reliably correct React,
and there is no grammar that can enforce correctness on a program the way one
can on a schema.

The precedent is also clarifying. There is no shipping example of
model-generated component code being mounted into a host application's live
component tree. Everything embedded selects from a registry. Everything that
genuinely generates, including Claude's own Artifacts, runs the result on a
separate origin inside a sandboxed iframe and treats it as a foreign document.
Google's Dynamic View does generate, with a frontier model and server-side
tools, and reports taking a minute or more per interface, which is the wrong
shape for a card that appears while someone is talking.

**If that door is ever opened, it is a different feature.** A plugin system is
not a bigger Card Forge. It would be off by default with explicit consent, in
the shape Obsidian uses, and its pixels would live in a sandboxed iframe on a
separate origin, in the shape VS Code and Artifacts use. It would not mount
into this application's React tree.

## Open questions

1. **Which section kind is missing next?** `grid` answered the calendar. Do not
   guess the one after it; watch what personas approximate and add that.
2. **Can a persona edit a card it made?** Making a better one is cheap, so
   editing may be unnecessary complexity. It becomes necessary the moment cards
   carry data bindings.
3. **Do forged cards sync between devices?** They are user data, so eventually
   yes, and that is the same question as syncing the second brain rather than a
   separate one.
4. **What happens to the two cards already commissioned the old way?** They are
   personal trading dashboards and do not ship, so nothing. But they are the
   only real examples of the loop working, and they are worth re-expressing in
   the new vocabulary as a test of whether it is rich enough.
