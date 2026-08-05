# Rendering UI defined after the app shipped

Research for the Hearth desktop client. The test case is a calendar card: month grid, day cells, some marked, a heading.

## Verdict

The shortest defensible path is to widen the section vocabulary by exactly one kind, a wrapping grid of cells, and let the model emit the cells unrolled with literal props. No loops, no expressions, no code.

The reasoning is that repetition and conditional styling are compression features for a human author. A model does not need them. A human writes `for day in month` because typing 42 cells is tedious; a model already knows which days are marked and can emit 42 cell objects with a literal `style` on each. Unrolling costs roughly 500 to 800 tokens and in exchange it deletes the entire expression-language surface: no `${...}` parser, no `$when` predicate evaluator, no data-binding scope stack, no place for a model to write a condition that is subtly wrong. Every system reviewed below that went past a fixed vocabulary immediately grew a small programming language, and each one is a language a small model has to be correct in.

Concretely, add one section kind:

```json
{ "kind": "grid",
  "columns": 7,
  "heading": "August 2026",
  "cells": [
    { "text": "S", "style": "muted" },
    { "text": "1", "style": "default" },
    { "text": "3", "style": "marked" },
    { "text": "", "style": "empty" }
  ] }
```

That is a calendar. It is also a habit tracker, a seat map, a swatch board, and a keypad. `style` is a closed enum resolved by the host to real CSS, so the model never authors a style value. This is the same move Adaptive Cards made with `Layout.Flow` plus `itemWidth`, and the same one DivKit and Vercel's `json-render` make: a general container plus a closed set of leaf kinds, rather than a new named kind per use case.

The general escape hatch, if one card kind is not enough later, is an interpreted element tree with an element whitelist and a style enum, described in section 6. Runtime evaluation of model-authored code is the thing not to do here, for reasons in section 5 that are about reliability at 2.3B parameters at least as much as they are about security.

## How far declarative goes

The yardstick: can it produce a month grid with marked days, given a model that emits the payload.

### Adaptive Cards

Adaptive Cards is the most developed answer to this exact problem and it goes further than most people assume.

**Layout.** Containers support three layouts: `Layout.Stack` (default), `Layout.Flow` (spreads elements horizontally and wraps to new rows), and `Layout.AreaGrid` (divides a container into named areas, elements placed via a `grid.area` property, with `row`, `column`, `rowSpan`, `columnSpan`). `Layout.Flow` takes `itemWidth`, `maxItemWidth`, `minItemWidth`, `itemFit: Fit | Fill`, `columnSpacing`, `rowSpacing`. Source: https://learn.microsoft.com/en-us/microsoftteams/platform/task-modules-and-cards/container-layouts

A calendar in Adaptive Cards is `Layout.Flow` with `itemWidth` set so seven items fit per row, then 42 `TextBlock` or `Container` elements in the body. It wraps into a month grid. This works. It is the direct precedent for the recommendation above.

**Tables.** A `Table` element exists as of schema 1.5, with `columns` (`TableColumnDefinition[]`), `rows` (`TableRow[]`), `TableCell` items, `firstRowAsHeader`, `showGridLines`, `gridStyle`, and a per-cell `style` drawn from the `ContainerStyle` enum (`default`, `emphasis`, `good`, `attention`, `warning`, `accent`). Per-cell conditional colour is therefore expressible as a literal enum value on each cell. Source: https://learn.microsoft.com/en-us/adaptive-cards/schema-explorer/table

**Repetition and conditionals.** The templating layer is where it becomes a programming language. Binding is `${expr}`. Any element whose `$data` is bound to an array is repeated once per item, with expressions scoped to the item. Reserved scopes are `$data`, `$root`, `$index`. `$when` drops an element when a predicate is false. Expressions run on the Adaptive Expression Language, a superset of the Logic Apps expression language, including `if(cond, a, b)`, `json(str)`, arithmetic, string functions, and host-registered custom functions. Source: https://learn.microsoft.com/en-us/adaptive-cards/templating/language

So `"style": "${if(isMarked, 'good', 'default')}"` inside a `$data`-repeated cell is a calendar with conditional styling, and the community pattern of repeating a `ColumnSet` or a `Container` per array item is documented. Source: https://adaptivecards.io/blog/2020/Templating-RC/

**Where it stops.** Two places, both instructive.

