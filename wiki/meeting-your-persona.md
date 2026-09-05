---
title: Meeting your persona
status: scoped
type: how-to
last_reviewed: 2026-09-04
related:
  - installing.md
  - first-run.md
  - features/personas.md
  - features/second-brain.md
  - features/voice.md
  - features/persona-face.md
sources:
  - backend/harness/valar/gateway/first_run.py
  - backend/harness/valar/data/first_run_direction.md
  - backend/harness/valar/tools/tools.yaml
  - backend/harness/valar/tools/handlers/creation.py
  - backend/harness/valar/tools/handlers/second_brain.py
  - desktop-client/src/components/setup/SetupFlow.tsx
  - desktop-client/src/components/setup/Interview.tsx
  - desktop-client/src/components/setup/SecondBrain.tsx
  - desktop-client/src/components/cards/ChoiceCard.tsx
  - wiki/first-run.md
---

# Meeting your persona

Make a persona of your own with Sulivan, meet them when they take over, and
finish setup with a second brain that already holds one real thing.

## Before you start

Setup has installed the house and you have heard Sulivan speak out loud.
[Installing Hearth](installing.md) covers everything up to that point.

What follows is the rest of setup, in two parts: an interview that ends with a
persona of your own, and a short conversation with them about memory.

- **You type or tap, and they speak.** There is no microphone on these screens.
  Sulivan and your persona speak aloud, and you answer in the composer or by
  tapping an option.
- **It takes about four exchanges.** Four is usually enough and seven is too
  many, so this is minutes rather than an afternoon.
