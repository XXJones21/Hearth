import { useEffect, useRef } from 'react';
import { FaceDirector, type LookTarget } from '../../lib/face/director';
import { facePaths } from '../../lib/face/geometry';
import { ttsPlayer } from '../../lib/audioPlayer';
import { loadSettings, SETTINGS_EVENT } from '../../lib/settings';
import { useAppStore, type VisualizerState } from '../../store/appStore';
import type { FaceGeometry } from '../../types/persona';

/*
 * The procedural face's SVG renderer. All behaviour -- state playlists,
 * energy-tiered blink, micro-saccades, transient cues, the amplitude
 * mouth -- lives in the FaceDirector, which is renderer-free; this
 * component's whole job is ticking it and writing path data onto the SVG.
 *
 * The animation loop owns the pose through the director and writes
 * attributes imperatively: a 60fps mouth must not re-render the React
 * tree. React's job here is mounting the skeleton and reacting to
 * identity changes (a different persona, a different geometry).
 */

type StateRgb = { r: number; g: number; b: number };

type Props = {
  geometry: FaceGeometry;
  visualState: VisualizerState;
  /** The persona's per-state colours (same block the orb glow reads). The
   *  face's ink leans toward the active state's colour so a state is
   *  legible even in peripheral vision. */
  stateColors?: Record<string, StateRgb>;
};

const rgbCss = (c: StateRgb): string =>
  `rgb(${Math.round(c.r * 255)} ${Math.round(c.g * 255)} ${Math.round(c.b * 255)})`;