First, composition. The templating docs state plainly: "Currently there is no support for composing template 'parts' together." A template cannot call another template. That is the moment a declarative format stops being a document format and would have to become a language with functions, and Microsoft declined to cross it.

Second, the split between template and data. Adaptive Cards templating assumes a human authors the template and a service supplies the data. In Hearth's case one model produces both, which means the expression layer buys nothing. A model that writes `${if(isMarked, 'good', 'default')}` must also emit an `isMarked` field per day in the data, and must keep the two in agreement. That is strictly harder than emitting `"style": "marked"` on the right cells. The templating layer solves a separation-of-concerns problem Hearth does not have.

The version story is also a warning. The grid layouts arrived in 1.5, the Table element in 1.5, and the newer hub advertises `Icon`, `Badge`, `Carousel`, and `Chart.Line` beyond that. The vocabulary grew roughly one significant element per release for seven years and still does not include a calendar.

### Slack Block Kit

Much less expressive and honest about it. Blocks render into discrete chunks: header, section with an optional two-column field list, divider, actions row, image, context. Hard caps of 50 blocks per message, 100 per modal, 10 fields per section. There is no general grid and no repetition construct; the caller unrolls everything server side. A table block was added in 2025 for API-driven messages, and the stated reason tables were absent for so long is that a full grid breaks the chat layout on narrow screens. Source: https://api.slack.com/block-kit/building and https://api.slack.com/messaging/composing/layouts

A calendar in Block Kit is not reachable as a grid. The closest is a context or section block per week with pre-joined text, which loses the cells.

The useful lesson is the one Slack shipped by accident: their format has no expression language at all, and callers unroll. That is exactly the recommendation, arrived at from the other direction.

### DivKit

Yandex's open-source server-driven UI framework builds native views from JSON against a published JSON schema, with Android, iOS, Web, and Flutter renderers. It includes grid and container div types and is the closest open equivalent of a general element tree with a closed vocabulary. Sources: https://github.com/divkit/divkit and https://divkit.tech/en/

A calendar is reachable. The cost is that DivKit is a full cross-platform framework with its own expression syntax and its own schema toolchain, which is a great deal of surface to adopt for one card kind in a Tauri webview.

### JSON Schema form renderers

JSONForms and react-jsonschema-form solve a genuinely narrower problem: given a data schema plus a UI schema, render a form. Both dispatch to a registry of renderers, JSONForms by "testers" that score a renderer against a schema element, react-jsonschema-form by overridable `FieldTemplate` and `ObjectFieldTemplate` components. Sources: https://jsonforms.io/docs/tutorial/custom-renderers and https://react-jsonschema-form.readthedocs.io/en/v1.8.1/advanced-customization/

Neither reaches a calendar as a display artefact, because the tree they walk is a data schema, not a layout. They are worth noting only for the registry-plus-tester dispatch idea, which is the same shape as a whitelist renderer.

### Summary on the yardstick

A calendar is reachable declaratively, and the requirement is smaller than it looks. It needs exactly three things: a container that wraps at N columns, a way to emit many cells, and a closed style enum per cell. It does not need a loop, and it does not need a predicate.

## Server-driven UI, what the field learned

**Airbnb, Ghost Platform.** A single shared GraphQL schema across web, iOS, and Android, with strongly typed models generated for each. The unit is a "section", a primitive reusable block holding pre-formatted data, tagged with a `SectionComponentType` that selects the renderer, so one data model can render differently in different contexts. "Screens" own layout via `ILayout` implementations that adapt across breakpoints. Ghost Platform powers search, listing pages, and checkout. Source: https://medium.com/airbnb-engineering/a-deep-dive-into-airbnbs-server-driven-ui-system-842244c5f5

What they admit: "Server-driven UI is complex. Countless hours have gone into creating a robust schema, client frameworks, and developer documentation." What they list as still missing at the time of writing is nested sections, which is to say composition, the same wall Adaptive Cards hit. The post names no failure cases, and that absence is itself a data point: it is an engineering-brand post, not a retrospective.

**Lyft, Canvas.** Protocol Buffers rather than GraphQL, with primitives (buttons, layouts, action callbacks) defined in protobuf schemas and renderers on each client walking the hierarchy. The stated reasons for protobuf are compact binary encoding and built-in versioning. I found this only in secondary write-ups, not a Lyft primary source. Source: https://medium.com/@aubreyhaskett/server-driven-ui-what-airbnb-netflix-and-lyft-learned-building-dynamic-mobile-experiences-20e346265305

