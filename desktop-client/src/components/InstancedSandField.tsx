import { useLayoutEffect, useMemo, useRef } from 'react';
import { useFrame } from '@react-three/fiber';
import {
  Color,
  InstancedMesh,
  Object3D,
  IcosahedronGeometry,
  MeshStandardMaterial,
} from 'three';
import type { VisualizationSphereParticle } from '../types/persona';

type Props = {
  vis: VisualizationSphereParticle;
  visualState: 'idle' | 'thinking' | 'speaking' | 'listening';
};

function pseudoR(seed: number, i: number, j: number) {
  const t = Math.sin((seed + i) * 12.9898 + (j + 0.1) * 78.233) * 43758.5453;
  return t - Math.floor(t);
}

export default function InstancedSandField({ vis, visualState }: Props) {
  const ps = vis.particle_system;
  const countN = useMemo(
    () => Math.min(620, Math.max(260, ps.count)),
    [ps.count]
  );
  const mesh = useRef<InstancedMesh>(null);
  const dummy = useMemo(() => new Object3D(), []);
  const seed = 2042;
  const c = ps.color;
  const baseColor = useMemo(() => new Color(c.r, c.g, c.b), [c.r, c.g, c.b]);
  const hotColor = useMemo(() => new Color(0.95, 0.78, 0.42), []);

  const { geometry, material } = useMemo(() => {
    return {
      geometry: new IcosahedronGeometry(1, 0),
      material: new MeshStandardMaterial({
        metalness: 0.08,
        roughness: 0.68,
        depthWrite: true,
        emissiveIntensity: 0.18,
      }),
    };
  }, []);

  useLayoutEffect(() => {
    material.color.copy(baseColor);
    material.emissive.copy(baseColor);
    return () => {
      geometry.dispose();
      material.dispose();
    };
  }, [baseColor, geometry, material]);

  const particles = useMemo(() => {
    const p: {
      band: number;
      phase: number;
      radius: number;
      height: number;
      speed: number;
      size: number;
      brightness: number;
      drift: number;
    }[] = [];
    const maxR = Math.max(ps.max_distance * 0.52, 0.42);
    for (let i = 0; i < countN; i++) {
      const band = Math.floor(pseudoR(seed, i, 0) * 5);
      const radialBias = Math.pow(pseudoR(seed, i, 1), 1.85);
      const radius = 0.08 + radialBias * maxR;
      p.push({
        band,
        phase: pseudoR(seed, i, 2) * Math.PI * 2,
        radius,
        height: (pseudoR(seed, i, 3) - 0.5) * (0.38 + band * 0.035),
        speed: 0.42 + pseudoR(seed, i, 4) * 0.8 + band * 0.06,
        size: 0.009 + (1 - radialBias) * 0.018 + pseudoR(seed, i, 5) * 0.006,
        brightness: 0.5 + (1 - radialBias) * 0.45,
        drift: pseudoR(seed, i, 6),
      });
    }
    return p;
  }, [countN, ps.max_distance, seed]);

  useLayoutEffect(() => {
    if (!mesh.current) return;
    for (let i = 0; i < countN; i++) {
      const p = particles[i];
      const color = baseColor.clone().lerp(hotColor, Math.max(0, 1 - p.radius));
      color.multiplyScalar(p.brightness);
      mesh.current.setColorAt(i, color);
    }
    if (mesh.current.instanceColor) mesh.current.instanceColor.needsUpdate = true;
  }, [baseColor, countN, hotColor, particles]);

  useFrame((st) => {
    if (!mesh.current) return;
    const t = st.clock.elapsedTime;
    const think = visualState === 'thinking' ? 1.35 : 1.0;
    const listen = visualState === 'listening' ? 0.08 : 0;
    for (let i = 0; i < countN; i++) {
      const p = particles[i];
      const u = t * think;
      const vortex = u * p.speed + p.phase;
      const wind =
        ((p.drift + u * (0.055 + p.band * 0.012)) % 1 - 0.5) *
        (0.34 + p.band * 0.04);
      const spiralR =
        p.radius * (1 + 0.1 * Math.sin(u * 1.7 + p.phase)) + listen;
      const x =
        spiralR * Math.cos(vortex) +
        0.12 * Math.sin(u * 0.9 + p.band) +
        wind;
      const y =
        p.height +
        0.12 * Math.sin(vortex * 1.7 + p.band) +
        0.035 * Math.sin(u * 4 + i);
      const z =
        spiralR * Math.sin(vortex) * 0.72 +
        0.16 * Math.cos(u * 0.7 + p.phase);
      dummy.position.set(x, y, z);
      const s = p.size * (visualState === 'thinking' ? 1.08 : 1);
      dummy.scale.setScalar(s);
      dummy.rotation.set(
        t * 0.7 + p.phase,
        t * 0.55 + p.band,
        t * 0.4 + p.drift
      );
      dummy.updateMatrix();
      mesh.current.setMatrixAt(i, dummy.matrix);
    }
    mesh.current.instanceMatrix.needsUpdate = true;
  });

  return (
    <instancedMesh
      ref={mesh}
      args={[geometry, material, countN]}
      frustumCulled={false}
    />
  );
}
