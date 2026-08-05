/*
 * ui_component card contracts, v1 (SUPPORTED_VERSION = 1).
 * Transcribed from the Valar emitters (Valar/valar/gateway/composer.py and
 * the tool handlers) and the Echo renderer (UiComponent.kt). These types are
 * the single source of truth for the beat-built card components -- beats
 * implement against these exact shapes and never invent fields.
 */

export const SUPPORTED_VERSION = 1;

export type ClockProps = {
  time: string;
  date?: string;
};

export type WeatherCardProps = {
  temp: string | number;
  condition: string;
  location?: string;
  high?: string | number;
  low?: string | number;
  day?: string;
};

export type TimerEntry = {
  label: string;
  /** epoch seconds, as a string, when the timer fires */
  fire_at: string;
  seconds: number;
};

export type TimerCardProps = {
  timers: TimerEntry[];
};

export type BriefTextProps = {
  title?: string;
  body: string;
};

export type SlideshowProps = {
  images: string[];
  interval_ms?: number;
};

export type CaptionsProps = {
  text: string;
};

export type TerminalCardProps = {
  title?: string;
  subtitle?: string;
  status?: 'running' | 'done' | 'error' | 'timeout' | 'blocked';
  /** markdown: prose, bullets, headings, fenced blocks */
  body: string;
  meta?: string[];
  /** commands the agent wrote but could not run itself */
  pending?: string[];
  /** what it actually did, one line per tool call */
  steps?: string[];
  /** present while the run can still change; the card polls /claude/state */
  run_id?: string;
};

export type ImageCardProps = {
  title?: string;
  /** what was asked for, shown as the caption */
  prompt?: string;
  status?: 'running' | 'done' | 'error';
  /** asset path, empty while the canvas is still blank */
  src?: string;
  /** why there is no picture, when status is error */
  note?: string;
  /** present while the drawing can still change; the card polls /imagery/state */
  job_id?: string;
};

export type GeneratedViewSection =
  | { kind: 'text'; body: string }
  | { kind: 'stat'; label: string; value: string }
  | { kind: 'stat_row'; stats: { label: string; value: string }[] }
  | { kind: 'image'; src: string }
  | { kind: 'divider' };

export type GeneratedViewProps = {
  template?: 'plain' | 'brief' | 'hero_stat' | 'comparison';
  title?: string;
  sections: GeneratedViewSection[];
};

/** Every card component receives its raw props object; components narrow it. */
export type CardProps = {
  props: Record<string, unknown>;
};
