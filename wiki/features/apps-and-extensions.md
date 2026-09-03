---
title: Apps and extensions
status: draft
last_reviewed: 2026-09-03
related:
  - ../card-forge.md
  - ../first-run.md
  - personas.md
sources:
  - wiki/card-forge.md
  - backend/harness/valar/tools/tools.yaml
  - backend/harness/valar/tools/card_catalog.yaml
  - backend/harness/valar/tools/spec.py
  - backend/harness/valar/tools/loop.py
  - backend/harness/valar/tools/__init__.py
  - backend/harness/valar/tools/handlers/
  - backend/harness/valar/gateway/apps_api.py
  - backend/harness/valar/gateway/first_run.py
  - backend/personas/Sulivan/sulivan.json
  - wiki/first-run.md
---

# Apps and extensions

A persona grows in two directions: what it can draw on your screen, and what
it can do in the world. The first is a card, the second is a tool. This page
covers both surfaces and how a developer adds to each.

## Cards: what a persona draws

A card is a layout, not a component. When a persona wants to show you
something with a shape, such as a calendar, a set of figures, or a short
brief, it calls `compose_view` with a title, a template, and an ordered list
of sections written in a small closed vocabulary. There is no code involved
on either side: the persona writes JSON, and a renderer that already ships
turns it into pixels.

The templates are `plain` (stacks the sections), `brief` (a short read),
`hero_stat` (makes the first section large), and `comparison` (two columns).
The sections are `text`, `stat`, `stat_row`, `image`, `grid`, and `divider`.
`grid` is the general-purpose one: a calendar, a habit tracker, or a seat map
is all a grid of styled cells, emitted one object at a time with no loop and
no condition, because a small model can emit forty-two cells more reliably
than it can write and debug the loop that would produce them.

The `compose_view` handler cleans its input rather than rejecting it: an
unrecognized cell style falls back to a default, a bad section is dropped
while the rest of the card still renders, and only a completely empty layout
is refused. See [The card forge](../card-forge.md) for the full vocabulary
and the reasoning behind it.

Saving a composed card so it becomes part of the library, the second half of
the forge, is designed but not yet built: `forge_card` and `list_cards` are
specified in `backend/harness/valar/tools/tools.yaml` and disabled pending
that work. Two cards in `backend/harness/valar/tools/card_catalog.yaml`,
`choam_portfolio_dashboard` and `ticker_insight_card`, were commissioned
under an earlier mechanism that wrote React components directly; they predate
the data-layout approach and are not examples of it.

## Tools: what a persona calls

A tool is a verb: check the weather, set a timer, look something up, put a
card on screen. The registry lives at
`backend/harness/valar/tools/tools.yaml`, and each entry names a handler
function, so a complete tool is one YAML block plus one Python function.
Here is `get_weather`, unabridged apart from its parameter descriptions:

```yaml
- name: get_weather
  description: >-
    Get the weather for a place -- current conditions + the day's high/low...
  handler: valar.tools.handlers.weather:current_weather
  domain: weather
  risk: read
  speak: Let me check the weather.
  parameters:
    type: object
    properties:
      location: { type: string }
      units: { type: string, enum: [imperial, metric] }
      day: { type: string, enum: [today, tomorrow] }
    required: [location]
```

`handler` is a `module:function` reference, resolved by
`backend/harness/valar/tools/spec.py`. `domain` is the tag a persona's grants
select on. `risk` classifies the blast radius as `read`, `write`, or
`control`. `speak` is an optional short phrase the voice loop says while the
handler runs, covering the gap while a slower tool executes.

The handlers themselves live under
`backend/harness/valar/tools/handlers/`: `weather.py`, `timers.py`,
`web_search.py`, `memory.py`, `consult.py`, `imagery.py`, `claude_code.py`,
`compose.py`, `choice.py`, `creation.py`, `second_brain.py`, `forge.py`, and
`session_persist.py`. A handler is a plain function that takes the model's
arguments and returns a `ToolResult` (content, an ok flag, and an optional
data payload); it never touches the websocket, the session, or the brain
directly, which is what makes each one testable on its own.

A tool call is a two-step round trip, run by
`backend/harness/valar/tools/loop.py`. Valar sends the registry's schemas to
the model as `tools=[...]`. If the model answers with `tool_calls` instead of
prose, Valar runs `registry.invoke(name, args)` for each one, appends the
result as a `role: "tool"` message, and calls the model again for the final,
spoken answer. The loop caps itself at a small number of rounds and drops a
call that repeats one it already made in the same turn, so a model that gets
stuck on tool calls cannot stall a voice turn.

## The grant model

Not every persona sees every tool. The offered set for a session is enabled
tools, intersected with what the persona is granted, intersected with what
the connected client can render (`backend/harness/valar/tools/__init__.py`).
A persona's `tool_grants` names the domains it gets plus any individual tool
names to add or withhold. Sulivan, the persona that ships with Hearth, is
granted the domains `weather`, `timers`, `search`, `news`, `memory`,
`briefs`, `media`, and `dev`, which is the full daily set.

Grants also narrow by context, not just by persona. During first run, before
a resident persona exists, the interview session is granted no domains at
all, only two tools by name: `choice_card` and `create_persona`
(`backend/harness/valar/gateway/first_run.py`,
`INTERVIEW_GRANTS`). The interview cannot check the weather or search the
web; it can offer you choices and, once, commit the person you built.

## Adding a tool

1. Add an entry to `backend/harness/valar/tools/tools.yaml`: a name, a model-facing
   description, a `handler: module:function` reference, a `domain`, and a `risk`.
2. Write the handler function at that module path. It takes the arguments dict
   and returns a `ToolResult`.
3. Grant the tool's domain, or the tool's name directly, to whichever
   personas should have it, in that persona's `tool_grants`.

No pipeline code changes for a new tool; the registry and the loop are
generic over whatever `tools.yaml` lists.

## Where extensions live today

Hearth is pre-alpha, and this section says so plainly. Cards and tools are
both in-repo: `tools.yaml`, `card_catalog.yaml`, and the handler modules ship
inside the backend tree that installs with the client. There is no package
format, no signing, and no store.

The client does have a read-only view of what is connected, served from
`backend/harness/valar/gateway/apps_api.py` at `/apps/surface`. It derives a
list of "apps," bundles of tools, cards, and the personas granted to use
them, from the same `tools.yaml` and `card_catalog.yaml` a developer edits by
hand. Some of what it lists is live today, such as Claude Code and local
ComfyUI; some is defined but waiting on configuration, such as Home Assistant
and Google Calendar, which the surface reports as not configured or not
signed in. Turning a tool on or granting it to a persona through this surface
writes back to `tools.yaml` or the persona file and restarts the service to
pick it up; nothing here is a live, hot-swappable plugin socket. The file
also carries an empty slot for MCP servers, reserved so that discovered
servers can become apps once Valar has an MCP client, with no change to this
surface when that lands.

Until an extension format exists, adding a card or a tool means editing this
repository.
