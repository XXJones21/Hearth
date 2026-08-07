// Hearth mark candidates. Emits one SVG per variant plus PNG renders.
//
//   node build-icons.mjs
//
// Every path lives in a 1024x1024 box so the same geometry serves the tray
// mark and the 1024 icon master. Edit a candidate's `mark()` and re-run.

import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Resvg } from "@resvg/resvg-js";

const HERE = dirname(fileURLToPath(import.meta.url));

// Palette, copied from desktop-client/src/styles/globals.css.
const C = {
  cream: "#FAF4EA",
  fennec: "#E39A5B",
  ember: "#C97F45",
  honey: "#FFB84D",
  roast: "#3B2B20",
  linen: "#EFE6D8",
  parchment: "#FBF3E7",
};

// A flame. `cx` centre, `top` apex y, `bottom` base y, `w` half-width.
// The tip starts narrow and only flares below the midpoint, and the apex
// leans right, which is what separates a flame from a teardrop.
function flame(cx, top, bottom, w) {
  const h = bottom - top;
  const y = (t) => top + h * t;
  const apex = cx + w * 0.16;
  return [
    `M${apex} ${top}`,
    `C${apex + w * 0.3} ${y(0.24)} ${cx + w} ${y(0.44)} ${cx + w} ${y(0.66)}`,
    `C${cx + w} ${y(0.9)} ${cx + w * 0.58} ${bottom} ${cx} ${bottom}`,
    `C${cx - w * 0.58} ${bottom} ${cx - w} ${y(0.9)} ${cx - w} ${y(0.66)}`,
    `C${cx - w} ${y(0.4)} ${apex - w * 0.54} ${y(0.2)} ${apex} ${top}`,
    "Z",
  ].join(" ");
}

// Rounded arch: straight legs, semicircular head, open at the base.
function arch(x0, x1, yBase, ySpring) {
  const r = (x1 - x0) / 2;
  return `M${x0} ${yBase} L${x0} ${ySpring} A${r} ${r} 0 0 1 ${x1} ${ySpring} L${x1} ${yBase}`;
}

