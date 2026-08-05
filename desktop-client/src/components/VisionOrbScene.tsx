import { useMemo, useRef } from 'react';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import { ttsPlayer } from '../lib/audioPlayer';
import type { VisualizationSphereParticle } from '../types/persona';

/*
 * The visionOS orb particle field, ported from
 * Apple Client/.../RealityKitSceneManager.swift: N beads on a deterministic
 * Fibonacci shell with per-state choreography --
 *   idle       shell breathes and the whole field slowly spins
 *   listening  3D firefly swirl (per-particle orbits, distance pulse, bob)
 *   thinking   flat Saturn ring at y=0, double orbit speed
 *   speaking   front-facing audio waveform driven by real TTS amplitude
 * plus per-particle twinkle and depth-based fade/size. Colors come from the
 * persona config (server wins); the CSS OrbGlow supplies the halo, so beads
 * use saturated normal blending, which reads on the light Hearth stage where
 * additive/bloom would wash out.
 */

type Props = {
  vis: VisualizationSphereParticle;
  visualState: 'idle' | 'thinking' | 'speaking' | 'listening';
};

const GOLDEN = Math.PI * (3 - Math.sqrt(5));

function rand(i: number, j: number) {
  const t = Math.sin(i * 12.9898 + (j + 0.1) * 78.233) * 43758.5453;
  return t - Math.floor(t);
}

type Seed = {
  baseDir: THREE.Vector3;
  dist: number;
  orbitSpeed: number;
  animSpeed: number;
  vertSpeed: number;
  angle: number;
};

const STATE_TARGETS = {
  idle: { motion: 0.15, spin: 0.06, tint: 0.0 },
  listening: { motion: 0.8, spin: 0.0, tint: 0.55 },
  thinking: { motion: 0.5, spin: 0.0, tint: 0.35 },
  speaking: { motion: 0.7, spin: 0.0, tint: 0.7 },
} as const;

