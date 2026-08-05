import { FC, useEffect, useState } from 'react';
import type { CardProps, SlideshowProps } from './types';
import { resolvePersonaAssetUrl } from '../../lib/resolveAssetUrl';

/* Beat: fills the SlideshowCard stub. Renders a slideshow of images with
   auto-advancing via setInterval, defaulting to 4000ms interval. */
export const SlideshowCard: FC<CardProps> = ({ props }) => {
  const slideshow = props as unknown as SlideshowProps;
  const { images, interval_ms = 4000 } = slideshow;
  const [index, setIndex] = useState(0);

  useEffect(() => {
    if (images.length === 0) return;

    const timer = setInterval(() => {
      setIndex((i) => (i + 1) % images.length);
    }, interval_ms);

    return () => clearInterval(timer);
  }, [images.length, interval_ms]);

  if (images.length === 0) return null;

  return (
    <img
      className="max-h-56 w-full rounded-xl object-cover"
      alt=""
      src={resolvePersonaAssetUrl(images[index], '')}
    />
  );
};
