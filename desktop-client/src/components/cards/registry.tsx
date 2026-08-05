import type { FC } from 'react';
import type { CardProps } from './types';
import { BriefTextCard } from './BriefTextCard';
import { CaptionsCard } from './CaptionsCard';
import { ClockCard } from './ClockCard';
import { GeneratedViewCard } from './GeneratedViewCard';
import { ImageCard } from './ImageCard';
import { SlideshowCard } from './SlideshowCard';
import { TerminalCard } from './TerminalCard';
import { TimerCard } from './TimerCard';
import { WeatherCard } from './WeatherCard';
// FORGE:IMPORTS -- the Card Forge scaffolder inserts commissioned-card
// imports above this line. Do not remove or hand-edit the marker.

/*
 * The when(type) registry (Echo DynamicComponent pattern): one component per
 * known card type, unknown types render nothing. Adding a card type = one
 * component file + one line here.
 */
export const CARD_REGISTRY: Record<string, FC<CardProps>> = {
  clock: ClockCard,
  weather_card: WeatherCard,
  timer_card: TimerCard,
  brief_text: BriefTextCard,
  slideshow: SlideshowCard,
  captions: CaptionsCard,
  terminal_card: TerminalCard,
  image_card: ImageCard,
  generated_view: GeneratedViewCard,
  // FORGE:REGISTER -- commissioned cards land above this line.
};

export function cardComponentFor(type: string): FC<CardProps> | null {
  return CARD_REGISTRY[type] ?? null;
}
