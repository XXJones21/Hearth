export type PersonaClassification = 'abstract' | 'realistic' | string;

export type Rgba = { r: number; g: number; b: number; a: number };

export type VisualizationSphereParticle = {
  type: 'sphere_particle';
  position: { x: number; y: number; z: number };
  scale: { x: number; y: number; z: number };
  sphere: {
    radius: number;
    color: Rgba;
    metallic: number;
    roughness: number;
  };
  particle_system: {
    enabled: boolean;
    count: number;
    particle_radius: number;
    max_distance: number;
    color: Rgba;
  };
  /**
   * `sulivan_dashed_aurora` — [dashed `Line2` with animated dash offset](https://varun.ca/three-js-particles/) over Catmull–Rom paths.
   * `sand_storm` (formerly `mentat_sand_storm`) - instanced dodecahedra.
   */
  layout_preset?: string;
  glb?: unknown;
  animations?: unknown;
};

export type VisualizationGlb = {
  type: 'glb_animated';
  position: { x: number; y: number; z: number };
  scale: { x: number; y: number; z: number };
  rotation?: { x: number; y: number; z: number };
  glb?: {
    asset_url?: string;
  };
  animations: Record<string, string>;
  layout_preset?: string;
  sphere?: unknown;
  particle_system?: { enabled: boolean };
};

/** Appearance only, roughly a dozen numbers. Every value is normalised
 *  against the head's own bounding box rather than pixels, so a face is
 *  resolution-independent and an expression written once means the same
 *  thing on a phone and a headset. Motion never lives here: expressions are
 *  deltas the harness ships, applied to whatever geometry a persona has.
 *
 *  The face is EYES-FIRST (the grok-bot register): two vertical capsules
 *  carry the whole character; there are no brows, and the mouth only
 *  appears when there is speech or a transient to perform.
 *  Doc: valinor wiki/clients/persona-face.md. */
export type FaceGeometry = {
  head_width: number;
  head_height: number;
  head_roundness: number;
  /** capsule width, as a fraction of the head's width */
  eye_size: number;
  eye_spacing: number;
  eye_height: number;
  /** capsule height as a multiple of its width; 1 is a dot, ~2.4 a tall pill */
  eye_length: number;
  /** resting parallel lean of both capsules, radians; usually 0 */
  eye_tilt: number;
  mouth_width: number;
  mouth_thickness: number;
  mouth_curve: number;
};

export type VisualizationProceduralFace = {
  type: 'procedural_face';
  /** Named starting point in personas/_visual/archetypes.json. Recorded for
   *  provenance; geometry below is already complete and wins. */
  archetype?: string;
  geometry: FaceGeometry;
  /* Colour is deliberately absent: the persona's state_colors and theme
     colour already govern every surface that follows it. */
  layout_preset?: string;
  glb?: unknown;
  sphere?: unknown;
  particle_system?: { enabled: boolean };
};

export type PersonaVisualization =
  | VisualizationSphereParticle
  | VisualizationGlb
  | VisualizationProceduralFace;

export type PersonaConfig = {
  name: string;
  version: string;
  description: string;
  classification: PersonaClassification;
  visualization: PersonaVisualization;
};

export type ListPersonaEntry = {
  name: string;
  description?: string;
  version?: string;
  visualization_type?: string;
  config_url: string;
};

export type StateUpdate = {
  state: 'transcribing' | 'deciding' | 'acting' | 'consulting';
  stage: string;
};