**Netflix.** The most useful single fact in this whole section: Netflix deliberately did not use server-driven UI for the core browsing experience, the row-scrolling home screen, judging that some surfaces are better as dedicated native implementations. Source: as above, and https://www.infoq.com/jp/news/2024/08/netflix-server-driven-ui

**Where practitioners say it breaks.** Consolidating the critical write-ups:

- Debugging degrades badly. A broken screen can originate in the payload, the schema, the renderer, a stale client version, an experiment flag, or a capability mismatch, and a crash log tells you none of it.
- Versioning is a permanent tax. The server ends up speaking several UI dialects at once because it must know which client versions can render which components.
- API surface expands quickly, and complexity leaks into the contract.
- Component proliferation is the failure mode with the sharpest phrasing: once the backend can compose screens, teams ask for knobs, flags, overrides, and exceptions, and "if nobody owns the design system boundary, server-driven UI becomes a form builder with brand colors."

Sources: https://github.com/MobileNativeFoundation/discussions/discussions/47 and https://nativeblocks.io/blog/best-practices-and-common-pitfalls/

**Read across to Hearth.** Three of the four costs do not apply. There is no fleet of client versions, no app store review, no multi-team design-system politics. The single cost that does apply is the debugging one, and it applies with more force, because the payload author is a small model rather than a backend engineer, so a malformed or semantically wrong card is a routine event rather than an incident. That argues for a schema simple enough that the renderer can validate a card fully before mounting it and fall back cleanly, which is achievable for a grid of literal cells and not really achievable for an expression language.

## Generated UI from models in 2026, and the select-versus-generate distinction

This is the section with the clearest answer. Almost everything shipping selects and parameterises. The two systems that genuinely generate are both consumer chat products that run the output in a browser-level sandbox, and neither embeds the result in the host application.

**Vercel AI SDK.** Documentation is unambiguous: "Generative UI is the process of connecting the results of a tool call to a React component." The developer pre-builds components, the model calls a tool, the developer inspects `message.parts` for a `tool-${toolName}` entry and its state (`input-available`, `output-available`, `output-error`) and conditionally renders the matching component. The model never emits component code. Source: https://ai-sdk.dev/docs/ai-sdk-ui/generative-user-interfaces

The 2026 additions reinforce this: AI Elements is a prebuilt component library and custom registry. The earlier RSC-based approach is paused. Sources: https://vercel.com/blog/ai-sdk-3-generative-ui and https://ai-sdk.dev/

**Vercel Labs json-render.** This is the most directly relevant artefact found, billed as "The Generative UI framework". It is an interpreted component tree. The spec is a flat map of elements with a root id:

```json
{ "root": "card-1",
  "elements": {
    "card-1": { "type": "Card", "props": { "title": "Hello" }, "children": ["button-1"] },
    "button-1": { "type": "Button", "props": { "label": "Click me" }, "children": [] } } }
```

Components are registered in two steps, a catalog of schemas defined with Zod, and a registry mapping catalog entries to real implementations. The catalog also generates the system prompt, including component descriptions, props schemas, and available actions. Expressions exist but are deliberately few: `{"$state": "/path"}`, `{"$cond": c, "$then": a, "$else": b}`, `{"$template": "Hello, ${/user/name}!"}`, and `{"$computed": "fn", "args": {...}}` which calls a host-registered function. Streaming is handled by a `SpecStreamCompiler` that renders partial specs as chunks arrive. Renderers exist for React, Vue, Svelte, Solid, React Native, Remotion, React PDF, React Email, Ink, React Three Fiber, and Satori. The stated properties are "Guardrailed: AI can only use components in your catalog" and "Predictable: JSON output matches your schema, every time". Source: https://github.com/vercel-labs/json-render

Notably, the README documents no iteration or repeat construct. Vercel Labs, building the generic version of this problem in 2026, shipped conditionals and templates and did not ship loops. The `$computed` escape hatch calls host functions, not model-authored ones. That is the same boundary recommended above, drawn by someone with no stake in Hearth's answer.

**Thesys C1.** Marketed as "the world's first API built for Generative UI": an LLM-compatible API that returns interfaces instead of text, paired with the Crayon React SDK, which "replaces a traditional markdown renderer" on the client. The component library is organised into Display Information, Form Elements, Triggers, and Data Visualization, with themeing and custom component registration. The docs do not disclose the wire format. The architecture, an API returning something a specific React SDK renders against a documented component library, is select-and-parameterise, not code generation, but I could not confirm the serialisation from primary documentation. Sources: https://docs.thesys.dev/ and https://docs.thesys.dev/library/index.md and https://www.infoworld.com/article/3971182/thesys-introduces-generative-ui-api-for-building-ai-apps.html

