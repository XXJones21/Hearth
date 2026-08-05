import { useEffect, useMemo, useRef } from 'react';
import { useAnimations, useGLTF } from '@react-three/drei';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import { SkeletonUtils } from 'three-stdlib';
import { resolvePersonaAssetUrl } from '../lib/resolveAssetUrl';
import type { PersonaConfig, VisualizationGlb } from '../types/persona';

type Props = {
  config: PersonaConfig;
  vis: VisualizationGlb;
  visualState: 'idle' | 'thinking' | 'speaking' | 'listening';
};

const stateToKey: Record<string, string> = {
  idle: 'idle',
  thinking: 'thinking',
  speaking: 'speaking',
  listening: 'listening',
};

export default function GlbScene({ config, vis, visualState }: Props) {
  const path =
    vis.glb?.asset_url ||
    vis.animations[stateToKey[visualState] || 'idle'] ||
    vis.animations.idle ||
    Object.values(vis.animations)[0];

  if (!path) {
    return (
      <mesh>
        <icosahedronGeometry args={[0.24, 1]} />
        <meshStandardMaterial color="#6688aa" wireframe />
      </mesh>
    );
  }

  const url = resolvePersonaAssetUrl(path, config.name);
  return (
    <GlbInner
      key={url}
      url={url}
      vis={vis}
      visualState={visualState}
    />
  );
}

type InnerProps = {
  url: string;
  vis: VisualizationGlb;
  visualState: 'idle' | 'thinking' | 'speaking' | 'listening';
};

function GlbInner({ url, vis, visualState }: InnerProps) {
  const group = useRef<THREE.Group>(null);
  const { scene, animations } = useGLTF(url);

  /* useGLTF caches one scene object per URL; skinned meshes must be cloned
     via SkeletonUtils so each mount gets a consistent mesh+skeleton graph
     that actually inherits this component's transforms (a shared cached
     scene keeps stale parent chains and the skeleton stops following). */
  const model = useMemo(() => SkeletonUtils.clone(scene), [scene]);
  const { actions, mixer } = useAnimations(animations, group);

  /* Manifest position/scale are tuned for the Quest/Android renderers, not
     this camera -- applied raw, a humanoid GLB lands tiny and off-frame.
     Auto-frame instead: fit the bounding box to the default camera
     (position [0, 0.15, 1.9], fov 42) and center it. Manifest rotation is
     still honored below so a model authored facing away can be corrected
     per-persona. Measured on the fresh unparented clone = clean local box. */
  const framing = useMemo(() => {
    const box = new THREE.Box3().setFromObject(model);
    const size = box.getSize(new THREE.Vector3());
    const center = box.getCenter(new THREE.Vector3());
    const maxDim = Math.max(size.x, size.y, size.z) || 1;
    const scale = 1.35 / maxDim;
    return {
      scale,
      offset: center.multiplyScalar(-scale),
    };
  }, [model]);

  useEffect(() => {
    const clipName = stateToKey[visualState] || 'idle';
    const act =
      actions[clipName] ||
      actions['idle'] ||
      Object.values(actions).find(Boolean);
    if (act) {
      act.reset().fadeIn(0.2).play();
    }
    return () => {
      if (act) {
        act.fadeOut(0.2);
      }
    };
  }, [actions, visualState]);

  /* The static box lies for animated skinned models: Selene's clip carries
     Spine.scale tracks that reshape the skeleton every frame, so the only
     truthful measurement is the POSED skeleton (the Android client learned
     the same: frame from skeleton bounds, not geometry). Wait out the
     T-pose -> idle fade (0.2s) before measuring or the box catches spread
     arms and under-frames; then fit ONCE by standing HEIGHT -- full-length
     mirror framing -- with a width guard for the narrow stage. */
  const fitted = useRef(false);
  const elapsed = useRef(0);

  useFrame((_st, dt) => {
    mixer?.update(dt);
    const g = group.current;
    if (fitted.current || !g) return;
    elapsed.current += dt;
    if (elapsed.current < 0.8) return;
    const box = new THREE.Box3();
    const v = new THREE.Vector3();
    let bones = 0;
    g.traverse((o) => {
      if ((o as THREE.Bone).isBone) {
        box.expandByPoint(o.getWorldPosition(v));
        bones += 1;
      }
    });
    fitted.current = true;
    if (bones < 2) return;
    const size = box.getSize(new THREE.Vector3());
    const center = box.getCenter(new THREE.Vector3());
    /* Camera z=1.9 fov=42 sees ~1.46 units of height at the origin. Fill
       ~92% of it; never exceed the panel's width. Bone spans undercount
       mesh volume (skirt, hair), hence the 1.15 width budget. */
    const k = Math.min(1.34 / (size.y || 1), 1.15 / (size.x || 1));
    g.scale.multiplyScalar(k);
    g.position.set(
      (g.position.x - center.x) * k,
      (g.position.y - center.y) * k,
      (g.position.z - center.z) * k,
    );
  });

  const rot = vis.rotation || { x: 0, y: 0, z: 0 };

  return (
    <group
      rotation={[
        THREE.MathUtils.degToRad(rot.x),
        THREE.MathUtils.degToRad(rot.y),
        THREE.MathUtils.degToRad(rot.z),
      ]}
    >
      <group
        ref={group}
        position={[framing.offset.x, framing.offset.y, framing.offset.z]}
        scale={framing.scale}
      >
        <primitive object={model} />
      </group>
    </group>
  );
}
