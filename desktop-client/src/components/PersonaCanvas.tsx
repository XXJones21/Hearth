import { Canvas } from '@react-three/fiber';
import { OrbitControls } from '@react-three/drei';
import { Suspense, lazy } from 'react';

const GlbScene = lazy(() => import('./GlbScene'));
const SphereScene = lazy(() => import('./SphereScene'));

import { PersonaFace } from './stage/PersonaFace';
import { PersonaFlame } from './PersonaFlame';
import { VisualizationErrorBoundary } from './VisualizationErrorBoundary';
import type { PersonaConfig } from '../types/persona';
import { mapVisualizerState, useAppStore } from '../store/appStore';
import { getWsUrl } from '../lib/config';

type Props = {
  config: PersonaConfig | null;
};

export default function PersonaCanvas({ config }: Props) {
  const visualState = useAppStore((s) => s.visualState);
  const inputFocused = useAppStore((s) => s.inputFocused);
  const connection = useAppStore((s) => s.connection);
  const effective = mapVisualizerState(visualState, inputFocused);

  if (!config) {
    return (
      <div className="flex h-full w-full items-center justify-center rounded-full bg-parchment p-4 text-center">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-ember">Waking up</p>
          <p className="mt-1 text-[11px] leading-relaxed text-fawn">
            {connection === 'connecting'
              ? 'Reaching your home server...'
              : `Waiting for ${getWsUrl()}`}
          </p>
        </div>
      </div>
    );
  }

  const v = config.visualization;

  // The face is SVG, not three.js: no Canvas, no camera, no error boundary
  // for GLB loads. It keys on the persona so a switch remounts the loop.
  if (v.type === 'procedural_face') {
    const stateColors = (v as { state_colors?: Record<string, { r: number; g: number; b: number }> })
      .state_colors;
    return (
      <div className="h-full w-full" key={config.name}>
        <PersonaFace geometry={v.geometry} visualState={effective} stateColors={stateColors} />
      </div>
    );
  }

  // The fire (persona-flame-spec.md, 2D recipe): the canvas flame the phones
  // draw -- one body path and gradient, licks, a bounded tip feather, the
  // same face director in features-only flat black, additive embers, the
  // halo. Flat like the SVG face branch: no three.js, no camera.
  if (v.type === 'flame') {
    return (
      <div className="h-full w-full" key={config.name}>
        <PersonaFlame geometry={v.geometry} visualState={effective} />
      </div>
    );
  }

  const sceneKey = `${config.name}:${v.type}:${v.layout_preset ?? 'default'}`;
  const assetUrl = typeof v === 'object' && v && 'glb' in v
    ? (v as { glb?: { asset_url?: string } }).glb?.asset_url || ''
    : '';

  const failFallback = (
    <div className="flex h-full w-full flex-col items-center justify-center gap-1.5 rounded-full bg-parchment p-4 text-center text-xs text-fawn">
      <p className="font-semibold text-roast">Visualization unavailable</p>
      {assetUrl && <code className="break-all text-[10px]">{assetUrl}</code>}
      <button
        type="button"
        className="rounded-full bg-roast px-3 py-1 text-[11px] font-medium text-cream"
        onClick={() => useAppStore.getState().setVisualizationError(null)}
      >
        Retry
      </button>
    </div>
  );

  return (
    <div className="h-full w-full">
      <VisualizationErrorBoundary key={config.name} fallback={failFallback}>
        <Canvas
          camera={{ position: [0, 0.15, 1.9], fov: 42 }}
          gl={{ antialias: true, alpha: true }}
        >
          <ambientLight intensity={0.55} />
          <directionalLight position={[3, 5, 4]} intensity={1.1} />
          <Suspense fallback={null}>
            <group key={sceneKey}>
              {v.type === 'sphere_particle' ? (
                <Suspense fallback={null}>
                  <SphereScene vis={v} visualState={effective} />
                </Suspense>
              ) : (
                <Suspense fallback={null}>
                  <GlbScene
                    config={config}
                    vis={v}
                    visualState={effective}
                  />
                </Suspense>
              )}
            </group>
          </Suspense>
          <OrbitControls enableZoom={false} maxPolarAngle={Math.PI / 1.9} />
        </Canvas>
      </VisualizationErrorBoundary>
    </div>
  );
}