**Google Gemini, Dynamic View.** Genuine generation. The Google Research post's own pipeline diagram has the model emitting HTML, CSS, and JS to the user's browser, passed through post-processors, with tool access on the server side. Reported limitations are directly relevant: "Our current implementation can sometimes take a minute or more to generate results" and "There are occasional inaccuracies in the outputs", and their evaluation explicitly did not account for generation speed. Sources: https://research.google/blog/generative-ui-a-rich-custom-visual-interactive-user-experience-for-any-prompt/ and https://www.glbgpt.com/hub/what-is-gemini-3-dynamic-view/

A minute or more, from a frontier model with server-side tools, for one generated interface. That is the honest latency benchmark for genuine generation, and it is the wrong shape for a card that appears while a persona is talking.

**Claude Artifacts.** Also genuine generation, and the sandbox design is the reference implementation. Each artifact is a single-file payload running in a sandboxed iframe on a separate origin (`claudeusercontent.com`), isolated from the host app by the iframe `sandbox` attribute and Content Security Policy headers, with the code passed in over `window.postMessage()`. It has no filesystem, no shell, no access to host cookies or credentials, and network access constrained by CSP to an allowlist of CDNs. Sources: https://bloom.security/blog/claude-artifacts and https://www.reidbarber.com/blog/reverse-engineering-claude-artifacts

The structural point: the isolation is a separate origin plus an iframe, not a clever in-process wrapper. Generated code is treated as a different application that happens to be displayed nearby. Nothing in the Artifacts design lets generated code participate in the host app's component tree, and that is not an oversight.

**The distinction, stated plainly.** Everything intended to be embedded in a host application's own UI selects from a registry. Everything that genuinely generates runs the result in a separate origin or a sandbox and displays it as a foreign document. There is no shipping example found of model-generated component code being mounted into a host application's live React tree. The practitioner consensus is blunt: runtime-generated component code is "the most flexible and most dangerous approach", suitable for prototyping, internal tools, and sandboxed environments, while "production apps overwhelmingly" use tool-mapped components or declarative specs. Source: https://medium.com/@akshaychame2/the-complete-guide-to-generative-ui-frameworks-in-2026-fde71c4fa8cc

## Runtime evaluation, mechanisms, costs, security

If the model does emit code, here is what actually executes it.

**react-live.** Bundles Sucrase for transpilation and evaluates with the `Function` constructor, not `eval`. The evaluation path builds `new Function(...scopeKeys, code)(...scopeValues)`, passing scope names as parameters and the transpiled source as the body. Sources: https://github.com/FormidableLabs/react-live/blob/master/packages/react-live/src/utils/transpile/evalCode.ts and https://www.npmjs.com/package/sucrase

`new Function` is not meaningfully safer than `eval` against untrusted input. It does not close over the local lexical scope, which is the only real difference, but the constructed function still runs on the main thread with full access to `globalThis`, `window`, `document`, `fetch`, and every capability the host page holds. Shadowing globals by naming them as parameters is a convention, not a boundary: any global not explicitly shadowed remains reachable, and so does everything reachable from a constructor chain. react-live is a playground for code the developer wrote, and it is used that way.

Sucrase itself is fast because it does very little: it strips JSX, TypeScript, and Flow and passes everything else through unchanged, on the assumption of a modern runtime. Unsupported syntax (decorators, private fields, throw expressions, generator arrow functions, do expressions) is not transpiled and reaches the runtime as-is. Source: https://github.com/alangpierce/sucrase

**Babel standalone.** Babel's own documentation states it plainly: "If you're using Babel in production, you should normally not use @babel/standalone", and lists the intended use cases as prototyping and sites that compile user-provided JavaScript in real time, naming JSFiddle, JS Bin, and the Babel REPL. Source: https://babeljs.io/docs/babel-standalone

Size is the second problem. A Babel issue thread on making standalone smaller describes it as "almost 6 MB minified", and a community fork advertises a reduction to roughly 1.73 MB minified. I could not confirm a gzipped figure from an authoritative source. Sources: https://github.com/babel/babel/issues/14314 and https://github.com/haltcase/babel-standalone

