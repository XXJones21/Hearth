---
title: First Run
status: draft
last_reviewed: 2026-08-04
related:
  - backend/build-pipeline.md
  - backend/portability-ledger.md
  - _index.md
sources:
  - D:/Tools/Valinor/tasks/first-time-user.md
  - D:/Tools/Valinor/hearth-pitch/mockups/hearth-setup-flow.html
---

# First Run

What happens between someone downloading Hearth and having a companion that
knows something about them. The visual reference is
`hearth-pitch/mockups/hearth-setup-flow.html` in the Valinor repository,
seventeen screens built against the real client shell.

## Three beats

The whole experience is three movements, in this order, and the order is the
design.

1. **Install.** The client is the installer. One download, a hardware scan, a
   model chosen for this machine, and a verification pass that proves it works.
2. **Make someone.** Sulivan interviews the user and they build a persona
   together. He is the only resident at this point, and he says so.
3. **Give them a memory.** The persona just created sets up the second brain
   and takes one real thing into it.

Beat three belongs to the new persona, not to Sulivan. A persona whose first
act is to introduce themselves reads as software. A persona whose first act is
to build something for you reads as alive, and it gives them a reason to exist
within ninety seconds of being made.

## Beat one: install

### The client is the installer

The user downloads the desktop client and nothing else. This is the pattern
ComfyUI Desktop and Ollama both use: a small installer, then first run detects
the hardware and provisions everything to match.

It also removes a question the draft had to ask. "Is this a client or a host
machine?" is unanswerable by a stranger and unnecessary to ask: the client
always installs, then either provisions a backend here or connects to one it
found. Same-host detection, designed for a different reason in
`tasks/desktop-client-macOS.md`, is the mechanism.

### The scan is not only about picking a model

Every hardware constant the portability ledger flags is a value this scan
should produce instead: the model and quantization, the context size, the
offload depth, the CUDA architecture, the accelerator backend, and whether the
brain and the voice can be resident at the same time. Doing it once, at install,
is what turns a machine-specific configuration into a generated one.

Two rules learned expensively and worth encoding:

- Use `nvidia-smi` for video memory, never WMI. `Win32_VideoController.AdapterRAM`
  reports 4 GB for a 16 GB card because the field is 32-bit and overflows.
- Check free disk against Windows, not against the distro. Inside WSL the root
  filesystem reports far more space than the host actually has, because the
  distro disk is a growing virtual disk on the system drive.

### Say what you found, and be honest about it

The scan reports back rather than proceeding silently: the machine, the tier it
implies, the itemised download, and one sentence on why that model. This is the
moment the draft calls "cool, downloading this."

Where the machine is small, say so plainly and in the user's language. On 8 GB
the brain and the voice cannot both stay resident, and the honest phrasing is
"your persona will think and speak one at a time," not a note about VRAM. The
user then chooses knowingly instead of discovering a pause mid-sentence and
assuming the product is broken.

### Verification is part of the install

Starting is not the same as working, and this product fails silently in at
least five ways: a missing package yields a healthy-looking gateway with no
memory and no voice, a missing YAML parser yields an empty tool registry that
looks exactly like tools being switched off, a missing memory tree yields empty
recall, and a misconfigured voice endpoint yields silence.

So the installer checks each capability and names it in plain terms: the mind is
loaded and answering, the voice is ready, hearing is ready, skills are
available, the second brain exists and is empty. An installer that cannot tell
you it failed is worse than no installer, because it converts a loud problem
into a silent one and moves the cost onto someone with no way to diagnose it.

The last check is one no automated probe can perform. **Sulivan speaks.** If the
user hears him, the mind that wrote the words, the voice that said them, and
the machine underneath both are all working. Only a human can confirm sound came
out of the speakers, so the screen offers "I heard him" and "I didn't hear
anything" as equals.

## Beat two: making someone

### It is a conversation, not a questionnaire

The mockup shows five questions in a fixed order. That is a simulation of the
shape and not the specification. A fixed questionnaire produces a form, and the
point of the beat is that it does not feel like one.

