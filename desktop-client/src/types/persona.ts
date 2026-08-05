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

export type PersonaVisualization = VisualizationSphereParticle | VisualizationGlb;

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
