# Hearth mark candidates

Five icon candidates for the Hearth app icon and tray icon. Vector SVG sources
plus PNG renders, all built from the real Direction B palette.

**Status: pen.dev could not be used. It requires an interactive account login
that cannot be completed unattended.** The candidates below were authored
directly as SVG. Details in "What happened with pen.dev" at the bottom.

## The candidates

| # | Slug | Idea | Colors |
| --- | --- | --- | --- |
| 1 | `ember` | A single flame with a hot core. Pure silhouette, no structure around it. | ember, honey |
| 2 | `hearth-arch` | Filled fireplace surround with the fire silhouetted against a glowing opening. | roast, honey |
| 3 | `orb` | The persona orb: hot core, warm shell, three orbiting motes. | fennec, honey, ember |
| 4 | `home-flame` | House silhouette carrying the fire. The most literal read of the product. | roast, honey |
| 5 | `arch-orb` | Open hearth arch holding the orb. Home plus companion in two strokes. | fennec, honey |

Recommendation: **candidate 4, `home-flame`**. It is the only mark that states
both halves of the product in one silhouette, and it survives 32 px better than
the others because the shape is a single solid form with one bright counter.
Candidate 2 is the runner-up if a fireplace reads better than a house.

Candidate 5 is the weakest. At 32 px an open arch with a dot inside is
ambiguous, and it can read as a padlock or a pair of headphones.

## Files per candidate

For each candidate `candidate-N-<slug>`:

| File | What it is |
| --- | --- |
| `.svg` | Tray mark. Transparent background, 1024 viewBox, the vector source. |
| `-32.png` | 32 px tray render. The size test. |
| `-128.png` | 128 px render, for looking at the shape without squinting. |
| `-app.svg` | App icon master. The mark inset on a cream rounded-square plate. |
| `-app-1024.png` | 1024 px render of the above. This is the `tauri icon` input. |
| `-dark.svg` and `-dark-{32,128}.png` | Dark background variant, where one exists. |

Candidates 2 and 4 use `roast` as their structural ink, which disappears on a
dark background, so they ship a `-dark` variant that swaps `roast` for `cream`.
Candidates 1, 3, and 5 are built from fennec, ember, and honey only, so a single
file reads on both backgrounds and no dark variant is needed.

Each variant is meant for its own background. The `-dark` files are not
drop-in replacements on light surfaces.

## Palette

Taken from `desktop-client/src/styles/globals.css`, not invented:

| Token | Hex |
| --- | --- |
| cream | `#FAF4EA` |
| fennec | `#E39A5B` |
| ember | `#C97F45` |
| honey | `#FFB84D` |
| roast | `#3B2B20` |

Every candidate uses at most three of these plus the plate background, per the
brief. No mark uses `fennec` or `honey` as an ink on a light surface in a way
that would violate the design system contrast rules, because none of them carry
text.

## Regenerating and iterating

Everything is produced by one script. The geometry lives in shared helpers so a
shape change propagates to every render of that candidate.

```bash
cd D:/Tools/Hearth/design/icons
npm install        # once, pulls @resvg/resvg-js for SVG to PNG
node build-icons.mjs
```

That rewrites all 31 files and prints what it wrote.

To iterate on a candidate, edit its entry in the `candidates` array in
`build-icons.mjs` and re-run. The pieces worth knowing:

- `C` is the palette object. Add a token here rather than pasting a hex inline.
- `flame(cx, top, bottom, w)` returns a flame path. The tip stays narrow until
  the midpoint and the apex leans right, which is what stops it reading as a
  teardrop. Widen `w` or drop `bottom` to change proportion.
- `arch(x0, x1, yBase, ySpring)` returns an open arch path for stroking.
- `mark(ink)` returns the SVG body. It is called with `"light"` and, when
  `needsDark` is true, with `"dark"`. Branch on `ink` only for the structural
  color, never for the warm accents.
- The app plate corner radius is `216` on a 1024 box, and the mark is inset to
  78 percent. Both are in `svgDoc` and the emit loop.

To add a sixth candidate, append one object to the array. Numbering comes from
array position, so inserting in the middle renumbers the files after it.

## Next step

Pick a candidate, then from `desktop-client`:

```bash
npx tauri icon ../design/icons/candidate-4-home-flame-app-1024.png
```

That regenerates the full `src-tauri/icons/` set, including the Windows `.ico`,
the macOS `.icns`, and the Square*Logo PNGs that are already in the tree.

For the tray icon specifically, check whether the tray should use the
transparent `candidate-4-home-flame.svg` mark instead of the plated app icon.
Trays generally look better without a plate, and on Windows the tray sits on a
taskbar that follows the system theme, which is what the `-dark` variant is for.

## What happened with pen.dev

pen.dev is a headless design tool. You give its CLI a natural language prompt
and it drives an AI agent that produces a `.pen` design file, which it can then
export as an image. It is aimed at UI layouts rather than icon marks, and it
bills itself as the way an agent can design without a human in a GUI.

Installation worked cleanly:

```bash
npm install -g @pen.dev/cli
pen version        # 0.3.2
```

Generation did not, because the tool is gated on a pen.dev account:

```
$ pen status
Status      Not authenticated

$ pen --out probe.pen --prompt "a simple orange circle" --export probe.png
[ERROR] Authentication required. Run "pen login" or set PEN_CLI_KEY environment variable.
```

There are three ways to satisfy it, and none could be done unattended:

1. `pen login` is a fully interactive prompt. It opens a menu asking for email
   plus password or email plus a one time code, and it aborts if stdin is not a
   TTY. This is the blocker that stopped the run.
2. `pen signup --email <email> --username <name> --name "<full name>"` creates
   an account. This was deliberately not run, because creating an account on a
   third party service under your email is not something to do without you
   asking for it.
3. `PEN_CLI_KEY` is the unattended path, intended for CI. It takes precedence
   over any stored session. Getting one requires an account first.

An agent API key is a separate axis. `PEN_AGENT_API_KEY` or `ANTHROPIC_API_KEY`
supplies the model that pen.dev drives, but neither substitutes for the pen.dev
account, which is checked first.

To unblock it later, run `pen login` yourself in a terminal, or set
`PEN_CLI_KEY` in the environment, then:

```bash
pen --out candidate.pen --prompt "<description>" --export candidate.png --export-scale 2
pen --in candidate.pen --out candidate-v2.pen --prompt "<changes>" --export candidate-v2.png
```

One thing to know before investing in it: `pen --help` lists `png`, `jpeg`,
`webp`, and `pdf` as export formats, with no SVG. The `.pen` file is the vector
source and it is proprietary. For an icon that has to end up as clean vector
paths, that is a real limitation regardless of the auth situation.
