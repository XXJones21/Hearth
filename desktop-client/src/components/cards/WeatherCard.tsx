import type { CardProps, WeatherCardProps } from './types';

export function WeatherCard({ props }: CardProps) {
  const w = props as WeatherCardProps;
  if (!w.condition && !w.temp) return null;
  const hasTemp = w.temp !== undefined && w.temp !== null && String(w.temp) !== '';
  return (
    <div className="max-w-[560px] rounded-2xl border border-linen bg-fluff px-4 py-3 shadow-soft">
      <div className="mb-2 flex items-baseline gap-2">
        <span className="text-[11.5px] font-bold uppercase tracking-wider text-ember">
          {w.location ? `Weather · ${w.location}` : 'Weather'}
        </span>
        {w.day && <span className="ml-auto text-[11.5px] text-fawn">{w.day}</span>}
      </div>
      <div className="flex flex-wrap gap-5">
        <div>
          <div className="text-[21px] font-bold text-roast">{hasTemp ? w.temp : w.condition}</div>
          <div className="text-[11.5px] text-fawn">{hasTemp ? w.condition : 'expected'}</div>
        </div>
        {w.high !== undefined && (
          <div>
            <div className="text-[21px] font-bold text-roast">{w.high}</div>
            <div className="text-[11.5px] text-fawn">high</div>
          </div>
        )}
        {w.low !== undefined && (
          <div>
            <div className="text-[21px] font-bold text-roast">{w.low}</div>
            <div className="text-[11.5px] text-fawn">low</div>
          </div>
        )}
      </div>
    </div>
  );
}