export function PersonaFace({ geometry, visualState, stateColors }: Props) {
  const groupRef = useRef<SVGGElement | null>(null);
  const headRef = useRef<SVGPathElement | null>(null);
  const leftEyeRef = useRef<SVGPathElement | null>(null);
  const rightEyeRef = useRef<SVGPathElement | null>(null);
  const leftGlintRef = useRef<SVGPathElement | null>(null);
  const rightGlintRef = useRef<SVGPathElement | null>(null);
  const mouthRef = useRef<SVGPathElement | null>(null);
  const mouthRoundRef = useRef<SVGPathElement | null>(null);

  const stateRef = useRef<VisualizerState>(visualState);
  stateRef.current = visualState;

  const svgRef = useRef<SVGSVGElement | null>(null);

  useEffect(() => {
    const director = new FaceDirector(geometry, performance.now());
    let reduceMotion = loadSettings().reduceMotion;
    const syncSettings = () => {
      reduceMotion = loadSettings().reduceMotion;
    };
    window.addEventListener(SETTINGS_EVENT, syncSettings);

    // The look target: where the composer input sits relative to the face,
    // in gaze space. Remeasured on a slow timer -- layout moves rarely,
    // and the director eases toward it anyway. On this client that is the
    // desktop's input box; an iOS renderer passes its own target instead.
    let lookTarget: LookTarget = null;
    const measure = () => {
      const face = svgRef.current?.getBoundingClientRect();
      const input = document
        .querySelector('textarea, input[placeholder*="Ask"]')
        ?.getBoundingClientRect();
      if (!face || !input || face.width === 0) {
        lookTarget = null;
        return;
      }
      const dx = (input.left + input.width / 2 - (face.left + face.width / 2)) / face.width;
      const dy = (input.top + input.height / 2 - (face.top + face.height / 2)) / face.height;
      lookTarget = {
        x: Math.max(-1, Math.min(1, dx * 0.9)),
        y: Math.max(-1, Math.min(1, dy * 0.9)),
        focus: 0.5,
      };
    };
    measure();
    const measureTimer = window.setInterval(measure, 1500);

    let raf = 0;

    const step = (now: number) => {
      // The whole frame body is guarded: an exception thrown inside a rAF
      // callback ends the chain silently, which freezes the face in its
      // last pose and looks exactly like "the mouth stopped working".
      try {
        frameBody(now);
      } catch {
        /* skip the frame, keep the loop alive */
      }
      raf = requestAnimationFrame(step);
    };

    const frameBody = (now: number) => {
      const frame = director.tick(
        now,
        stateRef.current,
        useAppStore.getState().faceCue,
        ttsPlayer.level(),
        reduceMotion,
        lookTarget,
      );
      const p = facePaths(frame, 200);
      headRef.current?.setAttribute('d', p.head);
      leftEyeRef.current?.setAttribute('d', p.leftEye);
      rightEyeRef.current?.setAttribute('d', p.rightEye);
      leftEyeRef.current?.setAttribute('transform', p.leftEyeTransform);
      rightEyeRef.current?.setAttribute('transform', p.rightEyeTransform);
      leftGlintRef.current?.setAttribute('d', p.leftGlint);
      rightGlintRef.current?.setAttribute('d', p.rightGlint);
      leftGlintRef.current?.setAttribute('transform', p.leftEyeTransform);
      rightGlintRef.current?.setAttribute('transform', p.rightEyeTransform);
      leftGlintRef.current?.setAttribute('opacity', String(p.glintOpacity));
      rightGlintRef.current?.setAttribute('opacity', String(p.glintOpacity));
      mouthRef.current?.setAttribute('d', p.mouth);
      mouthRoundRef.current?.setAttribute('d', p.mouthRound);
      // The resting face is eyes-only: the mouth fades in with whatever is
      // opening it (speech amplitude or a transient) and vanishes after.
      // mouth_round crossfades the crescent against the round "o", so the
      // two shapes never have to morph path-by-path.
      const mouthVis = Math.min(1, frame.mouth_open * 4);
      mouthRef.current?.setAttribute('opacity', String(mouthVis * (1 - frame.mouth_round)));
      mouthRoundRef.current?.setAttribute('opacity', String(mouthVis * frame.mouth_round));
      groupRef.current?.setAttribute('transform', p.transform);
    };
    raf = requestAnimationFrame(step);

    return () => {
      cancelAnimationFrame(raf);
      window.clearInterval(measureTimer);
      window.removeEventListener(SETTINGS_EVENT, syncSettings);
    };
  }, [geometry]);

  /* Colours: the base accent is the theme's --persona; the active state's
     colour (the same block the orb glow read) leans the ink and the head
     stroke, with a slow fill transition so state changes wash rather than
     snap. A face that invented its own palette would drift from the chips
     and the glow. */
  const stateColor = stateColors?.[visualState];
  const ink = stateColor
    ? `color-mix(in srgb, ${rgbCss(stateColor)} 38%, #3B2517)`
    : 'color-mix(in srgb, var(--persona, #E39A5B) 22%, #3B2517)';
  const rim = stateColor
    ? `color-mix(in srgb, ${rgbCss(stateColor)} 62%, #4A2F20)`
    : 'color-mix(in srgb, var(--persona, #E39A5B) 55%, #4A2F20)';
  const glint = 'color-mix(in srgb, var(--persona-glow, #FFB84D) 25%, #FDF8F1)';
  const fillTransition = { transition: 'fill 600ms ease, stroke 600ms ease' } as const;
  return (
    <svg
      ref={svgRef}
      viewBox="0 0 200 200"
      className="h-full w-full"
      role="img"
      aria-label="Persona face"
    >
      <g ref={groupRef}>
        <path
          ref={headRef}
          fill="color-mix(in srgb, var(--persona, #E39A5B) 16%, #FDF8F1)"
          stroke={rim}
          strokeWidth="3"
          style={fillTransition}
        />
        <path ref={leftEyeRef} fill={ink} style={fillTransition} />
        <path ref={rightEyeRef} fill={ink} style={fillTransition} />
        <path ref={leftGlintRef} opacity="0" fill={glint} />
        <path ref={rightGlintRef} opacity="0" fill={glint} />
        <path ref={mouthRef} opacity="0" fill={ink} style={fillTransition} />
        <path ref={mouthRoundRef} opacity="0" fill={ink} style={fillTransition} />
      </g>
    </svg>
  );
}
