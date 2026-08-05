# Hearth design system -- Direction B

Extracted from the design of record (`hearth-pitch/mockups/hearth-app-mockup-b.html`)
and `hearth-pitch/brand-direction.md`. Implemented as Tailwind v4 `@theme`
tokens in `src/styles/globals.css`. Light-first; ember mode is a deferred
variant.

## Tokens

| Token | Hex | Tailwind name | Use |
| --- | --- | --- | --- |
| cream | `#FAF4EA` | `cream` | app background inside the frame |
| fluff | `#FFFFFF` | `fluff` | cards / surfaces |
| fennec | `#E39A5B` | `fennec` | primary accent: active chips, meters, orb |
| ember | `#C97F45` | `ember` | hover/pressed, emphasis, icon accents |
| honey | `#FFB84D` | `honey` | glows, highlights, progress fills, CTA top |
| roast | `#3B2B20` | `roast` | the ONLY body-text ink on light surfaces |
| fawn | `#8C7A66` | `fawn` | secondary text |
| linen | `#EFE6D8` | `linen` | dividers, borders, recessed tracks |
| peach | `#F6DFC8` | `peach` | the page field behind the frame |
| peach-deep | `#F0D2B4` | `peach-deep` | field blob shading |
| parchment | `#FBF3E7` | `parchment` | search pill / row fills |
| glowtint | `#FDF4E4` | `glowtint` | live-chip fill |
| bubble | `#F6E3CB` | `bubble` | user message fill |
| bubble-line | `#EDD5B4` | `bubble-line` | user message border |
| tab | `#F8E2C4` | `tab` | selected pill tab |

Shadows: `shadow-frame` (floating app frame), `shadow-soft` (cards, buttons).
Motion: `.breathe` (5.2s orb heartbeat; disabled under reduced motion).
Field: `.hearth-field` paints the peach page + corner blobs.

## Contrast rules (non-negotiable)

- `roast` on `cream`/`fluff`/`parchment` is the only body-text pairing.
- `fennec`/`honey` are never text colors on light surfaces. Buttons on
  fennec/honey fills use roast text (see the mockup CTA).
- `fawn` is for secondary text only, never sub-12px on tinted fills.
- Status colors stay reserved and ship with icon + label, never color alone.

## Persona accent channel

`applyPersonaTheme` (`src/lib/personaTheme.ts`) writes exactly two runtime
vars: `--persona` (the persona's color, default fennec) and `--persona-glow`
(mixed toward honey). Components use `persona`/`persona-glow` Tailwind colors
for orb glow, timeline nodes, and highlight accents. Surfaces and ink never
repaint on persona switch -- that is the core difference from the retired
dark theme.

## Component inventory (mockup regions -> components)

| Mockup region | Component | Status |
| --- | --- | --- |
| Floating frame + grid 300/1fr/320 | `shell/AppFrame` | Stage 4 |
| Persona stage (chip, orb, name, chips, listen, dock) | `stage/PersonaStage` + `stage/PersonaChips` + `stage/OrbGlow` | Stage 4 |
| Particle orb | `PersonaCanvas`/`SphereScene` (ported, warm default) | Stage 4 |
| Topbar (search pill, icon buttons) | `feed/Feed` | Stage 5 |
| Live chip | `rail/LiveChip` | Stage 7 beat |
| Timeline (rail line, nodes, entries) | `feed/Timeline` + `feed/TimelineEntry` | Stage 5 |
| Message cards / user bubble | `feed/MessageCard` | Stage 5 |
| Composer | `feed/Composer` | Stage 5 |
| ui_component cards | `cards/*` via `cards/registry` | Stage 6 |
| Mentat run card | `feed/MentatRunCard` | Stage 7 beat |
| Rail (icons, pill tabs, rows, pips, facts, CTA) | `rail/Rail` + tabs | Stage 7 |

## Type and shape

Body: Segoe UI Variable stack (warm humanist-adjacent, ships on Windows);
`font-humanist` (Georgia) applies for personas classified `realistic`.
Radii: 16px cards, 26px frame, full-round chips/pills. Shadows soft and warm,
never hard black. Whitespace-generous.
