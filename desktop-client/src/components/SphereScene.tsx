import { useLayoutEffect, useMemo, useRef, Suspense } from 'react';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import React from 'react';
const VisionOrbScene = React.lazy(() => import('./VisionOrbScene'));
const InstancedSandField = React.lazy(() => import('./InstancedSandField'));
import type { VisualizationSphereParticle } from '../types/persona';


/* The preset was named after a persona that does not ship. The old spelling is
   still accepted so an existing persona.json keeps rendering. */
const SAND_STORM = ['sand_storm', 'mentat_sand_storm'];
const SULIVAN_DASHED = 'sulivan_dashed_aurora';

type Props = {
  vis: VisualizationSphereParticle;
  visualState: 'idle' | 'thinking' | 'speaking' | 'listening';
};

function pseudoRand(seed: number, i: number, j: number) {
  const t = Math.sin((seed + i) * 12.9898 + (j + 0.1) * 78.233) * 43758.5453;
  return t - Math.floor(t);
}

type ParticleData = {
  count: number;
  positions: Float32Array;
  colors: Float32Array;
};

/* Hearth warm defaults -- used only when the persona config carries no color;
   server-provided colors always win. */
const WARM_SPHERE = { r: 0.89, g: 0.604, b: 0.357, a: 1 }; /* fennec */
const WARM_PARTICLES = { r: 1.0, g: 0.722, b: 0.302, a: 1 }; /* honey */

function buildParticleData(vis: VisualizationSphereParticle): ParticleData {
  const ps = vis.particle_system;
  if (!ps.enabled) {
    return { count: 0, positions: new Float32Array(0), colors: new Float32Array(0) };
  }
  const seed = vis.layout_preset ? vis.layout_preset.length * 7 + 13 : 42;
  const n = Math.max(6, ps.count);
  const pos = new Float32Array(n * 3);
  const col = new Float32Array(n * 3);
  const c = ps.color ?? WARM_PARTICLES;
  const r0 = Math.max(vis.sphere.radius * 0.35, 0.02);
  const r1 = Math.max(ps.max_distance, r0 + 0.04);
  for (let i = 0; i < n; i++) {
    const ix = i * 3;
    const u = pseudoRand(seed, i, 0);
    const v = pseudoRand(seed, i, 1);
    const theta = u * Math.PI * 2;
    const phi = Math.acos(2 * v - 1);
    const t = r0 + pseudoRand(seed, i, 2) * (r1 - r0);
    const st = Math.sin(phi);
    pos[ix] = t * st * Math.cos(theta);
    pos[ix + 1] = t * st * Math.sin(theta);
    pos[ix + 2] = t * Math.cos(phi);
    const a = 0.65 + pseudoRand(seed, i, 3) * 0.35;
    col[ix] = c.r * a;
    col[ix + 1] = c.g * a;
    col[ix + 2] = c.b * a;
  }
  return { count: n, positions: pos, colors: col };
}

export default function SphereScene({ vis, visualState }: Props) {
  const preset = vis.layout_preset;
  const isSand = SAND_STORM.includes(preset ?? '');
  const isSulivanDashed = preset === SULIVAN_DASHED;
  const useAdvanced = isSand || isSulivanDashed;

  const groupRef = useRef<THREE.Group>(null);
  const meshRef = useRef<THREE.Mesh>(null);
  const orbitRef = useRef<THREE.Group>(null);
  const pointsRef = useRef<THREE.Points>(null);
  const data = useMemo(
    () => (useAdvanced ? null : buildParticleData(vis)),
    [vis, useAdvanced]
  );
  const col = vis.sphere?.color ?? WARM_SPHERE;
  const baseColor = useMemo(
    () => new THREE.Color(col.r, col.g, col.b),
    [col.r, col.g, col.b]
  );
  const ps = vis.particle_system;
  const hasPoints = !useAdvanced && ps.enabled && (data?.count ?? 0) > 0;
  const pointSize = Math.max(ps.particle_radius * 1.1, 0.012);

  useLayoutEffect(() => {
    if (!hasPoints || !pointsRef.current || !data) return;
    const g = pointsRef.current.geometry;
    g.setAttribute('position', new THREE.BufferAttribute(data.positions, 3));
    g.setAttribute('color', new THREE.BufferAttribute(data.colors, 3));
  }, [data, hasPoints]);

  useFrame((st, delta) => {
    const t = st.clock.elapsedTime;
    if (groupRef.current) {
      const pulse =
        visualState === 'thinking' ? 0.12 * Math.sin(t * 2.2) : 0;
      let s = 1 + pulse + (visualState === 'listening' ? 0.04 : 0);
      if (isSand) s *= visualState === 'thinking' ? 1.2 : 1.0;
      groupRef.current.scale.setScalar(s);
    }
    if (meshRef.current) {
      meshRef.current.rotation.y += delta * (isSulivanDashed ? 0.1 : 0.3);
    }
    if (orbitRef.current && hasPoints) {
      orbitRef.current.rotation.y += delta * 0.5;
    }
  });

  return (
    <group
      ref={groupRef}
      position={[vis.position.x, vis.position.y, vis.position.z]}
      scale={[vis.scale.x, vis.scale.y, vis.scale.z]}
    >
      {!isSand && (
        <mesh ref={meshRef}>
          <sphereGeometry args={[vis.sphere.radius, 48, 48]} />
          <meshStandardMaterial
            color={baseColor}
            metalness={vis.sphere.metallic}
            roughness={vis.sphere.roughness}
            emissive={baseColor}
            emissiveIntensity={
              isSulivanDashed ? 0.04 : visualState === 'thinking' ? 0.35 : 0.12
            }
            opacity={isSulivanDashed ? 0.34 : 1}
            transparent={isSulivanDashed}
            depthWrite={!isSulivanDashed}
          />
        </mesh>
      )}

      {isSulivanDashed && (
        <Suspense fallback={null}>
          {/* The visionOS-parity field owns its own spin -- no orbitRef wrap. */}
          <VisionOrbScene vis={vis} visualState={visualState} />
        </Suspense>
      )}

      {isSand && (
        <Suspense fallback={null}>
          <InstancedSandField vis={vis} visualState={visualState} />
        </Suspense>
      )}

      {hasPoints && (
        <group ref={orbitRef}>
          <points ref={pointsRef} frustumCulled={false}>
            <bufferGeometry />
            <pointsMaterial
              size={pointSize}
              vertexColors
              sizeAttenuation
              depthWrite={false}
              transparent
              opacity={0.72}
            />
          </points>
        </group>
      )}
    </group>
  );
}
