---
title: The Card Forge
status: draft
last_reviewed: 2026-08-05
related:
  - first-run.md
  - backend/build-pipeline.md
  - _index.md
---

# The Card Forge

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
| `divider` | a rule |

Five kinds and four templates is a small vocabulary, and the first thing to
learn from real use is which sixth kind is missing. Candidates already visible:
a list, a two-column key and value table, and a progress meter, which the
existing hand-built cards all implement privately.

## The shape of the tool

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

**No data binding, yet.** A forged card is rendered with the values the persona
passes when it shows it. Cards that pull their own data on a schedule are a
larger idea and need the same decision the image card needed: who fetches, who
waits, and what the card does while it waits.

## Open questions

1. **Which sixth section kind?** Do not guess. Ship the five, watch what
   personas try to express, and add the one that keeps being approximated.
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
