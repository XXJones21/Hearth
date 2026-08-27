---
title: The tool catalog
status: draft
last_reviewed: 2026-08-15
related:
  - ../features/apps-and-extensions.md
  - ../card-forge.md
  - ../features/second-brain.md
sources:
  - backend/harness/valar/tools/tools.yaml
  - backend/harness/valar/tools/card_catalog.yaml
  - backend/harness/valar/tools/__init__.py
  - backend/harness/valar/tools/loop.py
  - backend/harness/valar/tools/handlers/
  - backend/harness/valar/gateway/voice_loop.py
  - backend/harness/valar/gateway/first_run.py
  - backend/personas/Sulivan/sulivan.json
  - backend/personas/Selene/selene.json
---

# The tool catalog

Every tool the house can offer a persona, what each one is for, and which of
them no persona can currently reach. [Apps and
extensions](../features/apps-and-extensions.md) is the product-facing version
of this idea; this page is the inventory and the audit behind it.

## How a tool reaches a conversation

Four gates, all of which must pass, and each of which has silently swallowed a
working tool at least once:

1. **The flag.** `HEARTH_TOOLS_ENABLED` must be set. Off means the tool loop
   never runs and the turn is a plain streamed answer.
2. **The registry.** An entry in `tools.yaml` with a `handler` that imports.
   `enabled: false` keeps an entry in the file and out of the registry.
3. **The persona's grants.** `tool_grants.domains` in the persona JSON selects
   by `domain` tag. A domain nobody grants is a tool nobody can call.
4. **The client's capabilities.** `requires_capability` is matched against what
   the client declared on connect, so a screen-only tool is not offered to a
   voice-only surface.

The per-session offered set is the intersection of all four. First run and the
second-brain beat override step 3 entirely with a fixed list
(`first_run.INTERVIEW_GRANTS`, `first_run.BRAIN_GRANTS`), which is why some
tools work during setup and are unreachable an hour later.

## The inventory

31 entries as of 2026-08-15, 27 of them enabled.

| Tool | Domain | Risk | On | Feeds card |
| --- | --- | --- | --- | --- |
| `calendar_read` | calendar | read | yes | |
| `calendar_write` | calendar | write | yes | |
| `claude_status` | dev | read | yes | |
| `consult_claude` | dev | write | yes | `terminal_card` |
| `append_file` | files | write | yes | |
| `list_dir` | files | read | yes | `permission_card` |
| `new_file` | files | write | yes | |
| `read_file` | files | read | yes | |
| `search_files` | files | read | yes | |
| `write_file` | files | write | yes | |
| `check_image` | media | read | yes | |
| `generate_image` | media | write | yes | `image_card` |
| `consult_memory` | memory | read | yes | |
| `recall` | memory | read | yes | |
| `remember` | memory | write | yes | |
| `news_headlines` | news | read | yes | |
| `choice_card` | projects | read | yes | |
| `compose_view` | projects | read | yes | |
| `list_cards` | projects | read | yes | |
| `forge_card` | projects | write | yes | |
| `create_persona` | projects | write | yes | |
| `start_project` | projects | write | yes | |
| `import_brain` | projects | write | yes | |
| `complete_brain_setup` | projects | write | yes | |
| `web_search` | search | read | yes | |
| `set_timer` | timers | write | yes | |
| `list_timers` | timers | read | yes | `timer_card` |
| `cancel_timer` | timers | write | yes | |
| `current_time` | timers | read | no | |
| `get_weather` | weather | read | yes | `weather_card` |

Risk is a blast-radius tag for policy hooks that do not exist yet: `read`
looks, `write` changes something on disk, `control` acts on the world.

## What the audit found

**The `projects` domain is granted to nobody.** Eight enabled tools sit behind
it, and neither shipped persona lists it: Sulivan grants
`weather, timers, search, news, memory, briefs, media, dev, files`, and Selene
grants `weather, news, memory, files`. That makes `list_cards`, `forge_card`,
`compose_view`, and `choice_card` unreachable in ordinary conversation, which
means **the Card Forge cannot be commissioned by the persona it was built for**
outside of first run. `import_brain` is in the same position, which is what
made Settings > Journal and memory necessary rather than merely convenient.

This is the single most consequential finding on this page. It is a one-line
fix per persona and a decision about whether "projects" is one domain or should
be split (`workshop` for the card tools, `brain` for the second-brain tools).

**Sulivan grants a domain that does not exist.** `briefs` matches no tool, and
the registry logs `unknown domain(s) ignored: ['briefs']` on every persona load.
Harmless, and a sign that grants are not validated against the registry.

**One tool is switched off.** `current_time` was deliberately retired when the
time became ambient context in every prompt. It is a tool correctly deleted
rather than a gap with a placeholder, and the difference matters when reading
the file.

`hass_call` was the other, and it is now gone rather than disabled: it pointed
at `valar.tools.handlers.smarthome`, a module that does not exist. Home
Assistant, Telegram and Google Calendar all left the registry and the panels on
2026-08-26. Hearth connects to nothing outside the machine, and integrations
that do are a later release taken deliberately. See
`tasks/third-party-integrations.md`.