For an offline-first desktop app that already ships a bundle, adding a multi-megabyte compiler to render a calendar is not proportionate. Sucrase is the smaller answer if a transpiler is needed at all.

**The CSP problem, specific to Tauri.** Tauri v2's guidance is to make the CSP as restrictive as possible, and Tauri appends its own nonces and hashes to the CSP for bundled assets at compile time. `unsafe-eval` is not part of the default posture; it is an explicit opt-in, and the docs only carve out `wasm-unsafe-eval` for WebAssembly frontends. Sources: https://v2.tauri.app/security/csp/ and https://github.com/tauri-apps/tauri-docs/blob/v2/src/content/docs/security/csp.mdx

This matters more than it first appears. Adopting `new Function` means adding `unsafe-eval` to the Hearth webview's `script-src`, which weakens the app globally and permanently in order to enable one feature. It is not a scoped grant. That single fact is close to decisive on its own.

**Is there a way to define a component at runtime without `eval` or `Function`?** Yes, three of them, in ascending cost.

1. **Interpret a tree.** Walk a JSON structure and call `React.createElement(registry[node.type], node.props, children)`. No parser, no compiler, no dynamic code. This is section 6 and it is the recommendation.
2. **Parse markup, do not evaluate it.** `htm` uses standard tagged template literals to produce hyperscript calls, with no build step, at about 1 KB alongside Preact's 3 KB. Sources: https://github.com/developit/htm and https://preactjs.com/guide/v10/no-build-workflows/ There is a catch worth stating clearly. `htm` avoids a compiler because the interpolations are real JavaScript values supplied by real surrounding code. If a model emits an `htm` string, nothing evaluates those interpolations without `eval`, so the honest version is a markup-only subset with literal attributes, at which point it is a tree serialised as text rather than as JSON, and worse for a constrained decoder. A related option is `html-react-parser`, which converts an HTML string to React elements without `eval`, but it does not sanitize and is explicitly not XSS-safe on its own; it needs DOMPurify or a Trusted Types policy in front of it. Source: https://www.npmjs.com/package/html-react-parser
3. **Run a different JavaScript engine.** `quickjs-emscripten` runs QuickJS compiled to WebAssembly, executing untrusted JavaScript with an explicitly constructed global environment. It is the strongest in-page isolation available without a separate origin. Sources: https://github.com/justjake/quickjs-emscripten and https://til.simonwillison.net/npm/self-hosted-quickjs The caveat from that ecosystem generalises: the sandbox is only as tight as what you inject into it, and exposing the host `fetch` hands untrusted code the host's cookies. Also, QuickJS cannot touch the host DOM, so a component running inside it has to communicate its output over a bridge, which is to say it has to serialise a tree of elements, which lands back at option 1 with an extra WASM engine in the middle.

**The security posture, stated honestly.** The threat here is not primarily a malicious local model. It is that the model's context contains text from elsewhere: calendar entries, emails, web content, Engram memories, tool results. Prompt injection is unsolved, and an injected instruction that causes a model to emit component code is a code execution primitive in a desktop app that also holds filesystem and shell capability through Tauri. Source: https://simonwillison.net/2023/Apr/14/worst-that-can-happen/ A tree interpreter converts that same injection into, at worst, a rude-looking card.

The correctness threat is separate and less discussed: "An agent that writes text can be annoying when it's wrong. An agent that renders UI can be dangerous", the example given being an incorrect payment amount on a confirmation card. Source: https://medium.com/@akshaychame2/the-complete-guide-to-generative-ui-frameworks-in-2026-fde71c4fa8cc

## Interpreted component trees, the middle path, assessed honestly

The shape: the model emits a tree of nodes with a `type` drawn from a whitelist and `props` validated per type, and a renderer walks it calling `createElement`. Shipping precedents are `vercel-labs/json-render` (catalog plus registry, Zod-validated props), DivKit (JSON schema to native views on four platforms), Airbnb's Ghost Platform (typed sections dispatched by `SectionComponentType`), and Shopify's Remote DOM, whose receiver API is "geared towards you providing an allowlist of custom elements that the remote environment can render, which allows you to keep tight control over the visual appearance." Sources: https://github.com/vercel-labs/json-render, https://github.com/divkit/divkit, https://medium.com/airbnb-engineering/a-deep-dive-into-airbnbs-server-driven-ui-system-842244c5f5, https://github.com/Shopify/remote-dom/blob/main/README.md