Three pieces, deliberately separate:

| Piece | What it is |
| --- | --- |
| The direction | A skill document Sulivan loads during first run. Says what a persona needs, not what to say. |
| `choice_card` | A card he emits mid-conversation, with options he wrote himself |
| `create_persona` | One tool call, at the end. The commit, not the interview. |

The conversation is the model's job and it is already good at it. The tool does
the thing the model cannot: write a correct file.

### The direction

Loaded when a machine has exactly one persona and no history. It states what has
to be true at the end and leaves the route open.

**Come away with:** a name, a sense of what they are for, a temperament, a
voice, a colour, and enough of a picture to write a system prompt in their voice
rather than Sulivan's.

**Getting there:** one thing at a time. Acknowledge what was just learned before
asking the next thing, by name, so it reads as listening. Offer options when a
question is hard to answer cold, and let a typed answer override them entirely.
Follow an interesting answer rather than returning to a list.

**Stop** when you could describe this person to someone else. Four exchanges is
usually enough, seven is too many, and if they give you everything in one
paragraph, take it and move on.

**Do not** read out a questionnaire, ask for everything at once, ask the user to
write a system prompt, or offer a temperament you would not want to talk to.

The last line of the direction is the one that matters: **you are making this
person with them, not for them.** The user should feel like the author.

### `choice_card` and dynamic options

Options are composed per question, so someone who has already mentioned they are
a nurse gets different suggestions than someone who writes code. This rides the
generative UI seam that already exists, where a persona composes an element as
part of speaking rather than the client owning a fixed screen.

```yaml
choice_card:
  props:
    question: string
    options: [{ label: string, detail: string }]
    allow_free_text: bool
```

### `create_persona`

Called once. Six arguments, because a persona file has roughly eighty fields
and a conversation only produces six of them.

```yaml
parameters:
  name:          string
  description:   string
  system_prompt: string   # Sulivan writes this, in their voice
  temperament:   string
  voice_id:      string
  colour:        string   # hex; drives the entire visualization block
```

Everything else is expanded by the handler: the visualization block is a colour
ramp from one hue producing the sphere, the particles, and all four state
colours; the model paths come from the install scan rather than literals; chat
templates and stop tokens are boilerplate for the model family; tool grants are
defaults for a resident persona.

**One problem to solve rather than discover.** The persona engine caches by name
at load, and the existing apply route handles that by exiting the process and
letting the supervisor restart it. That is correct for editing a persona from a
settings page and fatal here, because the process would die in the middle of the
conversation that created it. Adding a persona needs cache invalidation, not a
process exit.

## Beat three: the second brain

In the new persona's voice, and argued from self-interest rather than features.

1. **Why it matters.** "Right now I'll forget this conversation the moment it
   ends. Let's fix that."
2. **What it actually is.** Plain folders on disk, readable in any text editor,
   deletable at any time, going nowhere. Show the four they get: things with an
   end, things that never end, what was talked about by day, things worth
   keeping.
3. **Take one real thing.** Ask what they are working on and make it the first
   project. An empty brain is intimidating; a brain with one true thing in it is
   a start.

**Seed empty. Never clone.** This is a standing constraint rather than a
preference. The memory layer currently hard-codes one person's path in two
modules with no environment override, and it carries a hand-maintained table of
that person's projects. Both have to become configurable before this ships. See
the portability ledger, section 8.

## Open questions

1. **How many beats in the persona conversation?** The mockup shows five. Four
   is probably right and the direction should express it as a budget rather than
   a script.
2. **Which voices ship, and under what licence?** The mockup names four
   placeholders. The real list is whatever ships with the voice engine, and the
   licensing has not been answered.
3. **Where does the second brain live by default?** The mockup shows a documents
   folder. It needs to be somewhere a person can find, back up, and delete.
4. **What does teaching a custom voice look like?** Named in the draft, not yet
   designed, and it is the one remaining screen with no mockup.
