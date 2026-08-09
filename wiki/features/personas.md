---
title: Personas
status: draft
last_reviewed: 2026-08-08
related:
  - ../first-run.md
  - ../backend/voice-engine.md
sources:
  - backend/harness/valar/gateway/first_run.py
  - backend/harness/valar/tools/handlers/creation.py
  - backend/harness/valar/persona/engine.py
  - backend/harness/valar/persona/__init__.py
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
- **A colour.** A single hex value that themes the sphere, the particles,
  and the four state colours (idle, listening, thinking, speaking) throughout
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

The opening line is the same on every install: "Let us make someone together.
A persona is a companion of your own design who will live here with you:
their purpose, their temperament, their voice, and their colour are all yours
to choose." From there you decide what this companion is for, their
temperament, their voice, and their colour, and Sulivan writes the system
prompt in their words once he has enough to describe them to someone else.

When the persona is ready, Sulivan says goodbye in his own scripted farewell
and hands the house over: "I will step back now, but I am never far; call on
me whenever you need me." From that turn on, the new persona speaks for
themselves, and greets you first.

Once the handover completes, your new persona hosts one more beat:
introducing you to your second brain, the memory layer where Hearth keeps
what you tell it, and asking what you are actually working on to start your
first project there. See [The second brain](second-brain.md).

## Where a persona lives

Each persona is a folder under `personas/`, named after them. Inside it sits
a manifest, `<name>.json` (the lowercased directory name), holding the system
prompt, the visualization colours, the model configuration, and the voice
settings. A `voice/` subfolder holds the designed reference clip and its
transcript, for example `personas/Wren/voice/wren_voice_reference.wav`
alongside `wren_voice_reference.txt`.

These are plain files. You own them: they are readable in a text editor,
and nothing about a persona lives anywhere else. The persona engine reads a
persona's manifest directly off disk when it loads or switches to that
persona, and a folder with no matching manifest is not a persona Hearth will
see.

Persona names collide case-insensitively: if `Wren` already exists, `wren`
is rejected, because the underlying filesystem cannot tell them apart.

## Voices, briefly

A persona's voice is designed once, at creation, from the instruct
attributes you and the interview settled on: pitch, age, and accent among
them. That single designed clip becomes their permanent reference, and every
sentence they speak afterward is cloned from it rather than redesigned. If
voice design is unavailable on your machine when a persona is made, the
persona still exists; their voice is recorded as pending and picked up the
first time the voice service is available, rather than borrowing another
persona's voice to cover the gap. The full mechanics, including the two
engines behind the voice and their differences, are in [Voice](voice.md) and
[the voice engine](../backend/voice-engine.md).

## Switching and multiple personas

Hearth can hold more than one persona at once. The persona engine keeps a
directory of everyone you have made and loads whichever one is current;
switching to another persona by name makes them the one who answers you next.
Internal personas used for routing, and personas marked desktop-only, do not
appear in a client's persona picker, but any persona can still be switched to
by exact name. Beyond that, day-to-day details of managing several personas,
such as a settings screen for editing or removing one, are not yet covered by
what ships today.