export default function VisionOrbScene({ vis, visualState }: Props) {
  const coreR = vis.sphere?.radius ?? 0.18;
  const ps = vis.particle_system;
  const count = Math.max(24, ps?.count ?? 96);
  const innerEdge = coreR + 0.04;
  const maxD = Math.max(Math.min(ps?.max_distance ?? coreR * 2.7, coreR * 3.2), innerEdge + 0.06);

  const meshRef = useRef<THREE.InstancedMesh>(null);
  const fieldRef = useRef<THREE.Group>(null);
  const eased = useRef({ motion: 0.15, spin: 0.06, tint: 0 });
  const positions = useRef<Float32Array>(new Float32Array(count * 3));
  const initialized = useRef(false);

  const seeds = useMemo<Seed[]>(() => {
    const out: Seed[] = [];
    for (let i = 0; i < count; i++) {
      const y = 1 - (2 * i + 1) / count;
      const r = Math.sqrt(Math.max(0, 1 - y * y));
      const theta = GOLDEN * i;
      out.push({
        baseDir: new THREE.Vector3(Math.cos(theta) * r, y, Math.sin(theta) * r),
        dist: innerEdge + rand(i, 1) * (maxD - innerEdge),
        orbitSpeed: 0.1 + rand(i, 2) * 0.3,
        animSpeed: 0.1 + rand(i, 3) * 0.5,
        vertSpeed: (rand(i, 4) - 0.5) * 0.4,
        angle: GOLDEN * i,
      });
    }
    initialized.current = false;
    return out;
  }, [count, innerEdge, maxD]);

  const baseColor = useMemo(() => {
    const c = ps?.color ?? { r: 1, g: 0.72, b: 0.3 };
    return new THREE.Color(c.r, c.g, c.b);
  }, [ps?.color]);
  const brightColor = useMemo(
    () => baseColor.clone().lerp(new THREE.Color('#FFF1DC'), 0.45),
    [baseColor]
  );

  const dummy = useMemo(() => new THREE.Object3D(), []);
  const tmpColor = useMemo(() => new THREE.Color(), []);
  const target = useMemo(() => new THREE.Vector3(), []);

  useFrame((st, dt) => {
    const mesh = meshRef.current;
    if (!mesh) return;
    const t = st.clock.elapsedTime;
    const k = Math.min(1, dt * 4);
    const goal = STATE_TARGETS[visualState];
    const e = eased.current;
    e.motion += (goal.motion - e.motion) * k;
    e.spin += (goal.spin - e.spin) * k;
    e.tint += (goal.tint - e.tint) * k;

    if (fieldRef.current) {
      if (visualState === 'idle') {
        fieldRef.current.rotation.y += e.spin * dt * Math.PI * 2;
      } else {
        fieldRef.current.rotation.y *= 1 - k; // unwind so rings/waveform sit straight
      }
    }

    const level = visualState === 'speaking' ? ttsPlayer.level() : 0;
    const pos = positions.current;

    for (let i = 0; i < count; i++) {
      const s = seeds[i];
      switch (visualState) {
        case 'listening': {
          s.angle += s.orbitSpeed * dt * 4;
          const d = maxD * (0.6 + 0.4 * Math.sin(t * s.animSpeed * 3 + i));
          target.set(
            Math.cos(s.angle) * d,
            Math.sin(t * s.vertSpeed * 3 + i) * 0.15 * maxD +
              Math.sin(t * 0.5 + s.angle) * 0.05 * maxD,
            Math.sin(s.angle) * d
          );
          break;
        }
        case 'thinking': {
          s.angle += s.orbitSpeed * dt * 8;
          const d = 0.8 * maxD;
          target.set(Math.cos(s.angle) * d, 0, Math.sin(s.angle) * d);
          break;
        }
        case 'speaking': {
          const halfW = 0.9 * maxD;
          const x = (i / Math.max(1, count - 1)) * 2 * halfW - halfW;
          const amp = (0.04 + 0.5 * level) * maxD;
          const phase = (x / maxD) * 6 + t * 7;
          target.set(
            x,
            amp * (0.7 * Math.sin(phase) + 0.3 * Math.sin(0.5 * phase + t * 3)),
            coreR + 0.06
          );
          break;
        }
        default: {
          const swell = 1 + 0.5 * e.motion * 0.3 + 0.04 * Math.sin(t * 1.2 + i * 0.4);
          target.copy(s.baseDir).multiplyScalar(s.dist * swell);
        }
      }

      const ix = i * 3;
      if (!initialized.current) {
        pos[ix] = target.x;
        pos[ix + 1] = target.y;
        pos[ix + 2] = target.z;
      } else {
        // morph between formations instead of teleporting
        pos[ix] += (target.x - pos[ix]) * Math.min(1, dt * 5);
        pos[ix + 1] += (target.y - pos[ix + 1]) * Math.min(1, dt * 5);
        pos[ix + 2] += (target.z - pos[ix + 2]) * Math.min(1, dt * 5);
      }

      const twinkle = 0.55 + 0.45 * Math.sin(t * (1 + s.animSpeed * 4) + i * 1.7);
      const depth = (pos[ix + 2] / maxD + 1) / 2; // front = 1, back = 0
      const sizeScale = (0.6 + 0.8 * depth) * (0.8 + 0.4 * twinkle);

      dummy.position.set(pos[ix], pos[ix + 1], pos[ix + 2]);
      dummy.scale.setScalar(sizeScale);
      dummy.updateMatrix();
      mesh.setMatrixAt(i, dummy.matrix);

      tmpColor
        .copy(baseColor)
        .lerp(brightColor, e.tint * 0.6 + 0.4 * twinkle)
        .multiplyScalar(0.55 + 0.45 * depth);
      mesh.setColorAt(i, tmpColor);
    }
    initialized.current = true;
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
  });

  const beadR = Math.max(ps?.particle_radius ?? 0.012, 0.008);

  return (
    <group ref={fieldRef}>
      <instancedMesh ref={meshRef} args={[undefined, undefined, count]} frustumCulled={false}>
        <sphereGeometry args={[beadR, 8, 8]} />
        <meshBasicMaterial toneMapped={false} />
      </instancedMesh>
    </group>
  );
}
