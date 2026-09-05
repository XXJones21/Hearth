---
name: technical-writing-style
description: >-
  Use when drafting or reviewing technical documentation and needing style
  rules for voice, clarity, headings, SEO, inclusive language, technical
  notation, or anti-LLM wording. Shared by the technical-writing-reviewer
  agent and future drafting agents.
---

# Technical writing style

Shared style rules for technical documentation. Foundation is curated from the Apple Style Guide (voice, clarity, inclusive language, technical notation), plus heading/SEO patterns from Apple Developer sample articles and a personal anti-LLM layer. Do not load the full Apple PDF.

Canonical heading and SEO sample: [Playing spatial audio](https://developer.apple.com/documentation/visionos/playing-spatial-audio-in-visionos) (title *Playing spatial audio*; abstract *Create and adjust spatial audio in visionOS with RealityKit.*; section heads such as *Create the axis visualizer*, *Play the spatial audio*, *Control the spatial audio*).

Read files under `references/` only when the dispatch prompt or task names that pack.

In the Hearth repository, do not use this file alone. Load the `hearth-style` skill, which reads `wiki/style-guide.md` and `wiki/page-types.md` as canonical and carries the grading contract. The two Hearth packs that used to live under `references/` are retired pointers now, because their content is published in `wiki/`. Where a Hearth page and this file disagree, the Hearth page wins.

## Voice

- Clear, direct instructional voice.
- Prefer **active** constructions. Address the reader as *you* when giving instructions.
- In procedures, prefer imperative or *you* + verb: *Open…*, *Select…*, *Confirm…* — not *the page shows* / *status is shown* as the main instruction.
- Do not anthropomorphize products or systems for decisions or intent. Stating UI result state is fine (*The Inspector shows the new properties*) when it follows an action you took.
- Prefer specific over abstract. Name the control, API, setting, or result.

### Active voice in procedures (required)

- One actor per instructional sentence, usually *you* (implied in imperatives).
- Avoid burying the action behind the UI chrome: bad *The Connectors page probes the upstream URL, so a connector that cannot…*; better put the **check** in a step, then one short result note.
- Flag stacks of UI verbs in one sentence (*Open…, select…, and confirm…*) — those belong in an ordered list (see UI steps).

## Clarity

- One idea per sentence when density rises.
- Lead with the action or result, then context.
- Cut stacked adjectives and empty intensifiers.
- Prefer short paragraphs. Use scannable headings and lists for procedures.
- Vary sentence length. Lead with the strongest verb.

## Structure, flow, audience, and perspective

Style polish is not enough. Before grading clarity high, reason across the page:

1. **Audience / perspective** — Who is *you*? Keep that reader stable section to section. Refer to other roles (*users*, *admins*) in third person when they are not the reader.
2. **Flow** — Adjacent sections must agree on actor, system, and what happens next.
3. **Claims vs work** — Setup statements, requirements, or earlier claims (when present) must match the procedures that follow.

Examples when a requirements or Prerequisites block exists (optional; many pages have none):

- Require only what later sections use, or scope a requirement to the section that needs it.
- Do not list a console or role that the next procedure never uses.
- A requirement is a starting capability, not a restatement of step 1.

Also flag:

- Same word, different systems (for example Tailscale policy `grants` vs product model `grants`) without a clear distinction.
- Audience drift (*Before you begin…* then *Before users can…* as if the reader changed).

Treat these as **clarity** findings even when local wording is clean. Deeper learning objectives and learning-graph structure are owned by a downstream agent; this skill only enforces page-level structure, flow, and perspective.

## Callouts

Use callouts for information that must not hide in **procedure body** paragraphs.

| Callout | Use for |
| --- | --- |
| **Tip** | Optional help, shortcuts, alternate patterns |
| **Note** | Useful context that is not blocking |
| **Important** | Blocking requirements, access needs, data-loss or security consequences **inside a procedure** where they would otherwise sit mid-paragraph next to UI chrome |

Rules:

- **Prerequisites are already the requirements list.** Do not convert a Prerequisites bullet into an Important callout in that same section. Keep Admin access (and similar) as a normal prerequisite bullet when that is where it belongs.
- Use **Important** when a blocking requirement appears in or beside a procedure (for example next to a nav snippet or before a click path) and would be easy to miss in prose.
- Do not invent callout types beyond Tip / Note / Important unless the doc set already defines them.
- Keep callout body short. One idea per callout.
- Prefer the same markdown shape already used on the page (for example `> **Tip:**` / `> **Important:**`).

Bad (Important inside Prerequisites — redundant and noisy):

```markdown
## Prerequisites
* Aperture on your tailnet
> **Important:**
> You need Admin access…
```

Good (requirement stays a prerequisite bullet):

```markdown
## Prerequisites
* Aperture enabled on your tailnet
* Admin access to the Aperture configuration
* Upstream service URL…
```

Good (Important beside a procedure, not in Prerequisites):

```markdown
## Configure grants

> **Important:**
>
> You need Admin access to the Aperture dashboard for this section.

[nav snippet]
1. Open …
```

## UI steps and visual components

Canonical UI pattern: [Building materials in Reality Composer Pro](https://developer.apple.com/documentation/realitycomposerpro/building-materials-in-reality-composer-pro) — sequential UI work uses **ordered lists** with **one primary action per step**, naming the pane/control then the action (*In the Project Browser, click [+]…*; *In the Inspector, click the Shader field…*).

Rules:

- Preserve UI paths and labels exactly (`**Administration** > **Configuration**`, bold UI names).
- Keep visual/UI affordances: nav snippets, screenshot placeholders, visual editor vs JSON editor choices. Do not delete them when relocating requirements.
- Missing CMS snippets stay unless the dispatch prompt says to replace them. Never invent UI chrome to fill them.
- **Sequential UI actions must be ordered lists**, not comma-stacked prose.
  - Bad: *Open the Connectors page, select the connector, and confirm its status shows Ready…*
  - Good:

```markdown
1. Open the **Connectors** page in the dashboard.
2. Select the connector.
3. Confirm the status shows **Ready** and the capability list includes the tools, resources, and templates you expect.
```

- One primary UI action per list item. Optional short result clause is fine in the same step (*… . The Inspector updates to show…*) when it is the immediate outcome of that click.
- Concept or reference material may stay in paragraphs or bullets; **do not** use paragraphs for multi-step click paths.
- Separate **requirement** (Important callout) from **navigation** (snippet / UI path) from **action** (ordered steps).

## Headings and SEO

Procedure and how-to pages follow Apple Developer article patterns: searchable titles, keyword-early abstracts, and **action titles** instead of numbered step labels.

### Page title (H1)

- Use a concise topic or gerund phrase that names the task and product keywords.
- Good: *Playing spatial audio*, *Get started with connectors*
- Avoid: *Guide to…*, *How to… (complete walkthrough)*, *Everything you need to know about…*

### Description / opening

- First sentence (or page description) states the outcome with primary keywords and product names early.
- Pattern: action verb + object + product/context. Example: *Create and adjust spatial audio in visionOS with RealityKit.*
- Overview body: say what the page demonstrates or covers, name the key API or feature in the first paragraph, then orient the reader.

### Section headings (H2 / H3)

- Use **action titles**: imperative verb + specific object (*Add a connector*, *Grant access*, *Verify the connection*).
- Match the Apple sample shape: *Create…*, *Set up…*, *Play…*, *Control…*
- **Do not** prefix headings with `Step 1`, `Step 2`, `Steps`, or `Step N:`.
  - Bad: `## Step 1: Add a connector`
  - Good: `## Add a connector`
- Numbered steps belong in ordered lists under the action heading, not in the heading text.
- Keep headings parallel across a page (same verb mood and specificity).
- Prefer words users search for (feature names, protocols, UI labels) over vague labels (*Overview* is fine for a concept section; *Miscellaneous* is not).

### Links and anchors

- Use descriptive link text that includes the destination topic (*see [How connectors work][…]*), not *click here* or bare URLs in running text.
- When you rename a heading, update in-page anchors and cross-references that pointed at the old `Step N` slug.

## Inclusive language

- People-first language. Use non-gendered defaults (*they* when gender is unknown).
- Avoid ableist metaphors and exclusionary idioms.
- Describe disability only when relevant to the topic.

## Technical notation

- Put code, API tokens, commands, and file names in code font (markdown backticks).
- Mark placeholders clearly (descriptive names such as `*username*` or `YOUR_API_KEY`).
- Keep syntax descriptions consistent. Do not invent new notation mid-document.
- Match UI label capitalization to the product UI when known.

## Fallback authorities

When this skill is silent:

1. Follow stated Apple Style Guide exceptions when they apply to the topic.
2. Otherwise use *The Chicago Manual of Style* for style and usage.
3. Use *Merriam-Webster's Collegiate Dictionary* for spelling (U.S. English).

## Personal layer: punctuation

No em-dashes. No double-hyphen em-dash proxies.

Zero `—` characters. Zero `--` pairs used as em-dash substitutes. Replace with:

- **Comma** for a brief aside.
- **Colon** when introducing a definition, list, or explainer.
- **Period** when the second clause stands alone.
- **Parentheses** for asides that interrupt the main thread.

Literal hyphens in compounds (`local-first`, `print-ready`) are fine.

### Other punctuation

- Serial (Oxford) comma always: *"Python, Rust, and TypeScript."*
- One space after a period. Never two.
- Avoid exclamation marks outside direct quotes.

## Personal layer: words to avoid

Replace on sight. These are weak verbs or common LLM defaults.

| Replace | With |
| --- | --- |
| utilize | use |
| leverage | use |
| ensure | make sure (or state *how*) |
| robust | specific behavior (*"recovers from disconnects"*) |
| seamless / seamlessly | delete, or describe what made it smooth |
| crucial / critically | delete, or quantify why |
| holistic | delete |
| harness (as verb) | use |
| delve | look into, study |
| navigate (figurative) | handle, work through |
| navigate the complexities of | handle |
| underscore | show |
| pivotal | central, key |
| embark | start |
| realm | field, area |
| at scale | replace with an explicit number |
| best-in-class | delete, or name the comparison |
| state-of-the-art | delete unless citing a benchmark |
| cutting-edge | delete |
| transformative / transformational | delete |

## Personal layer: LLM-tell phrases

Strike on sight:

- *"It's not just X, it's Y."*
- *"Moreover,"* / *"Furthermore,"* / *"Additionally,"* at sentence start. Delete the transition word.
- *"In today's [fast-paced / rapidly-evolving / dynamic] [world / landscape / environment]."*
- *"At its core, [thing] is [definition]."*
- *"Crucially,"* / *"Importantly,"* / *"Notably,"* at sentence start.
- *"This is more than X. It's Y."*
- Triple-parallel constructions for rhythm alone when one item is redundant.

## Out of scope

- Resume and cover letter conventions
- Full Apple A–Z product terminology
- Microsoft and Meta packs until added under `references/`