Shopify's system deserves a note because it is the most sophisticated version and it clarifies the boundary. Shopify runs genuinely untrusted third-party extension code, so they need both halves: a sandbox (Web Worker on web, WebView on Android, JavaScriptCore on iOS) where the extension's arbitrary logic runs, and a serialised element tree that crosses from sandbox to host over RPC, where the host renders only allowlisted elements. The production sandbox removes dangerous globals such as `importScripts` and replaces others with restricted versions such as a domain-limited `fetch`, and the sandbox script is served from a separate domain so the browser applies additional constraints. Source: https://shopify.engineering/remote-rendering-ui-extensibility

The lesson for Hearth is that the tree is the security boundary, not the sandbox. Shopify needs the sandbox because extensions contain live logic that must run somewhere. A Hearth card is a static picture of a month. There is no logic to host. Taking the tree half without the sandbox half is the correct subset.

**What goes wrong with tree interpreters, honestly.**

- **Styling is where the whitelist leaks.** An element whitelist is easy. A style whitelist is where people give up and accept a `style` object or a `className` string, and at that point the model is authoring CSS, which means it can position elements over the rest of the app, spoof host chrome, or load a remote background image and exfiltrate the fact that a card rendered. Closed style enums per element type avoid this; free-form style props do not. Every design decision here should push toward enums.
- **Props drift.** "Runtime prop mismatches" is named among the ways generative UI apps break in production. Source: https://medium.com/@akshaychame2/the-complete-guide-to-generative-ui-frameworks-in-2026-fde71c4fa8cc The mitigation is validating each node's props against a per-type schema before mount and dropping or substituting nodes that fail, which is what Adaptive Cards formalised as `fallback` and `requires`.
- **Vocabulary creep.** This is the real long-term risk and it is the "form builder with brand colors" failure. A tree interpreter makes it cheap to add a type, so types get added, and after two years there are ninety of them, no two composing cleanly. The counter is a hard rule that new types must be general (grid, not calendar) and that the model prompt is generated from the catalog so the cost of a new type is visible as prompt tokens.
- **Streaming and partial trees.** A partially arrived tree is not renderable without care. `json-render` addresses this with `SpecStreamCompiler`, and its flat `elements` map with a `root` pointer is a deliberate choice that makes partial specs tractable, since a node can arrive before its parent. If cards need to appear mid-utterance, copy that structure rather than a nested one.
- **Interaction.** The moment a card has a button, the tree needs actions, actions need a target, and targets are either a closed set of host-defined intents or an open channel. Keep them closed. `json-render`'s `$computed` calling host-registered functions is the right pattern.

**Whether Hearth needs a general tree at all.** Probably not yet. The existing renderer has four layout templates and five section kinds. Adding a `grid` section kind is a one-file change and handles the calendar plus a broad class of adjacent cards. A general tree is the correct destination if the second and third unknown cards turn out to be structurally different from each other, and the honest signal to watch is whether new requests keep arriving as "a grid of things" or start arriving as genuinely novel arrangements. Building the general tree now, before that evidence exists, would be building a framework on one data point.

## Reliability at small model sizes

This is where the recommendation stops being a preference and becomes the constraint.

**Small models are unreliable at plain JSON.** Measured JSON parse rates: Llama 3.2 3B at 47.8 to 56.5 percent, described as a regression versus Llama 3.1 8B, with the conclusion that "the 3B scale appears insufficient for reliable structured output". SmolLM2 1.7B Q4_K_M at 26.1 percent parse rate and 4.3 percent schema compliance. Gemma 3 4B at 100 percent parse rate but 87 percent schema compliance at Q4_K_M. Source: https://ascentcore.com/2026/04/01/small-llm-performance-benchmark/

A 2.3B model is inside the band where unconstrained JSON output cannot be trusted, and the quantisation used matters as much as the parameter count.

**Constrained decoding fixes syntax completely, and it is not optional here.** llama.cpp's GBNF grammars restrict the sampler's vocabulary at each step so only tokens conforming to the grammar can be emitted, and `common/json-schema-to-grammar.cpp` converts a subset of JSON Schema Draft 7 into GBNF automatically. Syntactically invalid output becomes impossible. Two caveats: generation can still stop mid-structure if the token budget runs out, and complex grammars slow generation measurably. Sources: https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md and https://deepwiki.com/ggml-org/llama.cpp/8.1-grammar-and-structured-output and https://til.simonwillison.net/llms/llama-cpp-python-grammars