const candidates = [
  {
    slug: "ember",
    note: "Single flame, hot core. Pure silhouette, no structure.",
    mark: (ink) => `
  <path d="${flame(512, 120, 900, 248)}" fill="${ink === "dark" ? C.fennec : C.ember}"/>
  <path d="${flame(512, 404, 838, 146)}" fill="${C.honey}"/>`,
    needsDark: false,
  },
  {
    slug: "hearth-arch",
    note: "Filled fireplace surround, fire silhouetted against the glowing opening.",
    mark: (ink) => {
      const ho = ink === "dark" ? C.cream : C.roast;
      return `
  <path d="M232 832 L232 472 A280 280 0 0 1 792 472 L792 832 Z" fill="${ho}"/>
  <path d="M340 832 L340 472 A172 172 0 0 1 684 472 L684 832 Z" fill="${C.honey}"/>
  <path d="${flame(512, 512, 832, 120)}" fill="${ho}"/>`;
    },
    needsDark: true,
  },
  {
    slug: "orb",
    note: "The persona orb: hot core, warm shell, three orbiting motes.",
    mark: () => {
      const dots = [-52, 68, 188]
        .map((deg) => {
          const a = (deg * Math.PI) / 180;
          const x = 512 + Math.cos(a) * 424;
          const y = 512 + Math.sin(a) * 424;
          return `  <circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="56" fill="${C.ember}"/>`;
        })
        .join("\n");
      return `
  <circle cx="512" cy="512" r="322" fill="none" stroke="${C.fennec}" stroke-width="52"/>
  <circle cx="512" cy="512" r="214" fill="${C.honey}"/>
${dots}`;
    },
    needsDark: false,
  },
  {
    slug: "home-flame",
    note: "House silhouette carrying the fire. The most literal read.",
    mark: (ink) => {
      const ho = ink === "dark" ? C.cream : C.roast;
      return `
  <path d="M512 168 L862 462 L862 848 L162 848 L162 462 Z"
        fill="${ho}" stroke="${ho}" stroke-width="76" stroke-linejoin="round"/>
  <path d="${flame(512, 424, 796, 126)}" fill="${C.honey}"/>`;
    },
    needsDark: true,
  },
  {
    slug: "arch-orb",
    note: "Open hearth arch holding the orb. Home plus companion, two strokes.",
    mark: () => `
  <path d="${arch(238, 786, 866, 590)}" fill="none" stroke="${C.fennec}"
        stroke-width="80" stroke-linecap="round"/>
  <circle cx="512" cy="586" r="168" fill="${C.honey}"/>`,
    needsDark: false,
  },
  {
    slug: "brick-hearth",
    note: "Mantel, brick columns, fire in the box. The living-room fireplace.",
    mark: (ink) => {
      const ho = ink === "dark" ? C.cream : C.roast;
      // Mortar: horizontal courses plus staggered head joints, only on the
      // masonry. At 32 px they read as texture, not as lines to count.
      const mortar = [
        // columns, three courses each
        ...[440, 584, 728].map(
          (y) => `  <rect x="192" y="${y}" width="160" height="16" fill="${C.cream}"/>
  <rect x="672" y="${y}" width="160" height="16" fill="${C.cream}"/>`,
        ),
        // staggered head joints on the columns
        `  <rect x="264" y="296" width="16" height="144" fill="${C.cream}"/>`,
        `  <rect x="744" y="440" width="16" height="144" fill="${C.cream}"/>`,
        `  <rect x="264" y="584" width="16" height="144" fill="${C.cream}"/>`,
        `  <rect x="744" y="728" width="16" height="144" fill="${C.cream}"/>`,
        // two head joints on the lintel
        `  <rect x="440" y="296" width="16" height="124" fill="${C.cream}"/>`,
        `  <rect x="568" y="296" width="16" height="124" fill="${C.cream}"/>`,
      ].join("\n");
      return `
  <rect x="152" y="232" width="720" height="64" rx="20" fill="${ho}"/>
  <rect x="192" y="296" width="640" height="576" fill="${C.ember}"/>
${mortar}
  <rect x="352" y="420" width="320" height="452" fill="${ho}"/>
  <path d="${flame(512, 500, 852, 112)}" fill="${C.honey}"/>
  <path d="${flame(512, 656, 838, 60)}" fill="${C.cream}"/>
  <rect x="152" y="872" width="720" height="48" rx="16" fill="${ho}"/>`;
    },
    needsDark: true,
  },
  {
    slug: "brick-arch",
    note: "Full brick block, arched firebox, fire inside. The chimney breast.",
    mark: (ink) => {
      const ho = ink === "dark" ? C.cream : C.roast;
      const mortar = [
        ...[360, 488, 616, 744].map(
          (y) => `  <rect x="192" y="${y}" width="640" height="16" fill="${C.cream}"/>`,
        ),
        `  <rect x="504" y="232" width="16" height="128" fill="${C.cream}"/>`,
        `  <rect x="336" y="360" width="16" height="128" fill="${C.cream}"/>`,
        `  <rect x="672" y="360" width="16" height="128" fill="${C.cream}"/>`,
        `  <rect x="504" y="488" width="16" height="128" fill="${C.cream}"/>`,
        `  <rect x="288" y="616" width="16" height="128" fill="${C.cream}"/>`,
        `  <rect x="720" y="616" width="16" height="128" fill="${C.cream}"/>`,
        `  <rect x="264" y="744" width="16" height="128" fill="${C.cream}"/>`,
        `  <rect x="744" y="744" width="16" height="128" fill="${C.cream}"/>`,
      ].join("\n");
      return `
  <rect x="192" y="232" width="640" height="640" rx="44" fill="${C.ember}"/>
${mortar}
  <path d="${arch(362, 662, 872, 560)} Z" fill="${ho}"/>
  <path d="${flame(512, 604, 852, 96)}" fill="${C.honey}"/>
  <path d="${flame(512, 716, 838, 52)}" fill="${C.cream}"/>
  <rect x="152" y="872" width="720" height="48" rx="16" fill="${ho}"/>`;
    },
    needsDark: true,
  },
];

function svgDoc(body, { plate } = {}) {
  const bg = plate
    ? `\n  <rect width="1024" height="1024" rx="216" fill="${plate}"/>`
    : "";
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">${bg}${body}
</svg>
`;
}

function render(svg, width) {
  return new Resvg(svg, { fitTo: { mode: "width", value: width } })
    .render()
    .asPng();
}

const written = [];
function emit(name, svg, pngSizes) {
  writeFileSync(join(HERE, `${name}.svg`), svg);
  written.push(`${name}.svg`);
  for (const size of pngSizes) {
    writeFileSync(join(HERE, `${name}-${size}.png`), render(svg, size));
    written.push(`${name}-${size}.png`);
  }
}

candidates.forEach((cand, i) => {
  const base = `candidate-${i + 1}-${cand.slug}`;

  // Tray mark: transparent, scaled to fill more of the box than the app icon.
  emit(base, svgDoc(cand.mark("light")), [32, 128]);

  // App icon master: the mark inset on a cream plate, 1024 for `tauri icon`.
  const inset = `
  <g transform="translate(512 512) scale(0.78) translate(-512 -512)">${cand.mark("light")}
  </g>`;
  emit(`${base}-app`, svgDoc(inset, { plate: C.cream }), [1024]);

  if (cand.needsDark) {
    emit(`${base}-dark`, svgDoc(cand.mark("dark")), [32, 128]);
  }
});

console.log(`${candidates.length} candidates, ${written.length} files:`);
for (const f of written) console.log(`  ${f}`);
