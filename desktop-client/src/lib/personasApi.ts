import { houseFetch } from './config';

/* The household. Every field exists in persona.json today; the server
   translates colours to hex and models to names so the client never sees a
   float triple or a filesystem path. */

export type PersonaVoice = {
  reference_audio: string;
  reference_text: string;
  test_line: string;
  voice_description: string;
  /** every wav already in their folder -- what Replace picks from */
  clips: string[];
  /** absolute path to their voice folder, for the file browser */
  folder: string;
};

export type PersonaRow = {
  key: string;
  name: string;
  description: string;
  classification: string;
  internal: boolean;
  system_prompt: string;
  voice: PersonaVoice;
  form: 'non_corporeal' | 'humanoid' | 'quadruped' | 'custom';
  type: string;
  preset: string;
  accent: string;
  state_colors: Record<string, string> | null;
  domains: string[];
  deny: string[];
  reasoning: boolean;
  rounds: number;
  model: string;
  temperature: number;
  n_ctx: number;
  /* No `tiers`. A persona once declared fast/deep/escalation models; the
     product kept one. escalation_model was dropped rather than carried across
     with a path nothing could resolve (see backend/manifest.yaml), and the
     surface has never sent the field. It stayed in this type as required,
     which is why nothing complained and why reading tiers.fast blanked the
     whole app: a type that lies is worse than no type at all. */
};

export type PersonasSurface = {
  personas: PersonaRow[];
  models: string[];
  domains: string[];
  forms: string[];
};

/** The voice fields that are writable. clips and folder are read-only facts. */
export type PersonaVoiceEdit = Partial<
  Pick<PersonaVoice, 'reference_audio' | 'reference_text' | 'test_line' | 'voice_description'>
>;

/** Only the fields the page owns. Everything else in the file is untouched. */
export type PersonaEdit = Partial<{
  name: string;
  description: string;
  system_prompt: string;
  voice: PersonaVoiceEdit;
  form: string;
  state_colors: Record<string, string>;
  domains: string[];
  reasoning: boolean;
  rounds: number;
  model: string;
  temperature: number;
}>;

export async function fetchPersonas(): Promise<PersonasSurface | null> {
  try {
    const res = await houseFetch(`/personas/surface`, { cache: 'no-store' });
    if (!res.ok) return null;
    return (await res.json()) as PersonasSurface;
  } catch {
    return null;
  }
}

/** Hear it. Renders the line on screen, saved or not, in the persona's voice.
 *
 * Returns the wav, or a string saying why there isn't one. The caller plays
 * it, because playback is where the persona's speaking state belongs. */
export async function fetchTestLine(req: {
  persona: string;
  text: string;
  reference_audio: string;
  reference_text: string;
}): Promise<ArrayBuffer | string> {
  try {
    const res = await houseFetch(`/personas/speak`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(req),
    });
    if (!res.ok) {
      const body = (await res.json().catch(() => null)) as { error?: string } | null;
      return body?.error || `The voice service answered ${res.status}.`;
    }
    return await res.arrayBuffer();
  } catch (err) {
    return err instanceof Error ? err.message : 'The voice service is unreachable.';
  }
}

export async function applyPersonas(payload: {
  edits: Record<string, PersonaEdit>;
  remove?: string[];
}): Promise<{ ok: boolean; changed?: string[]; restarting?: boolean; error?: string }> {
  try {
    const res = await houseFetch(`/personas/apply`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    return (await res.json()) as { ok: boolean; changed?: string[]; error?: string };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : 'unreachable' };
  }
}