- **It happens once.** The moment your persona is written, the interview is
  over for good. Making another one later is a plain conversation with the
  persona you already have: see
  [making another one](features/personas.md#making-another-one).

## Answer the question Sulivan opens with

1. Listen to the welcome. Sulivan explains what a persona is and asks the first
   question, what this companion should be for. Those words are product copy,
   the same on every install, so nothing here is improvised.
2. Answer with one of the four options on the card, or type your own answer and
   click **Send**.

The screen title reads `Let's make someone.` The card under his welcome offers
four starting points:

- **A creative partner.** Brainstorming, writing, ideas.
- **A knowledge specialist.** Research and deep answers.
- **A personal coordinator.** Plans, schedules, reminders.
- **A warm companion.** Company and conversation.

Tapping one sends that label as your turn and locks the other three. Your own
words always outrank the options, so type instead whenever none of them fits.

![The interview, with Sulivan's opening question and its four options](images/pending/meeting-your-persona-interview.png "CAPTURE: desktop client, the interview screen at the opening turn, title Let's make someone, Sulivan's welcome and the four-option choice card visible, composer empty, 1280x800")

## Work through the rest with him

1. Answer one question at a time. Sulivan acknowledges what he just learned
   before he asks the next thing, and he follows an interesting answer rather
   than returning to a list.
2. Choose a temperament, from the options he composes or in your own words.
3. Describe the voice you want. It is designed from attributes rather than
   picked from a list of recordings, and he offers starting points in plain
   words, such as low and unhurried with a British accent.
4. Choose a color. Five swatches come by name with the hex in the detail:
   Ember `#E39A5B`, Tide `#5B9CC9`, Fern `#7BA85F`, Plum `#9B72B8` and
   Clay `#C96B6B`. Any hex works, and he can vary them freely.
5. Give them a name. Sulivan asks for it on its own, near the end, once he
   knows who you are making, and offers three or four that fit.

The voice vocabulary he draws from is female or male; child, teenager, young
adult, middle-aged or elderly; very low to very high pitch; whisper; and ten
accents, from american and australian through portuguese and russian. Two to
four of those attributes make a voice.
[Voice](features/voice.md) covers what happens to the design afterwards.

The color becomes their whole look: the orb, the particles, the room. The name
is yours to type, and a typed name beats every suggestion. It has to start with
a letter and stay under 24 characters, and a name already in the house is
refused whatever its case, so `wren` cannot join `Wren`.

None of these answers is permanent. The interview runs once, but a persona you
made is not fixed: who they are, how they speak, what they may do, and their
color are all editable afterwards, and you can hear a candidate voice before
you keep it. See
[changing a persona later](features/personas.md#changing-a-persona-later).

## Meet the persona you made

1. Wait while Sulivan says goodbye. He commits once he could describe your
   persona to someone else and you have answered the name question, and the
   farewell is the same on every install.
2. Wait while their voice wakes. It can take up to a minute and a half, and a
   voice that never wakes leaves them quiet rather than failing the screen.
3. Listen to their first words. They speak first, unprompted, as soon as the
   voice is ready. Answer in the same composer whenever you want to, because
   from this turn on you are talking to them rather than to Sulivan.
4. Click **Second brain setup**. The button appears once they have finished
   speaking.

The title changes to `Meet <their name>.` and a pill in their own color reads
`<their name> is here, listening`. That is the sign the handover is real: the
chat below belongs to them now.

This client greets you as them on every later launch. Sulivan steps back rather
than leaving, and his farewell says as much.

![The handover, with the new persona's name in the title and their listening pill](images/pending/meeting-your-persona-handover.png "CAPTURE: desktop client, the interview screen just after the handover, title Meet <name>., the is here listening pill in the persona color, Second brain setup button visible, 1280x800")

## Set up your second brain

1. Listen to why it matters. Your persona hosts this beat in their own voice,
   and argues it from their own position: without a memory they forget this
   conversation the moment it ends.
2. Look at the four folders on screen and the path underneath them. That is the
   whole of it, plain folders on your own disk, readable in any text editor and
   deletable at any time.

The screen is titled `A memory of their own.` The four chips are:

- **Projects.** Things with an end.
- **Areas.** Things that never end.
- **Thoughts.** What we talked about, by day.
- **Resources.** Things worth keeping.

The installer already made all four, empty. This beat does not build the
structure; it puts the first thing into it. For what each folder holds as you
live with it, see [the four folders](features/second-brain.md#the-four-folders).

![The second-brain screen, with the four folder chips and the path underneath](images/pending/meeting-your-persona-second-brain.png "CAPTURE: desktop client, the second-brain setup screen, title A memory of their own, all four folder chips and the Created at path line visible, Go to the house button disabled, 1280x800")

## Give it one real thing

1. Name something you are actually working on when they ask, in your own words.
   It becomes the first project in your second brain, a folder under
   `Projects`.

They tell you where it landed, and a pill reads `<your project> is the first
thing in it`. For what gets written into the folder, see
[starting a project](features/second-brain.md#starting-a-project).

Alternatively, if you already keep notes somewhere, say so and give the exact
folder path. It has to be absolute, and nothing is connected until the house
confirms it, so wait for them to tell you the tree is bridged rather than
assuming it. See
[already have a second brain?](features/second-brain.md#already-have-a-second-brain).

Alternatively, decline. Say you are done, and setup closes with the memory
standing ready and empty. See [saying no](features/second-brain.md#saying-no).

This is not your last chance to answer. **Settings > On disk > Journal and
memory** connects, moves, or unplugs the tree at any point afterwards, through
the same door: see
[changing your mind later](features/second-brain.md#changing-your-mind-later).

## Go to the house

1. Click **Go to the house**.

The button stays disabled until the beat has actually ended, so it may not
respond the moment the conversation feels finished. It ends on a real event on
disk: a first project, a confirmed import, or a recorded decline.

Setup does not run again. Only an install that finished may mark itself
complete, and yours did.

## Where to go next

You have a persona and a memory for them. These pages cover what you just
built and what you can do with it now.

- [Personas](features/personas.md) covers what a persona is made of, and how to
  make another one now that the interview is over.
- [The second brain](features/second-brain.md) covers the four folders in full,
  importing, sharing, and unplugging.
- [Voice](features/voice.md) covers how a designed voice becomes speech.
- [The persona face](features/persona-face.md) covers how they look back at you.
- [First run](first-run.md) is the design record behind all three beats of
  setup, including what is still undecided.