The calendar used to be a third case and is now neither. `calendar_today` and
`calendar_next` were disabled entries pointing at a handler module that never
existed, and they assumed a Google-backed calendar. They are replaced by
`calendar_read` and `calendar_write` over the house's own store at
`$ENGRAM/Areas/Calendar/YYYY-MM.md`, ported from Valinor 2026-08-26. Nothing to
sign in to.

**`requires_capability` is set on nothing.** The fourth gate is built and
unused. Tools that only make sense with a screen (`compose_view`, `forge_card`,
`generate_image`) are offered to voice-only clients today.

**Five of thirteen cards have a tool behind them.** The rest are composed
through `compose_view` or emitted by a handler directly. A card with no
`data_source` and no composer path is a card nothing can put on screen.

## Twenty tools this house should have

Ordered by how often the absence has actually bitten, not by how interesting
they are to build. Each names the gap it closes. Two are built; the numbering
stays fixed so the list can be referred to by number.

### Documents and files

1. ~~**`search_files`**~~ — **built 2026-08-15.** Grep across the allowed
   roots. The scan budget is per root rather than shared, which is not a
   detail: with one budget, the first large folder walked consumed it and the
   tool reported "nothing matches" about folders it had never opened. A
   truncated search now says so and refuses to be read as proof of absence.
2. ~~**`append_file`**~~ — **built 2026-08-15.** Adds to the end of an
   existing file and carries its text directly. The rule that bodies never
   travel in tool-call JSON is about documents; a line is not a document, and
   making this one go through a brain call would rewrite text nobody asked to
   change.
3. **`rename_file`** / **`move_file`** — reorganise without leaving the
   conversation. Needs the permission card for a destination outside the roots.
4. **`delete_file`** — the only genuinely destructive file tool, so it needs a
   confirmation card of its own rather than the folder-grant card.
5. **`open_path`** — hand a file or folder to the operating system so the
   operator can look at it. The client can already do this; the persona cannot
   ask for it.

### Memory

6. **`forget`** — remove or correct a stored fact. `remember` writes and
   nothing unwrites, so a wrong fact is permanent until the file is hand-edited.
7. **`search_journal`** — full-text search across past sessions. The client has
   this endpoint; the persona has no tool for it and has to guess from recall.
8. **`list_projects`** — what is in the second brain right now. `start_project`
   can create one, and nothing can enumerate them.
9. **`update_project`** — append a decision or note under a project's
   `Key Decisions`. The daily review does this on a schedule; a conversation
   cannot do it on purpose.
10. **`session_summary`** — summarise and file the current conversation on
    request, rather than waiting for the idle timer or a New session click.

### Time and attention

11. **`create_reminder`** — a prompt at an absolute date and time. Timers are
    relative and in-process only; nothing survives a restart or reaches
    tomorrow.
12. **`calendar_read`** — the disabled calendar pair, given a real backend.
    "What is my day" is the most common question a companion cannot answer.
13. **`calendar_write`** — create and move events. Read-only calendar access
    covers half a use and invites the persona to describe changes it cannot
    make.
14. **`manage_routine`** — add, edit, and remove entries in `Areas/routines.md`
    from conversation. Today the record is edited by hand and the daily review
    is the only routine that exists.

### The world outside

15. **`fetch_url`** — read a page the operator names or that `web_search`
    returned. Search gives titles and snippets; nothing can open the result.
16. **`draft_email`** — compose into the mail client rather than sending.
    Sending is a trust question that a draft sidesteps entirely.
17. **`clipboard`** — read what the operator just copied, and put a result
    where they can paste it. The shortest path between the house and every
    other program on the machine.

### The house itself

18. **`house_status`** — what is running, which model is resident, how much
    VRAM is left. The client shows this; the persona cannot answer "why are you
    slow right now".
19. **`switch_model`** — change the resident model for the next turn. The
    machinery exists in the supervisor and has no conversational door.
20. **`play_media`** — control local playback. `media` currently means imagery
    only, and a companion that cannot start music is conspicuously missing a
    limb.

Two rules for anything on this list. It needs a **domain a persona actually
grants**, or it joins the eight tools nobody can reach. And it needs a decision
about **`requires_capability`**, because half of these are meaningless without
a screen.

## Adding one

One entry in `tools.yaml` and one handler function. The registry is the plugin
seam: `handler: valar.tools.handlers.<module>:<function>`, a `domain`, a
`risk`, an optional `speak` phrase for the thinking filler, and an OpenAI
function schema. Then grant the domain to a persona, or the tool exists and
nobody can call it.

Selection reliability falls as the tool set grows, which is the reason for
domains in the first place. A persona offered fifteen tools chooses better than
one offered twenty-nine, so the right question for a new tool is not "is this
useful" but "whose domain is it in, and is that persona already carrying too
much".