Hearth already runs on llama.cpp, so this is available today and should be considered mandatory for card emission regardless of which approach is chosen.

**But constraint has a semantic cost, and the paper measured it on a calendar.** "The Constraint Tax" (arXiv 2605.26128) tests Qwen2.5-0.5B, Qwen2.5-1.5B, SmolLM2-1.7B, and Qwen2.5-3B. Aggregate: hard schema decoding raised schema validity from 61.5 to 100.0 percent, lowered answer accuracy from 19.7 to 11.0 percent, and raised the rate of outputs that are schema-valid but wrong from 49.5 to 88.9 percent.

The calendar-shaped result is the one that should govern the design. On a calendar tool-call analogue, both modes reached 100 percent schema validity, but prompt-only JSON scored 91.5 percent executable accuracy while hard schema decoding scored 48.0 percent, a drop of 43.5 points, with 102 of 104 failures involving wrong duration values. The recommended mitigation is "reason free, constrain late": let the model solve the problem in unconstrained output first, then package the answer into the schema in a second pass. Their expanded-interface study reached 40.7 percent accuracy at 100 percent validity with delayed constraints, beating direct schema decoding. They also recommend tracking wrong-valid-schema rate as a first-class metric, and measuring a prompt-only baseline before hard-constraining anything. Source: https://arxiv.org/html/2605.26128v1

Three consequences for Hearth.

1. **A schema-valid card can be a wrong card, and at 2.3B that will be the common failure.** Grammar constraint guarantees the calendar renders. It guarantees nothing about the 14th being marked. The metric to instrument is not parse rate.
2. **Two passes, not one.** Have the persona decide what to show in ordinary prose or a small free-form reasoning step, then run a second constrained pass that only serialises. This is the paper's finding, it matches Hearth's existing multi-stage pipeline shape, and it is cheap on a resident model.
3. **Shallow beats clever.** The tax scales with how much the schema fights the model's reasoning while it reasons. A flat list of 42 cells with a `text` string and a `style` enum is close to the easiest structure a constrained decoder can produce, because at every position the grammar admits a small set of tokens and the model is transcribing rather than computing. A nested template with a `$data` binding and a `${if(...)}` predicate is the opposite: the model must hold an abstraction, a data shape, and a predicate consistent simultaneously, under grammar constraint, at 2.3B.

**And the code comparison is not close.** Writing valid React means producing balanced JSX, correct hook usage, valid CSS, and a correct default export, with no grammar available to enforce any of it, since a GBNF grammar for JavaScript would admit essentially every syntactically valid program and constrain nothing semantically. A model at 26 to 56 percent on plain JSON is not going to produce reliably correct React. Even if the security question were somehow settled, reliability alone rules it out at this model size.

## What I could not determine

- **Thesys C1's wire format.** The public docs describe the Crayon React SDK "replacing a traditional markdown renderer" and list component categories, but do not disclose whether the API returns JSON, XML, or something else. I inferred select-and-parameterise from the architecture; I did not confirm it. The unread pages are `docs.thesys.dev/api-reference/objects/streaming.md` and `docs.thesys.dev/sdk-reference/c1-response.md`.
- **The gzipped size of `@babel/standalone`.** Bundlephobia did not return figures. The "almost 6 MB minified" number comes from a Babel issue thread, not from official docs or a published measurement.
- **Lyft Canvas from a primary source.** All details came from secondary write-ups. I did not find a Lyft engineering post.
- **Airbnb's actual failure cases.** Their post names none. The critical material in section 3 comes from practitioner write-ups and the MobileNativeFoundation discussion, not from the companies that built these systems. Treat the vendor posts as claims and the criticism as field reports; neither is a controlled comparison.
- **Whether Adaptive Cards' `Layout.Flow` calendar renders identically across hosts.** The layout properties are documented, but Adaptive Cards renderers vary by host and version, and I did not verify a calendar payload against a live renderer. The mechanism is documented; the fidelity is not verified.
- **Hearth's current Tauri CSP.** I researched Tauri v2's defaults and guidance but did not inspect the repository, so I do not know whether `unsafe-eval` is currently present in the app's `script-src` or what changing it would touch.
- **Whether any 2026 product mounts model-generated component code into a host app's live React tree.** I found none and the practitioner consensus says none do, but absence of evidence over a handful of searches is weak evidence of absence.
