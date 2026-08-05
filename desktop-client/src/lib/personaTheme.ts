import type { PersonaConfig, Rgba, VisualizationSphereParticle } from '../types/persona';

/* Hearth brand defaults: fennec accent + honey glow. */
const DEFAULT_PERSONA: Rgba = { r: 0.89, g: 0.604, b: 0.357, a: 1 }; /* #E39A5B */
const GLOW_TARGET = { r: 1.0, g: 0.722, b: 0.302 }; /* #FFB84D */

function rgbaToCss(c: Rgba): string {
  return `rgb(${Math.round(c.r * 255)} ${Math.round(c.g * 255)} ${Math.round(
    c.b * 255
  )} / ${c.a})`;
}

function mix(
  a: { r: number; g: number; b: number },
  b: { r: number; g: number; b: number },
  t: number
) {
  return {
    r: a.r * (1 - t) + b.r * t,
    g: a.g * (1 - t) + b.g * t,
    b: a.b * (1 - t) + b.b * t,
  };
}

/*
 * Direction B rule: the light surfaces are fixed (roast ink on cream/fluff,
 * always). Persona identity lives in the accent channel only -- the orb glow,
 * timeline nodes, and highlight fills read --persona / --persona-glow.
 */
export function applyPersonaTheme(
  el: HTMLElement,
  config: PersonaConfig | null
): void {
  el.classList.remove('font-geometric', 'font-humanist');
  if (!config) {
    el.style.removeProperty('--persona');
    el.style.removeProperty('--persona-glow');
    return;
  }

  let persona: Rgba = DEFAULT_PERSONA;
  if (config.visualization.type === 'sphere_particle') {
    const v = config.visualization as VisualizationSphereParticle;
    if (v.sphere?.color) persona = { ...v.sphere.color, a: 1 };
  }
  const glow = mix({ r: persona.r, g: persona.g, b: persona.b }, GLOW_TARGET, 0.55);

  el.style.transitionProperty = 'background, color, border-color';
  el.style.transitionDuration = '250ms';
  el.style.transitionTimingFunction = 'ease';
  el.style.setProperty('--persona', rgbaToCss(persona));
  el.style.setProperty('--persona-glow', rgbaToCss({ ...glow, a: 1 }));

  if (String(config.classification).toLowerCase() === 'realistic') {
    el.classList.add('font-humanist');
  } else {
    el.classList.add('font-geometric');
  }
}
