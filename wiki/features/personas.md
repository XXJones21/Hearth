---
title: Personas
status: open
type: concept
last_reviewed: 2026-09-03
related:
  - ../first-run.md
  - ../backend/voice-engine.md
sources:
  - backend/harness/valar/gateway/first_run.py
  - backend/harness/valar/gateway/personas_api.py
  - backend/harness/valar/tools/handlers/creation.py
  - backend/harness/valar/tools/tools.yaml
  - backend/harness/valar/data/persona_template.json
  - backend/harness/valar/persona/engine.py
  - backend/harness/valar/persona/__init__.py
  - desktop-client/src/components/personas/PersonasView.tsx
  - wiki/first-run.md
  - wiki/backend/voice-engine.md
---

# Personas

A persona is a companion of your own design, living on your machine. Hearth is
built around this idea: you do not configure a chatbot, you make someone, and
that someone is who greets you from then on.

## What a persona is made of

Every persona carries the same six parts, whether it is the one that ships
with Hearth or one you make yourself:

- **Name.** What you call them.
- **Description.** A short sense of who they are, used elsewhere in the
  product to describe them.
- **System prompt.** Written in their voice, not a generic template. It
  states who they are, their temperament, and how they speak.
- **Temperament.** The disposition behind the system prompt.
- **A designed voice.** A handful of instruct attributes, such as pitch,
  age, and accent, that produce a reference clip. See
  [Voice](voice.md) for how that clip becomes speech.
- **A color.** A single hex value that themes the sphere, the particles,
  and the four state colors (idle, listening, thinking, speaking) throughout
  the app.

A made persona also learns a small vocabulary of non-verbal tags it can place
inline in a reply, such as `[laughter]` and `[sigh]`, which the voice engine
performs rather than reads aloud.

## Making your first one

The first time you open Hearth, Sulivan, the persona who ships with the
product, interviews you to make your first persona together. It is a
conversation, not a form: he asks one thing at a time, acknowledges what you
just told him before moving on, and follows an interesting answer rather than
working down a list. Where a question is hard to answer cold, he offers a few
options as a card you can tap, but your own typed words always override the
suggestions.

The opening is the same on every install, and it begins: "Let us make
someone together. A persona is a companion of your own design who will live
here with you." From there you decide what this companion is for, their
temperament, their voice, and their color, and Sulivan writes the system
prompt in their words once he has enough to describe them to someone else.

When the persona is ready, Sulivan says goodbye in his own scripted farewell
and hands the house over: "I will step back now, but I am never far; call on
me whenever you need me." From that turn on, the new persona speaks for
themselves, and greets you first.

Once the handover completes, your new persona hosts one more beat:
introducing you to your second brain, the memory layer where Hearth keeps
what you tell it, and asking what you are actually working on to start your
first project there. See [The second brain](second-brain.md).

## Making another one

First run happens once. The moment your first persona is written the
interview expires for good, so it is not the route to a second persona. You
ask instead: a persona you made can make another persona, because they are
born holding the one tool that does it, `create_persona`.

The grant is that narrow. The `personas` tool domain holds exactly one tool,
so a persona who has it can make someone new and nothing else. It does not
let them edit a persona, remove one, or switch the house to another.

Making a persona this way is a plain conversation rather than the first-run
interview: no scripted opening, no card to tap, and no schema behind the
questions. You say who you would like, and once your persona could describe
that someone to a stranger, they compose the six parts and make them.

Nothing needs restarting. The new persona exists as soon as their folder is
written, because Hearth finds personas by reading the directory rather than
by remembering a list it loaded at startup. The house does not switch to
them. You keep talking to the persona you asked, and switch to the new one
by name.

> **Note:** A persona made before 2026-09-03 does not carry this grant. It
> reached the template new personas are built from, and nothing rewrites a
> manifest that already exists. Two routes work for an older house: switch to
> Sulivan, who holds the domain, and ask him, or grant the `personas` domain
> to your own persona on the Personas page your client carries, described
> under [Changing a persona later](#changing-a-persona-later).

## Where a persona lives

Each persona is a folder under `personas/`, named after them. Inside it sits
a manifest, `<name>.json` (the lowercased directory name), holding the system
prompt, the visualization colors, the model configuration, and the voice
settings. A `voice/` subfolder holds the designed reference clip and its
transcript, for example `personas/Wren/voice/wren_voice_reference.wav`
alongside `wren_voice_reference.txt`.

These are plain files. You own them: they are readable in a text editor,
and nothing about a persona lives anywhere else. The persona engine reads a
manifest the first time it loads that persona and holds it from then on, so
an edit you make by hand takes effect when the house next starts rather than
the next time you switch. A folder with no matching manifest is not a persona
Hearth will see.

Persona names collide case-insensitively: if `Wren` already exists, `wren`
is rejected, because the underlying filesystem cannot tell them apart.

## Voices, briefly

A persona's voice is designed once, at creation, from the instruct
attributes you and the interview settled on: pitch, age, and accent among
them. Every sentence they speak afterward is cloned from that reference clip
rather than redesigned. The clip is not permanent, though: the Personas page
can point a persona at another clip already sitting in their folder.

If voice design is unavailable on your machine when a persona is made, the
persona still exists and their voice is recorded as pending. Nothing picks
that up later. There is no retry and no sweep at startup, and a voice is only
ever designed inside persona creation.

Until a persona has a clip they do not borrow another persona's voice. The
engine refuses to speak rather than putting words in the wrong mouth, so a
persona in that state needs a clip pointed at them on the Personas page
before they can say anything.

The full mechanics, including the two engines behind the voice and their
differences, are in [Voice](voice.md) and
[the voice engine](../backend/voice-engine.md).

## Switching and multiple personas

Hearth can hold more than one persona at once. The persona engine keeps a
directory of everyone you have made and loads whichever one is current;
switching to another persona by name makes them the one who answers you next.
Internal personas used for routing, and personas marked desktop-only, do not
appear in a client's persona picker, but any persona can still be switched to
by exact name. Each client also pins, in its own settings, the persona it
asks for when it connects: that is who greets you on that device.

## Changing a persona later

A persona you made is not fixed. The desktop client, the iPhone, and Android
each carry a Personas page, and editing needs nothing switched on first. You
can change who a persona is, how they speak, what they are allowed to do, and
the prompt they think from, and hear a candidate voice before committing to
it.

![The Personas page, with a persona open for editing](../images/pending/personas-changing.png "CAPTURE: desktop client, Personas page with a persona you made selected, showing the Who they are, Voice and What they may do sections and the Save and restart button, developer mode off, 1280x800")

Two things behave differently from making a persona. Saving an edit restarts
the house, and that restart is what makes the edit take effect, because a
manifest is read once and then held. Making a persona restarts nothing.

Removing a persona sits behind developer mode, which also swaps the panel for
the raw manifest. Even then, a removal renames the persona's folder rather
than deleting it, so what you wrote is still on disk, and the default persona
cannot be removed until you have set another.

The iPhone and Android write far less than the desktop. On the iPhone you can
edit the system prompt and the state colors, on Android the system prompt
alone, and neither can remove a persona.
